import Foundation
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
        operands: BooleanOperandContext,
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
                operands: operands,
                tolerance: tolerance
            )
        } catch {
            throw contextualized(
                error,
                stage: "face-boundary materialization",
                tolerance: tolerance
            )
        }
        // Coincident-region ownership removes whole faces; boundaries whose
        // pair twin lives on such a face must drop on the surviving side as
        // well, or their intersection edges sew single-sided.
        let discardedFaceIDs = Set(
            coincidentFaceActions.filter { $0.value == .discard }.map(\.key)
        )
        let effectiveBoundaries = boundaries.filter { boundary in
            guard discardedFaceIDs.contains(boundary.faceID) == false else {
                return false
            }
            let pair = boundary.reference.facePair
            return discardedFaceIDs.contains(pair.targetFaceID) == false
                && discardedFaceIDs.contains(pair.toolFaceID) == false
        }
        let arrangement = try SharedCurveFaceArrangement().arrange(
            boundaries: effectiveBoundaries,
            model: model,
            sourceSubshapes: sourceSubshapes,
            forcedActions: coincidentFaceActions,
            tolerance: tolerance
        )
        let splitPatches = arrangement.patches
        let splitFaceIDs = arrangement.splitFaceIDs
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
                operands: operands,
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
            bodyKind: operands.resultBodyKind,
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
        operands: BooleanOperandContext,
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
                let targetBoundaries = try BooleanFaceArrangementBoundary.make(
                    reference: reference,
                    geometry: component.geometry,
                    face: targetFace,
                    surfaceSide: .first,
                    regionSelectionGraph: regionSelectionGraph,
                    parentSubshapeIDs: componentParents,
                    tolerance: tolerance
                )
                let toolBoundaries = try BooleanFaceArrangementBoundary.make(
                    reference: reference,
                    geometry: component.geometry,
                    face: toolFace,
                    surfaceSide: .second,
                    regionSelectionGraph: regionSelectionGraph,
                    parentSubshapeIDs: componentParents,
                    tolerance: tolerance
                )
                result.append(contentsOf: targetBoundaries)
                result.append(contentsOf: toolBoundaries)
            }
        }
        // An empty-shell operand has no material to change a face's action across, yet the
        // crossing is where the operands meet: a face crossing an empty shell is split there
        // when both sides stay.
        for index in result.indices where result[index].isPartitioning == false {
            let boundary = result[index]
            let oppositeSolidity = targetFaceIDs.contains(boundary.faceID)
                ? operands.solidities.tool
                : operands.solidities.target
            if oppositeSolidity == .none,
               boundary.forwardLeftAction != .discard,
               boundary.forwardRightAction != .discard {
                result[index].forcedPartitioning = true
            }
        }
        // Solid sewing pairs every intersection edge across its face pair,
        // so a component partitioning one face forces its kept-kept twin
        // face to partition as well.
        var partitioningByComponent: [BooleanFaceSplitComponentReference: Bool] = [:]
        for boundary in result where boundary.isPartitioning {
            partitioningByComponent[boundary.reference] = true
        }
        for index in result.indices {
            let boundary = result[index]
            if boundary.isPartitioning == false,
               partitioningByComponent[boundary.reference] == true,
               boundary.forwardLeftAction != .discard,
               boundary.forwardRightAction != .discard {
                result[index].forcedPartitioning = true
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
