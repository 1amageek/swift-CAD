import CADCore
import CADIR
import CADModeling
import CADTopology
import CADGeometry

public enum BooleanPipelinePhase: String, Hashable, Sendable, CaseIterable {
    case operandValidation
    case facePairBroadPhase
    case faceIntersection
    case uvFaceSplitting
    case pointInSolidClassification
    case resultRegionSelection
    case sewing
    case topologyValidation
    case lineageGeneration
}

/// Fixed-order orchestration boundary for exact Boolean evaluators.
/// The concrete evaluator may reject a phase when its declared capability is incomplete,
/// but it cannot silently bypass validation or return an unvalidated B-rep.
public struct BooleanPipeline: Sendable {
    let preparationOwner: BooleanPreparationOwner
    private struct BoundaryContactCacheKey: Hashable {
        let edgeID: EdgeID
        let surfaceID: SurfaceID
    }

    private enum BoundaryContactCacheEntry {
        case empty
        case geometry(BooleanBoundaryContactGeometry)
    }

    private let evaluator: any BRepBooleanEvaluating
    private let intersector: any CurveSurfaceIntersecting
    private let surfaceIntersector: any SurfaceSurfaceIntersecting
    private let boundedSurfaceIntersector: any BoundedSurfaceSurfaceIntersecting
    private let uvFaceSplitter: any BooleanUVFaceSplitting
    private let regionClassifier: any BooleanRegionClassifying
    private let regionSelector: any BooleanResultRegionSelecting

