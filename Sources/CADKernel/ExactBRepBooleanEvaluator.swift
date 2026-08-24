import CADCore
import CADIR
import CADModeling
import CADTopology

public struct ExactBRepBooleanEvaluator: BRepBooleanEvaluating {
    public init() {}

    public func intersectionRequirement(
        operation: BooleanOperation,
        targetBodyIDs: [BodyID],
        toolBodyID: BodyID,
        model: BRepModel,
        tolerance: ModelingTolerance
    ) throws -> BooleanIntersectionRequirement {
        let operationPlan: BRepBooleanOperationPlan
        do {
            operationPlan = try makePlan(
                operation: operation,
                targetBodyIDs: targetBodyIDs,
                toolBodyID: toolBodyID,
                model: model,
                tolerance: tolerance
            )
        } catch let error as KernelError where error.code == .unsupportedCapability {
            return .required
        }
        switch operationPlan.shape {
        case .carriedOperand, .disjointUnion:
            return .provenEmpty
        case .orthogonal,
             .revolvedBoolean,
             .partialCylinder,
             .convexPlanarBoolean:
            return .required
        }
    }

    func plan(
        operation: BooleanOperation,
        targetBodyIDs: [BodyID],
        toolBodyID: BodyID,
        model: BRepModel,
        tolerance: ModelingTolerance
    ) throws -> BRepBooleanPlan {
        try makePlan(
            operation: operation,
            targetBodyIDs: targetBodyIDs,
            toolBodyID: toolBodyID,
            model: model,
            tolerance: tolerance
        ).summary
    }

    public func exactRegionSelection(
        operation: BooleanOperation,
        targetBodyIDs: [BodyID],
        toolBodyID: BodyID,
        featureID: FeatureID,
        model: BRepModel,
        subshapes: [SubshapeID: TopologyReference],
        uvSplitGraph: BooleanUVSplitGraph,
        regionSelectionGraph: BooleanRegionSelectionGraph,
        tolerance: ModelingTolerance
    ) throws -> BooleanExactRegionSelectionGraph {
        let operationPlan: BRepBooleanOperationPlan
        do {
            operationPlan = try makePlan(
                operation: operation,
                targetBodyIDs: targetBodyIDs,
                toolBodyID: toolBodyID,
                model: model,
                tolerance: tolerance
            )
        } catch let error as KernelError where error.code == .unsupportedCapability {
            let request: BRepSewingRequest
            if operation == .slice {
                request = try BooleanSliceSewingRequestBuilder().materialize(
                    targetBodyIDs: targetBodyIDs,
                    toolBodyID: toolBodyID,
                    featureID: featureID,
                    model: model,
                    sourceSubshapes: subshapes,
                    uvSplitGraph: uvSplitGraph,
                    sliceRegionSelectionGraph: regionSelectionGraph,
                    tolerance: tolerance
                )
            } else {
                request = try ExactIntersectionFacePatchMaterializer().materialize(
                    operation: operation,
                    targetBodyIDs: targetBodyIDs,
                    toolBodyID: toolBodyID,
                    featureID: featureID,
                    model: model,
                    sourceSubshapes: subshapes,
                    uvSplitGraph: uvSplitGraph,
                    regionSelectionGraph: regionSelectionGraph,
                    tolerance: tolerance
                )
            }
            return BooleanExactRegionSelectionGraph(
                decisions: regionSelectionGraph,
                sewingRequest: request
            )
        }
        switch operationPlan.shape {
        case let .orthogonal(resultShape):
            let request = try OrthogonalBooleanFacePatchBuilder(
                tolerance: tolerance
            ).request(for: resultShape, featureID: featureID)
            return BooleanExactRegionSelectionGraph(
                decisions: regionSelectionGraph,
                sewingRequest: request
            )
        case let .revolvedBoolean(plan):
            let request = try RevolvedBooleanFacePatchBuilder(
                tolerance: tolerance
            ).request(for: plan, featureID: featureID)
            return BooleanExactRegionSelectionGraph(
                decisions: regionSelectionGraph,
                sewingRequest: request
            )
        case let .partialCylinder(plan):
            let request = try ExactPrismaticFacePatchBuilder(
                tolerance: tolerance
            ).request(
                boundaries: plan.boundaries,
                axis: plan.axis,
                height: plan.height,
                featureID: featureID,
                stablePrefix: "revolved-boolean:partial:\(operation.rawValue)"
            )
            return BooleanExactRegionSelectionGraph(
                decisions: regionSelectionGraph,
                sewingRequest: request
            )
        case let .carriedOperand(bodyID):
            let extraction = try DefaultBRepFacePatchExtractor().extract(
                bodyID: bodyID,
                featureID: featureID,
                from: model,
                sourceSubshapes: subshapes,
                tolerance: tolerance
            )
            return BooleanExactRegionSelectionGraph(
                decisions: regionSelectionGraph,
                sewingRequest: extraction.request
            )
        case let .disjointUnion(plan):
            var sourceModel = model
            let sourceSubshapes = try BRepDisjointUnionEvaluator().addResultBody(
                plan: plan,
                featureID: featureID,
                to: &sourceModel
            )
            try ExactFacePcurveBuilder().populateMissingPcurves(
                in: &sourceModel,
                tolerance: tolerance
            )
            let sourceBodyID = try singleBodyID(in: sourceSubshapes)
            let extraction = try DefaultBRepFacePatchExtractor().extract(
                bodyID: sourceBodyID,
                featureID: featureID,
                from: sourceModel,
                tolerance: tolerance
            )
            var stableSubshapes: [SubshapeID: BRepSewingStableKey] = [:]
            for (subshapeID, reference) in sourceSubshapes {
                guard let stableKey = extraction.sourceStableKeys[reference] else {
                    throw FeatureEvaluationError.invalidGraph(
                        "Disjoint Boolean region selection lost a source topology identity."
                    )
                }
                stableSubshapes[subshapeID] = stableKey
            }
            return BooleanExactRegionSelectionGraph(
                decisions: regionSelectionGraph,
                sewingRequest: extraction.request,
                stableSubshapes: stableSubshapes
            )
        case let .convexPlanarBoolean(target, tool):
            let request = try ConvexPlanarBooleanFacePatchBuilder(
                tolerance: tolerance
            ).request(
                operation: operation,
                target: target,
                tool: tool,
                featureID: featureID
            )
            return BooleanExactRegionSelectionGraph(
                decisions: regionSelectionGraph,
                sewingRequest: request
            )
        }
    }

