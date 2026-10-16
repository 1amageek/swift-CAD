import CADCore
import CADTopology
import CADGeometry

/// Square: a four-sided sheet framed by two to four curves (sketch curves or edges of bodies
/// through their edge curves): four meeting end to end, three meeting end to end closed by a
/// straight side, two meeting at a corner completed by their translated copies, or two apart ruled
/// between. Each given side matches its curve (G0), along an edge of a body is tangent or
/// curvature continuous with the face beside it, or is Free (followed loosely); the sheet is
/// fitted to its frame by `options`.
public struct SquareSurfaceFeature: Hashable, Sendable {
    public var sides: [SquareSide]
    public var options: SquareFitOptions

    public init(sides: [SquareSide], options: SquareFitOptions = SquareFitOptions()) {
        self.sides = sides
        self.options = options
    }

#if !hasFeature(Embedded)
    private enum CodingKeys: String, CodingKey {
        case sides, options
    }
#endif

#if !hasFeature(Embedded)
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try container.validateOnlyExpectedKeys([.sides, .options], in: decoder)
        sides = try container.decode([SquareSide].self, forKey: .sides)
        options = try container.decode(SquareFitOptions.self, forKey: .options)
        try validate()
    }
#endif

#if !hasFeature(Embedded)
    public func encode(to encoder: Encoder) throws {
        try validate()
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(sides, forKey: .sides)
        try container.encode(options, forKey: .options)
    }
#endif

    public func validate() throws {
        var execution = try OriginalQueryExecution.independentGeometry()
        try validate(using: &execution)
    }

    public func validate(using execution: inout OriginalQueryExecution) throws {
        try execution.consumeWork(1)
        guard (2...4).contains(sides.count) else {
            throw FeatureEvaluationError.invalidGraph("A Square is framed by two to four curves.")
        }
        guard (try OriginalParameterQueryStorage.set((try OriginalParameterQueryStorage.map(sides, using: &execution) { value, execution in value.curve.featureID }), using: &execution)).count == sides.count else {
            throw FeatureEvaluationError.invalidGraph("A Square's sides are distinct curves.")
        }
        for side in sides {
            try execution.consumeWork(1)
            try side.validate(using: &execution)
        }
        try options.validate(using: &execution)
        try execution.checkpoint()
    }

    /// The features the Square consumes: its sides' curves and the bodies of continuous sides.
    public var inputs: [FeatureInput] {
        var seen = Set<FeatureInput>()
        return (sides.map { FeatureInput(featureID: $0.curve.featureID, role: .curve) }
            + sides.compactMap { $0.continuity }.map { FeatureInput(featureID: $0.source, role: $0.bodyRole) })
            .filter { seen.insert($0).inserted }
    }

    func validationInputs(using execution: inout OriginalQueryExecution) throws -> [FeatureInput] {
        try execution.consumeWork(1)
        var result: [FeatureInput] = []
        for side in sides {
            try execution.consumeWork(1)
            try OriginalParameterQueryStorage.append(FeatureInput(featureID: side.curve.featureID, role: .curve), to: &result, using: &execution)
        }
        for side in sides {
            try execution.consumeWork(1)
            if let continuity = side.continuity {
                try OriginalParameterQueryStorage.append(FeatureInput(featureID: continuity.source, role: continuity.bodyRole), to: &result, using: &execution)
            }
        }

        var seen = Set<FeatureInput>()
        let filtered = try OriginalParameterQueryStorage.filter(result, using: &execution) { value, execution in
            try OriginalParameterQueryStorage.insert(value, in: &seen, using: &execution)
        }
        try execution.checkpoint()
        return filtered
    }
}

/// One side of a Square: its curve and, when it runs along an edge of a body, how the Square meets
/// the face beside that edge; a Free side is followed loosely, by the Square's weight.
public struct SquareSide: Hashable, Sendable {
    public var curve: CurveSectionReference
    public var continuity: SurfaceEdgeContinuity?
    public var isFree: Bool

    public init(curve: CurveSectionReference, continuity: SurfaceEdgeContinuity? = nil, isFree: Bool = false) {
        self.curve = curve
        self.continuity = continuity
        self.isFree = isFree
    }

#if !hasFeature(Embedded)
    private enum CodingKeys: String, CodingKey {
        case curve, continuity, isFree
    }
#endif

#if !hasFeature(Embedded)
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try container.validateOnlyExpectedKeys([.curve, .continuity, .isFree], in: decoder)
        curve = try container.decode(CurveSectionReference.self, forKey: .curve)
        continuity = try container.decodeIfPresent(SurfaceEdgeContinuity.self, forKey: .continuity)
        isFree = try container.decodeIfPresent(Bool.self, forKey: .isFree) ?? false
        try validate()
    }
#endif

#if !hasFeature(Embedded)
    public func encode(to encoder: Encoder) throws {
        try validate()
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(curve, forKey: .curve)
        try container.encodeIfPresent(continuity, forKey: .continuity)
        if isFree { try container.encode(true, forKey: .isFree) }
    }
#endif

    public func validate() throws {
        var execution = try OriginalQueryExecution.independentGeometry()
        try validate(using: &execution)
    }

    public func validate(using execution: inout OriginalQueryExecution) throws {
        try execution.consumeWork(1)
        try curve.validate(using: &execution)
        try continuity?.validate(using: &execution)
        guard !(isFree && continuity != nil) else {
            throw FeatureEvaluationError.invalidGraph("A Free Square side takes no continuity.")
        }
        try execution.checkpoint()
    }
}

#if !hasFeature(Embedded)
extension SquareSurfaceFeature: Codable {}
extension SquareSide: Codable {}
#endif