    public init(
        evaluator: any BRepBooleanEvaluating,
        intersector: any CurveSurfaceIntersecting = DefaultCurveSurfaceIntersector(),
        surfaceIntersector: any SurfaceSurfaceIntersecting = DefaultSurfaceSurfaceIntersector(),
        boundedSurfaceIntersector: any BoundedSurfaceSurfaceIntersecting = DefaultBoundedSurfaceSurfaceIntersector(),
        uvFaceSplitter: any BooleanUVFaceSplitting = DefaultBooleanUVFaceSplitter(),
        regionClassifier: any BooleanRegionClassifying = DefaultBooleanRegionClassifier(),
        regionSelector: any BooleanResultRegionSelecting = DefaultBooleanResultRegionSelector()
    ) {
        preparationOwner = BooleanPreparationOwner()
        self.evaluator = evaluator
        self.intersector = intersector
        self.surfaceIntersector = surfaceIntersector
        self.boundedSurfaceIntersector = boundedSurfaceIntersector
        self.uvFaceSplitter = uvFaceSplitter
        self.regionClassifier = regionClassifier
        self.regionSelector = regionSelector
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
        inputLineage: [SubshapeID: TopologyLineage] = [:],
        materials: BooleanMaterials = .default,
        tolerance: ModelingTolerance,
        prepared: PreparedBooleanIntersection? = nil
    ) throws -> EvaluationResult {
        var execution: OriginalQueryExecution
        if let prepared { execution = try prepared.lifetime.execution() }
        else { execution = try OriginalQueryExecution.kernelOriginal() }
        return try evaluate(operation: operation, targetBodyIDs: targetBodyIDs, toolBodyID: toolBodyID, keepTools: keepTools, featureID: featureID, model: model, subshapes: subshapes, toolSubshapes: toolSubshapes, inputLineage: inputLineage, materials: materials, tolerance: tolerance, prepared: prepared, using: &execution)
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
        inputLineage: [SubshapeID: TopologyLineage] = [:],
        materials: BooleanMaterials = .default,
        tolerance: ModelingTolerance,
        prepared: PreparedBooleanIntersection? = nil,
        using execution: inout OriginalQueryExecution) throws -> EvaluationResult {
        if let prepared {
            return try prepared.lifetime.withRead(using: &execution) { execution in
                try perform(using: &execution)
            }
        }
        return try perform(using: &execution)
        func perform(using execution: inout OriginalQueryExecution) throws -> EvaluationResult {
      do {
        do {
            try CurrentTaskCancellationChecker().checkCancellation()
            try prepared?.validateBinding(model: model, targetBodyIDs: targetBodyIDs,
                toolBodyID: toolBodyID, tolerance: tolerance, owner: preparationOwner)
            let operands = BooleanOperandContext(
                targetBodyIDs: targetBodyIDs,
                toolBodyID: toolBodyID,
                solidities: try BooleanOperandSolidities.resolve(
                    materials,
                    targetBodyIDs: targetBodyIDs,
                    toolBodyID: toolBodyID,
                    model: model,
                    tolerance: tolerance
                )
            )
            let intersectionGraph: BooleanIntersectionGraph
            do {
                intersectionGraph = try prepared?.intersectionGraph ?? self.intersectionGraph(
                    targetBodyIDs: targetBodyIDs,
                    toolBodyID: toolBodyID,
                    operation: operation,
                    model: model,
                    operands: operands,
                    tolerance: tolerance,
                using: &execution)
            } catch {
                throw contextualized(
                    error,
                    stage: "intersection graph construction",
                    tolerance: tolerance
                )
            }
            let uvSplitGraph: BooleanUVSplitGraph
            do {
                uvSplitGraph = try prepared?.uvSplitGraph ?? self.uvSplitGraph(
                    intersectionGraph: intersectionGraph,
                    model: model,
                    tolerance: tolerance
                , using: &execution)
            } catch {
                throw contextualized(
                    error,
                    stage: "UV split graph construction",
                    tolerance: tolerance
                )
            }
            let classificationGraph: BooleanClassificationGraph
            do {
                classificationGraph = try self.classificationGraph(
                    uvSplitGraph: uvSplitGraph,
                    targetBodyIDs: targetBodyIDs,
                    toolBodyID: toolBodyID,
                    model: model,
                    operands: operands,
                    tolerance: tolerance
                , using: &execution)
            } catch {
                throw contextualized(
                    error,
                    stage: "classification graph construction",
                    tolerance: tolerance
                )
            }
            let regionSelectionGraph: BooleanRegionSelectionGraph
            do {
                regionSelectionGraph = try self.regionSelectionGraph(
                    operation: operation,
                    classificationGraph: classificationGraph,
                    rule: operands.rule,
                    tolerance: tolerance
                , using: &execution)
            } catch {
                throw contextualized(
                    error,
                    stage: "region selection graph construction",
                    tolerance: tolerance
                )
            }
            let exactRegionSelectionGraph: BooleanExactRegionSelectionGraph
            do {
                exactRegionSelectionGraph = try evaluator.exactRegionSelection(
                    operation: operation,
                    targetBodyIDs: targetBodyIDs,
                    toolBodyID: toolBodyID,
                    featureID: featureID,
                    model: model,
                    subshapes: subshapes,
                    uvSplitGraph: uvSplitGraph,
                    regionSelectionGraph: regionSelectionGraph,
                    operands: operands,
                    tolerance: tolerance
                , using: &execution)
            } catch {
                throw contextualized(
                    error,
                    stage: "exact region materialization",
                    tolerance: tolerance
                )
            }

            // Exact selected regions are the sole input to the sewing phase.
            var result: EvaluationResult
            do {
                result = try evaluator.evaluate(
                    operation: operation,
                    targetBodyIDs: targetBodyIDs,
                    toolBodyID: toolBodyID,
                    keepTools: keepTools,
                    featureID: featureID,
                    model: model,
                    subshapes: subshapes,
                    toolSubshapes: toolSubshapes,
                    intersectionGraph: intersectionGraph,
                    uvSplitGraph: uvSplitGraph,
                    classificationGraph: classificationGraph,
                    exactRegionSelectionGraph: exactRegionSelectionGraph,
                    operands: operands,
                    tolerance: tolerance,
                using: &execution)
            } catch {
                throw contextualized(
                    error,
                    stage: "exact sewing evaluation",
                    tolerance: tolerance
                )
            }
            let topologyLineage: [SubshapeID: TopologyLineage]
            do {
                // Lineage uses the same cumulative owner as the preceding Boolean phases.
                var lineageInputs = subshapes

                    for _ in subshapes.keys {
                        try execution.consumeWork(1)
                    }
                    let retainedBytes = subshapes.count.multipliedReportingOverflow(
                        by: MemoryLayout<(SubshapeID, TopologyReference)>.stride)
                    guard !retainedBytes.overflow else {
                        throw GeometryConversionError.resourceLimitExceeded("Boolean lineage input storage overflowed.")
                    }
                    try execution.retainStorage(bytes: retainedBytes.partialValue)

                for (id, reference) in toolSubshapes {
                    try CurrentTaskCancellationChecker().checkCancellation()
                    try execution.consumeWork(1)
                    if lineageInputs[id] == nil {
                        try execution.retainStorage(bytes: MemoryLayout<(SubshapeID, TopologyReference)>.stride)
                        lineageInputs[id] = reference
                    }
                }
                var lineageOperands = targetBodyIDs

                    for _ in targetBodyIDs { try execution.consumeWork(1)
            }
                    let count = targetBodyIDs.count.addingReportingOverflow(1)
                    let bytes = count.partialValue.multipliedReportingOverflow(by: MemoryLayout<BodyID>.stride)
                    guard !count.overflow, !bytes.overflow else {
                        throw GeometryConversionError.resourceLimitExceeded("Boolean lineage operand storage overflowed.")
                    }
                    try execution.retainStorage(bytes: bytes.partialValue)

                lineageOperands.append(toolBodyID)
                topologyLineage = try BooleanTopologyLineageBuilder().build(
                    featureID: featureID,
                    operandBodyIDs: lineageOperands,
                    inputModel: model,
                    resultModel: result.brep,
                    inputSubshapes: lineageInputs,
                    outputSubshapes: result.subshapes,
                    inputLineage: inputLineage,
                    tolerance: tolerance,
                    retainedLineage: result.lineage,
                    using: &execution
                )
            } catch {
                throw contextualized(
                    error,
                    stage: "topology lineage construction",
                    tolerance: tolerance
                )
            }
            result.lineage = topologyLineage
            try CurrentTaskCancellationChecker().checkCancellation()
            return result
        } catch {
            let classification = OriginalQueryFailure.classification(of: error) ?? KernelError.wrapping(
                error,
                phase: .topology,
                featureID: featureID,
                tolerance: tolerance
            )
            throw OriginalQueryFailure.contextualizing(error, classification: classification)
        }

      } catch { throw OriginalQueryFailure.published(error, context: execution.context, tolerance: tolerance) }
        }
    }

