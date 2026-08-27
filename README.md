# NetworkKit

Elevate your app’s connectivity with NetworkKit — a small, modular network layer that supports **Combine** (on Apple platforms), **async/await**, **closures**, and a **legacy callback bridge**, with **Swift concurrency** in mind.

## Requirements

- **Swift:** 5.9+
- **Platforms:** iOS 15+, macOS 12+, watchOS 8+, tvOS 15+, visionOS 1+

Combine-backed APIs are available only where **Combine** exists (Apple platforms). The core protocol and async/closure APIs build on **Linux** and other environments without Combine.

## Features

- **Combine** — `NetworkService.sendRequestUsingCombine(endpoint:type:)` returns `AnyPublisher` (Apple platforms only).
- **Async/await — URL string** — `sendRequestUsingURLString(_:)` for a one-off raw URL.
- **Async/await — endpoint** — `sendRequestUsingEndpoint(endpoint:)` for a structured `EndPoint`.
- **Legacy callback** — `sendRequestUsingLegacyCallbackAPI(endpoint:resultHandler:)` with a `@Sendable` completion handler, for callers not yet on async/await.
- **Adapters & retry** — `RequestAdapting` mutates each request before it is sent (e.g. auth tokens); `RequestRetrying` decides whether a failure is retried, bounded by `maxRetryCount`.
- **Injectable session** — `NetworkService(configuration:)` for tests (e.g. custom `URLSessionConfiguration` / `URLProtocol`).

## Installation (Swift Package Manager)

**Xcode:** File → Add Package Dependencies… → enter the repository URL.

**`Package.swift`:**

```swift
.package(url: "https://github.com/sabapathy7/NetworkKit.git", from: "2.0.0")
```

Use the [Releases](https://github.com/sabapathy7/NetworkKit/releases) page and set `from:` to the lowest version you support (or pin an exact revision if you prefer).

## Usage overview

Define types that conform to `EndPoint`, then use `NetworkService`:

```swift
import NetworkKit

let service = NetworkService()

// Async/await — raw URL string
let dict: [String: String] = try await service.sendRequestUsingURLString("https://api.example.com/v1/config")

// Async/await — endpoint
let user: User = try await service.sendRequestUsingEndpoint(endpoint: UserEndpoint.profile)

// Legacy callback
service.sendRequestUsingLegacyCallbackAPI(endpoint: UserEndpoint.profile) { (result: Result<User, NetworkError>) in
    switch result {
    case .success(let user): print(user)
    case .failure(let error): print(error.customMessage)
    }
}

#if canImport(Combine)
import Combine

// Combine (Apple platforms)
var cancellables = Set<AnyCancellable>()
service.sendRequestUsingCombine(endpoint: UserEndpoint.profile, type: User.self)
    .sink(receiveCompletion: { _ in }, receiveValue: { print($0) })
    .store(in: &cancellables)
#endif
```

### Protocol surface

`Networkable` covers URL async, endpoint async, and the closure API. The Combine publisher lives on **`NetworkService`** so the protocol stays portable without Combine:

```swift
public protocol Networkable: Sendable {
    func sendRequestUsingURLString<T: Decodable & Sendable>(_ urlStr: String) async throws -> T
    func sendRequestUsingEndpoint<T: Decodable & Sendable>(endpoint: EndPoint) async throws -> T
    func sendRequestUsingLegacyCallbackAPI<T: Decodable & Sendable>(
        endpoint: EndPoint,
        resultHandler: @Sendable @escaping (Result<T, NetworkError>) -> Void
    )
}
```

## Migrating from 1.x

Every request method is renamed for how it is called, so overloads no longer
differ only by argument label:

| 1.x | 2.0 |
|---|---|
| `sendRequest(urlStr:)` | `sendRequestUsingURLString(_:)` |
| `sendRequest(endpoint:)` | `sendRequestUsingEndpoint(endpoint:)` |
| `sendRequest(endpoint:resultHandler:)` | `sendRequestUsingLegacyCallbackAPI(endpoint:resultHandler:)` |
| `sendRequest(endpoint:type:)` | `sendRequestUsingCombine(endpoint:type:)` |

The endpoint-based async continuation method is removed — `sendRequestUsingEndpoint`
covers it using `URLSession`'s native async API.

Adapters and retrying come from `NetworkKitCore`, so `import NetworkKitCore`
where you conform to `RequestAdapting` or `RequestRetrying`.

## Develop and test locally

```bash
git clone https://github.com/sabapathy7/NetworkKit.git
cd NetworkKit
swift build
swift test
```

## Links

- [Swift Package Index](https://swiftpackageindex.com/sabapathy7/NetworkKit)
- [Tutorial on Medium](https://sabapathy7.medium.com/how-to-create-a-network-layer-for-your-ios-app-623f99161677)
- [Kanagasabapathy on LinkedIn](https://www.linkedin.com/in/sabapathy7/)

## Contributions

Issues and pull requests are welcome.

## License

MIT — see [LICENSE](LICENSE).
