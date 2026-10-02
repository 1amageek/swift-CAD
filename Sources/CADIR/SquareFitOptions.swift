import CADCore

/// How a Square's sheet is fitted to its frame: the least Degree and Spans of its control net in
/// each direction, the Flatness blending its thin plate (1) with membrane tautness, the Weight of
/// its loose terms (Free sides, boundary flow) against that fairness, and the Boundary flow its
/// cross derivatives follow along sides without a face.
public struct SquareFitOptions: Codable, Hashable, Sendable {
    /// The cross flow along a side without a face: none (`natural`), perpendicular to the side
    /// (`normal`), perpendicular within the frame's mean plane (`next`), or blending the
    /// neighbouring sides' derivatives at its corners (`adjacent`).
    public enum BoundaryFlow: String, Codable, Hashable, Sendable, CaseIterable {
        case natural
        case normal
        case next
        case adjacent
    }

    public var uDegree: Int
    public var vDegree: Int
    public var uSpans: Int
    public var vSpans: Int
    public var flatness: Double
    public var weight: Double
    public var boundaryFlow: BoundaryFlow

    public static let maximumDegree = 11
    public static let maximumSpans = 32

    public init(uDegree: Int = 3, vDegree: Int = 3, uSpans: Int = 3, vSpans: Int = 3,
                flatness: Double = 1, weight: Double = 1, boundaryFlow: BoundaryFlow = .adjacent) {
        self.uDegree = uDegree
        self.vDegree = vDegree
        self.uSpans = uSpans
        self.vSpans = vSpans
        self.flatness = flatness
        self.weight = weight
        self.boundaryFlow = boundaryFlow
    }

    public func validate() throws {
        guard (1...Self.maximumDegree).contains(uDegree), (1...Self.maximumDegree).contains(vDegree) else {
            throw FeatureEvaluationError.invalidGraph("A Square's degree lies between 1 and \(Self.maximumDegree).")
        }
        guard (1...Self.maximumSpans).contains(uSpans), (1...Self.maximumSpans).contains(vSpans) else {
            throw FeatureEvaluationError.invalidGraph("A Square's spans lie between 1 and \(Self.maximumSpans).")
        }
        guard flatness.isFinite, flatness >= 0, flatness <= 1 else {
            throw FeatureEvaluationError.invalidGraph("A Square's flatness lies in [0, 1].")
        }
        guard weight.isFinite, weight > 0 else {
            throw FeatureEvaluationError.invalidGraph("A Square's weight is finite and positive.")
        }
    }

    private enum CodingKeys: String, CodingKey {
        case uDegree, vDegree, uSpans, vSpans, flatness, weight, boundaryFlow
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try container.validateOnlyExpectedKeys([.uDegree, .vDegree, .uSpans, .vSpans, .flatness, .weight, .boundaryFlow], in: decoder)
        uDegree = try container.decode(Int.self, forKey: .uDegree)
        vDegree = try container.decode(Int.self, forKey: .vDegree)
        uSpans = try container.decode(Int.self, forKey: .uSpans)
        vSpans = try container.decode(Int.self, forKey: .vSpans)
        flatness = try container.decode(Double.self, forKey: .flatness)
        weight = try container.decode(Double.self, forKey: .weight)
        boundaryFlow = try container.decode(BoundaryFlow.self, forKey: .boundaryFlow)
        try validate()
    }

    public func encode(to encoder: Encoder) throws {
        try validate()
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(uDegree, forKey: .uDegree)
        try container.encode(vDegree, forKey: .vDegree)
        try container.encode(uSpans, forKey: .uSpans)
        try container.encode(vSpans, forKey: .vSpans)
        try container.encode(flatness, forKey: .flatness)
        try container.encode(weight, forKey: .weight)
        try container.encode(boundaryFlow, forKey: .boundaryFlow)
    }
}
