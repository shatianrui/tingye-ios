import Foundation
import ReadiumShared

/// Only this field is lossy. A corrupt optional Locator must never discard a catalog or archive.
@propertyWrapper
struct StoredLocator: Codable, Equatable, Sendable {
    var wrappedValue: JSONValue?
    init(wrappedValue: JSONValue? = nil) { self.wrappedValue = Self.validated(wrappedValue) }
    init(from decoder: Decoder) throws {
        wrappedValue = Self.validated(try? JSONValue(from: decoder))
    }
    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(Self.validated(wrappedValue))
    }
    static func validated(_ value: JSONValue?) -> JSONValue? {
        guard let value, let object = value.object,
              let href = object["href"]?.string, !href.isEmpty,
              object["type"]?.string != nil,
              let data = try? JSONEncoder().encode(value), data.count <= 256 * 1024,
              let json = String(data: data, encoding: .utf8),
              let shared = try? ReadiumShared.JSONValue(jsonString: json),
              (try? ReadiumShared.Locator(json: shared, warnings: nil)) != nil else { return nil }
        if let locations = object["locations"] {
            guard let locations = locations.object else { return nil }
            for key in ["progression", "totalProgression"] {
                if let raw = locations[key] {
                    guard case .number(let number) = raw, number.isFinite, (0...1).contains(number) else { return nil }
                }
            }
            if let raw = locations["position"], integer(raw).map({ $0 >= 1 }) != true { return nil }
        }
        return value
    }
    static func integer(_ value: JSONValue?) -> Int? {
        guard let value, case .number(let number) = value, number.isFinite, number.rounded(.towardZero) == number else { return nil }
        return value.int
    }
    static func readium(_ value: JSONValue?) -> ReadiumShared.Locator? {
        guard let value = validated(value), let data = try? JSONEncoder().encode(value),
              let string = String(data: data, encoding: .utf8),
              let json = try? ReadiumShared.JSONValue(jsonString: string) else { return nil }
        return try? ReadiumShared.Locator(json: json, warnings: nil)
    }
    static func json(_ locator: ReadiumShared.Locator) -> JSONValue? {
        guard let string = try? locator.jsonString(), let data = string.data(using: .utf8) else { return nil }
        return validated(try? JSONDecoder().decode(JSONValue.self, from: data))
    }
}

extension KeyedDecodingContainer {
    func decode(_ type: StoredLocator.Type, forKey key: Key) throws -> StoredLocator {
        (try? decodeIfPresent(type, forKey: key)) ?? StoredLocator()
    }
}
extension KeyedEncodingContainer {
    mutating func encode(_ value: StoredLocator, forKey key: Key) throws {
        if value.wrappedValue != nil { try encodeIfPresent(value, forKey: key) }
    }
}
