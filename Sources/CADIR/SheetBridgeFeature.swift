import CADCore

/// Bridge Surface: a blend between two sheets set back by `width` from where they meet — on their
/// extensions when they do not — shaped as a curvature-continuous (G2) quintic or a straight
/// chamfer across, its handles scaled by `tension`. `reversesFirstSense` and `reversesSecondSense`
/// each take the other side of the meeting line for that sheet when it crosses it, so the two
/// choose any of the four quadrants of two crossing sheets (Plasticity's two Sense toggles). Between sheets that are not two planes meeting (curved
/// sheets, sheets bending out of one plane, parallel planes), or when boundary edges are named, the
/// bridge spans between each sheet's named boundary edge — or the pair of boundary edges nearest
/// each other — continuous with both sheets there (decided 2026-10-02).
public struct SheetBridgeFeature: Codable, Hashable, Sendable {
    public enum Shape: String, Codable, Hashable, Sendable {
        case curvature
        case chamfer
    }

    /// Which sheets the bridge trims back to its contacts. Bridge Surface's Short and Long name the
    /// sheet reaching less or more far from where the sheets meet; authors resolve them into the
    /// first or second sheet (`SheetBridgeWallReach`), so the feature keeps which wall it consumes.
    public enum TrimWalls: String, Codable, Hashable, Sendable {
        case none
        case both
        case first
        case second
    }

    /// How far the bridge between two planes meeting runs along where they meet: the stretch both
    /// sheets share (Both), the shorter or the longer sheet's own stretch (Short, Long), or both
    /// sheets' stretches together run on by the width at each end, the bridge left untrimmed (None).
    public enum Extent: String, Codable, Hashable, Sendable {
        case both
        case short
        case long
        case none
    }

    public var first: FeatureID
    public var second: FeatureID
    public var width: CADExpression
    public var tension: Double
    public var shape: Shape
    public var trimWalls: TrimWalls
    public var extent: Extent
    public var reversesFirstSense: Bool
    public var reversesSecondSense: Bool
    /// The boundary edges of the first and second sheet the bridge spans between; nil for the
    /// meeting line's bridge between two planes, or the nearest boundary edges otherwise.
    public var edges: (first: StableSubshapeReference, second: StableSubshapeReference)?
    /// Beside a curved sheet, the angle (radians) and the curvature (1/length) a bridge between
    /// boundary edges may stray from the sheet's, as a Loft's continuity does; nil beside planes.
    public var angularAllowance: Double?
    public var curvatureAllowance: Double?

    public init(first: FeatureID, second: FeatureID, width: CADExpression, tension: Double = 1, shape: Shape = .curvature,
                trimWalls: TrimWalls = .none, extent: Extent = .both, reversesFirstSense: Bool = false, reversesSecondSense: Bool = false,
                edges: (first: StableSubshapeReference, second: StableSubshapeReference)? = nil,
                angularAllowance: Double? = nil, curvatureAllowance: Double? = nil) {
        self.edges = edges
        self.angularAllowance = angularAllowance
        self.curvatureAllowance = curvatureAllowance
        self.first = first
        self.second = second
        self.width = width
        self.tension = tension
        self.shape = shape
        self.trimWalls = trimWalls
        self.extent = extent
        self.reversesFirstSense = reversesFirstSense
        self.reversesSecondSense = reversesSecondSense
    }

    private enum CodingKeys: String, CodingKey {
        case first, second, width, tension, shape, trimWalls, extent, reversesFirstSense, reversesSecondSense, firstEdge, secondEdge, angularAllowance, curvatureAllowance
    }

