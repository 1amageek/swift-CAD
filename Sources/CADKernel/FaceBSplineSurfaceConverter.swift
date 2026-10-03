import Foundation
import CADCore
import CADGeometry
import CADIR
import CADModeling
import CADTopology

/// A face's surface as an exact B-spline holding the face: what Raise Degree gives a face of a
/// solid before raising it, its control points then editable in the body
/// (`FaceRebuildMethod.given`).
///
/// A B-spline face keeps its surface. A plane is affine in its parameters, so the degree (1, 1)
/// patch through its four corners over a rectangle holding the face is the plane itself, on the
/// face's own parameters: the rectangle bounds every trimming curve, read exactly at the ends of
/// straight ones, at the control points of B-spline ones (their hull holds them) and otherwise at
/// 65 samples widened by a fiftieth of the face's extent each way. A cylinder or cone face is the
/// exact rational surface over that rectangle (`revolved`), on parameters of its own.
public struct FaceBSplineSurfaceConverter {
    public init() {}

    /// The surface of the face `reference` names in `document`.
    public func surface(of reference: StableSubshapeReference, in document: EvaluatedDocument) throws -> BSplineSurface3D {
        let tolerance = document.configuration.tolerance
        guard case let .face(faceID) = try StableSubshapeResolver().topologyReference(
            for: reference, model: document.brep, subshapes: document.subshapes, lineage: document.lineage, tolerance: tolerance
        ) else {
            throw KernelError(phase: .evaluation, code: .invalidInput, tolerance: tolerance, message: "A surface is given to a face.")
        }
        return try surface(of: faceID, in: document.brep, tolerance: tolerance)
    }

    func surface(of faceID: FaceID, in model: BRepModel, tolerance: ModelingTolerance) throws -> BSplineSurface3D {
        guard let face = model.faces[faceID], let surface = model.geometry.surfaces[face.surfaceID] else {
            throw TopologyError.missingReference("The face to convert is missing.")
        }
        switch surface {
        case let .bSpline(spline):
            return spline
        case .plane:
            let (u, v) = try extent(of: face, in: model, tolerance: tolerance)
            let corners = try [v.low, v.high].map { vv in try [u.low, u.high].map { uu in try surface.point(u: uu, v: vv, tolerance: tolerance) } }
            return BSplineSurface3D(uDegree: 1, vDegree: 1, uKnots: [u.low, u.low, u.high, u.high], vKnots: [v.low, v.low, v.high, v.high],
                                    controlPoints: corners)
        case .cylinder, .analytic(.cylinder), .analytic(.cone):
            return try revolved(surface, extent: try extent(of: face, in: model, tolerance: tolerance), tolerance: tolerance)
        default:
            // FIXME(INCOMPLETE_IMPLEMENTATION): planes, cylinders, cones and B-splines are given
            // control points; a sphere or torus face (rational in both directions) is refused here.
            // Production path: Rupa's Raise Degree on such a face. Complete when a sphere's and a
            // torus's faces are converted exactly, verified by a rounded corner raised in place.
            throw KernelError(phase: .evaluation, code: .unsupportedCapability, tolerance: tolerance,
                              message: "Only a planar, cylindrical, conical or B-spline face is given control points.")
        }
    }

    /// The rectangle of the face's own parameters holding every trimming curve.
    private func extent(of face: Face, in model: BRepModel, tolerance: ModelingTolerance) throws
        -> (u: (low: Double, high: Double), v: (low: Double, high: Double)) {
        var u = (low: Double.infinity, high: -Double.infinity), v = u
        var widens = false
        func include(_ point: SurfaceParameter) {
            u = (min(u.low, point.u), max(u.high, point.u))
            v = (min(v.low, point.v), max(v.high, point.v))
        }
        for loopID in face.loops {
            for coedge in model.loops[loopID]?.coedges ?? [] {
                guard let pcurve = coedge.surfaceParameterCurve else {
                    throw KernelError(phase: .evaluation, code: .missingReference, tolerance: tolerance,
                                      message: "A face to convert has an edge without a trimming curve.")
                }
                switch pcurve {
                case .affine, .constantU, .constantV:
                    include(try pcurve.parameter(atNormalizedFraction: 0, tolerance: tolerance))
                    include(try pcurve.parameter(atNormalizedFraction: 1, tolerance: tolerance))
                case let .polyline(points):
                    points.forEach(include)
                case let .bSpline(curve):
                    curve.controlPoints.forEach { include(SurfaceParameter(u: $0.x, v: $0.y)) }
                default:
                    widens = true
                    for k in 0...64 { include(try pcurve.parameter(atNormalizedFraction: Double(k) / 64, tolerance: tolerance)) }
                }
            }
        }
        guard u.low < u.high, v.low < v.high else {
            throw KernelError(phase: .evaluation, code: .invalidInput, tolerance: tolerance, message: "A face to convert has no extent.")
        }
        if widens {
            let (du, dv) = ((u.high - u.low) / 50, (v.high - v.low) / 50)
            u = (u.low - du, u.high + du)
            v = (v.low - dv, v.high + dv)
        }
        return (u, v)
    }

