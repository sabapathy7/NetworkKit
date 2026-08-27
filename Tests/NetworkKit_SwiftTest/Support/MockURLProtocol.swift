//
//  MockURLProtocol.swift
//  NetworkKit
//
//  Created by kanagasabapathy.
//

import Foundation

final class MockURLProtocol: URLProtocol {
    // Shared across instances; MockedNetworkTests.serialized keeps this from racing.
    nonisolated(unsafe) static var requestHandler: (@Sendable (URLRequest) throws -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool { true }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let handler = MockURLProtocol.requestHandler else {
            client?.urlProtocol(self, didFailWithError: URLError(.badURL))
            return
        }
        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}

extension URLSessionConfiguration {
    static func mock(handler: @escaping @Sendable (URLRequest) throws -> (HTTPURLResponse, Data)) -> URLSessionConfiguration {
        MockURLProtocol.requestHandler = handler
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockURLProtocol.self]
        return configuration
    }

    static func mockStatusCode(_ statusCode: Int, data: Data = Data()) -> URLSessionConfiguration {
        mock { request in
            (try mockResponse(for: request, statusCode: statusCode), data)
        }
    }
}

func mockResponse(for request: URLRequest, statusCode: Int = 200) throws -> HTTPURLResponse {
    guard let url = request.url else {
        throw URLError(.badURL)
    }
    guard let response = HTTPURLResponse(url: url, statusCode: statusCode, httpVersion: nil, headerFields: nil) else {
        throw URLError(.cannotParseResponse)
    }
    return response
}
