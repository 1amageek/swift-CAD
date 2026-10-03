import Foundation
import CADCore
import CADGeometry
import CADIR
import CADModeling
import CADTopology

/// A face's surface as an exact B-spline on the face's own parameters, so its trimming curves
/// stay valid on it: what Raise Degree gives a face of a solid before raising it, its control
/// points then editable in the body (`FaceRebuildMethod.given`).
///
/// A B-spline face keeps its surface. A plane is affine in its parameters, so the degree (1, 1)
/// patch through its four corners over a rectangle holding the face is the plane itself: the
/// rectangle bounds every trimming curve, read exactly at the ends of straight ones, at the
/// control points of B-spline ones (their hull holds them) and otherwise at 65 samples widened by
/// a fiftieth of the face's extent each way.
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
            let corners = try [v.low, v.high].map { vv in try [u.low, u.high].map { uu in try surface.point(u: uu, v: vv, tolerance: tolerance) } }
            return BSplineSurface3D(uDegree: 1, vDegree: 1, uKnots: [u.low, u.low, u.high, u.high], vKnots: [v.low, v.low, v.high, v.high],
                                    controlPoints: corners)
        default:
            // FIXME(INCOMPLETE_IMPLEMENTATION): only planes and B-splines are given control points;
            // a cylinder, cone, sphere or torus face (exact as a rational B-spline) is refused here.
            // Production path: Rupa's Raise Degree on a face of a body that is not a B-spline
            // surface source. Complete when an analytic face is converted exactly, verified by a
            // cylinder's side raised and its control points moved.
            throw KernelError(phase: .evaluation, code: .unsupportedCapability, tolerance: tolerance,
                              message: "Only a planar or B-spline face is given control points.")
        }
    }
}
