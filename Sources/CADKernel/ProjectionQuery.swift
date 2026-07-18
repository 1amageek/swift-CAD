import CADCore
import CADIR

public struct ProjectionQuery: Codable, Sendable, Hashable {
    public enum Target: Codable, Sendable, Hashable {
        case curve(CurveOutputReference)
        case edge(EdgeReference)
        case surface(SurfaceReference)

        private enum CodingKeys: String, CodingKey {
            case kind
            case curve
            case edge
            case surface
        }

        private enum Kind: String, Codable {
            case curve
            case edge
            case surface
        }

        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            let kind = try container.decode(Kind.self, forKey: .kind)
            switch kind {
            case .curve:
                try container.validateOnlyExpectedKeys([.kind, .curve], in: decoder)
                self = .curve(try container.decode(CurveOutputReference.self, forKey: .curve))
            case .edge:
                try container.validateOnlyExpectedKeys([.kind, .edge], in: decoder)
                self = .edge(try container.decode(EdgeReference.self, forKey: .edge))
            case .surface:
                try container.validateOnlyExpectedKeys([.kind, .surface], in: decoder)
                self = .surface(try container.decode(SurfaceReference.self, forKey: .surface))
            }
        }

        public func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            switch self {
            case let .curve(reference):
                try container.encode(Kind.curve, forKey: .kind)
                try container.encode(reference, forKey: .curve)
            case let .edge(reference):
                try container.encode(Kind.edge, forKey: .kind)
                try container.encode(reference, forKey: .edge)
            case let .surface(reference):
                try container.encode(Kind.surface, forKey: .kind)
                try container.encode(reference, forKey: .surface)
            }
        }

        fileprivate func validate() throws {
            switch self {
            case let .curve(reference):
                try reference.validate()
            case let .edge(reference):
                try reference.validate()
            case let .surface(reference):
                try reference.validate()
            }
        }
    }

    public enum DirectionRange: String, Codable, Sendable, Hashable {
        case line
        case ray
    }

    public enum Mode: Codable, Sendable, Hashable {
        case closest
        case directional(direction: Vector3D, range: DirectionRange)

        private enum CodingKeys: String, CodingKey {
            case kind
            case direction
            case range
        }

        private enum Kind: String, Codable {
            case closest
            case directional
        }

        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            let kind = try container.decode(Kind.self, forKey: .kind)
            switch kind {
            case .closest:
                try container.validateOnlyExpectedKeys([.kind], in: decoder)
                self = .closest
            case .directional:
                try container.validateOnlyExpectedKeys([.kind, .direction, .range], in: decoder)
                self = .directional(
                    direction: try container.decode(Vector3D.self, forKey: .direction),
                    range: try container.decode(DirectionRange.self, forKey: .range)
                )
            }
        }

        public func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            switch self {
            case .closest:
                try container.encode(Kind.closest, forKey: .kind)
            case let .directional(direction, range):
                try container.encode(Kind.directional, forKey: .kind)
                try container.encode(direction, forKey: .direction)
                try container.encode(range, forKey: .range)
            }
        }

        fileprivate func validate(tolerance: ModelingTolerance) throws {
            guard case let .directional(direction, _) = self else {
                return
            }
            try direction.validate()
            guard direction.length > tolerance.distance else {
                throw GeometryError.invalidVectorLength(direction.length)
            }
        }
    }

    public var point: Point3D
    public var target: Target
    public var mode: Mode
    public var sampleCount: Int
    public var maximumIterations: Int

    private enum CodingKeys: String, CodingKey {
        case point
        case target
        case mode
        case sampleCount
        case maximumIterations
    }

    public init(
        point: Point3D,
        target: Target,
        mode: Mode = .closest,
        sampleCount: Int = 9,
        maximumIterations: Int = 32
    ) {
        self.point = point
        self.target = target
        self.mode = mode
        self.sampleCount = sampleCount
        self.maximumIterations = maximumIterations
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try container.validateOnlyExpectedKeys(
            [.point, .target, .mode, .sampleCount, .maximumIterations],
            in: decoder
        )
        point = try container.decode(Point3D.self, forKey: .point)
        target = try container.decode(Target.self, forKey: .target)
        mode = try container.decode(Mode.self, forKey: .mode)
        sampleCount = try container.decode(Int.self, forKey: .sampleCount)
        maximumIterations = try container.decode(Int.self, forKey: .maximumIterations)
    }

    public func validate(tolerance: ModelingTolerance) throws {
        try tolerance.validate()
        try point.validate()
        try target.validate()
        try mode.validate(tolerance: tolerance)
        guard sampleCount >= 2 else {
            throw FeatureEvaluationError.invalidGraph(
                "Projection query sample count must be at least two."
            )
        }
        guard maximumIterations >= 0 else {
            throw FeatureEvaluationError.invalidGraph(
                "Projection query iteration count must not be negative."
            )
        }
    }
}