    public func evaluate(
        operation: BooleanOperation,
        targetBodyIDs: [BodyID],
        toolBodyID: BodyID,
        keepTools: Bool,
        featureID: FeatureID,
        model: BRepModel,
        subshapes: [SubshapeID: TopologyReference],
        toolSubshapes: [SubshapeID: TopologyReference],
        intersectionGraph: BooleanIntersectionGraph,
        uvSplitGraph: BooleanUVSplitGraph,
        classificationGraph: BooleanClassificationGraph,
        exactRegionSelectionGraph: BooleanExactRegionSelectionGraph,
        tolerance: ModelingTolerance
    ) throws -> EvaluationResult {
        // BooleanPipeline owns the fixed phase order. Each phase validates its
        // output before the next phase consumes it, so repeating all geometric
        // residual checks here would repeat the full cost for every complex
        // exact boundary.
        try exactRegionSelectionGraph.validate(
            operation: operation,
            featureID: featureID,
            classificationGraph: classificationGraph,
            tolerance: tolerance
        )
        var resultModel = model
        var removedSubshapeIDs = Set<SubshapeID>()
        var resultSubshapes: [SubshapeID: TopologyReference] = [:]

        if keepTools {
            resultSubshapes = try newlyPublishedToolSubshapes(
                toolSubshapes,
                existingSubshapes: subshapes,
                featureID: featureID
            )
        } else {
            for targetBodyID in targetBodyIDs {
                removedSubshapeIDs.formUnion(
                    subshapeIDsReferencingBodyTopology(
                        bodyID: targetBodyID,
                        in: resultModel,
                        subshapes: subshapes
                    )
                )
                try removeBodyTopology(bodyID: targetBodyID, from: &resultModel)
            }
            removedSubshapeIDs.formUnion(
                subshapeIDsReferencingBodyTopology(
                    bodyID: toolBodyID,
                    in: resultModel,
                    subshapes: subshapes
                )
            )
            try removeBodyTopology(bodyID: toolBodyID, from: &resultModel)
        }

        let sewn = try DefaultBRepSewer().sew(
            exactRegionSelectionGraph.sewingRequest.namespaced(as: .booleanResult),
            tolerance: tolerance
        )
        let builtSubshapes: [SubshapeID: TopologyReference]
        if exactRegionSelectionGraph.stableSubshapes.isEmpty {
            builtSubshapes = try OrthogonalBooleanFacePatchBuilder(
                tolerance: tolerance
            ).generatedSubshapes(
                featureID: featureID,
                stableReferences: sewn.stableReferences
            )
        } else {
            builtSubshapes = try remapStableSubshapes(
                exactRegionSelectionGraph.stableSubshapes,
                sewnStableReferences: sewn.stableReferences
            )
        }
        try BRepModelCombiner().merge(sewn.brep, into: &resultModel)
        for (subshapeID, reference) in builtSubshapes {
            guard resultSubshapes[subshapeID] == nil else {
                throw FeatureEvaluationError.invalidGraph("Boolean generated subshape collision.")
            }
            resultSubshapes[subshapeID] = reference
        }
        var evaluation = EvaluationResult(
            brep: resultModel,
            subshapes: resultSubshapes,
            removedSubshapeIDs: removedSubshapeIDs,
            lineage: remappedSewnLineage(
                builtSubshapes: builtSubshapes,
                sewn: sewn
            )
        )
        if resultModel == sewn.brep {
            evaluation.validatedBRep = sewn.validatedBRep
        }
        return evaluation
    }

    private func remappedSewnLineage(
        builtSubshapes: [SubshapeID: TopologyReference],
        sewn: BRepSewingResult
    ) -> [SubshapeID: TopologyLineage] {
        let sewnIdentityByReference = Dictionary(
            sewn.subshapes.map { ($0.value, $0.key) },
            uniquingKeysWith: { first, _ in first }
        )
        return Dictionary(uniqueKeysWithValues: builtSubshapes.compactMap { output, reference in
            guard let sewnIdentity = sewnIdentityByReference[reference],
                  let lineage = sewn.lineage[sewnIdentity],
                  lineage.parents.isEmpty == false else {
                return nil
            }
            return (
                output,
                TopologyLineage(
                    output: output,
                    parents: lineage.parents,
                    relation: lineage.relation
                )
            )
        })
    }

    private func makePlan(
        operation: BooleanOperation,
        targetBodyIDs: [BodyID],
        toolBodyID: BodyID,
        model: BRepModel,
        tolerance: ModelingTolerance
    ) throws -> BRepBooleanOperationPlan {
        try tolerance.validate()
        guard Set(targetBodyIDs).count == targetBodyIDs.count else {
            throw FeatureEvaluationError.invalidGraph("Boolean target body IDs must be unique.")
        }
        guard targetBodyIDs.contains(toolBodyID) == false else {
            throw FeatureEvaluationError.invalidGraph("Boolean tool body must be distinct from every target body.")
        }
        let targetOperands: [OrthogonalSolidOperand]
        do {
            targetOperands = try targetBodyIDs.map { bodyID in
                try OrthogonalSolidOperand(bodyID: bodyID, in: model, tolerance: tolerance)
            }
        } catch {
            if supportsConvexPlanarMaterialization(operation), targetBodyIDs.count == 1 {
                do {
                    return try convexPlanarBooleanPlan(
                        operation: operation,
                        targetBodyID: targetBodyIDs[0],
                        toolBodyID: toolBodyID,
                        model: model,
                        tolerance: tolerance
                    )
                } catch let planarError as KernelError {
                    if supportsRevolvedBooleanMaterialization(operation),
                       planarError.code == .unsupportedCapability {
                        do {
                            return try revolvedBooleanOperationPlan(
                                operation: operation,
                                targetBodyID: targetBodyIDs[0],
                                toolBodyID: toolBodyID,
                                model: model,
                                tolerance: tolerance
                            )
                        } catch let revolvedError as KernelError {
                            if operation != .union || revolvedError.code != .unsupportedCapability {
                                throw revolvedError
                            }
                        }
                    }
                    if operation != .union || planarError.code != .unsupportedCapability {
                        throw planarError
                    }
                }
            }
            guard operation == .union else {
                throw error
            }
            let plan = try BRepDisjointUnionEvaluator().plan(
                targetBodyIDs: targetBodyIDs,
                toolBodyID: toolBodyID,
                model: model,
                tolerance: tolerance
            )
            return BRepBooleanOperationPlan(
                summary: plan.summary,
                shape: .disjointUnion(plan)
            )
        }
        let toolOperand: OrthogonalSolidOperand
        do {
            toolOperand = try OrthogonalSolidOperand(
                bodyID: toolBodyID,
                in: model,
                tolerance: tolerance
            )
        } catch {
            if supportsConvexPlanarMaterialization(operation), targetBodyIDs.count == 1 {
                do {
                    return try convexPlanarBooleanPlan(
                        operation: operation,
                        targetBodyID: targetBodyIDs[0],
                        toolBodyID: toolBodyID,
                        model: model,
                        tolerance: tolerance
                    )
                } catch let planarError as KernelError {
                    if planarError.code != .unsupportedCapability {
                        throw planarError
                    }
                }
            }
            if supportsRevolvedBooleanMaterialization(operation), targetOperands.count == 1 {
                do {
                    return try revolvedBooleanOperationPlan(
                        operation: operation,
                        targetBodyID: targetBodyIDs[0],
                        toolBodyID: toolBodyID,
                        model: model,
                        tolerance: tolerance
                    )
                } catch let revolvedError as KernelError {
                    if operation != .union || revolvedError.code != .unsupportedCapability {
                        throw revolvedError
                    }
                }
            }
            guard operation == .union else {
                throw error
            }
            let plan = try BRepDisjointUnionEvaluator().plan(
                targetBodyIDs: targetBodyIDs,
                toolBodyID: toolBodyID,
                model: model,
                tolerance: tolerance
            )
            return BRepBooleanOperationPlan(
                summary: plan.summary,
                shape: .disjointUnion(plan)
            )
        }
        let targetCells = targetOperands.flatMap(\.cells)
        let toolCells = toolOperand.cells
        let resultShape = try bodyShape(
            for: operation,
            targets: targetCells,
            tool: toolCells,
            tolerance: tolerance
        )
        guard resultShape.isEmpty == false else {
            throw FeatureEvaluationError.emptyResult("Boolean operation produced no body.")
        }
        let topology = try OrthogonalBooleanFacePatchBuilder(tolerance: tolerance).topology(
            for: resultShape
        )
        return BRepBooleanOperationPlan(
            summary: BRepBooleanPlan(
                operandKind: targetOperands.allSatisfy { $0.cells.count == 1 } && toolOperand.cells.count == 1
                    ? .axisAlignedBoxSolids
                    : .orthogonalCellUnionSolids,
                outputTopologyKind: resultShape.outputTopologyKind,
                topologyNameSchemes: resultShape.topologyNameSchemes,
                topologySlots: topology.slots,
                topologyCounts: topology.counts,
                targetCellCount: targetCells.count,
                toolCellCount: toolCells.count,
                resultPrimitiveCount: resultShape.resultPrimitiveCount
            ),
            shape: .orthogonal(resultShape)
        )
    }

