import CADCore

/// Square: a four-sided sheet framed by four curves (sketch curves or edges of bodies through
/// their edge curves) meeting end to end, each side matching its curve (G0) or, along an edge of a
/// body, tangent or curvature continuous with the face beside it.
public struct SquareSurfaceFeature: Codable, Hashable, Sendable {
    public var sides: [SquareSide]

    public init(sides: [SquareSide]) {
        self.sides = sides
    }

    private enum CodingKeys: String, CodingKey {
        case sides
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try container.validateOnlyExpectedKeys([.sides], in: decoder)
        sides = try container.decode([SquareSide].self, forKey: .sides)
        try validate()
    }

    public func encode(to encoder: Encoder) throws {
        try validate()
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(sides, forKey: .sides)
    }

    public func validate() throws {
        guard sides.count == 4 else {
            throw FeatureEvaluationError.invalidGraph("A Square has four sides.")
        }
        guard Set(sides.map(\.curve.featureID)).count == 4 else {
            throw FeatureEvaluationError.invalidGraph("A Square's sides are four distinct curves.")
        }
        for side in sides {
            try side.validate()
        }
    }

    /// The features the Square consumes: its sides' curves and the bodies of continuous sides.
    public var inputs: [FeatureInput] {
        sides.map { FeatureInput(featureID: $0.curve.featureID, role: .curve) }
            + sides.compactMap(\.continuity).map { FeatureInput(featureID: $0.source, role: $0.bodyRole) }
    }
}

/// One side of a Square: its curve and, when it runs along an edge of a body, how the Square meets
/// the face beside that edge.
public struct SquareSide: Codable, Hashable, Sendable {
    public var curve: CurveSectionReference
    public var continuity: SurfaceEdgeContinuity?

    public init(curve: CurveSectionReference, continuity: SurfaceEdgeContinuity? = nil) {
        self.curve = curve
        self.continuity = continuity
    }

    private enum CodingKeys: String, CodingKey {
        case curve, continuity
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try container.validateOnlyExpectedKeys([.curve, .continuity], in: decoder)
        curve = try container.decode(CurveSectionReference.self, forKey: .curve)
        continuity = try container.decodeIfPresent(SurfaceEdgeContinuity.self, forKey: .continuity)
        try validate()
    }

    public func encode(to encoder: Encoder) throws {
        try validate()
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(curve, forKey: .curve)
        try container.encodeIfPresent(continuity, forKey: .continuity)
    }

    public func validate() throws {
        try curve.validate()
        try continuity?.validate()
    }
}