    public static func == (lhs: SheetBridgeFeature, rhs: SheetBridgeFeature) -> Bool {
        lhs.first == rhs.first && lhs.second == rhs.second && lhs.width == rhs.width && lhs.tension == rhs.tension
            && lhs.shape == rhs.shape && lhs.trimWalls == rhs.trimWalls && lhs.extent == rhs.extent
            && lhs.reversesFirstSense == rhs.reversesFirstSense && lhs.reversesSecondSense == rhs.reversesSecondSense
            && lhs.edges?.first == rhs.edges?.first && lhs.edges?.second == rhs.edges?.second
            && lhs.angularAllowance == rhs.angularAllowance && lhs.curvatureAllowance == rhs.curvatureAllowance
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(first)
        hasher.combine(second)
        hasher.combine(width)
        hasher.combine(tension)
        hasher.combine(shape)
        hasher.combine(trimWalls)
        hasher.combine(extent)
        hasher.combine(reversesFirstSense)
        hasher.combine(reversesSecondSense)
        hasher.combine(edges?.first)
        hasher.combine(edges?.second)
        hasher.combine(angularAllowance)
        hasher.combine(curvatureAllowance)
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try container.validateOnlyExpectedKeys([.first, .second, .width, .tension, .shape, .trimWalls, .extent, .reversesFirstSense, .reversesSecondSense, .firstEdge, .secondEdge, .angularAllowance, .curvatureAllowance], in: decoder)
        first = try container.decode(FeatureID.self, forKey: .first)
        second = try container.decode(FeatureID.self, forKey: .second)
        width = try container.decode(CADExpression.self, forKey: .width)
        tension = try container.decode(Double.self, forKey: .tension)
        shape = try container.decode(Shape.self, forKey: .shape)
        trimWalls = try container.decode(TrimWalls.self, forKey: .trimWalls)
        extent = try container.decodeIfPresent(Extent.self, forKey: .extent) ?? .both
        reversesFirstSense = try container.decodeIfPresent(Bool.self, forKey: .reversesFirstSense) ?? false
        reversesSecondSense = try container.decodeIfPresent(Bool.self, forKey: .reversesSecondSense) ?? false
        angularAllowance = try container.decodeIfPresent(Double.self, forKey: .angularAllowance)
        curvatureAllowance = try container.decodeIfPresent(Double.self, forKey: .curvatureAllowance)
        let firstEdge = try container.decodeIfPresent(StableSubshapeReference.self, forKey: .firstEdge)
        let secondEdge = try container.decodeIfPresent(StableSubshapeReference.self, forKey: .secondEdge)
        switch (firstEdge, secondEdge) {
        case let (a?, b?): edges = (a, b)
        case (nil, nil): edges = nil
        default: throw FeatureEvaluationError.invalidGraph("A Bridge Surface names a boundary edge of both sheets or of neither.")
        }
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
        if extent != .both { try container.encode(extent, forKey: .extent) }
        if reversesFirstSense { try container.encode(true, forKey: .reversesFirstSense) }
        if reversesSecondSense { try container.encode(true, forKey: .reversesSecondSense) }
        try container.encodeIfPresent(edges?.first, forKey: .firstEdge)
        try container.encodeIfPresent(edges?.second, forKey: .secondEdge)
        try container.encodeIfPresent(angularAllowance, forKey: .angularAllowance)
        try container.encodeIfPresent(curvatureAllowance, forKey: .curvatureAllowance)
    }

    public func validate() throws {
        guard first != second else {
            throw FeatureEvaluationError.invalidGraph("A Bridge Surface joins two different sheets.")
        }
        guard tension.isFinite, tension > 0, tension <= 1.5 else {
            throw FeatureEvaluationError.invalidGraph("A Bridge Surface's tension lies in (0, 1.5].")
        }
        try width.validateLiteralQuantities()
        if let angularAllowance, !(angularAllowance.isFinite && angularAllowance > 0 && angularAllowance < Double.pi / 2) {
            throw FeatureEvaluationError.invalidGraph("A Bridge Surface's angle allowance lies strictly between 0 and a right angle.")
        }
        if let curvatureAllowance, !(curvatureAllowance.isFinite && curvatureAllowance > 0) {
            throw FeatureEvaluationError.invalidGraph("A Bridge Surface's curvature allowance is positive.")
        }
        try edges?.first.validate()
        try edges?.second.validate()
    }

    /// The features the bridge consumes: its two sheets.
    public var inputs: [FeatureInput] {
        [FeatureInput(featureID: first, role: .sheet), FeatureInput(featureID: second, role: .sheet)]
    }

    public var expressions: [CADExpression] { [width] }
}
