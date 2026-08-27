//
//  Networkable.swift
//  IosNetworkExample
//
//  Created by kanagasabapathy on 01/01/24.
//

#if canImport(Combine)
import Combine
#endif
import Foundation

/// Async/await plus a completion-handler API for callers not yet on concurrency.
/// Combine lives on `NetworkService` so this builds without Combine (e.g. Linux).
public protocol Networkable: Sendable {
    func sendRequestUsingURLString<T: Decodable & Sendable>(_ urlStr: String) async throws -> T
    func sendRequestUsingEndpoint<T: Decodable & Sendable>(endpoint: EndPoint) async throws -> T
    func sendRequestUsingLegacyCallbackAPI<T: Decodable & Sendable>(
        endpoint: EndPoint,
        resultHandler: @Sendable @escaping (Result<T, NetworkError>) -> Void
    )
}

/// `URLSession`-backed `Networkable`. Safe to share: all stored state is immutable
/// and `URLSession` is thread-safe.
public final class NetworkService: Networkable {

    private let session: URLSession
    private let adapters: [any RequestAdapting]
    private let retrier: (any RequestRetrying)?
    private let maxRetryCount: Int

    /// Pass a custom configuration (e.g. `protocolClasses`) for tests.
    ///
    /// - Parameters:
    ///   - adapters: Run in order against every request before it is sent.
    ///   - retrier: Consulted when a request fails; `nil` disables retrying.
    ///   - maxRetryCount: Hard ceiling on retries, so a retrier that always asks
    ///     to retry cannot loop forever.
    public init(configuration: URLSessionConfiguration = .default,
                adapters: [any RequestAdapting] = [],
                retrier: (any RequestRetrying)? = nil,
                maxRetryCount: Int = 3) {
        self.session = URLSession(configuration: configuration)
        self.adapters = adapters
        self.retrier = retrier
        self.maxRetryCount = maxRetryCount
    }

    // MARK: - Async/Await

    /// Fetches and decodes a resource at a raw URL string.
    public func sendRequestUsingURLString<T: Decodable & Sendable>(_ urlStr: String) async throws -> T {
        guard let url = URL(string: urlStr) else {
            throw NetworkError.invalidURL
        }
        return try await withAdaptersAndRetry(URLRequest(url: url)) { urlRequest in
            try await self.perform(urlRequest)
        }
    }

    /// Fetches and decodes a resource described by an `EndPoint`.
    public func sendRequestUsingEndpoint<T: Decodable & Sendable>(endpoint: EndPoint) async throws -> T {
        guard let baseRequest = createRequest(endPoint: endpoint) else {
            throw NetworkError.invalidURL
        }
        return try await withAdaptersAndRetry(baseRequest) { urlRequest in
            try await self.perform(urlRequest)
        }
    }

    // MARK: - Legacy callback

    /// Completion-handler API for callers not yet using async/await.
    ///
    /// Sends via `URLSession.dataTask`, bridged with `withCheckedThrowingContinuation`
    /// so it can still share the adapter and retry pipeline.
    public func sendRequestUsingLegacyCallbackAPI<T: Decodable & Sendable>(
        endpoint: EndPoint,
        resultHandler: @Sendable @escaping (Result<T, NetworkError>) -> Void
    ) {
        guard let baseRequest = createRequest(endPoint: endpoint) else {
            resultHandler(.failure(.invalidURL))
            return
        }
        Task {
            do {
                let decoded: T = try await withAdaptersAndRetry(baseRequest) { urlRequest in
                    try await self.performUsingContinuation(urlRequest)
                }
                resultHandler(.success(decoded))
            } catch let error as NetworkError {
                resultHandler(.failure(error))
            } catch {
                resultHandler(.failure(.unknown))
            }
        }
    }

    // MARK: - Combine (Apple platforms only)

#if canImport(Combine)
    /// Returns a Combine publisher that fetches and decodes a resource.
    ///
    /// Adapters and retrying do not apply here — the publisher must be returned
    /// synchronously, so use the async/await or closure APIs when you need them.
    public func sendRequestUsingCombine<T: Decodable & Sendable>(
        endpoint: EndPoint,
        type: T.Type
    ) -> AnyPublisher<T, NetworkError> {
        guard let urlRequest = createRequest(endPoint: endpoint) else {
            return Fail(error: .invalidURL).eraseToAnyPublisher()
        }
        return session.dataTaskPublisher(for: urlRequest)
            .tryMap { data, response -> Data in
                guard let httpResponse = response as? HTTPURLResponse,
                      200...299 ~= httpResponse.statusCode else {
                    throw NetworkError.unexpectedStatusCode
                }
                return data
            }
            .decode(type: T.self, decoder: JSONDecoder())
            .mapError { error -> NetworkError in
                if error is DecodingError { return .decode }
                if let netError = error as? NetworkError { return netError }
                return .unknown
            }
            .eraseToAnyPublisher()
    }
#endif

