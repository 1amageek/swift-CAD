import Foundation

/// The persisted form of Extend Curve's Arc, Soft and Reflective shapes: what, besides the
/// curve's own Bezier control points and the length, fixes the new points' structure.
public enum BezierExtensionShape: Codable, Sendable, Hashable {
    /// The end's curvature held over `spanCount` cubic spans raised to the curve's degree.
    case arc(spanCount: Int)
    /// The end's curvature fading to zero over `spanCount` cubic spans raised to the curve's degree.
    case soft(spanCount: Int)
    /// The curve's last length, taken from its stored Bezier segments of `degree`, mirrored across
    /// the end's normal; with `coversCurve` the stored segments are the whole curve, so a length
    /// past it mirrors all of it.
    case reflective(degree: Int, coversCurve: Bool)

    private enum CodingKeys: String, CodingKey {
        case kind, spanCount, degree, coversCurve
    }

    private enum Kind: String, Codable {
        case arc, soft, reflective
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(Kind.self, forKey: .kind) {
        case .arc:
            try container.validateOnlyExpectedKeys([.kind, .spanCount], in: decoder)
            self = .arc(spanCount: try container.decode(Int.self, forKey: .spanCount))
        case .soft:
            try container.validateOnlyExpectedKeys([.kind, .spanCount], in: decoder)
            self = .soft(spanCount: try container.decode(Int.self, forKey: .spanCount))
        case .reflective:
            try container.validateOnlyExpectedKeys([.kind, .degree, .coversCurve], in: decoder)
            self = .reflective(
                degree: try container.decode(Int.self, forKey: .degree),
                coversCurve: try container.decode(Bool.self, forKey: .coversCurve)
            )
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case let .arc(spanCount):
            try container.encode(Kind.arc, forKey: .kind)
            try container.encode(spanCount, forKey: .spanCount)
        case let .soft(spanCount):
            try container.encode(Kind.soft, forKey: .kind)
            try container.encode(spanCount, forKey: .spanCount)
        case let .reflective(degree, coversCurve):
            try container.encode(Kind.reflective, forKey: .kind)
            try container.encode(degree, forKey: .degree)
            try container.encode(coversCurve, forKey: .coversCurve)
        }
    }
}

/// Evaluates Extend Curve's Arc, Soft and Reflective shapes from the curve's own Bezier control
/// points, so the persisted `bezierShapedExtension` expression follows the curve when its points
/// change. The structure — span count for Arc and Soft, stored segments for Reflective — is fixed
/// when the extension is made; an input the fixed structure cannot represent throws.
public struct BezierShapedExtension: Sendable {
    public let tolerance: ModelingTolerance

    public init(tolerance: ModelingTolerance) {
        self.tolerance = tolerance
    }

    /// How many new points the extension adds after the end, from its shape and the number of
    /// stored control points; throws for a form no extension has.
    public static func newPointCount(shape: BezierExtensionShape, controlPointCount: Int) throws -> Int {
        switch shape {
        case let .arc(spanCount), let .soft(spanCount):
            let degree = controlPointCount - 1
            guard (3...11).contains(degree) else {
                throw formError("Arc and Soft extensions store an end segment of degree 3...11.")
            }
            guard (1...CurvatureProfileExtension.maximumSpanCount).contains(spanCount) else {
                throw formError("Arc and Soft extensions have 1...\(CurvatureProfileExtension.maximumSpanCount) spans.")
            }
            return spanCount * degree
        case let .reflective(degree, _):
            guard (1...11).contains(degree), controlPointCount >= degree + 1,
                  (controlPointCount - 1).isMultiple(of: degree) else {
                throw formError("A Reflective extension stores whole Bezier segments of degree 1...11.")
            }
            return controlPointCount - 1
        }
    }

