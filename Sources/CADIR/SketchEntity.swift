import CADCore

public struct SketchPoint: Codable, Sendable, Hashable {
    public var x: CADExpression
    public var y: CADExpression

    public init(x: CADExpression, y: CADExpression) {
        self.x = x
        self.y = y
    }
}

public struct SketchLine: Codable, Sendable, Hashable {
    public var start: SketchPoint
    public var end: SketchPoint

    public init(start: SketchPoint, end: SketchPoint) {
        self.start = start
        self.end = end
    }
}

public struct SketchCircle: Codable, Sendable, Hashable {
    public var center: SketchPoint
    public var radius: CADExpression

    public init(center: SketchPoint, radius: CADExpression) {
        self.center = center
        self.radius = radius
    }
}

public struct SketchArc: Codable, Sendable, Hashable {
    public var center: SketchPoint
    public var radius: CADExpression
    public var startAngle: CADExpression
    public var endAngle: CADExpression

    public init(
        center: SketchPoint,
        radius: CADExpression,
        startAngle: CADExpression,
        endAngle: CADExpression
    ) {
        self.center = center
        self.radius = radius
        self.startAngle = startAngle
        self.endAngle = endAngle
    }
}

public struct SketchSpline: Codable, Sendable, Hashable {
    public var controlPoints: [SketchPoint]
    public var isClosed: Bool

    public init(controlPoints: [SketchPoint], isClosed: Bool = false) {
        self.controlPoints = controlPoints
        self.isClosed = isClosed
    }
}

public enum SketchEntity: Codable, Sendable, Hashable {
    case point(SketchPoint)
    case line(SketchLine)
    case circle(SketchCircle)
    case arc(SketchArc)
    case spline(SketchSpline)

    private enum CodingKeys: String, CodingKey {
        case kind
        case point
        case line
        case circle
        case arc
        case spline
    }

    private enum Kind: String, Codable {
        case point
        case line
        case circle
        case arc
        case spline
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try container.decode(Kind.self, forKey: .kind)
        switch kind {
        case .point:
            try container.validateOnlyExpectedKeys([.kind, .point], in: decoder)
            self = .point(try container.decode(SketchPoint.self, forKey: .point))
        case .line:
            try container.validateOnlyExpectedKeys([.kind, .line], in: decoder)
            self = .line(try container.decode(SketchLine.self, forKey: .line))
        case .circle:
            try container.validateOnlyExpectedKeys([.kind, .circle], in: decoder)
            self = .circle(try container.decode(SketchCircle.self, forKey: .circle))
        case .arc:
            try container.validateOnlyExpectedKeys([.kind, .arc], in: decoder)
            self = .arc(try container.decode(SketchArc.self, forKey: .arc))
        case .spline:
            try container.validateOnlyExpectedKeys([.kind, .spline], in: decoder)
            self = .spline(try container.decode(SketchSpline.self, forKey: .spline))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case let .point(point):
            try container.encode(Kind.point, forKey: .kind)
            try container.encode(point, forKey: .point)
        case let .line(line):
            try container.encode(Kind.line, forKey: .kind)
            try container.encode(line, forKey: .line)
        case let .circle(circle):
            try container.encode(Kind.circle, forKey: .kind)
            try container.encode(circle, forKey: .circle)
        case let .arc(arc):
            try container.encode(Kind.arc, forKey: .kind)
            try container.encode(arc, forKey: .arc)
        case let .spline(spline):
            try container.encode(Kind.spline, forKey: .kind)
            try container.encode(spline, forKey: .spline)
        }
    }
}
