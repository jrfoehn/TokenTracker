import Foundation

// MARK: - App Domain Models

enum Provider: String, CaseIterable, Codable, Identifiable {
    case openai = "OpenAI"
    case anthropic = "Anthropic"
    case bedrock = "AWS Bedrock"

    var id: String { rawValue }
}

struct ModelUsage: Identifiable {
    let id = UUID()
    let model: String
    let inputTokens: Int           // base (uncached) input
    let outputTokens: Int
    let cacheReadTokens: Int       // cache hits & refreshes
    let cacheWrite5mTokens: Int    // 5-minute cache writes
    let cacheWrite1hTokens: Int    // 1-hour cache writes
    let cost: Double
}

struct ProviderUsage: Identifiable {
    let id = UUID()
    let provider: Provider
    let totalInputTokens: Int
    let totalOutputTokens: Int
    let totalCacheReadTokens: Int
    let totalCacheWrite5mTokens: Int
    let totalCacheWrite1hTokens: Int
    let pastCost: Double        // actual from cost API (completed days)
    let todayCost: Double       // estimated from tokens (in-progress day)
    let totalCost: Double       // pastCost + todayCost
    let models: [ModelUsage]
    let fetchedAt: Date
}

struct DailyUsage: Identifiable {
    let id = UUID()
    let date: Date
    let cost: Double
    let inputTokens: Int
    let outputTokens: Int
}

// MARK: - Anthropic API Response Models

struct AnthropicUsageResponse: Codable {
    let data: [AnthropicUsageBucket]
    let hasMore: Bool?
    let nextPage: String?

    enum CodingKeys: String, CodingKey {
        case data
        case hasMore = "has_more"
        case nextPage = "next_page"
    }
}

struct AnthropicUsageBucket: Codable {
    let startingAt: String
    let endingAt: String
    let results: [AnthropicUsageResult]

    enum CodingKeys: String, CodingKey {
        case startingAt = "starting_at"
        case endingAt = "ending_at"
        case results
    }
}

struct AnthropicUsageResult: Codable {
    let uncachedInputTokens: Int?
    let outputTokens: Int?
    let cacheReadInputTokens: Int?
    let cacheCreation: AnthropicCacheCreation?
    let model: String?
    let workspaceId: String?
    let apiKeyId: String?
    let serviceTier: String?

    enum CodingKeys: String, CodingKey {
        case uncachedInputTokens = "uncached_input_tokens"
        case outputTokens = "output_tokens"
        case cacheReadInputTokens = "cache_read_input_tokens"
        case cacheCreation = "cache_creation"
        case model
        case workspaceId = "workspace_id"
        case apiKeyId = "api_key_id"
        case serviceTier = "service_tier"
    }
}

struct AnthropicCacheCreation: Codable {
    let ephemeral5mInputTokens: Int?
    let ephemeral1hInputTokens: Int?

    enum CodingKeys: String, CodingKey {
        case ephemeral5mInputTokens = "ephemeral_5m_input_tokens"
        case ephemeral1hInputTokens = "ephemeral_1h_input_tokens"
    }

    var totalTokens: Int {
        (ephemeral5mInputTokens ?? 0) + (ephemeral1hInputTokens ?? 0)
    }
}

// MARK: - Anthropic Cost API Response Models

struct AnthropicCostResponse: Codable {
    let data: [AnthropicCostBucket]
    let hasMore: Bool?
    let nextPage: String?

    enum CodingKeys: String, CodingKey {
        case data
        case hasMore = "has_more"
        case nextPage = "next_page"
    }
}

struct AnthropicCostBucket: Codable {
    let startingAt: String
    let endingAt: String
    let results: [AnthropicCostResult]

    enum CodingKeys: String, CodingKey {
        case startingAt = "starting_at"
        case endingAt = "ending_at"
        case results
    }
}

struct AnthropicCostResult: Codable {
    let amount: String?       // cents as decimal string, e.g. "123.45" = $1.2345
    let currency: String?
    let model: String?
    let costType: String?
    let description: String?
    let workspaceId: String?

    enum CodingKeys: String, CodingKey {
        case amount
        case currency
        case model
        case costType = "cost_type"
        case description
        case workspaceId = "workspace_id"
    }

