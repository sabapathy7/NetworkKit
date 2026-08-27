//
//  MockedNetworkTests.swift
//  NetworkKit
//
//  Created by kanagasabapathy.
//

import Testing

// Parent suite for tests sharing MockURLProtocol.requestHandler; .serialized recurses to nested suites.
@Suite(.serialized)
struct MockedNetworkTests {}
