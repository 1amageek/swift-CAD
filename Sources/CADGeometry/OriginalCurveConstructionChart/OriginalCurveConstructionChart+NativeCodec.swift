#if !hasFeature(Embedded)
import CADCore

extension OriginalCurveConstructionChart: Codable {
    private enum Keys: String, CodingKey { case kind, traversal, parameterSource }
    private enum Kind: String, Codable { case traversal, parameterLaw }
    public init(from decoder: Decoder) throws {
        try OriginalAffineWordDecodingContext.validateSourceNesting(from: decoder)
        let c = try decoder.container(keyedBy: Keys.self)
        switch try c.decode(Kind.self, forKey: .kind) {
        case .traversal:
            try c.validateOnlyExpectedKeys([.kind, .traversal], in: decoder)
            self = .traversal(try c.decode(OriginalCurveRootSpan3D.self, forKey: .traversal))
        case .parameterLaw:
            try c.validateOnlyExpectedKeys([.kind, .parameterSource], in: decoder)
            self = .parameterLaw(try c.decode(OriginalCurveConstructionParameterSource.self, forKey: .parameterSource))
        }
    }
    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: Keys.self)
        switch self {
        case .traversal(let value):
            try c.encode(Kind.traversal, forKey: .kind); try c.encode(value, forKey: .traversal)
        case .parameterLaw(let value):
            try c.encode(Kind.parameterLaw, forKey: .kind); try c.encode(value, forKey: .parameterSource)
        }
    }
}
#endif
