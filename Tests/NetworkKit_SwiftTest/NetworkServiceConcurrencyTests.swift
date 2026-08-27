//
//  NetworkServiceConcurrencyTests.swift
//  NetworkKit
//
//  Created by kanagasabapathy.
//

import Foundation
import Testing
@testable import NetworkKit

extension MockedNetworkTests {
    @Suite
    struct NetworkServiceConcurrencyTests {
        // MARK: Sendable / data race safety

        @Test("NetworkService safely serves many concurrent async requests")
        func manyConcurrentRequestsAllSucceed() async throws {
            let expected = MockUser(id: 42, name: "Grace")
            let configuration = URLSessionConfiguration.mock { request in
                let response = try mockResponse(for: request)
                return (response, try JSONEncoder().encode(expected))
            }
            let service = NetworkService(configuration: configuration)
            let endpoint = MockEndpoint()

            let results = try await withThrowingTaskGroup(of: MockUser.self) { group in
                for _ in 0..<100 {
                    group.addTask {
                        try await service.sendRequestUsingEndpoint(endpoint: endpoint)
                    }
                }
                var collected: [MockUser] = []
                for try await user in group {
                    collected.append(user)
                }
                return collected
            }

            #expect(results.count == 100)
            #expect(results.allSatisfy { $0 == expected })
        }

        @Test("an actor-isolated cache never drops concurrent writes")
        func actorCacheHandlesConcurrentWrites() async {
            actor UserCache {
                private(set) var usersByID: [Int: MockUser] = [:]

                func store(_ user: MockUser) {
                    usersByID[user.id] = user
                }
            }

            let cache = UserCache()

            await withTaskGroup(of: Void.self) { group in
                for i in 0..<100 {
                    group.addTask {
                        await cache.store(MockUser(id: i, name: "User \(i)"))
                    }
                }
            }

            let count = await cache.usersByID.count
            #expect(count == 100)
        }

        // MARK: Actor isolation / MainActor

        @Test("a @MainActor view model only mutates its state on the main actor")
        @MainActor
        func viewModelUpdatesOnMainActor() async {
            let expected = MockUser(id: 7, name: "Barbara")
            let configuration = URLSessionConfiguration.mock { request in
                let response = try mockResponse(for: request)
                return (response, try JSONEncoder().encode(expected))
            }
            let service = NetworkService(configuration: configuration)
            let viewModel = UserViewModel(service: service)

            viewModel.load(endpoint: MockEndpoint())

            try? await Task.sleep(nanoseconds: 400_000_000)

            #expect(viewModel.user == expected)
        }
    }
}

@MainActor
private final class UserViewModel {
    private(set) var user: MockUser?
    private let service: Networkable

    init(service: Networkable) {
        self.service = service
    }

    func load(endpoint: EndPoint) {
        service.sendRequestUsingLegacyCallbackAPI(endpoint: endpoint) { [weak self] (result: Result<MockUser, NetworkError>) in
            guard let user = try? result.get() else { return }
            Task { @MainActor [weak self] in
                self?.user = user
            }
        }
    }
}