    private func contextualized(
        _ error: any Error,
        stage: String,
        tolerance: ModelingTolerance
    ) -> any Error {
        let wrapped = OriginalQueryFailure.classification(of: error) ?? KernelError.wrapping(error, phase: .topology, tolerance: tolerance)
        let classification = KernelError(
            phase: wrapped.phase,
            code: wrapped.code,
            featureID: wrapped.featureID,
            subshapeID: wrapped.subshapeID,
            residual: wrapped.residual,
            tolerance: wrapped.tolerance ?? tolerance,
            message: "Boolean \(stage) failed: \(wrapped.message)"
        )
        return OriginalQueryFailure.contextualizing(error, classification: classification)
    }

    /// The intersection graph of one pass; `operands` default to both taken as solid volumes.
    public func intersectionGraph(
        targetBodyIDs: [BodyID],
        toolBodyID: BodyID,
        operation: BooleanOperation,
        model: BRepModel,
        operands: BooleanOperandContext? = nil,
        tolerance: ModelingTolerance
    ) throws -> BooleanIntersectionGraph {
        var execution = try OriginalQueryExecution.kernelOriginal()
        return try intersectionGraph(targetBodyIDs: targetBodyIDs, toolBodyID: toolBodyID, operation: operation, model: model, operands: operands, tolerance: tolerance, using: &execution)
    }

    public func intersectionGraph(
        targetBodyIDs: [BodyID],
        toolBodyID: BodyID,
        operation: BooleanOperation,
        model: BRepModel,
        operands: BooleanOperandContext? = nil,
        tolerance: ModelingTolerance,
        using execution: inout OriginalQueryExecution) throws -> BooleanIntersectionGraph {
      do {
        try operandValidation(
            targetBodyIDs: targetBodyIDs,
            toolBodyID: toolBodyID,
            model: model,
            tolerance: tolerance, using: &execution
        )
        let requirement = try evaluator.intersectionRequirement(
            operation: operation,
            targetBodyIDs: targetBodyIDs,
            toolBodyID: toolBodyID,
            model: model,
            operands: operands ?? .volumes(targetBodyIDs: targetBodyIDs, toolBodyID: toolBodyID),
            tolerance: tolerance
        , using: &execution)
        if case .provenEmpty = requirement {
            return BooleanIntersectionGraph(
                facePairs: [],
                boundaryContacts: [],
                faceIntersections: []
            )
        }
        let facePairs = try facePairBroadPhase(
            targetBodyIDs: targetBodyIDs,
            toolBodyID: toolBodyID,
            operation: operation,
            in: model,
            tolerance: tolerance,
            using: &execution)
        let graph = try faceIntersection(
            facePairs: facePairs,
            in: model,
            tolerance: tolerance,
            using: &execution)
        try graph.validate(in: model, tolerance: tolerance, using: &execution)
        return graph

      } catch { throw OriginalQueryFailure.published(error, context: execution.context, tolerance: tolerance) }
    }

    /// Builds the complete geometric intersection graph without accepting an
    /// evaluator-specific empty-intersection shortcut.
    // FIXME(INCOMPLETE_IMPLEMENTATION): This caller-admitted graph route meters
    // original graph/bounds/contact visits and forwards bounded SSI admission.
    // Geometry's retained coefficient allocation accounting and complete critical,
    // coincident and unbounded SSI producers remain required before whole Q2/B2
    // resource/completeness guarantees can be claimed. No legacy producer fallback
    // is permitted in this route.
    public func completeIntersectionGraph(
        targetBodyIDs: [BodyID], toolBodyID: BodyID, operation: BooleanOperation,
        validatedModel: ValidatedBRepModel,
        using execution: inout OriginalQueryExecution
    ) throws -> BooleanIntersectionGraph {
      do {
        let tolerance = validatedModel.tolerance
        try execution.consumeWork(1)
        guard validatedModel.validationLevel != .modeling, !targetBodyIDs.isEmpty else {
            throw KernelError(phase: .validation, code: .invalidInput, tolerance: tolerance,
                message: "Original graph construction requires an exact immutable model and target operands.")
        }
        let model = validatedModel.model
        var operands: Set<BodyID> = [toolBodyID]
        for bodyID in targetBodyIDs {
            try execution.consumeWork(1)
            guard operands.insert(bodyID).inserted else {
                throw KernelError(phase: .validation, code: .invalidInput, tolerance: tolerance,
                    message: "Original graph operands must be distinct.")
            }
        }
        for bodyID in operands {
            try execution.consumeWork(1)
            guard model.bodies[bodyID] != nil else {
                throw KernelError(phase: .validation, code: .missingReference, tolerance: tolerance,
                    message: "An original graph operand is missing from its immutable model.")
            }
        }
        let pairs = try facePairBroadPhase(targetBodyIDs: targetBodyIDs, toolBodyID: toolBodyID,
            operation: operation, in: model, tolerance: tolerance, using: &execution)
        let graph = try faceIntersection(facePairs: pairs, in: model,
            tolerance: tolerance, using: &execution)
        try graph.validate(in: model, tolerance: tolerance, using: &execution)
        try execution.consumeWork(1)
        return graph

      } catch { throw OriginalQueryFailure.published(error, context: execution.context, tolerance: validatedModel.tolerance) }
    }