    /// Amount is in cents (lowest currency units) as a decimal string
    var dollars: Double {
        guard let amount = amount, let cents = Double(amount) else { return 0 }
        return cents / 100.0
    }
}

// MARK: - OpenAI API Response Models

struct OpenAIUsageResponse: Codable {
    let object: String?
    let data: [OpenAIUsageBucket]
    let hasMore: Bool?
    let nextPage: String?

    enum CodingKeys: String, CodingKey {
        case object
        case data
        case hasMore = "has_more"
        case nextPage = "next_page"
    }
}

struct OpenAIUsageBucket: Codable {
    let object: String?
    let startTime: Int
    let endTime: Int
    let results: [OpenAIUsageResult]

    enum CodingKeys: String, CodingKey {
        case object
        case startTime = "start_time"
        case endTime = "end_time"
        case results
    }
}

struct OpenAIUsageResult: Codable {
    let inputTokens: Int?
    let outputTokens: Int?
    let numModelRequests: Int?
    let model: String?
    let inputCachedTokens: Int?

    enum CodingKeys: String, CodingKey {
        case inputTokens = "input_tokens"
        case outputTokens = "output_tokens"
        case numModelRequests = "num_model_requests"
        case model
        case inputCachedTokens = "input_cached_tokens"
    }
}

struct OpenAICostResponse: Codable {
    let object: String?
    let data: [OpenAICostBucket]
    let hasMore: Bool?
    let nextPage: String?

    enum CodingKeys: String, CodingKey {
        case object
        case data
        case hasMore = "has_more"
        case nextPage = "next_page"
    }
}

struct OpenAICostBucket: Codable {
    let object: String?
    let startTime: Int
    let endTime: Int
    let results: [OpenAICostResult]

    enum CodingKeys: String, CodingKey {
        case object
        case startTime = "start_time"
        case endTime = "end_time"
        case results
    }
}

struct OpenAICostResult: Codable {
    let amount: OpenAICostAmount?
    let lineItem: String?
    let projectId: String?

    enum CodingKeys: String, CodingKey {
        case amount
        case lineItem = "line_item"
        case projectId = "project_id"
    }
}

struct OpenAICostAmount: Codable {
    let value: Double
    let currency: String
}

// MARK: - Pricing (per million tokens)

struct ModelPricing {
    let inputPerMillion: Double
    let outputPerMillion: Double
    let cacheReadPerMillion: Double     // cache hits & refreshes (0.1x base for Anthropic)
    let cacheWrite5mPerMillion: Double  // 5-min cache writes (1.25x base for Anthropic)
    let cacheWrite1hPerMillion: Double  // 1-hour cache writes (2x base for Anthropic)

    func cost(uncachedInputTokens: Int, outputTokens: Int, cacheReadTokens: Int, cacheWrite5mTokens: Int, cacheWrite1hTokens: Int) -> Double {
        return (Double(uncachedInputTokens) / 1_000_000.0 * inputPerMillion)
             + (Double(outputTokens) / 1_000_000.0 * outputPerMillion)
             + (Double(cacheReadTokens) / 1_000_000.0 * cacheReadPerMillion)
             + (Double(cacheWrite5mTokens) / 1_000_000.0 * cacheWrite5mPerMillion)
             + (Double(cacheWrite1hTokens) / 1_000_000.0 * cacheWrite1hPerMillion)
    }
}