    public static func validateCoordinateForm(shape: BezierExtensionShape, count: Int, index: Int) throws {
        guard count.isMultiple(of: 2), count <= 2 * 4_096 else {
            throw formError("A shaped extension stores interleaved x, y coordinates of at most 4096 points.")
        }
        let newPoints = try newPointCount(shape: shape, controlPointCount: count / 2)
        guard (0..<(2 * newPoints)).contains(index) else {
            throw formError("A shaped extension's coordinate index must select one of its new points.")
        }
    }

    /// Evaluates one persisted extension coordinate after both expression evaluators resolve inputs.
    public func coordinate(
        shape: BezierExtensionShape,
        coordinates: [Quantity],
        length: Quantity,
        index: Int
    ) throws -> Quantity {
        try Self.validateCoordinateForm(shape: shape, count: coordinates.count, index: index)
        for value in coordinates + [length] {
            try value.validate()
            guard value.kind == .length else {
                throw UnitError.expectedQuantity(operation: "bezierShapedExtension", expected: .length, actual: value.kind)
            }
        }
        let points = stride(from: 0, to: coordinates.count, by: 2).map {
            Point2D(x: coordinates[$0].value, y: coordinates[$0 + 1].value)
        }
        let result = try newPoints(shape: shape, controlPoints: points, length: length.value)[index / 2]
        let value = Quantity(value: index.isMultiple(of: 2) ? result.x : result.y, kind: .length)
        try value.validate()
        return value
    }

    /// The extension's new points after the end, in curve order. For Arc and Soft,
    /// `controlPoints` is the end Bezier segment; for Reflective, the stored Bezier segments in
    /// curve order, sharing their joint points.
    public func newPoints(shape: BezierExtensionShape, controlPoints: [Point2D], length: Double) throws -> [Point2D] {
        _ = try Self.newPointCount(shape: shape, controlPointCount: controlPoints.count)
        guard controlPoints.allSatisfy({ $0.x.isFinite && $0.y.isFinite }) else {
            throw invalid("A shaped extension needs finite control points.")
        }
        guard length.isFinite, length > tolerance.distance else {
            throw invalid("An extension length must be finite and above the modeling distance.")
        }
        switch shape {
        case let .arc(spanCount):
            return try profilePoints(segment: controlPoints, length: length, profile: .arc, spanCount: spanCount)
        case let .soft(spanCount):
            return try profilePoints(segment: controlPoints, length: length, profile: .soft, spanCount: spanCount)
        case let .reflective(degree, coversCurve):
            return try reflectivePoints(segments: controlPoints, degree: degree, length: length, coversCurve: coversCurve)
        }
    }

    /// The span count an Arc or Soft extension of this end segment is made with: the fewest
    /// spans within the modeling distance.
    public func profileSpanCount(segment: [Point2D], length: Double, profile: CurvatureProfileExtension.Profile) throws -> Int {
        let frame = try endFrame(of: segment)
        let spans = try CurvatureProfileExtension(tolerance: tolerance).cubicSpans(
            from: frame.point, direction: frame.tangent, curvature: frame.curvature, length: length, profile: profile
        )
        return spans.count / 3
    }

    /// How many of the curve's Bezier segments (`segments` in curve order, sharing joints) a
    /// Reflective extension of `length` stores, counted from the end, and whether that is all of
    /// them: the segments back to the one the reflected length starts in.
    public func reflectiveSegmentCount(segments: [Point2D], degree: Int, length: Double) throws -> (count: Int, coversCurve: Bool) {
        let total = try Self.newPointCount(shape: .reflective(degree: degree, coversCurve: true), controlPointCount: segments.count) / degree
        let start = try reflectedStart(segments: segments, degree: degree, length: length)
        guard let start else { return (total, true) }
        return (total - start.segment, start.segment == 0)
    }

    // MARK: - Arc and Soft

