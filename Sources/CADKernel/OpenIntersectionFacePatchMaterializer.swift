import CADCore
import CADIR
import CADModeling
import CADTopology

struct OpenIntersectionFacePatchMaterializer {
    private let unsplitFaceMaterializer: ClosedIntersectionUnsplitFaceMaterializer

    init(
        unsplitFaceMaterializer: ClosedIntersectionUnsplitFaceMaterializer = ClosedIntersectionUnsplitFaceMaterializer()
    ) {
        self.unsplitFaceMaterializer = unsplitFaceMaterializer
    }

    func materialize(
        operation: BooleanOperation,
        targetBodyIDs: [BodyID],
        toolBodyID: BodyID,
        featureID: FeatureID,
        model: BRepModel,
        sourceSubshapes: [SubshapeID: TopologyReference],
        uvSplitGraph: BooleanUVSplitGraph,
        regionSelectionGraph: BooleanRegionSelectionGraph,
        coincidentArrangementBoundaries: [BooleanFaceArrangementBoundary] = [],
        coincidentFaceActions: [FaceID: BooleanRegionSelectionAction] = [:],
        tolerance: ModelingTolerance
    ) throws -> BRepSewingRequest {
        try tolerance.validate()
        guard targetBodyIDs.isEmpty == false,
              Set(targetBodyIDs).count == targetBodyIDs.count,
              targetBodyIDs.contains(toolBodyID) == false else {
            throw KernelError(
                phase: .topology,
                code: .invalidInput,
                tolerance: tolerance,
                message: "Open-intersection materialization requires distinct Boolean operands and a result operation."
            )
        }
        let targetFaceIDs = try operandFaceIDs(
            bodyIDs: targetBodyIDs,
            model: model,
            tolerance: tolerance
        )
        let toolFaceIDs = try operandFaceIDs(
            bodyIDs: [toolBodyID],
            model: model,
            tolerance: tolerance
        )
        let boundaries: [BooleanFaceArrangementBoundary]
        do {
            boundaries = try faceBoundaries(
                uvSplitGraph: uvSplitGraph,
                regionSelectionGraph: regionSelectionGraph,
                targetFaceIDs: targetFaceIDs,
                toolFaceIDs: toolFaceIDs,
                model: model,
                sourceSubshapes: sourceSubshapes,
                coincidentArrangementBoundaries: coincidentArrangementBoundaries,
                tolerance: tolerance
            )
        } catch {
            throw contextualized(
                error,
                stage: "face-boundary materialization",
                tolerance: tolerance
            )
        }
        let effectiveBoundaries = boundaries.filter {
            coincidentFaceActions[$0.faceID] != .discard
        }
        let groupedBoundaries = Dictionary(grouping: effectiveBoundaries, by: \.faceID)
        var splitPatches: [BRepSewingFacePatch] = []
        var splitFaceIDs: Set<FaceID> = []
        for faceID in groupedBoundaries.keys.sorted() {
            guard let faceBoundaries = groupedBoundaries[faceID] else { continue }
            let result: BooleanOpenFaceArrangementBuilder.Result
            do {
                result = try BooleanOpenFaceArrangementBuilder().build(
                    faceID: faceID,
                    boundaries: faceBoundaries,
                    model: model,
                    sourceSubshapes: sourceSubshapes,
                    forcedAction: coincidentFaceActions[faceID],
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
        guard splitFaceIDs.isEmpty == false || coincidentFaceActions.isEmpty == false else {
            throw KernelError(
                phase: .topology,
                code: .unsupportedCapability,
                tolerance: tolerance,
                message: "Open-intersection materialization requires at least one action-changing exact pcurve."
            )
        }
        let carriedPatches: [BRepSewingFacePatch]
        do {
            carriedPatches = try unsplitFaceMaterializer.patches(
                operation: operation,
                targetBodyIDs: targetBodyIDs,
                toolBodyID: toolBodyID,
                splitFaceIDs: splitFaceIDs,
                forcedActions: coincidentFaceActions,
                model: model,
                sourceSubshapes: sourceSubshapes,
                tolerance: tolerance
            )
        } catch {
            throw contextualized(
                error,
                stage: "unsplit-face materialization",
                tolerance: tolerance
            )
        }
        let patches = splitPatches + carriedPatches
        guard patches.isEmpty == false else {
            throw KernelError(
                phase: .topology,
                code: .topologyFailure,
                tolerance: tolerance,
                message: "Open Boolean region selection produced no exact face patches."
            )
        }
        let shells: [BRepSewingShell]
        do {
            shells = try BRepSewingPatchShellPartitioner().shells(
                patches: patches,
                stablePrefix: "open-intersection:shell",
                tolerance: tolerance
            )
        } catch {
            throw contextualized(
                error,
                stage: "shell partitioning",
                tolerance: tolerance
            )
        }
        let request = BRepSewingRequest(
            featureID: featureID,
            bodyKind: .solid,
            shells: shells,
            bodyParentSubshapeIDs: (targetBodyIDs + [toolBodyID]).flatMap {
                parentSubshapeIDs(for: .body($0), in: sourceSubshapes)
            }
        )
        return request
    }

    private func faceBoundaries(
        uvSplitGraph: BooleanUVSplitGraph,
        regionSelectionGraph: BooleanRegionSelectionGraph,
        targetFaceIDs: Set<FaceID>,
        toolFaceIDs: Set<FaceID>,
        model: BRepModel,
        sourceSubshapes: [SubshapeID: TopologyReference],
        coincidentArrangementBoundaries: [BooleanFaceArrangementBoundary],
        tolerance: ModelingTolerance
    ) throws -> [BooleanFaceArrangementBoundary] {
        let operandFaceIDs = targetFaceIDs.union(toolFaceIDs)
        guard coincidentArrangementBoundaries.allSatisfy({
            operandFaceIDs.contains($0.faceID)
        }) else {
            throw KernelError(
                phase: .topology,
                code: .missingReference,
                tolerance: tolerance,
                message: "Coincident arrangement boundary belongs to a face outside the Boolean operands."
            )
        }
        var result = coincidentArrangementBoundaries
        for split in uvSplitGraph.splits {
            guard targetFaceIDs.contains(split.facePair.targetFaceID),
                  toolFaceIDs.contains(split.facePair.toolFaceID),
                  let targetFace = model.faces[split.facePair.targetFaceID],
                  let toolFace = model.faces[split.facePair.toolFaceID] else {
                throw KernelError(
                    phase: .topology,
                    code: .missingReference,
                    tolerance: tolerance,
                    message: "Open Boolean split references topology outside its declared operands."
                )
            }
            let componentParents = parentSubshapeIDs(
                for: .face(targetFace.id),
                in: sourceSubshapes
            ) + parentSubshapeIDs(
                for: .face(toolFace.id),
                in: sourceSubshapes
            )
            for component in split.components {
                if case .coincident = component.geometry {
                    continue
                }
                let reference = BooleanFaceSplitComponentReference(
                    facePair: split.facePair,
                    componentID: component.id
                )
                result.append(contentsOf: try BooleanFaceArrangementBoundary.make(
                    reference: reference,
                    geometry: component.geometry,
                    face: targetFace,
                    surfaceSide: .first,
                    regionSelectionGraph: regionSelectionGraph,
                    parentSubshapeIDs: componentParents,
                    tolerance: tolerance
                ))
                result.append(contentsOf: try BooleanFaceArrangementBoundary.make(
                    reference: reference,
                    geometry: component.geometry,
                    face: toolFace,
                    surfaceSide: .second,
                    regionSelectionGraph: regionSelectionGraph,
                    parentSubshapeIDs: componentParents,
                    tolerance: tolerance
                ))
            }
        }
        return result
    }

    private func operandFaceIDs(
        bodyIDs: [BodyID],
        model: BRepModel,
        tolerance: ModelingTolerance
    ) throws -> Set<FaceID> {
        var result: Set<FaceID> = []
        for bodyID in bodyIDs {
            guard let body = model.bodies[bodyID], body.shellIDs.isEmpty == false else {
                throw KernelError(
                    phase: .topology,
                    code: .missingReference,
                    tolerance: tolerance,
                    message: "Open Boolean materialization references a missing operand body."
                )
            }
            for shellID in body.shellIDs {
                guard let shell = model.shells[shellID] else {
                    throw KernelError(
                        phase: .topology,
                        code: .missingReference,
                        tolerance: tolerance,
                        message: "Open Boolean materialization references a missing operand shell."
                    )
                }
                result.formUnion(shell.faceIDs)
            }
        }
        return result
    }

    private func parentSubshapeIDs(
        for reference: TopologyReference,
        in sourceSubshapes: [SubshapeID: TopologyReference]
    ) -> [SubshapeID] {
        sourceSubshapes.compactMap { subshapeID, candidate in
            candidate == reference ? subshapeID : nil
        }.sorted()
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
