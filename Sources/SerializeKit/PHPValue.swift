//
//  PHPValue.swift
//  SerializeKit
//
//  Created by Wesley de Groot on 2026-08-13.
//  https://wesleydegroot.nl
//
//  https://github.com/0xWDG/SerializeKit
//  MIT License
//

import Foundation

/// A byte string as used by PHP's serialization format.
public struct PHPString: Hashable, Sendable {
    public let data: Data

    public init(data: Data) {
        self.data = data
    }

    public init(_ value: String) {
        self.data = Data(value.utf8)
    }

    /// The value decoded as UTF-8, or `nil` when it contains non-UTF-8 bytes.
    public var string: String? {
        String(bytes: data, encoding: .utf8)
    }
}

extension PHPString: ExpressibleByStringLiteral {
    public init(stringLiteral value: String) {
        self.init(value)
    }
}

/// A valid PHP array key.
public enum PHPKey: Hashable, Sendable {
    case integer(Int64)
    case string(PHPString)
}

extension PHPKey: ExpressibleByIntegerLiteral {
    public init(integerLiteral value: Int64) {
        self = .integer(value)
    }
}

extension PHPKey: ExpressibleByStringLiteral {
    public init(stringLiteral value: String) {
        self = .string(PHPString(value))
    }
}

/// One ordered key/value pair in a PHP array.
public struct PHPArrayElement: Equatable, Sendable {
    public let key: PHPKey
    public let value: PHPValue

    public init(key: PHPKey, value: PHPValue) {
        self.key = key
        self.value = value
    }
}

/// One named property in a serialized PHP object.
public struct PHPObjectProperty: Equatable, Sendable {
    public let name: PHPString
    public let value: PHPValue

    public init(name: PHPString, value: PHPValue) {
        self.name = name
        self.value = value
    }
}

/// A value representable by PHP's native `serialize()` format.
public indirect enum PHPValue: Equatable, Sendable {
    case null
    case boolean(Bool)
    case integer(Int64)
    case double(Double)
    case string(PHPString)
    case array([PHPArrayElement])
    case object(className: PHPString, properties: [PHPObjectProperty])
    case enumeration(PHPString)

    /// Creates a PHP array with sequential integer keys beginning at zero.
    public static func list(_ values: [PHPValue]) -> PHPValue {
        .array(values.enumerated().map {
            PHPArrayElement(key: .integer(Int64($0.offset)), value: $0.element)
        })
    }
}

extension PHPValue: ExpressibleByNilLiteral {
    public init(nilLiteral: ()) {
        self = .null
    }
}

extension PHPValue: ExpressibleByBooleanLiteral {
    public init(booleanLiteral value: Bool) {
        self = .boolean(value)
    }
}

extension PHPValue: ExpressibleByIntegerLiteral {
    public init(integerLiteral value: Int64) {
        self = .integer(value)
    }
}

extension PHPValue: ExpressibleByFloatLiteral {
    public init(floatLiteral value: Double) {
        self = .double(value)
    }
}

extension PHPValue: ExpressibleByStringLiteral {
    public init(stringLiteral value: String) {
        self = .string(PHPString(value))
    }
}

extension PHPValue: ExpressibleByArrayLiteral {
    public init(arrayLiteral elements: PHPValue...) {
        self = .list(elements)
    }
}

extension PHPValue: ExpressibleByDictionaryLiteral {
    public init(dictionaryLiteral elements: (PHPKey, PHPValue)...) {
        self = .array(elements.map(PHPArrayElement.init(key:value:)))
    }
}
