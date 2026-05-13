//
//  NetworkKitTests.swift
//  NetworkKit
//
//  Created by kanagasabapathy on 01/01/24.
//

#if canImport(Combine)
import Combine
#endif
@preconcurrency import XCTest
@testable import NetworkKit

final class NetworkServiceTests: XCTestCase {

    private var networkService: NetworkService!
#if canImport(Combine)
    private var cancellables: Set<AnyCancellable>!
#endif

    override func setUp() {
        super.setUp()
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [URLProtocolMock.self]
        networkService = NetworkService(configuration: config)
#if canImport(Combine)
        cancellables = []
#endif
    }

    override func tearDown() {
        networkService = nil
#if canImport(Combine)
        cancellables = nil
#endif
        URLProtocolMock.mockResponse = nil
        super.tearDown()
    }

    // MARK: - Async/Await Tests

    func testSendRequestWithURLString_Success() async throws {
        let expectedData = "{\"key\":\"value\"}".data(using: .utf8)!
        URLProtocolMock.mockResponse = MockResponse(
            data: expectedData,
            response: HTTPURLResponse(
                url: URL(string: "https://swiftpublished.com")!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil),
            error: nil
        )

        let result: [String: String] = try await networkService.sendRequest(
            urlStr: "https://swiftpublished.com"
        )

        XCTAssertEqual(result["key"], "value")
    }

    func testSendRequestWithEndpoint_Success() async throws {
        let expectedData = "{\"key\":\"value\"}".data(using: .utf8)!
        URLProtocolMock.mockResponse = MockResponse(
            data: expectedData,
            response: HTTPURLResponse(
                url: URL(string: "https://swiftpublished.com")!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil),
            error: nil
        )

        let result: [String: String] = try await networkService.sendRequest(
            endpoint: MockEndpoint()
        )

        XCTAssertEqual(result["key"], "value")
    }

    func testSendRequestWithEndpoint_Failure() async {
        URLProtocolMock.mockResponse = MockResponse(
            data: nil,
            response: nil,
            error: URLError(.notConnectedToInternet)
        )

        do {
            let _: [String: String] = try await networkService.sendRequest(endpoint: MockEndpoint())
            XCTFail("Expected to throw, but did not.")
        } catch {
            XCTAssertNotNil(error)
        }
    }

    // MARK: - Closure Tests

    func testSendRequestWithResultHandler_Success() {
        let expectedData = "{\"key\":\"value\"}".data(using: .utf8)!
        URLProtocolMock.mockResponse = MockResponse(
            data: expectedData,
            response: HTTPURLResponse(
                url: URL(string: "https://swiftpublished.com")!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil),
            error: nil
        )

        let expectation = self.expectation(description: "Closure should succeed")
        networkService.sendRequest(endpoint: MockEndpoint()) { (result: Result<[String: String], NetworkError>) in
            switch result {
            case .success(let data):
                XCTAssertEqual(data["key"], "value")
            case .failure:
                XCTFail("Expected success, got failure")
            }
            expectation.fulfill()
        }

        waitForExpectations(timeout: 2.0)
    }

    func testSendRequestWithResultHandler_Failure() {
        URLProtocolMock.mockResponse = MockResponse(
            data: nil,
            response: nil,
            error: URLError(.notConnectedToInternet)
        )

        let expectation = self.expectation(description: "Closure should fail")
        networkService.sendRequest(endpoint: MockEndpoint()) { (result: Result<[String: String], NetworkError>) in
            switch result {
            case .success:
                XCTFail("Expected failure, got success")
            case .failure(let error):
                XCTAssertEqual(error, NetworkError.unknown)
            }
            expectation.fulfill()
        }

        waitForExpectations(timeout: 2.0)
    }

    // MARK: - Combine Tests (Apple platforms only)

#if canImport(Combine)
    func testSendRequestWithCombine_Success() {
        let expectedData = "{\"key\":\"value\"}".data(using: .utf8)!
        URLProtocolMock.mockResponse = MockResponse(
            data: expectedData,
            response: HTTPURLResponse(
                url: URL(string: "https://swiftpublished.com")!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil),
            error: nil
        )

        let expectation = self.expectation(description: "Combine should succeed")
        networkService.sendRequest(endpoint: MockEndpoint(), type: [String: String].self)
            .sink(receiveCompletion: { completion in
                if case .failure(let error) = completion {
                    XCTFail("Expected success, got \(error)")
                }
            }, receiveValue: { result in
                XCTAssertEqual(result["key"], "value")
                expectation.fulfill()
            })
            .store(in: &cancellables)

        waitForExpectations(timeout: 2.0)
    }

    func testSendRequestWithCombine_Failure() {
        URLProtocolMock.mockResponse = MockResponse(
            data: nil,
            response: nil,
            error: URLError(.notConnectedToInternet)
        )

        let expectation = self.expectation(description: "Combine should fail")
        var receivedError: NetworkError?

        networkService.sendRequest(endpoint: MockEndpoint(), type: TestModel.self)
            .sink(receiveCompletion: { completion in
                if case .failure(let error) = completion {
                    receivedError = error
                    expectation.fulfill()
                }
            }, receiveValue: { _ in
                XCTFail("Expected failure, got success")
            })
            .store(in: &cancellables)

        waitForExpectations(timeout: 2.0)
        XCTAssertEqual(receivedError, .unknown)
    }
#endif
}

// MARK: - Mock Infrastructure

final class URLProtocolMock: URLProtocol {
    nonisolated(unsafe) static var mockResponse: MockResponse?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        if let mock = URLProtocolMock.mockResponse {
            if let response = mock.response {
                client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            }
            if let data = mock.data {
                client?.urlProtocol(self, didLoad: data)
            }
            if let error = mock.error {
                client?.urlProtocol(self, didFailWithError: error)
            }
        }
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

struct MockResponse {
    var data: Data?
    var response: URLResponse?
    var error: Error?
}

struct MockEndpoint: EndPoint {
    var scheme: String { "https" }
    var host: String { "swiftpublished.com" }
    var path: String { "/mock" }
    var method: RequestMethod { .get }
    var header: [String: String]? { ["Content-Type": "application/json"] }
    var body: [String: String]? { nil }
    var queryParams: [String: String]? { nil }
    var pathParams: [String: String]? { nil }
}

struct TestModel: Decodable, Equatable, Sendable {
    let id: Int
    let name: String
}
