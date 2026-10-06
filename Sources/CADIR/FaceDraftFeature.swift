import CADCore
import CADTopology

/// Draft Face, isocline: faces of one solid turned about where they cross the neutral plane (the
/// neutral face's plane, moved `neutralOffset` along its outward side) so each makes `angle` with
/// the pull direction, the neutral face's outward normal. A positive angle leans each face out
/// as it runs away from the neutral plane. Planar faces stay planar; a cylinder along the pull
/// direction becomes the cone through its circle on the neutral plane.
public struct FaceDraftFeature: Hashable, Sendable {
    public var target: FaceDraftTargetReference
    public var faces: [StableSubshapeReference]
    public var neutralFace: StableSubshapeReference
    public var angle: CADExpression
    public var neutralOffset: CADExpression?
    public var grow: FaceEditGrow
    /// How each face's turn is taken: about where it crosses the neutral plane against the pull
    /// direction (isocline), about chosen edges (curve), against another face's pull direction
    /// (surface), or against the reference's own normal (normal).
    public var method: FaceDraftMethod

    public init(
        target: FaceDraftTargetReference,
        faces: [StableSubshapeReference],
        neutralFace: StableSubshapeReference,
        angle: CADExpression,
        neutralOffset: CADExpression? = nil,
        grow: FaceEditGrow = .moving,
        method: FaceDraftMethod = .isocline
    ) {
        self.target = target
        self.faces = faces
        self.neutralFace = neutralFace
        self.angle = angle
        self.neutralOffset = neutralOffset
        self.grow = grow
        self.method = method
    }

    public func validate() throws {
        try target.validate()
        guard faces.isEmpty == false else {
            throw FeatureEvaluationError.invalidGraph("Face Draft requires at least one face target.")
        }
        var seen = Set<StableSubshapeReference>()
        for face in faces {
            try face.validate()
            guard seen.insert(face).inserted else {
                throw FeatureEvaluationError.invalidGraph("Face Draft targets must be unique.")
            }
        }
        try neutralFace.validate()
        guard seen.contains(neutralFace) == false else {
            throw FeatureEvaluationError.invalidGraph("Face Draft neutral face must be distinct from target faces.")
        }
        try angle.validateLiteralQuantities()
        try neutralOffset?.validateLiteralQuantities()
        try method.validate()
    }

#if !hasFeature(Embedded)
    private enum CodingKeys: String, CodingKey {
        case target
        case faces
        case neutralFace
        case angle
        case neutralOffset
        case grow
        case method
    }
#endif

#if !hasFeature(Embedded)
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try container.validateOnlyExpectedKeys(
            [.target, .faces, .neutralFace, .angle, .neutralOffset, .grow, .method],
            in: decoder
        )
        target = try container.decode(FaceDraftTargetReference.self, forKey: .target)
        faces = try container.decode([StableSubshapeReference].self, forKey: .faces)
        neutralFace = try container.decode(StableSubshapeReference.self, forKey: .neutralFace)
        angle = try container.decode(CADExpression.self, forKey: .angle)
        neutralOffset = try container.decodeIfPresent(CADExpression.self, forKey: .neutralOffset)
        grow = try container.decode(FaceEditGrow.self, forKey: .grow)
        method = try container.decodeIfPresent(FaceDraftMethod.self, forKey: .method) ?? .isocline
        try validate()
    }
#endif

#if !hasFeature(Embedded)
    public func encode(to encoder: Encoder) throws {
        try validate()
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(target, forKey: .target)
        try container.encode(faces, forKey: .faces)
        try container.encode(neutralFace, forKey: .neutralFace)
        try container.encode(angle, forKey: .angle)
        try container.encodeIfPresent(neutralOffset, forKey: .neutralOffset)
        try container.encode(grow, forKey: .grow)
        // Isocline, the method of every earlier document, is left out so those stay byte-identical.
        if method != .isocline { try container.encode(method, forKey: .method) }
    }
}

/// Draft Face's taper method.
public enum FaceDraftMethod: Codable, Hashable, Sendable {
    /// Each face turns about its crossing with the neutral plane, making the angle with the pull
    /// direction (the neutral face's outward normal).
    case isocline
    /// Each face turns about the chosen straight edge lying on it (the parting line), making the
    /// angle with the neutral face's pull direction; each edge square to that direction.
    case curve(pivots: [StableSubshapeReference])
    /// Each face turns about its crossing with the neutral plane, making the angle with the
    /// outward normal of another planar face of the body.
    case surface(reference: StableSubshapeReference)
    /// Each face makes the angle with the reference face's own normal where it meets it: on a
    /// planar reference the isocline draft, on a curved one the ruled draft about the shared edge.
    case normal

    public func validate() throws {
        switch self {
        case .isocline, .normal:
            return
        case let .curve(pivots):
            guard pivots.isEmpty == false else {
                throw FeatureEvaluationError.invalidGraph("A curve draft needs at least one pivot edge.")
            }
            var seen = Set<StableSubshapeReference>()
            for pivot in pivots {
                try pivot.validate()
                guard seen.insert(pivot).inserted else {
                    throw FeatureEvaluationError.invalidGraph("A curve draft's pivot edges must be unique.")
                }
            }
        case let .surface(reference):
            try reference.validate()
        }
    }
#endif
}

public struct FaceDraftTargetReference: Hashable, Sendable {
    public var featureID: FeatureID

    public init(featureID: FeatureID) {
        self.featureID = featureID
    }

    public func validate() throws {}

#if !hasFeature(Embedded)
    private enum CodingKeys: String, CodingKey {
        case featureID
    }
#endif

#if !hasFeature(Embedded)
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try container.validateOnlyExpectedKeys([.featureID], in: decoder)
        featureID = try container.decode(FeatureID.self, forKey: .featureID)
        try validate()
    }
#endif

#if !hasFeature(Embedded)
    public func encode(to encoder: Encoder) throws {
        try validate()
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(featureID, forKey: .featureID)
    }
#endif
}

#if !hasFeature(Embedded)
extension FaceDraftFeature: Codable {}
extension FaceDraftTargetReference: Codable {}
#endif
