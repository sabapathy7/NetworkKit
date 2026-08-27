//
//  TestFixtures.swift
//  NetworkKit
//
//  Shared model/endpoint used across NetworkService test suites.
//

import Foundation
@testable import NetworkKit

struct MockUser: Codable, Sendable, Equatable {
    let id: Int
    let name: String
}

struct MockEndpoint: EndPoint, Sendable {
    var host: String = "api.example.com"
    var scheme: String = "https"
    var path: String = "/users/1"
    var method: RequestMethod = .get
    var header: [String: String]?
    var body: [String: String]?
    var queryParams: [String: String]?
    var pathParams: [String: String]?
}
