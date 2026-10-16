#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#elseif canImport(WASILibc)
import WASILibc
#else
#error("CADCore numeric algorithms require the target C math module.")
#endif

/// The persisted form of Extend Curve's Arc, Soft and Reflective shapes: what, besides the
/// curve's own Bezier control points and the length, fixes the new points' structure.
public enum BezierExtensionShape: Sendable, Hashable {
    /// The end's curvature held over `spanCount` cubic spans raised to the curve's degree.
    case arc(spanCount: Int)
    /// The end's curvature fading to zero over `spanCount` cubic spans raised to the curve's degree.
    case soft(spanCount: Int)
    /// The curve's last length, taken from its stored Bezier segments of `degree`, mirrored across
    /// the end's normal; with `coversCurve` the stored segments are the whole curve, so a length
    /// past it mirrors all of it.
    case reflective(degree: Int, coversCurve: Bool)


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
        var admission = UnboundedAuthoringAdmission()
        return try coordinate(shape: shape, coordinates: coordinates, length: length, index: index, using: &admission)
    }

    public func coordinate<A: NumericWorkAdmission & ~Copyable>(
        shape: BezierExtensionShape, coordinates: [Quantity], length: Quantity,
        index: Int, using admission: inout A
    ) throws -> Quantity {
        try admission.checkpoint()
        try Self.validateCoordinateForm(shape: shape, count: coordinates.count, index: index)
        for offset in 0...coordinates.count {
            try admission.consumeWork(1)
            let value = offset < coordinates.count ? coordinates[offset] : length
            try value.validate()
            guard value.kind == .length else {
                throw UnitError.expectedQuantity(operation: "bezierShapedExtension", expected: .length, actual: value.kind)
            }
        }
        try admission.retainStorage(count: coordinates.count / 2, stride: MemoryLayout<Point2D>.stride)
        let points = try stride(from: 0, to: coordinates.count, by: 2).map { offset in
            try admission.consumeWork(1)
            return Point2D(x: coordinates[offset].value, y: coordinates[offset + 1].value)
        }
        let result = try newPoints(shape: shape, controlPoints: points, length: length.value, using: &admission)[index / 2]
        let value = Quantity(value: index.isMultiple(of: 2) ? result.x : result.y, kind: .length)
        try value.validate()
        try admission.checkpoint()
        return value
    }

    /// The extension's new points after the end, in curve order. For Arc and Soft,
    /// `controlPoints` is the end Bezier segment; for Reflective, the stored Bezier segments in
    /// curve order, sharing their joint points.
    public func newPoints(shape: BezierExtensionShape, controlPoints: [Point2D], length: Double) throws -> [Point2D] {
        var admission = UnboundedAuthoringAdmission()
        return try newPoints(shape: shape, controlPoints: controlPoints, length: length, using: &admission)
    }

    public func newPoints<A: NumericWorkAdmission & ~Copyable>(
        shape: BezierExtensionShape, controlPoints: [Point2D], length: Double, using admission: inout A
    ) throws -> [Point2D] {
        try admission.checkpoint()
        _ = try Self.newPointCount(shape: shape, controlPointCount: controlPoints.count)
        for point in controlPoints {
            try admission.consumeWork(1)
            guard point.x.isFinite && point.y.isFinite else {
                throw invalid("A shaped extension needs finite control points.")
            }
        }
        guard length.isFinite, length > tolerance.distance else {
            throw invalid("An extension length must be finite and above the modeling distance.")
        }
        let result: [Point2D]
        switch shape {
        case let .arc(spanCount):
            result = try profilePoints(segment: controlPoints, length: length, profile: .arc, spanCount: spanCount, using: &admission)
        case let .soft(spanCount):
            result = try profilePoints(segment: controlPoints, length: length, profile: .soft, spanCount: spanCount, using: &admission)
        case let .reflective(degree, coversCurve):
            result = try reflectivePoints(segments: controlPoints, degree: degree, length: length, coversCurve: coversCurve, using: &admission)
        }
        try admission.checkpoint()
        return result
    }

    /// The span count an Arc or Soft extension of this end segment is made with: the fewest
    /// spans within the modeling distance.
    public func profileSpanCount(segment: [Point2D], length: Double, profile: CurvatureProfileExtension.Profile) throws -> Int {
        var admission = UnboundedAuthoringAdmission()
        return try profileSpanCount(segment: segment, length: length, profile: profile, using: &admission)
    }

    public func profileSpanCount<A: NumericWorkAdmission & ~Copyable>(
        segment: [Point2D], length: Double, profile: CurvatureProfileExtension.Profile, using admission: inout A
    ) throws -> Int {
        try admission.checkpoint()
        let frame = try endFrame(of: segment, using: &admission)
        let spans = try CurvatureProfileExtension(tolerance: tolerance).cubicSpans(
            from: frame.point, direction: frame.tangent, curvature: frame.curvature, length: length, profile: profile,
            using: &admission
        )
        try admission.checkpoint()
        return spans.count / 3
    }

    /// How many of the curve's Bezier segments (`segments` in curve order, sharing joints) a
    /// Reflective extension of `length` stores, counted from the end, and whether that is all of
    /// them: the segments back to the one the reflected length starts in.
    public func reflectiveSegmentCount(segments: [Point2D], degree: Int, length: Double) throws -> (count: Int, coversCurve: Bool) {
        var admission = UnboundedAuthoringAdmission()
        return try reflectiveSegmentCount(segments: segments, degree: degree, length: length, using: &admission)
    }

    public func reflectiveSegmentCount<A: NumericWorkAdmission & ~Copyable>(
        segments: [Point2D], degree: Int, length: Double, using admission: inout A
    ) throws -> (count: Int, coversCurve: Bool) {
        try admission.checkpoint()
        let total = try Self.newPointCount(shape: .reflective(degree: degree, coversCurve: true), controlPointCount: segments.count) / degree
        let start = try reflectedStart(segments: segments, degree: degree, length: length, using: &admission)
        try admission.checkpoint()
        guard let start else { return (total, true) }
        return (total - start.segment, start.segment == 0)
    }

    // MARK: - Arc and Soft

    private func profilePoints<A: NumericWorkAdmission & ~Copyable>(
        segment: [Point2D],
        length: Double,
        profile: CurvatureProfileExtension.Profile,
        spanCount: Int,
        using admission: inout A
    ) throws -> [Point2D] {
        let degree = segment.count - 1
        let frame = try endFrame(of: segment, using: &admission)
        let spans = try CurvatureProfileExtension(tolerance: tolerance).cubicSpans(
            from: frame.point, direction: frame.tangent, curvature: frame.curvature,
            length: length, profile: profile, spanCount: spanCount, using: &admission
        )
        let outputCount = spanCount * degree
        try admission.retainStorage(count: outputCount, stride: MemoryLayout<Point2D>.stride)
        var points: [Point2D] = []
        points.reserveCapacity(outputCount)
        var previous = frame.point
        for start in stride(from: 0, to: spans.count, by: 3) {
            try admission.consumeWork(1)
            try admission.retainStorage(count: 4, stride: MemoryLayout<Point2D>.stride)
            try admission.consumeWork(4)
            var bezier = [previous, spans[start], spans[start + 1], spans[start + 2]]
            while bezier.count - 1 < degree {
                try admission.consumeWork(1)
                bezier = try elevated(bezier, using: &admission)
            }
            for point in bezier.dropFirst() {
                try admission.consumeWork(1)
                points.append(point)
            }
            previous = bezier[bezier.count - 1]
        }
        return points
    }

    /// The end point, unit tangent and signed curvature of a Bezier segment's end.
    private func endFrame<A: NumericWorkAdmission & ~Copyable>(
        of segment: [Point2D], using admission: inout A
    ) throws -> (point: Point2D, tangent: Point2D, curvature: Double) {
        try admission.consumeWork(3)
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

    private func elevated<A: NumericWorkAdmission & ~Copyable>(_ p: [Point2D], using admission: inout A) throws -> [Point2D] {
        let n = Double(p.count - 1)
        try admission.retainStorage(count: p.count + 1, stride: MemoryLayout<Point2D>.stride)
        var q: [Point2D] = []
        q.reserveCapacity(p.count + 1)
        try admission.consumeWork(1)
        q.append(p[0])
        for i in 1..<p.count {
            try admission.consumeWork(1)
            let a = Double(i) / (n + 1)
            q.append(Point2D(x: a * p[i - 1].x + (1 - a) * p[i].x, y: a * p[i - 1].y + (1 - a) * p[i].y))
        }
        try admission.consumeWork(1)
        q.append(p[p.count - 1])
        return q
    }

    // MARK: - Reflective

    private func reflectivePoints<A: NumericWorkAdmission & ~Copyable>(
        segments: [Point2D], degree: Int, length: Double, coversCurve: Bool, using admission: inout A
    ) throws -> [Point2D] {
        let start = try reflectedStart(segments: segments, degree: degree, length: length, using: &admission)
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
            try admission.retainStorage(count: degree + 1, stride: MemoryLayout<Point2D>.stride)
            try admission.consumeWork(degree + 1)
            let segment = Array(segments[0...degree])
            let right = try split(segment, at: start.parameter, using: &admission)
            try admission.retainStorage(count: segments.count, stride: MemoryLayout<Point2D>.stride)
            try admission.consumeWork(segments.count)
            tail = right + segments.dropFirst(degree + 1)
        }
        let end = segments[segments.count - 1]
        let direction = try endTangent(of: segments, using: &admission)
        // Mirror across the line through the end perpendicular to its tangent, backwards.
        try admission.retainStorage(count: tail.count - 1, stride: MemoryLayout<Point2D>.stride)
        return try tail.reversed().dropFirst().map { q in
            try admission.consumeWork(1)
            let along = (q.x - end.x) * direction.x + (q.y - end.y) * direction.y
            return Point2D(x: q.x - 2 * along * direction.x, y: q.y - 2 * along * direction.y)
        }
    }

    /// The unit tangent at the last control point, along the last control-polygon leg.
    private func endTangent<A: NumericWorkAdmission & ~Copyable>(of points: [Point2D], using admission: inout A) throws -> Point2D {
        try admission.consumeWork(2)
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
    private func reflectedStart<A: NumericWorkAdmission & ~Copyable>(
        segments: [Point2D], degree: Int, length: Double, using admission: inout A
    ) throws -> (segment: Int, parameter: Double)? {
        guard length.isFinite, length > tolerance.distance else {
            throw invalid("An extension length must be finite and above the modeling distance.")
        }
        let count = (segments.count - 1) / degree
        var remaining = length
        for index in stride(from: count - 1, through: 0, by: -1) {
            try admission.consumeWork(1)
            try admission.retainStorage(count: degree + 1, stride: MemoryLayout<Point2D>.stride)
            try admission.consumeWork(degree + 1)
            let segment = Array(segments[(index * degree)...((index + 1) * degree)])
            let segmentLength = try arcLength(of: segment, from: 0, to: 1, using: &admission)
            if remaining <= segmentLength {
                return (index, try parameter(on: segment, lengthBeforeEnd: remaining, total: segmentLength, using: &admission))
            }
            remaining -= segmentLength
        }
        return nil
    }

    /// The parameter u with arc length `target` from u to the segment's end, by bisection
    /// refined with Newton steps.
    private func parameter<A: NumericWorkAdmission & ~Copyable>(
        on segment: [Point2D], lengthBeforeEnd target: Double, total: Double, using admission: inout A
    ) throws -> Double {
        var low = 0.0, high = 1.0
        var u = 1 - target / max(total, .leastNormalMagnitude)
        for _ in 0..<100 {
            try admission.consumeWork(1)
            let value = try arcLength(of: segment, from: u, to: 1, using: &admission) - target
            if abs(value) <= tolerance.distance * 1e-3 { return u }
            if value > 0 { low = u } else { high = u }
            let derivative = try derivativeSpeed(of: segment, at: u, using: &admission)
            let newton = u + value / max(derivative, .leastNormalMagnitude)
            u = (newton > low && newton < high) ? newton : (low + high) / 2
        }
        throw KernelError(phase: .geometry, code: .resourceLimitExceeded, tolerance: tolerance,
            message: "The Reflective extension's start did not converge.")
    }

    private func derivativeSpeed<A: NumericWorkAdmission & ~Copyable>(
        of segment: [Point2D], at u: Double, using admission: inout A
    ) throws -> Double {
        let n = Double(segment.count - 1)
        try admission.retainStorage(count: segment.count - 1, stride: MemoryLayout<Point2D>.stride)
        let hodograph = try zip(segment, segment.dropFirst()).map { first, second in
            try admission.consumeWork(1)
            return Point2D(x: n * (second.x - first.x), y: n * (second.y - first.y))
        }
        let d = try hodograph.isEmpty ? Point2D(x: 0, y: 0) : evaluate(hodograph, at: u, using: &admission)
        return hypot(d.x, d.y)
    }

    /// Composite five-point Gauss–Legendre on the segment's speed.
    private func arcLength<A: NumericWorkAdmission & ~Copyable>(
        of segment: [Point2D], from a: Double, to b: Double, using admission: inout A
    ) throws -> Double {
        try admission.retainStorage(count: 10, stride: MemoryLayout<Double>.stride)
        try admission.consumeWork(10)
        let nodes = [0.0, -0.538_469_310_105_683_1, 0.538_469_310_105_683_1, -0.906_179_845_938_664, 0.906_179_845_938_664]
        let weights = [0.568_888_888_888_888_9, 0.478_628_670_499_366_5, 0.478_628_670_499_366_5, 0.236_926_885_056_189_1, 0.236_926_885_056_189_1]
        let pieces = 32
        let width = (b - a) / Double(pieces)
        var total = 0.0
        for piece in 0..<pieces {
            try admission.consumeWork(1)
            let middle = a + (Double(piece) + 0.5) * width
            for (node, weight) in zip(nodes, weights) {
                try admission.consumeWork(1)
                total += try weight * derivativeSpeed(of: segment, at: middle + node * width / 2, using: &admission) * width / 2
            }
        }
        return total
    }

    private func evaluate<A: NumericWorkAdmission & ~Copyable>(
        _ points: [Point2D], at t: Double, using admission: inout A
    ) throws -> Point2D {
        var level = points
        while level.count > 1 {
            try admission.consumeWork(1)
            try admission.retainStorage(count: level.count - 1, stride: MemoryLayout<Point2D>.stride)
            level = try zip(level, level.dropFirst()).map { first, second in
                try admission.consumeWork(1)
                return Point2D(x: first.x + (second.x - first.x) * t, y: first.y + (second.y - first.y) * t)
            }
        }
        return level[0]
    }

    /// The part of a Bezier segment from `u` to its end, by de Casteljau.
    private func split<A: NumericWorkAdmission & ~Copyable>(
        _ segment: [Point2D], at u: Double, using admission: inout A
    ) throws -> [Point2D] {
        var level = segment
        try admission.retainStorage(count: segment.count, stride: MemoryLayout<Point2D>.stride)
        var right: [Point2D] = []
        right.reserveCapacity(segment.count)
        try admission.consumeWork(1)
        right.append(level[level.count - 1])
        while level.count > 1 {
            try admission.consumeWork(1)
            try admission.retainStorage(count: level.count - 1, stride: MemoryLayout<Point2D>.stride)
            level = try zip(level, level.dropFirst()).map { first, second in
                try admission.consumeWork(1)
                return Point2D(x: first.x + (second.x - first.x) * u, y: first.y + (second.y - first.y) * u)
            }
            try admission.consumeWork(1)
            right.append(level[level.count - 1])
        }
        try admission.retainStorage(count: right.count, stride: MemoryLayout<Point2D>.stride)
        try admission.consumeWork(right.count)
        return right.reversed()
    }

    private static func formError(_ message: String) -> KernelError {
        KernelError(phase: .geometry, code: .invalidInput, tolerance: .standard, message: message)
    }

    private func invalid(_ message: String) -> KernelError {
        KernelError(phase: .geometry, code: .invalidInput, tolerance: tolerance, message: message)
    }
}

#if !hasFeature(Embedded)
extension BezierExtensionShape: Codable {
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
#endif
