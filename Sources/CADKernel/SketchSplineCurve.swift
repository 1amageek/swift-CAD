import CADCore
import CADGeometry
import CADIR

/// A sketch spline's exact geometry in the sketch plane: its clamped B-spline and the Bezier
/// segments it is made of, each with its parameter interval on the B-spline.
///
/// A spline in chain form already is its segments, span k on [k, k + 1]. A spline with explicit
/// knots is decomposed by inserting every interior knot up to multiplicity `degree`, which does
/// not change the curve.
public struct SketchSplineCurve: Sendable, Hashable {
    public struct Segment: Sendable, Hashable {
        /// The segment's `degree + 1` Bezier control points.
        public var controlPoints: [Point2D]
        public var lowerParameter: Double
        public var upperParameter: Double
    }

    public let degree: Int
    public let bSpline: BSplineCurve2D
    public let segments: [Segment]

    public init(spline: SketchSpline, controlPoints: [Point2D], tolerance: ModelingTolerance) throws {
        guard controlPoints.count == spline.controlPoints.count else {
            throw SketchError.invalidReference("A sketch spline's resolved control points must match its control points.")
        }
        try self.init(degree: spline.degree, knots: spline.knots, controlPoints: controlPoints, tolerance: tolerance)
    }

    /// The geometry of resolved control points of `degree`, with `knots` or in chain form when nil.
    public init(degree: Int, knots explicitKnots: [Double]?, controlPoints: [Point2D], tolerance: ModelingTolerance) throws {
        // The form's rules live on SketchSpline; its control point values do not matter to them.
        let origin = SketchPoint(x: .constant(.length(0, unit: .meter)), y: .constant(.length(0, unit: .meter)))
        let spline = SketchSpline(
            controlPoints: Array(repeating: origin, count: controlPoints.count),
            degree: degree,
            knots: explicitKnots
        )
        try spline.validateForm()
        guard controlPoints.allSatisfy({ $0.x.isFinite && $0.y.isFinite }) else {
            throw SketchError.unsupportedEntity("A sketch spline's control points must be finite.")
        }
        guard let knots = spline.knotVector else {
            throw SketchError.unsupportedEntity("A sketch spline's knot vector could not be resolved.")
        }
        let bSpline = BSplineCurve2D(degree: degree, knots: knots, controlPoints: controlPoints)
        try bSpline.validate(tolerance: tolerance)
        self.degree = degree
        self.bSpline = bSpline
        if spline.isBezierChain {
            segments = stride(from: 0, to: controlPoints.count - 1, by: degree).map { start in
                let span = Double(start / degree)
                return Segment(
                    controlPoints: Array(controlPoints[start...(start + degree)]),
                    lowerParameter: span,
                    upperParameter: span + 1
                )
            }
        } else {
            segments = try Self.bezierSegments(of: bSpline, tolerance: tolerance)
        }
    }

    /// Raises every interior knot of `curve` to multiplicity `degree` and slices the result.
    private static func bezierSegments(of curve: BSplineCurve2D, tolerance: ModelingTolerance) throws -> [Segment] {
        let degree = curve.degree
        var refined = curve
        let interior = Array(curve.knots.dropFirst(degree + 1).dropLast(degree + 1))
        var distinct: [(value: Double, multiplicity: Int)] = []
        for knot in interior {
            if let last = distinct.last, last.value == knot {
                distinct[distinct.count - 1].multiplicity += 1
            } else {
                distinct.append((knot, 1))
            }
        }
        for (value, multiplicity) in distinct where multiplicity < degree {
            for _ in multiplicity..<degree {
                refined = try refined.insertingKnot(value, tolerance: tolerance)
            }
        }
        let breaks = [curve.knots[degree]] + distinct.map(\.value) + [curve.knots[curve.knots.count - degree - 1]]
        let points = refined.controlPoints
        guard points.count == degree * (breaks.count - 1) + 1 else {
            throw SketchError.unsupportedEntity("A sketch spline could not be decomposed into Bezier segments.")
        }
        return (0..<(breaks.count - 1)).map { index in
            Segment(
                controlPoints: Array(points[(degree * index)...(degree * index + degree)]),
                lowerParameter: breaks[index],
                upperParameter: breaks[index + 1]
            )
        }
    }
}
