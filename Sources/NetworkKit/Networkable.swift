//
//  Networkable.swift
//  IosNetworkExample
//
//  Created by kanagasabapathy on 01/01/24.
//

@_exported import Combine
@_exported import Foundation

/// Main networking protocol with full Swift 6 concurrency support
///
/// This protocol provides two API styles:
/// - async/await: Modern Swift concurrency (inherits caller's isolation)
/// - Closures: Legacy callback-based API
///
/// All generic types are constrained to Sendable for safe concurrent usage.
///
public protocol Networkable: Sendable {

    /// Sends a network request using a URL string
    /// - Parameter urlStr: The URL string to request
    /// - Returns: Decoded response of type T
    /// - Throws: NetworkError if the request fails
    /// - Note: Inherits caller's isolation context (SE-0461)
    func sendRequest<T: Decodable & Sendable>(urlStr: String) async throws -> T

    /// Sends a network request and returns a Combine publisher
    /// - Parameters:
    ///   - endpoint: The endpoint configuration
    ///   - type: The type to decode the response into
    /// - Returns: Publisher that emits the decoded response or NetworkError
    func sendRequest<T>(endpoint: EndPoint, type: T.Type) -> AnyPublisher<T, NetworkError> where T: Decodable & Sendable

    /// Bridging callbacks to async/await with continuation
    /// Demonstrates bridging callback-based APIs to async/await
    /// Useful pattern for wrapping legacy APIs without native async support
    /// - Parameter endpoint: The endpoint configuration
    /// - Returns: Decoded response of type T
    /// - Throws: NetworkError if the request fails
    func sendRequestWithContinuation<T: Decodable & Sendable>(endpoint: EndPoint) async throws -> T

    /// Sends a network request using an endpoint configuration
    /// - Parameter endpoint: The endpoint configuration
    /// - Returns: Decoded response of type T
    /// - Throws: NetworkError if the request fails
    /// - Note: Inherits caller's isolation context (SE-0461)
    func sendRequest<T: Decodable & Sendable>(endpoint: EndPoint) async throws -> T

    /// Sends a network request with a completion handler
    /// - Parameters:
    ///   - endpoint: The endpoint configuration
    ///   - resultHandler: Sendable completion handler called with the result
    func sendRequest<T: Decodable & Sendable>(endpoint: EndPoint, resultHandler: @Sendable @escaping (Result<T, NetworkError>) -> Void)
}

/// Default implementation of the Networkable protocol
/// Thread-safe and Sendable-conformant for concurrent usage
public final class NetworkService: Networkable, @unchecked Sendable {
    // Immutable URLSession for thread-safety
    private let session: URLSession

    /// Initializes a new NetworkService with default configuration
    public convenience init() {
        self.init(configuration: .default)
    }

    /// Initializes a new NetworkService
    /// - Parameter configuration: URLSession configuration
    public init(configuration: URLSessionConfiguration) {
        self.session = URLSession(configuration: configuration)
    }

    /// Sends a network request using a URL string
    /// Inherits caller's isolation context (SE-0461)
    public func sendRequest<T>(urlStr: String) async throws -> T where T: Decodable & Sendable {
        guard let url = URL(string: urlStr) else {
            throw NetworkError.invalidURL
        }
        let (data, response) = try await session.data(from: url)
        guard let httpResponse = response as? HTTPURLResponse, 200...299 ~= httpResponse.statusCode else {
            throw NetworkError.unexpectedStatusCode
        }
        do {
            let decodedResponse = try JSONDecoder().decode(T.self, from: data)
            return decodedResponse
        } catch {
            throw NetworkError.decode
        }
    }

    /// Sends a network request and returns a Combine publisher
    /// - Parameters:
    ///   - endpoint: The endpoint configuration
    ///   - type: The type to decode the response into
    /// - Returns: Publisher that emits the decoded response or NetworkError
    public func sendRequest<T>(endpoint: EndPoint, type: T.Type) -> AnyPublisher<T, NetworkError> where T: Decodable & Sendable {
        guard let urlRequest = createRequest(endPoint: endpoint) else {
            return Fail(error: .invalidURL).eraseToAnyPublisher()
        }
        return session.dataTaskPublisher(for: urlRequest)
            .tryMap { data, response -> Data in
                guard let httpResponse = response as? HTTPURLResponse, 200...299 ~= httpResponse.statusCode else {
                    throw NetworkError.unexpectedStatusCode
                }
                return data
            }
            .decode(type: T.self, decoder: JSONDecoder())
            .mapError { error -> NetworkError in
                if error is DecodingError {
                    return NetworkError.decode
                } else if let netError = error as? NetworkError {
                    return netError
                } else {
                    return NetworkError.unknown
                }
            }
            .eraseToAnyPublisher()
    }

