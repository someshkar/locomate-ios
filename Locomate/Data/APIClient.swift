//
//  APIClient.swift
//  Locomate
//
//  Rail API client — ported from SmartRail `src/services/apiClient.ts` and
//  `src/services/railData.ts`. Preserves:
//  - 12s request timeout
//  - retryable statuses {408, 429, 500, 502, 503, 504}
//  - Retry-After parsing (seconds or HTTP date)
//  - device-session create/refresh with a 30s expiry skew
//  - the gateway error envelope, including Cloudflare 1102 resource limits
//

import Foundation

// MARK: - Errors

public struct APIError: Error, LocalizedError, Sendable {
    public let status: Int
    public let code: String
    public let requestId: String
    public let retryable: Bool
    public let message: String

    public var errorDescription: String? { message }
}

// MARK: - Session

public struct AuthSession: Codable, Sendable {
    public var accessToken: String
    public var refreshToken: String?
    public var expiresAt: Date

    public var isExpired: Bool {
        expiresAt.timeIntervalSinceNow < APIClient.sessionExpirySkew
    }
}

public protocol TokenStore: Sendable {
    func load() -> AuthSession?
    func save(_ session: AuthSession) throws
    func clear()
}

// MARK: - Client

public actor APIClient {
    public static let sessionExpirySkew: TimeInterval = 30
    static let requestTimeout: TimeInterval = 12
    static let retryableStatuses: Set<Int> = [408, 429, 500, 502, 503, 504]

    private let baseURL: URL
    private let tokenStore: TokenStore
    private let session: URLSession
    private let installationId: String
    private var refreshTask: Task<AuthSession, Error>?

    public init(baseURL: URL, tokenStore: TokenStore, installationId: String) {
        self.baseURL = baseURL
        self.tokenStore = tokenStore
        self.installationId = installationId
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = APIClient.requestTimeout
        configuration.timeoutIntervalForResource = APIClient.requestTimeout * 2
        configuration.waitsForConnectivity = false
        self.session = URLSession(configuration: configuration)
    }

    // MARK: Auth

    /// Create or refresh a device session. Single-flight: concurrent callers
    /// await one refresh rather than stampeding the gateway.
    private func validSession() async throws -> AuthSession {
        if let existing = tokenStore.load(), !existing.isExpired { return existing }
        if let refreshTask { return try await refreshTask.value }

        let task = Task<AuthSession, Error> { [installationId] in
            let response: SessionResponse = try await self.rawRequest(
                path: "/v1/auth/device-session",
                method: "POST",
                body: ["installationId": installationId],
                token: nil
            )
            let session = AuthSession(
                accessToken: response.accessToken,
                refreshToken: response.refreshToken,
                expiresAt: Date().addingTimeInterval(TimeInterval(response.expiresIn))
            )
            try? self.tokenStore.save(session)
            return session
        }
        refreshTask = task
        defer { refreshTask = nil }
        return try await task.value
    }

    struct SessionResponse: Decodable {
        let accessToken: String
        let refreshToken: String?
        let expiresIn: Double
    }

    // MARK: Requests

    public func get<T: Decodable>(_ path: String, query: [String: String] = [:]) async throws -> T {
        let session = try await validSession()
        return try await rawRequest(path: path, method: "GET", query: query, body: nil, token: session.accessToken)
    }

    /// Preserve the gateway's complete privacy export without narrowing its schema in the app.
    public func getRaw(_ path: String) async throws -> Data {
        let session = try await validSession()
        let (data, _, _) = try await performRequest(
            path: path, method: "GET", body: nil, token: session.accessToken
        )
        return data
    }

    public func post<T: Decodable>(
        _ path: String,
        body: [String: Any]?,
        idempotencyKey: String? = nil
    ) async throws -> T {
        let session = try await validSession()
        return try await rawRequest(
            path: path,
            method: "POST",
            body: body,
            token: session.accessToken,
            idempotencyKey: idempotencyKey
        )
    }

    public func postData<T: Decodable>(
        _ path: String,
        bodyData: Data,
        idempotencyKey: String? = nil
    ) async throws -> T {
        let session = try await validSession()
        let (data, status, requestId) = try await performRequest(
            path: path, method: "POST", body: nil, token: session.accessToken,
            idempotencyKey: idempotencyKey, bodyData: bodyData
        )
        do {
            return try JSONDecoder.locomote.decode(T.self, from: data)
        } catch {
            throw APIError(status: status, code: "decode_error", requestId: requestId, retryable: false,
                           message: "The rail service returned an unexpected response.")
        }
    }

    public func delete(_ path: String) async throws {
        let session = try await validSession()
        _ = try await performRequest(path: path, method: "DELETE", body: nil, token: session.accessToken)
    }

    private func rawRequest<T: Decodable>(
        path: String,
        method: String,
        query: [String: String] = [:],
        body: [String: Any]?,
        token: String?,
        idempotencyKey: String? = nil
    ) async throws -> T {
        let (data, status, requestId) = try await performRequest(
            path: path, method: method, query: query, body: body, token: token,
            idempotencyKey: idempotencyKey
        )
        do {
            return try JSONDecoder.locomote.decode(T.self, from: data)
        } catch {
            throw APIError(status: status, code: "decode_error", requestId: requestId, retryable: false,
                           message: "The rail service returned an unexpected response.")
        }
    }

    private func performRequest(
        path: String,
        method: String,
        query: [String: String] = [:],
        body: [String: Any]?,
        token: String?,
        idempotencyKey: String? = nil,
        bodyData: Data? = nil
    ) async throws -> (Data, Int, String) {
        var components = URLComponents(url: baseURL.appendingPathComponent(path), resolvingAgainstBaseURL: false)
        if !query.isEmpty {
            components?.queryItems = query.map { URLQueryItem(name: $0.key, value: $0.value) }
        }
        guard let url = components?.url else {
            throw APIError(status: 0, code: "bad_url", requestId: "", retryable: false,
                           message: "The rail service URL is invalid.")
        }

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("LocomateNative/1.0", forHTTPHeaderField: "User-Agent")
        if let token { request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        if let idempotencyKey { request.setValue(idempotencyKey, forHTTPHeaderField: "Idempotency-Key") }
        if let bodyData {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = bodyData
        } else if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        }

        let requestId = UUID().uuidString
        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                throw APIError(status: 0, code: "no_response", requestId: requestId,
                               retryable: true, message: "The rail service did not respond.")
            }
            guard (200..<300).contains(http.statusCode) else {
                throw Self.makeError(http: http, data: data, requestId: requestId)
            }
            return (data, http.statusCode, requestId)
        } catch let error as APIError {
            throw error
        } catch {
            throw APIError(status: 0, code: "network_error", requestId: requestId, retryable: true,
                           message: "Couldn't reach the railway feed. Check your connection and try again.")
        }
    }

    // MARK: Error mapping

    static func makeError(http: HTTPURLResponse, data: Data, requestId: String) -> APIError {
        var code = "http_error"
        var message = "Rail API request failed (\(http.statusCode))"

        if let payload = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            if let title = payload["title"] as? String, title.hasPrefix("Error 1102") {
                code = "gateway_resource_limit"
                message = "The rail service is temporarily overloaded. Please try again."
            }
            if let error = payload["error"] as? [String: Any] {
                if let value = error["code"] as? String { code = value }
                if let value = error["message"] as? String { message = value }
            }
        }

        if code.hasPrefix("invalid_provider") || code.hasPrefix("provider_") {
            message = "The rail feed is temporarily unavailable. Try again shortly."
        }

        if http.statusCode == 429,
           let retryAfter = parseRetryAfter(http.value(forHTTPHeaderField: "Retry-After")) {
            let minutes = max(1, Int(ceil(retryAfter / 60)))
            message = "Too many requests. Try again in \(minutes) minute(s)."
        }

        return APIError(
            status: http.statusCode,
            code: code,
            requestId: requestId,
            retryable: retryableStatuses.contains(http.statusCode),
            message: message
        )
    }

    /// Parse a `Retry-After` header (seconds or HTTP date) into seconds.
    static func parseRetryAfter(_ value: String?, now: Date = Date()) -> TimeInterval? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespaces)
        if let seconds = Double(trimmed) { return seconds >= 0 ? seconds : nil }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "GMT")
        formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
        guard let date = formatter.date(from: trimmed) else { return nil }
        return max(0, date.timeIntervalSince(now))
    }
}

// MARK: - Decoding

public extension JSONDecoder {
    static let locomote: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .useDefaultKeys
        return decoder
    }()
}

// MARK: - URL validation (mirrors validateRailApiUrl)

public enum RailAPIURL {
    public static func validate(_ value: String, development: Bool = false) throws -> URL {
        let candidate = value.trimmingCharacters(in: .whitespaces)
        guard let url = URL(string: candidate), let scheme = url.scheme, let host = url.host else {
            throw URLValidationError.invalid
        }
        let isLocal = ["localhost", "127.0.0.1", "::1"].contains(host)
        guard scheme == "https" || (development && isLocal && scheme == "http") else {
            throw URLValidationError.notHTTPS
        }
        guard url.user == nil, url.password == nil, url.query == nil, url.fragment == nil else {
            throw URLValidationError.hasCredentials
        }
        return url
    }

    public enum URLValidationError: Error, LocalizedError {
        case invalid, notHTTPS, hasCredentials
        public var errorDescription: String? {
            switch self {
            case .invalid: return "The rail API URL is not a valid absolute URL."
            case .notHTTPS: return "The rail API URL must use HTTPS."
            case .hasCredentials: return "The rail API URL must not contain credentials, a query, or a fragment."
            }
        }
    }
}
