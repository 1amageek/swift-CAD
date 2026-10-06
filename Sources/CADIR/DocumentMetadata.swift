#if !hasFeature(Embedded)
import Foundation
#endif
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#elseif canImport(WASILibc)
import WASILibc
#else
#error("Document metadata authoring requires an explicit platform wall-clock adapter.")
#endif
import CADCore

public struct DocumentMetadata: Equatable, Sendable {
    public var name: String?
    public var createdAtReferenceDate: Double
    public var updatedAtReferenceDate: Double

    public init(name: String? = nil, createdAtReferenceDate: Double, updatedAtReferenceDate: Double) {
        self.name = name
        self.createdAtReferenceDate = createdAtReferenceDate
        self.updatedAtReferenceDate = updatedAtReferenceDate
    }

    /// Reads one wall-clock value for both timestamps and reports platform failure.
    public static func current(name: String? = nil) throws -> Self {
        var timestamp = timespec()
        guard clock_gettime(CLOCK_REALTIME, &timestamp) == 0 else {
            throw SchemaError.invalidMetadata("The platform wall clock could not provide document metadata.")
        }
        let referenceSeconds = Double(timestamp.tv_sec) + Double(timestamp.tv_nsec) * 1e-9 - 978_307_200
        let result = Self(name: name, createdAtReferenceDate: referenceSeconds,
            updatedAtReferenceDate: referenceSeconds)
        try result.validate()
        return result
    }

#if !hasFeature(Embedded)
    public var createdAt: Date {
        get { Date(timeIntervalSinceReferenceDate: createdAtReferenceDate) }
        set { createdAtReferenceDate = newValue.timeIntervalSinceReferenceDate }
    }

    public var updatedAt: Date {
        get { Date(timeIntervalSinceReferenceDate: updatedAtReferenceDate) }
        set { updatedAtReferenceDate = newValue.timeIntervalSinceReferenceDate }
    }

    public init(name: String? = nil) {
        let now = Date()
        self.init(name: name, createdAt: now, updatedAt: now)
    }

    public init(name: String? = nil, createdAt: Date, updatedAt: Date) {
        self.init(name: name, createdAtReferenceDate: createdAt.timeIntervalSinceReferenceDate,
            updatedAtReferenceDate: updatedAt.timeIntervalSinceReferenceDate)
    }
#endif

#if !hasFeature(Embedded)
    private enum CodingKeys: String, CodingKey {
        case name
        case createdAt
        case updatedAt
    }
#endif

#if !hasFeature(Embedded)
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try container.validateOnlyExpectedKeys([.name, .createdAt, .updatedAt], in: decoder)
        name = try container.decodeIfPresent(String.self, forKey: .name)
        createdAtReferenceDate = try container.decode(Date.self, forKey: .createdAt).timeIntervalSinceReferenceDate
        updatedAtReferenceDate = try container.decode(Date.self, forKey: .updatedAt).timeIntervalSinceReferenceDate
    }
#endif

#if !hasFeature(Embedded)
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(name, forKey: .name)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encode(updatedAt, forKey: .updatedAt)
    }
#endif

    public func validate() throws {
        let created = createdAtReferenceDate
        let updated = updatedAtReferenceDate
        guard created.isFinite, updated.isFinite else {
            throw SchemaError.invalidMetadata("Document metadata timestamps must be finite.")
        }
        guard updated >= created else {
            throw SchemaError.invalidMetadata("Document metadata updatedAt must not be earlier than createdAt.")
        }
    }
}

#if !hasFeature(Embedded)
extension DocumentMetadata: Codable {}
#endif
