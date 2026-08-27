//
//  NetworkServiceInterceptorTests.swift
//  NetworkKit
//
//  Created by kanagasabapathy.
//

import Foundation
import Testing
import NetworkKitCore
@testable import NetworkKit

extension MockedNetworkTests {
    @Suite
    struct NetworkServiceInterceptorTests {
        struct HeaderAddingAdapter: RequestAdapting {
            let name: String
            let value: String

            func adapt(_ request: URLRequest) async throws -> URLRequest {
                var request = request
                request.setValue(value, forHTTPHeaderField: name)
                return request
            }
        }

        struct ThrowingAdapter: RequestAdapting {
            struct AdapterError: Error {}

            func adapt(_ request: URLRequest) async throws -> URLRequest {
                throw AdapterError()
            }
        }

        struct StubRetrier: RequestRetrying {
            let result: RetryResult

            func retry(for request: URLRequest, dueTo error: Error, attempt: Int) async -> RetryResult {
                result
            }
        }

        @Test("adapter-added header reaches the actual request")
        func adapterHeaderReachesRequest() async throws {
            let expected = MockUser(id: 1, name: "Ada")
            let configuration = URLSessionConfiguration.mock { request in
                #expect(request.value(forHTTPHeaderField: "X-Test") == "adapted")
                let response = try mockResponse(for: request)
                return (response, try JSONEncoder().encode(expected))
            }
            let service = NetworkService(configuration: configuration,
                                         adapters: [HeaderAddingAdapter(name: "X-Test", value: "adapted")])

            let result: MockUser = try await service.sendRequestUsingEndpoint(endpoint: MockEndpoint())

            #expect(result == expected)
        }

        @Test("retrier retries once then succeeds")
        func retrierRetriesThenSucceeds() async throws {
            let expected = MockUser(id: 2, name: "Grace")
            nonisolated(unsafe) var callCount = 0
            let configuration = URLSessionConfiguration.mock { request in
                callCount += 1
                if callCount == 1 {
                    return (try mockResponse(for: request, statusCode: 500), Data())
                }
                return (try mockResponse(for: request), try JSONEncoder().encode(expected))
            }
            let service = NetworkService(configuration: configuration,
                                         retrier: StubRetrier(result: .retryAfter(0.01)))

            let result: MockUser = try await service.sendRequestUsingEndpoint(endpoint: MockEndpoint())

            #expect(result == expected)
            #expect(callCount == 2)
        }

        @Test("retrier declining a retry surfaces the original error with no retry")
        func retrierDecliningRetrySurfacesOriginalError() async throws {
            nonisolated(unsafe) var callCount = 0
            let configuration = URLSessionConfiguration.mock { request in
                callCount += 1
                return (try mockResponse(for: request, statusCode: 500), Data())
            }
            let service = NetworkService(configuration: configuration,
                                         retrier: StubRetrier(result: .doNotRetry))

            await #expect(throws: NetworkError.unexpectedStatusCode) {
                let _: MockUser = try await service.sendRequestUsingEndpoint(endpoint: MockEndpoint())
            }
            #expect(callCount == 1)
        }

        @Test("adapter failure propagates unwrapped and is offered to the retrier")
        func adapterFailurePropagatesAndOffersRetry() async throws {
            nonisolated(unsafe) var retrierWasCalled = false
            struct RecordingRetrier: RequestRetrying {
                let onCalled: @Sendable (Error) -> Void
                func retry(for request: URLRequest, dueTo error: Error, attempt: Int) async -> RetryResult {
                    onCalled(error)
                    return .doNotRetry
                }
            }
            let configuration = URLSessionConfiguration.mock { request in
                Issue.record("Adapter should have thrown before any request was sent")
                return (try mockResponse(for: request), Data())
            }
            let service = NetworkService(
                configuration: configuration,
                adapters: [ThrowingAdapter()],
                retrier: RecordingRetrier(onCalled: { error in
                    #expect(error is ThrowingAdapter.AdapterError)
                    retrierWasCalled = true
                })
            )

            await #expect(throws: ThrowingAdapter.AdapterError.self) {
                let _: MockUser = try await service.sendRequestUsingEndpoint(endpoint: MockEndpoint())
            }
            #expect(retrierWasCalled)
        }

        @Test("maxRetryCount stops a retrier that always says retryAfter")
        func maxRetryCountStopsUnboundedRetrying() async throws {
            nonisolated(unsafe) var callCount = 0
            let configuration = URLSessionConfiguration.mock { request in
                callCount += 1
                return (try mockResponse(for: request, statusCode: 500), Data())
            }
            let service = NetworkService(configuration: configuration,
                                         retrier: StubRetrier(result: .retryAfter(0.001)),
                                         maxRetryCount: 2)

            await #expect(throws: NetworkError.unexpectedStatusCode) {
                let _: MockUser = try await service.sendRequestUsingEndpoint(endpoint: MockEndpoint())
            }
            #expect(callCount == 3)
        }

        @Test("the legacy callback API retries too, and adapters reach its request")
        func legacyCallbackAPIHonoursRetryAndAdapters() async throws {
            let expected = MockUser(id: 5, name: "Barbara")
            nonisolated(unsafe) var callCount = 0
            let configuration = URLSessionConfiguration.mock { request in
                callCount += 1
                #expect(request.value(forHTTPHeaderField: "X-Test") == "adapted")
                if callCount == 1 {
                    return (try mockResponse(for: request, statusCode: 500), Data())
                }
                return (try mockResponse(for: request), try JSONEncoder().encode(expected))
            }
            let service = NetworkService(configuration: configuration,
                                         adapters: [HeaderAddingAdapter(name: "X-Test", value: "adapted")],
                                         retrier: StubRetrier(result: .retryAfter(0.01)))

            await confirmation("resultHandler is called exactly once") { handlerCalled in
                service.sendRequestUsingLegacyCallbackAPI(endpoint: MockEndpoint()) { (result: Result<MockUser, NetworkError>) in
                    handlerCalled()
                    #expect((try? result.get()) == expected)
                }
                try? await Task.sleep(nanoseconds: 400_000_000)
            }
            #expect(callCount == 2)
        }
    }
}
