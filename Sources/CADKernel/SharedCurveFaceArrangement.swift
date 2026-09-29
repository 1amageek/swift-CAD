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
    ) throws -> Result {
        let groupedBoundaries = Dictionary(grouping: boundaries, by: \.faceID)
        // Faces sharing one geometric curve support must segment it
        // identically for solid sewing to pair twins. Independently authored
        // analytic and B-spline lines can describe the same support, so exact
        // representation equality is insufficient at this topology boundary.
        var curveIdentityRegistry = CurveSupportIdentityRegistry()
        func curveKey(_ edge: BRepSewingEdge) -> ExactCurveIdentity {
            curveIdentityRegistry.identity(for: edge, tolerance: tolerance)
        }
        var sharedPointsByCurve: [ExactCurveIdentity: [Point3D]] = [:]
        var previewEdgesByFaceID: [FaceID: [BRepSewingEdge]] = [:]
        for boundary in boundaries {
            let key = curveKey(boundary.edge)
            sharedPointsByCurve[key, default: []]
                .append(boundary.edge.startPoint)
            sharedPointsByCurve[key, default: []]
                .append(boundary.edge.endPoint)
        }
        // Pass one discovers every face's own segmentation (including
        // in-face crossings); its patch-edge endpoints join the shared set
        // so pass two segments every curve identically on all faces.
        for faceID in groupedBoundaries.keys.sorted() {
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
                )
            } catch {
                throw contextualized(
                    error,
                    stage: "preliminary arrangement of face \(faceID)",
                    tolerance: tolerance
                )
            }
            let previewEdges = preview.patches.flatMap {
                $0.loops.flatMap(\.edges)
            }
            previewEdgesByFaceID[faceID] = previewEdges
            for edge in previewEdges {
                let key = curveKey(edge)
                sharedPointsByCurve[key, default: []]
                    .append(edge.startPoint)
                sharedPointsByCurve[key, default: []]
                    .append(edge.endPoint)
            }
        }
        // Independently computed copies of one split point differ by
        // rounding across faces; clustering to canonical representatives
        // keeps every face's segmentation bitwise identical.
        for (key, points) in sharedPointsByCurve {
            var representatives: [Point3D] = []
            for point in points.sorted(by: {
                ($0.x, $0.y, $0.z) < ($1.x, $1.y, $1.z)
            }) {
                if representatives.contains(where: {
                    ($0 - point).length <= tolerance.distance * 8.0
                }) == false {
                    representatives.append(point)
                }
            }
            sharedPointsByCurve[key] = representatives
        }
        var splitPatches: [BRepSewingFacePatch] = []
        var splitFaceIDs: Set<FaceID> = []
        for faceID in groupedBoundaries.keys.sorted() {
            guard let faceBoundaries = groupedBoundaries[faceID] else { continue }
            let result: BooleanOpenFaceArrangementBuilder.Result
            do {
                var sharedSubdivisionPoints: [Point3D] = []
                for boundary in faceBoundaries {
                    sharedSubdivisionPoints.append(
                        contentsOf: sharedPointsByCurve[
                            curveKey(boundary.edge)
                        ] ?? []
                    )
                }
                for edge in previewEdgesByFaceID[faceID, default: []] {
                    sharedSubdivisionPoints.append(
                        contentsOf: sharedPointsByCurve[
                            curveKey(edge)
                        ] ?? []
                    )
                }
                result = try BooleanOpenFaceArrangementBuilder().build(
                    faceID: faceID,
                    boundaries: faceBoundaries,
                    model: model,
                    sourceSubshapes: sourceSubshapes,
                    forcedAction: forcedActions[faceID],
                    sharedSubdivisionPoints: sharedSubdivisionPoints,
                    tolerance: tolerance
                )
            } catch {
                throw contextualized(
                    error,
                    stage: "arrangement of face \(faceID)",
                    tolerance: tolerance
                )
            }
            if result.isPartitioned {
                splitFaceIDs.insert(faceID)
                splitPatches.append(contentsOf: result.patches)
            }
        }
        return Result(patches: splitPatches, splitFaceIDs: splitFaceIDs)
    }

    private func contextualized(
        _ error: any Error,
        stage: String,
        tolerance: ModelingTolerance
    ) -> KernelError {
        if let error = error as? KernelError {
            return KernelError(
                phase: error.phase,
                code: error.code,
                residual: error.residual,
                tolerance: tolerance,
                message: "Open-intersection \(stage) failed: \(error.message)"
            )
        }
        return KernelError(
            phase: .topology,
            code: .topologyFailure,
            tolerance: tolerance,
            message: "Open-intersection \(stage) failed: \(error)"
        )
    }
}
