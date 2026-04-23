import Foundation

// MARK: - App Domain Models

enum Provider: String, CaseIterable, Codable, Identifiable {
    case openai = "OpenAI"
    case anthropic = "Anthropic"

    var id: String { rawValue }
}

struct ModelUsage: Identifiable {
    let id = UUID()
    let model: String
    let inputTokens: Int
    let outputTokens: Int
    let cachedTokens: Int
    let cost: Double
}

struct ProviderUsage: Identifiable {
    let id = UUID()
    let provider: Provider
    let totalInputTokens: Int
    let totalOutputTokens: Int
    let totalCachedTokens: Int
    let totalCost: Double
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
    let startTime: String
    let endTime: String
    let inputTokens: Int?
    let outputTokens: Int?
    let inputCachedTokens: Int?
    let cacheCreationTokens: Int?
    let model: String?
    let workspaceId: String?

    enum CodingKeys: String, CodingKey {
        case startTime = "start_time"
        case endTime = "end_time"
        case inputTokens = "input_tokens"
        case outputTokens = "output_tokens"
        case inputCachedTokens = "input_cached_tokens"
        case cacheCreationTokens = "cache_creation_tokens"
        case model
        case workspaceId = "workspace_id"
    }
}

struct AnthropicCostResponse: Codable {
    let data: [AnthropicCostBucket]
    let hasMore: Bool?

    enum CodingKeys: String, CodingKey {
        case data
        case hasMore = "has_more"
    }
}

struct AnthropicCostBucket: Codable {
    let startTime: String
    let endTime: String
    let costs: AnthropicCostBreakdown?

    enum CodingKeys: String, CodingKey {
        case startTime = "start_time"
        case endTime = "end_time"
        case costs
    }
}

struct AnthropicCostBreakdown: Codable {
    let amount: String?
    let currency: String?
    let description: String?
    let workspaceId: String?

    enum CodingKeys: String, CodingKey {
        case amount
        case currency
        case description
        case workspaceId = "workspace_id"
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
    let cachedInputPerMillion: Double

    func cost(inputTokens: Int, outputTokens: Int, cachedTokens: Int) -> Double {
        let uncachedInput = max(0, inputTokens - cachedTokens)
        return (Double(uncachedInput) / 1_000_000.0 * inputPerMillion)
             + (Double(outputTokens) / 1_000_000.0 * outputPerMillion)
             + (Double(cachedTokens) / 1_000_000.0 * cachedInputPerMillion)
    }
}

struct PricingTable {
    static let anthropic: [String: ModelPricing] = [
        "claude-opus-4-6": ModelPricing(inputPerMillion: 5.0, outputPerMillion: 25.0, cachedInputPerMillion: 0.5),
        "claude-sonnet-4-6": ModelPricing(inputPerMillion: 3.0, outputPerMillion: 15.0, cachedInputPerMillion: 0.3),
        "claude-haiku-4-5": ModelPricing(inputPerMillion: 1.0, outputPerMillion: 5.0, cachedInputPerMillion: 0.1),
        "claude-sonnet-4-5": ModelPricing(inputPerMillion: 3.0, outputPerMillion: 15.0, cachedInputPerMillion: 0.3),
        "claude-opus-4-5": ModelPricing(inputPerMillion: 5.0, outputPerMillion: 25.0, cachedInputPerMillion: 0.5),
    ]

    static let openai: [String: ModelPricing] = [
        "gpt-4o": ModelPricing(inputPerMillion: 2.5, outputPerMillion: 10.0, cachedInputPerMillion: 1.25),
        "gpt-4o-mini": ModelPricing(inputPerMillion: 0.15, outputPerMillion: 0.60, cachedInputPerMillion: 0.075),
        "gpt-4-turbo": ModelPricing(inputPerMillion: 10.0, outputPerMillion: 30.0, cachedInputPerMillion: 5.0),
        "o1": ModelPricing(inputPerMillion: 15.0, outputPerMillion: 60.0, cachedInputPerMillion: 7.5),
        "o1-mini": ModelPricing(inputPerMillion: 1.10, outputPerMillion: 4.40, cachedInputPerMillion: 0.55),
        "o3": ModelPricing(inputPerMillion: 10.0, outputPerMillion: 40.0, cachedInputPerMillion: 2.5),
        "o3-mini": ModelPricing(inputPerMillion: 1.10, outputPerMillion: 4.40, cachedInputPerMillion: 0.55),
        "o4-mini": ModelPricing(inputPerMillion: 1.10, outputPerMillion: 4.40, cachedInputPerMillion: 0.55),
    ]

    static let defaultPricing = ModelPricing(inputPerMillion: 3.0, outputPerMillion: 15.0, cachedInputPerMillion: 0.3)

    static func pricing(for model: String, provider: Provider) -> ModelPricing {
        let table = provider == .anthropic ? anthropic : openai
        // Try exact match first, then prefix match
        if let p = table[model] { return p }
        for (key, p) in table {
            if model.hasPrefix(key) { return p }
        }
        return defaultPricing
    }
}
