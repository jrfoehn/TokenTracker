import Foundation

/// Low-level client for querying AWS Bedrock usage via CloudWatch metrics.
/// Uses the JSON protocol: POST to monitoring.<region>.amazonaws.com with
/// X-Amz-Target = GraniteServiceVersion20100801.<Operation>.
struct BedrockClient {
    let credentials: AWSCredentials
    let region: String
    let session: URLSession

    private var endpoint: URL {
        URL(string: "https://monitoring.\(region).amazonaws.com/")!
    }

    // Metrics we care about for usage tracking.
    static let tokenMetrics: [String] = [
        "InputTokenCount",
        "OutputTokenCount",
        "CacheReadInputTokenCount",
        "CacheWriteInputTokenCount",
        "Invocations",
    ]

    // MARK: - ListMetrics

    /// Enumerate unique ModelId dimension values active in the last ~2 weeks.
    func listModelIds() async throws -> [String] {
        var next: String? = nil
        var ids = Set<String>()
        repeat {
            var body: [String: Any] = [
                "Namespace": "AWS/Bedrock",
                "MetricName": "InputTokenCount",
            ]
            if let next = next { body["NextToken"] = next }
            let response: ListMetricsResponse = try await call(
                target: "ListMetrics",
                body: body
            )
            for m in response.Metrics ?? [] {
                for d in m.Dimensions ?? [] where d.Name == "ModelId" {
                    ids.insert(d.Value)
                }
            }
            next = response.NextToken
        } while next != nil
        return ids.sorted()
    }

    // MARK: - GetMetricData

    /// Returns a mapping: modelId -> metricName -> summed value over the window.
    func fetchTokenTotals(
        modelIds: [String],
        startTime: Date,
        endTime: Date,
        period: Int
    ) async throws -> [String: [String: Double]] {
        guard !modelIds.isEmpty else { return [:] }

        // Build one MetricDataQuery per (model, metric). Id ties result back to (model, metric).
        var refs: [QueryRefLite] = []
        var queries: [[String: Any]] = []
        for (mi, modelId) in modelIds.enumerated() {
            for (ni, metric) in Self.tokenMetrics.enumerated() {
                let id = "q\(mi)_\(ni)"
                refs.append(QueryRefLite(id: id, modelId: modelId, metric: metric))
                queries.append([
                    "Id": id,
                    "ReturnData": true,
                    "MetricStat": [
                        "Metric": [
                            "Namespace": "AWS/Bedrock",
                            "MetricName": metric,
                            "Dimensions": [
                                ["Name": "ModelId", "Value": modelId]
                            ]
                        ],
                        "Period": period,
                        "Stat": "Sum",
                    ],
                ])
            }
        }

        // CloudWatch allows up to 500 queries per call; chunk to be safe.
        var totals: [String: [String: Double]] = [:]
        let chunkSize = 500
        var idx = 0
        while idx < queries.count {
            let end = min(idx + chunkSize, queries.count)
            let slice = Array(queries[idx..<end])
            let sliceRefs = Array(refs[idx..<end])
            try await fetchChunk(
                queries: slice,
                refs: sliceRefs,
                startTime: startTime,
                endTime: endTime,
                totals: &totals
            )
            idx = end
        }
        return totals
    }

    private func fetchChunk(
        queries: [[String: Any]],
        refs: [QueryRefLite],
        startTime: Date,
        endTime: Date,
        totals: inout [String: [String: Double]]
    ) async throws {
        var next: String? = nil
        repeat {
            var body: [String: Any] = [
                "StartTime": startTime.timeIntervalSince1970,
                "EndTime": endTime.timeIntervalSince1970,
                "ScanBy": "TimestampAscending",
                "MaxDatapoints": 100_000,
                "MetricDataQueries": queries,
            ]
            if let next = next { body["NextToken"] = next }
            let response: GetMetricDataResponse = try await call(
                target: "GetMetricData",
                body: body
            )
            let idToRef = Dictionary(uniqueKeysWithValues: refs.map { ($0.id, $0) })
            for result in response.MetricDataResults ?? [] {
                guard let ref = idToRef[result.Id] else { continue }
                let sum = (result.Values ?? []).reduce(0, +)
                totals[ref.modelId, default: [:]][ref.metric, default: 0] += sum
            }
            next = response.NextToken
        } while next != nil
    }

    // Type-erased ref passed into chunk fetcher.
    struct QueryRefLite { let id: String; let modelId: String; let metric: String }

    // MARK: - Transport

    private func call<T: Decodable>(target: String, body: [String: Any]) async throws -> T {
        let payload = try JSONSerialization.data(withJSONObject: body, options: [.sortedKeys])
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("amz-1.0", forHTTPHeaderField: "Content-Encoding")
        request.setValue("GraniteServiceVersion20100801.\(target)", forHTTPHeaderField: "X-Amz-Target")
        request.httpBody = payload

        SigV4Signer.sign(
            request: &request,
            body: payload,
            service: "monitoring",
            region: region,
            credentials: credentials
        )

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw UsageError.networkError("Invalid response")
        }
        guard (200...299).contains(http.statusCode) else {
            let msg = String(data: data, encoding: .utf8) ?? "No body"
            throw UsageError.apiError(.bedrock, statusCode: http.statusCode, message: msg)
        }
        return try JSONDecoder().decode(T.self, from: data)
    }
}

// MARK: - Response models

struct ListMetricsResponse: Decodable {
    let Metrics: [CWMetric]?
    let NextToken: String?
}

struct CWMetric: Decodable {
    let Namespace: String?
    let MetricName: String?
    let Dimensions: [CWDimension]?
}

struct CWDimension: Decodable {
    let Name: String
    let Value: String
}

struct GetMetricDataResponse: Decodable {
    let MetricDataResults: [MetricDataResult]?
    let NextToken: String?
}

struct MetricDataResult: Decodable {
    let Id: String
    let Label: String?
    let Timestamps: [Double]?
    let Values: [Double]?
    let StatusCode: String?
}
