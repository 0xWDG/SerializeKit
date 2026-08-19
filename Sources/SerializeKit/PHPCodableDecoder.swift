//
//  PHPCodableDecoder.swift
//  SerializeKit
//
//  Created by Wesley de Groot on 2026-08-13.
//  https://wesleydegroot.nl
//
//  https://github.com/0xWDG/SerializeKit
//  MIT License
//

import Foundation

/// Decodes `Decodable` values from the PHP serialization value model.
public final class PHPCodableDecoder {
    /// Contextual values made available to custom `Decodable` implementations.
    public var userInfo: [CodingUserInfoKey: Any] = [:]

    /// Creates a PHP Codable decoder.
    public init() {}

    /// Decodes a value from a ``PHPValue``.
    public func decode<T: Decodable>(_ type: T.Type, from value: PHPValue) throws -> T {
        try decodeDecodable(
            type,
            from: value,
            codingPath: [],
            userInfo: userInfo
        )
    }
}

private final class PHPValueDecoder: Decoder {
    let value: PHPValue
    let codingPath: [any CodingKey]
    let userInfo: [CodingUserInfoKey: Any]

    init(value: PHPValue, codingPath: [any CodingKey], userInfo: [CodingUserInfoKey: Any]) {
        self.value = value
        self.codingPath = codingPath
        self.userInfo = userInfo
    }

    func container<Key: CodingKey>(keyedBy type: Key.Type) throws -> KeyedDecodingContainer<Key> {
        let entries = try keyedEntries()
        let container = PHPKeyedDecodingContainer<Key>(
            entries: entries,
            codingPath: codingPath,
            userInfo: userInfo
        )
        return KeyedDecodingContainer(container)
    }

    func unkeyedContainer() throws -> any UnkeyedDecodingContainer {
        guard case .array(let elements) = value else {
            throw typeMismatch([PHPValue].self, value: value, codingPath: codingPath)
        }
        for (index, element) in elements.enumerated() {
            guard element.key == .integer(Int64(index)) else {
                throw DecodingError.dataCorrupted(
                    DecodingError.Context(
                        codingPath: codingPath,
                        debugDescription: "Expected sequential PHP array keys beginning at zero."
                    )
                )
            }
        }
        return PHPUnkeyedDecodingContainer(
            values: elements.map(\.value),
            codingPath: codingPath,
            userInfo: userInfo
        )
    }

    func singleValueContainer() throws -> any SingleValueDecodingContainer {
        PHPSingleValueDecodingContainer(value: value, codingPath: codingPath, userInfo: userInfo)
    }

    private func keyedEntries() throws -> [String: PHPValue] {
        let pairs: [(PHPKey, PHPValue)]
        switch value {
        case .array(let elements):
            pairs = elements.map { ($0.key, $0.value) }
        case .object(_, let properties):
            pairs = properties.map { (.string($0.name), $0.value) }
        default:
            throw typeMismatch([String: PHPValue].self, value: value, codingPath: codingPath)
        }

        var result: [String: PHPValue] = [:]
        for (key, value) in pairs {
            let string: String
            switch key {
            case .integer(let integer):
                string = String(integer)
            case .string(let phpString):
                guard let decoded = phpString.string else {
                    throw DecodingError.dataCorrupted(
                        DecodingError.Context(
                            codingPath: codingPath,
                            debugDescription: "A keyed value contains a non-UTF-8 key."
                        )
                    )
                }
                string = decoded
            }
            result[string] = value
        }
        return result
    }
}

private struct PHPKeyedDecodingContainer<Key: CodingKey>: KeyedDecodingContainerProtocol {
    let entries: [String: PHPValue]
    let codingPath: [any CodingKey]
    let userInfo: [CodingUserInfoKey: Any]

    var allKeys: [Key] {
        entries.keys.compactMap(Key.init(stringValue:))
    }

    func contains(_ key: Key) -> Bool {
        entries[key.stringValue] != nil
    }

    func decodeNil(forKey key: Key) throws -> Bool {
        guard let value = entries[key.stringValue] else {
            throw keyNotFound(key)
        }
        return value == .null
    }

