import CADCore

public enum SketchConstraint: Codable, Sendable, Hashable {
    case coincident(SketchReference, SketchReference)
    case horizontal(SketchEntityID)
    case vertical(SketchEntityID)
    case parallel(SketchEntityID, SketchEntityID)
    case perpendicular(SketchEntityID, SketchEntityID)
    case equalLength(SketchEntityID, SketchEntityID)
    case tangent(SketchEntityID, SketchEntityID)
    case concentric(SketchEntityID, SketchEntityID)
    case equalRadius(SketchEntityID, SketchEntityID)
    case smoothSplineControlPoint(entity: SketchEntityID, index: Int)
    case splineEndpointTangent(spline: SketchEntityID, endpoint: SketchSplineEndpoint, line: SketchEntityID)
    case tangentSplineEndpoints(first: SketchSplineEndpointReference, second: SketchSplineEndpointReference)
    case smoothSplineEndpoints(first: SketchSplineEndpointReference, second: SketchSplineEndpointReference)
    case fixed(SketchReference)

    private enum CodingKeys: String, CodingKey {
        case kind
        case first
        case second
        case entityID
        case controlPointIndex
        case endpoint
        case splineID
        case lineID
    }

    private enum Kind: String, Codable {
        case coincident
        case horizontal
        case vertical
        case parallel
        case perpendicular
        case equalLength
        case tangent
        case concentric
        case equalRadius
        case smoothSplineControlPoint
        case splineEndpointTangent
        case tangentSplineEndpoints
        case smoothSplineEndpoints
        case fixed
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try container.decode(Kind.self, forKey: .kind)
        switch kind {
        case .coincident:
            try container.validateOnlyExpectedKeys([.kind, .first, .second], in: decoder)
            self = .coincident(
                try container.decode(SketchReference.self, forKey: .first),
                try container.decode(SketchReference.self, forKey: .second)
            )
        case .horizontal:
            try container.validateOnlyExpectedKeys([.kind, .entityID], in: decoder)
            self = .horizontal(try container.decode(SketchEntityID.self, forKey: .entityID))
        case .vertical:
            try container.validateOnlyExpectedKeys([.kind, .entityID], in: decoder)
            self = .vertical(try container.decode(SketchEntityID.self, forKey: .entityID))
        case .parallel:
            try container.validateOnlyExpectedKeys([.kind, .first, .second], in: decoder)
            self = .parallel(
                try container.decode(SketchEntityID.self, forKey: .first),
                try container.decode(SketchEntityID.self, forKey: .second)
            )
        case .perpendicular:
            try container.validateOnlyExpectedKeys([.kind, .first, .second], in: decoder)
            self = .perpendicular(
                try container.decode(SketchEntityID.self, forKey: .first),
                try container.decode(SketchEntityID.self, forKey: .second)
            )
        case .equalLength:
            try container.validateOnlyExpectedKeys([.kind, .first, .second], in: decoder)
            self = .equalLength(
                try container.decode(SketchEntityID.self, forKey: .first),
                try container.decode(SketchEntityID.self, forKey: .second)
            )
        case .tangent:
            try container.validateOnlyExpectedKeys([.kind, .first, .second], in: decoder)
            self = .tangent(
                try container.decode(SketchEntityID.self, forKey: .first),
                try container.decode(SketchEntityID.self, forKey: .second)
            )
        case .concentric:
            try container.validateOnlyExpectedKeys([.kind, .first, .second], in: decoder)
            self = .concentric(
                try container.decode(SketchEntityID.self, forKey: .first),
                try container.decode(SketchEntityID.self, forKey: .second)
            )
        case .equalRadius:
            try container.validateOnlyExpectedKeys([.kind, .first, .second], in: decoder)
            self = .equalRadius(
                try container.decode(SketchEntityID.self, forKey: .first),
                try container.decode(SketchEntityID.self, forKey: .second)
            )
        case .smoothSplineControlPoint:
            try container.validateOnlyExpectedKeys([.kind, .entityID, .controlPointIndex], in: decoder)
            self = .smoothSplineControlPoint(
                entity: try container.decode(SketchEntityID.self, forKey: .entityID),
                index: try container.decode(Int.self, forKey: .controlPointIndex)
            )
        case .splineEndpointTangent:
            try container.validateOnlyExpectedKeys([.kind, .splineID, .endpoint, .lineID], in: decoder)
            self = .splineEndpointTangent(
                spline: try container.decode(SketchEntityID.self, forKey: .splineID),
                endpoint: try container.decode(SketchSplineEndpoint.self, forKey: .endpoint),
                line: try container.decode(SketchEntityID.self, forKey: .lineID)
            )
        case .tangentSplineEndpoints:
            try container.validateOnlyExpectedKeys([.kind, .first, .second], in: decoder)
            self = .tangentSplineEndpoints(
                first: try container.decode(SketchSplineEndpointReference.self, forKey: .first),
                second: try container.decode(SketchSplineEndpointReference.self, forKey: .second)
            )
        case .smoothSplineEndpoints:
            try container.validateOnlyExpectedKeys([.kind, .first, .second], in: decoder)
            self = .smoothSplineEndpoints(
                first: try container.decode(SketchSplineEndpointReference.self, forKey: .first),
                second: try container.decode(SketchSplineEndpointReference.self, forKey: .second)
            )
        case .fixed:
            try container.validateOnlyExpectedKeys([.kind, .first], in: decoder)
            self = .fixed(try container.decode(SketchReference.self, forKey: .first))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case let .coincident(first, second):
            try container.encode(Kind.coincident, forKey: .kind)
            try container.encode(first, forKey: .first)
            try container.encode(second, forKey: .second)
        case let .horizontal(entityID):
            try container.encode(Kind.horizontal, forKey: .kind)
            try container.encode(entityID, forKey: .entityID)
        case let .vertical(entityID):
            try container.encode(Kind.vertical, forKey: .kind)
            try container.encode(entityID, forKey: .entityID)
        case let .parallel(first, second):
            try container.encode(Kind.parallel, forKey: .kind)
            try container.encode(first, forKey: .first)
            try container.encode(second, forKey: .second)
        case let .perpendicular(first, second):
            try container.encode(Kind.perpendicular, forKey: .kind)
            try container.encode(first, forKey: .first)
            try container.encode(second, forKey: .second)
        case let .equalLength(first, second):
            try container.encode(Kind.equalLength, forKey: .kind)
            try container.encode(first, forKey: .first)
            try container.encode(second, forKey: .second)
        case let .tangent(first, second):
            try container.encode(Kind.tangent, forKey: .kind)
            try container.encode(first, forKey: .first)
            try container.encode(second, forKey: .second)
        case let .concentric(first, second):
            try container.encode(Kind.concentric, forKey: .kind)
            try container.encode(first, forKey: .first)
            try container.encode(second, forKey: .second)
        case let .equalRadius(first, second):
            try container.encode(Kind.equalRadius, forKey: .kind)
            try container.encode(first, forKey: .first)
            try container.encode(second, forKey: .second)
        case let .smoothSplineControlPoint(entityID, index):
            try container.encode(Kind.smoothSplineControlPoint, forKey: .kind)
            try container.encode(entityID, forKey: .entityID)
            try container.encode(index, forKey: .controlPointIndex)
        case let .splineEndpointTangent(splineID, endpoint, lineID):
            try container.encode(Kind.splineEndpointTangent, forKey: .kind)
            try container.encode(splineID, forKey: .splineID)
            try container.encode(endpoint, forKey: .endpoint)
            try container.encode(lineID, forKey: .lineID)
        case let .tangentSplineEndpoints(first, second):
            try container.encode(Kind.tangentSplineEndpoints, forKey: .kind)
            try container.encode(first, forKey: .first)
            try container.encode(second, forKey: .second)
        case let .smoothSplineEndpoints(first, second):
            try container.encode(Kind.smoothSplineEndpoints, forKey: .kind)
            try container.encode(first, forKey: .first)
            try container.encode(second, forKey: .second)
        case let .fixed(reference):
            try container.encode(Kind.fixed, forKey: .kind)
            try container.encode(reference, forKey: .first)
        }
    }
}
