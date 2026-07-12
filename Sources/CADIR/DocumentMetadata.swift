import Foundation
import CADCore

public struct DocumentMetadata: Codable, Sendable {
    public var name: String?
    public var createdAt: Date
    public var updatedAt: Date

    public init(name: String? = nil) {
        let now = Date()
        self.init(name: name, createdAt: now, updatedAt: now)
    }

    public init(name: String? = nil, createdAt: Date, updatedAt: Date) {
        self.name = name
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    private enum CodingKeys: String, CodingKey {
        case name
        case createdAt
        case updatedAt
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try container.validateOnlyExpectedKeys([.name, .createdAt, .updatedAt], in: decoder)
        name = try container.decodeIfPresent(String.self, forKey: .name)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        updatedAt = try container.decode(Date.self, forKey: .updatedAt)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(name, forKey: .name)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encode(updatedAt, forKey: .updatedAt)
    }

    public func validate() throws {
        let created = createdAt.timeIntervalSinceReferenceDate
        let updated = updatedAt.timeIntervalSinceReferenceDate
        guard created.isFinite, updated.isFinite else {
            throw SchemaError.invalidMetadata("Document metadata timestamps must be finite.")
        }
        guard updatedAt >= createdAt else {
            throw SchemaError.invalidMetadata("Document metadata updatedAt must not be earlier than createdAt.")
        }
    }
}
