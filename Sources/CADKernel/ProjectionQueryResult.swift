import CADCore

public enum ProjectionQueryResult: Codable, Sendable {
    case curveClosest(CurveProjectionResult)
    case curveDirectional(CurveDirectionalProjectionResult)
    case edgeClosest(EdgeProjectionResult)
    case edgeDirectional(EdgeDirectionalProjectionResult)
    case surfaceClosest(SurfaceProjectionResult)
    case surfaceDirectional(SurfaceDirectionalProjectionResult)

    private enum CodingKeys: String, CodingKey {
        case kind
        case curveClosest
        case curveDirectional
        case edgeClosest
        case edgeDirectional
        case surfaceClosest
        case surfaceDirectional
    }

    private enum Kind: String, Codable {
        case curveClosest
        case curveDirectional
        case edgeClosest
        case edgeDirectional
        case surfaceClosest
        case surfaceDirectional
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(Kind.self, forKey: .kind) {
        case .curveClosest:
            try container.validateOnlyExpectedKeys([.kind, .curveClosest], in: decoder)
            self = .curveClosest(try container.decode(
                CurveProjectionResult.self,
                forKey: .curveClosest
            ))
        case .curveDirectional:
            try container.validateOnlyExpectedKeys([.kind, .curveDirectional], in: decoder)
            self = .curveDirectional(try container.decode(
                CurveDirectionalProjectionResult.self,
                forKey: .curveDirectional
            ))
        case .edgeClosest:
            try container.validateOnlyExpectedKeys([.kind, .edgeClosest], in: decoder)
            self = .edgeClosest(try container.decode(
                EdgeProjectionResult.self,
                forKey: .edgeClosest
            ))
        case .edgeDirectional:
            try container.validateOnlyExpectedKeys([.kind, .edgeDirectional], in: decoder)
            self = .edgeDirectional(try container.decode(
                EdgeDirectionalProjectionResult.self,
                forKey: .edgeDirectional
            ))
        case .surfaceClosest:
            try container.validateOnlyExpectedKeys([.kind, .surfaceClosest], in: decoder)
            self = .surfaceClosest(try container.decode(
                SurfaceProjectionResult.self,
                forKey: .surfaceClosest
            ))
        case .surfaceDirectional:
            try container.validateOnlyExpectedKeys([.kind, .surfaceDirectional], in: decoder)
            self = .surfaceDirectional(try container.decode(
                SurfaceDirectionalProjectionResult.self,
                forKey: .surfaceDirectional
            ))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case let .curveClosest(result):
            try container.encode(Kind.curveClosest, forKey: .kind)
            try container.encode(result, forKey: .curveClosest)
        case let .curveDirectional(result):
            try container.encode(Kind.curveDirectional, forKey: .kind)
            try container.encode(result, forKey: .curveDirectional)
        case let .edgeClosest(result):
            try container.encode(Kind.edgeClosest, forKey: .kind)
            try container.encode(result, forKey: .edgeClosest)
        case let .edgeDirectional(result):
            try container.encode(Kind.edgeDirectional, forKey: .kind)
            try container.encode(result, forKey: .edgeDirectional)
        case let .surfaceClosest(result):
            try container.encode(Kind.surfaceClosest, forKey: .kind)
            try container.encode(result, forKey: .surfaceClosest)
        case let .surfaceDirectional(result):
            try container.encode(Kind.surfaceDirectional, forKey: .kind)
            try container.encode(result, forKey: .surfaceDirectional)
        }
    }
}
