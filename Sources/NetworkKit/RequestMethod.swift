//
//  RequestMethod.swift
//  IosNetworkExample
//
//  Created by kanagasabapathy on 01/01/24.
//

import Foundation

public enum RequestMethod: String, Sendable {
    case delete = "DELETE"
    case get = "GET"
    case patch = "PATCH"
    case post = "POST"
    case put = "PUT"
}
