import CADCore
import CADGeometry

extension SketchSplineCurve {
    /// The same curve one degree higher, on the same parameter.
    ///
    /// Each Bezier segment of degree n is elevated exactly (Qᵢ = i/(n+1)·Pᵢ₋₁ + (1 − i/(n+1))·Pᵢ)
    /// and the segments are joined at their parameter breaks with knots of multiplicity n + 1,
    /// so the curve passes through every former break: exact in shape and parameter, with more
    /// control points and, where knots were smooth, more joints.
    public func degreeElevated(tolerance: ModelingTolerance) throws -> BSplineCurve2D {
        guard let first = segments.first, let last = segments.last else {
            throw SketchError.unsupportedEntity("A spline without segments cannot be raised in degree.")
        }
        let raised = degree + 1
        var controlPoints: [Point2D] = []
        var knots = Array(repeating: first.lowerParameter, count: raised + 1)
        for (index, segment) in segments.enumerated() {
            let p = segment.controlPoints
            let n = Double(p.count - 1)
            var q = [p[0]]
            for i in 1..<p.count {
                let a = Double(i) / (n + 1)
                q.append(Point2D(x: a * p[i - 1].x + (1 - a) * p[i].x, y: a * p[i - 1].y + (1 - a) * p[i].y))
            }
            q.append(p[p.count - 1])
            controlPoints += index == 0 ? q : Array(q.dropFirst())
            if index < segments.count - 1 {
                knots += Array(repeating: segment.upperParameter, count: raised)
            }
        }
        knots += Array(repeating: last.upperParameter, count: raised + 1)
        let curve = BSplineCurve2D(degree: raised, knots: knots, controlPoints: controlPoints)
        try curve.validate(tolerance: tolerance)
        return curve
    }
}