    private func profilePoints(
        segment: [Point2D],
        length: Double,
        profile: CurvatureProfileExtension.Profile,
        spanCount: Int
    ) throws -> [Point2D] {
        let degree = segment.count - 1
        let frame = try endFrame(of: segment)
        let spans = try CurvatureProfileExtension(tolerance: tolerance).cubicSpans(
            from: frame.point, direction: frame.tangent, curvature: frame.curvature,
            length: length, profile: profile, spanCount: spanCount
        )
        var points: [Point2D] = []
        var previous = frame.point
        for start in stride(from: 0, to: spans.count, by: 3) {
            var bezier = [previous] + Array(spans[start..<(start + 3)])
            while bezier.count - 1 < degree { bezier = elevated(bezier) }
            points += bezier.dropFirst()
            previous = bezier[bezier.count - 1]
        }
        return points
    }

    /// The end point, unit tangent and signed curvature of a Bezier segment's end.
    private func endFrame(of segment: [Point2D]) throws -> (point: Point2D, tangent: Point2D, curvature: Double) {
        let n = Double(segment.count - 1)
        let p = segment[segment.count - 1], q = segment[segment.count - 2], r = segment[segment.count - 3]
        let first = Point2D(x: n * (p.x - q.x), y: n * (p.y - q.y))
        let second = Point2D(x: n * (n - 1) * (p.x - 2 * q.x + r.x), y: n * (n - 1) * (p.y - 2 * q.y + r.y))
        let speed = hypot(first.x, first.y)
        guard speed > tolerance.distance else {
            throw invalid("The curve's end has no tangent to extend along.")
        }
        let curvature = (first.x * second.y - first.y * second.x) / (speed * speed * speed)
        return (p, Point2D(x: first.x / speed, y: first.y / speed), curvature)
    }

    private func elevated(_ p: [Point2D]) -> [Point2D] {
        let n = Double(p.count - 1)
        var q = [p[0]]
        for i in 1..<p.count {
            let a = Double(i) / (n + 1)
            q.append(Point2D(x: a * p[i - 1].x + (1 - a) * p[i].x, y: a * p[i - 1].y + (1 - a) * p[i].y))
        }
        q.append(p[p.count - 1])
        return q
    }

    // MARK: - Reflective

    private func reflectivePoints(segments: [Point2D], degree: Int, length: Double, coversCurve: Bool) throws -> [Point2D] {
        let start = try reflectedStart(segments: segments, degree: degree, length: length)
        let tail: [Point2D]
        switch start {
        case nil:
            guard coversCurve else {
                throw KernelError(phase: .geometry, code: .resourceLimitExceeded, tolerance: tolerance,
                    message: "The Reflective extension is longer than the curve segments it stores; extend the curve again.")
            }
            tail = segments
        case let .some(start):
            guard start.segment == 0 else {
                throw KernelError(phase: .geometry, code: .resourceLimitExceeded, tolerance: tolerance,
                    message: "The Reflective extension now starts in a later segment than it stores; extend the curve again.")
            }
            tail = split(Array(segments[0...degree]), at: start.parameter) + segments.dropFirst(degree + 1)
        }
        let end = segments[segments.count - 1]
        let direction = try endTangent(of: segments)
        // Mirror across the line through the end perpendicular to its tangent, backwards.
        return tail.reversed().dropFirst().map { q in
            let along = (q.x - end.x) * direction.x + (q.y - end.y) * direction.y
            return Point2D(x: q.x - 2 * along * direction.x, y: q.y - 2 * along * direction.y)
        }
    }

    /// The unit tangent at the last control point, along the last control-polygon leg.
    private func endTangent(of points: [Point2D]) throws -> Point2D {
        let p = points[points.count - 1], q = points[points.count - 2]
        let speed = hypot(p.x - q.x, p.y - q.y)
        guard speed > tolerance.distance else {
            throw invalid("The curve's end has no tangent to extend along.")
        }
        return Point2D(x: (p.x - q.x) / speed, y: (p.y - q.y) / speed)
    }

