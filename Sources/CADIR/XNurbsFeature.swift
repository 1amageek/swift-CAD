import CADCore

/// XNURBS: a sheet over an opening framed by boundary curves (sketch curves or edges of bodies
/// through their edge curves), each G0 or tangent or curvature continuous with the face beside its
/// edge. Quad sided over two to four boundaries is Square's untrimmed sheet; otherwise the
/// boundary closes into a loop and one sheet over its mean plane is trimmed by it, open profile
/// guides pulling it, within the position and angle tolerances when it satisfies them.
public struct XNurbsFeature: Codable, Hashable, Sendable {
    /// Quality: the sheet's starting spans each way (Auto 3, High 6, Max 12).
    public enum Quality: String, Codable, Hashable, Sendable, CaseIterable {
        case auto
        case high
        case max

        public var spans: Int {
            switch self {
            case .auto: 3
            case .high: 6
            case .max: 12
            }
        }
    }

    public var boundaries: [SquareSide]
    public var guides: [CurveSectionReference]
    public var quadSided: Bool
    public var flatness: Double
    public var boundaryFlow: SquareFitOptions.BoundaryFlow
    public var quality: Quality
    public var satisfiesTolerances: Bool
    /// The largest distance the sheet may keep from its boundary, in meters.
    public var positionTolerance: Double
    /// The largest angle between the sheet's and a continuous boundary's face normals, in radians.
    public var angleTolerance: Double

    public init(boundaries: [SquareSide], guides: [CurveSectionReference] = [], quadSided: Bool = false, flatness: Double = 0.95,
                boundaryFlow: SquareFitOptions.BoundaryFlow = .adjacent, quality: Quality = .auto, satisfiesTolerances: Bool = true,
                positionTolerance: Double = 1e-5, angleTolerance: Double = 0.1 * Double.pi / 180) {
        self.boundaries = boundaries
        self.guides = guides
        self.quadSided = quadSided
        self.flatness = flatness
        self.boundaryFlow = boundaryFlow
        self.quality = quality
        self.satisfiesTolerances = satisfiesTolerances
        self.positionTolerance = positionTolerance
        self.angleTolerance = angleTolerance
    }

    public func validate() throws {
        guard boundaries.count >= 2, quadSided == false || boundaries.count <= 4 else {
            throw FeatureEvaluationError.invalidGraph(quadSided ? "A quad-sided XNURBS is framed by two to four curves."
                                                               : "An XNURBS is framed by two or more boundary curves.")
        }
        let curves = boundaries.map(\.curve.featureID) + guides.map(\.featureID)
        guard Set(curves).count == curves.count else {
            throw FeatureEvaluationError.invalidGraph("An XNURBS's boundaries and guides are distinct curves.")
        }
        for boundary in boundaries {
            try boundary.validate()
            guard boundary.isFree == false else {
                throw FeatureEvaluationError.invalidGraph("An XNURBS boundary is G0, G1 or G2.")
            }
        }
        for guide in guides { try guide.validate() }
        guard flatness.isFinite, flatness > 0, flatness <= 1 else {
            throw FeatureEvaluationError.invalidGraph("An XNURBS's flatness lies in (0, 1].")
        }
        guard positionTolerance.isFinite, positionTolerance > 0, angleTolerance.isFinite, angleTolerance > 0, angleTolerance < Double.pi / 2 else {
            throw FeatureEvaluationError.invalidGraph("An XNURBS's tolerances are a positive length and an angle below a right angle.")
        }
    }

    /// The features XNURBS consumes: its boundaries' and guides' curves and continuity bodies.
    public var inputs: [FeatureInput] {
        var seen = Set<FeatureInput>()
        return (boundaries.map { FeatureInput(featureID: $0.curve.featureID, role: .curve) }
            + guides.map { FeatureInput(featureID: $0.featureID, role: .curve) }
            + boundaries.compactMap(\.continuity).map { FeatureInput(featureID: $0.source, role: $0.bodyRole) })
            .filter { seen.insert($0).inserted }
    }

    private enum CodingKeys: String, CodingKey {
        case boundaries, guides, quadSided, flatness, boundaryFlow, quality, satisfiesTolerances, positionTolerance, angleTolerance
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try container.validateOnlyExpectedKeys([.boundaries, .guides, .quadSided, .flatness, .boundaryFlow, .quality, .satisfiesTolerances,
                                                .positionTolerance, .angleTolerance], in: decoder)
        boundaries = try container.decode([SquareSide].self, forKey: .boundaries)
        guides = try container.decode([CurveSectionReference].self, forKey: .guides)
        quadSided = try container.decode(Bool.self, forKey: .quadSided)
        flatness = try container.decode(Double.self, forKey: .flatness)
        boundaryFlow = try container.decode(SquareFitOptions.BoundaryFlow.self, forKey: .boundaryFlow)
        quality = try container.decode(Quality.self, forKey: .quality)
        satisfiesTolerances = try container.decode(Bool.self, forKey: .satisfiesTolerances)
        positionTolerance = try container.decode(Double.self, forKey: .positionTolerance)
        angleTolerance = try container.decode(Double.self, forKey: .angleTolerance)
        try validate()
    }

    public func encode(to encoder: Encoder) throws {
        try validate()
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(boundaries, forKey: .boundaries)
        try container.encode(guides, forKey: .guides)
        try container.encode(quadSided, forKey: .quadSided)
        try container.encode(flatness, forKey: .flatness)
        try container.encode(boundaryFlow, forKey: .boundaryFlow)
        try container.encode(quality, forKey: .quality)
        try container.encode(satisfiesTolerances, forKey: .satisfiesTolerances)
        try container.encode(positionTolerance, forKey: .positionTolerance)
        try container.encode(angleTolerance, forKey: .angleTolerance)
    }
}
