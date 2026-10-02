import CADCore

/// Extend Sheet's Limit: the extension runs on toward a body instead of by a distance (decided
/// 2026-10-02) — `minimal` until the extended edge first meets the body, `inside` until all of it
/// reaches the body's near side, `outside` until all of it has passed through to the far side.
public struct SheetExtensionLimit: Codable, Hashable, Sendable {
    public enum Mode: String, Codable, Hashable, Sendable, CaseIterable {
        case minimal
        case inside
        case outside
    }

    /// The feature whose body the extension runs to.
    public var body: FeatureID
    public var mode: Mode

    public init(body: FeatureID, mode: Mode = .minimal) {
        self.body = body
        self.mode = mode
    }
}