    /// Where the last `length` of the curve starts: the segment (0 the first stored) and its
    /// parameter, or nil when the length reaches past the stored segments. A length ending
    /// exactly at a joint starts in the later segment.
    private func reflectedStart(segments: [Point2D], degree: Int, length: Double) throws -> (segment: Int, parameter: Double)? {
        guard length.isFinite, length > tolerance.distance else {
            throw invalid("An extension length must be finite and above the modeling distance.")
        }
        let count = (segments.count - 1) / degree
        var remaining = length
        for index in stride(from: count - 1, through: 0, by: -1) {
            let segment = Array(segments[(index * degree)...((index + 1) * degree)])
            let segmentLength = arcLength(of: segment, from: 0, to: 1)
            if remaining <= segmentLength {
                return (index, try parameter(on: segment, lengthBeforeEnd: remaining, total: segmentLength))
            }
            remaining -= segmentLength
        }
        return nil
    }

    /// The parameter u with arc length `target` from u to the segment's end, by bisection
    /// refined with Newton steps.
    private func parameter(on segment: [Point2D], lengthBeforeEnd target: Double, total: Double) throws -> Double {
        var low = 0.0, high = 1.0
        var u = 1 - target / max(total, .leastNormalMagnitude)
        for _ in 0..<100 {
            let value = arcLength(of: segment, from: u, to: 1) - target
            if abs(value) <= tolerance.distance * 1e-3 { return u }
            if value > 0 { low = u } else { high = u }
            let derivative = derivativeSpeed(of: segment, at: u)
            let newton = u + value / max(derivative, .leastNormalMagnitude)
            u = (newton > low && newton < high) ? newton : (low + high) / 2
        }
        throw KernelError(phase: .geometry, code: .resourceLimitExceeded, tolerance: tolerance,
            message: "The Reflective extension's start did not converge.")
    }

    private func derivativeSpeed(of segment: [Point2D], at u: Double) -> Double {
        let n = Double(segment.count - 1)
        let hodograph = zip(segment, segment.dropFirst()).map { Point2D(x: n * ($1.x - $0.x), y: n * ($1.y - $0.y)) }
        let d = hodograph.isEmpty ? Point2D(x: 0, y: 0) : evaluate(hodograph, at: u)
        return hypot(d.x, d.y)
    }

    /// Composite five-point Gauss–Legendre on the segment's speed.
    private func arcLength(of segment: [Point2D], from a: Double, to b: Double) -> Double {
        let nodes = [0.0, -0.538_469_310_105_683_1, 0.538_469_310_105_683_1, -0.906_179_845_938_664, 0.906_179_845_938_664]
        let weights = [0.568_888_888_888_888_9, 0.478_628_670_499_366_5, 0.478_628_670_499_366_5, 0.236_926_885_056_189_1, 0.236_926_885_056_189_1]
        let pieces = 32
        let width = (b - a) / Double(pieces)
        var total = 0.0
        for piece in 0..<pieces {
            let middle = a + (Double(piece) + 0.5) * width
            for (node, weight) in zip(nodes, weights) {
                total += weight * derivativeSpeed(of: segment, at: middle + node * width / 2) * width / 2
            }
        }
        return total
    }

    private func evaluate(_ points: [Point2D], at t: Double) -> Point2D {
        var level = points
        while level.count > 1 {
            level = zip(level, level.dropFirst()).map { Point2D(x: $0.x + ($1.x - $0.x) * t, y: $0.y + ($1.y - $0.y) * t) }
        }
        return level[0]
    }

    /// The part of a Bezier segment from `u` to its end, by de Casteljau.
    private func split(_ segment: [Point2D], at u: Double) -> [Point2D] {
        var level = segment
        var right = [level[level.count - 1]]
        while level.count > 1 {
            level = zip(level, level.dropFirst()).map { Point2D(x: $0.x + ($1.x - $0.x) * u, y: $0.y + ($1.y - $0.y) * u) }
            right.append(level[level.count - 1])
        }
        return right.reversed()
    }

    private static func formError(_ message: String) -> KernelError {
        KernelError(phase: .geometry, code: .invalidInput, tolerance: .standard, message: message)
    }

    private func invalid(_ message: String) -> KernelError {
        KernelError(phase: .geometry, code: .invalidInput, tolerance: tolerance, message: message)
    }
}