    func completeIntersectionGraph(
        targetBodyIDs: [BodyID],
        toolBodyID: BodyID,
        operation: BooleanOperation,
        model: BRepModel,
        tolerance: ModelingTolerance
    ) throws -> BooleanIntersectionGraph {
        var execution = try OriginalQueryExecution.kernelOriginal()
        return try completeIntersectionGraph(targetBodyIDs: targetBodyIDs, toolBodyID: toolBodyID, operation: operation, model: model, tolerance: tolerance, using: &execution)
    }

    func completeIntersectionGraph(
        targetBodyIDs: [BodyID],
        toolBodyID: BodyID,
        operation: BooleanOperation,
        model: BRepModel,
        tolerance: ModelingTolerance,
        using execution: inout OriginalQueryExecution) throws -> BooleanIntersectionGraph {
        try operandValidation(
            targetBodyIDs: targetBodyIDs,
            toolBodyID: toolBodyID,
            model: model,
            tolerance: tolerance, using: &execution
        )
        let facePairs = try facePairBroadPhase(
            targetBodyIDs: targetBodyIDs,
            toolBodyID: toolBodyID,
            operation: operation,
            in: model,
            tolerance: tolerance,
            using: &execution)
        let graph = try faceIntersection(
            facePairs: facePairs,
            in: model,
            tolerance: tolerance,
            using: &execution)
        try graph.validate(in: model, tolerance: tolerance, using: &execution)
        return graph
    }

    /// Prepares complete original intersections for explicitly selected finite faces.
    /// Incident faces may share a body; their original ownership and topology are retained.
    public func completeIntersectionGraph(
        facePairs: [BooleanFacePairCandidate],
        model: BRepModel,
        tolerance: ModelingTolerance
    ) throws -> BooleanIntersectionGraph {
        var execution = try OriginalQueryExecution.kernelOriginal()
        return try completeIntersectionGraph(facePairs: facePairs, model: model, tolerance: tolerance, using: &execution)
    }

    public func completeIntersectionGraph(
        facePairs: [BooleanFacePairCandidate],
        model: BRepModel,
        tolerance: ModelingTolerance,
        using execution: inout OriginalQueryExecution) throws -> BooleanIntersectionGraph {
      do {
        try CurrentTaskCancellationChecker().checkCancellation()
        try tolerance.validate()
        try model.validate(tolerance: tolerance, using: &execution)
        let ordered = try orderedFiniteFacePairs(facePairs, in: model,
            tolerance: tolerance, using: &execution)
        let graph = try faceIntersection(facePairs: ordered, in: model, tolerance: tolerance, using: &execution)
        try graph.validate(in: model, tolerance: tolerance, using: &execution)
        try execution.checkpoint()
        return graph

      } catch { throw OriginalQueryFailure.published(error, context: execution.context, tolerance: tolerance) }
    }

    /// Complete authored finite-face graph bound to one immutable admitted source.
    public func completeIntersectionGraph(
        facePairs: [BooleanFacePairCandidate], validatedModel: ValidatedBRepModel,
        using execution: inout OriginalQueryExecution
    ) throws -> BooleanIntersectionGraph {
      do {
        let tolerance = validatedModel.tolerance
        try execution.consumeWork(1)
        guard validatedModel.validationLevel != .modeling else {
            throw KernelError(phase: .validation, code: .invalidInput, tolerance: tolerance,
                message: "Finite-face preparation requires the immutable exact original source.")
        }
        let model = validatedModel.model
        let ordered = try orderedFiniteFacePairs(facePairs, in: model,
            tolerance: tolerance, using: &execution)
        // FIXME(INCOMPLETE_IMPLEMENTATION): This finite-face factory forwards
        // actual original graph/SSI callbacks and reuses the exact source receipt.
        // Complete lower SSI critical/coincident/unbounded coverage and its
        // temporary byte producers remain required for the whole query guarantee.
        let graph = try faceIntersection(facePairs: ordered, in: model,
            tolerance: tolerance, using: &execution)
        try graph.validate(in: model, tolerance: tolerance, using: &execution)
        try execution.consumeWork(1)
        return graph

      } catch { throw OriginalQueryFailure.published(error, context: execution.context, tolerance: validatedModel.tolerance) }
    }

    private func orderedFiniteFacePairs(_ pairs: [BooleanFacePairCandidate],
        in model: BRepModel, tolerance: ModelingTolerance,
        using execution: inout OriginalQueryExecution) throws -> [BooleanFacePairCandidate] {
        var seen: Set<BooleanFacePairCandidate> = []
        var ordered: [BooleanFacePairCandidate] = []
        try OriginalParameterQueryStorage.reserve(pairs.count, in: &ordered, using: &execution)
        for pair in pairs {
            try execution.consumeWork(1)
            guard pair.targetFaceID != pair.toolFaceID else {
                throw KernelError(phase: .validation, code: .invalidInput, tolerance: tolerance,
                    message: "Finite-face preparation requires distinct original faces.")
            }
            guard try OriginalParameterQueryStorage.insert(pair, in: &seen, using: &execution) else {
                throw KernelError(phase: .validation, code: .invalidInput, tolerance: tolerance,
                    message: "Finite-face preparation requires unique original face pairs.")
            }
            guard model.faces[pair.targetFaceID] != nil, model.faces[pair.toolFaceID] != nil else {
                throw KernelError(phase: .validation, code: .missingReference, tolerance: tolerance,
                    message: "A finite-face source pair is absent from its original model.")
            }
            ordered.append(pair)
        }
        try OriginalParameterQueryStorage.sort(&ordered, using: &execution) { first, second in
            first.targetFaceID == second.targetFaceID
                ? first.toolFaceID < second.toolFaceID : first.targetFaceID < second.targetFaceID
        }
        try execution.checkpoint()
        return ordered
    }

