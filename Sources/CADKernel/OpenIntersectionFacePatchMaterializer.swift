import Foundation
import CADCore
import CADGeometry
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
    , using execution: inout OriginalQueryExecution) throws -> BRepSewingRequest {
        try execution.consumeWork(1)
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
        , using: &execution)
        let toolFaceIDs = try operandFaceIDs(
            bodyIDs: [toolBodyID],
            model: model,
            tolerance: tolerance
        , using: &execution)
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
            , using: &execution)
        } catch {
            throw contextualized(
                error,
                stage: "face-boundary materialization",
                tolerance: tolerance, context: execution.context
            )
        }
        // Coincident-region ownership removes whole faces; boundaries whose
        // pair twin lives on such a face must drop on the surviving side as
        // well, or their intersection edges sew single-sided.
        var discardedFaceIDs: Set<FaceID> = []
        for (id, action) in coincidentFaceActions {
            try execution.consumeWork(1)
            if action == .discard { try OriginalParameterQueryStorage.insert(id, in: &discardedFaceIDs, using: &execution) }
        }
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
        , using: &execution)
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
                splitPatches: splitPatches,
                model: model,
                sourceSubshapes: sourceSubshapes,
                operands: operands,
                tolerance: tolerance
            , using: &execution)
        } catch {
            throw contextualized(
                error,
                stage: "unsplit-face materialization",
                tolerance: tolerance, context: execution.context
            )
        }
        let patches = try mergedCoincidentAncestry(splitPatches + carriedPatches,
            uvSplitGraph: uvSplitGraph, forcedActions: coincidentFaceActions,
            model: model, sourceSubshapes: sourceSubshapes, tolerance: tolerance, using: &execution)
        guard patches.isEmpty == false else {
            throw KernelError(
                phase: .classification,
                code: .emptyResult,
                tolerance: tolerance,
                message: "Open Boolean region selection proved an empty material result."
            )
        }
        let shells: [BRepSewingShell]
        do {
            shells = try BRepSewingPatchShellPartitioner().shells(
                patches: patches,
                stablePrefix: "open-intersection:shell",
                tolerance: tolerance
            , using: &execution)
        } catch {
            throw contextualized(
                error,
                stage: "shell partitioning",
                tolerance: tolerance, context: execution.context
            )
        }
        var bodyParents: [SubshapeID] = []
        for id in targetBodyIDs {
            try execution.consumeWork(1)
            let parents = try parentSubshapeIDs(for: .body(id), in: sourceSubshapes, using: &execution)
            try OriginalParameterQueryStorage.append(contentsOf: parents, to: &bodyParents, using: &execution)
        }
        let toolParents = try parentSubshapeIDs(for: .body(toolBodyID), in: sourceSubshapes, using: &execution)
        try OriginalParameterQueryStorage.append(contentsOf: toolParents, to: &bodyParents, using: &execution)
        let request = BRepSewingRequest(
            featureID: featureID,
            bodyKind: operands.resultBodyKind,
            shells: shells,
            bodyParentSubshapeIDs: bodyParents
        )
        return request
    }

    private func mergedCoincidentAncestry(_ original: [BRepSewingFacePatch],
        uvSplitGraph: BooleanUVSplitGraph, forcedActions: [FaceID: BooleanRegionSelectionAction],
        model: BRepModel, sourceSubshapes: [SubshapeID: TopologyReference],
        tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution) throws -> [BRepSewingFacePatch] {
        try execution.consumeWork(1)
        try execution.retainKernelValues(count: original.count, stride: MemoryLayout<BRepSewingFacePatch>.stride)
        var retained = original
        for split in uvSplitGraph.splits {
            try execution.consumeWork(1)
            try execution.consumeWork(1)
            guard split.components.contains(where: {
                if case .coincident = $0.geometry { return true }; return false
            }) else { continue }
            let a = split.facePair.targetFaceID, b = split.facePair.toolFaceID
            let discarded: FaceID
            switch (forcedActions[a], forcedActions[b]) {
            case (.keep?, .discard?), (.keepReversed?, .discard?): discarded = b
            case (.discard?, .keep?), (.discard?, .keepReversed?): discarded = a
            default: continue
            }
            let duplicate = try SourceBRepFacePatchBuilder().build(faceID: discarded,
                stableID: "~coincident-parent:\(a):\(b)", from: model,
                sourceSubshapes: sourceSubshapes, tolerance: tolerance, using: &execution).patch
            let merged = try CoincidentFacePatchMerger().merge(retained + [duplicate],
                tolerance: tolerance, using: &execution)
            guard merged.count == retained.count,
                  !merged.contains(where: { $0.stableID == duplicate.stableID }) else {
                throw KernelError(phase: .classification, code: .classificationFailure,
                    tolerance: tolerance,
                    message: "A fully owned coincident face has no retained original region for ancestry.")
            }
            retained = merged
        }
        return retained
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
    , using execution: inout OriginalQueryExecution) throws -> [BooleanFaceArrangementBoundary] {
        try execution.consumeWork(1)
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
        try execution.retainKernelValues(count: coincidentArrangementBoundaries.count, stride: MemoryLayout<BooleanFaceArrangementBoundary>.stride)
        var result = coincidentArrangementBoundaries
        for split in uvSplitGraph.splits {
            try execution.consumeWork(1)
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
            let targetParents = try parentSubshapeIDs(
                for: .face(targetFace.id), in: sourceSubshapes, using: &execution)
            let toolParents = try parentSubshapeIDs(
                for: .face(toolFace.id), in: sourceSubshapes, using: &execution)
            let componentParents = try OriginalParameterQueryStorage.concatenated(
                targetParents, toolParents, using: &execution)
            for component in split.components {
            try execution.consumeWork(1)
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
                , using: &execution)
                let toolBoundaries = try BooleanFaceArrangementBoundary.make(
                    reference: reference,
                    geometry: component.geometry,
                    face: toolFace,
                    surfaceSide: .second,
                    regionSelectionGraph: regionSelectionGraph,
                    parentSubshapeIDs: componentParents,
                    tolerance: tolerance
                , using: &execution)
                try OriginalParameterQueryStorage.append(contentsOf: targetBoundaries, to: &result, using: &execution)
                try OriginalParameterQueryStorage.append(contentsOf: toolBoundaries, to: &result, using: &execution)
            }
        }
        // An empty-shell operand has no material to change a face's action across, yet the
        // crossing is where the operands meet: a face crossing an empty shell is split there
        // when both sides stay.
        for index in result.indices where result[index].isPartitioning == false {
            try execution.consumeWork(1)
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
            try execution.consumeWork(1)
            try OriginalParameterQueryStorage.set(true, for: boundary.reference, in: &partitioningByComponent, using: &execution)
        }
        for index in result.indices {
            try execution.consumeWork(1)
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
    , using execution: inout OriginalQueryExecution) throws -> Set<FaceID> {
        try execution.consumeWork(1)
        var result: Set<FaceID> = []
        for bodyID in bodyIDs {
            try execution.consumeWork(1)
            guard let body = model.bodies[bodyID], body.shellIDs.isEmpty == false else {
                throw KernelError(
                    phase: .topology,
                    code: .missingReference,
                    tolerance: tolerance,
                    message: "Open Boolean materialization references a missing operand body."
                )
            }
            for shellID in body.shellIDs {
            try execution.consumeWork(1)
                guard let shell = model.shells[shellID] else {
                    throw KernelError(
                        phase: .topology,
                        code: .missingReference,
                        tolerance: tolerance,
                        message: "Open Boolean materialization references a missing operand shell."
                    )
                }
                for id in shell.faceIDs {
            try execution.consumeWork(1)
            try OriginalParameterQueryStorage.insert(id, in: &result, using: &execution) }
            }
        }
        return result
    }

    private func parentSubshapeIDs(for reference: TopologyReference,
        in sourceSubshapes: [SubshapeID: TopologyReference], using execution: inout OriginalQueryExecution) throws -> [SubshapeID] {
        var result: [SubshapeID] = []
        for (id, candidate) in sourceSubshapes {
            try execution.consumeWork(1)
            if candidate == reference { try OriginalParameterQueryStorage.append(id, to: &result, using: &execution) }
        }
        try OriginalParameterQueryStorage.sort(&result, using: &execution) { $0 < $1 }
        return result
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
