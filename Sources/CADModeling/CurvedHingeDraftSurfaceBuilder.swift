import Foundation
import CADCore
import CADGeometry

/// The surface a planar face drafted about a curved reference turns onto: isocline along the curve
/// it shares with the reference, so at each point of that hinge the face leans out by the draft
/// angle from the reference's outward normal there (the pull), as a plane does about a straight
/// hinge. The surface is ruled: through each hinge point a straight line running against the pull
/// and out along the face's outward side by the angle's tangent per unit of depth. It is fitted as a
/// B-spline, cubic along the hinge (carried on past its ends — a line or circle along itself, a
/// spline straight along its end tangents with the pull held at its ends — so the faces at its ends
/// still cross it) and linear across it.
package struct CurvedHingeDraftSurfaceBuilder {
    private let tolerance: ModelingTolerance

    package init(tolerance: ModelingTolerance) {
        self.tolerance = tolerance
    }

    /// The drafted surface: `hinge` from `start` to `end` of its parameter, the reference surface
    /// with `referenceSign` turning its normal outward, the face's outward normal, the draft angle,
    /// and `reach`, how far the ruled lines run (and the hinge is carried past its ends).
    package func surface(
        hinge: Curve3D, start: Double, end: Double,
        reference: Surface3D, referenceSign: Double,
        outward: Vector3D, angle: Double, reach: Double
    ) throws -> Surface3D {
        let foot = SurfaceFootResolver()
        let tangent = tan(angle)
        if case let .circle(circle) = hinge,
           let cone = try cone(circle: circle, start: start, end: end, reference: reference, referenceSign: referenceSign,
                               outward: outward, tangent: tangent) {
            return cone
        }
        let (first, last) = (try hinge.point(at: start, tolerance: tolerance), try hinge.point(at: end, tolerance: tolerance))
        let step = (end - start) * 1e-4
        let startDirection = try (try hinge.point(at: start + step, tolerance: tolerance) - first).normalized(tolerance: 1e-300) * -1
        let endDirection = try (last - (try hinge.point(at: end - step, tolerance: tolerance))).normalized(tolerance: 1e-300)
        let carry = 0.5 * reach
        // A line or a circle runs on along itself past the hinge's ends, staying on a reference it
        // lies on (a cylinder's arc), so the ruled lines there meet the reference only on it; a
        // spline is carried on straight along its end tangents.
        let runsOn: Bool
        switch hinge {
        case .line, .circle, .analytic(.line), .analytic(.circle): runsOn = true
        default: runsOn = false
        }
        /// The hinge at `s` in [0, 1], with the hinge itself over [1/5, 4/5] and its carry-ons past
        /// its ends over the rest; `held` is where the pull is measured (the end, past a straight
        /// carry-on). The hinge's ends are breaks of the fit, where a straight carry-on leaves the
        /// curve's curvature behind.
        func hingePoint(_ s: Double) throws -> (point: Point3D, held: Point3D) {
            if runsOn || (0.2...0.8).contains(s) {
                let point = try hinge.point(at: start + (end - start) * (s - 0.2) / 0.6, tolerance: tolerance)
                return (point, point)
            }
            if s < 0.2 {
                return (first + startDirection * (carry * (0.2 - s) / 0.2), first)
            }
            return (last + endDirection * (carry * (s - 0.8) / 0.2), last)
        }

        /// The ruled line's direction through the hinge point at `s`, a unit of depth along the pull.
        func running(_ s: Double) throws -> (point: Point3D, direction: Vector3D) {
            let (point, held) = try hingePoint(s)
            let normal = try foot.foot(of: held, on: reference, tolerance: tolerance).normal * referenceSign
            let pull = try normal.normalized(tolerance: 1e-300)
            let across = try (outward - pull * outward.dot(pull)).normalized(tolerance: tolerance.distance)
            return (point, pull * -1 + across * tangent)
        }
        // FIXME(INCOMPLETE_IMPLEMENTATION): a hinge other than a circle about its reference's
        // normals gets its ruled surface fitted here; a planar neighbour meets it along the exact
        // plane cut (`RuledBSplinePlaneSection`), but any other neighbour is re-solved against
        // the B-spline by the general certified intersector, which fails on it, so such drafts
        // end in that typed failure. Production path: FaceDraftFeatureEvaluator's curved hinge
        // for a non-circular shared edge. Complete only when a drafted wall beside a curved
        // neighbour (a rounded block's end wall under an S top) drafts, verified by its volume.
        // The two rows of the ruled surface, a little above the hinge (so its edge on the
        // reference is a crossing, and no ruled line runs far enough out to meet a neighbour
        // again) and one and a half reaches below, fitted on the same spans: each fit's breaks are
        // handed to the other until both settle on one set.
        let depths = [-0.05 * reach, 1.5 * reach]
        let fitter = try SpatialCurveFitter(deviation: tolerance.distance / 8)
        func breaks(of curve: BSplineCurve3D) -> [Double] {
            var result: [Double] = []
            for knot in curve.knots where result.last.map({ abs($0 - knot) > 1e-15 }) ?? true { result.append(knot) }
            return result
        }
        var rows: [BSplineCurve3D] = []
        var shared = runsOn ? [0.0, 1.0] : [0.0, 0.2, 0.8, 1.0]
        for _ in 0..<6 {
            rows = try depths.map { depth in
                try fitter.fitBSpline(breakpoints: shared, tolerance: tolerance) { s in
                    let line = try running(s)
                    return line.point + line.direction * depth
                }.curve
            }
            let settled = rows.map(breaks)
            if settled.allSatisfy({ $0 == shared }) { break }
            shared = Array(Set(settled.flatMap { $0 })).sorted()
        }
        guard rows.count == 2, rows[0].knots == rows[1].knots else {
            throw KernelError(phase: .geometry, code: .classificationFailure, tolerance: tolerance,
                              message: "A face drafted about a curved edge could not be fitted on one set of spans.")
        }
        let surface = BSplineSurface3D(uDegree: rows[0].degree, vDegree: 1, uKnots: rows[0].knots, vKnots: [0, 0, 1, 1],
                                       controlPoints: rows.map(\.controlPoints))
        try surface.validate(tolerance: tolerance)
        return .bSpline(surface)
    }

    /// A circular hinge on a reference whose normal along it runs through the circle's centre (a
    /// coaxial cylinder's or a sphere's arc): the ruled lines all pass through one point on the
    /// circle's axis, so the drafted surface is exactly the cone from it through the circle; nil
    /// for any other reference.
    private func cone(circle: Circle3D, start: Double, end: Double, reference: Surface3D, referenceSign: Double,
                      outward: Vector3D, tangent: Double) throws -> Surface3D? {
        let curve = Curve3D.circle(circle)
        var apexes: [Point3D] = []
        for fraction in [0.0, 0.5, 1.0] {
            let point = try curve.point(at: start + (end - start) * fraction, tolerance: tolerance)
            let pull = try (try SurfaceFootResolver().foot(of: point, on: reference, tolerance: tolerance).normal * referenceSign)
                .normalized(tolerance: 1e-300)
            let radial = try (point - circle.center).normalized(tolerance: tolerance.distance)
            // The pull along the radius, out (+1) or in (-1); any other leaves no common point.
            guard pull.cross(radial).length <= tolerance.angle else { return nil }
            let sense = pull.dot(radial) > 0 ? 1.0 : -1.0
            let across = try (outward - pull * outward.dot(pull)).normalized(tolerance: tolerance.distance)
            // Down the pull a radius (sense ±) reaches the centre's line: the apex.
            apexes.append(point + (pull * -1 + across * tangent) * (sense * circle.radius))
        }
        guard apexes.allSatisfy({ ($0 - apexes[0]).length <= tolerance.distance }) else { return nil }
        let apex = apexes[0]
        let height = (circle.center - apex).length
        guard height > tolerance.distance else { return nil }
        return .analytic(.cone(apex: apex, axis: try (circle.center - apex).normalized(tolerance: tolerance.distance),
                               halfAngle: atan2(circle.radius, height)))
    }
}