    public func uvSplitGraph(
        intersectionGraph: BooleanIntersectionGraph,
        model: BRepModel,
        tolerance: ModelingTolerance
    ) throws -> BooleanUVSplitGraph {
        var execution = try OriginalQueryExecution.kernelOriginal()
        return try uvSplitGraph(intersectionGraph: intersectionGraph, model: model,
            tolerance: tolerance, using: &execution)
    }

    public func uvSplitGraph(
        intersectionGraph: BooleanIntersectionGraph,
        model: BRepModel,
        tolerance: ModelingTolerance
    ,
        using execution: inout OriginalQueryExecution
    ) throws -> BooleanUVSplitGraph {
        try uvFaceSplitter.splitGraph(
            intersectionGraph: intersectionGraph,
            model: model,
            tolerance: tolerance, using: &execution
        )
    }

    /// The classification graph of one pass; `operands` default to both taken as solid volumes.
    public func classificationGraph(
        uvSplitGraph: BooleanUVSplitGraph,
        targetBodyIDs: [BodyID],
        toolBodyID: BodyID,
        model: BRepModel,
        operands: BooleanOperandContext? = nil,
        tolerance: ModelingTolerance
    ) throws -> BooleanClassificationGraph {
        var execution = try OriginalQueryExecution.kernelOriginal()
        return try classificationGraph(uvSplitGraph: uvSplitGraph, targetBodyIDs: targetBodyIDs,
            toolBodyID: toolBodyID, model: model, operands: operands, tolerance: tolerance, using: &execution)
    }

    public func classificationGraph(
        uvSplitGraph: BooleanUVSplitGraph,
        targetBodyIDs: [BodyID],
        toolBodyID: BodyID,
        model: BRepModel,
        operands: BooleanOperandContext? = nil,
        tolerance: ModelingTolerance
    ,
        using execution: inout OriginalQueryExecution
    ) throws -> BooleanClassificationGraph {
        try regionClassifier.classificationGraph(
            uvSplitGraph: uvSplitGraph,
            targetBodyIDs: targetBodyIDs,
            toolBodyID: toolBodyID,
            model: model,
            operands: operands ?? .volumes(targetBodyIDs: targetBodyIDs, toolBodyID: toolBodyID),
            tolerance: tolerance, using: &execution
        )
    }

    /// The region selection of one pass; `rule` defaults to both operands taken as solid volumes.
    public func regionSelectionGraph(
        operation: BooleanOperation,
        classificationGraph: BooleanClassificationGraph,
        rule: BooleanRegionSelectionRule = BooleanRegionSelectionRule(solidities: .volumes),
        tolerance: ModelingTolerance
    ) throws -> BooleanRegionSelectionGraph {
        var execution = try OriginalQueryExecution.kernelOriginal()
        return try regionSelectionGraph(operation: operation, classificationGraph: classificationGraph,
            rule: rule, tolerance: tolerance, using: &execution)
    }

    public func regionSelectionGraph(
        operation: BooleanOperation,
        classificationGraph: BooleanClassificationGraph,
        rule: BooleanRegionSelectionRule = BooleanRegionSelectionRule(solidities: .volumes),
        tolerance: ModelingTolerance
    ,
        using execution: inout OriginalQueryExecution
    ) throws -> BooleanRegionSelectionGraph {
        try regionSelector.selectionGraph(
            operation: operation,
            classificationGraph: classificationGraph,
            rule: rule,
            tolerance: tolerance, using: &execution
        )
    }

    private func operandValidation(
        targetBodyIDs: [BodyID],
        toolBodyID: BodyID,
        model: BRepModel,
        tolerance: ModelingTolerance,
        using execution: inout OriginalQueryExecution
    ) throws {
        try tolerance.validate()
        guard !targetBodyIDs.isEmpty,
              Set(targetBodyIDs).count == targetBodyIDs.count,
              !targetBodyIDs.contains(toolBodyID) else {
            throw KernelError(
                phase: .validation,
                code: .invalidInput,
                tolerance: tolerance,
                message: "Boolean operands must be distinct and contain at least one target."
            )
        }
        for bodyID in targetBodyIDs + [toolBodyID] {
            guard model.bodies[bodyID] != nil else {
                throw KernelError(
                    phase: .validation,
                    code: .missingReference,
                    tolerance: tolerance,
                    message: "Boolean operand body is missing."
                )
            }
        }
        try model.validate(tolerance: tolerance, using: &execution)
    }

