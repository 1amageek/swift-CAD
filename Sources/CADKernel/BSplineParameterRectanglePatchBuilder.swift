import CADCore
import CADGeometry
import CADModeling
import CADTopology

/// The sewing patch of a B-spline surface bounded by its whole parameter rectangle: its four sides
/// run counterclockwise in parameter space, each its isoparametric B-spline curve exactly (so an
/// edge's length and bounds come from its own control points, not through the surface).
struct BSplineParameterRectanglePatchBuilder {
    func patch(
        _ surface: BSplineSurface3D,
        stableID: String,
        orientation: Orientation,
        parentSubshapeIDs: [SubshapeID],
        tolerance: ModelingTolerance
    ) throws -> BRepSewingFacePatch {
        guard let a = surface.uKnots.first, let b = surface.uKnots.last, let c = surface.vKnots.first, let d = surface.vKnots.last else {
            throw KernelError(phase: .geometry, code: .invalidInput, tolerance: tolerance, message: "A B-spline patch has no parameter rectangle.")
        }
        let wrapped = Surface3D.bSpline(surface)
        let corners = [SurfaceParameter(u: a, v: c), SurfaceParameter(u: b, v: c), SurfaceParameter(u: b, v: d), SurfaceParameter(u: a, v: d)]
        let sides: [SurfaceParameterCurve] = [
            .constantV(v: c, uStart: a, uEnd: b), .constantU(u: b, vStart: c, vEnd: d),
            .constantV(v: d, uStart: b, uEnd: a), .constantU(u: a, vStart: d, vEnd: c),
        ]
        let edges = try sides.enumerated().map { index, side -> BRepSewingEdge in
            let curve: BSplineCurve3D
            let (start, end): (Double, Double)
            switch side {
            case let .constantU(u, vStart, vEnd):
                curve = try surface.vIsoparametricCurve(atU: u, tolerance: tolerance)
                (start, end) = (vStart, vEnd)
            case let .constantV(v, uStart, uEnd):
                curve = try surface.uIsoparametricCurve(atV: v, tolerance: tolerance)
                (start, end) = (uStart, uEnd)
            default:
                throw KernelError(phase: .geometry, code: .invalidInput, tolerance: tolerance, message: "A patch side is not isoparametric.")
            }
            let next = corners[(index + 1) % 4]
            return BRepSewingEdge(
                stableID: "\(stableID):side:\(index)", curve: .bSpline(curve), startParameter: start, endParameter: end,
                startPoint: try wrapped.differentialGeometry(u: corners[index].u, v: corners[index].v, tolerance: tolerance).position,
                endPoint: try wrapped.differentialGeometry(u: next.u, v: next.v, tolerance: tolerance).position,
                surfaceParameterCurve: side, parentSubshapeIDs: parentSubshapeIDs
            )
        }
        return BRepSewingFacePatch(
            stableID: stableID, surface: wrapped, orientation: orientation,
            loops: [BRepSewingLoop(stableID: "\(stableID):outer", role: .outer, edges: edges)], parentSubshapeIDs: parentSubshapeIDs
        )
    }
}
