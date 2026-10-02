import CADCore

/// Square: a four-sided sheet framed by two to four curves (sketch curves or edges of bodies
/// through their edge curves): four meeting end to end, three meeting end to end closed by a
/// straight side, two meeting at a corner completed by their translated copies, or two apart ruled
/// between. Each given side matches its curve (G0), along an edge of a body is tangent or
/// curvature continuous with the face beside it, or is Free (followed loosely); the sheet is
/// fitted to its frame by `options`.
public struct SquareSurfaceFeature: Codable, Hashable, Sendable {
    public var sides: [SquareSide]
    public var options: SquareFitOptions

    public init(sides: [SquareSide], options: SquareFitOptions = SquareFitOptions()) {
        self.sides = sides
        self.options = options
    }

    private enum CodingKeys: String, CodingKey {
        case sides, options
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try container.validateOnlyExpectedKeys([.sides, .options], in: decoder)
        sides = try container.decode([SquareSide].self, forKey: .sides)
        options = try container.decode(SquareFitOptions.self, forKey: .options)
        try validate()
    }

    public func encode(to encoder: Encoder) throws {
        try validate()
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(sides, forKey: .sides)
        try container.encode(options, forKey: .options)
    }

    public func validate() throws {
        guard (2...4).contains(sides.count) else {
            throw FeatureEvaluationError.invalidGraph("A Square is framed by two to four curves.")
        }
        guard Set(sides.map(\.curve.featureID)).count == sides.count else {
            throw FeatureEvaluationError.invalidGraph("A Square's sides are distinct curves.")
        }
        for side in sides {
            try side.validate()
        }
        try options.validate()
    }

    /// The features the Square consumes: its sides' curves and the bodies of continuous sides.
    public var inputs: [FeatureInput] {
        var seen = Set<FeatureInput>()
        return (sides.map { FeatureInput(featureID: $0.curve.featureID, role: .curve) }
            + sides.compactMap(\.continuity).map { FeatureInput(featureID: $0.source, role: $0.bodyRole) })
            .filter { seen.insert($0).inserted }
    }
}

/// One side of a Square: its curve and, when it runs along an edge of a body, how the Square meets
/// the face beside that edge; a Free side is followed loosely, by the Square's weight.
public struct SquareSide: Codable, Hashable, Sendable {
    public var curve: CurveSectionReference
    public var continuity: SurfaceEdgeContinuity?
    public var isFree: Bool

    public init(curve: CurveSectionReference, continuity: SurfaceEdgeContinuity? = nil, isFree: Bool = false) {
        self.curve = curve
        self.continuity = continuity
        self.isFree = isFree
    }

    private enum CodingKeys: String, CodingKey {
        case curve, continuity, isFree
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try container.validateOnlyExpectedKeys([.curve, .continuity, .isFree], in: decoder)
        curve = try container.decode(CurveSectionReference.self, forKey: .curve)
        continuity = try container.decodeIfPresent(SurfaceEdgeContinuity.self, forKey: .continuity)
        isFree = try container.decodeIfPresent(Bool.self, forKey: .isFree) ?? false
        try validate()
    }

    public func encode(to encoder: Encoder) throws {
        try validate()
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(curve, forKey: .curve)
        try container.encodeIfPresent(continuity, forKey: .continuity)
        if isFree { try container.encode(true, forKey: .isFree) }
    }

    public func validate() throws {
        try curve.validate()
        try continuity?.validate()
        guard !(isFree && continuity != nil) else {
            throw FeatureEvaluationError.invalidGraph("A Free Square side takes no continuity.")
        }
    }
}
