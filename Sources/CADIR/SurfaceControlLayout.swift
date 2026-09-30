import CADCore


/// The control structure a surface is refitted to: its degree and number of spans along U and V
/// (Rebuild Face's explicit method, Align Surface's Degree and Spans).
public struct SurfaceControlLayout: Codable, Hashable, Sendable {
    public static let degrees = 1...9
    public static let spans = 1...128

    public var uDegree: Int
    public var vDegree: Int
    public var uSpans: Int
    public var vSpans: Int

    public init(uDegree: Int, vDegree: Int, uSpans: Int, vSpans: Int) {
        self.uDegree = uDegree
        self.vDegree = vDegree
        self.uSpans = uSpans
        self.vSpans = vSpans
    }

    public func validate() throws {
        guard Self.degrees.contains(uDegree), Self.degrees.contains(vDegree) else {
            throw FeatureEvaluationError.invalidGraph("A surface layout's degrees run from 1 to 9.")
        }
        guard Self.spans.contains(uSpans), Self.spans.contains(vSpans) else {
            throw FeatureEvaluationError.invalidGraph("A surface layout's spans run from 1 to 128.")
        }
    }

    private enum CodingKeys: String, CodingKey {
        case uDegree, vDegree, uSpans, vSpans
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try container.validateOnlyExpectedKeys([.uDegree, .vDegree, .uSpans, .vSpans], in: decoder)
        uDegree = try container.decode(Int.self, forKey: .uDegree)
        vDegree = try container.decode(Int.self, forKey: .vDegree)
        uSpans = try container.decode(Int.self, forKey: .uSpans)
        vSpans = try container.decode(Int.self, forKey: .vSpans)
        try validate()
    }

    public func encode(to encoder: Encoder) throws {
        try validate()
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(uDegree, forKey: .uDegree)
        try container.encode(vDegree, forKey: .vDegree)
        try container.encode(uSpans, forKey: .uSpans)
        try container.encode(vSpans, forKey: .vSpans)
    }
}
