import CADCore
import CADGeometry

/// How Wrap takes a point's UVN coordinates on the reference face to the target face: `s` and
/// `t` are the face's support parameters normalized over its parameter box, `n` the height along
/// its outward normal. Scale and offset act about the box's centre and in its normalized units, N
/// scaled and offset as a length; the flips mirror `s`, swap `s` and `t`, and turn the normal.
public struct WrapOptions: Codable, Hashable, Sendable {
    public var scaleU: Double
    public var scaleV: Double
    public var scaleN: Double
    public var offsetU: Double
    public var offsetV: Double
    public var offsetN: CADExpression
    public var mirrors: Bool
    public var flipsUV: Bool
    public var flipsNormal: Bool

    public init(
        scaleU: Double = 1, scaleV: Double = 1, scaleN: Double = 1,
        offsetU: Double = 0, offsetV: Double = 0, offsetN: CADExpression = .constant(.length(0, unit: .meter)),
        mirrors: Bool = false, flipsUV: Bool = false, flipsNormal: Bool = false
    ) {
        self.scaleU = scaleU
        self.scaleV = scaleV
        self.scaleN = scaleN
        self.offsetU = offsetU
        self.offsetV = offsetV
        self.offsetN = offsetN
        self.mirrors = mirrors
        self.flipsUV = flipsUV
        self.flipsNormal = flipsNormal
    }

    public func validate() throws {
        for value in [scaleU, scaleV, scaleN, offsetU, offsetV] where !value.isFinite {
            throw FeatureEvaluationError.invalidGraph("Wrap scales and offsets must be finite.")
        }
        guard scaleU != 0, scaleV != 0, scaleN != 0 else {
            throw FeatureEvaluationError.invalidGraph("Wrap scales must be non-zero: a zero scale flattens the body.")
        }
    }

    /// The target coordinates of reference coordinates `(s, t, n)`, `offsetN` the resolved N offset.
    public func mapped(s: Double, t: Double, n: Double, offsetN: Double) -> (s: Double, t: Double, n: Double) {
        var s = s, t = t
        if flipsUV { swap(&s, &t) }
        if mirrors { s = 1 - s }
        let height = n * scaleN + offsetN
        return (0.5 + (s - 0.5) * scaleU + offsetU, 0.5 + (t - 0.5) * scaleV + offsetV, flipsNormal ? -height : height)
    }
}

/// A body deformed from one face onto another (Deform Solid and Sheet): each point of the body
/// goes from its UVN coordinates on the reference face, through the options, to the same
/// coordinates on the target face. The faces may belong to any bodies, the target's own among
/// them, as they are before this feature. The result lives in the target's frame; a face's
/// placement says where its body sits in that frame (`nil`: where it was evaluated). The body is
/// replaced unless `keepsTarget`, which leaves it and adds the deformed copy.
public struct WrapFeature: Codable, Hashable, Sendable {
    public var target: PatternTargetReference
    public var referenceFace: StableSubshapeReference
    public var targetFace: StableSubshapeReference
    /// Where the reference face's body sits in the target's frame.
    public var referencePlacement: RigidTransform3D?
    /// Where the target face's body sits in the target's frame.
    public var targetPlacement: RigidTransform3D?
    public var options: WrapOptions
    public var keepsTarget: Bool

    public init(
        target: PatternTargetReference,
        referenceFace: StableSubshapeReference,
        targetFace: StableSubshapeReference,
        referencePlacement: RigidTransform3D? = nil,
        targetPlacement: RigidTransform3D? = nil,
        options: WrapOptions = WrapOptions(),
        keepsTarget: Bool = false
    ) {
        self.target = target
        self.referenceFace = referenceFace
        self.targetFace = targetFace
        self.referencePlacement = referencePlacement
        self.targetPlacement = targetPlacement
        self.options = options
        self.keepsTarget = keepsTarget
    }

    public func validate() throws {
        try target.validate()
        try referenceFace.validate()
        try targetFace.validate()
        try options.validate()
    }

    /// The features this one reads: the target body, then the owners of the faces, each once.
    public var sourceInputs: [FeatureInput] {
        var inputs = [FeatureInput(featureID: target.featureID, role: .target)]
        for owner in [referenceFace.subshapeID.featureID, targetFace.subshapeID.featureID]
        where !inputs.contains(where: { $0.featureID == owner }) {
            inputs.append(FeatureInput(featureID: owner, role: .target))
        }
        return inputs
    }

    /// A deformed body keeps its kind.
    public func resultPort(sourcePort: FeaturePort) throws -> FeaturePort {
        guard sourcePort == .body || sourcePort == .sheet else {
            throw FeatureEvaluationError.invalidGraph("Wrap needs a solid or sheet target.")
        }
        return sourcePort
    }

    private enum CodingKeys: String, CodingKey {
        case target, referenceFace, targetFace, referencePlacement, targetPlacement, options, keepsTarget
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try container.validateOnlyExpectedKeys([.target, .referenceFace, .targetFace, .referencePlacement, .targetPlacement, .options, .keepsTarget], in: decoder)
        target = try container.decode(PatternTargetReference.self, forKey: .target)
        referenceFace = try container.decode(StableSubshapeReference.self, forKey: .referenceFace)
        targetFace = try container.decode(StableSubshapeReference.self, forKey: .targetFace)
        referencePlacement = try container.decodeIfPresent(RigidTransform3D.self, forKey: .referencePlacement)
        targetPlacement = try container.decodeIfPresent(RigidTransform3D.self, forKey: .targetPlacement)
        options = try container.decode(WrapOptions.self, forKey: .options)
        keepsTarget = try container.decode(Bool.self, forKey: .keepsTarget)
        try validate()
    }

    public func encode(to encoder: Encoder) throws {
        try validate()
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(target, forKey: .target)
        try container.encode(referenceFace, forKey: .referenceFace)
        try container.encode(targetFace, forKey: .targetFace)
        try container.encodeIfPresent(referencePlacement, forKey: .referencePlacement)
        try container.encodeIfPresent(targetPlacement, forKey: .targetPlacement)
        try container.encode(options, forKey: .options)
        try container.encode(keepsTarget, forKey: .keepsTarget)
    }
}
