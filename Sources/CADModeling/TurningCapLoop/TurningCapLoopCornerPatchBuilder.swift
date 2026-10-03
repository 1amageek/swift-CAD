import Foundation
import CADCore
import CADGeometry
import CADIR

/// The patch closing a cap loop's blend where its walls turn from rising to falling at a sharp
/// corner `V`: the rising wall's band (filling its corner with the cap) and the falling wall's
/// band (cutting its corner away) both end on sections through `P`, where their cap contacts
/// meet, and the edge between the two walls, running down from `V`, is cut at `S`, the blend's
/// distance below the cap. The patch is bounded by the rising band's end section from `P` up to
/// `Q` on the rising wall, the falling band's end section from `P` down to `T` on the falling
/// wall, the falling wall's contact from `T` back to `S`, and a descent on the rising wall from
/// `Q` down to `S`. It is tangent continuous with both bands and with the falling wall (which the
/// descent makes possible by reaching `S` straight down the edge, in the falling wall's plane),
/// and meets the rising wall along the descent at the angle the walls meet at along the edge.
package struct TurningCapLoopCornerPatchBuilder {
    /// The angle the patch's normals may stray from a band's along their shared section. Where
    /// the two bands' sections leave `P` the patch cannot be tangent to both exactly — the
    /// filling band curves it up across its section and the cutting band down across its own, so
    /// the twist each asks for there differs — and it strays most within the first sixteenth of
    /// each section from `P`; elsewhere it keeps to a few ten-thousandths.
    package static let angularAllowance = 1e-2

    /// The fewest spans the patch's sides take, which brings the stray at `P` within the allowance.
    private static let minimumSpans = 16

    private let tolerance: ModelingTolerance

    package init(tolerance: ModelingTolerance) {
        self.tolerance = tolerance
    }

    /// The descent on the rising wall from `q` (above `foot`, the rising band's end on its loop
    /// edge, the blend's wall distance up) to `s` (below `vertex` the same distance): the wall's
    /// base from `foot` back to `vertex` (a line, or an arc of `arc`'s circle) traversed as
    /// `(1 − t)²` of the way from `vertex`, so it arrives at `vertex` with no speed along the base,
    /// its height falling evenly over the control net. A rational quartic lying on the wall
    /// exactly, tangent to the edge below `vertex` at `s`.
    package func descent(from q: Point3D, foot: Point3D, vertex: Point3D, to s: Point3D, arc: Circle3D?) throws -> BSplineCurve3D {
        // The base as a rational quadratic from the vertex (parameter 0) to the foot (1).
        let middle: Point3D
        let middleWeight: Double
        if let arc {
            let (a, b) = (vertex - arc.center, foot - arc.center)
            let cosine = max(-1, min(1, a.dot(b) / (a.length * b.length)))
            let half = acos(cosine) / 2
            guard half > tolerance.angle, half < Double.pi / 3 else {
                throw failure(.unsupportedCapability, "A blend's turning corner lies within a third of a turn of its arc's foot.")
            }
            let bisector = try (a + b).normalized(tolerance: tolerance.distance)
            middle = arc.center + bisector * (arc.radius / cos(half))
            middleWeight = cos(half)
        } else {
            middle = vertex + (foot - vertex) * 0.5
            middleWeight = 1
        }
        // With the base parameter (1 − t)², the quadratic's Bernstein functions are quartics of t
        // whose Bernstein coefficients weigh the base's homogeneous points: the foot at t = 0,
        // the vertex doubled at t = 1 (where the base stops).
        let homogeneous: [(point: Vector3D, weight: Double)] = [
            (foot - .origin, 1),
            ((middle - .origin) * middleWeight, middleWeight),
            ((vertex - .origin) * (2.0 / 3) + (middle - .origin) * (middleWeight / 3), 2.0 / 3 + middleWeight / 3),
            (vertex - .origin, 1),
            (vertex - .origin, 1),
        ]
        let rise = q - foot
        let fall = s - vertex
        guard rise.cross(fall).length <= tolerance.distance * max(rise.length, 1), rise.dot(fall) < 0 else {
            throw failure(.invalidInput, "A turning corner's descent runs from above the cap to below it along the cap's normal.")
        }
        // The heights fall evenly from the rise above the foot to the fall below the vertex.
        let points = homogeneous.enumerated().map { index, value -> Point3D in
            let base = Point3D.origin + value.point * (1 / value.weight)
            let fraction = Double(index) / 4
            return base + rise * (1 - fraction) + fall * fraction
        }
        let curve = BSplineCurve3D(degree: 4, knots: [0, 0, 0, 0, 0, 1, 1, 1, 1, 1], controlPoints: points,
                                   weights: homogeneous.map(\.weight))
        try curve.validate(tolerance: tolerance)
        return curve
    }

    /// The descent's trimming curve on the rising wall: its control points carried onto a
    /// plane's (affine) parameters, or on a cylinder a cubic spline through its parameters at
    /// even steps of the descent's own, the angle unwrapped along it.
    package func pcurve(of descent: BSplineCurve3D, on surface: Surface3D) throws -> SurfaceParameterCurve {
        switch surface {
        case .plane, .analytic(.plane):
            let projected = try descent.controlPoints.map { point -> Point2D in
                let uv = try surface.parameterProjection(of: point, tolerance: tolerance)
                return Point2D(x: uv.u, y: uv.v)
            }
            return .bSpline(BSplineCurve2D(degree: descent.degree, knots: descent.knots, controlPoints: projected,
                                           weights: descent.weights))
        case .cylinder, .analytic(.cylinder):
            break
        default:
            throw failure(.unsupportedCapability, "A turning corner's rising wall is a plane or a cylinder.")
        }
        let degree = 3, count = 64
        let knots = Array(repeating: 0.0, count: degree + 1)
            + (1..<(count - degree)).map { Double($0) / Double(count - degree) }
            + Array(repeating: 1.0, count: degree + 1)
        let grevilles = (0..<count).map { knots[($0 + 1)...($0 + degree)].reduce(0, +) / Double(degree) }
        var chart: [Point2D] = []
        for g in grevilles {
            let point = try Curve3D.bSpline(descent).point(at: g, tolerance: tolerance)
            let uv = try surface.parameterProjection(of: point, tolerance: tolerance)
            var next = Point2D(x: uv.u, y: uv.v)
            if let previous = chart.last, case let .periodic(period) = surface.uDomain {
                next.x += ((previous.x - next.x) / period).rounded() * period
            }
            chart.append(next)
        }
        var matrix: [Double] = []
        for g in grevilles {
            for column in 0..<count {
                let unit = BSplineCurve3D(degree: degree, knots: knots,
                                          controlPoints: (0..<count).map { $0 == column ? Point3D(x: 1, y: 0, z: 0) : .origin })
                matrix.append(try Curve3D.bSpline(unit).point(at: g, tolerance: tolerance).x)
            }
        }
        let qr = try SurfaceFittingQR(coefficients: matrix, rows: count, columns: count,
                                      relativeRankTolerance: 1e-12, maximumElements: 1 << 20)
        let x = try qr.solveFullRankLeastSquares(chart.map(\.x))
        let y = try qr.solveFullRankLeastSquares(chart.map(\.y))
        return .bSpline(BSplineCurve2D(degree: degree, knots: knots, controlPoints: zip(x, y).map { Point2D(x: $0, y: $1) }))
    }

    /// The corner patch: `bottom` the rising band's end section from `P` to `Q`, `left` the
    /// falling band's from `P` to `T`, `top` the falling wall's contact from `T` to `S`, `right`
    /// the descent from `Q` to `S`; tangent continuous with the bands within the allowance and
    /// with the falling wall's plane (unit outward normal `wallNormal`). The sides are taken as
    /// polynomial splines through their curves' points and tangents (within an eighth of the
    /// distance tolerance), so the surface is one polynomial tensor that refines until it meets
    /// the bands' curved tangent planes; the sides' ends and end tangents are the curves' own.
    package func surface(bottom: BSplineCurve3D, left: BSplineCurve3D, top: BSplineCurve3D, right: BSplineCurve3D,
                         risingBand: BSplineSurface3D, fallingBand: BSplineSurface3D, wallNormal: Vector3D,
                         featureID: FeatureID) throws -> BSplineSurface3D {
        // Opposite sides on one basis, which the surface keeps (tangent continuous at its knots).
        let across = max(Self.minimumSpans, try spans(bottom), try spans(top))
        let along = max(Self.minimumSpans, try spans(left), try spans(right))
        let (bottom, top) = (try hermite(bottom, spans: across), try hermite(top, spans: across))
        let (left, right) = (try hermite(left, spans: along), try hermite(right, spans: along))
        let corners = [bottom.controlPoints[0], bottom.controlPoints[bottom.controlPoints.count - 1],
                       top.controlPoints[0], top.controlPoints[top.controlPoints.count - 1]]
        let interior = Point3D.origin + corners.reduce(Vector3D.zero) { $0 + ($1 - .origin) } * 0.25
        /// The support of a side along a face: its leaving directions turned away from the face,
        /// into the patch.
        func support(_ face: ExactEdgeContinuitySupport.Face, along side: BSplineCurve3D) throws -> ExactEdgeContinuitySupport {
            let geometry = try side.differentialGeometry(at: 0.5, tolerance: tolerance)
            let probe = ExactEdgeContinuitySupport(face: face, sign: 1, order: .tangent, tension: 1)
            let leaving = try probe.normal(at: geometry.position, tolerance: tolerance).cross(geometry.firstDerivative)
            return ExactEdgeContinuitySupport(face: face, sign: leaving.dot(interior - geometry.position) >= 0 ? 1 : -1,
                                              order: .tangent, tension: 1)
        }
        func curved(_ band: BSplineSurface3D) -> ExactEdgeContinuitySupport.Face {
            .curved(surface: .bSpline(band), outwardSign: 1, angularAllowance: Self.angularAllowance, curvatureAllowance: nil)
        }
        return try ExactHermiteCoonsSurfaceBuilder(tolerance: tolerance).buildAllSides(
            bottom: bottom, top: top, left: left, right: right,
            bottomSupport: try support(curved(risingBand), along: bottom),
            topSupport: try support(.plane(normal: wallNormal), along: top),
            leftSupport: try support(curved(fallingBand), along: left),
            rightSupport: nil,
            featureID: featureID
        )
    }

    /// The fewest spans, halving from four up to 64, whose `hermite` spline stays within an
    /// eighth of the distance tolerance of `curve` at the spans' sixths.
    private func spans(_ curve: BSplineCurve3D) throws -> Int {
        guard case let .closed(t0, t1) = curve.domain else {
            throw failure(.invalidInput, "A corner patch's side is bounded.")
        }
        var count = 4
        while true {
            let spline = try hermite(curve, spans: count)
            var deviation = 0.0
            for k in 0..<(6 * count) {
                let fraction = (Double(k) + 0.5) / Double(6 * count)
                let exact = try Curve3D.bSpline(curve).point(at: t0 + (t1 - t0) * fraction, tolerance: tolerance)
                deviation = max(deviation, (try Curve3D.bSpline(spline).point(at: fraction, tolerance: tolerance) - exact).length)
            }
            if deviation <= tolerance.distance / 8 { return count }
            guard count < 64 else {
                throw failure(.classificationFailure, "A corner patch's side could not be followed by a polynomial spline.")
            }
            count *= 2
        }
    }

    /// `curve` over [0, 1] as a cubic spline of `spans` even spans, tangent continuous at its
    /// double knots: through its points with its derivatives at the knots (each span's Bézier
    /// handles a third of the span along them).
    private func hermite(_ curve: BSplineCurve3D, spans: Int) throws -> BSplineCurve3D {
        guard case let .closed(t0, t1) = curve.domain else {
            throw failure(.invalidInput, "A corner patch's side is bounded.")
        }
        let step = (t1 - t0) / Double(spans)
        let jets = try (0...spans).map { k in try curve.differentialGeometry(at: t0 + step * Double(k), tolerance: tolerance) }
        var points: [Point3D] = [jets[0].position]
        for k in 0..<spans {
            points.append(jets[k].position + jets[k].firstDerivative * (step / 3))
            points.append(jets[k + 1].position + jets[k + 1].firstDerivative * (-step / 3))
        }
        points.append(jets[spans].position)
        var knots = [0.0, 0.0, 0.0, 0.0]
        for k in 1..<spans { knots += [Double(k) / Double(spans), Double(k) / Double(spans)] }
        knots += [1, 1, 1, 1]
        let spline = BSplineCurve3D(degree: 3, knots: knots, controlPoints: points)
        try spline.validate(tolerance: tolerance)
        return spline
    }

    private func failure(_ code: KernelErrorCode, _ message: String) -> KernelError {
        KernelError(phase: .evaluation, code: code, tolerance: tolerance, message: message)
    }
}
