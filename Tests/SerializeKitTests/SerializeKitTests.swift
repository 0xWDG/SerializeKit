//
//  SerializeKitTests.swift
//  SerializeKit
//
//  Created by Wesley de Groot on 2026-08-13.
//  https://wesleydegroot.nl
//
//  https://github.com/0xWDG/SerializeKit
//  MIT License
//

import Foundation
import Testing
@testable import SerializeKit

private struct CodableUser: Codable, Equatable {
    let id: Int64
    let displayName: String
    let isActive: Bool
    let nickname: String?
    let scores: [Double]
    let metadata: [String: Int]
    let avatar: Data
    let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case displayName = "display_name"
        case isActive = "is_active"
        case nickname, scores, metadata, avatar
        case createdAt = "created_at"
    }
}

@Test func serializesScalarValuesLikePHP() throws {
    #expect(try PHPSerializer.serializeString(.null) == "N;")
    #expect(try PHPSerializer.serializeString(true) == "b:1;")
    #expect(try PHPSerializer.serializeString(42) == "i:42;")
    #expect(try PHPSerializer.serializeString(1.5) == "d:1.5;")
    #expect(try PHPSerializer.serializeString("héllo") == "s:6:\"héllo\";")
    #expect(try PHPSerializer.serializeString(.double(-0.0)) == "d:-0;")
    #expect(try PHPSerializer.serializeString(.double(1.0e20)) == "d:1.0E+20;")
    #expect(try PHPSerializer.serializeString(.double(1.0e-7)) == "d:1.0E-7;")
    #expect(try PHPSerializer.serializeString(.double(.infinity)) == "d:INF;")
    #expect(try PHPSerializer.serializeString(.double(-.infinity)) == "d:-INF;")
    #expect(try PHPSerializer.serializeString(.double(.nan)) == "d:NAN;")
}

@Test func roundTripsMixedPHPArrayKeys() throws {
    let value: PHPValue = [
        "name": "Wesley",
        2: true,
        "items": [1, nil, 3.5]
    ]

    let serialized = try PHPSerializer.serializeString(value)
    #expect(serialized == "a:3:{s:4:\"name\";s:6:\"Wesley\";i:2;b:1;s:5:\"items\";a:3:{i:0;i:1;i:1;N;i:2;d:3.5;}}")
    #expect(try PHPSerializer.unserialize(serialized) == value)
}

@Test func preservesBinaryStrings() throws {
    let bytes = Data([0x00, 0xFF, 0x41])
    let value = PHPValue.string(PHPString(data: bytes))
    let serialized = PHPSerializer.serialize(value)

    #expect(serialized.prefix(5) == Data("s:3:\"".utf8))
    #expect(try PHPSerializer.unserialize(serialized) == value)
    #expect(throws: PHPSerializationError.invalidStringEncoding) {
        try PHPSerializer.serializeString(value)
    }
}

@Test func readsAndWritesObjectsWithoutInstantiatingClasses() throws {
    let value = PHPValue.object(
        className: "User",
        properties: [PHPObjectProperty(name: "name", value: "Wesley")]
    )
    let serialized = "O:4:\"User\":1:{s:4:\"name\";s:6:\"Wesley\";}"

    #expect(try PHPSerializer.serializeString(value) == serialized)
    #expect(try PHPSerializer.unserialize(serialized) == value)
}

@Test func rejectsMalformedAndTrailingData() {
    #expect(throws: PHPSerializationError.trailingData(offset: 2)) {
        try PHPSerializer.unserialize("N;N;")
    }
    #expect(throws: PHPSerializationError.unexpectedEnd(offset: 5)) {
        try PHPSerializer.unserialize("s:4:\"")
    }
    #expect(throws: PHPSerializationError.unsupportedType(82, offset: 0)) {
        try PHPSerializer.unserialize("R:1;")
    }
}

@Test func enforcesMaximumDepth() {
    #expect((try? PHPSerializer.unserialize("a:1:{i:0;N;}", maximumDepth: 1)) != nil)
    #expect(throws: PHPSerializationError.maximumDepthExceeded(limit: 1)) {
        try PHPSerializer.unserialize("a:1:{i:0;a:1:{i:0;N;}}", maximumDepth: 1)
    }
    #expect((try? PHPSerializer.unserialize("a:1:{i:0;a:1:{i:0;N;}}", maximumDepth: 0)) != nil)
}

@Test func serializesAndUnserializesCodableModels() throws {
    let user = CodableUser(
        id: 9_007_199_254_740_993,
        displayName: "Wesley",
        isActive: true,
        nickname: nil,
        scores: [9.5, 8],
        metadata: ["visits": 3],
        avatar: Data([0x00, 0xFF]),
        createdAt: Date(timeIntervalSinceReferenceDate: 123_456)
    )

    let serialized = try PHPSerializer.serialize(user)
    let restored = try PHPSerializer.unserialize(CodableUser.self, from: serialized)

    #expect(restored == user)
    #expect(String(bytes: serialized.prefix(4), encoding: .utf8) == "a:7:")
}

@Test func codableUsesCodingKeysAndPHPArrayShapes() throws {
    struct Profile: Codable, Equatable {
        let name: String
        let tags: [String]
    }

    let serialized = try PHPSerializer.serializeString(Profile(name: "Ana", tags: ["swift", "php"]))
    #expect(serialized == "a:2:{s:4:\"name\";s:3:\"Ana\";s:4:\"tags\";a:2:{i:0;s:5:\"swift\";i:1;s:3:\"php\";}}")
    let restored = try PHPSerializer.unserialize(Profile.self, from: serialized)
    #expect(restored == Profile(name: "Ana", tags: ["swift", "php"]))
}

@Test func codableReportsKeyedTypeMismatch() throws {
    struct Identifier: Decodable {
        let id: Int
    }

    do {
        _ = try PHPSerializer.unserialize(Identifier.self, from: "a:1:{s:2:\"id\";s:3:\"one\";}")
        Issue.record("Expected decoding to fail")
    } catch let DecodingError.typeMismatch(_, context) {
        #expect(context.codingPath.map(\.stringValue) == ["id"])
    }
}

@Test func codableRoundTripsIntegerKeyedDictionaries() throws {
    let value = [2: "two", 7: "seven"]
    let serialized = try PHPSerializer.serialize(value)
    let restored = try PHPSerializer.unserialize([Int: String].self, from: serialized)

    #expect(restored == value)
}