    // MARK: - Private Helpers

    /// Runs `send` against an adapted request, consulting `retrier` on failure until
    /// it declines or `maxRetryCount` is reached. Adapters re-run on every attempt,
    /// so a refreshed token is picked up by the retry.
    private func withAdaptersAndRetry<T: Sendable>(
        _ baseRequest: URLRequest,
        send: (URLRequest) async throws -> T
    ) async throws -> T {
        var attempt = 0
        while true {
            do {
                var urlRequest = baseRequest
                for adapter in adapters {
                    urlRequest = try await adapter.adapt(urlRequest)
                }
                return try await send(urlRequest)
            } catch {
                guard attempt < maxRetryCount,
                      let retrier,
                      case .retryAfter(let delay) = await retrier.retry(for: baseRequest,
                                                                       dueTo: error,
                                                                       attempt: attempt)
                else {
                    throw error
                }
                attempt += 1
                try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            }
        }
    }

    /// Sends via `URLSession`'s native async API.
    private func perform<T: Decodable & Sendable>(_ urlRequest: URLRequest) async throws -> T {
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: urlRequest)
        } catch {
            throw NetworkError.unknown
        }
        guard let httpResponse = response as? HTTPURLResponse,
              200...299 ~= httpResponse.statusCode else {
            throw NetworkError.unexpectedStatusCode
        }
        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            throw NetworkError.decode
        }
    }

    /// Sends via `URLSession.dataTask`, bridged with `withCheckedThrowingContinuation`.
    private func performUsingContinuation<T: Decodable & Sendable>(_ urlRequest: URLRequest) async throws -> T {
        try await withCheckedThrowingContinuation { continuation in
            session.dataTask(with: urlRequest) { data, response, error in
                if error != nil {
                    continuation.resume(throwing: NetworkError.unknown)
                    return
                }
                guard response is HTTPURLResponse else {
                    continuation.resume(throwing: NetworkError.invalidURL)
                    return
                }
                guard let httpResponse = response as? HTTPURLResponse,
                      200...299 ~= httpResponse.statusCode else {
                    continuation.resume(throwing: NetworkError.unexpectedStatusCode)
                    return
                }
                guard let data else {
                    continuation.resume(throwing: NetworkError.unknown)
                    return
                }
                do {
                    let decoded = try JSONDecoder().decode(T.self, from: data)
                    continuation.resume(returning: decoded)
                } catch {
                    continuation.resume(throwing: NetworkError.decode)
                }
            }.resume()
        }
    }

    private func createRequest(endPoint: EndPoint) -> URLRequest? {
        var urlComponents = URLComponents()
        urlComponents.scheme = endPoint.scheme
        urlComponents.host = endPoint.host
        urlComponents.queryItems = endPoint.queryParams?.map {
            URLQueryItem(name: $0.key, value: $0.value)
        }

        var path = endPoint.path
        for (key, value) in endPoint.pathParams ?? [:] {
            let encoded = value.addingPercentEncoding(withAllowedCharacters: .pathParameterAllowed) ?? value
            path = path.replacingOccurrences(of: "{\(key)}", with: encoded)
        }
        urlComponents.path = path

        guard let url = urlComponents.url else { return nil }

        var request = URLRequest(url: url)
        request.httpMethod = endPoint.method.rawValue
        request.allHTTPHeaderFields = endPoint.header
        if let body = endPoint.body {
            request.httpBody = try? JSONEncoder().encode(body)
        }
        return request
    }
}

private extension CharacterSet {
    /// `.urlPathAllowed` permits "/", since it is meant for a whole path. A path
    /// parameter is a single segment, so "/" must be encoded rather than split it.
    static let pathParameterAllowed = CharacterSet.urlPathAllowed
        .subtracting(CharacterSet(charactersIn: "/"))
}
