import Foundation
import CryptoKit

struct AWSCredentials {
    let accessKeyId: String
    let secretAccessKey: String
    let sessionToken: String?
}

enum SigV4Signer {
    static let algorithm = "AWS4-HMAC-SHA256"

    static func sign(
        request: inout URLRequest,
        body: Data,
        service: String,
        region: String,
        credentials: AWSCredentials,
        now: Date = Date()
    ) {
        guard let url = request.url, let host = url.host else { return }
        let method = request.httpMethod ?? "POST"

        let (amzDate, dateStamp) = formatDates(now)
        let payloadHash = sha256Hex(body)

        request.setValue(host, forHTTPHeaderField: "Host")
        request.setValue(amzDate, forHTTPHeaderField: "X-Amz-Date")
        if let token = credentials.sessionToken, !token.isEmpty {
            request.setValue(token, forHTTPHeaderField: "X-Amz-Security-Token")
        }

        let signedHeaderNames = collectSignedHeaderNames(from: request)
        let canonicalHeaders = buildCanonicalHeaders(from: request, names: signedHeaderNames)
        let signedHeaders = signedHeaderNames.joined(separator: ";")

        let canonicalURI = url.path.isEmpty ? "/" : canonicalizePath(url.path)
        let canonicalQuery = canonicalQueryString(url: url)

        let canonicalRequest = [
            method.uppercased(),
            canonicalURI,
            canonicalQuery,
            canonicalHeaders,
            signedHeaders,
            payloadHash
        ].joined(separator: "\n")

        let credentialScope = "\(dateStamp)/\(region)/\(service)/aws4_request"
        let stringToSign = [
            algorithm,
            amzDate,
            credentialScope,
            sha256Hex(Data(canonicalRequest.utf8))
        ].joined(separator: "\n")

        let signingKey = deriveSigningKey(
            secret: credentials.secretAccessKey,
            dateStamp: dateStamp,
            region: region,
            service: service
        )
        let signature = hmacHex(key: signingKey, data: Data(stringToSign.utf8))

        let authorization = "\(algorithm) " +
            "Credential=\(credentials.accessKeyId)/\(credentialScope), " +
            "SignedHeaders=\(signedHeaders), " +
            "Signature=\(signature)"
        request.setValue(authorization, forHTTPHeaderField: "Authorization")
    }

    // MARK: - Header canonicalization

    private static func collectSignedHeaderNames(from request: URLRequest) -> [String] {
        let names = (request.allHTTPHeaderFields ?? [:])
            .keys
            .map { $0.lowercased() }
            .filter { isSignableHeader($0) }
        return Array(Set(names)).sorted()
    }

    private static func isSignableHeader(_ name: String) -> Bool {
        // Always sign these; skip anything a proxy might rewrite.
        switch name {
        case "host", "content-type", "x-amz-date", "x-amz-target",
             "x-amz-security-token", "x-amz-content-sha256":
            return true
        default:
            return name.hasPrefix("x-amz-")
        }
    }

    private static func buildCanonicalHeaders(from request: URLRequest, names: [String]) -> String {
        let headers = request.allHTTPHeaderFields ?? [:]
        let lowered = Dictionary(uniqueKeysWithValues: headers.map { ($0.key.lowercased(), $0.value) })
        return names.map { name in
            let value = (lowered[name] ?? "").trimmingCharacters(in: .whitespaces)
            let collapsed = value.split(separator: " ", omittingEmptySubsequences: true).joined(separator: " ")
            return "\(name):\(collapsed)\n"
        }.joined()
    }

    private static func canonicalizePath(_ path: String) -> String {
        // AWS expects percent-encoded path, "/" preserved. For our JSON endpoints this is always "/".
        let allowed = CharacterSet(charactersIn: "/").union(.urlPathAllowed)
        return path.addingPercentEncoding(withAllowedCharacters: allowed) ?? path
    }

    private static func canonicalQueryString(url: URL) -> String {
        guard let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems, !items.isEmpty else {
            return ""
        }
        let encoded = items.map { item -> (String, String) in
            let k = awsEncode(item.name)
            let v = awsEncode(item.value ?? "")
            return (k, v)
        }
        return encoded
            .sorted { $0.0 == $1.0 ? $0.1 < $1.1 : $0.0 < $1.0 }
            .map { "\($0.0)=\($0.1)" }
            .joined(separator: "&")
    }

    private static func awsEncode(_ s: String) -> String {
        // RFC 3986 unreserved: A-Z a-z 0-9 - _ . ~
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-_.~")
        return s.addingPercentEncoding(withAllowedCharacters: allowed) ?? s
    }

    // MARK: - Signing key derivation

    private static func deriveSigningKey(secret: String, dateStamp: String, region: String, service: String) -> Data {
        let kSecret = Data("AWS4\(secret)".utf8)
        let kDate = hmac(key: kSecret, data: Data(dateStamp.utf8))
        let kRegion = hmac(key: kDate, data: Data(region.utf8))
        let kService = hmac(key: kRegion, data: Data(service.utf8))
        return hmac(key: kService, data: Data("aws4_request".utf8))
    }

    private static func hmac(key: Data, data: Data) -> Data {
        let mac = HMAC<SHA256>.authenticationCode(for: data, using: SymmetricKey(data: key))
        return Data(mac)
    }

    private static func hmacHex(key: Data, data: Data) -> String {
        return hmac(key: key, data: data).map { String(format: "%02x", $0) }.joined()
    }

    private static func sha256Hex(_ data: Data) -> String {
        return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    // MARK: - Date formatting

    private static func formatDates(_ date: Date) -> (amzDate: String, dateStamp: String) {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let comps = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
        let amz = String(format: "%04d%02d%02dT%02d%02d%02dZ",
                         comps.year ?? 0, comps.month ?? 0, comps.day ?? 0,
                         comps.hour ?? 0, comps.minute ?? 0, comps.second ?? 0)
        let stamp = String(format: "%04d%02d%02d",
                           comps.year ?? 0, comps.month ?? 0, comps.day ?? 0)
        return (amz, stamp)
    }
}
