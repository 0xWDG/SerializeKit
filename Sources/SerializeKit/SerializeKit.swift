//
//  SerializeKit.swift
//  SerializeKit
//
//  Created by Wesley de Groot on 2026-08-13.
//  https://wesleydegroot.nl
//
//  https://github.com/0xWDG/SerializeKit
//  MIT License
//

import Foundation

/// Errors produced while reading or converting a PHP serialized value.
public enum PHPSerializationError: Error, Equatable, Sendable {
    case unexpectedEnd(offset: Int)
    case unexpectedByte(UInt8, offset: Int)
    case unsupportedType(UInt8, offset: Int)
    case invalidNumber(offset: Int)
    case invalidArrayKey(offset: Int)
    case invalidStringEncoding
    case maximumDepthExceeded(limit: Int)
    case trailingData(offset: Int)
}

extension PHPSerializationError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .unexpectedEnd(let offset):
            return "Unexpected end of serialized data at byte \(offset)."
        case .unexpectedByte(let byte, let offset):
            return "Unexpected byte \(byte) at byte \(offset)."
        case .unsupportedType(let byte, let offset):
            return "Unsupported PHP type marker \(byte) at byte \(offset)."
        case .invalidNumber(let offset):
            return "Invalid number at byte \(offset)."
        case .invalidArrayKey(let offset):
            return "PHP array keys must be integers or strings (byte \(offset))."
        case .invalidStringEncoding:
            return "The serialized byte stream is not valid UTF-8. Use serialize(_:) to retain binary data."
        case .maximumDepthExceeded(let limit):
            return "The serialized value exceeds the maximum depth of \(limit)."
        case .trailingData(let offset):
            return "The serialized value has trailing data beginning at byte \(offset)."
        }
    }
}

/// Encodes and decodes values compatible with PHP's native serialization format.
public enum PHPSerializer {
    /// Serializes a value into PHP's binary-safe byte-stream representation.
    public static func serialize(_ value: PHPValue) -> Data {
        var output = Data()
        Serializer.append(value, to: &output)
        return output
    }

    /// Encodes and serializes an `Encodable` value.
    public static func serialize<T: Encodable>(
        _ value: T,
        encoder: PHPCodableEncoder = PHPCodableEncoder()
    ) throws -> Data {
        serialize(try encoder.encode(value))
    }

    /// Serializes a value as UTF-8 text.
    ///
    /// Use ``serialize(_:)`` when a value may contain arbitrary binary strings.
    public static func serializeString(_ value: PHPValue) throws -> String {
        guard let result = String(data: serialize(value), encoding: .utf8) else {
            throw PHPSerializationError.invalidStringEncoding
        }
        return result
    }

    /// Encodes and serializes an `Encodable` value as UTF-8 text.
    public static func serializeString<T: Encodable>(
        _ value: T,
        encoder: PHPCodableEncoder = PHPCodableEncoder()
    ) throws -> String {
        try serializeString(encoder.encode(value))
    }

    /// Reads exactly one serialized value from a byte stream.
    ///
    /// Pass zero for `maximumDepth` to disable the nesting limit, matching PHP.
    public static func unserialize(
        _ data: Data,
        maximumDepth: Int = 4_096
    ) throws -> PHPValue {
        var parser = Parser(data: data, maximumDepth: max(0, maximumDepth))
        let result = try parser.parseValue(depth: 0)
        guard parser.isAtEnd else {
            throw PHPSerializationError.trailingData(offset: parser.offset)
        }
        return result
    }

    /// Unserializes and decodes a `Decodable` value from a byte stream.
    public static func unserialize<T: Decodable>(
        _ type: T.Type,
        from data: Data,
        maximumDepth: Int = 4_096,
        decoder: PHPCodableDecoder = PHPCodableDecoder()
    ) throws -> T {
        try decoder.decode(type, from: unserialize(data, maximumDepth: maximumDepth))
    }

    /// Reads exactly one serialized value from UTF-8 text.
    public static func unserialize(
        _ string: String,
        maximumDepth: Int = 4_096
    ) throws -> PHPValue {
        try unserialize(Data(string.utf8), maximumDepth: maximumDepth)
    }