    private func convexPlanarBooleanPlan(
        operation: BooleanOperation,
        targetBodyID: BodyID,
        toolBodyID: BodyID,
        model: BRepModel,
        tolerance: ModelingTolerance
    ) throws -> BRepBooleanOperationPlan {
        let target = try ConvexPlanarSolidOperand(
            bodyID: targetBodyID,
            model: model,
            tolerance: tolerance
        )
        let tool = try ConvexPlanarSolidOperand(
            bodyID: toolBodyID,
            model: model,
            tolerance: tolerance
        )
        let request = try ConvexPlanarBooleanFacePatchBuilder(
            tolerance: tolerance
        ).request(
            operation: operation,
            target: target,
            tool: tool,
            featureID: FeatureID()
        )
        let topology = try OrthogonalBooleanFacePatchBuilder(
            tolerance: tolerance
        ).topology(for: request)
        let outputKind: BooleanEvaluationCapabilities.OutputTopologyKind
        switch operation {
        case .union:
            outputKind = .convexPlanarUnion
        case .difference:
            outputKind = .convexPlanarDifference
        case .intersect:
            outputKind = .convexPlanarIntersection
        case .slice:
            throw KernelError.unsupportedEvaluation(
                tolerance: tolerance,
                message: "Convex planar materialization supports union, difference, and intersection."
            )
        }
        return BRepBooleanOperationPlan(
            summary: BRepBooleanPlan(
                operandKind: .convexPlanarSolids,
                outputTopologyKind: outputKind,
                topologyNameSchemes: [.body, .exactPlanarBoundaryTopology],
                topologySlots: topology.slots,
                topologyCounts: topology.counts,
                targetCellCount: 1,
                toolCellCount: 1,
                resultPrimitiveCount: 1
            ),
            shape: .convexPlanarBoolean(target: target, tool: tool)
        )
    }

    private func revolvedBooleanOperationPlan(
        operation: BooleanOperation,
        targetBodyID: BodyID,
        toolBodyID: BodyID,
        model: BRepModel,
        tolerance: ModelingTolerance
    ) throws -> BRepBooleanOperationPlan {
        let target = try ConvexPlanarSolidOperand(
            bodyID: targetBodyID,
            model: model,
            tolerance: tolerance
        )
        let tool = try RevolvedSolidOperand(
            bodyID: toolBodyID,
            model: model,
            tolerance: tolerance
        )
        let separation = try RevolvedTargetSeparation(
            target: target,
            tool: tool,
            tolerance: tolerance
        )
        if separation.isSeparated {
            switch operation {
            case .union:
                guard let proof = separation.proof else {
                    throw FeatureEvaluationError.invalidGraph(
                        "Revolved Boolean separation lost its analytic witness."
                    )
                }
                let plan = try BRepDisjointUnionEvaluator().plan(
                    targetBodyIDs: [targetBodyID],
                    toolBodyID: toolBodyID,
                    model: model,
                    tolerance: tolerance,
                    separation: proof
                )
                return BRepBooleanOperationPlan(
                    summary: plan.summary,
                    shape: .disjointUnion(plan)
                )
            case .difference:
                return try carriedOperandPlan(
                    bodyID: targetBodyID,
                    model: model,
                    tolerance: tolerance
                )
            case .intersect:
                throw FeatureEvaluationError.emptyResult(
                    "Boolean intersection has no volume because a target supporting plane separates the revolved tool."
                )
            case .slice:
                break
            }
        }
        if separation.isContact {
            let residual = separation.contactResidual ?? 0.0
            switch operation {
            case .union:
                throw KernelError(
                    phase: .topology,
                    code: .nonManifoldResult,
                    residual: residual,
                    tolerance: tolerance,
                    message: "Boolean union of boundary-contacting solids would produce a non-manifold result."
                )
            case .difference:
                return try carriedOperandPlan(
                    bodyID: targetBodyID,
                    model: model,
                    tolerance: tolerance
                )
            case .intersect:
                throw KernelError(
                    phase: .classification,
                    code: .emptyResult,
                    residual: residual,
                    tolerance: tolerance,
                    message: "Boolean intersection of boundary-contacting solids has no volumetric result."
                )
            case .slice:
                break
            }
        }
        let containment = try RevolvedToolContainment(
            target: target,
            tool: tool,
            tolerance: tolerance
        )
        if containment.containsTarget {
            switch operation {
            case .union:
                return try carriedOperandPlan(
                    bodyID: toolBodyID,
                    model: model,
                    tolerance: tolerance
                )
            case .intersect:
                return try carriedOperandPlan(
                    bodyID: targetBodyID,
                    model: model,
                    tolerance: tolerance
                )
            case .difference:
                throw FeatureEvaluationError.emptyResult(
                    "Boolean difference removed a target fully contained by its revolved tool."
                )
            case .slice:
                break
            }
        }
        let revolved: RevolvedBooleanPlan
        do {
            revolved = try RevolvedBooleanPlan(
                operation: operation,
                target: target,
                tool: tool,
                tolerance: tolerance
            )
        } catch let error as KernelError where error.code == .unsupportedCapability {
            return try partialCylinderOperationPlan(
                operation: operation,
                target: target,
                tool: tool,
                tolerance: tolerance
            )
        }
        let request = try RevolvedBooleanFacePatchBuilder(
            tolerance: tolerance
        ).request(for: revolved, featureID: FeatureID())
        let topology = try OrthogonalBooleanFacePatchBuilder(
            tolerance: tolerance
        ).topology(for: request)
        let outputTopologyKind: BooleanEvaluationCapabilities.OutputTopologyKind
        switch operation {
        case .union:
            outputTopologyKind = .revolvedUnion
        case .difference:
            if revolved.createsEnclosedCavity {
                outputTopologyKind = .revolvedCavity
            } else if revolved.differenceOpensLowerCap && revolved.differenceOpensUpperCap {
                outputTopologyKind = .revolvedThroughHole
            } else {
                outputTopologyKind = .revolvedBlindHole
            }
        case .intersect:
            outputTopologyKind = .revolvedIntersection
        case .slice:
            throw KernelError.unsupportedEvaluation(
                tolerance: tolerance,
                message: "Revolved Boolean materialization supports union, difference, and intersection."
            )
        }
        return BRepBooleanOperationPlan(
            summary: BRepBooleanPlan(
                operandKind: .planarAndRevolvedSolids,
                outputTopologyKind: outputTopologyKind,
                topologyNameSchemes: [.body, .curvedBoundaryTopology],
                topologySlots: topology.slots,
                topologyCounts: topology.counts,
                targetCellCount: 1,
                toolCellCount: 1,
                resultPrimitiveCount: 1
            ),
            shape: .revolvedBoolean(revolved)
        )
    }

