import CADCore

/// Bridge Surface: a blend between two sheets set back by `width` from where they meet — on their
/// extensions when they do not — shaped as a curvature-continuous (G2) quintic or a straight
/// chamfer across, its handles scaled by `tension`. `reversesSense` takes the other side of the
/// meeting line for a sheet crossing it.
public struct SheetBridgeFeature: Codable, Hashable, Sendable {
    public enum Shape: String, Codable, Hashable, Sendable {
        case curvature
        case chamfer
    }

    /// Which sheets the bridge trims back to its contacts.
    public enum TrimWalls: String, Codable, Hashable, Sendable {
        case none
        case both
        case short
        case long
    }

    public var first: FeatureID
    public var second: FeatureID
    public var width: CADExpression
    public var tension: Double
    public var shape: Shape
    public var trimWalls: TrimWalls
    public var reversesSense: Bool

    public init(first: FeatureID, second: FeatureID, width: CADExpression, tension: Double = 1, shape: Shape = .curvature,
                trimWalls: TrimWalls = .none, reversesSense: Bool = false) {
        self.first = first
        self.second = second
        self.width = width
        self.tension = tension
        self.shape = shape
        self.trimWalls = trimWalls
        self.reversesSense = reversesSense
    }

    private enum CodingKeys: String, CodingKey {
        case first, second, width, tension, shape, trimWalls, reversesSense
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try container.validateOnlyExpectedKeys([.first, .second, .width, .tension, .shape, .trimWalls, .reversesSense], in: decoder)
        first = try container.decode(FeatureID.self, forKey: .first)
        second = try container.decode(FeatureID.self, forKey: .second)
        width = try container.decode(CADExpression.self, forKey: .width)
        tension = try container.decode(Double.self, forKey: .tension)
        shape = try container.decode(Shape.self, forKey: .shape)
        trimWalls = try container.decode(TrimWalls.self, forKey: .trimWalls)
        reversesSense = try container.decodeIfPresent(Bool.self, forKey: .reversesSense) ?? false
        try validate()
    }

    public func encode(to encoder: Encoder) throws {
        try validate()
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(first, forKey: .first)
        try container.encode(second, forKey: .second)
        try container.encode(width, forKey: .width)
        try container.encode(tension, forKey: .tension)
        try container.encode(shape, forKey: .shape)
        try container.encode(trimWalls, forKey: .trimWalls)
        if reversesSense { try container.encode(true, forKey: .reversesSense) }
    }

    public func validate() throws {
        guard first != second else {
            throw FeatureEvaluationError.invalidGraph("A Bridge Surface joins two different sheets.")
        }
        guard tension.isFinite, tension > 0, tension <= 1.5 else {
            throw FeatureEvaluationError.invalidGraph("A Bridge Surface's tension lies in (0, 1.5].")
        }
        try width.validateLiteralQuantities()
    }

    /// The features the bridge consumes: its two sheets.
    public var inputs: [FeatureInput] {
        [FeatureInput(featureID: first, role: .sheet), FeatureInput(featureID: second, role: .sheet)]
    }

    public var expressions: [CADExpression] { [width] }
}