    func decode<T: Decodable>(_ type: T.Type, forKey key: Key) throws -> T {
        let value = try value(for: key)
        return try decodeDecodable(
            type,
            from: value,
            codingPath: codingPath + [key],
            userInfo: userInfo
        )
    }

    func nestedContainer<NestedKey: CodingKey>(
        keyedBy type: NestedKey.Type,
        forKey key: Key
    ) throws -> KeyedDecodingContainer<NestedKey> {
        try decoder(for: key).container(keyedBy: type)
    }

    func nestedUnkeyedContainer(forKey key: Key) throws -> any UnkeyedDecodingContainer {
        try decoder(for: key).unkeyedContainer()
    }

    func superDecoder() throws -> any Decoder {
        let key = PHPIndexKey.superKey
        guard let value = entries[key.stringValue] else {
            return PHPValueDecoder(value: .null, codingPath: codingPath + [key], userInfo: userInfo)
        }
        return PHPValueDecoder(value: value, codingPath: codingPath + [key], userInfo: userInfo)
    }

    func superDecoder(forKey key: Key) throws -> any Decoder {
        try decoder(for: key)
    }

    private func value(for key: Key) throws -> PHPValue {
        guard let value = entries[key.stringValue] else {
            throw keyNotFound(key)
        }
        return value
    }

    private func decoder(for key: Key) throws -> PHPValueDecoder {
        PHPValueDecoder(
            value: try value(for: key),
            codingPath: codingPath + [key],
            userInfo: userInfo
        )
    }

    private func keyNotFound(_ key: Key) -> DecodingError {
        .keyNotFound(
            key,
            DecodingError.Context(
                codingPath: codingPath,
                debugDescription: "No value is associated with key \"\(key.stringValue)\"."
            )
        )
    }
}

private struct PHPUnkeyedDecodingContainer: UnkeyedDecodingContainer {
    let values: [PHPValue]
    let codingPath: [any CodingKey]
    let userInfo: [CodingUserInfoKey: Any]
    var currentIndex = 0

    var count: Int? { values.count }
    var isAtEnd: Bool { currentIndex >= values.count }

    mutating func decodeNil() throws -> Bool {
        let value = try currentValue()
        guard value == .null else { return false }
        currentIndex += 1
        return true
    }

    mutating func decode<T: Decodable>(_ type: T.Type) throws -> T {
        let index = currentIndex
        let value = try currentValue()
        let result = try decodeDecodable(
            type,
            from: value,
            codingPath: codingPath + [PHPIndexKey(index)],
            userInfo: userInfo
        )
        currentIndex += 1
        return result
    }

    mutating func nestedContainer<NestedKey: CodingKey>(
        keyedBy type: NestedKey.Type
    ) throws -> KeyedDecodingContainer<NestedKey> {
        let decoder = try takeDecoder()
        return try decoder.container(keyedBy: type)
    }

    mutating func nestedUnkeyedContainer() throws -> any UnkeyedDecodingContainer {
        try takeDecoder().unkeyedContainer()
    }

    mutating func superDecoder() throws -> any Decoder {
        try takeDecoder()
    }

    private func currentValue() throws -> PHPValue {
        guard isAtEnd == false else {
            throw DecodingError.valueNotFound(
                PHPValue.self,
                DecodingError.Context(
                    codingPath: codingPath,
                    debugDescription: "Unkeyed container is at end."
                )
            )
        }
        return values[currentIndex]
    }

    private mutating func takeDecoder() throws -> PHPValueDecoder {
        let index = currentIndex
        let value = try currentValue()
        currentIndex += 1
        return PHPValueDecoder(
            value: value,
            codingPath: codingPath + [PHPIndexKey(index)],
            userInfo: userInfo
        )
    }
}

private struct PHPSingleValueDecodingContainer: SingleValueDecodingContainer {
    let value: PHPValue
    let codingPath: [any CodingKey]
    let userInfo: [CodingUserInfoKey: Any]

    func decodeNil() -> Bool { value == .null }