    private func partialCylinderOperationPlan(
        operation: BooleanOperation,
        target: ConvexPlanarSolidOperand,
        tool: RevolvedSolidOperand,
        tolerance: ModelingTolerance
    ) throws -> BRepBooleanOperationPlan {
        let plan = try ConvexPolygonCircleBooleanPlan(
            operation: operation,
            target: target,
            tool: tool,
            tolerance: tolerance
        )
        let request = try ExactPrismaticFacePatchBuilder(
            tolerance: tolerance
        ).request(
            boundaries: plan.boundaries,
            axis: plan.axis,
            height: plan.height,
            featureID: FeatureID(),
            stablePrefix: "revolved-boolean:partial:\(operation.rawValue)"
        )
        let topology = try OrthogonalBooleanFacePatchBuilder(
            tolerance: tolerance
        ).topology(for: request)
        let outputTopologyKind: BooleanEvaluationCapabilities.OutputTopologyKind
        switch operation {
        case .union:
            outputTopologyKind = .partialCylinderUnion
        case .difference:
            outputTopologyKind = .partialCylinderDifference
        case .intersect:
            outputTopologyKind = .partialCylinderIntersection
        case .slice:
            throw KernelError.unsupportedEvaluation(
                tolerance: tolerance,
                message: "Partial-cylinder materialization supports union, difference, and intersection."
            )
        }
        return BRepBooleanOperationPlan(
            summary: BRepBooleanPlan(
                operandKind: .planarAndRevolvedSolids,
                outputTopologyKind: outputTopologyKind,
                topologyNameSchemes: [.body, .curvedBoundaryTopology],
                topologySlots: topology.slots,
                topologyCounts: topology.counts,
                targetCellCount: 1,
                toolCellCount: 1,
                resultPrimitiveCount: plan.boundaries.count
            ),
            shape: .partialCylinder(plan)
        )
    }

    private func carriedOperandPlan(
        bodyID: BodyID,
        model: BRepModel,
        tolerance: ModelingTolerance
    ) throws -> BRepBooleanOperationPlan {
        let extraction = try DefaultBRepFacePatchExtractor().extract(
            bodyID: bodyID,
            featureID: FeatureID(),
            from: model,
            tolerance: tolerance
        )
        let topology = try OrthogonalBooleanFacePatchBuilder(
            tolerance: tolerance
        ).topology(for: extraction.request)
        return BRepBooleanOperationPlan(
            summary: BRepBooleanPlan(
                operandKind: .planarAndRevolvedSolids,
                outputTopologyKind: .carriedOperand,
                topologyNameSchemes: [.body, .copiedSourceTopology],
                topologySlots: topology.slots,
                topologyCounts: topology.counts,
                targetCellCount: 1,
                toolCellCount: 1,
                resultPrimitiveCount: 1
            ),
            shape: .carriedOperand(bodyID: bodyID)
        )
    }

    private func supportsRevolvedBooleanMaterialization(
        _ operation: BooleanOperation
    ) -> Bool {
        operation == .union || operation == .difference || operation == .intersect
    }

    private func supportsConvexPlanarMaterialization(
        _ operation: BooleanOperation
    ) -> Bool {
        operation == .union || operation == .difference || operation == .intersect
    }

    private func bodyShape(
        for operation: BooleanOperation,
        targets: [AxisAlignedBox],
        tool: [AxisAlignedBox],
        tolerance: ModelingTolerance
    ) throws -> BooleanBodyShape {
        let targetCells = try normalizedCells(targets, tolerance: tolerance)
        let toolCells = try normalizedCells(tool, tolerance: tolerance)
        switch operation {
        case .union:
            return try compactedShape(from: targetCells + toolCells, tolerance: tolerance)
        case .difference:
            if toolCells.count == 1 {
                return try differenceBoxes(targets: targetCells, tool: toolCells[0], tolerance: tolerance)
            }
            return try differenceCells(targets: targetCells, tools: toolCells, tolerance: tolerance)
        case .intersect:
            return try intersectCells(targets: targetCells, tools: toolCells, tolerance: tolerance)
        case .slice:
            return .boxes(try sliceCells(targets: targetCells, tools: toolCells, tolerance: tolerance))
        }
    }

    private func compactedShape(
        from boxes: [AxisAlignedBox],
        tolerance: ModelingTolerance
    ) throws -> BooleanBodyShape {
        let cells = try normalizedCells(boxes, tolerance: tolerance)
        guard cells.isEmpty == false else {
            throw FeatureEvaluationError.emptyResult("Boolean operation produced no body.")
        }
        if let singleBox = rectangularUnion(of: cells, tolerance: tolerance) {
            return .boxes([singleBox])
        }
        if boxesAreSeparated(cells, tolerance: tolerance) {
            return .boxes(cells)
        }
        return .orthogonalCellUnion(cells)
    }

