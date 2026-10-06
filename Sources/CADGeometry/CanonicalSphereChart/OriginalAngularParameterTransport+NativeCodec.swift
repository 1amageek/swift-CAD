#if !hasFeature(Embedded)
import CADCore
extension OriginalAngularParameterTransport: Codable {
    private enum Keys: String, CodingKey { case kind, gain, offset, start, end, additionalTurns }
    private enum Kind: String, Codable { case intrinsic, physicalRadians, physicalRadianArc }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: Keys.self)
        switch try c.decode(Kind.self, forKey: .kind) {
        case .intrinsic:
            try c.validateOnlyExpectedKeys([.kind], in: decoder); self = .intrinsic
        case .physicalRadianArc:
            try c.validateOnlyExpectedKeys([.kind, .start, .end, .additionalTurns], in: decoder)
            self = .physicalRadianArc(start: try c.decode(ExactRationalCoefficient.self, forKey: .start),
                end: try c.decode(ExactRationalCoefficient.self, forKey: .end),
                additionalTurns: try c.decode(Int.self, forKey: .additionalTurns))
        case .physicalRadians:
            try c.validateOnlyExpectedKeys([.kind, .gain, .offset], in: decoder)
            let gain = try c.decode(ExactRationalCoefficient.self, forKey: .gain)
            guard !gain.isZero else { throw GeometryConversionError.invalidInput("Original physical angle requires a nonzero gain.") }
            self = .physicalRadians(gain: gain, offset: try c.decode(ExactRationalCoefficient.self, forKey: .offset))
        }
    }
    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: Keys.self)
        switch self {
        case .intrinsic: try c.encode(Kind.intrinsic, forKey: .kind)
        case .physicalRadianArc(let start, let end, let turns):
            try c.encode(Kind.physicalRadianArc, forKey: .kind); try c.encode(start, forKey: .start)
            try c.encode(end, forKey: .end); try c.encode(turns, forKey: .additionalTurns)
        case .physicalRadians(let gain, let offset):
            try c.encode(Kind.physicalRadians, forKey: .kind); try c.encode(gain, forKey: .gain); try c.encode(offset, forKey: .offset)
        }
    }
}
#endif
