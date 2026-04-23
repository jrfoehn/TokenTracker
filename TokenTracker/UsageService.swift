import Foundation

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
        let startDate = Calendar.current.date(byAdding: .day, value: -days, to: now)!

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        let startStr = formatter.string(from: startDate)
        let endStr = formatter.string(from: now)

        // Fetch usage grouped by model
        var components = URLComponents(string: "https://api.anthropic.com/v1/organizations/usage_report/messages")!
        components.queryItems = [
            URLQueryItem(name: "starting_at", value: startStr),
            URLQueryItem(name: "ending_at", value: endStr),
            URLQueryItem(name: "group_by[]", value: "model"),
            URLQueryItem(name: "bucket_width", value: "1d"),
        ]

        var request = URLRequest(url: components.url!)
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")

        let (data, response) = try await session.data(for: request)
        try validateResponse(response, data: data, provider: .anthropic)

        let usageResponse = try JSONDecoder().decode(AnthropicUsageResponse.self, from: data)

        // Aggregate by model
        var modelAgg: [String: (input: Int, output: Int, cached: Int)] = [:]
        for bucket in usageResponse.data {
            let model = bucket.model ?? "unknown"
            var current = modelAgg[model, default: (0, 0, 0)]
            current.input += bucket.inputTokens ?? 0
            current.output += bucket.outputTokens ?? 0
            current.cached += (bucket.inputCachedTokens ?? 0) + (bucket.cacheCreationTokens ?? 0)
            modelAgg[model] = current
        }

        let models = modelAgg.map { (model, tokens) -> ModelUsage in
            let pricing = PricingTable.pricing(for: model, provider: .anthropic)
            return ModelUsage(
                model: model,
                inputTokens: tokens.input,
                outputTokens: tokens.output,
                cachedTokens: tokens.cached,
                cost: pricing.cost(inputTokens: tokens.input, outputTokens: tokens.output, cachedTokens: tokens.cached)
            )
        }.sorted { $0.cost > $1.cost }

        let totalInput = models.reduce(0) { $0 + $1.inputTokens }
        let totalOutput = models.reduce(0) { $0 + $1.outputTokens }
        let totalCached = models.reduce(0) { $0 + $1.cachedTokens }
        let totalCost = models.reduce(0.0) { $0 + $1.cost }

        return ProviderUsage(
            provider: .anthropic,
            totalInputTokens: totalInput,
            totalOutputTokens: totalOutput,
            totalCachedTokens: totalCached,
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
        var modelAgg: [String: (input: Int, output: Int, cached: Int)] = [:]
        for bucket in usageResponse.data {
            for result in bucket.results {
                let model = result.model ?? "unknown"
                var current = modelAgg[model, default: (0, 0, 0)]
                current.input += result.inputTokens ?? 0
                current.output += result.outputTokens ?? 0
                current.cached += result.inputCachedTokens ?? 0
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
            let estimatedCost = pricing.cost(inputTokens: tokens.input, outputTokens: tokens.output, cachedTokens: tokens.cached)
            return ModelUsage(
                model: model,
                inputTokens: tokens.input,
                outputTokens: tokens.output,
                cachedTokens: tokens.cached,
                cost: estimatedCost
            )
        }.sorted { $0.cost > $1.cost }

        let totalInput = models.reduce(0) { $0 + $1.inputTokens }
        let totalOutput = models.reduce(0) { $0 + $1.outputTokens }
        let totalCached = models.reduce(0) { $0 + $1.cachedTokens }
        // Use actual cost if available, otherwise use estimated
        let actualTotal = costByModel.values.reduce(0, +)
        let totalCost = actualTotal > 0 ? actualTotal : models.reduce(0.0) { $0 + $1.cost }

        return ProviderUsage(
            provider: .openai,
            totalInputTokens: totalInput,
            totalOutputTokens: totalOutput,
            totalCachedTokens: totalCached,
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