    private func differenceBoxes(
        targets: [AxisAlignedBox],
        tool: AxisAlignedBox,
        tolerance: ModelingTolerance
    ) throws -> BooleanBodyShape {
        var result: [AxisAlignedBox] = []
        var frames: [ZThroughBoxFrame] = []
        for target in targets {
            let fragments = target.subtracting(tool, tolerance: tolerance)
            if fragments.isEmpty {
                continue
            }
            if let rectangularResult = rectangularUnion(of: fragments, tolerance: tolerance) {
                result.append(rectangularResult)
                continue
            }
            guard boxesAreSeparated(fragments, tolerance: tolerance) else {
                if let frame = target.zThroughFrame(cutBy: tool, tolerance: tolerance) {
                    frames.append(frame)
                    continue
                }
                // Fold connected fragments into the shared accumulator so the
                // final combined pass below resolves them together with every
                // other target. Returning this target's cell union mid-loop
                // silently discarded the other targets' geometry while
                // evaluate() still removed all target bodies.
                result.append(contentsOf: fragments)
                continue
            }
            result.append(contentsOf: fragments)
        }
        guard frames.isEmpty else {
            guard result.isEmpty, frames.count == 1 else {
                throw KernelError.unsupportedEvaluation(tolerance: tolerance, message:
                    "Box difference frame results cannot be mixed with other target fragments."
                )
            }
            return .zThroughFrame(frames[0])
        }
        if let rectangularResult = rectangularUnion(of: result, tolerance: tolerance) {
            return .boxes([rectangularResult])
        }
        guard boxesAreSeparated(result, tolerance: tolerance) else {
            return .orthogonalCellUnion(try normalizedCells(result, tolerance: tolerance))
        }
        return .boxes(result)
    }

    private func differenceCells(
        targets: [AxisAlignedBox],
        tools: [AxisAlignedBox],
        tolerance: ModelingTolerance
    ) throws -> BooleanBodyShape {
        var fragments = targets
        for tool in tools {
            fragments = fragments.flatMap { fragment in
                fragment.subtracting(tool, tolerance: tolerance)
            }
            guard fragments.isEmpty == false else {
                throw FeatureEvaluationError.emptyResult("Boolean difference produced no body.")
            }
        }
        return try compactedShape(from: fragments, tolerance: tolerance)
    }

    private func intersectCells(
        targets: [AxisAlignedBox],
        tools: [AxisAlignedBox],
        tolerance: ModelingTolerance
    ) throws -> BooleanBodyShape {
        let intersections = targets.flatMap { target in
            tools.compactMap { tool in
                target.intersection(with: tool, tolerance: tolerance)
            }
        }
        guard intersections.isEmpty == false else {
            throw FeatureEvaluationError.emptyResult("Boolean intersection produced no body.")
        }
        return try compactedShape(from: intersections, tolerance: tolerance)
    }

    private func sliceCells(
        targets: [AxisAlignedBox],
        tools: [AxisAlignedBox],
        tolerance: ModelingTolerance
    ) throws -> [AxisAlignedBox] {
        var result: [AxisAlignedBox] = []
        for target in targets {
            var fragments = [target]
            for tool in tools {
                fragments = fragments.flatMap { fragment in
                    fragment.sliced(by: tool, tolerance: tolerance)
                }
            }
            result.append(contentsOf: fragments)
        }
        let cells = try normalizedCells(result, tolerance: tolerance)
        guard cells.isEmpty == false else {
            throw FeatureEvaluationError.emptyResult("Boolean slice produced no body.")
        }
        return cells
    }

    private func normalizedCells(
        _ boxes: [AxisAlignedBox],
        tolerance: ModelingTolerance
    ) throws -> [AxisAlignedBox] {
        guard boxes.isEmpty == false else {
            return []
        }
        let xCoordinates = uniqueSorted(boxes.flatMap { [$0.minimum.x, $0.maximum.x] }, tolerance: tolerance)
        let yCoordinates = uniqueSorted(boxes.flatMap { [$0.minimum.y, $0.maximum.y] }, tolerance: tolerance)
        let zCoordinates = uniqueSorted(boxes.flatMap { [$0.minimum.z, $0.maximum.z] }, tolerance: tolerance)
        guard xCoordinates.count >= 2,
              yCoordinates.count >= 2,
              zCoordinates.count >= 2 else {
            return []
        }
        var cells: [AxisAlignedBox] = []
        for xIndex in 0..<(xCoordinates.count - 1) {
            for yIndex in 0..<(yCoordinates.count - 1) {
                for zIndex in 0..<(zCoordinates.count - 1) {
                    let minimum = Point3D(
                        x: xCoordinates[xIndex],
                        y: yCoordinates[yIndex],
                        z: zCoordinates[zIndex]
                    )
                    let maximum = Point3D(
                        x: xCoordinates[xIndex + 1],
                        y: yCoordinates[yIndex + 1],
                        z: zCoordinates[zIndex + 1]
                    )
                    let center = Point3D(
                        x: (minimum.x + maximum.x) * 0.5,
                        y: (minimum.y + maximum.y) * 0.5,
                        z: (minimum.z + maximum.z) * 0.5
                    )
                    guard boxes.contains(where: { $0.contains(center) }) else {
                        continue
                    }
                    cells.append(try AxisAlignedBox(minimum: minimum, maximum: maximum, tolerance: tolerance))
                }
            }
        }
        return cells
    }

    private func rectangularUnion(
        of boxes: [AxisAlignedBox],
        tolerance: ModelingTolerance
    ) -> AxisAlignedBox? {
        guard let boundingBox = AxisAlignedBox.bounding(boxes) else {
            return nil
        }
        // Combinatorial rectangularity: split the bounding box along every input
        // coordinate and require every cell center to be covered by some box.
        // The previous volume-difference budget applied the linear tolerance as
        // an absolute volume (1e-6 m^3 for bodies up to 1 m^3), so any cut
        // smaller than that vanished silently: subtracting a 5 mm pocket from a
        // 100 mm plate returned the uncut bounding box. Any uncovered cell is at
        // least tolerance-sized by construction, so nothing real is swallowed.
        let xCoordinates = uniqueSorted(boxes.flatMap { [$0.minimum.x, $0.maximum.x] }, tolerance: tolerance)
        let yCoordinates = uniqueSorted(boxes.flatMap { [$0.minimum.y, $0.maximum.y] }, tolerance: tolerance)
        let zCoordinates = uniqueSorted(boxes.flatMap { [$0.minimum.z, $0.maximum.z] }, tolerance: tolerance)
        guard xCoordinates.count >= 2,
              yCoordinates.count >= 2,
              zCoordinates.count >= 2 else {
            return nil
        }
        for xIndex in 0..<(xCoordinates.count - 1) {
            for yIndex in 0..<(yCoordinates.count - 1) {
                for zIndex in 0..<(zCoordinates.count - 1) {
                    let center = Point3D(
                        x: (xCoordinates[xIndex] + xCoordinates[xIndex + 1]) * 0.5,
                        y: (yCoordinates[yIndex] + yCoordinates[yIndex + 1]) * 0.5,
                        z: (zCoordinates[zIndex] + zCoordinates[zIndex + 1]) * 0.5
                    )
                    guard boxes.contains(where: { $0.contains(center) }) else {
                        return nil
                    }
                }
            }
        }
        return boundingBox
    }

