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
            let (u, v) = try extent(of: face, on: surface, in: model, tolerance: tolerance)
            let corners = try [v.low, v.high].map { vv in try [u.low, u.high].map { uu in try surface.point(u: uu, v: vv, tolerance: tolerance) } }
            return BSplineSurface3D(uDegree: 1, vDegree: 1, uKnots: [u.low, u.low, u.high, u.high], vKnots: [v.low, v.low, v.high, v.high],
                                    controlPoints: corners)
        case let .cylinder(cylinder):
            return try revolved(surface, origin: cylinder.origin, axis: cylinder.axis, profileIsArc: false,
                                extent: try extent(of: face, on: surface, in: model, tolerance: tolerance), tolerance: tolerance)
        case let .analytic(.cylinder(origin, axis, _)):
            return try revolved(surface, origin: origin, axis: axis, profileIsArc: false,
                                extent: try extent(of: face, on: surface, in: model, tolerance: tolerance), tolerance: tolerance)
        case let .analytic(.cone(apex, axis, _)):
            return try revolved(surface, origin: apex, axis: axis, profileIsArc: false,
                                extent: try extent(of: face, on: surface, in: model, tolerance: tolerance), tolerance: tolerance)
        case let .analytic(.sphere(center, _)):
            return try revolved(surface, origin: center, axis: .unitZ, profileIsArc: true,
                                extent: try extent(of: face, on: surface, in: model, tolerance: tolerance), tolerance: tolerance)
        case let .analytic(.torus(center, axis, _, _)):
            return try revolved(surface, origin: center, axis: axis, profileIsArc: true,
                                extent: try extent(of: face, on: surface, in: model, tolerance: tolerance), tolerance: tolerance)
        default:
            // FIXME(INCOMPLETE_IMPLEMENTATION): planes, surfaces of revolution and B-splines are
            // given control points; a procedural or ruled surface face is refused here. Production
            // path: Rupa's Raise Degree on such a face. Complete when every face kind is converted
            // exactly, verified by a swept face raised in place.
            throw KernelError(phase: .evaluation, code: .unsupportedCapability, tolerance: tolerance,
                              message: "Only a planar, revolved or B-spline face is given control points.")
        }
    }

    /// The rectangle of the face's own parameters holding every trimming curve.
    private func extent(of face: Face, on surface: Surface3D, in model: BRepModel, tolerance: ModelingTolerance) throws
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
        // Never past the surface's own domain (a sphere's poles).
        if case let .closed(low, high) = surface.uDomain { u = (max(u.low, low), min(u.high, high)) }
        if case let .closed(low, high) = surface.vDomain { v = (max(v.low, low), min(v.high, high)) }
        return (u, v)
    }

    /// A surface of revolution (u the angle about `axis` through `origin`; its profile along v a
    /// straight line for a cylinder or cone, a circular arc for a sphere or torus) over `extent`, as
    /// the exact rational B-spline: the profile at the extent's first angle as control points —
    /// its two ends, or arcs of at most a quarter turn whose middle control point is
    /// M + (M − Q) / cos θ weighted cos θ (M an arc's middle, Q its chord's, θ its half angle) —
    /// each turned about the axis the same way in u, its weights the products. A face closing round
    /// the axis puts the surface's two ends on its seam. The new surface is checked to lie on the old
    /// one.
    private func revolved(_ surface: Surface3D, origin: Point3D, axis: Vector3D, profileIsArc: Bool,
                          extent: (u: (low: Double, high: Double), v: (low: Double, high: Double)),
                          tolerance: ModelingTolerance) throws -> BSplineSurface3D {
        func arcs(_ span: Double) -> (count: Int, half: Double) {
            let count = max(1, Int((span / (Double.pi / 2) - 1e-9).rounded(.up)))
            return (count, span / Double(count) / 2)
        }
        func knots(_ count: Int) -> [Double] {
            var result = [0.0, 0.0, 0.0]
            for k in 1..<count { result += [Double(k), Double(k)] }
            return result + [Double(count), Double(count), Double(count)]
        }
        let uSpan = extent.u.high - extent.u.low
        guard uSpan <= 2 * Double.pi + 1e-9 else {
            throw KernelError(phase: .evaluation, code: .invalidInput, tolerance: tolerance, message: "A face turns more than once round its axis.")
        }
        // The profile at the first angle: its control points and weights along v.
        let u0 = extent.u.low
        var profile: [(point: Point3D, weight: Double)] = []
        let vKnots: [Double]
        let vDegree: Int
        // FIXME(INCOMPLETE_IMPLEMENTATION): a face reaching a pole of its surface (a sphere's
        // octant) would leave the new surface a side collapsed to that point, which the face's loop
        // does not run along; it is refused here. Production path: Rupa's Raise Degree on such a
        // face. Complete when a collapsed side is carried, verified by a ball's octant raised.
        for v in [extent.v.low, extent.v.high] {
            let a = try surface.point(u: u0, v: v, tolerance: tolerance)
            let b = try surface.point(u: u0 + min(1, uSpan), v: v, tolerance: tolerance)
            guard (a - b).length > tolerance.distance else {
                throw KernelError(phase: .evaluation, code: .unsupportedCapability, tolerance: tolerance,
                                  message: "A face reaching a pole of its surface is not given control points.")
            }
        }
        if profileIsArc {
            let (count, half) = arcs(extent.v.high - extent.v.low)
            for k in 0..<count {
                let a = extent.v.low + 2 * half * Double(k)
                let p0 = try surface.point(u: u0, v: a, tolerance: tolerance)
                let p2 = try surface.point(u: u0, v: a + 2 * half, tolerance: tolerance)
                let middle = try surface.point(u: u0, v: a + half, tolerance: tolerance)
                let chord = .origin + ((p0 - .origin) + (p2 - .origin)) * 0.5
                if k == 0 { profile.append((p0, 1)) }
                profile.append((middle + (middle - chord) / cos(half), cos(half)))
                profile.append((p2, 1))
            }
            vKnots = knots(count)
            vDegree = 2
        } else {
            profile = [(try surface.point(u: u0, v: extent.v.low, tolerance: tolerance), 1),
                       (try surface.point(u: u0, v: extent.v.high, tolerance: tolerance), 1)]
            vKnots = [extent.v.low, extent.v.low, extent.v.high, extent.v.high]
            vDegree = 1
        }
        // Which way u turns about the axis.
        var k = try axis.normalized(tolerance: tolerance.distance)
        func turned(_ vector: Vector3D, by angle: Double, about k: Vector3D) -> Vector3D {
            vector * cos(angle) + k.cross(vector) * sin(angle) + k * (k.dot(vector) * (1 - cos(angle)))
        }
        let vMiddle = (extent.v.low + extent.v.high) / 2
        let probe = try surface.point(u: u0, v: vMiddle, tolerance: tolerance)
        let probeHub = origin + k * (probe - origin).dot(k)
        let step = min(0.25, uSpan)
        let expected = try surface.point(u: u0 + step, v: vMiddle, tolerance: tolerance)
        if (probeHub + turned(probe - probeHub, by: step, about: k) - expected).length > (probeHub + turned(probe - probeHub, by: step, about: k * -1) - expected).length {
            k = k * -1
        }
        let (count, half) = arcs(uSpan)
        var rows: [[Point3D]] = []
        var weights: [[Double]] = []
        for (point, weight) in profile {
            let hub = origin + k * (point - origin).dot(k)
            let radial = point - hub
            var row: [Point3D] = [point]
            var rowWeights: [Double] = [weight]
            for segment in 0..<count {
                let a = 2 * half * Double(segment)
                row.append(hub + turned(radial, by: a + half, about: k) / cos(half))
                rowWeights.append(weight * cos(half))
                row.append(hub + turned(radial, by: a + 2 * half, about: k))
                rowWeights.append(weight)
            }
            rows.append(row)
            weights.append(rowWeights)
        }
        let result = BSplineSurface3D(uDegree: 2, vDegree: vDegree, uKnots: knots(count), vKnots: vKnots,
                                      controlPoints: rows, weights: weights)
        try result.validate(tolerance: tolerance)
        // The new surface on the old one: a grid of its points each within the distance tolerance.
        let new = Surface3D.bSpline(result)
        guard case let .closed(t0, t1) = new.vDomain else {
            throw KernelError(phase: .evaluation, code: .invalidInput, tolerance: tolerance, message: "A revolved surface has no v domain.")
        }
        for i in 0...(4 * count) {
            for j in 0...8 {
                let point = try new.point(u: Double(i) / 4, v: t0 + (t1 - t0) * Double(j) / 8, tolerance: tolerance)
                if case .outsideTolerance = try surface.parameterProjectionResult(of: point, tolerance: tolerance) {
                    throw KernelError(phase: .evaluation, code: .unsupportedCapability, tolerance: tolerance,
                                      message: "The face's surface is not the revolved one it was read as; it is not given control points.")
                }
            }
        }
        return result
    }
}
