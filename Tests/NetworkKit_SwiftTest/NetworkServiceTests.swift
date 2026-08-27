//
//  NetworkServiceTests.swift
//  NetworkKit
//
//  Created by kanagasabapathy.
//

#if canImport(Combine)
import Combine
#endif
import Foundation
import Testing
@testable import NetworkKit

extension MockedNetworkTests {
    @Suite
    struct NetworkServiceTests {
        let endpoint = MockEndpoint()

        // MARK: async/await

        @Test("async/await decodes a successful response")
        func asyncSuccess() async throws {
            let expected = MockUser(id: 1, name: "Ada")
            let configuration = URLSessionConfiguration.mock { request in
                let response = try mockResponse(for: request)
                return (response, try JSONEncoder().encode(expected))
            }
            let service = NetworkService(configuration: configuration)

            let result: MockUser = try await service.sendRequestUsingEndpoint(endpoint: endpoint)

            #expect(result == expected)
        }

        @Test("async/await throws .decode for malformed JSON")
        func asyncDecodeFailure() async {
            let service = NetworkService(configuration: .mockStatusCode(200, data: Data("not json".utf8)))

            await #expect(throws: NetworkError.decode) {
                let _: MockUser = try await service.sendRequestUsingEndpoint(endpoint: endpoint)
            }
        }

        @Test("async/await throws .unexpectedStatusCode for a non-2xx response")
        func asyncBadStatusCode() async {
            let service = NetworkService(configuration: .mockStatusCode(500))

            await #expect(throws: NetworkError.unexpectedStatusCode) {
                let _: MockUser = try await service.sendRequestUsingEndpoint(endpoint: endpoint)
            }
        }

        @Test("async/await decodes a response fetched by raw URL string")
        func asyncURLStringSuccess() async throws {
            let expected = MockUser(id: 2, name: "Grace")
            let configuration = URLSessionConfiguration.mock { request in
                let response = try mockResponse(for: request)
                return (response, try JSONEncoder().encode(expected))
            }
            let service = NetworkService(configuration: configuration)

            let result: MockUser = try await service.sendRequestUsingURLString("https://api.example.com/users/2")

            #expect(result == expected)
        }

        @Test("async/await throws .invalidURL for an unparseable URL string")
        func asyncURLStringInvalid() async {
            let service = NetworkService(configuration: .mockStatusCode(200))

            await #expect(throws: NetworkError.invalidURL) {
                let _: MockUser = try await service.sendRequestUsingURLString("")
            }
        }

        // MARK: legacy callback

        @Test("legacy callback delivers a successful decoded result")
        func legacyCallbackSuccess() async {
            let expected = MockUser(id: 3, name: "Hedy")
            let configuration = URLSessionConfiguration.mock { request in
                let response = try mockResponse(for: request)
                return (response, try JSONEncoder().encode(expected))
            }
            let service = NetworkService(configuration: configuration)

            await confirmation("resultHandler is called exactly once") { handlerCalled in
                service.sendRequestUsingLegacyCallbackAPI(endpoint: endpoint) { (result: Result<MockUser, NetworkError>) in
                    handlerCalled()
                    #expect((try? result.get()) == expected)
                }
                try? await Task.sleep(nanoseconds: 300_000_000)
            }
        }

        @Test("legacy callback delivers .unexpectedStatusCode for a non-2xx response")
        func legacyCallbackFailure() async {
            let service = NetworkService(configuration: .mockStatusCode(404))

            await confirmation("resultHandler is called exactly once") { handlerCalled in
                service.sendRequestUsingLegacyCallbackAPI(endpoint: endpoint) { (result: Result<MockUser, NetworkError>) in
                    handlerCalled()
                    #expect(result == .failure(.unexpectedStatusCode))
                }
                try? await Task.sleep(nanoseconds: 300_000_000)
            }
        }

        // MARK: Combine publisher