    /// Unserializes and decodes a `Decodable` value from UTF-8 text.
    public static func unserialize<T: Decodable>(
        _ type: T.Type,
        from string: String,
        maximumDepth: Int = 4_096,
        decoder: PHPCodableDecoder = PHPCodableDecoder()
    ) throws -> T {
        try decoder.decode(type, from: unserialize(string, maximumDepth: maximumDepth))
    }
}

private enum Serializer {
    static func append(_ value: PHPValue, to output: inout Data) {
        switch value {
        case .null:
            output.appendASCII("N;")
        case .boolean(let value):
            output.appendASCII(value ? "b:1;" : "b:0;")
        case .integer(let value):
            output.appendASCII("i:\(value);")
        case .double(let value):
            output.appendASCII("d:\(formatted(value));")
        case .string(let value):
            append(value, to: &output)
        case .array(let elements):
            output.appendASCII("a:\(elements.count):{")
            for element in elements {
                append(element.key, to: &output)
                append(element.value, to: &output)
            }
            output.appendASCII("}")
        case .object(let className, let properties):
            output.appendASCII("O:\(className.data.count):\"")
            output.append(className.data)
            output.appendASCII("\":\(properties.count):{")
            for property in properties {
                append(property.name, to: &output)
                append(property.value, to: &output)
            }
            output.appendASCII("}")
        case .enumeration(let value):
            output.appendASCII("E:\(value.data.count):\"")
            output.append(value.data)
            output.appendASCII("\";")
        }
    }

    private static func append(_ value: PHPString, to output: inout Data) {
        output.appendASCII("s:\(value.data.count):\"")
        output.append(value.data)
        output.appendASCII("\";")
    }

    private static func append(_ key: PHPKey, to output: inout Data) {
        switch key {
        case .integer(let value):
            output.appendASCII("i:\(value);")
        case .string(let value):
            append(value, to: &output)
        }
    }

    private static func formatted(_ value: Double) -> String {
        if value.isNaN { return "NAN" }
        if value == .infinity { return "INF" }
        if value == -.infinity { return "-INF" }

        var result = String(value).uppercased()
        if result.hasSuffix(".0") {
            result.removeLast(2)
        }
        if let exponentIndex = result.firstIndex(of: "E") {
            if result[..<exponentIndex].contains(".") == false {
                result.insert(contentsOf: ".0", at: exponentIndex)
            }
            guard let normalizedExponentIndex = result.firstIndex(of: "E") else {
                return result
            }
            let exponentStart = result.index(after: normalizedExponentIndex)
            var signIndex = exponentStart
            if signIndex < result.endIndex, result[signIndex] == "+" || result[signIndex] == "-" {
                signIndex = result.index(after: signIndex)
            }
            while signIndex < result.endIndex,
                  result[signIndex] == "0",
                  result.index(after: signIndex) < result.endIndex {
                result.remove(at: signIndex)
            }
        }
        return result
    }
}

private struct Parser {
    private let bytes: [UInt8]
    private let maximumDepth: Int
    private(set) var offset = 0

    init(data: Data, maximumDepth: Int) {
        self.bytes = Array(data)
        self.maximumDepth = maximumDepth
    }

    var isAtEnd: Bool {
        offset == bytes.count
    }

    mutating func parseValue(depth: Int) throws -> PHPValue {
        let markerOffset = offset
        let marker = try readByte()
        switch marker {
        case ascii("N"):
            try expect(ascii(";"))
            return .null
        case ascii("b"):
            return .boolean(try parseBoolean())
        case ascii("i"):
            try expect(ascii(":"))
            return .integer(try readInteger(terminator: ascii(";")))
        case ascii("d"):
            try expect(ascii(":"))
            return .double(try readDouble())
        case ascii("s"):
            return .string(try readString())
        case ascii("a"):
            return try parseArray(depth: depth)
        case ascii("O"):
            return try parseObject(depth: depth)
        case ascii("E"):
            return .enumeration(try readString())
        default:
            throw PHPSerializationError.unsupportedType(marker, offset: markerOffset)
        }
    }

    private mutating func parseBoolean() throws -> Bool {
        try expect(ascii(":"))
        let valueOffset = offset
        let value = try readByte()
        guard value == ascii("0") || value == ascii("1") else {
            throw PHPSerializationError.invalidNumber(offset: valueOffset)
        }
        try expect(ascii(";"))
        return value == ascii("1")
    }

