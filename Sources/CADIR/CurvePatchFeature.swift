import CADCore

/// Patch from closed curves: a sheet spanning curves (sketch curves or edges of bodies through their
/// edge curves) that join end to end into one closed loop, or one closed curve.
public struct CurvePatchFeature: Codable, Hashable, Sendable {
    public var curves: [CurveSectionReference]

    public init(curves: [CurveSectionReference]) {
        self.curves = curves
    }

    private enum CodingKeys: String, CodingKey {
        case curves
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try container.validateOnlyExpectedKeys([.curves], in: decoder)
        curves = try container.decode([CurveSectionReference].self, forKey: .curves)
        try validate()
    }

    public func encode(to encoder: Encoder) throws {
        try validate()
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(curves, forKey: .curves)
    }

    public func validate() throws {
        guard curves.isEmpty == false, Set(curves.map(\.featureID)).count == curves.count else {
            throw FeatureEvaluationError.invalidGraph("A curve patch spans one or more distinct curves.")
        }
        for curve in curves {
            try curve.validate()
        }
    }

    /// The features the patch consumes: its curves.
    public var inputs: [FeatureInput] {
        curves.map { FeatureInput(featureID: $0.featureID, role: .curve) }
    }
}
