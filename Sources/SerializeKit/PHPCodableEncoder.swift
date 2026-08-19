//
//  PHPCodableEncoder.swift
//  SerializeKit
//
//  Created by Wesley de Groot on 2026-08-13.
//  https://wesleydegroot.nl
//
//  https://github.com/0xWDG/SerializeKit
//  MIT License
//

import Foundation

/// Encodes `Encodable` values into the PHP serialization value model.
public final class PHPCodableEncoder {
    /// Contextual values made available to custom `Encodable` implementations.
    public var userInfo: [CodingUserInfoKey: Any] = [:]

    /// Creates a PHP Codable encoder.
    public init() {}

    /// Encodes a value into a ``PHPValue``.
    public func encode<T: Encodable>(_ value: T) throws -> PHPValue {
        let node = PHPEncodingNode()
        let encoder = PHPValueEncoder(node: node, codingPath: [], userInfo: userInfo)
        try encoder.encode(value)
        return try node.materialized(codingPath: [])
    }
}

private final class PHPEncodingNode {
    enum Storage {
        case unset
        case value(PHPValue)
        case keyed(PHPKeyedEncodingStorage)
        case unkeyed(PHPUnkeyedEncodingStorage)
    }

    var storage = Storage.unset

    func materialized(codingPath: [any CodingKey]) throws -> PHPValue {
        switch storage {
        case .unset:
            throw EncodingError.invalidValue(
                self,
                EncodingError.Context(
                    codingPath: codingPath,
                    debugDescription: "The value did not encode any content."
                )
            )
        case .value(let value):
            return value
        case .keyed(let storage):
            return .array(try storage.entries.map { entry in
                PHPArrayElement(
                    key: entry.phpKey,
                    value: try entry.node.materialized(codingPath: codingPath + [entry.codingKey])
                )
            })
        case .unkeyed(let storage):
            return .array(try storage.nodes.enumerated().map { index, node in
                PHPArrayElement(
                    key: .integer(Int64(index)),
                    value: try node.materialized(codingPath: codingPath + [PHPIndexKey(index)])
                )
            })
        }
    }
}

private final class PHPKeyedEncodingStorage {
    struct Entry {
        let phpKey: PHPKey
        let codingKey: any CodingKey
        let node: PHPEncodingNode
    }

    private var indices: [String: Int] = [:]
    private(set) var entries: [Entry] = []

    func node(for key: some CodingKey) -> PHPEncodingNode {
        if let index = indices[key.stringValue] {
            return entries[index].node
        }
        let node = PHPEncodingNode()
        indices[key.stringValue] = entries.count
        let phpKey = key.intValue.map { PHPKey.integer(Int64($0)) }
            ?? .string(PHPString(key.stringValue))
        entries.append(Entry(phpKey: phpKey, codingKey: key, node: node))
        return node
    }
}

private final class PHPUnkeyedEncodingStorage {
    private(set) var nodes: [PHPEncodingNode] = []

    func appendNode() -> PHPEncodingNode {
        let node = PHPEncodingNode()
        nodes.append(node)
        return node
    }
}

private final class PHPValueEncoder: Encoder {
    let node: PHPEncodingNode
    let codingPath: [any CodingKey]
    let userInfo: [CodingUserInfoKey: Any]

    init(
        node: PHPEncodingNode,
        codingPath: [any CodingKey],
        userInfo: [CodingUserInfoKey: Any]
    ) {
        self.node = node
        self.codingPath = codingPath
        self.userInfo = userInfo
    }

    func container<Key: CodingKey>(keyedBy type: Key.Type) -> KeyedEncodingContainer<Key> {
        let storage: PHPKeyedEncodingStorage
        if case .keyed(let existing) = node.storage {
            storage = existing
        } else {
            storage = PHPKeyedEncodingStorage()
            node.storage = .keyed(storage)
        }
        let container = PHPKeyedEncodingContainer<Key>(
            storage: storage,
            codingPath: codingPath,
            userInfo: userInfo
        )
        return KeyedEncodingContainer(container)
    }

    func unkeyedContainer() -> any UnkeyedEncodingContainer {
        let storage: PHPUnkeyedEncodingStorage
        if case .unkeyed(let existing) = node.storage {
            storage = existing
        } else {
            storage = PHPUnkeyedEncodingStorage()
            node.storage = .unkeyed(storage)
        }
        return PHPUnkeyedEncodingContainer(
            storage: storage,
            codingPath: codingPath,
            userInfo: userInfo
        )
    }

    func singleValueContainer() -> any SingleValueEncodingContainer {
        PHPSingleValueEncodingContainer(node: node, codingPath: codingPath, userInfo: userInfo)
    }

    func encode<T: Encodable>(_ value: T) throws {
        try encodeEncodable(value, into: node, codingPath: codingPath, userInfo: userInfo)
    }
}

private struct PHPKeyedEncodingContainer<Key: CodingKey>: KeyedEncodingContainerProtocol {
    let storage: PHPKeyedEncodingStorage
    let codingPath: [any CodingKey]
    let userInfo: [CodingUserInfoKey: Any]

    mutating func encodeNil(forKey key: Key) throws {
        storage.node(for: key).storage = .value(.null)
    }

    mutating func encode<T: Encodable>(_ value: T, forKey key: Key) throws {
        try encodeEncodable(
            value,
            into: storage.node(for: key),
            codingPath: codingPath + [key],
            userInfo: userInfo
        )
    }

