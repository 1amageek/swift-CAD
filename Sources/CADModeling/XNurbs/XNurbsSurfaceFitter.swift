import Foundation
import CADCore
import CADGeometry
import CADIR

/// XNURBS over an N-sided opening: one sheet over the boundary's mean plane, trimmed by the
/// boundary. The plane is the loop's Newell normal through its centroid, its first axis the
/// projected boundary's principal direction, turned so the loop runs counterclockwise; the
/// projected boundary's bounding rectangle, widened by 5 %, maps affinely onto the unit parameter
/// square, so each boundary curve's trimming curve is its exact projection (its control points
/// mapped, its weights kept).
///
/// The sheet is a uniform clamped B-spline of degree 3 (5 at curvature order) with the given spans
/// each way, fitted by least squares: the flatness-weighted thin plate and membrane fairness over
/// the square, and the boundary's positions (Gauss points over each of its spans cut into twice
/// the sheet's spans) and guides' points where they project, weighted 10⁸ against it. Continuity takes further passes, each separable over the coordinates: the
/// cross-boundary derivative along each continuous curve held at the last pass's, its component
/// along the face's normal removed (G1), then its second derivative's normal component set to the
/// face's normal curvature across the side (G2). The result's deviation from the boundary
/// (position, and angle beside faces) is measured at 64 points per curve; satisfying tolerances
/// doubles the spans (up to 12) until both are met, and fails with the values reached otherwise.
package struct XNurbsSurfaceFitter {
    package struct Boundary {
        package var curve: BSplineCurve3D
        package var support: ExactEdgeContinuitySupport?

        package init(curve: BSplineCurve3D, support: ExactEdgeContinuitySupport? = nil) {
            self.curve = curve
            self.support = support
        }
    }

    package struct Result {
        package let surface: BSplineSurface3D
        /// Each boundary curve's trimming curve on the sheet, in the loop's order.
        package let pcurves: [BSplineCurve2D]
        package let positionDeviation: Double
        package let angleDeviation: Double
        package let spans: Int
    }

    package static let maximumSpans = 12
    private static let boundaryWeight = 1e8

    private let tolerance: ModelingTolerance

    package init(tolerance: ModelingTolerance) {
        self.tolerance = tolerance
    }

    package func fit(boundaries: [Boundary], guides: [BSplineCurve3D], flatness: Double, spans initialSpans: Int,
                     satisfying limits: (position: Double, angle: Double)?, featureID: FeatureID) throws -> Result {
        guard boundaries.count >= 2 else {
            throw failure(.invalidInput, "XNURBS frames an opening with two or more boundary curves.", featureID)
        }
        // The mean plane and the parameter map.
        let samples = try boundaries.flatMap { try points(of: $0.curve, count: 32).dropLast() }
        var normal = Vector3D.zero
        for (a, b) in zip(samples, samples.dropFirst() + [samples[0]]) {
            normal = normal + Vector3D(x: (a.y - b.y) * (a.z + b.z), y: (a.z - b.z) * (a.x + b.x), z: (a.x - b.x) * (a.y + b.y))
        }
        let unitNormal = try normal.normalized(tolerance: tolerance.distance * tolerance.distance)
        let centroid = Point3D.origin + samples.reduce(Vector3D.zero) { $0 + ($1 - .origin) } * (1 / Double(samples.count))
        let seed = abs(unitNormal.x) < 0.9 ? Vector3D(x: 1, y: 0, z: 0) : Vector3D(x: 0, y: 1, z: 0)
        let a1 = try (seed - unitNormal * seed.dot(unitNormal)).normalized(tolerance: 1e-12)
        let a2 = unitNormal.cross(a1)
        // The principal direction of the projected boundary.
        var (sxx, sxy, syy) = (0.0, 0.0, 0.0)
        for p in samples {
            let d = p - centroid
            let (x, y) = (d.dot(a1), d.dot(a2))
            sxx += x * x; sxy += x * y; syy += y * y
        }
        let angle = 0.5 * atan2(2 * sxy, sxx - syy)
        let e1 = a1 * cos(angle) + a2 * sin(angle)
        let e2 = unitNormal.cross(e1)
        func planar(_ p: Point3D) -> (Double, Double) { ((p - centroid).dot(e1), (p - centroid).dot(e2)) }
        let projected = samples.map(planar)
        var area = 0.0
        for (p, q) in zip(projected, projected.dropFirst() + [projected[0]]) { area += p.0 * q.1 - q.0 * p.1 }
        guard abs(area) > tolerance.distance * tolerance.distance else {
            throw failure(.invalidInput, "An XNURBS boundary encloses no area across its mean plane.", featureID)
        }
        // A clockwise loop is mirrored so the trimming loop runs counterclockwise.
        let flip = area < 0 ? -1.0 : 1.0
        let mapped = projected.map { ($0.0, $0.1 * flip) }
        try requireSimple(mapped, featureID: featureID)
        // The box holds every trimming curve's control points too (a rational arc's middle one lies
        // outside the arc), so each trimming curve lies inside the sheet's domain.
        let controls = boundaries.flatMap(\.curve.controlPoints).map(planar).map { ($0.0, $0.1 * flip) }
        let (xs, ys) = ((mapped + controls).map(\.0), (mapped + controls).map(\.1))
        guard let x0 = xs.min(), let x1 = xs.max(), let y0 = ys.min(), let y1 = ys.max() else {
            throw failure(.invalidInput, "An XNURBS boundary has no points.", featureID)
        }
        let (mx, my) = (0.05 * (x1 - x0), 0.05 * (y1 - y0))
        let box = (x0 - mx, x1 + mx, y0 - my, y1 + my)
        func parameter(_ p: Point3D) -> Point2D {
            let (x, y) = planar(p)
            return Point2D(x: (x - box.0) / (box.1 - box.0), y: (y * flip - box.2) / (box.3 - box.2))
        }
        let pcurves = boundaries.map { boundary in
            BSplineCurve2D(degree: boundary.curve.degree, knots: boundary.curve.knots,
                           controlPoints: boundary.curve.controlPoints.map(parameter), weights: boundary.curve.weights)
        }
        let guidePoints = try guides.flatMap { try points(of: $0, count: 32) }
        let guideParameters = guidePoints.map(parameter)
        guard guideParameters.allSatisfy({ (0...1).contains($0.x) && (0...1).contains($0.y) }) else {
            throw failure(.invalidInput, "An XNURBS guide reaches past the boundary's extent across its mean plane.", featureID)
        }

        let order = boundaries.contains { $0.support?.order == .curvature } ? 2 : boundaries.contains { $0.support != nil } ? 1 : 0
        var spans = max(1, initialSpans)
        while true {
            let surface = try fitted(boundaries: boundaries, pcurves: pcurves, guides: Array(zip(guidePoints, guideParameters)),
                                     flatness: flatness, spans: spans, degree: order == 2 ? 5 : 3, order: order, featureID: featureID)
            let (position, angleDeviation) = try deviation(of: surface, boundaries: boundaries, pcurves: pcurves)
            let met = limits.map { position <= $0.position && angleDeviation <= $0.angle } ?? true
            if met {
                return Result(surface: surface, pcurves: pcurves, positionDeviation: position, angleDeviation: angleDeviation, spans: spans)
            }
            guard spans < Self.maximumSpans, let limits else {
                throw failure(.classificationFailure,
                              "XNURBS could not meet its tolerances: \(position) m from the boundary and \(angleDeviation) rad beside its faces at \(spans) spans (asked \(limits.map { "\($0.position) m, \($0.angle) rad" } ?? "")).",
                              featureID)
            }
            spans = min(Self.maximumSpans, spans * 2)
        }
    }

    // MARK: - Fit

    private func fitted(boundaries: [Boundary], pcurves: [BSplineCurve2D], guides: [(Point3D, Point2D)], flatness: Double,
                        spans: Int, degree: Int, order: Int, featureID: FeatureID) throws -> BSplineSurface3D {
        let knots = Array(repeating: 0.0, count: degree + 1) + (1..<spans).map { Double($0) / Double(spans) }
            + Array(repeating: 1.0, count: degree + 1)
        let n = knots.count - degree - 1
        let basis = FairSurfaceSystem.Basis(knots: knots, degree: degree, count: n)
        let weight = Self.boundaryWeight
        // The boundary's Gauss points along each curve: (point on the curve, parameter on the sheet,
        // the inward direction across it on the sheet's parameters, the curve's support).
        var stations: [(point: Point3D, uv: Point2D, inward: Point2D, weight: Double, support: ExactEdgeContinuitySupport?)] = []
        for (boundary, pcurve) in zip(boundaries, pcurves) {
            guard case let .closed(lower, upper) = boundary.curve.domain else {
                throw failure(.invalidInput, "An XNURBS boundary curve is unbounded.", featureID)
            }
            // The curve's own spans, each cut into as many pieces as the sheet has spans across, so
            // the boundary is held as finely as the sheet can follow it.
            let knotsAlong = Array(Set(boundary.curve.knots.filter { $0 >= lower && $0 <= upper } + [lower, upper])).sorted()
            let breaks = zip(knotsAlong, knotsAlong.dropFirst()).flatMap { a, b in
                (0..<(2 * spans)).map { a + (b - a) * Double($0) / Double(2 * spans) }
            } + [upper]
            for (t, w) in try FairSurfaceSystem.gaussPoints(knots: breaks, count: degree + 2) {
                let point = try Curve3D.bSpline(boundary.curve).point(at: t, tolerance: tolerance)
                let jet = try pcurve.differentialGeometry(at: t, tolerance: tolerance)
                let (uv, tangent) = (jet.position, jet.firstDerivative)
                let length = (tangent.x * tangent.x + tangent.y * tangent.y).squareRoot()
                guard length > 0 else { throw failure(.invalidInput, "An XNURBS boundary curve stalls across its mean plane.", featureID) }
                stations.append((point, uv, Point2D(x: -tangent.y / length, y: tangent.x / length), w / (upper - lower), boundary.support))
            }
        }
        var previous: BSplineSurface3D?
        for pass in 0...order {
            var rows = FairSurfaceSystem()
            try rows.addFairness(uBasis: basis, vBasis: basis, flatness: flatness)
            for station in stations {
                let scale = (weight * station.weight).squareRoot()
                let bu = basis.derivatives(at: station.uv.x, order: 2), bv = basis.derivatives(at: station.uv.y, order: 2)
                rows.addScalar(FairSurfaceSystem.product(bu, bv, du: 0, dv: 0, nu: n).map { ($0.0, $0.1 * scale) },
                               target: [station.point.x * scale, station.point.y * scale, station.point.z * scale])
                guard pass > 0, let support = station.support, let last = previous else { continue }
                let (w0, w1) = (station.inward.x, station.inward.y)
                let local = try jet(last, basis: basis, u: station.uv.x, v: station.uv.y)
                var faceNormal = try support.normal(at: station.point, tolerance: tolerance)
                if faceNormal.dot(local.normal) < 0 { faceNormal = faceNormal * -1 }
                // Across the side: the cross derivative S_w, held in the face's tangent plane.
                let cross = local.tangentU * w0 + local.tangentV * w1
                let crossTarget = cross - faceNormal * cross.dot(faceNormal)
                let crossTerms = FairSurfaceSystem.product(bu, bv, du: 1, dv: 0, nu: n).map { ($0.0, $0.1 * w0 * scale) }
                    + FairSurfaceSystem.product(bu, bv, du: 0, dv: 1, nu: n).map { ($0.0, $0.1 * w1 * scale) }
                rows.addScalar(crossTerms, target: [crossTarget.x * scale, crossTarget.y * scale, crossTarget.z * scale])
                guard pass > 1, support.order == .curvature else { continue }
                // Its second derivative's normal component the face's normal curvature across the side.
                let second = local.secondDerivativeUU * (w0 * w0) + local.secondDerivativeUV * (2 * w0 * w1) + local.secondDerivativeVV * (w1 * w1)
                let curvature = try support.normalCurvature(at: station.point, along: cross, normal: faceNormal, tolerance: tolerance)
                let secondTarget = second - faceNormal * second.dot(faceNormal) + faceNormal * (curvature * cross.dot(cross))
                let secondTerms = FairSurfaceSystem.product(bu, bv, du: 2, dv: 0, nu: n).map { ($0.0, $0.1 * w0 * w0 * scale) }
                    + FairSurfaceSystem.product(bu, bv, du: 1, dv: 1, nu: n).map { ($0.0, $0.1 * 2 * w0 * w1 * scale) }
                    + FairSurfaceSystem.product(bu, bv, du: 0, dv: 2, nu: n).map { ($0.0, $0.1 * w1 * w1 * scale) }
                rows.addScalar(secondTerms, target: [secondTarget.x * scale, secondTarget.y * scale, secondTarget.z * scale])
            }
            if guides.isEmpty == false {
                let scale = (weight / Double(guides.count)).squareRoot()
                for (point, uv) in guides {
                    rows.addScalar(FairSurfaceSystem.product(basis.derivatives(at: uv.x, order: 0), basis.derivatives(at: uv.y, order: 0),
                                                             du: 0, dv: 0, nu: n).map { ($0.0, $0.1 * scale) },
                                   target: [point.x * scale, point.y * scale, point.z * scale])
                }
            }
            let free = Array(0..<(n * n))
            let solution = try rows.solve(free: free, column: free, fixedValues: [], featureID: featureID, failure: failure)
            let net = (0..<n).map { j in (0..<n).map { i in Point3D(x: solution[j * n + i][0], y: solution[j * n + i][1], z: solution[j * n + i][2]) } }
            let surface = BSplineSurface3D(uDegree: degree, vDegree: degree, uKnots: knots, vKnots: knots, controlPoints: net)
            try surface.validate(tolerance: tolerance)
            previous = surface
        }
        guard let previous else { throw failure(.invalidInput, "XNURBS made no sheet.", featureID) }
        return previous
    }

    /// The largest distance from the boundary to the sheet along its trimming curves, and the
    /// largest angle between the sheet's and the faces' normals beside continuous curves.
    private func deviation(of surface: BSplineSurface3D, boundaries: [Boundary], pcurves: [BSplineCurve2D]) throws -> (Double, Double) {
        var position = 0.0, angle = 0.0
        for (boundary, pcurve) in zip(boundaries, pcurves) {
            guard case let .closed(lower, upper) = boundary.curve.domain else { continue }
            for k in 0...64 {
                let t = lower + (upper - lower) * Double(k) / 64
                let point = try Curve3D.bSpline(boundary.curve).point(at: t, tolerance: tolerance)
                let uv = try pcurve.point(at: t, tolerance: tolerance)
                let basis = FairSurfaceSystem.Basis(knots: surface.uKnots, degree: surface.uDegree, count: surface.uControlPointCount)
                let local = try jet(surface, basis: basis, u: min(1, max(0, uv.x)), v: min(1, max(0, uv.y)))
                position = max(position, (local.position - point).length)
                if let support = boundary.support, k > 0, k < 64 {
                    let faceNormal = try support.normal(at: point, tolerance: tolerance)
                    angle = max(angle, acos(min(1, abs(faceNormal.dot(local.normal)))))
                }
            }
        }
        return (position, angle)
    }

    // MARK: - Helpers

    /// The polynomial sheet's point, derivatives to second order and unit normal at (u, v), from
    /// its basis (both directions share `basis`).
    private func jet(_ surface: BSplineSurface3D, basis: FairSurfaceSystem.Basis, u: Double, v: Double) throws
        -> (position: Point3D, tangentU: Vector3D, tangentV: Vector3D, secondDerivativeUU: Vector3D, secondDerivativeUV: Vector3D,
            secondDerivativeVV: Vector3D, normal: Vector3D) {
        let n = surface.uControlPointCount
        let bu = basis.derivatives(at: u, order: 2), bv = basis.derivatives(at: v, order: 2)
        func sum(_ du: Int, _ dv: Int) -> Vector3D {
            FairSurfaceSystem.product(bu, bv, du: du, dv: dv, nu: n).reduce(Vector3D.zero) {
                $0 + (surface.controlPoints[$1.0 / n][$1.0 % n] - .origin) * $1.1
            }
        }
        let (su, sv) = (sum(1, 0), sum(0, 1))
        let normal = try su.cross(sv).normalized(tolerance: tolerance.distance * tolerance.distance)
        return (.origin + sum(0, 0), su, sv, sum(2, 0), sum(1, 1), sum(0, 2), normal)
    }

    private func points(of curve: BSplineCurve3D, count: Int) throws -> [Point3D] {
        guard case let .closed(lower, upper) = curve.domain else {
            throw KernelError(phase: .geometry, code: .invalidInput, tolerance: tolerance, message: "An XNURBS curve is unbounded.")
        }
        return try (0...count).map { try Curve3D.bSpline(curve).point(at: lower + (upper - lower) * Double($0) / Double(count), tolerance: tolerance) }
    }

    /// Refuses a projected boundary that crosses itself (it would fold over the mean plane).
    private func requireSimple(_ polygon: [(Double, Double)], featureID: FeatureID) throws {
        let count = polygon.count
        func cross(_ o: (Double, Double), _ a: (Double, Double), _ b: (Double, Double)) -> Double {
            (a.0 - o.0) * (b.1 - o.1) - (a.1 - o.1) * (b.0 - o.0)
        }
        for i in 0..<count where i + 2 < count {
            let (a, b) = (polygon[i], polygon[(i + 1) % count])
            for j in (i + 2)..<count where !(i == 0 && j == count - 1) {
                let (c, d) = (polygon[j], polygon[(j + 1) % count])
                if cross(a, b, c) * cross(a, b, d) < 0 && cross(c, d, a) * cross(c, d, b) < 0 {
                    throw failure(.invalidInput, "An XNURBS boundary folds over its mean plane; it must project without crossing itself.", featureID)
                }
            }
        }
    }

    private func failure(_ code: KernelErrorCode, _ message: String, _ featureID: FeatureID) -> KernelError {
        KernelError(phase: .evaluation, code: code, featureID: featureID, tolerance: tolerance, message: message)
    }
}
