import CADCore
import CADGeometry
import CADIR
import CADModeling
import CADTopology

/// The pieces of a parameter curve that lie inside a face, each an exact edge on the face whose
/// ends lie on the face's boundary: the curve is split wherever it crosses one of the face's
/// edges, and a piece is kept when its middle lies inside the face. A piece that closes on
/// itself is halved, since an edge must join two vertices. A curve that runs along one of the
/// face's own edges has nothing to imprint there: it is refused, or yields nothing when the
/// caller expects such curves.
struct BRepFaceCurveClipper {
    /// What a curve that runs along one of the face's own edges yields.
    enum AlongEdge {
        case refuse
        case yieldNothing
    }

    func clip(
        _ parameterCurve: SurfaceParameterCurve,
        to faceID: FaceID,
        stableID: String,
        parentSubshapeIDs: [SubshapeID],
        model: BRepModel,
        sourceSubshapes: [SubshapeID: TopologyReference],
        alongEdge: AlongEdge = .refuse,
        tolerance: ModelingTolerance
    ) throws -> [BRepSewingEdge] {
        guard let face = model.faces[faceID], let surface = model.geometry.surfaces[face.surfaceID] else {
            throw failure(.missingReference, tolerance, "The face to imprint on is missing.")
        }
        let candidate = try Self.edge(
            parameterCurve, on: surface, stableID: stableID, parentSubshapeIDs: parentSubshapeIDs, tolerance: tolerance
        )
        let trimEdges = try SourceBRepFacePatchBuilder().build(
            faceID: faceID, stableID: "\(stableID):face", from: model, sourceSubshapes: sourceSubshapes, tolerance: tolerance
        ).patch.loops.flatMap(\.edges)
        var crossings: [Point3D] = []
        let intersector = ExactTrimEdgeIntersector()
        for trimEdge in trimEdges {
            switch try intersector.intersections(candidate, trimEdge, sharedSurface: surface, tolerance: tolerance) {
            case .subdivisionPoints(let points):
                crossings += points
            case .coincident:
                guard alongEdge == .yieldNothing else {
                    throw failure(.invalidInput, tolerance, "The curve runs along an edge the face already has.")
                }
                return []
            }
        }
        let tester = DefaultFacePointContainmentTester()
        var preparation = FacePointContainmentPreparationCache()
        var pieces: [BRepSewingEdge] = []
        for segment in try BRepSewingEdgeSubdivider().subdivide(candidate, at: crossings, tolerance: tolerance) {
            let middle = try segment.surfaceParameterCurve.parameter(atNormalizedFraction: 0.5, tolerance: tolerance)
            guard try tester.contains(middle, on: faceID, in: model, preparationCache: &preparation, tolerance: tolerance) else {
                continue
            }
            if (segment.startPoint - segment.endPoint).length <= tolerance.distance {
                pieces += try BRepSewingEdgeSubdivider().subdivide(
                    segment,
                    at: [try surface.point(u: middle.u, v: middle.v, tolerance: tolerance)],
                    tolerance: tolerance
                )
            } else {
                pieces.append(segment)
            }
        }
        return pieces.enumerated().map { index, piece in
            BRepSewingEdge(
                stableID: "\(stableID):\(index)", curve: piece.curve,
                startParameter: piece.startParameter, endParameter: piece.endParameter,
                startPoint: piece.startPoint, endPoint: piece.endPoint,
                surfaceParameterCurve: piece.surfaceParameterCurve, parentSubshapeIDs: parentSubshapeIDs
            )
        }
    }

    /// The exact edge a parameter curve traces on a surface: the curve's lift onto it.
    static func edge(
        _ parameterCurve: SurfaceParameterCurve,
        on surface: Surface3D,
        stableID: String,
        parentSubshapeIDs: [SubshapeID],
        tolerance: ModelingTolerance
    ) throws -> BRepSewingEdge {
        let start = try parameterCurve.startParameter(tolerance: tolerance)
        let end = try parameterCurve.endParameter(tolerance: tolerance)
        return BRepSewingEdge(
            stableID: stableID,
            curve: .surfaceLift(SurfaceLiftCurve3D(surface: surface, parameterCurve: parameterCurve)),
            startParameter: 0.0,
            endParameter: 1.0,
            startPoint: try surface.point(u: start.u, v: start.v, tolerance: tolerance),
            endPoint: try surface.point(u: end.u, v: end.v, tolerance: tolerance),
            surfaceParameterCurve: parameterCurve,
            parentSubshapeIDs: parentSubshapeIDs
        )
    }

    /// The box the face's boundary spans in its surface's parameters, from its edges' parameter
    /// curves sampled densely enough to follow each.
    static func parameterBounds(
        of faceID: FaceID,
        model: BRepModel,
        sourceSubshapes: [SubshapeID: TopologyReference],
        tolerance: ModelingTolerance
    ) throws -> (u: ClosedRange<Double>, v: ClosedRange<Double>) {
        let edges = try SourceBRepFacePatchBuilder().build(
            faceID: faceID, stableID: "bounds:face:\(faceID)", from: model, sourceSubshapes: sourceSubshapes, tolerance: tolerance
        ).patch.loops.flatMap(\.edges)
        var u = (lower: Double.infinity, upper: -Double.infinity)
        var v = (lower: Double.infinity, upper: -Double.infinity)
        for edge in edges {
            for index in 0...32 {
                let parameter = try edge.surfaceParameterCurve.parameter(atNormalizedFraction: Double(index) / 32, tolerance: tolerance)
                u = (min(u.lower, parameter.u), max(u.upper, parameter.u))
                v = (min(v.lower, parameter.v), max(v.upper, parameter.v))
            }
        }
        guard u.lower.isFinite, v.lower.isFinite, u.upper > u.lower, v.upper > v.lower else {
            throw KernelError(phase: .topology, code: .invalidInput, tolerance: tolerance,
                message: "The face spans no area in its surface's parameters.")
        }
        return (u.lower...u.upper, v.lower...v.upper)
    }

    private func failure(_ code: KernelErrorCode, _ tolerance: ModelingTolerance, _ message: String) -> KernelError {
        KernelError(phase: .topology, code: code, tolerance: tolerance, message: message)
    }
}