    func decode(_ type: Bool.Type) throws -> Bool {
        guard case .boolean(let result) = value else { throw mismatch(type) }
        return result
    }

    func decode(_ type: String.Type) throws -> String {
        let phpString: PHPString
        switch value {
        case .string(let result): phpString = result
        case .enumeration(let result): phpString = result
        default: throw mismatch(type)
        }
        guard let result = phpString.string else {
            throw DecodingError.dataCorrupted(
                DecodingError.Context(
                    codingPath: codingPath,
                    debugDescription: "The PHP string is not valid UTF-8."
                )
            )
        }
        return result
    }

    func decode(_ type: Double.Type) throws -> Double { try floating(type) }
    func decode(_ type: Float.Type) throws -> Float { Float(try floating(Double.self)) }
    func decode(_ type: Int.Type) throws -> Int { try integer(type) }
    func decode(_ type: Int8.Type) throws -> Int8 { try integer(type) }
    func decode(_ type: Int16.Type) throws -> Int16 { try integer(type) }
    func decode(_ type: Int32.Type) throws -> Int32 { try integer(type) }
    func decode(_ type: Int64.Type) throws -> Int64 { try integer(type) }
    func decode(_ type: UInt.Type) throws -> UInt { try integer(type) }
    func decode(_ type: UInt8.Type) throws -> UInt8 { try integer(type) }
    func decode(_ type: UInt16.Type) throws -> UInt16 { try integer(type) }
    func decode(_ type: UInt32.Type) throws -> UInt32 { try integer(type) }
    func decode(_ type: UInt64.Type) throws -> UInt64 { try integer(type) }

    func decode<T: Decodable>(_ type: T.Type) throws -> T {
        try decodeDecodable(type, from: value, codingPath: codingPath, userInfo: userInfo)
    }

    private func floating<T>(_ type: T.Type) throws -> Double {
        switch value {
        case .double(let result): return result
        case .integer(let result): return Double(result)
        default: throw mismatch(type)
        }
    }

    private func integer<T: FixedWidthInteger>(_ type: T.Type) throws -> T {
        guard case .integer(let value) = value, let result = T(exactly: value) else {
            throw mismatch(type)
        }
        return result
    }

    private func mismatch<T>(_ type: T.Type) -> DecodingError {
        typeMismatch(type, value: value, codingPath: codingPath)
    }
}

private func decodeDecodable<T: Decodable>(
    _ type: T.Type,
    from value: PHPValue,
    codingPath: [any CodingKey],
    userInfo: [CodingUserInfoKey: Any]
) throws -> T {
    if type == Data.self {
        guard case .string(let string) = value else {
            throw typeMismatch(type, value: value, codingPath: codingPath)
        }
        guard let result = string.data as? T else {
            throw typeMismatch(type, value: value, codingPath: codingPath)
        }
        return result
    }
    if type == Date.self {
        let interval: Double
        switch value {
        case .double(let value): interval = value
        case .integer(let value): interval = Double(value)
        default: throw typeMismatch(type, value: value, codingPath: codingPath)
        }
        guard let result = Date(timeIntervalSinceReferenceDate: interval) as? T else {
            throw typeMismatch(type, value: value, codingPath: codingPath)
        }
        return result
    }
    return try T(from: PHPValueDecoder(value: value, codingPath: codingPath, userInfo: userInfo))
}

private func typeMismatch<T>(
    _ type: T.Type,
    value: PHPValue,
    codingPath: [any CodingKey]
) -> DecodingError {
    .typeMismatch(
        type,
        DecodingError.Context(
            codingPath: codingPath,
            debugDescription: "Expected \(type), but found \(value.phpTypeDescription)."
        )
    )
}

private extension PHPValue {
    var phpTypeDescription: String {
        switch self {
        case .null: return "null"
        case .boolean: return "a boolean"
        case .integer: return "an integer"
        case .double: return "a double"
        case .string: return "a string"
        case .array: return "an array"
        case .object: return "an object"
        case .enumeration: return "an enumeration"
        }
    }
}