    private func boxesAreSeparated(
        _ boxes: [AxisAlignedBox],
        tolerance: ModelingTolerance
    ) -> Bool {
        for firstIndex in boxes.indices {
            for secondIndex in boxes.indices where secondIndex > firstIndex {
                guard boxes[firstIndex].isSeparated(from: boxes[secondIndex], tolerance: tolerance) else {
                    return false
                }
            }
        }
        return true
    }

    private func subshapeIDsReferencingBodyTopology(
        bodyID: BodyID,
        in model: BRepModel,
        subshapes: [SubshapeID: TopologyReference]
    ) -> Set<SubshapeID> {
        let references = topologyReferences(for: bodyID, in: model)
        return Set(subshapes.compactMap { subshapeID, reference in
            references.contains(reference) ? subshapeID : nil
        })
    }

    private func topologyReferences(for bodyID: BodyID, in model: BRepModel) -> Set<TopologyReference> {
        guard let body = model.bodies[bodyID] else {
            return []
        }
        var references: Set<TopologyReference> = [.body(bodyID)]
        for shellID in body.shellIDs {
            guard let shell = model.shells[shellID] else {
                continue
            }
            for faceID in shell.faceIDs {
                references.insert(.face(faceID))
                guard let face = model.faces[faceID] else {
                    continue
                }
                for loopID in face.loops {
                    guard let loop = model.loops[loopID] else {
                        continue
                    }
                    for orientedEdge in loop.edges {
                        references.insert(.edge(orientedEdge.edgeID))
                        guard let edge = model.edges[orientedEdge.edgeID] else {
                            continue
                        }
                        references.insert(.vertex(edge.startVertexID))
                        references.insert(.vertex(edge.endVertexID))
                    }
                }
            }
        }
        return references
    }

    private func removeBodyTopology(bodyID: BodyID, from model: inout BRepModel) throws {
        guard let body = model.bodies.removeValue(forKey: bodyID) else {
            throw TopologyError.missingReference("Missing boolean body \(bodyID).")
        }
        var surfaceIDs = Set<SurfaceID>()
        var curveIDs = Set<CurveID>()
        var loopIDs = Set<LoopID>()
        var edgeIDs = Set<EdgeID>()
        var vertexIDs = Set<VertexID>()

        for shellID in body.shellIDs {
            guard let shell = model.shells.removeValue(forKey: shellID) else {
                throw TopologyError.missingReference("Missing boolean shell \(shellID).")
            }
            for faceID in shell.faceIDs {
                guard let face = model.faces.removeValue(forKey: faceID) else {
                    throw TopologyError.missingReference("Missing boolean face \(faceID).")
                }
                surfaceIDs.insert(face.surfaceID)
                for loopID in face.loops {
                    loopIDs.insert(loopID)
                }
            }
        }
        for loopID in loopIDs {
            guard let loop = model.loops.removeValue(forKey: loopID) else {
                throw TopologyError.missingReference("Missing boolean loop \(loopID).")
            }
            for orientedEdge in loop.edges {
                edgeIDs.insert(orientedEdge.edgeID)
            }
        }
        for edgeID in edgeIDs {
            guard let edge = model.edges.removeValue(forKey: edgeID) else {
                throw TopologyError.missingReference("Missing boolean edge \(edgeID).")
            }
            curveIDs.insert(edge.curveID)
            vertexIDs.insert(edge.startVertexID)
            vertexIDs.insert(edge.endVertexID)
        }
        for vertexID in vertexIDs {
            model.vertices.removeValue(forKey: vertexID)
        }
        for curveID in curveIDs {
            model.geometry.curves.removeValue(forKey: curveID)
        }
        for surfaceID in surfaceIDs {
            model.geometry.surfaces.removeValue(forKey: surfaceID)
        }
    }

    private func newlyPublishedToolSubshapes(
        _ subshapes: [SubshapeID: TopologyReference],
        existingSubshapes: [SubshapeID: TopologyReference],
        featureID: FeatureID
    ) throws -> [SubshapeID: TopologyReference] {
        let indexedReferences = Set(existingSubshapes.values)
        var remapped: [SubshapeID: TopologyReference] = [:]
        for (sourceID, reference) in subshapes {
            guard indexedReferences.contains(reference) == false else {
                continue
            }
            let remappedID = SubshapeID(
                featureID: featureID,
                role: SubshapeIdentityRole.compose(
                    generatedRole: sourceID.role,
                    subshapeRole: "tool"
                ),
                ordinal: sourceID.ordinal
            )
            guard remapped[remappedID] == nil else {
                throw FeatureEvaluationError.invalidGraph("Boolean tool subshape collision.")
            }
            remapped[remappedID] = reference
        }
        return remapped
    }

    private func singleBodyID(
        in subshapes: [SubshapeID: TopologyReference]
    ) throws -> BodyID {
        let bodyIDs = Set(subshapes.values.compactMap { reference -> BodyID? in
            guard case let .body(bodyID) = reference else { return nil }
            return bodyID
        })
        guard bodyIDs.count == 1, let bodyID = bodyIDs.first else {
            throw FeatureEvaluationError.invalidGraph(
                "Boolean topology source must publish exactly one result body."
            )
        }
        return bodyID
    }

    private func remapStableSubshapes(
        _ subshapes: [SubshapeID: BRepSewingStableKey],
        sewnStableReferences: [BRepSewingStableKey: TopologyReference]
    ) throws -> [SubshapeID: TopologyReference] {
        var result: [SubshapeID: TopologyReference] = [:]
        for (subshapeID, stableKey) in subshapes {
            guard let sewnReference = sewnStableReferences[stableKey] else {
                throw FeatureEvaluationError.invalidGraph(
                    "Boolean sewing did not preserve a generated topology reference."
                )
            }
            result[subshapeID] = sewnReference
        }
        return result
    }

}

private struct BRepBooleanOperationPlan: Sendable {
    var summary: BRepBooleanPlan
    var shape: BRepBooleanOperationShape
}

private enum BRepBooleanOperationShape: Sendable {
    case orthogonal(BooleanBodyShape)
    case revolvedBoolean(RevolvedBooleanPlan)
    case partialCylinder(ConvexPolygonCircleBooleanPlan)
    case carriedOperand(bodyID: BodyID)
    case disjointUnion(BRepDisjointUnionPlan)
    case convexPlanarBoolean(
        target: ConvexPlanarSolidOperand,
        tool: ConvexPlanarSolidOperand
    )
}

struct AxisAlignedBox: Sendable, Hashable {
    var minimum: Point3D
    var maximum: Point3D

    init(minimum: Point3D, maximum: Point3D, tolerance: ModelingTolerance) throws {
        try tolerance.validate()
        guard maximum.x - minimum.x > tolerance.distance,
              maximum.y - minimum.y > tolerance.distance,
              maximum.z - minimum.z > tolerance.distance else {
            throw FeatureEvaluationError.emptyResult("Orthogonal Boolean produced a collapsed body.")
        }
        self.minimum = minimum
        self.maximum = maximum
    }

