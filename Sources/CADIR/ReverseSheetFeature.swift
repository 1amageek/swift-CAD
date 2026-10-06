import CADCore
import CADTopology

/// Turns a sheet over: every face of it faces the other way, keeping its geometry and trim. The
/// source sheet is consumed.
public struct ReverseSheetFeature: Hashable, Sendable {
    public var target: PatternTargetReference

    public init(target: PatternTargetReference) {
        self.target = target
    }

    public func validate() throws {
        try target.validate()
    }

#if !hasFeature(Embedded)
    private enum CodingKeys: String, CodingKey {
        case target
    }
#endif

#if !hasFeature(Embedded)
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try container.validateOnlyExpectedKeys([.target], in: decoder)
        target = try container.decode(PatternTargetReference.self, forKey: .target)
        try validate()
    }
#endif

#if !hasFeature(Embedded)
    public func encode(to encoder: Encoder) throws {
        try validate()
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(target, forKey: .target)
    }
#endif
}

#if !hasFeature(Embedded)
extension ReverseSheetFeature: Codable {}
#endif
