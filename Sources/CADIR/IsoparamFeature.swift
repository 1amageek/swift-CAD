import CADCore
import CADGeometry
import CADTopology

/// Edges along a face's surface parameter lines (Isoparam): at each fraction of the face's extent
/// across `direction`, the line along the other parameter is imprinted on the face, and on the
/// faces it runs into, as far as it lies on the face. With `subdividesControlNet` a B-spline
/// surface first gains knots at those lines, as many as its degree, so each line is a row of
/// control points the pieces on either side share.
public struct IsoparamFeature: Codable, Hashable, Sendable {
    public var target: PatternTargetReference
    public var face: StableSubshapeReference
    /// The parameter the lines hold constant.
    public var direction: SurfaceParameterDirection
    /// Where the lines lie across the face's extent in `direction`, each strictly between 0 and 1.
    public var fractions: [Double]
    public var subdividesControlNet: Bool

    public init(
        target: PatternTargetReference,
        face: StableSubshapeReference,
        direction: SurfaceParameterDirection,
        fractions: [Double],
        subdividesControlNet: Bool
    ) {
        self.target = target
        self.face = face
        self.direction = direction
        self.fractions = fractions
        self.subdividesControlNet = subdividesControlNet
    }

    public func validate() throws {
        try target.validate()
        try face.validate()
        guard fractions.isEmpty == false else {
            throw FeatureEvaluationError.invalidGraph("Isoparam needs at least one line.")
        }
        guard fractions.allSatisfy({ $0.isFinite && $0 > 0 && $0 < 1 }) else {
            throw FeatureEvaluationError.invalidGraph("Isoparam lines lie strictly inside the face's extent.")
        }
        guard Set(fractions).count == fractions.count else {
            throw FeatureEvaluationError.invalidGraph("Isoparam lines must be distinct.")
        }
    }

    private enum CodingKeys: String, CodingKey {
        case target, face, direction, fractions, subdividesControlNet
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try container.validateOnlyExpectedKeys([.target, .face, .direction, .fractions, .subdividesControlNet], in: decoder)
        target = try container.decode(PatternTargetReference.self, forKey: .target)
        face = try container.decode(StableSubshapeReference.self, forKey: .face)
        direction = try container.decode(SurfaceParameterDirection.self, forKey: .direction)
        fractions = try container.decode([Double].self, forKey: .fractions)
        subdividesControlNet = try container.decode(Bool.self, forKey: .subdividesControlNet)
        try validate()
    }

    public func encode(to encoder: Encoder) throws {
        try validate()
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(target, forKey: .target)
        try container.encode(face, forKey: .face)
        try container.encode(direction, forKey: .direction)
        try container.encode(fractions, forKey: .fractions)
        try container.encode(subdividesControlNet, forKey: .subdividesControlNet)
    }
}