    /// A surface whose u is the angle about an axis and along whose v it runs straight (a cylinder
    /// or a cone), over `extent`, as the exact rational B-spline of degree 2 in u — each v-circle cut
    /// into arcs of at most a quarter turn, an arc's middle control point at M + (M − Q) / cos θ
    /// (M its middle, Q its chord's, θ its half angle) weighted cos θ — and degree 1 in v. The face
    /// must not close round the axis (a seam's two sides would meet on one boundary), and the new
    /// surface is checked to lie on the old one.
    private func revolved(_ surface: Surface3D, extent: (u: (low: Double, high: Double), v: (low: Double, high: Double)),
                          tolerance: ModelingTolerance) throws -> BSplineSurface3D {
        let span = extent.u.high - extent.u.low
        // FIXME(INCOMPLETE_IMPLEMENTATION): a face closing round its axis (a drum's side, whose seam
        // edge both coedges use) is refused here; its periodic surface needs a seam on the new
        // surface's boundary. Production path: Rupa's Raise Degree on such a face. Complete when a
        // cylinder's whole side is raised, verified by a drum raised whole keeping its volume.
        guard span < 2 * Double.pi - 1e-9 else {
            throw KernelError(phase: .evaluation, code: .unsupportedCapability, tolerance: tolerance,
                              message: "A face closing round its axis is not given control points.")
        }
        let segments = max(1, Int((span / (Double.pi / 2) - 1e-9).rounded(.up)))
        let theta = span / Double(segments) / 2
        var rows: [[Point3D]] = []
        var weights: [[Double]] = []
        for v in [extent.v.low, extent.v.high] {
            var row: [Point3D] = []
            var rowWeights: [Double] = []
            for k in 0..<segments {
                let a = extent.u.low + 2 * theta * Double(k)
                let p0 = try surface.point(u: a, v: v, tolerance: tolerance)
                let p2 = try surface.point(u: a + 2 * theta, v: v, tolerance: tolerance)
                let middle = try surface.point(u: a + theta, v: v, tolerance: tolerance)
                let chord = .origin + ((p0 - .origin) + (p2 - .origin)) * 0.5
                if k == 0 { row.append(p0); rowWeights.append(1) }
                row.append(middle + (middle - chord) / cos(theta))
                rowWeights.append(cos(theta))
                row.append(p2)
                rowWeights.append(1)
            }
            rows.append(row)
            weights.append(rowWeights)
        }
        var uKnots = [0.0, 0.0, 0.0]
        for k in 1..<segments { uKnots += [Double(k), Double(k)] }
        uKnots += [Double(segments), Double(segments), Double(segments)]
        let result = BSplineSurface3D(uDegree: 2, vDegree: 1, uKnots: uKnots, vKnots: [extent.v.low, extent.v.low, extent.v.high, extent.v.high],
                                      controlPoints: rows, weights: weights)
        try result.validate(tolerance: tolerance)
        // The new surface on the old one: a grid of its points each within the distance tolerance.
        let new = Surface3D.bSpline(result)
        for i in 0...(4 * segments) {
            for j in 0...4 {
                let point = try new.point(u: Double(i) / 4, v: extent.v.low + (extent.v.high - extent.v.low) * Double(j) / 4, tolerance: tolerance)
                if case .outsideTolerance = try surface.parameterProjectionResult(of: point, tolerance: tolerance) {
                    throw KernelError(phase: .evaluation, code: .unsupportedCapability, tolerance: tolerance,
                                      message: "The face's surface does not turn about an axis along a straight line; it is not given control points.")
                }
            }
        }
        return result
    }
}
