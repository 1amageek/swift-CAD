import CADCore
import CADGeometry

public struct BridgeSurfaceFeature: Sendable, Hashable {
    public enum EndOrientation: String, Sendable, Hashable {
        case forward
        case reversed
    }

    public let startBoundary: StableSubshapeReference
    public let endBoundary: StableSubshapeReference
    public let endOrientation: EndOrientation
    public let startTransform: AffineTransform3D?
    public let endTransform: AffineTransform3D?
    public let startContinuity: SurfaceContinuityLevel
    public let endContinuity: SurfaceContinuityLevel
    public let startTension: Double
    public let endTension: Double
    public let width: Double?
    public let startWall: StableSubshapeReference?
    public let endWall: StableSubshapeReference?

    public init(
        startBoundary: StableSubshapeReference,
        endBoundary: StableSubshapeReference,
        endOrientation: EndOrientation = .forward,
        startTransform: AffineTransform3D? = nil,
        endTransform: AffineTransform3D? = nil,
        startContinuity: SurfaceContinuityLevel = .positional,
        endContinuity: SurfaceContinuityLevel = .positional,
        startTension: Double = 1,
        endTension: Double = 1,
        width: Double? = nil,
        startWall: StableSubshapeReference? = nil,
        endWall: StableSubshapeReference? = nil
    ) {
        self.startBoundary = startBoundary
        self.endBoundary = endBoundary
        self.endOrientation = endOrientation
        self.startTransform = startTransform
        self.endTransform = endTransform
        self.startContinuity = startContinuity
        self.endContinuity = endContinuity
        self.startTension = startTension
        self.endTension = endTension
        self.width = width
        self.startWall = startWall
        self.endWall = endWall
    }

#if !hasFeature(Embedded)
    private enum CodingKeys: String, CodingKey {
        case startBoundary
        case endBoundary
        case endOrientation
        case startTransform
        case endTransform
        case startContinuity, endContinuity, startTension, endTension, width, startWall, endWall
    }
#endif

#if !hasFeature(Embedded)
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try container.validateOnlyExpectedKeys(
            [.startBoundary, .endBoundary, .endOrientation, .startTransform, .endTransform,
             .startContinuity, .endContinuity, .startTension, .endTension, .width, .startWall, .endWall],
            in: decoder
        )
        startBoundary = try container.decode(StableSubshapeReference.self, forKey: .startBoundary)
        endBoundary = try container.decode(StableSubshapeReference.self, forKey: .endBoundary)
        endOrientation = try container.decode(
            EndOrientation.self,
            forKey: .endOrientation
        )
        startTransform = try container.decodeIfPresent(AffineTransform3D.self, forKey: .startTransform)
        endTransform = try container.decodeIfPresent(AffineTransform3D.self, forKey: .endTransform)
        startContinuity = try container.decode(SurfaceContinuityLevel.self, forKey: .startContinuity)
        endContinuity = try container.decode(SurfaceContinuityLevel.self, forKey: .endContinuity)
        startTension = try container.decode(Double.self, forKey: .startTension)
        endTension = try container.decode(Double.self, forKey: .endTension)
        width = try container.decodeIfPresent(Double.self, forKey: .width)
        startWall = try container.decodeIfPresent(StableSubshapeReference.self, forKey: .startWall)
        endWall = try container.decodeIfPresent(StableSubshapeReference.self, forKey: .endWall)
        try validate(tolerance: CADIRPersistenceValidation.tolerance)
    }
#endif

#if !hasFeature(Embedded)
    public func encode(to encoder: Encoder) throws {
        try validate(tolerance: CADIRPersistenceValidation.tolerance)
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(startBoundary, forKey: .startBoundary)
        try container.encode(endBoundary, forKey: .endBoundary)
        try container.encode(endOrientation, forKey: .endOrientation)
        try container.encodeIfPresent(startTransform, forKey: .startTransform)
        try container.encodeIfPresent(endTransform, forKey: .endTransform)
        try container.encode(startContinuity, forKey: .startContinuity)
        try container.encode(endContinuity, forKey: .endContinuity)
        try container.encode(startTension, forKey: .startTension)
        try container.encode(endTension, forKey: .endTension)
        try container.encodeIfPresent(width, forKey: .width)
        try container.encodeIfPresent(startWall, forKey: .startWall)
        try container.encodeIfPresent(endWall, forKey: .endWall)
    }
#endif

    public func validate(tolerance: ModelingTolerance) throws {
        try tolerance.validate()
        try startBoundary.validate()
        try endBoundary.validate()
        guard startTension.isFinite, startTension > 0,
              endTension.isFinite, endTension > 0 else {
            throw FeatureEvaluationError.invalidGraph("Bridge tensions must be finite and positive.")
        }
        if let width {
            guard width.isFinite, width > tolerance.distance else {
                throw FeatureEvaluationError.invalidGraph("Bridge width must exceed the source distance tolerance.")
            }
        }
        for wall in [startWall, endWall].compactMap({ $0 }) {
            try wall.validate()
            guard case .face = wall.geometrySignature else {
                throw FeatureEvaluationError.invalidGraph("Bridge supporting walls require stable face references.")
            }
        }
        for transform in [startTransform, endTransform].compactMap({ $0 }) {
            try transform.validate()
            let determinant = transform.basisX.dot(transform.basisY.cross(transform.basisZ))
            guard determinant.isFinite, determinant != 0 else {
                throw FeatureEvaluationError.invalidGraph("Boundary coordinate maps must be nonsingular.")
            }
        }
        guard (startBoundary.subshapeID != endBoundary.subshapeID || startTransform != endTransform),
              case .edge = startBoundary.geometrySignature,
              case .edge = endBoundary.geometrySignature else {
            throw FeatureEvaluationError.invalidGraph(
                "Bridge surface requires two distinct edge references."
            )
        }
    }

    public var targetFeatureID: FeatureID { startBoundary.subshapeID.featureID }

    public var sourceInputs: [FeatureInput] {
        var inputs = [FeatureInput(featureID: targetFeatureID, role: .target)]
        for id in [endBoundary.subshapeID.featureID, startWall?.subshapeID.featureID,
                   endWall?.subshapeID.featureID].compactMap({ $0 }) {
            if !inputs.contains(where: { $0.featureID == id }) {
                inputs.append(FeatureInput(featureID: id, role: .target))
            }
        }
        return inputs
    }
}

#if !hasFeature(Embedded)
extension BridgeSurfaceFeature: Codable {}
extension BridgeSurfaceFeature.EndOrientation: Codable {}
#endif
