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
    package enum Face: Sendable {
        /// The face's unit outward normal.
        case plane(normal: Vector3D)
        /// The face's surface and the sign turning its normal outward.
        case curved(surface: Surface3D, outwardSign: Double, angularAllowance: Double)
    }

    package let face: Face
    /// The sign that turns `n × C′` away from the face for the side's curve `C`.
    package let sign: Double
    package let order: SurfaceEdgeContinuity.Order
    package let tension: Double

    /// The angle the surface's normal may stray from a curved face's; zero for a plane.
    package var allowance: Double {
        if case let .curved(_, _, angularAllowance) = face { return angularAllowance }
        return 0
    }

    /// Whether rows built from `leavingDirections` meet the face exactly.
    package var isExact: Bool {
        if case .plane = face { return true }
        return false
    }

    /// The face's unit outward normal at `point` on the edge.
    package func normal(at point: Point3D, tolerance: ModelingTolerance) throws -> Vector3D {
        switch face {
        case let .plane(normal):
            return normal
        case let .curved(surface, outwardSign, _):
            let projected = try surface.parameterProjection(of: point, tolerance: tolerance)
            return try (surface.normal(u: projected.u, v: projected.v, tolerance: tolerance) * outwardSign)
                .normalized(tolerance: tolerance.distance)
        }
    }

    /// The rows leaving the face across `span`, one per control point: for a plane the unit
    /// directions at the control points' Greville abscissae, in the plane; beside a curved face the
    /// rows whose (rational) spline over `span`'s basis takes the unit leaving direction at each
    /// Greville abscissa.
    package func leavingDirections(along span: BSplineCurve3D, tolerance: ModelingTolerance) throws -> [Vector3D] {
        let degree = span.degree
        let grevilles = span.controlPoints.indices.map { span.knots[($0 + 1)...($0 + degree)].reduce(0, +) / Double(degree) }
        let targets = try grevilles.map { t -> Vector3D in
            let geometry = try span.differentialGeometry(at: t, tolerance: tolerance)
            return try (normal(at: geometry.position, tolerance: tolerance).cross(geometry.firstDerivative) * sign)
                .normalized(tolerance: tolerance.distance)
        }
        guard case .curved = face else { return targets }
        // Collocation: the (rational) basis functions at the Greville abscissae, each read as the
        // x coordinate of the span with a unit control point.
        let count = span.controlPoints.count
        var matrix: [Double] = []
        matrix.reserveCapacity(count * count)
        for t in grevilles {
            for column in 0..<count {
                let unit = BSplineCurve3D(degree: degree, knots: span.knots,
                    controlPoints: (0..<count).map { $0 == column ? Point3D(x: 1, y: 0, z: 0) : .origin }, weights: span.weights)
                matrix.append(try Curve3D.bSpline(unit).point(at: t, tolerance: tolerance).x)
            }
        }
        let qr = try SurfaceFittingQR(coefficients: matrix, rows: count, columns: count,
                                      relativeRankTolerance: 1e-12, maximumElements: 1 << 20)
        let x = try qr.solveFullRankLeastSquares(targets.map(\.x))
        let y = try qr.solveFullRankLeastSquares(targets.map(\.y))
        let z = try qr.solveFullRankLeastSquares(targets.map(\.z))
        return (0..<count).map { Vector3D(x: x[$0], y: y[$0], z: z[$0]) }
    }

    /// Certifies that `surface` along its `v`-boundary over `span` stays within the angular
    /// allowance of the curved face's normals; a plane needs no certificate. The certifier reads the
    /// two boundaries at equal fractions, so the face's side is the cubic spline through the face
    /// chart's projections of the span's points at the span's own fractions (unwrapped across a
    /// periodic seam), its position kept within eight distance tolerances of the span.
    package func certify(_ surface: BSplineSurface3D, boundaryV v: Double, span: BSplineCurve3D,
                         tolerance: ModelingTolerance, featureID: FeatureID) throws {
        guard case let .curved(faceSurface, _, allowance) = face else { return }
        guard case let .closed(u0, u1) = surface.uDomain, case let .closed(s0, s1) = span.domain else {
            throw KernelError(phase: .evaluation, code: .invalidInput, featureID: featureID, tolerance: tolerance,
                              message: "A continuous side's surface has an unbounded domain.")
        }
        let degree = 3, count = 32
        let knots = Array(repeating: 0.0, count: degree + 1)
            + (1..<(count - degree)).map { Double($0) / Double(count - degree) }
            + Array(repeating: 1.0, count: degree + 1)
        let grevilles = (0..<count).map { knots[($0 + 1)...($0 + degree)].reduce(0, +) / Double(degree) }
        var chart: [Point2D] = []
        for g in grevilles {
            let point = try Curve3D.bSpline(span).point(at: s0 + g * (s1 - s0), tolerance: tolerance)
            let projected = try faceSurface.parameterProjection(of: point, tolerance: tolerance)
            var next = Point2D(x: projected.u, y: projected.v)
            if let previous = chart.last {
                if case let .periodic(period) = faceSurface.uDomain { next.x += ((previous.x - next.x) / period).rounded() * period }
                if case let .periodic(period) = faceSurface.vDomain { next.y += ((previous.y - next.y) / period).rounded() * period }
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
        let pcurve = BSplineCurve2D(degree: degree, knots: knots, controlPoints: zip(x, y).map { Point2D(x: $0, y: $1) })
        let faceSide = SurfaceContinuitySamplingSide(surface: faceSurface, parameterCurve: .bSpline(pcurve))
        // The surface's normal faces the way the face's does where they meet.
        let middle = try surface.differentialGeometry(u: 0.5 * (u0 + u1), v: v, tolerance: tolerance)
        let faceMiddle = try faceSurface.parameterProjection(of: middle.position, tolerance: tolerance)
        let faceNormal = try faceSurface.normal(u: faceMiddle.u, v: faceMiddle.v, tolerance: tolerance)
        let surfaceSide = SurfaceContinuitySamplingSide(
            surface: .bSpline(surface), parameterCurve: .constantV(v: v, uStart: u0, uEnd: u1),
            frameOrientation: middle.normal.dot(faceNormal) >= 0 ? .forward : .reversed
        )
        _ = try SurfaceBoundaryContinuityEvaluator(modelingTolerance: tolerance).certify(
            first: surfaceSide, second: faceSide, requiredLevel: .tangentPlane,
            tolerances: SurfaceContinuityTolerances(positionDistance: tolerance.distance * 8, normalAngle: allowance, principalCurvature: 1),
            maximumIntervals: 4096, maximumDepth: 24
        )
    }
}

/// Resolves an edge continuity against the body: of the faces beside the edge, the one the surface
/// leaves toward the rest of it.
package struct ExactEdgeContinuitySupportResolver: Sendable {
    private let subshapeResolver: any StableSubshapeResolving

    package init(subshapeResolver: any StableSubshapeResolving = StableSubshapeResolver()) {
        self.subshapeResolver = subshapeResolver
    }

    /// The support for `continuity` at a side whose curve leaves `point` with derivative
    /// `derivative`, the rest of the surface lying toward `toward`.
    package func support(
        for continuity: SurfaceEdgeContinuity,
        point: Point3D,
        derivative: Vector3D,
        toward: Vector3D,
        context: EvaluationContext,
        featureID: FeatureID
    ) throws -> ExactEdgeContinuitySupport {
        let tolerance = context.tolerance
        let model = context.brep
        let scope = try BodyTopologyScope(bodyID: try context.bodyID(generatedBy: continuity.source), model: model)
        let resolved = try subshapeResolver.topologyReference(
            for: continuity.edge, model: model, subshapes: context.subshapes, lineage: context.lineage, tolerance: tolerance
        )
        guard case let .edge(edgeID) = resolved, scope.references.contains(.edge(edgeID)), let edge = model.edges[edgeID],
              let curve = model.geometry.curves[edge.curveID], let trim = edge.trim else {
            throw KernelError(phase: .evaluation, code: .missingReference, featureID: featureID, subshapeID: continuity.edge.subshapeID,
                              tolerance: tolerance, message: "A continuity edge did not resolve to an edge of its body.")
        }
        let projection = try curve.parameterProjection(of: point, tolerance: tolerance)
        guard (try curve.point(at: projection.parameter, tolerance: tolerance) - point).length <= tolerance.distance else {
            throw KernelError(phase: .evaluation, code: .invalidInput, featureID: featureID, tolerance: tolerance,
                              message: "A continuous side does not run along its edge.")
        }
        let along = try curve.differentialGeometry(at: projection.parameter, tolerance: tolerance).firstDerivative
            * (trim.endParameter >= trim.startParameter ? 1 : -1)
        var best: (outward: Vector3D, outwardNormal: Vector3D, face: Face, score: Double)?
        for case let .face(faceID) in scope.references {
            guard let face = model.faces[faceID] else { continue }
            for loopID in face.loops {
                guard let loop = model.loops[loopID] else { throw TopologyError.missingReference("A face's loop is missing.") }
                for coedge in loop.coedges where coedge.edgeID == edgeID {
                    guard let surface = model.geometry.surfaces[face.surfaceID] else {
                        throw TopologyError.missingReference("A face's surface is missing.")
                    }
                    let projected = try surface.parameterProjection(of: point, tolerance: tolerance)
                    let outwardNormal = try surface.normal(u: projected.u, v: projected.v, tolerance: tolerance)
                        * (face.orientation == .forward ? 1 : -1)
                    // The face lies to the left of its coedges about its outward normal.
                    let travel = along * (coedge.orientation == .forward ? 1 : -1)
                    let outward = try travel.cross(outwardNormal).normalized(tolerance: tolerance.distance)
                    let score = outward.dot(toward)
                    if best.map({ score > $0.score }) ?? true {
                        best = (outward, outwardNormal, face, score)
                    }
                }
            }
        }
        guard let best, let surface = model.geometry.surfaces[best.face.surfaceID] else {
            throw KernelError(phase: .evaluation, code: .invalidInput, featureID: featureID, tolerance: tolerance,
                              message: "A continuity edge borders no face of its body.")
        }
        let outwardSign: Double = best.face.orientation == .forward ? 1 : -1
        let face: ExactEdgeContinuitySupport.Face
        if let plane = try DefaultPlanarSurfaceResolver().exactPlane(for: surface, tolerance: tolerance) {
            face = .plane(normal: try (plane.normal * outwardSign).normalized(tolerance: tolerance.distance))
        } else {
            guard continuity.order == .tangent else {
                // FIXME(INCOMPLETE_IMPLEMENTATION): curvature continuity with a curved face needs
                // second-derivative rows matching the face's normal curvature across the edge,
                // which are not fitted, so it is refused. Production path:
                // ExactEdgeContinuitySupportResolver for every Loft section and Square side with
                // curvature continuity. Complete only when those rows are fitted and the
                // curvature certified, verified by a G2 loft from a cylinder's rim.
                throw KernelError(phase: .evaluation, code: .unsupportedCapability, featureID: featureID, tolerance: tolerance,
                                  message: "Curvature continuity is with a planar face.")
            }
            guard let allowance = continuity.angularAllowance else {
                throw KernelError(phase: .evaluation, code: .invalidInput, featureID: featureID, tolerance: tolerance,
                                  message: "Tangent continuity with a curved face needs an angular allowance.")
            }
            face = .curved(surface: surface, outwardSign: outwardSign, angularAllowance: allowance)
        }
        let across = best.outwardNormal.cross(derivative)
        guard across.length > tolerance.distance else {
            throw KernelError(phase: .evaluation, code: .invalidInput, featureID: featureID, tolerance: tolerance,
                              message: "A continuous side has no direction along its edge.")
        }
        return ExactEdgeContinuitySupport(
            face: face, sign: across.dot(best.outward) >= 0 ? 1 : -1,
            order: continuity.order, tension: continuity.tension
        )
    }
}
