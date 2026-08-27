//
//  TestDoubles.swift
//  NetworkKit
//
//  Created by kanagasabapathy.
//

import Foundation
import Testing
@testable import NetworkKit

// MARK: - Stub

final class StubNetworkService: Networkable {
    private let result: any Sendable

    init(result: any Sendable) {
        self.result = result
    }

    private func cannedValue<T>() -> T {
        guard let value = result as? T else {
            fatalError("StubNetworkService not configured for \(T.self)")
        }
        return value
    }

    func sendRequestUsingURLString<T: Decodable & Sendable>(_ urlStr: String) async throws -> T {
        cannedValue()
    }

    func sendRequestUsingEndpoint<T: Decodable & Sendable>(endpoint: EndPoint) async throws -> T {
        cannedValue()
    }

    func sendRequestUsingLegacyCallbackAPI<T: Decodable & Sendable>(
        endpoint: EndPoint,
        resultHandler: @Sendable @escaping (Result<T, NetworkError>) -> Void
    ) {
        resultHandler(.success(cannedValue()))
    }
}

// MARK: - Fake

final class FakeNetworkService: Networkable {
    private actor Storage {
        private var responsesByPath: [String: Data] = [:]

        func set(_ data: Data, for path: String) {
            responsesByPath[path] = data
        }

        func data(for path: String) -> Data? {
            responsesByPath[path]
        }
    }

    private let storage = Storage()

    func stub(path: String, with value: some Encodable) async {
        guard let data = try? JSONEncoder().encode(value) else { return }
        await storage.set(data, for: path)
    }

    private func decoded<T: Decodable>(forPath path: String) async throws -> T {
        guard let data = await storage.data(for: path) else { throw NetworkError.unknown }
        return try JSONDecoder().decode(T.self, from: data)
    }

    func sendRequestUsingURLString<T: Decodable & Sendable>(_ urlStr: String) async throws -> T {
        try await decoded(forPath: urlStr)
    }

    func sendRequestUsingEndpoint<T: Decodable & Sendable>(endpoint: EndPoint) async throws -> T {
        try await Task.sleep(nanoseconds: 10_000_000)
        return try await decoded(forPath: endpoint.path)
    }

    func sendRequestUsingLegacyCallbackAPI<T: Decodable & Sendable>(
        endpoint: EndPoint,
        resultHandler: @Sendable @escaping (Result<T, NetworkError>) -> Void
    ) {
        Task {
            do {
                let value: T = try await decoded(forPath: endpoint.path)
                resultHandler(.success(value))
            } catch {
                resultHandler(.failure(.unknown))
            }
        }
    }
}

// MARK: - Mock

final class MockNetworkService: Networkable {
    private actor CallRecorder {
        private(set) var paths: [String] = []

        func record(_ path: String) {
            paths.append(path)
        }
    }

    private let expectedPath: String
    private let result: any Sendable
    private let recorder = CallRecorder()

    init(expectedPath: String, result: any Sendable) {
        self.expectedPath = expectedPath
        self.result = result
    }

    private func cannedValue<T>() -> T {
        guard let value = result as? T else {
            fatalError("MockNetworkService not configured for \(T.self)")
        }
        return value
    }

    func sendRequestUsingURLString<T: Decodable & Sendable>(_ urlStr: String) async throws -> T {
        await recorder.record(urlStr)
        return cannedValue()
    }

    func sendRequestUsingEndpoint<T: Decodable & Sendable>(endpoint: EndPoint) async throws -> T {
        await recorder.record(endpoint.path)
        return cannedValue()
    }

    func sendRequestUsingLegacyCallbackAPI<T: Decodable & Sendable>(
        endpoint: EndPoint,
        resultHandler: @Sendable @escaping (Result<T, NetworkError>) -> Void
    ) {
        let value: T = cannedValue()
        Task {
            await recorder.record(endpoint.path)
            resultHandler(.success(value))
        }
    }

    func verify(sourceLocation: SourceLocation = #_sourceLocation) async {
        let actualPaths = await recorder.paths
        #expect(actualPaths == [expectedPath],
                "Expected exactly one call to \(expectedPath)",
                sourceLocation: sourceLocation)
    }
}

// MARK: - Spy

final class NetworkServiceSpy: Networkable {
    private actor CallRecorder {
        private(set) var paths: [String] = []

        func record(_ path: String) {
            paths.append(path)
        }
    }

    private let wrapped: Networkable
    private let recorder = CallRecorder()

    init(wrapping wrapped: Networkable) {
        self.wrapped = wrapped
    }

    var requestedPaths: [String] {
        get async { await recorder.paths }
    }

    func sendRequestUsingURLString<T: Decodable & Sendable>(_ urlStr: String) async throws -> T {
        await recorder.record(urlStr)
        return try await wrapped.sendRequestUsingURLString(urlStr)
    }

    func sendRequestUsingEndpoint<T: Decodable & Sendable>(endpoint: EndPoint) async throws -> T {
        await recorder.record(endpoint.path)
        return try await wrapped.sendRequestUsingEndpoint(endpoint: endpoint)
    }

    func sendRequestUsingLegacyCallbackAPI<T: Decodable & Sendable>(
        endpoint: EndPoint,
        resultHandler: @Sendable @escaping (Result<T, NetworkError>) -> Void
    ) {
        Task { await recorder.record(endpoint.path) }
        wrapped.sendRequestUsingLegacyCallbackAPI(endpoint: endpoint, resultHandler: resultHandler)
    }
}