    init(bodyID: BodyID, in model: BRepModel, tolerance: ModelingTolerance) throws {
        try tolerance.validate()
        guard let body = model.bodies[bodyID] else {
            throw TopologyError.missingReference("Missing boolean target body \(bodyID).")
        }
        guard body.kind == .solid,
              body.shellIDs.count == 1,
              let shellID = body.shellIDs.first,
              let shell = model.shells[shellID],
              shell.faceIDs.count == 6 else {
            throw KernelError.unsupportedEvaluation(tolerance: tolerance, message:
                "Orthogonal Boolean requires one closed orthogonal solid shell."
            )
        }

        var faceIDs = Set<FaceID>()
        var loopIDs = Set<LoopID>()
        var edgeIDs = Set<EdgeID>()
        var vertexIDs = Set<VertexID>()
        for faceID in shell.faceIDs {
            guard let face = model.faces[faceID],
                  case .plane = model.geometry.surfaces[face.surfaceID] else {
                throw KernelError.unsupportedEvaluation(tolerance: tolerance, message:
                    "Orthogonal Boolean requires planar faces."
                )
            }
            faceIDs.insert(faceID)
            for loopID in face.loops {
                loopIDs.insert(loopID)
                guard let loop = model.loops[loopID] else {
                    throw TopologyError.missingReference("Missing boolean loop \(loopID).")
                }
                for orientedEdge in loop.edges {
                    edgeIDs.insert(orientedEdge.edgeID)
                }
            }
        }
        guard faceIDs.count == 6,
              loopIDs.count == 6,
              edgeIDs.count == 12 else {
            throw KernelError.unsupportedEvaluation(tolerance: tolerance, message:
                "Orthogonal Boolean source decomposition requires rectangular-prism cells."
            )
        }
        for edgeID in edgeIDs {
            guard let edge = model.edges[edgeID],
                  case .line = model.geometry.curves[edge.curveID] else {
                throw KernelError.unsupportedEvaluation(tolerance: tolerance, message:
                    "Orthogonal Boolean requires linear edges."
                )
            }
            vertexIDs.insert(edge.startVertexID)
            vertexIDs.insert(edge.endVertexID)
        }
        guard vertexIDs.count == 8 else {
            throw KernelError.unsupportedEvaluation(tolerance: tolerance, message:
                "Orthogonal Boolean source cells require eight vertices."
            )
        }
        let points = try vertexIDs.map { vertexID -> Point3D in
            guard let point = model.vertices[vertexID]?.point else {
                throw TopologyError.missingReference("Missing boolean vertex \(vertexID).")
            }
            return point
        }
        let minimum = Point3D(
            x: points.map(\.x).min() ?? 0.0,
            y: points.map(\.y).min() ?? 0.0,
            z: points.map(\.z).min() ?? 0.0
        )
        let maximum = Point3D(
            x: points.map(\.x).max() ?? 0.0,
            y: points.map(\.y).max() ?? 0.0,
            z: points.map(\.z).max() ?? 0.0
        )
        try self.init(minimum: minimum, maximum: maximum, tolerance: tolerance)
        try validateCorners(points, tolerance: tolerance)
    }

    var volume: Double {
        (maximum.x - minimum.x) * (maximum.y - minimum.y) * (maximum.z - minimum.z)
    }

    func intersection(with other: AxisAlignedBox, tolerance: ModelingTolerance) -> AxisAlignedBox? {
        let minimum = Point3D(
            x: max(self.minimum.x, other.minimum.x),
            y: max(self.minimum.y, other.minimum.y),
            z: max(self.minimum.z, other.minimum.z)
        )
        let maximum = Point3D(
            x: min(self.maximum.x, other.maximum.x),
            y: min(self.maximum.y, other.maximum.y),
            z: min(self.maximum.z, other.maximum.z)
        )
        guard maximum.x - minimum.x > tolerance.distance,
              maximum.y - minimum.y > tolerance.distance,
              maximum.z - minimum.z > tolerance.distance else {
            return nil
        }
        return AxisAlignedBox(uncheckedMinimum: minimum, uncheckedMaximum: maximum)
    }

    func subtracting(_ tool: AxisAlignedBox, tolerance: ModelingTolerance) -> [AxisAlignedBox] {
        guard let intersection = intersection(with: tool, tolerance: tolerance) else {
            return [self]
        }
        return partitioned(by: intersection, tolerance: tolerance).filter { fragment in
            let center = fragment.center
            return intersection.contains(center) == false
        }
    }

    func sliced(by tool: AxisAlignedBox, tolerance: ModelingTolerance) -> [AxisAlignedBox] {
        guard let intersection = intersection(with: tool, tolerance: tolerance) else {
            return [self]
        }
        return partitioned(by: intersection, tolerance: tolerance)
    }

    fileprivate func zThroughFrame(cutBy tool: AxisAlignedBox, tolerance: ModelingTolerance) -> ZThroughBoxFrame? {
        guard let hole = intersection(with: tool, tolerance: tolerance),
              abs(hole.minimum.z - minimum.z) <= tolerance.distance,
              abs(hole.maximum.z - maximum.z) <= tolerance.distance,
              hole.minimum.x - minimum.x > tolerance.distance,
              maximum.x - hole.maximum.x > tolerance.distance,
              hole.minimum.y - minimum.y > tolerance.distance,
              maximum.y - hole.maximum.y > tolerance.distance else {
            return nil
        }
        return ZThroughBoxFrame(outer: self, hole: hole)
    }

    var center: Point3D {
        Point3D(
            x: (minimum.x + maximum.x) * 0.5,
            y: (minimum.y + maximum.y) * 0.5,
            z: (minimum.z + maximum.z) * 0.5
        )
    }

    private func partitioned(by intersection: AxisAlignedBox, tolerance: ModelingTolerance) -> [AxisAlignedBox] {
        var xCoordinates = uniqueSorted(
            [minimum.x, intersection.minimum.x, intersection.maximum.x, maximum.x],
            tolerance: tolerance
        )
        var yCoordinates = uniqueSorted(
            [minimum.y, intersection.minimum.y, intersection.maximum.y, maximum.y],
            tolerance: tolerance
        )
        var zCoordinates = uniqueSorted(
            [minimum.z, intersection.minimum.z, intersection.maximum.z, maximum.z],
            tolerance: tolerance
        )
        xCoordinates = xCoordinates.filter { $0 >= minimum.x - tolerance.distance && $0 <= maximum.x + tolerance.distance }
        yCoordinates = yCoordinates.filter { $0 >= minimum.y - tolerance.distance && $0 <= maximum.y + tolerance.distance }
        zCoordinates = zCoordinates.filter { $0 >= minimum.z - tolerance.distance && $0 <= maximum.z + tolerance.distance }
        var fragments: [AxisAlignedBox] = []
        for xIndex in 0..<(xCoordinates.count - 1) {
            for yIndex in 0..<(yCoordinates.count - 1) {
                for zIndex in 0..<(zCoordinates.count - 1) {
                    let cellMinimum = Point3D(
                        x: xCoordinates[xIndex],
                        y: yCoordinates[yIndex],
                        z: zCoordinates[zIndex]
                    )
                    let cellMaximum = Point3D(
                        x: xCoordinates[xIndex + 1],
                        y: yCoordinates[yIndex + 1],
                        z: zCoordinates[zIndex + 1]
                    )
                    guard cellMaximum.x - cellMinimum.x > tolerance.distance,
                          cellMaximum.y - cellMinimum.y > tolerance.distance,
                          cellMaximum.z - cellMinimum.z > tolerance.distance else {
                        continue
                    }
                    fragments.append(AxisAlignedBox(
                        uncheckedMinimum: cellMinimum,
                        uncheckedMaximum: cellMaximum
                    ))
                }
            }
        }
        return fragments
    }

