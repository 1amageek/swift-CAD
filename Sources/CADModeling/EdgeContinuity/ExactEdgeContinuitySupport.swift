import Foundation
import CADCore
import CADGeometry
import CADIR
import CADTopology

/// The face a surface is tangent or curvature continuous with along a body edge (a Loft's end
/// section, a Square's side), and the directions leaving it across the edge.
///
/// A planar face is met exactly: every cross-boundary row in its plane keeps the surface's
/// derivative there. Beside a curved face the leaving direction `n(C) × C′` turns with the face's
/// normal, which no B-spline row follows exactly, so the rows interpolate it at the side's Greville
/// abscissae and the built surface is certified against the face within the continuity's angular
/// allowance; a consumer refines the side's basis until it is.
package struct ExactEdgeContinuitySupport: Sendable {
    /// Original incident topology retained independently of fitted leaving rows.
    package struct OriginalBoundary: Sendable {
        package let edgeID: EdgeID
        package let faceID: FaceID
        package let surface: Surface3D
        package let curve: Curve3D
        package let startParameter: Double
        package let endParameter: Double
        package let coedgeOrientation: Orientation
        package let parameterCurve: SurfaceParameterCurve?
        package let faceOrientation: Orientation
    }

    package enum Face: Sendable {
        /// The face's unit outward normal.
        case plane(normal: Vector3D)
        /// The face's surface, the sign turning its normal outward, and the allowances its normals
        /// and (for curvature order) its principal curvatures are met within.
        case curved(surface: Surface3D, outwardSign: Double, angularAllowance: Double, curvatureAllowance: Double?)
    }

    package let face: Face
    /// The sign that turns `n × C′` away from the face for the side's curve `C`.
    package let sign: Double
    package let order: SurfaceEdgeContinuity.Order
    package let tension: Double
    package let originalBoundary: OriginalBoundary?

    package init(face: Face, sign: Double, order: SurfaceEdgeContinuity.Order,
        tension: Double, originalBoundary: OriginalBoundary? = nil) {
        self.face = face; self.sign = sign; self.order = order
        self.tension = tension; self.originalBoundary = originalBoundary
    }

    /// The angle the surface's normal may stray from a curved face's; zero for a plane.
    package var allowance: Double {
        if case let .curved(_, _, angularAllowance, _) = face { return angularAllowance }
        return 0
    }

    /// Whether rows built from `leavingDirections` meet the face exactly.
    package var isExact: Bool {
        if case .plane = face { return true }
        return false
    }

    package func normal(at point: Point3D, tolerance: ModelingTolerance) throws -> Vector3D {
        var execution = try OriginalQueryExecution.independentGeometry()
        return try normal(at: point, tolerance: tolerance, using: &execution)
    }
    package func normalCurvature(at point: Point3D, along direction: Vector3D, normal: Vector3D,
        tolerance: ModelingTolerance) throws -> Double {
        var execution = try OriginalQueryExecution.independentGeometry()
        return try normalCurvature(at: point, along: direction, normal: normal, tolerance: tolerance, using: &execution)
    }
    package func leavingDirections(along span: BSplineCurve3D, tolerance: ModelingTolerance) throws -> [Vector3D] {
        var execution = try OriginalQueryExecution.independentGeometry()
        return try leavingDirections(along: span, tolerance: tolerance, using: &execution)
    }
    package func carriedRows(along span: BSplineCurve3D, start: Vector3D, end: Vector3D, entering: Bool,
        tolerance: ModelingTolerance) throws -> [Vector3D] {
        var execution = try OriginalQueryExecution.independentGeometry()
        return try carriedRows(along: span, start: start, end: end, entering: entering, tolerance: tolerance, using: &execution)
    }
    package func curvatureRows(along span: BSplineCurve3D, rows: [Vector3D], tolerance: ModelingTolerance) throws -> [Vector3D] {
        var execution = try OriginalQueryExecution.independentGeometry()
        return try curvatureRows(along: span, rows: rows, tolerance: tolerance, using: &execution)
    }
    package func certify(_ surface: BSplineSurface3D, boundaryV v: Double, span: BSplineCurve3D,
        tolerance: ModelingTolerance, featureID: FeatureID) throws {
        var execution = try OriginalQueryExecution.independentGeometry()
        try certify(surface, boundaryV: v, span: span, tolerance: tolerance, featureID: featureID, using: &execution)
    }
    package func certify(_ surface: BSplineSurface3D, along boundary: Boundary, span: BSplineCurve3D,
        tolerance: ModelingTolerance, featureID: FeatureID) throws {
        var execution = try OriginalQueryExecution.independentGeometry()
        try certify(surface, along: boundary, span: span, tolerance: tolerance, featureID: featureID, using: &execution)
    }

    /// The face's unit outward normal at `point` on the edge.
    package func normal(at point: Point3D, tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution) throws -> Vector3D {
        try execution.consumeWork(1)
        switch face {
        case let .plane(normal):
            return normal
        case let .curved(surface, outwardSign, _, _):
            let projected = try surface.parameterProjection(of: point, tolerance: tolerance, using: &execution)
            return try (surface.normal(u: projected.u, v: projected.v, tolerance: tolerance, using: &execution) * outwardSign)
                .normalized(tolerance: tolerance.distance)
        }
    }

    /// The face's normal curvature at `point` along the tangent direction nearest `direction`,
    /// signed about `normal` (a unit normal of the face there): zero for a plane.
    package func normalCurvature(at point: Point3D, along direction: Vector3D, normal: Vector3D,
                                 tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution) throws -> Double {
        try execution.consumeWork(1)
        guard case let .curved(surface, _, _, _) = face else { return 0 }
        let projected = try surface.parameterProjection(of: point, tolerance: tolerance, using: &execution)
        let geometry = try surface.differentialGeometry(u: projected.u, v: projected.v, tolerance: tolerance, using: &execution)
        let (su, sv) = (geometry.tangentU, geometry.tangentV)
        let (e, f, g) = (su.dot(su), su.dot(sv), sv.dot(sv))
        let determinant = e * g - f * f
        guard determinant > 0 else {
            throw KernelError(phase: .geometry, code: .invalidInput, tolerance: tolerance, message: "A degenerate face has no curvature.")
        }
        let (p, q) = (direction.dot(su), direction.dot(sv))
        let (a, b) = ((g * p - f * q) / determinant, (e * q - f * p) / determinant)
        let first = e * a * a + 2 * f * a * b + g * b * b
        guard first > 0 else {
            throw KernelError(phase: .geometry, code: .invalidInput, tolerance: tolerance, message: "A curvature direction lies off the face.")
        }
        return (geometry.secondDerivativeUU.dot(normal) * a * a + 2 * geometry.secondDerivativeUV.dot(normal) * a * b
            + geometry.secondDerivativeVV.dot(normal) * b * b) / first
    }

    /// The rows leaving the face across `span`, one per control point: for a plane the unit
    /// directions at the control points' Greville abscissae, in the plane; beside a curved face the
    /// rows whose (rational) spline over `span`'s basis takes the unit leaving direction at each
    /// Greville abscissa.
    package func leavingDirections(along span: BSplineCurve3D, tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution) throws -> [Vector3D] {
        try execution.consumeWork(1)
        let degree = span.degree
        try execution.retainStorage(count: span.controlPointCount, stride: MemoryLayout<Double>.stride)
        let grevilles = try span.controlPoints.indices.map { index in
            try execution.consumeWork(1)
            return try span.knots[(index + 1)...(index + degree)].reduce(0.0) { sum, knot in
                try execution.consumeWork(1); return sum + knot
            } / Double(degree)
        }
        try execution.retainStorage(count: grevilles.count, stride: MemoryLayout<Vector3D>.stride)
        let targets = try grevilles.map { t -> Vector3D in
            let geometry = try span.differentialGeometry(at: t, tolerance: tolerance, using: &execution)
            return try (normal(at: geometry.position, tolerance: tolerance, using: &execution).cross(geometry.firstDerivative) * sign)
                .normalized(tolerance: tolerance.distance)
        }
        guard case .curved = face else { return targets }
        return try interpolating(targets, over: span, at: grevilles, tolerance: tolerance, using: &execution)
    }

    /// The rows leaving a curved face across `span` from the corner derivative `start` (at its
    /// start) to `end`, one per control point: the (rational) spline over `span`'s basis taking,
    /// at each Greville abscissa, the unit leaving direction (turned back when `entering`) and the
    /// side's unit tangent there, weighed by the corners' parts along each varying evenly between
    /// them — the leaving part times the tension — so it stays in the face's tangent planes, which
    /// turn along the side, where a corner's derivative carried unchanged would leave them.
    package func carriedRows(along span: BSplineCurve3D, start: Vector3D, end: Vector3D, entering: Bool,
                             tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution) throws -> [Vector3D] {
        try execution.consumeWork(1)
        let degree = span.degree
        try execution.retainStorage(count: span.controlPointCount, stride: MemoryLayout<Double>.stride)
        let grevilles = try span.controlPoints.indices.map { index in
            try execution.consumeWork(1)
            return try span.knots[(index + 1)...(index + degree)].reduce(0.0) { sum, knot in
                try execution.consumeWork(1); return sum + knot
            } / Double(degree)
        }
        try execution.retainStorage(count: grevilles.count, stride: MemoryLayout<(Vector3D, Vector3D)>.stride)
        let frames = try grevilles.map { t -> (leaving: Vector3D, tangent: Vector3D) in
            let geometry = try span.differentialGeometry(at: t, tolerance: tolerance, using: &execution)
            let leaving = try (normal(at: geometry.position, tolerance: tolerance, using: &execution).cross(geometry.firstDerivative) * (sign * (entering ? -1 : 1)))
                .normalized(tolerance: tolerance.distance)
            return (leaving, try geometry.firstDerivative.normalized(tolerance: tolerance.distance))
        }
        let last = frames.count - 1
        let (a0, b0) = (start.dot(frames[0].leaving), start.dot(frames[0].tangent))
        let (a1, b1) = (end.dot(frames[last].leaving), end.dot(frames[last].tangent))
        try execution.retainStorage(count: grevilles.count, stride: MemoryLayout<Vector3D>.stride)
        let targets = try grevilles.indices.map { i -> Vector3D in
            try execution.consumeWork(1)
            let g = (grevilles[i] - grevilles[0]) / (grevilles[last] - grevilles[0])
            let leaving = (a0 + (a1 - a0) * g) * (i == 0 || i == last ? 1 : tension)
            return frames[i].leaving * leaving + frames[i].tangent * (b0 + (b1 - b0) * g)
        }
        var rows = try interpolating(targets, over: span, at: grevilles, tolerance: tolerance, using: &execution)
        rows[0] = start
        rows[last] = end
        return rows
    }

    /// The second-derivative rows across `span` for curvature continuity: zero beside a plane (its
    /// curvature is nil), beside a curved face the rows interpolating n·II(D, D) at the Greville
    /// abscissae — the face's normal curvature along the cross-boundary derivative `D` that the
    /// (rational) spline of `rows` takes there, which is all curvature continuity adds once the
    /// side lies on the face and `D` in its tangent planes.
    package func curvatureRows(along span: BSplineCurve3D, rows: [Vector3D], tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution) throws -> [Vector3D] {
        try execution.consumeWork(1)
        guard case let .curved(surface, outwardSign, _, _) = face else {
            try execution.retainStorage(count: rows.count, stride: MemoryLayout<Vector3D>.stride)
            return Array(repeating: .zero, count: rows.count)
        }
        let degree = span.degree
        try execution.retainStorage(count: span.controlPointCount, stride: MemoryLayout<Double>.stride)
        let grevilles = try span.controlPoints.indices.map { index in
            try execution.consumeWork(1)
            return try span.knots[(index + 1)...(index + degree)].reduce(0.0) { sum, knot in
                try execution.consumeWork(1); return sum + knot
            } / Double(degree)
        }
        let matrix = try basis(of: span, at: grevilles, tolerance: tolerance, using: &execution)
        let count = rows.count
        try execution.retainStorage(count: grevilles.count, stride: MemoryLayout<Vector3D>.stride)
        let targets = try grevilles.enumerated().map { i, t -> Vector3D in
            try execution.consumeWork(1)
            var derivative = Vector3D.zero
            for j in 0..<count { try execution.consumeWork(1); derivative = derivative + rows[j] * matrix[i * count + j] }
            let point = try Curve3D.bSpline(span).point(at: t, tolerance: tolerance, using: &execution)
            let projected = try surface.parameterProjection(of: point, tolerance: tolerance, using: &execution)
            let geometry = try surface.differentialGeometry(u: projected.u, v: projected.v, tolerance: tolerance, using: &execution)
            let normal = try (geometry.normal * outwardSign).normalized(tolerance: tolerance.distance)
            // D in the chart's tangents: D = a·Su + b·Sv.
            let (su, sv) = (geometry.tangentU, geometry.tangentV)
            let (e, f, g) = (su.dot(su), su.dot(sv), sv.dot(sv))
            let determinant = e * g - f * f
            guard abs(determinant) > tolerance.relative * e * g else {
                throw KernelError(phase: .evaluation, code: .invalidInput, tolerance: tolerance,
                                  message: "A curved face's chart is singular where its curvature is read.")
            }
            let (p, q) = (derivative.dot(su), derivative.dot(sv))
            let a = (p * g - q * f) / determinant, b = (q * e - p * f) / determinant
            let second = geometry.secondDerivativeUU * (a * a) + geometry.secondDerivativeUV * (2 * a * b) + geometry.secondDerivativeVV * (b * b)
            return normal * second.dot(normal)
        }
        return try interpolating(targets, over: span, at: grevilles, tolerance: tolerance, using: &execution)
    }

    /// The (rational) basis functions of `span` at `parameters`, row by row, each read as the x
    /// coordinate of the span with a unit control point.
    private func basis(of span: BSplineCurve3D, at parameters: [Double], tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution) throws -> [Double] {
        try execution.consumeWork(1)
        let count = span.controlPoints.count
        try execution.retainStorage(count: continuityConstructionScalarCount(parameters.count, count, multiply: true), stride: MemoryLayout<Double>.stride)
        var matrix: [Double] = []
        matrix.reserveCapacity(parameters.count * count)
        for t in parameters {
            for column in 0..<count {
                try execution.consumeWork(1)
                try execution.retainStorage(count: count, stride: MemoryLayout<Point3D>.stride)
                let unit = BSplineCurve3D(degree: span.degree, knots: span.knots,
                    controlPoints: (0..<count).map { $0 == column ? Point3D(x: 1, y: 0, z: 0) : .origin }, weights: span.weights)
                matrix.append(try Curve3D.bSpline(unit).point(at: t, tolerance: tolerance, using: &execution).x)
            }
        }
        return matrix
    }

    /// The rows whose (rational) spline over `span`'s basis takes `targets` at `parameters`.
    private func interpolating(_ targets: [Vector3D], over span: BSplineCurve3D, at parameters: [Double],
                               tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution) throws -> [Vector3D] {
        try execution.consumeWork(1)
        let count = span.controlPoints.count
        try execution.retainStorage(count: continuityConstructionScalarCount(count, 3, multiply: true), stride: MemoryLayout<Double>.stride)
        try execution.retainStorage(count: count, stride: MemoryLayout<Vector3D>.stride)
        let qr = try SurfaceFittingQR(coefficients: try basis(of: span, at: parameters, tolerance: tolerance, using: &execution),
                                      rows: count, columns: count, relativeRankTolerance: 1e-12, maximumElements: 1 << 20, using: &execution)
        let x = try qr.solveFullRankLeastSquares(targets.map(\.x), using: &execution)
        let y = try qr.solveFullRankLeastSquares(targets.map(\.y), using: &execution)
        let z = try qr.solveFullRankLeastSquares(targets.map(\.z), using: &execution)
        return (0..<count).map { Vector3D(x: x[$0], y: y[$0], z: z[$0]) }
    }

    /// Construction-stage check only; a subsequently corrected side needs a final original-law certificate.
    /// Certifies that `surface` along its `v`-boundary over `span` stays within the angular
    /// allowance of the curved face's normals; a plane needs no certificate. The certifier reads the
    /// two boundaries at equal fractions, so the face's side is the cubic spline through the face
    /// chart's projections of the span's points at the span's own fractions (unwrapped across a
    /// periodic seam), its position kept within eight distance tolerances of the span.
    package func certify(_ surface: BSplineSurface3D, boundaryV v: Double, span: BSplineCurve3D,
                         tolerance: ModelingTolerance, featureID: FeatureID, using execution: inout OriginalQueryExecution) throws {
        try execution.consumeWork(1)
        try certify(surface, along: .v(v), span: span, tolerance: tolerance, featureID: featureID, using: &execution)
    }

    /// A boundary of a surface: the u-isocurve at a v value, or the v-isocurve at a u value.
    package enum Boundary: Sendable {
        case v(Double)
        case u(Double)
    }

    /// Final source check, independent of the native construction-stage certificate.
    package func certify(surface: Surface3D, along boundary: Boundary,
        originalSpan: OriginalCurveRootSpan3D, tolerance: ModelingTolerance,
        featureID: FeatureID, using execution: inout OriginalQueryExecution) throws {
        try execution.consumeWork(1)
        guard let originalBoundary else {
            throw KernelError(phase: .evaluation, code: .missingReference, featureID: featureID,
                tolerance: tolerance, message: "Final edge continuity requires its original incident topology.")
        }
        switch face {
        case .plane:
            try OriginalPlanarEdgeContinuityCertifier().certify(surface: surface, along: boundary,
                originalSpan: originalSpan, support: originalBoundary, order: order,
                tolerance: tolerance, featureID: featureID, using: &execution)
        case .curved:
            // FIXME(INCOMPLETE_IMPLEMENTATION): Loft final corrected source reaches
            // this curved-support branch. Its original coedge parameter transport
            // and bounded final position/normal/curvature issuer must share the
            // feature admission; the fitted native candidate chart is insufficient.
            throw KernelError(phase: .evaluation, code: .unsupportedCapability, featureID: featureID,
                tolerance: tolerance, message: "Final curved edge continuity requires its retained original coedge transport and bounded source certificate.")
        }
    }

    // FIXME(INCOMPLETE_IMPLEMENTATION): Loft and surface-fill construction still use this candidate-only check.
    // Final corrected surfaces require their actual original jets and retained coedge parameter transport;
    // this fitted chart certificate cannot authorize final original-boundary continuity or publication.
    package func certify(_ surface: BSplineSurface3D, along boundary: Boundary, span: BSplineCurve3D,
                         tolerance: ModelingTolerance, featureID: FeatureID, using execution: inout OriginalQueryExecution) throws {
        try execution.consumeWork(1)
        guard case let .curved(faceSurface, _, allowance, curvatureAllowance) = face else { return }
        guard case let .closed(u0, u1) = surface.uDomain, case let .closed(v0, v1) = surface.vDomain,
              case let .closed(s0, s1) = span.domain else {
            throw KernelError(phase: .evaluation, code: .invalidInput, featureID: featureID, tolerance: tolerance,
                              message: "A continuous side's surface has an unbounded domain.")
        }
        let degree = 3, count = 32
        try execution.retainStorage(count: count + degree + 1, stride: MemoryLayout<Double>.stride)
        try execution.retainStorage(count: count, stride: MemoryLayout<Double>.stride)
        try execution.retainStorage(count: count, stride: MemoryLayout<Point2D>.stride)
        let knots = Array(repeating: 0.0, count: degree + 1)
            + (1..<(count - degree)).map { Double($0) / Double(count - degree) }
            + Array(repeating: 1.0, count: degree + 1)
        let grevilles = (0..<count).map { knots[($0 + 1)...($0 + degree)].reduce(0, +) / Double(degree) }
        var chart: [Point2D] = []
        for g in grevilles {
            try execution.consumeWork(1)
            let point = try Curve3D.bSpline(span).point(at: s0 + g * (s1 - s0), tolerance: tolerance, using: &execution)
            let projected = try faceSurface.parameterProjection(of: point, tolerance: tolerance, using: &execution)
            var next = Point2D(x: projected.u, y: projected.v)
            if let previous = chart.last {
                if case let .periodic(period) = faceSurface.uDomain { next.x += ((previous.x - next.x) / period).rounded() * period }
                if case let .periodic(period) = faceSurface.vDomain { next.y += ((previous.y - next.y) / period).rounded() * period }
            }
            chart.append(next)
        }
        try execution.retainStorage(count: count * count, stride: MemoryLayout<Double>.stride)
        var matrix: [Double] = []
        for g in grevilles {
            for column in 0..<count {
                try execution.consumeWork(1)
                try execution.retainStorage(count: count, stride: MemoryLayout<Point3D>.stride)
                let unit = BSplineCurve3D(degree: degree, knots: knots,
                    controlPoints: (0..<count).map { $0 == column ? Point3D(x: 1, y: 0, z: 0) : .origin })
                matrix.append(try Curve3D.bSpline(unit).point(at: g, tolerance: tolerance, using: &execution).x)
            }
        }
        let qr = try SurfaceFittingQR(coefficients: matrix, rows: count, columns: count,
                                      relativeRankTolerance: 1e-12, maximumElements: 1 << 20, using: &execution)
        // The chart lies in the face's domain; its fitted control points are kept there too, so an
        // edge along the domain's boundary (projected exactly onto it) is not rounded off it.
        func clamped(_ values: [Double], to domain: ParameterDomain) -> [Double] {
            guard case let .closed(lower, upper) = domain else { return values }
            return values.map { min(upper, max(lower, $0)) }
        }
        try execution.retainStorage(count: count * 6, stride: MemoryLayout<Double>.stride)
        try execution.retainStorage(count: count, stride: MemoryLayout<Point2D>.stride)
        let x = clamped(try qr.solveFullRankLeastSquares(chart.map(\.x), using: &execution), to: faceSurface.uDomain)
        let y = clamped(try qr.solveFullRankLeastSquares(chart.map(\.y), using: &execution), to: faceSurface.vDomain)
        let pcurve = BSplineCurve2D(degree: degree, knots: knots, controlPoints: zip(x, y).map { Point2D(x: $0, y: $1) })
        let faceSide = SurfaceContinuitySamplingSide(surface: faceSurface, parameterCurve: .bSpline(pcurve))
        // The surface's normal faces the way the face's does where they meet.
        let (middleU, middleV, isocurve): (Double, Double, SurfaceParameterCurve)
        switch boundary {
        case let .v(v): (middleU, middleV, isocurve) = (0.5 * (u0 + u1), v, .constantV(v: v, uStart: u0, uEnd: u1))
        case let .u(u): (middleU, middleV, isocurve) = (u, 0.5 * (v0 + v1), .constantU(u: u, vStart: v0, vEnd: v1))
        }
        let middle = try surface.differentialGeometry(u: middleU, v: middleV, tolerance: tolerance, using: &execution)
        let faceMiddle = try faceSurface.parameterProjection(of: middle.position, tolerance: tolerance, using: &execution)
        let faceNormal = try faceSurface.normal(u: faceMiddle.u, v: faceMiddle.v, tolerance: tolerance, using: &execution)
        let surfaceSide = SurfaceContinuitySamplingSide(
            surface: .bSpline(surface), parameterCurve: isocurve,
            frameOrientation: middle.normal.dot(faceNormal) >= 0 ? .forward : .reversed
        )
        _ = try SurfaceBoundaryContinuityEvaluator(modelingTolerance: tolerance).certify(
            first: surfaceSide, second: faceSide, requiredLevel: order == .curvature ? .curvature : .tangentPlane,
            tolerances: SurfaceContinuityTolerances(positionDistance: tolerance.distance * 8, normalAngle: allowance,
                                                    principalCurvature: curvatureAllowance ?? 1),
            maximumIntervals: 4096, maximumDepth: 24, using: &execution)
    }
}

// Element counts are checked before the caller admits their typed storage bytes.
func continuityConstructionScalarCount(
    _ a: Int, _ b: Int, multiply: Bool = false
) throws(ExactScalarFailure) -> Int {
    let result = multiply ? a.multipliedReportingOverflow(by: b) : a.addingReportingOverflow(b)
    guard a >= 0, b >= 0, !result.overflow else { throw .countOverflow }
    return result.partialValue
}
