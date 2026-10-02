import CADCore

/// Rebuild Face: each chosen face of a body takes a B-spline surface refitted to its own on the
/// same parameters, over the face's parameter extent when `shrinks` (the surface's own domain
/// where it has one otherwise), widened past each side by `extendU` and `extendV` of that extent.
/// The body keeps its topology in its place.
public struct FaceRebuildFeature: Codable, Hashable, Sendable {
    public static let extensions = 0.0...1.0

    public var target: PatternTargetReference
    public var faces: [StableSubshapeReference]
    public var method: FaceRebuildMethod
    public var extendU: Double
    public var extendV: Double
    public var shrinks: Bool

    public init(
        target: PatternTargetReference, faces: [StableSubshapeReference], method: FaceRebuildMethod,
        extendU: Double = 0, extendV: Double = 0, shrinks: Bool = false
    ) {
        self.target = target
        self.faces = faces
        self.method = method
        self.extendU = extendU
        self.extendV = extendV
        self.shrinks = shrinks
    }

    public func validate() throws {
        try target.validate()
        guard faces.isEmpty == false else {
            throw FeatureEvaluationError.invalidGraph("Rebuild Face requires at least one face.")
        }
        var seen = Set<StableSubshapeReference>()
        for face in faces {
            try face.validate()
            guard seen.insert(face).inserted else {
                throw FeatureEvaluationError.invalidGraph("Rebuild Face faces must be unique.")
            }
        }
        try method.validate()
        guard Self.extensions.contains(extendU), Self.extensions.contains(extendV) else {
            throw FeatureEvaluationError.invalidGraph("Rebuild Face extends each way by 0 to 1 of the face's extent.")
        }
        if case .nominal = method, extendU != 0 || extendV != 0 {
            throw FeatureEvaluationError.invalidGraph("Remove Nominal Surface cuts a face's surface to its extent, with no extension.")
        }
        if case .square = method, extendU != 0 || extendV != 0 || shrinks {
            throw FeatureEvaluationError.invalidGraph("Square's Refit spans a face's own edges, with no extension.")
        }
    }

    private enum CodingKeys: String, CodingKey {
        case target, faces, method, extendU, extendV, shrinks
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try container.validateOnlyExpectedKeys([.target, .faces, .method, .extendU, .extendV, .shrinks], in: decoder)
        target = try container.decode(PatternTargetReference.self, forKey: .target)
        faces = try container.decode([StableSubshapeReference].self, forKey: .faces)
        method = try container.decode(FaceRebuildMethod.self, forKey: .method)
        extendU = try container.decode(Double.self, forKey: .extendU)
        extendV = try container.decode(Double.self, forKey: .extendV)
        shrinks = try container.decode(Bool.self, forKey: .shrinks)
        try validate()
    }

    public func encode(to encoder: Encoder) throws {
        try validate()
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(target, forKey: .target)
        try container.encode(faces, forKey: .faces)
        try container.encode(method, forKey: .method)
        try container.encode(extendU, forKey: .extendU)
        try container.encode(extendV, forKey: .extendV)
        try container.encode(shrinks, forKey: .shrinks)
    }

    /// The inputs the feature reads: its target, consumed.
    public var inputs: [FeatureInput] {
        [FeatureInput(featureID: target.featureID, role: .target)]
    }
}

/// How Rebuild Face lays out a face's new surface: an explicit layout of degrees and spans, as few
/// bicubic spans as keep the surface within a distance of the old one, — Remove Nominal Surface —
/// the face's own spline surface cut exactly to its trimmed extent, its hidden spans gone, or —
/// Square's Refit — an untrimmed four-sided sheet on the face's own edges.
public enum FaceRebuildMethod: Codable, Hashable, Sendable {
    case explicit(SurfaceControlLayout)
    case tolerance(CADExpression)
    case nominal
    case square(SquareRefit)

    public func validate() throws {
        switch self {
        case let .explicit(layout): try layout.validate()
        case let .tolerance(distance): try distance.validateLiteralQuantities()
        case .nominal: break
        case let .square(refit): try refit.validate()
        }
    }

    private enum CodingKeys: String, CodingKey {
        case kind, layout, tolerance, square
    }

    private enum Kind: String, Codable {
        case explicit, tolerance, nominal, square
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(Kind.self, forKey: .kind) {
        case .explicit:
            try container.validateOnlyExpectedKeys([.kind, .layout], in: decoder)
            self = .explicit(try container.decode(SurfaceControlLayout.self, forKey: .layout))
        case .tolerance:
            try container.validateOnlyExpectedKeys([.kind, .tolerance], in: decoder)
            self = .tolerance(try container.decode(CADExpression.self, forKey: .tolerance))
        case .nominal:
            try container.validateOnlyExpectedKeys([.kind], in: decoder)
            self = .nominal
        case .square:
            try container.validateOnlyExpectedKeys([.kind, .square], in: decoder)
            self = .square(try container.decode(SquareRefit.self, forKey: .square))
        }
        try validate()
    }

    public func encode(to encoder: Encoder) throws {
        try validate()
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case let .explicit(layout):
            try container.encode(Kind.explicit, forKey: .kind)
            try container.encode(layout, forKey: .layout)
        case let .tolerance(distance):
            try container.encode(Kind.tolerance, forKey: .kind)
            try container.encode(distance, forKey: .tolerance)
        case .nominal:
            try container.encode(Kind.nominal, forKey: .kind)
        case let .square(refit):
            try container.encode(Kind.square, forKey: .kind)
            try container.encode(refit, forKey: .square)
        }
    }
}
