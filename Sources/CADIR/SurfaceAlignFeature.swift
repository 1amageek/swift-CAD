import CADCore
import CADGeometry

/// Align Surface: a single-face B-spline sheet's edge made to follow a reference edge, of another
/// body placed by `referencePlacement` in the target's frame (where it is, when nil), with
/// positional, tangent-plane or curvature continuity, the speed across the edge scaled by
/// `tension` and the change faded over `blendRows` further control rows.
public struct SurfaceAlignFeature: Codable, Hashable, Sendable {
    public var target: PatternTargetReference
    public var targetEdge: StableSubshapeReference
    public var reference: PatternTargetReference
    public var referenceEdge: StableSubshapeReference
    public var referencePlacement: RigidTransform3D?
    public var continuity: SurfaceContinuityLevel
    public var tension: Double
    public var blendRows: Int

    public init(
        target: PatternTargetReference, targetEdge: StableSubshapeReference,
        reference: PatternTargetReference, referenceEdge: StableSubshapeReference,
        referencePlacement: RigidTransform3D? = nil, continuity: SurfaceContinuityLevel = .tangentPlane,
        tension: Double = 1, blendRows: Int = 0
    ) {
        self.target = target
        self.targetEdge = targetEdge
        self.reference = reference
        self.referenceEdge = referenceEdge
        self.referencePlacement = referencePlacement
        self.continuity = continuity
        self.tension = tension
        self.blendRows = blendRows
    }

    public func validate() throws {
        try target.validate()
        try reference.validate()
        try targetEdge.validate()
        try referenceEdge.validate()
        guard target.featureID != reference.featureID else {
            throw FeatureEvaluationError.invalidGraph("Align Surface aligns a sheet to an edge of another body.")
        }
        guard tension.isFinite, tension > 0 else {
            throw FeatureEvaluationError.invalidGraph("Align Surface tension must be positive.")
        }
        guard (0...64).contains(blendRows) else {
            throw FeatureEvaluationError.invalidGraph("Align Surface blends no more than 64 further rows.")
        }
    }

    private enum CodingKeys: String, CodingKey {
        case target, targetEdge, reference, referenceEdge, referencePlacement, continuity, tension, blendRows
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try container.validateOnlyExpectedKeys(
            [.target, .targetEdge, .reference, .referenceEdge, .referencePlacement, .continuity, .tension, .blendRows], in: decoder
        )
        target = try container.decode(PatternTargetReference.self, forKey: .target)
        targetEdge = try container.decode(StableSubshapeReference.self, forKey: .targetEdge)
        reference = try container.decode(PatternTargetReference.self, forKey: .reference)
        referenceEdge = try container.decode(StableSubshapeReference.self, forKey: .referenceEdge)
        referencePlacement = try container.decodeIfPresent(RigidTransform3D.self, forKey: .referencePlacement)
        continuity = try container.decode(SurfaceContinuityLevel.self, forKey: .continuity)
        tension = try container.decode(Double.self, forKey: .tension)
        blendRows = try container.decode(Int.self, forKey: .blendRows)
        try validate()
    }

    public func encode(to encoder: Encoder) throws {
        try validate()
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(target, forKey: .target)
        try container.encode(targetEdge, forKey: .targetEdge)
        try container.encode(reference, forKey: .reference)
        try container.encode(referenceEdge, forKey: .referenceEdge)
        try container.encodeIfPresent(referencePlacement, forKey: .referencePlacement)
        try container.encode(continuity, forKey: .continuity)
        try container.encode(tension, forKey: .tension)
        try container.encode(blendRows, forKey: .blendRows)
    }

    /// The inputs the feature reads: its sheet, consumed, and the reference's body.
    public var inputs: [FeatureInput] {
        [FeatureInput(featureID: target.featureID, role: .target), FeatureInput(featureID: reference.featureID, role: .body)]
    }
}
