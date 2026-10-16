import CADCore
import CADGeometry
import CADIR
import CADModeling
import CADTopology

/// Splits faces along boundary curves so that faces sharing one curve segment it identically:
/// each face's own arrangement is previewed, every split point on a curve is shared by all the
/// faces the curve lies on, and the faces are arranged again with those shared points. The
/// patches of the regions each face's boundaries select are returned with the faces split.
struct SharedCurveFaceArrangement {
    struct Result {
        let patches: [BRepSewingFacePatch]
        let splitFaceIDs: Set<FaceID>
    }

    func arrange(
        boundaries: [BooleanFaceArrangementBoundary],
        model: BRepModel,
        sourceSubshapes: [SubshapeID: TopologyReference],
        forcedActions: [FaceID: BooleanRegionSelectionAction] = [:],
        tolerance: ModelingTolerance
    , using execution: inout OriginalQueryExecution) throws -> Result {
        try execution.consumeWork(1)
        var groupedBoundaries: [FaceID: [BooleanFaceArrangementBoundary]] = [:]
        for boundary in boundaries {
            try execution.consumeWork(1)
            var items = groupedBoundaries[boundary.faceID] ?? []
            try execution.retainKernelValues(count: items.count, stride: MemoryLayout<BooleanFaceArrangementBoundary>.stride)
            try OriginalParameterQueryStorage.append(boundary, to: &items, using: &execution)
            try OriginalParameterQueryStorage.set(items, for: boundary.faceID, in: &groupedBoundaries, using: &execution)
        }
        // Faces sharing one geometric curve support must segment it
        // identically for solid sewing to pair twins. Independently authored
        // analytic and B-spline lines can describe the same support, so exact
        // representation equality is insufficient at this topology boundary.
        var curveIdentityRegistry = CurveSupportIdentityRegistry()
        func curveKey(_ edge: BRepSewingEdge, using execution: inout OriginalQueryExecution) throws -> ExactCurveIdentity {
            try curveIdentityRegistry.identity(for: edge, tolerance: tolerance, using: &execution)
        }
        func appendPoint(_ point: Point3D, key: ExactCurveIdentity,
            to points: inout [ExactCurveIdentity: [Point3D]], using execution: inout OriginalQueryExecution) throws {
            var items = points[key] ?? []
            try execution.retainKernelValues(count: items.count, stride: MemoryLayout<Point3D>.stride)
            try OriginalParameterQueryStorage.append(point, to: &items, using: &execution)
            try OriginalParameterQueryStorage.set(items, for: key, in: &points, using: &execution)
        }
        var sharedPointsByCurve: [ExactCurveIdentity: [Point3D]] = [:]
        var previewEdgesByFaceID: [FaceID: [BRepSewingEdge]] = [:]
        for boundary in boundaries {
            try execution.consumeWork(1)
            let key = try curveKey(boundary.edge, using: &execution)
            try appendPoint(boundary.edge.startPoint, key: key, to: &sharedPointsByCurve, using: &execution)
            try appendPoint(boundary.edge.endPoint, key: key, to: &sharedPointsByCurve, using: &execution)
        }
        // Pass one discovers every face's own segmentation (including
        // in-face crossings); its patch-edge endpoints join the shared set
        // so pass two segments every curve identically on all faces.
        for faceID in groupedBoundaries.keys.sorted() {
            try execution.consumeWork(1)
            guard let faceBoundaries = groupedBoundaries[faceID] else { continue }
            let preview: BooleanOpenFaceArrangementBuilder.Result
            do {
                preview = try BooleanOpenFaceArrangementBuilder().build(
                    faceID: faceID,
                    boundaries: faceBoundaries,
                    model: model,
                    sourceSubshapes: sourceSubshapes,
                    forcedAction: forcedActions[faceID],
                    tolerance: tolerance
                , using: &execution)
            } catch {
                throw contextualized(
                    error,
                    stage: "preliminary arrangement of face \(faceID)",
                    tolerance: tolerance, context: execution.context
                )
            }
            var previewEdges: [BRepSewingEdge] = []
            for patch in preview.patches {
            try execution.consumeWork(1)
                for loop in patch.loops {
            try execution.consumeWork(1)
            try OriginalParameterQueryStorage.append(contentsOf: loop.edges, to: &previewEdges, using: &execution) }
            }
            try OriginalParameterQueryStorage.set(previewEdges, for: faceID, in: &previewEdgesByFaceID, using: &execution)
            for edge in previewEdges {
            try execution.consumeWork(1)
                let key = try curveKey(edge, using: &execution)
                try appendPoint(edge.startPoint, key: key, to: &sharedPointsByCurve, using: &execution)
                try appendPoint(edge.endPoint, key: key, to: &sharedPointsByCurve, using: &execution)
            }
        }
        // Independently computed copies of one split point differ by
        // rounding across faces; clustering to canonical representatives
        // keeps every face's segmentation bitwise identical.
        for (key, points) in sharedPointsByCurve {
            try execution.consumeWork(1)
            var representatives: [Point3D] = []
            for point in points.sorted(by: {
                ($0.x, $0.y, $0.z) < ($1.x, $1.y, $1.z)
            }) {
            try execution.consumeWork(1)
                if representatives.contains(where: {
                    ($0 - point).length <= tolerance.distance * 8.0
                }) == false {
                    try OriginalParameterQueryStorage.append(point, to: &representatives, using: &execution)
                }
            }
            try OriginalParameterQueryStorage.set(representatives, for: key, in: &sharedPointsByCurve, using: &execution)
        }
        var splitPatches: [BRepSewingFacePatch] = []
        var splitFaceIDs: Set<FaceID> = []
        for faceID in groupedBoundaries.keys.sorted() {
            try execution.consumeWork(1)
            guard let faceBoundaries = groupedBoundaries[faceID] else { continue }
            let result: BooleanOpenFaceArrangementBuilder.Result
            do {
                var sharedSubdivisionPoints: [Point3D] = []
                for boundary in faceBoundaries {
            try execution.consumeWork(1)
                    try OriginalParameterQueryStorage.append(
                        contentsOf: sharedPointsByCurve[
                            try curveKey(boundary.edge, using: &execution)
                        ] ?? []
                    , to: &sharedSubdivisionPoints, using: &execution)
                }
                for edge in previewEdgesByFaceID[faceID, default: []] {
            try execution.consumeWork(1)
                    try OriginalParameterQueryStorage.append(
                        contentsOf: sharedPointsByCurve[
                            try curveKey(edge, using: &execution)
                        ] ?? []
                    , to: &sharedSubdivisionPoints, using: &execution)
                }
                result = try BooleanOpenFaceArrangementBuilder().build(
                    faceID: faceID,
                    boundaries: faceBoundaries,
                    model: model,
                    sourceSubshapes: sourceSubshapes,
                    forcedAction: forcedActions[faceID],
                    sharedSubdivisionPoints: sharedSubdivisionPoints,
                    tolerance: tolerance
                , using: &execution)
            } catch {
                throw contextualized(
                    error,
                    stage: "arrangement of face \(faceID)",
                    tolerance: tolerance, context: execution.context
                )
            }
            if result.isPartitioned {
                try OriginalParameterQueryStorage.insert(faceID, in: &splitFaceIDs, using: &execution)
                try OriginalParameterQueryStorage.append(contentsOf: result.patches, to: &splitPatches, using: &execution)
            }
        }
        return Result(patches: splitPatches, splitFaceIDs: splitFaceIDs)
    }

    private func contextualized(
        _ error: any Error,
        stage: String,
        tolerance: ModelingTolerance,
        context: OriginalQueryFailureContext
    ) -> any Error {
        OriginalQueryFailure.contextualizing(error,
            diagnosticPrefix: "Open-intersection \(stage) failed: ",
            context: context, tolerance: tolerance)
    }
}
