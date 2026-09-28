import CADCore

/// A clamped, non-rational B-spline in the sketch plane.
///
/// With `knots == nil` the spline is in Bezier-chain form: spans of `degree` joined end to end,
/// span k on [k, k + 1] using control points `degree·k` through `degree·(k + 1)`, every interior
/// knot of multiplicity `degree`, so the curve passes through every `degree`-th control point.
/// With explicit knots it is a general clamped B-spline. A closed spline's last control point
/// equals its first.
public struct SketchSpline: Codable, Sendable, Hashable {
    /// The highest degree a sketch spline may have: enough for a G3–G3 bridge (degree 7) and
    /// room to raise it further, while Bernstein and de Boor evaluation stay well conditioned.
    public static let maximumDegree = 11

    public var controlPoints: [SketchPoint]
    public var isClosed: Bool
    public var degree: Int
    /// The clamped knot vector, or nil for the Bezier-chain form.
    public var knots: [Double]?

    public init(controlPoints: [SketchPoint], isClosed: Bool = false, degree: Int = 3, knots: [Double]? = nil) {
        self.controlPoints = controlPoints
        self.isClosed = isClosed
        self.degree = degree
        self.knots = knots
    }

    /// Whether the spline is in Bezier-chain form.
    public var isBezierChain: Bool { knots == nil }

    /// Whether the spline is the cubic Bezier chain every earlier sketch holds.
    public var isCubicBezierChain: Bool { knots == nil && degree == 3 }

    /// The chain form's span count, or nil for explicit knots or a count that is not degree·n + 1.
    public var spanCount: Int? {
        guard knots == nil, degree >= 1, controlPoints.count >= degree + 1,
              (controlPoints.count - 1).isMultiple(of: degree) else { return nil }
        return (controlPoints.count - 1) / degree
    }

    /// The control point indices the curve passes through: every `degree`-th one in chain form,
    /// the two ends otherwise.
    public var jointIndices: [Int] {
        if let spanCount {
            return (0...spanCount).map { $0 * degree }
        }
        return controlPoints.isEmpty ? [] : [0, controlPoints.count - 1]
    }

    /// The resolved knot vector of either form, or nil when the chain form's count is invalid.
    public var knotVector: [Double]? {
        if let knots { return knots }
        guard let spanCount else { return nil }
        var result = Array(repeating: 0.0, count: degree + 1)
        if spanCount > 1 {
            for span in 1..<spanCount {
                result += Array(repeating: Double(span), count: degree)
            }
        }
        result += Array(repeating: Double(spanCount), count: degree + 1)
        return result
    }

    /// Checks the form: degree in range, the chain form's degree·n + 1 count, or an explicit knot
    /// vector that is finite, non-decreasing, clamped, of positive domain and interior
    /// multiplicity at most `degree`.
    public func validateForm() throws {
        guard (1...Self.maximumDegree).contains(degree) else {
            throw SketchError.unsupportedEntity(
                "Sketch spline degree must be between 1 and \(Self.maximumDegree)."
            )
        }
        guard let knots else {
            guard spanCount != nil else {
                throw SketchError.unsupportedEntity(
                    "A sketch spline of degree \(degree) in chain form needs \(degree)n + 1 control points, at least \(degree + 1)."
                )
            }
            return
        }
        let count = controlPoints.count
        guard count >= degree + 1 else {
            throw SketchError.unsupportedEntity("A sketch spline of degree \(degree) needs at least \(degree + 1) control points.")
        }
        guard knots.count == count + degree + 1 else {
            throw SketchError.unsupportedEntity("A sketch spline's knot vector needs control points + degree + 1 values.")
        }
        guard knots.allSatisfy(\.isFinite), zip(knots, knots.dropFirst()).allSatisfy({ $0 <= $1 }) else {
            throw SketchError.unsupportedEntity("A sketch spline's knots must be finite and non-decreasing.")
        }
        let first = knots[0], last = knots[knots.count - 1]
        guard knots.prefix(degree + 1).allSatisfy({ $0 == first }),
              knots.suffix(degree + 1).allSatisfy({ $0 == last }) else {
            throw SketchError.unsupportedEntity("A sketch spline's knot vector must be clamped.")
        }
        guard last > first else {
            throw SketchError.unsupportedEntity("A sketch spline's knot domain must be positive.")
        }
        let interior = knots.dropFirst(degree + 1).dropLast(degree + 1)
        var run = 0
        var previous: Double?
        for knot in interior {
            run = knot == previous ? run + 1 : 1
            previous = knot
            guard run <= degree else {
                throw SketchError.unsupportedEntity("A sketch spline's interior knot multiplicity must not exceed its degree.")
            }
        }
    }

    private enum CodingKeys: String, CodingKey {
        case controlPoints, isClosed, degree, knots
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        controlPoints = try container.decode([SketchPoint].self, forKey: .controlPoints)
        isClosed = try container.decode(Bool.self, forKey: .isClosed)
        // Documents written before degree and knots existed hold cubic chains.
        degree = try container.decodeIfPresent(Int.self, forKey: .degree) ?? 3
        knots = try container.decodeIfPresent([Double].self, forKey: .knots)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(controlPoints, forKey: .controlPoints)
        try container.encode(isClosed, forKey: .isClosed)
        // The cubic chain writes exactly what earlier documents hold.
        if degree != 3 { try container.encode(degree, forKey: .degree) }
        if let knots { try container.encode(knots, forKey: .knots) }
    }
}