struct PricingTable {
    static let anthropic: [String: ModelPricing] = [
        "claude-opus-4-7":  ModelPricing(inputPerMillion: 5.0,  outputPerMillion: 25.0, cacheReadPerMillion: 0.50,  cacheWrite5mPerMillion: 6.25,  cacheWrite1hPerMillion: 10.0),
        "claude-opus-4-6":  ModelPricing(inputPerMillion: 5.0,  outputPerMillion: 25.0, cacheReadPerMillion: 0.50,  cacheWrite5mPerMillion: 6.25,  cacheWrite1hPerMillion: 10.0),
        "claude-opus-4-5":  ModelPricing(inputPerMillion: 5.0,  outputPerMillion: 25.0, cacheReadPerMillion: 0.50,  cacheWrite5mPerMillion: 6.25,  cacheWrite1hPerMillion: 10.0),
        "claude-opus-4-1":  ModelPricing(inputPerMillion: 15.0, outputPerMillion: 75.0, cacheReadPerMillion: 1.50,  cacheWrite5mPerMillion: 18.75, cacheWrite1hPerMillion: 30.0),
        "claude-opus-4":    ModelPricing(inputPerMillion: 15.0, outputPerMillion: 75.0, cacheReadPerMillion: 1.50,  cacheWrite5mPerMillion: 18.75, cacheWrite1hPerMillion: 30.0),
        "claude-sonnet-4-6":ModelPricing(inputPerMillion: 3.0,  outputPerMillion: 15.0, cacheReadPerMillion: 0.30,  cacheWrite5mPerMillion: 3.75,  cacheWrite1hPerMillion: 6.0),
        "claude-sonnet-4-5":ModelPricing(inputPerMillion: 3.0,  outputPerMillion: 15.0, cacheReadPerMillion: 0.30,  cacheWrite5mPerMillion: 3.75,  cacheWrite1hPerMillion: 6.0),
        "claude-sonnet-4":  ModelPricing(inputPerMillion: 3.0,  outputPerMillion: 15.0, cacheReadPerMillion: 0.30,  cacheWrite5mPerMillion: 3.75,  cacheWrite1hPerMillion: 6.0),
        "claude-haiku-4-5": ModelPricing(inputPerMillion: 1.0,  outputPerMillion: 5.0,  cacheReadPerMillion: 0.10,  cacheWrite5mPerMillion: 1.25,  cacheWrite1hPerMillion: 2.0),
        "claude-haiku-3-5": ModelPricing(inputPerMillion: 0.80, outputPerMillion: 4.0,  cacheReadPerMillion: 0.08,  cacheWrite5mPerMillion: 1.0,   cacheWrite1hPerMillion: 1.6),
    ]

    // OpenAI: cache read = 0.5x base, no separate 5m/1h distinction
    static let openai: [String: ModelPricing] = [
        "gpt-4o":      ModelPricing(inputPerMillion: 2.5,  outputPerMillion: 10.0, cacheReadPerMillion: 1.25,  cacheWrite5mPerMillion: 2.5,  cacheWrite1hPerMillion: 2.5),
        "gpt-4o-mini": ModelPricing(inputPerMillion: 0.15, outputPerMillion: 0.60, cacheReadPerMillion: 0.075, cacheWrite5mPerMillion: 0.15, cacheWrite1hPerMillion: 0.15),
        "gpt-4-turbo": ModelPricing(inputPerMillion: 10.0, outputPerMillion: 30.0, cacheReadPerMillion: 5.0,   cacheWrite5mPerMillion: 10.0, cacheWrite1hPerMillion: 10.0),
        "o1":          ModelPricing(inputPerMillion: 15.0, outputPerMillion: 60.0, cacheReadPerMillion: 7.5,   cacheWrite5mPerMillion: 15.0, cacheWrite1hPerMillion: 15.0),
        "o3":          ModelPricing(inputPerMillion: 10.0, outputPerMillion: 40.0, cacheReadPerMillion: 2.5,   cacheWrite5mPerMillion: 10.0, cacheWrite1hPerMillion: 10.0),
        "o3-mini":     ModelPricing(inputPerMillion: 1.10, outputPerMillion: 4.40, cacheReadPerMillion: 0.55,  cacheWrite5mPerMillion: 1.10, cacheWrite1hPerMillion: 1.10),
        "o4-mini":     ModelPricing(inputPerMillion: 1.10, outputPerMillion: 4.40, cacheReadPerMillion: 0.55,  cacheWrite5mPerMillion: 1.10, cacheWrite1hPerMillion: 1.10),
    ]