    private func facePairBroadPhase(
        targetBodyIDs: [BodyID],
        toolBodyID: BodyID,
        operation: BooleanOperation,
        in model: BRepModel,
        tolerance: ModelingTolerance,
        using execution: inout OriginalQueryExecution
    ) throws -> [BooleanFacePairCandidate] {
        let toolFaceIDs = try faceIDs(for: toolBodyID, in: model, tolerance: tolerance, using: &execution)
        var preparedToolBounds: [FaceID: BoundingBox3D] = [:]

            for faceID in toolFaceIDs {
                try execution.retainKernelValues(count: 1, stride: MemoryLayout<FaceID>.stride + MemoryLayout<BoundingBox3D>.stride)
                preparedToolBounds[faceID] = try bounds(for: faceID, in: model,
                    tolerance: tolerance, using: &execution)
            }

        var candidates: [BooleanFacePairCandidate] = []
        for targetBodyID in targetBodyIDs {
            try execution.consumeWork(1)
            for targetFaceID in try faceIDs(
                for: targetBodyID,
                in: model,
                tolerance: tolerance,
                using: &execution
            ) {
                try execution.consumeWork(1)
                let targetBounds = try bounds(
                    for: targetFaceID,
                    in: model,
                    tolerance: tolerance,
                    using: &execution
                )
                for toolFaceID in toolFaceIDs {
                    try execution.consumeWork(1)
                    let toolBounds = try preparedToolBounds[toolFaceID] ?? bounds(
                        for: toolFaceID,
                        in: model,
                        tolerance: tolerance,
                        using: &execution
                    )
                    guard targetBounds.intersects(
                        toolBounds,
                        tolerance: tolerance.distance
                    ) else {
                        continue
                    }
                    try execution.retainKernelValues(count: 1, stride: MemoryLayout<BooleanFacePairCandidate>.stride)
                    candidates.append(BooleanFacePairCandidate(
                        targetFaceID: targetFaceID,
                        toolFaceID: toolFaceID
                    ))
                }
            }
        }
        try execution.retainKernelValues(count: candidates.count, stride: MemoryLayout<BooleanFacePairCandidate>.stride)
        return try candidates.sorted {
            try execution.consumeWork(1)
            if $0.targetFaceID != $1.targetFaceID {
                return $0.targetFaceID < $1.targetFaceID
            }
            return $0.toolFaceID < $1.toolFaceID
        }
    }

    private func faceIntersection(
        facePairs: [BooleanFacePairCandidate],
        in model: BRepModel,
        tolerance: ModelingTolerance,
        using execution: inout OriginalQueryExecution
    ) throws -> BooleanIntersectionGraph {
        var contacts: [BooleanBoundaryContact] = []
        var faceIntersections: [BooleanFaceSurfaceIntersection] = []
        var boundaryContactCache: [
            BoundaryContactCacheKey: BoundaryContactCacheEntry
        ] = [:]
        var admittedSurfaceCache: [SurfaceID: [SurfaceID: [SurfaceSurfaceIntersection]]] = [:]
        for pair in facePairs {
            try execution.consumeWork(1)
            let targetBoundaryContacts = try boundaryContacts(
                curveFaceID: pair.targetFaceID,
                surfaceFaceID: pair.toolFaceID,
                in: model,
                cache: &boundaryContactCache,
                tolerance: tolerance,
                using: &execution
            )
            let toolBoundaryContacts = try boundaryContacts(
                curveFaceID: pair.toolFaceID,
                surfaceFaceID: pair.targetFaceID,
                in: model,
                cache: &boundaryContactCache,
                tolerance: tolerance,
                using: &execution
            )
            try execution.retainKernelValues(count: targetBoundaryContacts.count, stride: MemoryLayout<BooleanBoundaryContact>.stride)
            try execution.retainKernelValues(count: toolBoundaryContacts.count, stride: MemoryLayout<BooleanBoundaryContact>.stride)
            contacts.append(contentsOf: targetBoundaryContacts)
            contacts.append(contentsOf: toolBoundaryContacts)
            guard let targetFace = model.faces[pair.targetFaceID],
                  let toolFace = model.faces[pair.toolFaceID],
                  let targetSurface = model.geometry.surfaces[targetFace.surfaceID],
                  let toolSurface = model.geometry.surfaces[toolFace.surfaceID] else {
                throw KernelError(
                    phase: .geometry,
                    code: .missingReference,
                    tolerance: tolerance,
                    message: "Boolean surface intersection references missing face geometry."
                )
            }
            let intersections: [SurfaceSurfaceIntersection]
            var boundaryPoints: [Point3D] = []
            try execution.retainKernelValues(count: targetBoundaryContacts.count + toolBoundaryContacts.count,
                stride: MemoryLayout<BooleanBoundaryContact>.stride)
            for contact in targetBoundaryContacts + toolBoundaryContacts {
                try execution.consumeWork(1)
                guard case let .points(values) = contact.geometry else { continue }
                for value in values {
                    try execution.retainKernelValues(count: 1, stride: MemoryLayout<Point3D>.stride)
                    boundaryPoints.append(value.point)
                }
            }
            do {

                    if let bounded = try boundedSurfaceIntersector.intersections(first: targetSurface,
                        second: toolSurface, boundaryPoints: boundaryPoints, options: .init(),
                        tolerance: tolerance, using: &execution) {
                        intersections = bounded
                    } else if let cached = admittedSurfaceCache[targetFace.surfaceID]?[toolFace.surfaceID] {
                        intersections = cached
                    } else {
                        intersections = try surfaceIntersector.intersections(first: targetSurface,
                            second: toolSurface, options: .init(), tolerance: tolerance,
                            using: &execution)
                        try execution.retainKernelValues(count: intersections.count, stride: MemoryLayout<SurfaceSurfaceIntersection>.stride)
                        try execution.retainKernelValues(count: 2, stride: MemoryLayout<SurfaceID>.stride)
                        admittedSurfaceCache[targetFace.surfaceID, default: [:]][toolFace.surfaceID] = intersections
                    }

            } catch {
                let wrapped = OriginalQueryFailure.classification(of: error) ?? KernelError.wrapping(
                    error,
                    phase: .geometry,
                    tolerance: tolerance
                )
                let classification = KernelError(
                    phase: wrapped.phase,
                    code: wrapped.code,
                    featureID: wrapped.featureID,
                    subshapeID: wrapped.subshapeID,
                    residual: wrapped.residual,
                    tolerance: wrapped.tolerance ?? tolerance,
                    message: "Boolean face-pair intersection failed for target face \(pair.targetFaceID) on surface \(targetFace.surfaceID) and tool face \(pair.toolFaceID) on surface \(toolFace.surfaceID): \(wrapped.message)"
                )
                throw OriginalQueryFailure.contextualizing(error, classification: classification)
            }
            for intersection in intersections {
                try execution.retainKernelValues(count: 1, stride: MemoryLayout<BooleanFaceSurfaceIntersection>.stride)
                faceIntersections.append(BooleanFaceSurfaceIntersection(facePair: pair, geometry: intersection))
            }
        }
        try execution.retainKernelValues(count: contacts.count, stride: MemoryLayout<BooleanBoundaryContact>.stride)
        let orderedContacts = try contacts.sorted {
            try execution.consumeWork(1)
            if $0.curveFaceID != $1.curveFaceID { return $0.curveFaceID < $1.curveFaceID }
            if $0.surfaceFaceID != $1.surfaceFaceID { return $0.surfaceFaceID < $1.surfaceFaceID }
            return $0.edgeID < $1.edgeID
        }
        return BooleanIntersectionGraph(
            facePairs: facePairs,
            boundaryContacts: orderedContacts,
            faceIntersections: faceIntersections
        )
    }