    mutating func nestedContainer<NestedKey: CodingKey>(
        keyedBy keyType: NestedKey.Type,
        forKey key: Key
    ) -> KeyedEncodingContainer<NestedKey> {
        PHPValueEncoder(
            node: storage.node(for: key),
            codingPath: codingPath + [key],
            userInfo: userInfo
        ).container(keyedBy: keyType)
    }

    mutating func nestedUnkeyedContainer(forKey key: Key) -> any UnkeyedEncodingContainer {
        PHPValueEncoder(
            node: storage.node(for: key),
            codingPath: codingPath + [key],
            userInfo: userInfo
        ).unkeyedContainer()
    }

    mutating func superEncoder() -> any Encoder {
        let key = PHPIndexKey.superKey
        return PHPValueEncoder(
            node: storage.node(for: key),
            codingPath: codingPath + [key],
            userInfo: userInfo
        )
    }

    mutating func superEncoder(forKey key: Key) -> any Encoder {
        PHPValueEncoder(
            node: storage.node(for: key),
            codingPath: codingPath + [key],
            userInfo: userInfo
        )
    }
}

private struct PHPUnkeyedEncodingContainer: UnkeyedEncodingContainer {
    let storage: PHPUnkeyedEncodingStorage
    let codingPath: [any CodingKey]
    let userInfo: [CodingUserInfoKey: Any]

    var count: Int { storage.nodes.count }

    mutating func encodeNil() throws {
        storage.appendNode().storage = .value(.null)
    }

    mutating func encode<T: Encodable>(_ value: T) throws {
        let index = count
        try encodeEncodable(
            value,
            into: storage.appendNode(),
            codingPath: codingPath + [PHPIndexKey(index)],
            userInfo: userInfo
        )
    }

    mutating func nestedContainer<NestedKey: CodingKey>(
        keyedBy keyType: NestedKey.Type
    ) -> KeyedEncodingContainer<NestedKey> {
        let index = count
        return PHPValueEncoder(
            node: storage.appendNode(),
            codingPath: codingPath + [PHPIndexKey(index)],
            userInfo: userInfo
        ).container(keyedBy: keyType)
    }

    mutating func nestedUnkeyedContainer() -> any UnkeyedEncodingContainer {
        let index = count
        return PHPValueEncoder(
            node: storage.appendNode(),
            codingPath: codingPath + [PHPIndexKey(index)],
            userInfo: userInfo
        ).unkeyedContainer()
    }

    mutating func superEncoder() -> any Encoder {
        let index = count
        return PHPValueEncoder(
            node: storage.appendNode(),
            codingPath: codingPath + [PHPIndexKey(index)],
            userInfo: userInfo
        )
    }
}

private struct PHPSingleValueEncodingContainer: SingleValueEncodingContainer {
    let node: PHPEncodingNode
    let codingPath: [any CodingKey]
    let userInfo: [CodingUserInfoKey: Any]

    func encodeNil() throws { node.storage = .value(.null) }
    func encode(_ value: Bool) throws { node.storage = .value(.boolean(value)) }
    func encode(_ value: String) throws { node.storage = .value(.string(PHPString(value))) }
    func encode(_ value: Double) throws { node.storage = .value(.double(value)) }
    func encode(_ value: Float) throws { node.storage = .value(.double(Double(value))) }
    func encode(_ value: Int) throws { try encodeInteger(value) }
    func encode(_ value: Int8) throws { try encodeInteger(value) }
    func encode(_ value: Int16) throws { try encodeInteger(value) }
    func encode(_ value: Int32) throws { try encodeInteger(value) }
    func encode(_ value: Int64) throws { node.storage = .value(.integer(value)) }
    func encode(_ value: UInt) throws { try encodeInteger(value) }
    func encode(_ value: UInt8) throws { try encodeInteger(value) }
    func encode(_ value: UInt16) throws { try encodeInteger(value) }
    func encode(_ value: UInt32) throws { try encodeInteger(value) }
    func encode(_ value: UInt64) throws { try encodeInteger(value) }

    func encode<T: Encodable>(_ value: T) throws {
        try encodeEncodable(value, into: node, codingPath: codingPath, userInfo: userInfo)
    }

    private func encodeInteger<T: BinaryInteger>(_ value: T) throws {
        guard let integer = Int64(exactly: value) else {
            throw EncodingError.invalidValue(
                value,
                EncodingError.Context(
                    codingPath: codingPath,
                    debugDescription: "PHP integers are limited to signed 64-bit values."
                )
            )
        }
        node.storage = .value(.integer(integer))
    }
}

private func encodeEncodable<T: Encodable>(
    _ value: T,
    into node: PHPEncodingNode,
    codingPath: [any CodingKey],
    userInfo: [CodingUserInfoKey: Any]
) throws {
    if let data = value as? Data {
        node.storage = .value(.string(PHPString(data: data)))
    } else if let date = value as? Date {
        node.storage = .value(.double(date.timeIntervalSinceReferenceDate))
    } else {
        try value.encode(to: PHPValueEncoder(node: node, codingPath: codingPath, userInfo: userInfo))
    }
}

struct PHPIndexKey: CodingKey {
    static let superKey = PHPIndexKey(name: "super")

    let intValue: Int?
    let stringValue: String

    init(_ index: Int) {
        self.intValue = index
        self.stringValue = "Index \(index)"
    }

    private init(name: String) {
        self.intValue = nil
        self.stringValue = name
    }

    init?(intValue: Int) {
        self.init(intValue)
    }

    init?(stringValue: String) {
        self.intValue = nil
        self.stringValue = stringValue
    }
}
