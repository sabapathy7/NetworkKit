//
//  Networkable.swift
//  IosNetworkExample
//
//  Created by kanagasabapathy on 01/01/24.
//

@_exported import Combine
@_exported import Foundation

public protocol Networkable {
    func sendRequest<T: Decodable>(urlStr: String) async throws -> T
    func sendRequest<T: Decodable>(endpoint: EndPoint) async throws -> T
    func sendRequest<T: Decodable>(endpoint: EndPoint, resultHandler: @Sendable @escaping (Result<T, NetworkError>) -> Void)
    func sendRequest<T: Decodable>(endpoint: EndPoint, type: T.Type) -> AnyPublisher<T, NetworkError>
}

public final class NetworkService: Networkable {
    public func sendRequest<T>(urlStr: String) async throws -> T where T : Decodable {
        guard let urlStr = urlStr as String?, let url = URL(string: urlStr) as URL?else {
            throw NetworkError.invalidURL
        }
        let (data, response) = try await URLSession.shared.data(from: url)
        guard let response = response as? HTTPURLResponse, 200...299 ~= response.statusCode else {
            throw NetworkError.unexpectedStatusCode
        }
        guard let data = data as Data? else {
            throw NetworkError.unknown
        }
        guard let decodedResponse = try? JSONDecoder().decode(T.self, from: data) else {
            throw NetworkError.decode
        }
        return decodedResponse
    }

    public func sendRequest<T>(endpoint: EndPoint, type: T.Type) -> AnyPublisher<T, NetworkError> where T: Decodable {
        guard let urlRequest = createRequest(endPoint: endpoint) else {
            preconditionFailure("Failed URLRequest")
        }
        return URLSession.shared.dataTaskPublisher(for: urlRequest)
            .subscribe(on: DispatchQueue.global(qos: .background))
            .tryMap { data, response -> Data in
                guard let response = response as? HTTPURLResponse, 200...299 ~= response.statusCode else {
                    throw NetworkError.invalidURL
                }
                return data
            }
            .decode(type: T.self, decoder: JSONDecoder())
            .mapError { error -> NetworkError in
                if error is DecodingError {
                    return NetworkError.decode
                } else if let error = error as? NetworkError {
                    return error
                } else {
                    return NetworkError.unknown
                }
            }
            .eraseToAnyPublisher()
    }

    public func sendRequest<T: Decodable>(endpoint: EndPoint) async throws -> T {
        guard let urlRequest = createRequest(endPoint: endpoint) else {
            throw NetworkError.decode
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
                    guard let decodedResponse = try? JSONDecoder().decode(T.self, from: data) else {
                        continuation.resume(throwing: NetworkError.decode)
                        return
                    }
                    continuation.resume(returning: decodedResponse)
                }
            task.resume()
        }
    }

    public func sendRequest<T: Decodable>(endpoint: EndPoint,
                                          resultHandler: @Sendable @escaping (Result<T, NetworkError>) -> Void) {

        guard let urlRequest = createRequest(endPoint: endpoint) else {
            return
        }
        let urlTask = URLSession.shared.dataTask(with: urlRequest) { data, response, error in
            guard error == nil else {
                resultHandler(.failure(.invalidURL))
                return
            }
            guard let response = response as? HTTPURLResponse, 200...299 ~= response.statusCode else {
                resultHandler(.failure(.unexpectedStatusCode))
                return
            }
            guard let data = data else {
                resultHandler(.failure(.unknown))
                return
            }
            guard let decodedResponse = try? JSONDecoder().decode(T.self, from: data) else {
                resultHandler(.failure(.decode))
                return
            }
            resultHandler(.success(decodedResponse))
        }
        urlTask.resume()
    }

    public init() {

    }
}

extension Networkable {
    fileprivate func createRequest(endPoint: EndPoint) -> URLRequest? {
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
