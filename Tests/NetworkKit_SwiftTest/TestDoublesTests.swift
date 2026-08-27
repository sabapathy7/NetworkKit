//
//  TestDoublesTests.swift
//  NetworkKit
//
//  Created by kanagasabapathy.
//

import Foundation
import Testing
@testable import NetworkKit

extension MockedNetworkTests {
    @Suite
    struct TestDoublesTests {
        // MARK: Stub — canned answer, no memory of the call

        @Test("stub returns its canned result no matter which endpoint is asked")
        func stubReturnsCannedResultRegardlessOfEndpoint() async throws {
            let stub = StubNetworkService(result: MockUser(id: 1, name: "Ada"))

            let first: MockUser = try await stub.sendRequestUsingEndpoint(endpoint: MockEndpoint(path: "/users/1"))
            let second: MockUser = try await stub.sendRequestUsingEndpoint(endpoint: MockEndpoint(path: "/completely/different/path"))

            #expect(first == MockUser(id: 1, name: "Ada"))
            #expect(second == first)
        }

        // MARK: Fake — real logic, no real I/O

        @Test("fake decodes real per-path responses, unlike a stub's single canned answer")
        func fakeRoutesResponsesPerPath() async throws {
            let fake = FakeNetworkService()
            await fake.stub(path: "/users/1", with: MockUser(id: 1, name: "Ada"))
            await fake.stub(path: "/users/2", with: MockUser(id: 2, name: "Grace"))

            let first: MockUser = try await fake.sendRequestUsingEndpoint(endpoint: MockEndpoint(path: "/users/1"))
            let second: MockUser = try await fake.sendRequestUsingEndpoint(endpoint: MockEndpoint(path: "/users/2"))

            #expect(first == MockUser(id: 1, name: "Ada"))
            #expect(second == MockUser(id: 2, name: "Grace"))
        }

        @Test("fake throws for a path nobody stubbed a response for")
        func fakeThrowsForUnknownPath() async {
            let fake = FakeNetworkService()

            await #expect(throws: NetworkError.unknown) {
                let _: MockUser = try await fake.sendRequestUsingEndpoint(endpoint: MockEndpoint(path: "/nowhere"))
            }
        }

        // MARK: Mock — pre-programmed expectation, verifies itself

        @Test("mock verifies it was called with the exact endpoint it expected")
        func mockVerifiesExpectedCall() async throws {
            let mock = MockNetworkService(expectedPath: "/users/1", result: MockUser(id: 1, name: "Ada"))

            let _: MockUser = try await mock.sendRequestUsingEndpoint(endpoint: MockEndpoint(path: "/users/1"))

            await mock.verify()
        }

        @Test("mock verify surfaces a failure when called with an unexpected endpoint")
        func mockVerifyCatchesUnexpectedCall() async throws {
            let mock = MockNetworkService(expectedPath: "/users/1", result: MockUser(id: 1, name: "Ada"))

            let _: MockUser = try await mock.sendRequestUsingEndpoint(endpoint: MockEndpoint(path: "/users/999"))

            await withKnownIssue("mock was called with a path other than the one it expected") {
                await mock.verify()
            }
        }

        // MARK: Spy — delegates to the real thing, records what happened

        @Test("spy records every call it forwards to the real service")
        func spyRecordsCallsToRealService() async throws {
            let expected = MockUser(id: 9, name: "Hedy")
            let configuration = URLSessionConfiguration.mock { request in
                let response = try mockResponse(for: request)
                return (response, try JSONEncoder().encode(expected))
            }
            let real = NetworkService(configuration: configuration)
            let spy = NetworkServiceSpy(wrapping: real)

            let result: MockUser = try await spy.sendRequestUsingEndpoint(endpoint: MockEndpoint(path: "/users/9"))

            #expect(result == expected)
            #expect(await spy.requestedPaths == ["/users/9"])
        }
    }
}
