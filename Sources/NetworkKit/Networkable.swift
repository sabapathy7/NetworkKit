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

/// Main networking protocol offering multiple call styles:
/// - **Async/await** (`sendRequest(urlStr:)` uses native `URLSession` async APIs)
/// - **Async/await + `withCheckedThrowingContinuation`** (`sendRequest(endpoint:)` bridges `URLSession.dataTask`)
/// - **Closures** (`sendRequest(endpoint:resultHandler:)`)
/// - **Combine** (`NetworkService.sendRequest(endpoint:type:)`), only where Combine exists
///
/// The Combine method lives on `NetworkService` (not this protocol) so the protocol
/// compiles on Linux and other platforms without Combine.
public protocol Networkable: Sendable {
    /// Fetches and decodes a resource at the given URL string (native async `URLSession`).
    func sendRequest<T: Decodable & Sendable>(urlStr: String) async throws -> T

    /// Fetches and decodes a resource described by an `EndPoint` (async/await via `withCheckedThrowingContinuation`).
    func sendRequest<T: Decodable & Sendable>(endpoint: EndPoint) async throws -> T

    /// Fetches and decodes a resource, delivering the result to a closure.
    func sendRequest<T: Decodable & Sendable>(
        endpoint: EndPoint,
        resultHandler: @Sendable @escaping (Result<T, NetworkError>) -> Void
    )
}

/// Concrete `Networkable` implementation backed by a `URLSession`.
///
/// `NetworkService` is safe to share across concurrency domains — all stored
/// properties are immutable and `URLSession` is itself thread-safe.
public final class NetworkService: Networkable, @unchecked Sendable {

    private let session: URLSession

    /// Creates a service using the provided `URLSessionConfiguration`.
    ///
    /// Pass a custom configuration (e.g. with `protocolClasses`) for testing.
    public init(configuration: URLSessionConfiguration = .default) {
        self.session = URLSession(configuration: configuration)
    }

    // MARK: - Async/Await

    public func sendRequest<T: Decodable & Sendable>(urlStr: String) async throws -> T {
        guard let url = URL(string: urlStr) else {
            throw NetworkError.invalidURL
        }
        let (data, response) = try await session.data(from: url)
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

    public func sendRequest<T: Decodable & Sendable>(endpoint: EndPoint) async throws -> T {
        guard let urlRequest = createRequest(endPoint: endpoint) else {
            throw NetworkError.invalidURL
        }
        return try await withCheckedThrowingContinuation { continuation in
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

    // MARK: - Closure

    public func sendRequest<T: Decodable & Sendable>(
        endpoint: EndPoint,
        resultHandler: @Sendable @escaping (Result<T, NetworkError>) -> Void
    ) {
        guard let urlRequest = createRequest(endPoint: endpoint) else {
            resultHandler(.failure(.invalidURL))
            return
        }
        session.dataTask(with: urlRequest) { data, response, error in
            if error != nil {
                resultHandler(.failure(.unknown))
                return
            }
            guard let httpResponse = response as? HTTPURLResponse,
                  200...299 ~= httpResponse.statusCode else {
                resultHandler(.failure(.unexpectedStatusCode))
                return
            }
            guard let data else {
                resultHandler(.failure(.unknown))
                return
            }
            do {
                let decoded = try JSONDecoder().decode(T.self, from: data)
                resultHandler(.success(decoded))
            } catch {
                resultHandler(.failure(.decode))
            }
        }.resume()
    }

    // MARK: - Combine (Apple platforms only)

#if canImport(Combine)
    /// Returns a Combine publisher that fetches and decodes a resource.
    public func sendRequest<T: Decodable & Sendable>(
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

    private func createRequest(endPoint: EndPoint) -> URLRequest? {
        var urlComponents = URLComponents()
        urlComponents.scheme = endPoint.scheme
        urlComponents.host = endPoint.host
        urlComponents.path = endPoint.path
        urlComponents.queryItems = endPoint.queryParams?.map {
            URLQueryItem(name: $0.key, value: $0.value)
        }

        var path = endPoint.path
        for (key, value) in endPoint.pathParams ?? [:] {
            path = path.replacingOccurrences(of: "{\(key)}", with: value)
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
