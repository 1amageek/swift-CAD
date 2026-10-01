import CADCore

/// A pipe along a curve: a circle (or a regular polygon) of `diameter`, or a custom `profile` (a
/// region or a planar face), standing across the path at its start, hollow to a wall `thickness`
/// when one is given, swept along the path between the `start` and `end` fractions of its length,
/// turned by `angle` about the path and scaled to `endScale` at its end, as a new body or combined
/// with `targets`. A pipe has exactly one of `diameter` and `profile`.
public struct PipeFeature: Codable, Hashable, Sendable {
    public var path: SweepPathReference
    /// The circle's or polygon's size; nil for a custom profile.
    public var diameter: CADExpression?
    /// The custom section, carried rigidly so its area centroid sits on the path's start and its
    /// plane stands across the path (the least rotation of its normal onto the path's tangent).
    public var profile: SectionReference?
    public var thickness: CADExpression?
    /// Zero for a circle, otherwise the regular polygon's vertex count.
    public var vertexCount: Int
    public var angle: CADExpression
    public var endScale: CADExpression
    public var start: CADExpression
    public var end: CADExpression
    public var booleanOperation: SweepBooleanOperation
    public var targets: [SweepTargetReference]
    public var keepTools: Bool
    /// The positional allowance a curved path's pipe is built within.
    public var approximationTolerance: CADExpression

    public init(
        path: SweepPathReference,
        diameter: CADExpression? = nil,
        profile: SectionReference? = nil,
        thickness: CADExpression? = nil,
        vertexCount: Int = 0,
        angle: CADExpression = .constant(.angle(0, unit: .degree)),
        endScale: CADExpression = .constant(.scalar(1)),
        start: CADExpression = .constant(.scalar(0)),
        end: CADExpression = .constant(.scalar(1)),
        booleanOperation: SweepBooleanOperation = .newBody,
        targets: [SweepTargetReference] = [],
        keepTools: Bool = false,
        approximationTolerance: CADExpression
    ) {
        self.path = path
        self.diameter = diameter
        self.profile = profile
        self.thickness = thickness
        self.vertexCount = vertexCount
        self.angle = angle
        self.endScale = endScale
        self.start = start
        self.end = end
        self.booleanOperation = booleanOperation
        self.targets = targets
        self.keepTools = keepTools
        self.approximationTolerance = approximationTolerance
    }

    private enum CodingKeys: String, CodingKey {
        case path, diameter, profile, thickness, vertexCount, angle, endScale, start, end, booleanOperation, targets, keepTools, approximationTolerance
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try container.validateOnlyExpectedKeys([
            .path, .diameter, .profile, .thickness, .vertexCount, .angle, .endScale, .start, .end,
            .booleanOperation, .targets, .keepTools, .approximationTolerance,
        ], in: decoder)
        path = try container.decode(SweepPathReference.self, forKey: .path)
        diameter = try container.decodeIfPresent(CADExpression.self, forKey: .diameter)
        profile = try container.decodeIfPresent(SectionReference.self, forKey: .profile)
        thickness = try container.decodeIfPresent(CADExpression.self, forKey: .thickness)
        vertexCount = try container.decode(Int.self, forKey: .vertexCount)
        angle = try container.decode(CADExpression.self, forKey: .angle)
        endScale = try container.decode(CADExpression.self, forKey: .endScale)
        start = try container.decode(CADExpression.self, forKey: .start)
        end = try container.decode(CADExpression.self, forKey: .end)
        booleanOperation = try container.decode(SweepBooleanOperation.self, forKey: .booleanOperation)
        targets = try container.decodeIfPresent([SweepTargetReference].self, forKey: .targets) ?? []
        keepTools = try container.decodeIfPresent(Bool.self, forKey: .keepTools) ?? false
        approximationTolerance = try container.decode(CADExpression.self, forKey: .approximationTolerance)
        try validate()
    }

    public func encode(to encoder: Encoder) throws {
        try validate()
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(path, forKey: .path)
        try container.encodeIfPresent(diameter, forKey: .diameter)
        try container.encodeIfPresent(profile, forKey: .profile)
        try container.encodeIfPresent(thickness, forKey: .thickness)
        try container.encode(vertexCount, forKey: .vertexCount)
        try container.encode(angle, forKey: .angle)
        try container.encode(endScale, forKey: .endScale)
        try container.encode(start, forKey: .start)
        try container.encode(end, forKey: .end)
        try container.encode(booleanOperation, forKey: .booleanOperation)
        if !targets.isEmpty { try container.encode(targets, forKey: .targets) }
        if keepTools { try container.encode(keepTools, forKey: .keepTools) }
        try container.encode(approximationTolerance, forKey: .approximationTolerance)
    }

    public func validate() throws {
        guard vertexCount == 0 || (3...256).contains(vertexCount) else {
            throw FeatureEvaluationError.invalidGraph("A pipe's section is a circle or a polygon of 3 to 256 vertices.")
        }
        guard (diameter == nil) != (profile == nil) else {
            throw FeatureEvaluationError.invalidGraph("A pipe has either a diameter or a custom profile.")
        }
        if let profile {
            try profile.validate()
            guard vertexCount == 0, profile.isClosedRegion, profile.featureID != path.featureID else {
                throw FeatureEvaluationError.invalidGraph(
                    "A pipe's custom profile is a region or a planar face, distinct from its path, without a vertex count."
                )
            }
        }
        let targetIDs = targets.map(\.featureID)
        guard Set(targetIDs).count == targetIDs.count, !targetIDs.contains(path.featureID) else {
            throw FeatureEvaluationError.invalidGraph("A pipe's targets are unique bodies distinct from its path.")
        }
        switch booleanOperation {
        case .newBody:
            guard targets.isEmpty, !keepTools else {
                throw FeatureEvaluationError.invalidGraph("A new-body pipe declares no targets and no Keep Tools.")
            }
        case .union, .difference, .intersect, .slice:
            guard !targets.isEmpty else {
                throw FeatureEvaluationError.invalidGraph("A Boolean pipe needs at least one target body.")
            }
        }
        for expression in expressions {
            try expression.validateLiteralQuantities()
        }
    }

    /// The features the pipe consumes: its custom profile's source, its path and its targets.
    public var inputs: [FeatureInput] {
        (profile.map { [FeatureInput(featureID: $0.featureID, role: $0.inputRole)] } ?? [])
            + [FeatureInput(featureID: path.featureID, role: .path)]
            + targets.map { FeatureInput(featureID: $0.featureID, role: .target) }
    }

    /// The expressions whose parameters the pipe depends on.
    public var expressions: [CADExpression] {
        [angle, endScale, start, end, approximationTolerance] + [diameter, thickness].compactMap { $0 }
    }
}