    /// Bridging callbacks to async/await with continuation
    /// Demonstrates bridging callback-based APIs to async/await
    /// Useful pattern for wrapping legacy APIs without native async support
    /// - Parameter endpoint: The endpoint configuration
    /// - Returns: Decoded response of type T
    /// - Throws: NetworkError if the request fails
    public func sendRequestWithContinuation<T: Decodable & Sendable>(endpoint: EndPoint) async throws -> T {
        guard let urlRequest = createRequest(endPoint: endpoint) else {
            throw NetworkError.invalidURL
        }
        return try await withCheckedThrowingContinuation { continuation in
            let task = URLSession(configuration: .default, delegate: nil, delegateQueue: .main)
                .dataTask(with: urlRequest) { data, response, _ in
                    guard response is HTTPURLResponse else {
                        continuation.resume(throwing: NetworkError.invalidURL)
                        return
                    }
                    guard let response = response as? HTTPURLResponse, 200...299 ~= response.statusCode else {
                        continuation.resume(throwing:
                                                NetworkError.unexpectedStatusCode)
                        return
                    }
                    guard let data = data else {
                        continuation.resume(throwing: NetworkError.unknown)
                        return
                    }
                    // Decode response
                    do {
                        let decoded = try JSONDecoder().decode(T.self, from: data)
                        continuation.resume(returning: decoded)
                    } catch {
                        continuation.resume(throwing: NetworkError.decode)
                    }
                }
            task.resume()
        }
    }

    /// Sends a network request using an endpoint configuration
    /// Inherits caller's isolation context (SE-0461)
    /// - Parameter endpoint: The endpoint configuration
    /// - Returns: Decoded response of type T
    /// - Throws: NetworkError if the request fails
    public func sendRequest<T>(endpoint: any EndPoint) async throws -> T where T : Decodable, T : Sendable {
        guard let urlRequest = createRequest(endPoint: endpoint) else {
            throw NetworkError.invalidURL
        }
        let (data, response) = try await session.data(for: urlRequest)
        guard let httpResponse = response as? HTTPURLResponse, 200...299 ~= httpResponse.statusCode else {
            throw NetworkError.unexpectedStatusCode
        }
        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            throw NetworkError.decode
        }
    }

    /// Sends a network request with a completion handler
    /// - Parameters:
    ///   - endpoint: The endpoint configuration
    ///   - resultHandler: Sendable completion handler called with the result
    public func sendRequest<T: Decodable & Sendable>(
        endpoint: EndPoint,
        resultHandler: @Sendable @escaping (Result<T, NetworkError>) -> Void
    ) {
        guard let urlRequest = createRequest(endPoint: endpoint) else {
            resultHandler(.failure(.invalidURL))
            return
        }
        let urlTask = session.dataTask(with: urlRequest) { data, response, error in
            if error != nil {
                resultHandler(.failure(.unknown))
                return
            }
            guard let httpResponse = response as? HTTPURLResponse, 200...299 ~= httpResponse.statusCode else {
                resultHandler(.failure(.unexpectedStatusCode))
                return
            }
            guard let data = data else {
                resultHandler(.failure(.unknown))
                return
            }
            do {
                let decodedResponse = try JSONDecoder().decode(T.self, from: data)
                resultHandler(.success(decodedResponse))
            } catch {
                resultHandler(.failure(.decode))
            }
        }
        urlTask.resume()
    }

    // MARK: - Private Helper Methods

    /// Creates a URLRequest from an EndPoint configuration
    /// - Parameter endPoint: The endpoint configuration
    /// - Returns: A configured URLRequest, or nil if the URL is invalid
    private func createRequest(endPoint: EndPoint) -> URLRequest? {
        var urlComponents = URLComponents()
        urlComponents.scheme = endPoint.scheme
        urlComponents.host = endPoint.host
        urlComponents.path = endPoint.path
        // Adding query parameters
        urlComponents.queryItems = endPoint.queryParams?.map { URLQueryItem(name: $0.key, value: $0.value) }

        // Handling path parameters
        var path = endPoint.path
        for (key, value) in endPoint.pathParams ?? [:] {
            path = path.replacingOccurrences(of: "{\(key)}", with: value)
        }
        urlComponents.path = path
        guard let url = urlComponents.url else {
            return nil
        }
        var request = URLRequest(url: url)
        request.httpMethod = endPoint.method.rawValue
        request.allHTTPHeaderFields = endPoint.header
        if let body = endPoint.body {
            let encoder = JSONEncoder()
            request.httpBody = try? encoder.encode(body)
        }
        return request
    }
}
