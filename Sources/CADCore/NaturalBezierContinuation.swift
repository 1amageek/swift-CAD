import Foundation

/// Extensions of a cubic Bezier chain, or of any Bezier end segment, past one of its ends.
public struct NaturalBezierContinuation: Sendable {
    /// Which end of the chain is extended.
    public enum End: Sendable {
        case start
        case end
    }

    public let tolerance: ModelingTolerance

    public init(tolerance: ModelingTolerance) {
        self.tolerance = tolerance
    }

    /// Evaluates one persisted extension coordinate after both expression evaluators resolve inputs.
    public func coordinate(_ coordinates: [Quantity], length: Quantity, index: Int) throws -> Quantity {
        try Self.validateCoordinateForm(count: coordinates.count, index: index)
        for value in coordinates + [length] {
            try value.validate()
            guard value.kind == .length else {
                throw UnitError.expectedQuantity(operation: "bezierNaturalExtension", expected: .length, actual: value.kind)
            }
        }
        let points = stride(from: 0, to: coordinates.count, by: 2).map {
            Point2D(x: coordinates[$0].value, y: coordinates[$0 + 1].value)
        }
        let result = try naturalSpan(ofSegment: points, at: .end, length: length.value)[index / 2]
        let value = Quantity(value: index.isMultiple(of: 2) ? result.x : result.y, kind: .length)
        try value.validate()
        return value
    }

    public static func validateCoordinateForm(count: Int, index: Int) throws {
        guard (4...24).contains(count), count.isMultiple(of: 2), (0..<(count - 2)).contains(index) else {
            throw KernelError(phase: .geometry, code: .invalidInput, tolerance: .standard,
                message: "Natural extension requires degree 1...11 and an existing output coordinate.")
        }
    }

    /// The Natural extension at `end`: the end span's own cubic continued past the end until it
    /// has run `length` along itself, as one new span. Returns the span's three new control
    /// points in chain order: to append after the end, or to prepend before the start.
    ///
    /// The end span B on [0, 1] continues as the same polynomial on [1, s]; that piece's control
    /// points are the blossom values f(1,1,1), f(1,1,s), f(1,s,s), f(s,s,s). s solves
    /// ∫₁ˢ |B′(u)| du = length by Newton steps on the arc length, integrated by composite
    /// five-point Gauss–Legendre.
    public func naturalSpan(of controlPoints: [Point2D], at end: End, length: Double) throws -> [Point2D] {
        guard controlPoints.count >= 4, (controlPoints.count - 1).isMultiple(of: 3) else {
            throw invalid("A cubic Bezier chain needs 3n + 1 control points.")
        }
        guard controlPoints.allSatisfy({ $0.x.isFinite && $0.y.isFinite }) else {
            throw invalid("A cubic Bezier chain needs finite control points.")
        }
        guard length.isFinite, length > tolerance.distance else {
            throw invalid("An extension length must be finite and above the modeling distance.")
        }
        let count = controlPoints.count
        let segment: [Point2D] = switch end {
        case .end: Array(controlPoints[(count - 4)...])
        case .start: Array(controlPoints[0...3])
        }
        return try naturalSpan(ofSegment: segment, at: end, length: length)
    }

    /// The Natural extension of a curve whose end segment is the Bezier `segment` of any degree
    /// n (n + 1 points in curve order, the first or last segment as `end` says): the segment's
    /// polynomial continued past that end until it has run `length` along itself, as one new
    /// Bezier span of the same degree. Returns its n new control points in curve order, to append
    /// after the end or prepend before the start.
    public func naturalSpan(ofSegment segment: [Point2D], at end: End, length: Double) throws -> [Point2D] {
        guard segment.count >= 2 else {
            throw invalid("A Bezier segment needs at least two control points.")
        }
        guard segment.allSatisfy({ $0.x.isFinite && $0.y.isFinite }) else {
            throw invalid("A Bezier segment needs finite control points.")
        }
        guard length.isFinite, length > tolerance.distance else {
            throw invalid("An extension length must be finite and above the modeling distance.")
        }
        let span: [Point2D] = switch end {
        case .end: segment
        case .start: segment.reversed()
        }
        let endSpeed = speed(span, at: 1)
        guard endSpeed > tolerance.distance else {
            throw invalid("The chain's end has no tangent to continue along.")
        }
        var s = 1 + length / endSpeed
        for _ in 0..<50 {
            let error = arcLength(span, from: 1, to: s) - length
            let step = error / speed(span, at: s)
            guard step.isFinite else { throw invalid("The Natural extension did not converge.") }
            s -= step
            if abs(step) <= 1e-14 * max(1, s) { break }
        }
        guard s > 1, abs(arcLength(span, from: 1, to: s) - length) <= tolerance.distance else {
            throw invalid("The Natural extension did not reach the requested length.")
        }
        // The piece on [1, s] has control points f(1…1, s…s) with i values s, i = 1…n.
        let degree = span.count - 1
        let continued = (1...degree).map { count in
            blossom(span, Array(repeating: 1, count: degree - count) + Array(repeating: s, count: count))
        }
        return switch end {
        case .end: continued
        case .start: continued.reversed()
        }
    }

    /// The blossom of Bezier `p` at `parameters` (one per degree): De Casteljau with a different
    /// parameter per level.
    private func blossom(_ p: [Point2D], _ parameters: [Double]) -> Point2D {
        var points = p
        for u in parameters {
            points = zip(points, points.dropFirst()).map { a, b in Point2D(x: a.x + (b.x - a.x) * u, y: a.y + (b.y - a.y) * u) }
        }
        return points[0]
    }

    /// |B′(u)| of Bezier `p`, for any u: its derivative's Bezier by De Casteljau.
    private func speed(_ p: [Point2D], at u: Double) -> Double {
        let n = Double(p.count - 1)
        let derivative = zip(p, p.dropFirst()).map { a, b in Point2D(x: n * (b.x - a.x), y: n * (b.y - a.y)) }
        let d = blossom(derivative, Array(repeating: u, count: derivative.count - 1))
        return (d.x * d.x + d.y * d.y).squareRoot()
    }

    private func arcLength(_ p: [Point2D], from a: Double, to b: Double) -> Double {
        let nodes = [0.0, -0.538_469_310_105_683_1, 0.538_469_310_105_683_1, -0.906_179_845_938_664, 0.906_179_845_938_664]
        let weights = [0.568_888_888_888_888_9, 0.478_628_670_499_366_5, 0.478_628_670_499_366_5, 0.236_926_885_056_189_1, 0.236_926_885_056_189_1]
        let pieces = 16
        let width = (b - a) / Double(pieces)
        var total = 0.0
        for piece in 0..<pieces {
            let middle = a + (Double(piece) + 0.5) * width
            for (node, weight) in zip(nodes, weights) {
                total += weight * speed(p, at: middle + node * width / 2)
            }
        }
        return total * width / 2
    }

    private func invalid(_ message: String) -> KernelError {
        KernelError(phase: .geometry, code: .invalidInput, tolerance: tolerance, message: message)
    }
}