    func contains(_ point: Point3D) -> Bool {
        point.x >= minimum.x && point.x <= maximum.x
            && point.y >= minimum.y && point.y <= maximum.y
            && point.z >= minimum.z && point.z <= maximum.z
    }

    func isSeparated(from other: AxisAlignedBox, tolerance: ModelingTolerance) -> Bool {
        maximum.x < other.minimum.x - tolerance.distance
            || other.maximum.x < minimum.x - tolerance.distance
            || maximum.y < other.minimum.y - tolerance.distance
            || other.maximum.y < minimum.y - tolerance.distance
            || maximum.z < other.minimum.z - tolerance.distance
            || other.maximum.z < minimum.z - tolerance.distance
    }

    static func bounding(_ boxes: [AxisAlignedBox]) -> AxisAlignedBox? {
        guard let first = boxes.first else {
            return nil
        }
        return boxes.dropFirst().reduce(first) { partial, box in
            AxisAlignedBox(
                uncheckedMinimum: Point3D(
                    x: min(partial.minimum.x, box.minimum.x),
                    y: min(partial.minimum.y, box.minimum.y),
                    z: min(partial.minimum.z, box.minimum.z)
                ),
                uncheckedMaximum: Point3D(
                    x: max(partial.maximum.x, box.maximum.x),
                    y: max(partial.maximum.y, box.maximum.y),
                    z: max(partial.maximum.z, box.maximum.z)
                )
            )
        }
    }

    static func unionVolume(of boxes: [AxisAlignedBox], tolerance: ModelingTolerance) -> Double {
        let xCoordinates = uniqueSorted(boxes.flatMap { [$0.minimum.x, $0.maximum.x] }, tolerance: tolerance)
        let yCoordinates = uniqueSorted(boxes.flatMap { [$0.minimum.y, $0.maximum.y] }, tolerance: tolerance)
        let zCoordinates = uniqueSorted(boxes.flatMap { [$0.minimum.z, $0.maximum.z] }, tolerance: tolerance)
        guard xCoordinates.count >= 2,
              yCoordinates.count >= 2,
              zCoordinates.count >= 2 else {
            return 0.0
        }
        var volume = 0.0
        for xIndex in 0..<(xCoordinates.count - 1) {
            for yIndex in 0..<(yCoordinates.count - 1) {
                for zIndex in 0..<(zCoordinates.count - 1) {
                    let center = Point3D(
                        x: (xCoordinates[xIndex] + xCoordinates[xIndex + 1]) * 0.5,
                        y: (yCoordinates[yIndex] + yCoordinates[yIndex + 1]) * 0.5,
                        z: (zCoordinates[zIndex] + zCoordinates[zIndex + 1]) * 0.5
                    )
                    guard boxes.contains(where: { $0.contains(center) }) else {
                        continue
                    }
                    volume += (xCoordinates[xIndex + 1] - xCoordinates[xIndex])
                        * (yCoordinates[yIndex + 1] - yCoordinates[yIndex])
                        * (zCoordinates[zIndex + 1] - zCoordinates[zIndex])
                }
            }
        }
        return volume
    }

    private init(uncheckedMinimum: Point3D, uncheckedMaximum: Point3D) {
        minimum = uncheckedMinimum
        maximum = uncheckedMaximum
    }

    private func validateCorners(_ points: [Point3D], tolerance: ModelingTolerance) throws {
        var cornerKeys = Set<String>()
        for point in points {
            let xKey = try axisKey(value: point.x, minimum: minimum.x, maximum: maximum.x, tolerance: tolerance)
            let yKey = try axisKey(value: point.y, minimum: minimum.y, maximum: maximum.y, tolerance: tolerance)
            let zKey = try axisKey(value: point.z, minimum: minimum.z, maximum: maximum.z, tolerance: tolerance)
            cornerKeys.insert("\(xKey):\(yKey):\(zKey)")
        }
        guard cornerKeys.count == 8 else {
            throw KernelError.unsupportedEvaluation(tolerance: tolerance, message:
                "Orthogonal Boolean requires axis-aligned cell corners."
            )
        }
    }

    private func axisKey(
        value: Double,
        minimum: Double,
        maximum: Double,
        tolerance: ModelingTolerance
    ) throws -> String {
        if abs(value - minimum) <= tolerance.distance {
            return "min"
        }
        if abs(value - maximum) <= tolerance.distance {
            return "max"
        }
        throw KernelError.unsupportedEvaluation(tolerance: tolerance, message:
            "Orthogonal Boolean requires axis-aligned cell vertices."
        )
    }
}

enum BooleanBodyShape: Sendable {
    case boxes([AxisAlignedBox])
    case orthogonalCellUnion([AxisAlignedBox])
    case zThroughFrame(ZThroughBoxFrame)

    var isEmpty: Bool {
        switch self {
        case let .boxes(boxes):
            return boxes.isEmpty
        case let .orthogonalCellUnion(cells):
            return cells.isEmpty
        case .zThroughFrame:
            return false
        }
    }

    var outputTopologyKind: BooleanEvaluationCapabilities.OutputTopologyKind {
        switch self {
        case .boxes(let boxes) where boxes.count == 1:
            return .singleBox
        case .boxes:
            return .separatedBoxes
        case .orthogonalCellUnion:
            return .orthogonalCellUnion
        case .zThroughFrame:
            return .zThroughFrame
        }
    }

    var resultPrimitiveCount: Int {
        switch self {
        case .boxes(let boxes):
            return boxes.count
        case .orthogonalCellUnion(let cells):
            return cells.count
        case .zThroughFrame:
            return 1
        }
    }

    var topologyNameSchemes: [BooleanEvaluationCapabilities.TopologyNameScheme] {
        [.body, .orthogonalBoundaryTopology]
    }
}

struct ZThroughBoxFrame: Sendable, Hashable {
    var outer: AxisAlignedBox
    var hole: AxisAlignedBox
}

func uniqueSorted(_ values: [Double], tolerance: ModelingTolerance) -> [Double] {
    let sorted = values.sorted()
    var result: [Double] = []
    for value in sorted {
        guard let last = result.last else {
            result.append(value)
            continue
        }
        if abs(value - last) > tolerance.distance {
            result.append(value)
        }
    }
    return result
}