    private mutating func parseArray(depth: Int) throws -> PHPValue {
        try validateContainerDepth(depth + 1)
        try expect(ascii(":"))
        let count = try readCount(terminator: ascii(":"))
        try expect(ascii("{"))
        var elements: [PHPArrayElement] = []
        for _ in 0..<count {
            let keyOffset = offset
            let keyValue = try parseValue(depth: depth + 1)
            let key: PHPKey
            switch keyValue {
            case .integer(let value): key = .integer(value)
            case .string(let value): key = .string(value)
            default: throw PHPSerializationError.invalidArrayKey(offset: keyOffset)
            }
            let value = try parseValue(depth: depth + 1)
            elements.append(PHPArrayElement(key: key, value: value))
        }
        try expect(ascii("}"))
        return .array(elements)
    }

    private mutating func parseObject(depth: Int) throws -> PHPValue {
        try validateContainerDepth(depth + 1)
        let className = try readString(endingWith: ascii(":"))
        let count = try readCount(terminator: ascii(":"))
        try expect(ascii("{"))
        var properties: [PHPObjectProperty] = []
        for _ in 0..<count {
            let propertyOffset = offset
            let property = try parseValue(depth: depth + 1)
            guard case .string(let name) = property else {
                throw PHPSerializationError.invalidArrayKey(offset: propertyOffset)
            }
            let value = try parseValue(depth: depth + 1)
            properties.append(PHPObjectProperty(name: name, value: value))
        }
        try expect(ascii("}"))
        return .object(className: className, properties: properties)
    }

    private func validateContainerDepth(_ depth: Int) throws {
        guard maximumDepth == 0 || depth <= maximumDepth else {
            throw PHPSerializationError.maximumDepthExceeded(limit: maximumDepth)
        }
    }

    private mutating func readString(endingWith terminator: UInt8 = ascii(";")) throws -> PHPString {
        try expect(ascii(":"))
        let length = try readCount(terminator: ascii(":"))
        try expect(ascii("\""))
        guard length <= bytes.count - offset else {
            throw PHPSerializationError.unexpectedEnd(offset: offset)
        }
        let data = Data(bytes[offset..<(offset + length)])
        offset += length
        try expect(ascii("\""))
        try expect(terminator)
        return PHPString(data: data)
    }

    private mutating func readInteger(terminator: UInt8) throws -> Int64 {
        let numberOffset = offset
        let text = try readASCII(until: terminator)
        guard let value = Int64(text) else {
            throw PHPSerializationError.invalidNumber(offset: numberOffset)
        }
        return value
    }

    private mutating func readCount(terminator: UInt8) throws -> Int {
        let numberOffset = offset
        let text = try readASCII(until: terminator)
        guard let value = Int(text), value >= 0 else {
            throw PHPSerializationError.invalidNumber(offset: numberOffset)
        }
        return value
    }

    private mutating func readDouble() throws -> Double {
        let numberOffset = offset
        let text = try readASCII(until: ascii(";"))
        switch text {
        case "INF": return .infinity
        case "-INF": return -.infinity
        case "NAN": return .nan
        default:
            guard let value = Double(text) else {
                throw PHPSerializationError.invalidNumber(offset: numberOffset)
            }
            return value
        }
    }

    private mutating func readASCII(until terminator: UInt8) throws -> String {
        let start = offset
        while offset < bytes.count, bytes[offset] != terminator {
            guard bytes[offset] < 128 else {
                throw PHPSerializationError.invalidNumber(offset: start)
            }
            offset += 1
        }
        guard offset < bytes.count else {
            throw PHPSerializationError.unexpectedEnd(offset: offset)
        }
        let result = String(bytes: bytes[start..<offset], encoding: .utf8) ?? ""
        offset += 1
        return result
    }

    private mutating func expect(_ expected: UInt8) throws {
        let byteOffset = offset
        let actual = try readByte()
        guard actual == expected else {
            throw PHPSerializationError.unexpectedByte(actual, offset: byteOffset)
        }
    }

    private mutating func readByte() throws -> UInt8 {
        guard offset < bytes.count else {
            throw PHPSerializationError.unexpectedEnd(offset: offset)
        }
        defer { offset += 1 }
        return bytes[offset]
    }
}

private extension Data {
    mutating func appendASCII(_ string: String) {
        append(contentsOf: string.utf8)
    }
}

private func ascii(_ character: Character) -> UInt8 {
    character.asciiValue ?? 0
}