    private func boundaryContacts(
        curveFaceID: FaceID,
        surfaceFaceID: FaceID,
        in model: BRepModel,
        cache: inout [BoundaryContactCacheKey: BoundaryContactCacheEntry],
        tolerance: ModelingTolerance,
        using execution: inout OriginalQueryExecution
    ) throws -> [BooleanBoundaryContact] {
        guard let curveFace = model.faces[curveFaceID],
              let surfaceFace = model.faces[surfaceFaceID],
              let surface = model.geometry.surfaces[surfaceFace.surfaceID] else {
            throw KernelError(
                phase: .geometry,
                code: .missingReference,
                tolerance: tolerance,
                message: "Boolean face-pair intersection references missing face geometry."
            )
        }
        let edgeIDs = try Set(curveFace.loops.flatMap { loopID -> [EdgeID] in
            try execution.consumeWork(1)
            guard let loop = model.loops[loopID] else {
                throw KernelError(
                    phase: .topology,
                    code: .missingReference,
                    tolerance: tolerance,
                    message: "Boolean face-pair intersection references a missing loop."
                )
            }
            return try loop.coedges.map { coedge in
                try execution.consumeWork(1)
                return coedge.edgeID
            }
        }).sorted { first, second in
            try execution.consumeWork(1)
            return first < second
        }
        var contacts: [BooleanBoundaryContact] = []
        for edgeID in edgeIDs {
            try execution.consumeWork(1)
            let key = BoundaryContactCacheKey(
                edgeID: edgeID,
                surfaceID: surfaceFace.surfaceID
            )
            if let cached = cache[key] {
                if case let .geometry(geometry) = cached {
                    try execution.retainKernelValues(count: 1, stride: MemoryLayout<BooleanBoundaryContact>.stride)
                    contacts.append(BooleanBoundaryContact(
                        edgeID: edgeID,
                        curveFaceID: curveFaceID,
                        surfaceFaceID: surfaceFaceID,
                        geometry: geometry
                    ))
                }
                continue
            }
            guard let edge = model.edges[edgeID],
                  let curve = model.geometry.curves[edge.curveID] else {
                throw KernelError(
                    phase: .geometry,
                    code: .missingReference,
                    tolerance: tolerance,
                    message: "Boolean face-pair intersection references missing edge geometry."
                )
            }
            let options = CurveSurfaceIntersectionOptions(
                curveRange: try curveRange(for: edge, curve: curve, in: model, tolerance: tolerance)
            )
            do {
                let intersections: [CurveSurfaceIntersection]

                    intersections = try intersector.intersections(curve: curve, surface: surface,
                        options: options, tolerance: tolerance,
                        using: &execution)

                if intersections.isEmpty == false {
                    let geometry = BooleanBoundaryContactGeometry.points(intersections)
                    try execution.retainKernelValues(count: 1, stride: MemoryLayout<BoundaryContactCacheKey>.stride + MemoryLayout<BoundaryContactCacheEntry>.stride)
                    try execution.retainKernelValues(count: intersections.count, stride: MemoryLayout<CurveSurfaceIntersection>.stride)
                    cache[key] = .geometry(geometry)
                    try execution.retainKernelValues(count: 1, stride: MemoryLayout<BooleanBoundaryContact>.stride)
                    contacts.append(BooleanBoundaryContact(
                        edgeID: edgeID,
                        curveFaceID: curveFaceID,
                        surfaceFaceID: surfaceFaceID,
                        geometry: geometry
                    ))
                } else {
                    try execution.retainKernelValues(count: 1, stride: MemoryLayout<BoundaryContactCacheKey>.stride + MemoryLayout<BoundaryContactCacheEntry>.stride)
                    cache[key] = .empty
                }
            } catch let error where OriginalQueryFailure.classification(of: error)?.code == .nonDiscreteIntersection {
            guard let errorClassification = OriginalQueryFailure.classification(of: error) else { throw error }
                try execution.retainKernelValues(count: 1, stride: MemoryLayout<BoundaryContactCacheKey>.stride + MemoryLayout<BoundaryContactCacheEntry>.stride)
                cache[key] = .geometry(.coincident)
                try execution.retainKernelValues(count: 1, stride: MemoryLayout<BooleanBoundaryContact>.stride)
                contacts.append(BooleanBoundaryContact(
                    edgeID: edgeID,
                    curveFaceID: curveFaceID,
                    surfaceFaceID: surfaceFaceID,
                    geometry: .coincident
                ))
            }
        }
        return contacts
    }

