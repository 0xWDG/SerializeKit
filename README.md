# SerializeKit

SerializeKit reads and writes values compatible with PHP's native `serialize()` and `unserialize()` format.

[![](https://img.shields.io/endpoint?url=https%3A%2F%2Fswiftpackageindex.com%2Fapi%2Fpackages%2F0xWDG%2FSerializeKit%2Fbadge%3Ftype%3Dplatforms)](https://swiftpackageindex.com/0xWDG/SerializeKit)
[![](https://img.shields.io/endpoint?url=https%3A%2F%2Fswiftpackageindex.com%2Fapi%2Fpackages%2F0xWDG%2FSerializeKit%2Fbadge%3Ftype%3Dswift-versions)](https://swiftpackageindex.com/0xWDG/SerializeKit)
[![Swift Package Manager](https://img.shields.io/badge/SPM-compatible-brightgreen.svg)](https://swift.org/package-manager)
![License](https://img.shields.io/github/license/0xWDG/SerializeKit)

## Requirements

- Swift 5.8+ (Xcode 15+)
- iOS 16+, macOS 13+, watchOS 9+, tvOS 16+

## Installation (Package.swift)

```swift
dependencies: [
    .package(url: "https://github.com/0xWDG/SerializeKit.git", branch: "main"),
],
targets: [
    .target(name: "MyTarget", dependencies: [
        .product(name: "SerializeKit", package: "SerializeKit"),
    ]),
]
```

## Usage

Swift literals convert directly to `PHPValue`. PHP arrays retain their ordered integer or string keys.

```swift
import SerializeKit

let value: PHPValue = [
    "name": "Wesley",
    "active": true,
    "scores": [10, 20, 30],
]

let serialized = try PHPSerializer.serializeString(value)
// a:3:{s:4:"name";s:6:"Wesley";s:6:"active";b:1;s:6:"scores";a:3:{i:0;i:10;i:1;i:20;i:2;i:30;}}

let restored = try PHPSerializer.unserialize(serialized)
```

### Codable

Codable models can be serialized directly. `CodingKeys`, nested models, optionals, arrays, dictionaries, `Data`, and `Date` are supported.

```swift
struct User: Codable {
    let id: Int64
    let name: String
    let roles: [String]
}

let user = User(id: 42, name: "Wesley", roles: ["admin"])
let data = try PHPSerializer.serialize(user)
let restored = try PHPSerializer.unserialize(User.self, from: data)
```

`Data` is encoded as a binary PHP string. `Date` uses seconds relative to Apple's reference date, matching its default Codable representation. Codable keyed containers use their coding keys, while unkeyed containers use sequential integer keys.

PHP strings are binary strings and can contain invalid UTF-8 or null bytes. Use the `Data` API for lossless binary values:

```swift
import Foundation
import SerializeKit

let binary = PHPValue.string(PHPString(data: Data([0x00, 0xFF])))
let data = PHPSerializer.serialize(binary)
let restored = try PHPSerializer.unserialize(data)
```

Supported values are null, booleans, 64-bit integers, doubles, binary strings, arrays, objects, and PHP enumerations. Objects are represented as inert class/property data; SerializeKit never loads a PHP class or executes object hooks. PHP references and legacy custom-serialized objects are rejected.

## Contact

🦋 [@0xWDG](https://bsky.app/profile/0xWDG.bsky.social)
🐘 [mastodon.social/@0xWDG](https://mastodon.social/@0xWDG)
🐦 [@0xWDG](https://x.com/0xWDG)
🧵 [@0xWDG](https://www.threads.net/@0xWDG)
🌐 [wesleydegroot.nl](https://wesleydegroot.nl)
🤖 [Discord](https://discordapp.com/users/918438083861573692)

Interested learning more about Swift? [Check out my blog](https://wesleydegroot.nl/blog/).
