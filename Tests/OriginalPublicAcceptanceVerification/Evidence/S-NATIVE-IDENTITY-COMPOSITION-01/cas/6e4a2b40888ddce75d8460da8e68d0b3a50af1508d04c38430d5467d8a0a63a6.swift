public struct DocumentRevision: Hashable, Sendable, Comparable {
    public var value: Int

    public init(_ value: Int = 0) {
        self.value = value
    }

    public func validate() throws {
        guard value >= 0, value < Int.max else {
            throw SchemaError.invalidRevision(value)
        }
    }

    public func advanced() -> DocumentRevision {
        let (advancedValue, overflow) = value.addingReportingOverflow(1)
        return DocumentRevision(overflow ? -1 : advancedValue)
    }

    public static func < (lhs: DocumentRevision, rhs: DocumentRevision) -> Bool {
        lhs.value < rhs.value
    }
}

#if !hasFeature(Embedded)
extension DocumentRevision: Codable {}
#endif