    private func curveRange(
        for edge: Edge,
        curve: Curve3D,
        in model: BRepModel,
        tolerance: ModelingTolerance
    ) throws -> ScalarInterval {
        if let trim = edge.trim {
            return try ScalarInterval(
                lower: min(trim.startParameter, trim.endParameter),
                upper: max(trim.startParameter, trim.endParameter)
            )
        }
        guard let startPoint = model.vertices[edge.startVertexID]?.point,
              let endPoint = model.vertices[edge.endVertexID]?.point else {
            throw KernelError(
                phase: .topology,
                code: .missingReference,
                tolerance: tolerance,
                message: "Boolean edge range references missing vertices."
            )
        }
        guard let line = lineGeometry(curve) else {
            throw KernelError(
                phase: .topology,
                code: .topologyFailure,
                tolerance: tolerance,
                message: "A bounded non-line edge must persist an explicit curve trim."
            )
        }
        let directionSquared = line.direction.dot(line.direction)
        guard directionSquared > tolerance.distance * tolerance.distance else {
            throw KernelError(
                phase: .geometry,
                code: .invalidInput,
                tolerance: tolerance,
                message: "Boolean edge line has a degenerate direction."
            )
        }
        let start = (startPoint - line.origin).dot(line.direction) / directionSquared
        let end = (endPoint - line.origin).dot(line.direction) / directionSquared
        return try ScalarInterval(lower: min(start, end), upper: max(start, end))
    }

    private func lineGeometry(_ curve: Curve3D) -> Line3D? {
        switch curve {
        case let .line(line):
            return line
        case let .analytic(.line(origin, direction)):
            return Line3D(origin: origin, direction: direction)
        case let .rigidImage(image):
            guard let source = lineGeometry(image.source) else { return nil }
            return Line3D(
                origin: image.transform.applying(to: source.origin),
                direction: image.transform.applying(to: source.direction)
            )
        case let .affineImage(image):
            guard let source = lineGeometry(image.source) else { return nil }
            return Line3D(
                origin: image.transform.applying(to: source.origin),
                direction: image.transform.applying(to: source.direction)
            )
        case .circle, .analytic, .bSpline, .implicit, .surfaceLift,
             .certifiedIntersection, .parameterImage, .originalConstructionChart, .originalEndpointConnector,
             .originalAngularTransport, .originalAffineWord, .originalPlaneDerivative, .originalGuideTraversalChain, .originalPolyline, .originalGuideEndpointConnector, .originalDrafted:
            return nil
        }
    }

    private func faceIDs(
        for bodyID: BodyID,
        in model: BRepModel,
        tolerance: ModelingTolerance,
        using execution: inout OriginalQueryExecution
    ) throws -> [FaceID] {
        guard let body = model.bodies[bodyID] else {
            throw KernelError(
                phase: .topology,
                code: .missingReference,
                tolerance: tolerance,
                message: "Boolean body is missing during face enumeration."
            )
        }
        var faceIDs: [FaceID] = []
        for shellID in body.shellIDs {
            try execution.consumeWork(1)
            guard let shell = model.shells[shellID] else {
                throw KernelError(
                    phase: .topology,
                    code: .missingReference,
                    tolerance: tolerance,
                    message: "Boolean body references a missing shell."
                )
            }
            for faceID in shell.faceIDs {
                try execution.retainKernelValues(count: 1, stride: MemoryLayout<FaceID>.stride)
                faceIDs.append(faceID)
            }
        }
        try execution.retainKernelValues(count: faceIDs.count, stride: MemoryLayout<FaceID>.stride)
        return try faceIDs.sorted { first, second in
            try execution.consumeWork(1)
            return first < second
        }
    }

    private func bounds(
        for faceID: FaceID,
        in model: BRepModel,
        tolerance: ModelingTolerance,
        using execution: inout OriginalQueryExecution
    ) throws -> BoundingBox3D {

            let limits = execution.effectiveLimits
            return try BRepFaceBoundingBoxBuilder().bounds(for: faceID, in: model, tolerance: tolerance,
                maximumSubdivisionDepth: min(32, limits.maximumSubdivisionDepth),
                remainingSourceDepth: min(16, limits.remainingSourceDepth),
                maximumAlgebraicDepth: min(32, limits.maximumValueDepth), using: &execution)


    }
}

#if !hasFeature(Embedded)
extension BooleanPipelinePhase: Codable {}
#endif
