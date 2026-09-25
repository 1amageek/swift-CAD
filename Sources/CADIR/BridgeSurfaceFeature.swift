import CADCore
import CADGeometry

public struct BridgeSurfaceFeature: Codable, Sendable, Hashable {
    public enum EndOrientation: String, Codable, Sendable, Hashable {
        case forward
        case reversed
    }

    public let startBoundary: StableSubshapeReference
    public let endBoundary: StableSubshapeReference
    public let endOrientation: EndOrientation
    public let startTransform: AffineTransform3D?
    public let endTransform: AffineTransform3D?

    public init(
        startBoundary: StableSubshapeReference,
        endBoundary: StableSubshapeReference,
        endOrientation: EndOrientation = .forward,
        startTransform: AffineTransform3D? = nil,
        endTransform: AffineTransform3D? = nil
    ) {
        self.startBoundary = startBoundary
        self.endBoundary = endBoundary
        self.endOrientation = endOrientation
        self.startTransform = startTransform
        self.endTransform = endTransform
    }

    private enum CodingKeys: String, CodingKey {
        case startBoundary
        case endBoundary
        case endOrientation
        case startTransform
        case endTransform
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try container.validateOnlyExpectedKeys(
            [.startBoundary, .endBoundary, .endOrientation, .startTransform, .endTransform],
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
        try validate(tolerance: CADIRPersistenceValidation.tolerance)
    }

    public func encode(to encoder: Encoder) throws {
        try validate(tolerance: CADIRPersistenceValidation.tolerance)
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(startBoundary, forKey: .startBoundary)
        try container.encode(endBoundary, forKey: .endBoundary)
        try container.encode(endOrientation, forKey: .endOrientation)
        try container.encodeIfPresent(startTransform, forKey: .startTransform)
        try container.encodeIfPresent(endTransform, forKey: .endTransform)
    }

    public func validate(tolerance: ModelingTolerance) throws {
        try tolerance.validate()
        try startBoundary.validate()
        try endBoundary.validate()
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
        let first = FeatureInput(featureID: targetFeatureID, role: .target)
        let secondID = endBoundary.subshapeID.featureID
        return secondID == targetFeatureID
            ? [first]
            : [first, FeatureInput(featureID: secondID, role: .target)]
    }
}