    // Bedrock IDs look like "anthropic.claude-sonnet-4-20250514-v1:0" or
    // "us.anthropic.claude-sonnet-4-20250514-v1:0" for cross-region inference profiles.
    // Cache read/write on Bedrock: reads ≈ 0.1x base, writes ≈ same as base (no 5m/1h split).
    static let bedrock: [String: ModelPricing] = [
        "anthropic.claude-opus-4":     ModelPricing(inputPerMillion: 15.0, outputPerMillion: 75.0, cacheReadPerMillion: 1.50, cacheWrite5mPerMillion: 15.0,  cacheWrite1hPerMillion: 15.0),
        "anthropic.claude-sonnet-4":   ModelPricing(inputPerMillion: 3.0,  outputPerMillion: 15.0, cacheReadPerMillion: 0.30, cacheWrite5mPerMillion: 3.0,   cacheWrite1hPerMillion: 3.0),
        "anthropic.claude-haiku-4":    ModelPricing(inputPerMillion: 1.0,  outputPerMillion: 5.0,  cacheReadPerMillion: 0.10, cacheWrite5mPerMillion: 1.0,   cacheWrite1hPerMillion: 1.0),
        "anthropic.claude-3-5-sonnet": ModelPricing(inputPerMillion: 3.0,  outputPerMillion: 15.0, cacheReadPerMillion: 0.30, cacheWrite5mPerMillion: 3.0,   cacheWrite1hPerMillion: 3.0),
        "anthropic.claude-3-5-haiku":  ModelPricing(inputPerMillion: 0.80, outputPerMillion: 4.0,  cacheReadPerMillion: 0.08, cacheWrite5mPerMillion: 0.80,  cacheWrite1hPerMillion: 0.80),
        "anthropic.claude-3-opus":     ModelPricing(inputPerMillion: 15.0, outputPerMillion: 75.0, cacheReadPerMillion: 1.50, cacheWrite5mPerMillion: 15.0,  cacheWrite1hPerMillion: 15.0),
        "anthropic.claude-3-sonnet":   ModelPricing(inputPerMillion: 3.0,  outputPerMillion: 15.0, cacheReadPerMillion: 0.30, cacheWrite5mPerMillion: 3.0,   cacheWrite1hPerMillion: 3.0),
        "anthropic.claude-3-haiku":    ModelPricing(inputPerMillion: 0.25, outputPerMillion: 1.25, cacheReadPerMillion: 0.03, cacheWrite5mPerMillion: 0.25,  cacheWrite1hPerMillion: 0.25),
        "amazon.nova-pro":             ModelPricing(inputPerMillion: 0.80, outputPerMillion: 3.20, cacheReadPerMillion: 0.20, cacheWrite5mPerMillion: 0.80,  cacheWrite1hPerMillion: 0.80),
        "amazon.nova-lite":            ModelPricing(inputPerMillion: 0.06, outputPerMillion: 0.24, cacheReadPerMillion: 0.015,cacheWrite5mPerMillion: 0.06,  cacheWrite1hPerMillion: 0.06),
        "amazon.nova-micro":           ModelPricing(inputPerMillion: 0.035,outputPerMillion: 0.14, cacheReadPerMillion: 0.009,cacheWrite5mPerMillion: 0.035, cacheWrite1hPerMillion: 0.035),
        "meta.llama3-3-70b":           ModelPricing(inputPerMillion: 0.72, outputPerMillion: 0.72, cacheReadPerMillion: 0.72, cacheWrite5mPerMillion: 0.72,  cacheWrite1hPerMillion: 0.72),
        "mistral.mistral-large":       ModelPricing(inputPerMillion: 2.0,  outputPerMillion: 6.0,  cacheReadPerMillion: 2.0,  cacheWrite5mPerMillion: 2.0,   cacheWrite1hPerMillion: 2.0),
    ]

    static let defaultPricing = ModelPricing(inputPerMillion: 3.0, outputPerMillion: 15.0, cacheReadPerMillion: 0.30, cacheWrite5mPerMillion: 3.75, cacheWrite1hPerMillion: 6.0)

    static func pricing(for model: String, provider: Provider) -> ModelPricing {
        let table: [String: ModelPricing]
        switch provider {
        case .anthropic: table = anthropic
        case .openai:    table = openai
        case .bedrock:   table = bedrock
        }
        if let p = table[model] { return p }
        // Strip cross-region prefixes like "us." / "eu." / "apac." for Bedrock IDs.
        let normalized = stripRegionPrefix(model)
        for (key, p) in table {
            if normalized.contains(key) { return p }
        }
        return defaultPricing
    }

    private static func stripRegionPrefix(_ id: String) -> String {
        for prefix in ["us.", "eu.", "apac.", "us-gov."] where id.hasPrefix(prefix) {
            return String(id.dropFirst(prefix.count))
        }
        return id
    }
}
