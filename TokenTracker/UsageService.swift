import Foundation
import os

private let logger = Logger(subsystem: "com.tokentracker.app", category: "usage")

private func log(_ msg: String) {
    logger.info("\(msg)")
    let logFile = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".tokentracker.log")
    let line = "\(ISO8601DateFormatter().string(from: Date())) \(msg)\n"
    if let data = line.data(using: .utf8) {
        if FileManager.default.fileExists(atPath: logFile.path) {
            if let handle = try? FileHandle(forWritingTo: logFile) {
                handle.seekToEndOfFile()
                handle.write(data)
                handle.closeFile()
            }
        } else {
            try? data.write(to: logFile)
        }
    }
}

actor UsageService {
    static let shared = UsageService()

    private let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        return URLSession(configuration: config)
    }()

    // MARK: - Anthropic

    func fetchAnthropicUsage(days: Int = 7) async throws -> ProviderUsage {
        guard let apiKey = KeychainHelper.anthropicKey, !apiKey.isEmpty else {
            throw UsageError.noApiKey(.anthropic)
        }

        let now = Date()
        let calendar = Calendar(identifier: .gregorian)
        let startDate = calendar.date(byAdding: .day, value: -days, to: now)!
        // Today's start in UTC for the intraday query
        let todayStart = calendar.startOfDay(for: now)
        let endDate = calendar.date(byAdding: .day, value: 1, to: now)!

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        let startStr = formatter.string(from: startDate)
        let endStr = formatter.string(from: endDate)
        let todayStartStr = formatter.string(from: todayStart)
        let todayEndStr = formatter.string(from: endDate)

        // Fetch past days at 1d granularity (completed buckets)
        var usageComponents = URLComponents(string: "https://api.anthropic.com/v1/organizations/usage_report/messages")!
        usageComponents.queryItems = [
            URLQueryItem(name: "starting_at", value: startStr),
            URLQueryItem(name: "ending_at", value: endStr),
            URLQueryItem(name: "group_by[]", value: "model"),
            URLQueryItem(name: "bucket_width", value: "1d"),
            URLQueryItem(name: "limit", value: "31"),
        ]

        // Fetch daily usage (completed days) + today's usage at 1h granularity
        let modelParam = [URLQueryItem(name: "group_by[]", value: "model")]

        let dailyBuckets = try await fetchAnthropicPaginated(
            baseURL: "https://api.anthropic.com/v1/organizations/usage_report/messages",
            startStr: startStr,
            endStr: endStr,
            apiKey: apiKey,
            extraParams: modelParam,
            type: AnthropicUsageResponse.self
        )

        // Today's in-progress data (1h granularity captures current day)
        let todayBuckets = try await fetchAnthropicPaginated(
            baseURL: "https://api.anthropic.com/v1/organizations/usage_report/messages",
            startStr: todayStartStr,
            endStr: todayEndStr,
            apiKey: apiKey,
            extraParams: modelParam,
            type: AnthropicUsageResponse.self,
            bucketWidth: "1h"
        )

        // Merge: use daily buckets + today's hourly buckets (daily won't have today)
        let usageReport = dailyBuckets + todayBuckets

        // Fetch cost report (no group_by for simple totals, with pagination)
        let costBuckets = await fetchAnthropicCosts(apiKey: apiKey, startStr: startStr, endStr: endStr)

        // Also fetch costs grouped by description to get per-model breakdown
        let costByModelBuckets = await fetchAnthropicCosts(
            apiKey: apiKey, startStr: startStr, endStr: endStr,
            extraParams: [URLQueryItem(name: "group_by[]", value: "description")]
        )

        // Past days: actual cost from cost API
        var pastDaysCost: Double = 0
        for bucket in costBuckets {
            for result in bucket.results {
                pastDaysCost += result.dollars
            }
        }

        // Per-model cost map from grouped cost query (past days only)
        var costByModel: [String: Double] = [:]
        for bucket in costByModelBuckets {
            for result in bucket.results {
                if let model = result.model {
                    costByModel[model, default: 0] += result.dollars
                }
            }
        }

        // Aggregate ALL tokens by model (past + today)
        var modelAgg: [String: (input: Int, output: Int, cacheRead: Int, cacheWrite5m: Int, cacheWrite1h: Int)] = [:]
        for bucket in usageReport {
            for result in bucket.results {
                let model = result.model ?? "unknown"
                var current = modelAgg[model, default: (0, 0, 0, 0, 0)]
                current.input += result.uncachedInputTokens ?? 0
                current.output += result.outputTokens ?? 0
                current.cacheRead += result.cacheReadInputTokens ?? 0
                current.cacheWrite5m += result.cacheCreation?.ephemeral5mInputTokens ?? 0
                current.cacheWrite1h += result.cacheCreation?.ephemeral1hInputTokens ?? 0
                modelAgg[model] = current
            }
        }

        // Aggregate today's tokens separately for cost estimation
        var todayAgg: [String: (input: Int, output: Int, cacheRead: Int, cacheWrite5m: Int, cacheWrite1h: Int)] = [:]
        for bucket in todayBuckets {
            for result in bucket.results {
                let model = result.model ?? "unknown"
                var current = todayAgg[model, default: (0, 0, 0, 0, 0)]
                current.input += result.uncachedInputTokens ?? 0
                current.output += result.outputTokens ?? 0
                current.cacheRead += result.cacheReadInputTokens ?? 0
                current.cacheWrite5m += result.cacheCreation?.ephemeral5mInputTokens ?? 0
                current.cacheWrite1h += result.cacheCreation?.ephemeral1hInputTokens ?? 0
                todayAgg[model] = current
            }
        }

        // Estimate today's cost from tokens (cost API doesn't have in-progress day)
        var todayEstimatedCost: Double = 0
        for (model, tokens) in todayAgg {
            let pricing = PricingTable.pricing(for: model, provider: .anthropic)
            todayEstimatedCost += pricing.cost(
                uncachedInputTokens: tokens.input,
                outputTokens: tokens.output,
                cacheReadTokens: tokens.cacheRead,
                cacheWrite5mTokens: tokens.cacheWrite5m,
                cacheWrite1hTokens: tokens.cacheWrite1h
            )
        }

        // Total cost = actual past + estimated today
        let totalCost = pastDaysCost + todayEstimatedCost

        let models = modelAgg.map { (model, tokens) -> ModelUsage in
            let actualCost = costByModel[model]
            let pricing = PricingTable.pricing(for: model, provider: .anthropic)
            let todayTokens = todayAgg[model, default: (0, 0, 0, 0, 0)]
            let todayCost = pricing.cost(
                uncachedInputTokens: todayTokens.input,
                outputTokens: todayTokens.output,
                cacheReadTokens: todayTokens.cacheRead,
                cacheWrite5mTokens: todayTokens.cacheWrite5m,
                cacheWrite1hTokens: todayTokens.cacheWrite1h
            )
            let cost = (actualCost ?? 0) + todayCost
            return ModelUsage(
                model: model,
                inputTokens: tokens.input,
                outputTokens: tokens.output,
                cacheReadTokens: tokens.cacheRead,
                cacheWrite5mTokens: tokens.cacheWrite5m,
                cacheWrite1hTokens: tokens.cacheWrite1h,
                cost: cost
            )
        }.sorted { $0.cost > $1.cost }

        let totalInput = models.reduce(0) { $0 + $1.inputTokens }
        let totalOutput = models.reduce(0) { $0 + $1.outputTokens }
        let totalCacheRead = models.reduce(0) { $0 + $1.cacheReadTokens }
        let totalCacheWrite5m = models.reduce(0) { $0 + $1.cacheWrite5mTokens }
        let totalCacheWrite1h = models.reduce(0) { $0 + $1.cacheWrite1hTokens }

        log("[TokenTracker] Anthropic tokens - input=\(totalInput), output=\(totalOutput), cacheRead=\(totalCacheRead), cacheWrite5m=\(totalCacheWrite5m), cacheWrite1h=\(totalCacheWrite1h)")
        log("[TokenTracker] Anthropic cost - pastActual=$\(pastDaysCost), todayEstimated=$\(todayEstimatedCost), total=$\(totalCost)")

        return ProviderUsage(
            provider: .anthropic,
            totalInputTokens: totalInput,
            totalOutputTokens: totalOutput,
            totalCacheReadTokens: totalCacheRead,
            totalCacheWrite5mTokens: totalCacheWrite5m,
            totalCacheWrite1hTokens: totalCacheWrite1h,
            pastCost: pastDaysCost,
            todayCost: todayEstimatedCost,
            totalCost: totalCost,
            models: models,
            fetchedAt: Date()
        )
    }

    // MARK: - OpenAI

    func fetchOpenAIUsage(days: Int = 7) async throws -> ProviderUsage {
        guard let apiKey = KeychainHelper.openAIKey, !apiKey.isEmpty else {
            throw UsageError.noApiKey(.openai)
        }

        let now = Date()
        let startDate = Calendar.current.date(byAdding: .day, value: -days, to: now)!
        let startTime = Int(startDate.timeIntervalSince1970)

        // Fetch usage grouped by model
        var components = URLComponents(string: "https://api.openai.com/v1/organization/usage/completions")!
        components.queryItems = [
            URLQueryItem(name: "start_time", value: "\(startTime)"),
            URLQueryItem(name: "bucket_width", value: "1d"),
            URLQueryItem(name: "group_by[]", value: "model"),
        ]

        var request = URLRequest(url: components.url!)
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await session.data(for: request)
        try validateResponse(response, data: data, provider: .openai)

        let usageResponse = try JSONDecoder().decode(OpenAIUsageResponse.self, from: data)

        // Aggregate by model
        var modelAgg: [String: (input: Int, output: Int, cacheRead: Int)] = [:]
        for bucket in usageResponse.data {
            for result in bucket.results {
                let model = result.model ?? "unknown"
                var current = modelAgg[model, default: (0, 0, 0)]
                current.input += result.inputTokens ?? 0
                current.output += result.outputTokens ?? 0
                current.cacheRead += result.inputCachedTokens ?? 0
                modelAgg[model] = current
            }
        }

        // Also try to get cost data
        var costByModel: [String: Double] = [:]
        if let costs = try? await fetchOpenAICosts(apiKey: apiKey, startTime: startTime) {
            for bucket in costs.data {
                for result in bucket.results {
                    let key = result.lineItem ?? "unknown"
                    costByModel[key, default: 0] += result.amount?.value ?? 0
                }
            }
        }

        let models = modelAgg.map { (model, tokens) -> ModelUsage in
            let pricing = PricingTable.pricing(for: model, provider: .openai)
            let estimatedCost = pricing.cost(
                uncachedInputTokens: tokens.input,
                outputTokens: tokens.output,
                cacheReadTokens: tokens.cacheRead,
                cacheWrite5mTokens: 0,
                cacheWrite1hTokens: 0
            )
            return ModelUsage(
                model: model,
                inputTokens: tokens.input,
                outputTokens: tokens.output,
                cacheReadTokens: tokens.cacheRead,
                cacheWrite5mTokens: 0,
                cacheWrite1hTokens: 0,
                cost: estimatedCost
            )
        }.sorted { $0.cost > $1.cost }

        let totalInput = models.reduce(0) { $0 + $1.inputTokens }
        let totalOutput = models.reduce(0) { $0 + $1.outputTokens }
        let totalCacheRead = models.reduce(0) { $0 + $1.cacheReadTokens }
        let actualTotal = costByModel.values.reduce(0, +)
        let totalCost = actualTotal > 0 ? actualTotal : models.reduce(0.0) { $0 + $1.cost }

        return ProviderUsage(
            provider: .openai,
            totalInputTokens: totalInput,
            totalOutputTokens: totalOutput,
            totalCacheReadTokens: totalCacheRead,
            totalCacheWrite5mTokens: 0,
            totalCacheWrite1hTokens: 0,
            pastCost: totalCost,
            todayCost: 0,
            totalCost: totalCost,
            models: models,
            fetchedAt: Date()
        )
    }

    private func fetchOpenAICosts(apiKey: String, startTime: Int) async throws -> OpenAICostResponse {
        var components = URLComponents(string: "https://api.openai.com/v1/organization/costs")!
        components.queryItems = [
            URLQueryItem(name: "start_time", value: "\(startTime)"),
            URLQueryItem(name: "bucket_width", value: "1d"),
        ]

        var request = URLRequest(url: components.url!)
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await session.data(for: request)
        try validateResponse(response, data: data, provider: .openai)
        return try JSONDecoder().decode(OpenAICostResponse.self, from: data)
    }

    // MARK: - Anthropic Pagination Helpers

    private func fetchAnthropicPaginated<T: Codable>(
        baseURL: String,
        startStr: String,
        endStr: String,
        apiKey: String,
        extraParams: [URLQueryItem] = [],
        type: T.Type,
        bucketWidth: String = "1d"
    ) async throws -> [AnthropicUsageBucket] {
        let limit = bucketWidth == "1h" ? "168" : bucketWidth == "1m" ? "1440" : "31"
        var allBuckets: [AnthropicUsageBucket] = []
        var page: String? = nil

        while true {
            var components = URLComponents(string: baseURL)!
            var queryItems = [
                URLQueryItem(name: "starting_at", value: startStr),
                URLQueryItem(name: "ending_at", value: endStr),
                URLQueryItem(name: "bucket_width", value: bucketWidth),
                URLQueryItem(name: "limit", value: limit),
            ] + extraParams

            if let page = page {
                queryItems.append(URLQueryItem(name: "page", value: page))
            }
            components.queryItems = queryItems

            var request = URLRequest(url: components.url!)
            request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
            request.setValue(apiKey, forHTTPHeaderField: "x-api-key")

            let (data, response) = try await session.data(for: request)
            try validateResponse(response, data: data, provider: .anthropic)

            let decoded = try JSONDecoder().decode(AnthropicUsageResponse.self, from: data)
            allBuckets.append(contentsOf: decoded.data)

            if decoded.hasMore == true, let nextPage = decoded.nextPage {
                page = nextPage
            } else {
                break
            }
        }
        return allBuckets
    }

    private func fetchAnthropicCosts(
        apiKey: String,
        startStr: String,
        endStr: String,
        extraParams: [URLQueryItem] = [],
        bucketWidth: String = "1d"
    ) async -> [AnthropicCostBucket] {
        var allBuckets: [AnthropicCostBucket] = []
        var page: String? = nil

        do {
            while true {
                var components = URLComponents(string: "https://api.anthropic.com/v1/organizations/cost_report")!
                var queryItems = [
                    URLQueryItem(name: "starting_at", value: startStr),
                    URLQueryItem(name: "ending_at", value: endStr),
                    URLQueryItem(name: "bucket_width", value: "1d"),
                    URLQueryItem(name: "limit", value: "31"),
                ] + extraParams

                if let page = page {
                    queryItems.append(URLQueryItem(name: "page", value: page))
                }
                components.queryItems = queryItems

                var request = URLRequest(url: components.url!)
                request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
                request.setValue(apiKey, forHTTPHeaderField: "x-api-key")

                let (data, response) = try await session.data(for: request)
                try validateResponse(response, data: data, provider: .anthropic)

                let decoded = try JSONDecoder().decode(AnthropicCostResponse.self, from: data)
                allBuckets.append(contentsOf: decoded.data)

                if decoded.hasMore == true, let nextPage = decoded.nextPage {
                    page = nextPage
                } else {
                    break
                }
            }
        } catch {
            // Cost API failure is non-fatal, we fall back to estimated costs
        }
        return allBuckets
    }

    // MARK: - Helpers

    private func validateResponse(_ response: URLResponse, data: Data, provider: Provider) throws {
        guard let http = response as? HTTPURLResponse else {
            throw UsageError.networkError("Invalid response")
        }
        guard (200...299).contains(http.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? "No body"
            throw UsageError.apiError(provider, statusCode: http.statusCode, message: body)
        }
    }
}

enum UsageError: LocalizedError {
    case noApiKey(Provider)
    case networkError(String)
    case apiError(Provider, statusCode: Int, message: String)

    var errorDescription: String? {
        switch self {
        case .noApiKey(let p):
            return "No admin API key configured for \(p.rawValue). Add it in Settings."
        case .networkError(let msg):
            return "Network error: \(msg)"
        case .apiError(let p, let code, let msg):
            return "\(p.rawValue) API error (\(code)): \(msg)"
        }
    }
}
