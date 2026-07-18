import CADCore
import CADTopology

public enum SubshapeGeometrySignature: Codable, Hashable, Sendable {
    public enum CurveKind: String, Codable, Hashable, Sendable {
        case line
        case circle
        case arc
        case ellipse
        case bSpline
    }

    public enum SurfaceKind: String, Codable, Hashable, Sendable {
        case plane
        case cylinder
        case cone
        case sphere
        case torus
        case bSpline
    }

    case body(boundaryPoints: [Point3D])
    case vertex(point: Point3D)
    case edge(kind: CurveKind, start: Point3D, midpoint: Point3D, end: Point3D)
    case face(kind: SurfaceKind, boundaryPoints: [Point3D])

    public func validate() throws {
        switch self {
        case let .body(boundaryPoints):
            try validateBoundaryPoints(boundaryPoints, minimumCount: 3)
        case let .vertex(point):
            try point.validate()
        case let .edge(_, start, midpoint, end):
            try start.validate()
            try midpoint.validate()
            try end.validate()
            guard start != end else {
                throw KernelError(
                    phase: .validation,
                    code: .invalidInput,
                    tolerance: nil,
                    message: "Edge geometry signature requires distinct endpoints."
                )
            }
        case let .face(_, boundaryPoints):
            try validateBoundaryPoints(boundaryPoints, minimumCount: 1)
        }
    }

    private func validateBoundaryPoints(
        _ points: [Point3D],
        minimumCount: Int
    ) throws {
        guard points.count >= minimumCount,
              Set(points).count == points.count,
              points == points.sorted(by: Self.pointOrder) else {
            throw KernelError(
                phase: .validation,
                code: .invalidInput,
                tolerance: nil,
                message: "Geometry signature boundary points must be unique and canonically ordered."
            )
        }
        for point in points {
            try point.validate()
        }
    }

    private static func pointOrder(_ lhs: Point3D, _ rhs: Point3D) -> Bool {
        if lhs.x != rhs.x { return lhs.x < rhs.x }
        if lhs.y != rhs.y { return lhs.y < rhs.y }
        return lhs.z < rhs.z
    }

    private enum CodingKeys: String, CodingKey {
        case kind
        case curveKind
        case surfaceKind
        case point
        case start
        case midpoint
        case end
        case boundaryPoints
    }

    private enum Kind: String, Codable {
        case body
        case vertex
        case edge
        case face
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(Kind.self, forKey: .kind) {
        case .body:
            try container.validateOnlyExpectedKeys([.kind, .boundaryPoints], in: decoder)
            self = .body(boundaryPoints: try container.decode([Point3D].self, forKey: .boundaryPoints))
        case .vertex:
            try container.validateOnlyExpectedKeys([.kind, .point], in: decoder)
            self = .vertex(point: try container.decode(Point3D.self, forKey: .point))
        case .edge:
            try container.validateOnlyExpectedKeys(
                [.kind, .curveKind, .start, .midpoint, .end],
                in: decoder
            )
            self = .edge(
                kind: try container.decode(CurveKind.self, forKey: .curveKind),
                start: try container.decode(Point3D.self, forKey: .start),
                midpoint: try container.decode(Point3D.self, forKey: .midpoint),
                end: try container.decode(Point3D.self, forKey: .end)
            )
        case .face:
            try container.validateOnlyExpectedKeys([.kind, .surfaceKind, .boundaryPoints], in: decoder)
            self = .face(
                kind: try container.decode(SurfaceKind.self, forKey: .surfaceKind),
                boundaryPoints: try container.decode([Point3D].self, forKey: .boundaryPoints)
            )
        }
        try validate()
    }

    public func encode(to encoder: Encoder) throws {
        try validate()
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case let .body(boundaryPoints):
            try container.encode(Kind.body, forKey: .kind)
            try container.encode(boundaryPoints, forKey: .boundaryPoints)
        case let .vertex(point):
            try container.encode(Kind.vertex, forKey: .kind)
            try container.encode(point, forKey: .point)
        case let .edge(kind, start, midpoint, end):
            try container.encode(Kind.edge, forKey: .kind)
            try container.encode(kind, forKey: .curveKind)
            try container.encode(start, forKey: .start)
            try container.encode(midpoint, forKey: .midpoint)
            try container.encode(end, forKey: .end)
        case let .face(kind, boundaryPoints):
            try container.encode(Kind.face, forKey: .kind)
            try container.encode(kind, forKey: .surfaceKind)
            try container.encode(boundaryPoints, forKey: .boundaryPoints)
        }
    }
}
