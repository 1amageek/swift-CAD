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
    , using execution: inout OriginalQueryExecution) throws -> [BRepSewingEdge] {
        do {
            let result = try resolve(using: &execution)
            execution.context = execution.context.at(stage: .publication)
            try execution.checkpoint()
            return result
        } catch {
            throw OriginalQueryFailure.published(error, context: execution.context, tolerance: tolerance)
        }
        func resolve(using execution: inout OriginalQueryExecution) throws -> [BRepSewingEdge] {
        try execution.consumeWork(1)
        guard let face = model.faces[faceID], let surface = model.geometry.surfaces[face.surfaceID] else {
            throw failure(.missingReference, tolerance, "The face to imprint on is missing.")
        }
        let candidate = try Self.edge(
            parameterCurve, on: surface, stableID: stableID, parentSubshapeIDs: parentSubshapeIDs, tolerance: tolerance
        , using: &execution)
        let trimPatch = try SourceBRepFacePatchBuilder().build(
            faceID: faceID, stableID: "\(stableID):face", from: model, sourceSubshapes: sourceSubshapes, tolerance: tolerance
        , using: &execution).patch
        var trimEdges: [BRepSewingEdge] = []
        for loop in trimPatch.loops {
            try execution.consumeWork(1)
            try OriginalParameterQueryStorage.append(contentsOf: loop.edges, to: &trimEdges, using: &execution)
        }
        var crossings: [Point3D] = []
        let intersector = ExactTrimEdgeIntersector()
        for trimEdge in trimEdges {
            try execution.consumeWork(1)
            switch try intersector.intersections(candidate, trimEdge, sharedSurface: surface, tolerance: tolerance, using: &execution) {
            case .subdivisionPoints(let points):
                try OriginalParameterQueryStorage.append(contentsOf: points, to: &crossings, using: &execution)
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
        for segment in try BRepSewingEdgeSubdivider().subdivide(candidate, at: crossings, tolerance: tolerance, using: &execution) {
            try execution.consumeWork(1)
            let middle = try segment.surfaceParameterCurve.parameter(atNormalizedFraction: 0.5, tolerance: tolerance, using: &execution)
            guard try tester.contains(middle, on: faceID, in: model, preparationCache: &preparation, tolerance: tolerance, using: &execution) else {
                continue
            }
            let kind = try BRepEdgeGeometryClassifier().kind(curve: segment.curve,
                from: segment.startParameter, to: segment.endParameter, tolerance: tolerance, using: &execution)
            if kind == .closed {
                let halves = try BRepSewingEdgeSubdivider().subdivide(
                    segment,
                    at: [try surface.point(u: middle.u, v: middle.v, tolerance: tolerance, using: &execution)],
                    tolerance: tolerance
                , using: &execution)
                try OriginalParameterQueryStorage.append(contentsOf: halves, to: &pieces, using: &execution)
            } else {
                try OriginalParameterQueryStorage.append(segment, to: &pieces, using: &execution)
            }
        }
        return try OriginalParameterQueryStorage.map(pieces.enumerated(), using: &execution) { entry, execution in
            let (index, piece) = entry
            return BRepSewingEdge(
                stableID: "\(stableID):\(index)", curve: piece.curve,
                startParameter: piece.startParameter, endParameter: piece.endParameter,
                startPoint: piece.startPoint, endPoint: piece.endPoint,
                surfaceParameterCurve: piece.surfaceParameterCurve, parentSubshapeIDs: parentSubshapeIDs,
                startVertexParentSubshapeIDs: piece.startVertexParentSubshapeIDs,
                endVertexParentSubshapeIDs: piece.endVertexParentSubshapeIDs
            )
        }
            }
    }

    /// The exact edge a parameter curve traces on a surface: the curve's lift onto it.
    static func edge(
        _ parameterCurve: SurfaceParameterCurve,
        on surface: Surface3D,
        stableID: String,
        parentSubshapeIDs: [SubshapeID],
        tolerance: ModelingTolerance
    , using execution: inout OriginalQueryExecution) throws -> BRepSewingEdge {
        try execution.consumeWork(1)
        let lift = SurfaceLiftCurve3D(surface: surface, parameterCurve: parameterCurve)
        return BRepSewingEdge(
            stableID: stableID,
            curve: .surfaceLift(lift),
            startParameter: 0.0,
            endParameter: 1.0,
            startPoint: try lift.point(atNormalizedFraction: 0, tolerance: tolerance, using: &execution),
            endPoint: try lift.point(atNormalizedFraction: 1, tolerance: tolerance, using: &execution),
            surfaceParameterCurve: parameterCurve,
            parentSubshapeIDs: parentSubshapeIDs
        )
    }

    /// Complete original finite trim bounds in the face's retained native chart.
    static func parameterBounds(
        of faceID: FaceID,
        model: BRepModel,
        sourceSubshapes: [SubshapeID: TopologyReference],
        tolerance: ModelingTolerance
    , using execution: inout OriginalQueryExecution) throws -> (u: ClosedRange<Double>, v: ClosedRange<Double>) {
        try execution.consumeWork(1)
        guard let face = model.faces[faceID], let surface = model.geometry.surfaces[face.surfaceID] else {
            throw TopologyError.missingReference("Original finite trim bounds require the face's source support.")
        }
        let bounds = try OriginalFaceParameterBounds.resolve(for: faceID,
            surface: surface, model: model, tolerance: tolerance, using: &execution)
        return (bounds.u.lower...bounds.u.upper, bounds.v.lower...bounds.v.upper)
    }

    private func failure(_ code: KernelErrorCode, _ tolerance: ModelingTolerance, _ message: String) -> KernelError {
        KernelError(phase: .topology, code: code, tolerance: tolerance, message: message)
    }
}