#if canImport(Combine)
        @Test("publisher emits a successful decoded value")
        func publisherSuccess() async {
            let expected = MockUser(id: 4, name: "Alan")
            let configuration = URLSessionConfiguration.mock { request in
                let response = try mockResponse(for: request)
                return (response, try JSONEncoder().encode(expected))
            }
            let service = NetworkService(configuration: configuration)

            await confirmation("publisher finishes") { finished in
                var cancellables = Set<AnyCancellable>()
                service.sendRequestUsingCombine(endpoint: endpoint, type: MockUser.self)
                    .sink(
                        receiveCompletion: { _ in finished() },
                        receiveValue: { user in #expect(user == expected) }
                    )
                    .store(in: &cancellables)
                try? await Task.sleep(nanoseconds: 300_000_000)
            }
        }

        @Test("publisher fails with .unexpectedStatusCode for a non-2xx response")
        func publisherFailure() async {
            let service = NetworkService(configuration: .mockStatusCode(500))

            await confirmation("publisher fails") { failed in
                var cancellables = Set<AnyCancellable>()
                service.sendRequestUsingCombine(endpoint: endpoint, type: MockUser.self)
                    .sink(
                        receiveCompletion: { completion in
                            if case .failure(let error) = completion {
                                #expect(error == .unexpectedStatusCode)
                                failed()
                            }
                        },
                        receiveValue: { _ in Issue.record("Did not expect a value") }
                    )
                    .store(in: &cancellables)
                try? await Task.sleep(nanoseconds: 300_000_000)
            }
        }
#endif

        // MARK: queryParams / pathParams

        @Test("queryParams become query items on the actual request URL")
        func queryParamsBecomeQueryItems() async throws {
            let expected = MockUser(id: 1, name: "Ada")
            let requestEndpoint = MockEndpoint(path: "/search", queryParams: ["q": "swift", "page": "1"])
            let configuration = URLSessionConfiguration.mock { request in
                let components = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)!
                #expect(Set(components.queryItems ?? []) == [
                    URLQueryItem(name: "q", value: "swift"),
                    URLQueryItem(name: "page", value: "1")
                ])
                let response = try mockResponse(for: request)
                return (response, try JSONEncoder().encode(expected))
            }
            let service = NetworkService(configuration: configuration)

            let _: MockUser = try await service.sendRequestUsingEndpoint(endpoint: requestEndpoint)
        }

        @Test("pathParams substitute {key} placeholders in the path")
        func pathParamsSubstituteIntoPath() async throws {
            let expected = MockUser(id: 2, name: "Grace")
            let requestEndpoint = MockEndpoint(path: "/users/{id}/posts/{postId}",
                                               pathParams: ["id": "42", "postId": "7"])
            let configuration = URLSessionConfiguration.mock { request in
                let path = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)!.path
                #expect(path == "/users/42/posts/7")
                let response = try mockResponse(for: request)
                return (response, try JSONEncoder().encode(expected))
            }
            let service = NetworkService(configuration: configuration)

            let _: MockUser = try await service.sendRequestUsingEndpoint(endpoint: requestEndpoint)
        }

        @Test("a '/' in a path param value is percent-encoded, not treated as a path separator")
        func pathParamValueWithSlashIsEncoded() async throws {
            let expected = MockUser(id: 3, name: "Ada")
            let requestEndpoint = MockEndpoint(path: "/files/{name}", pathParams: ["name": "a/b"])
            let configuration = URLSessionConfiguration.mock { request in
                #expect(request.url!.pathComponents == ["/", "files", "a%2Fb"])
                let response = try mockResponse(for: request)
                return (response, try JSONEncoder().encode(expected))
            }
            let service = NetworkService(configuration: configuration)

            let _: MockUser = try await service.sendRequestUsingEndpoint(endpoint: requestEndpoint)
        }

        @Test("an unmatched path placeholder is left literal")
        func unmatchedPathPlaceholderStaysLiteral() async throws {
            let expected = MockUser(id: 4, name: "Hedy")
            let requestEndpoint = MockEndpoint(path: "/users/{id}", pathParams: nil)
            let configuration = URLSessionConfiguration.mock { request in
                let path = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)!.path
                #expect(path == "/users/{id}")
                let response = try mockResponse(for: request)
                return (response, try JSONEncoder().encode(expected))
            }
            let service = NetworkService(configuration: configuration)

            let _: MockUser = try await service.sendRequestUsingEndpoint(endpoint: requestEndpoint)
        }
    }
}
