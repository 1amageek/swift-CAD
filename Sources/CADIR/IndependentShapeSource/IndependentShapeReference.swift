import CADCore

public enum IndependentShapeReference: Hashable, Sendable, Comparable {
    case body(SubshapeID)
    case item(IndependentShapeItemID)
    case geometricSet(IndependentShapeSetID)
    case frame(IndependentShapeFrameID)
    case representation(IndependentShapeRepresentationID)
    case group(IndependentShapeGroupID)
    case instance(IndependentShapeInstanceID)

    #if !hasFeature(Embedded)

    private enum CodingKeys: String, CodingKey { case kind, id }
    #endif

    #if !hasFeature(Embedded)
    private enum Kind: String, Codable { case body, item, geometricSet, frame, representation, group, instance }
    #endif

    #if !hasFeature(Embedded)
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        try c.validateOnlyExpectedKeys([.kind, .id], in: decoder)
        switch try c.decode(Kind.self, forKey: .kind) {
        case .body: self = .body(try c.decode(SubshapeID.self, forKey: .id))
        case .item: self = .item(try c.decode(IndependentShapeItemID.self, forKey: .id))
        case .geometricSet: self = .geometricSet(try c.decode(IndependentShapeSetID.self, forKey: .id))
        case .frame: self = .frame(try c.decode(IndependentShapeFrameID.self, forKey: .id))
        case .representation: self = .representation(try c.decode(IndependentShapeRepresentationID.self, forKey: .id))
        case .group: self = .group(try c.decode(IndependentShapeGroupID.self, forKey: .id))
        case .instance: self = .instance(try c.decode(IndependentShapeInstanceID.self, forKey: .id))
        }
    }
    #endif

    #if !hasFeature(Embedded)
    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .body(let id): try c.encode(Kind.body, forKey: .kind); try c.encode(id, forKey: .id)
        case .item(let id): try c.encode(Kind.item, forKey: .kind); try c.encode(id, forKey: .id)
        case .geometricSet(let id): try c.encode(Kind.geometricSet, forKey: .kind); try c.encode(id, forKey: .id)
        case .frame(let id): try c.encode(Kind.frame, forKey: .kind); try c.encode(id, forKey: .id)
        case .representation(let id): try c.encode(Kind.representation, forKey: .kind); try c.encode(id, forKey: .id)
        case .group(let id): try c.encode(Kind.group, forKey: .kind); try c.encode(id, forKey: .id)
        case .instance(let id): try c.encode(Kind.instance, forKey: .kind); try c.encode(id, forKey: .id)
        }
    }
    #endif
    public static func < (lhs: Self, rhs: Self) -> Bool {
        switch (lhs, rhs) {
        case (.body(let a), .body(let b)): return a < b
        case (.item(let a), .item(let b)): return a < b
        case (.geometricSet(let a), .geometricSet(let b)): return a < b
        case (.frame(let a), .frame(let b)): return a < b
        case (.representation(let a), .representation(let b)): return a < b
        case (.group(let a), .group(let b)): return a < b
        case (.instance(let a), .instance(let b)): return a < b
        default: return lhs.rank < rhs.rank
        }
    }
    private var rank: Int {
        switch self { case .body: 6; case .item: 0; case .geometricSet: 1; case .frame: 2; case .representation: 3; case .group: 4; case .instance: 5 }
    }
}

#if !hasFeature(Embedded)
extension IndependentShapeReference: Codable {}
#endif
