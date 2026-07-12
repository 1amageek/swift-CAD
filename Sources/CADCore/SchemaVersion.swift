public struct SchemaVersion: Codable, Hashable, Sendable, Comparable {
    public var major: Int
    public var minor: Int
    public var patch: Int

    public init(major: Int, minor: Int, patch: Int) {
        self.major = major
        self.minor = minor
        self.patch = patch
    }

    /// The active development wire format is intentionally pre-1.0.
    /// Compatibility and migration are not provided until the first release contract exists.
    public static let current = SchemaVersion(major: 0, minor: 1, patch: 0)

    public func validate() throws {
        guard major >= 0,
              minor >= 0,
              patch >= 0,
              self == Self.current else {
            throw SchemaError.unsupportedVersion(self)
        }
    }

    public static func < (lhs: SchemaVersion, rhs: SchemaVersion) -> Bool {
        if lhs.major != rhs.major { return lhs.major < rhs.major }
        if lhs.minor != rhs.minor { return lhs.minor < rhs.minor }
        return lhs.patch < rhs.patch
    }
}
