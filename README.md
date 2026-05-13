# NetworkKit

Elevate your app’s connectivity with NetworkKit — a small, modular network layer that supports **Combine** (on Apple platforms), **async/await**, **`withCheckedThrowingContinuation`**, and **closures**, with **Swift concurrency** (`Sendable`, strict concurrency checks) in mind.

## Requirements

- **Swift:** 5.9+
- **Platforms:** iOS 15+, macOS 12+, watchOS 8+, tvOS 15+, visionOS 1+

Combine-backed APIs are available only where **Combine** exists (Apple platforms). The core protocol and async/closure APIs build on **Linux** and other environments without Combine.

## Features

- **Combine** — `NetworkService.sendRequest(endpoint:type:)` returns `AnyPublisher` (Apple platforms only).
- **Async/await (native URLSession)** — `sendRequest(urlStr:)` uses `URLSession`’s async `data(from:)`.
- **Async/await + continuation** — `sendRequest(endpoint:)` bridges `URLSession.dataTask` with `withCheckedThrowingContinuation`.
- **Closures** — `sendRequest(endpoint:resultHandler:)` with a `@Sendable` completion handler.
- **Injectable session** — `NetworkService(configuration:)` for tests (e.g. custom `URLSessionConfiguration` / `URLProtocol`).

## Installation (Swift Package Manager)

**Xcode:** File → Add Package Dependencies… → enter the repository URL.

**`Package.swift`:**

```swift
.package(url: "https://github.com/sabapathy7/NetworkKit.git", from: "1.0.8")
```

Use the [Releases](https://github.com/sabapathy7/NetworkKit/releases) page and set `from:` to the lowest version you support (or pin an exact revision if you prefer).

## Usage overview

Define types that conform to `EndPoint`, then use `NetworkService`:

```swift
import NetworkKit

let service = NetworkService()

// Async/await — URL string (native URLSession)
let dict: [String: String] = try await service.sendRequest(urlStr: "https://api.example.com/v1/config")

// Async/await — endpoint (withCheckedThrowingContinuation + dataTask)
let user: User = try await service.sendRequest(endpoint: UserEndpoint.profile)

// Closure
service.sendRequest(endpoint: UserEndpoint.profile) { (result: Result<User, NetworkError>) in
    switch result {
    case .success(let user): print(user)
    case .failure(let error): print(error.customMessage)
    }
}

#if canImport(Combine)
import Combine

// Combine (Apple platforms)
var cancellables = Set<AnyCancellable>()
service.sendRequest(endpoint: UserEndpoint.profile, type: User.self)
    .sink(receiveCompletion: { _ in }, receiveValue: { print($0) })
    .store(in: &cancellables)
#endif
```

### Protocol surface

`Networkable` covers URL async, endpoint async, and the closure API. The Combine publisher lives on **`NetworkService`** so the protocol stays portable without Combine:

```swift
public protocol Networkable: Sendable {
    func sendRequest<T: Decodable & Sendable>(urlStr: String) async throws -> T
    func sendRequest<T: Decodable & Sendable>(endpoint: EndPoint) async throws -> T
    func sendRequest<T: Decodable & Sendable>(
        endpoint: EndPoint,
        resultHandler: @Sendable @escaping (Result<T, NetworkError>) -> Void
    )
}
```

## Develop and test locally

```bash
git clone https://github.com/sabapathy7/NetworkKit.git
cd NetworkKit
swift build
swift test
```

## Ecosystem

- **Swift Package Index:** [sabapathy7/NetworkKit](https://swiftpackageindex.com/sabapathy7/NetworkKit)
- **Repository:** [github.com/sabapathy7/NetworkKit](https://github.com/sabapathy7/NetworkKit)

## Full tutorial and examples

- [Tutorial on Medium](https://sabapathy7.medium.com/how-to-create-a-network-layer-for-your-ios-app-623f99161677)
- [iOS Network Example](https://github.com/sabapathyk7/iOSNetworkExample)
- [SOLID Principles Example](https://github.com/sabapathyk7/SOLIDPrinciplesExample)
- [Force Update App Example](https://github.com/sabapathyk7/ForceUpdateExample)

## Contributions

Issues and pull requests are welcome on [GitHub](https://github.com/sabapathy7/NetworkKit).

## Connect

[Kanagasabapathy on LinkedIn](https://www.linkedin.com/in/sabapathy7/)

## License

MIT — see [LICENSE](LICENSE).
