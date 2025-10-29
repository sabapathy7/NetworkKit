//
//  RequestMethod.swift
//  IosNetworkExample
//
//  Created by kanagasabapathy on 01/01/24.
//

import Foundation

/// HTTP request methods supported by the networking layer
/// Conforms to Sendable for safe concurrent usage
public enum RequestMethod: String, Sendable {
    case get = "GET"
    case post = "POST"
    case put = "PUT"
    case patch = "PATCH"
    case delete = "DELETE"
}
