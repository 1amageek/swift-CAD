import CADCore
import CADGeometry

/// Align Surface: a single-face B-spline sheet's edge made to follow a reference edge, of another
/// body placed by `referencePlacement` in the target's frame (where it is, when nil), with
/// positional, tangent-plane or curvature continuity, the speed across the edge scaled by
/// `tension` and the change faded over `blendRows` further control rows, which keep
/// `inputShapeInfluence` of their own shape. The whole edge is attached to the stretch of the
/// reference edge from `partialStart` to `partialEnd` (0 and 1: all of it), and the sheet is first refitted to `layout`
/// when one is given.
public struct SurfaceAlignFeature: Codable, Hashable, Sendable {
    public var target: PatternTargetReference
    public var targetEdge: StableSubshapeReference
    public var reference: PatternTargetReference
    public var referenceEdge: StableSubshapeReference
    public var referencePlacement: RigidTransform3D?
    public var continuity: SurfaceContinuityLevel
    public var tension: Double
    public var blendRows: Int
    public var inputShapeInfluence: Double
    public var partialStart: Double
    public var partialEnd: Double
    public var layout: SurfaceControlLayout?
    /// The cross-edge flow along a G1 or G2 edge (Plasticity's Boundary): the reference's next
    /// inner row (`next`), perpendicular to the edge (`normal`), the target's own (`natural`) or
    /// its side edges' (`adjacent`), each in the reference's tangent plane.
    public var boundaryFlow: SquareFitOptions.BoundaryFlow

    public init(
        target: PatternTargetReference, targetEdge: StableSubshapeReference,
        reference: PatternTargetReference, referenceEdge: StableSubshapeReference,
        referencePlacement: RigidTransform3D? = nil, continuity: SurfaceContinuityLevel = .tangentPlane,
        tension: Double = 1, blendRows: Int = 0, inputShapeInfluence: Double = 1,
        partialStart: Double = 0, partialEnd: Double = 1, layout: SurfaceControlLayout? = nil,
        boundaryFlow: SquareFitOptions.BoundaryFlow = .next
    ) {
        self.target = target
        self.targetEdge = targetEdge
        self.reference = reference
        self.referenceEdge = referenceEdge
        self.referencePlacement = referencePlacement
        self.continuity = continuity
        self.tension = tension
        self.blendRows = blendRows
        self.inputShapeInfluence = inputShapeInfluence
        self.partialStart = partialStart
        self.partialEnd = partialEnd
        self.layout = layout
        self.boundaryFlow = boundaryFlow
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
        guard (0...1).contains(inputShapeInfluence) else {
            throw FeatureEvaluationError.invalidGraph("Align Surface's input shape influence runs from 0 to 1.")
        }
        guard (0...1).contains(partialStart), (0...1).contains(partialEnd), partialEnd > partialStart else {
            throw FeatureEvaluationError.invalidGraph("Align Surface's partial start and end are fractions of the reference edge, the start before the end.")
        }
        try layout?.validate()
    }

    private enum CodingKeys: String, CodingKey {
        case target, targetEdge, reference, referenceEdge, referencePlacement, continuity, tension, blendRows
        case inputShapeInfluence, partialStart, partialEnd, layout, boundaryFlow
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try container.validateOnlyExpectedKeys(
            [.target, .targetEdge, .reference, .referenceEdge, .referencePlacement, .continuity, .tension, .blendRows,
             .inputShapeInfluence, .partialStart, .partialEnd, .layout, .boundaryFlow], in: decoder
        )
        target = try container.decode(PatternTargetReference.self, forKey: .target)
        targetEdge = try container.decode(StableSubshapeReference.self, forKey: .targetEdge)
        reference = try container.decode(PatternTargetReference.self, forKey: .reference)
        referenceEdge = try container.decode(StableSubshapeReference.self, forKey: .referenceEdge)
        referencePlacement = try container.decodeIfPresent(RigidTransform3D.self, forKey: .referencePlacement)
        continuity = try container.decode(SurfaceContinuityLevel.self, forKey: .continuity)
        tension = try container.decode(Double.self, forKey: .tension)
        blendRows = try container.decode(Int.self, forKey: .blendRows)
        inputShapeInfluence = try container.decode(Double.self, forKey: .inputShapeInfluence)
        partialStart = try container.decode(Double.self, forKey: .partialStart)
        partialEnd = try container.decode(Double.self, forKey: .partialEnd)
        layout = try container.decodeIfPresent(SurfaceControlLayout.self, forKey: .layout)
        boundaryFlow = try container.decodeIfPresent(SquareFitOptions.BoundaryFlow.self, forKey: .boundaryFlow) ?? .next
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
        try container.encode(inputShapeInfluence, forKey: .inputShapeInfluence)
        try container.encode(partialStart, forKey: .partialStart)
        try container.encode(partialEnd, forKey: .partialEnd)
        try container.encodeIfPresent(layout, forKey: .layout)
        try container.encode(boundaryFlow, forKey: .boundaryFlow)
    }

    /// The inputs the feature reads: its sheet, consumed, and the reference's body.
    public var inputs: [FeatureInput] {
        [FeatureInput(featureID: target.featureID, role: .target), FeatureInput(featureID: reference.featureID, role: .body)]
    }
}
