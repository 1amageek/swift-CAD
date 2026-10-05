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
        prepared: PreparedBooleanIntersection? = nil,
        lineageAdmission: GeometryConversionAdmission? = nil
    ) throws -> EvaluationResult {
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
                    tolerance: tolerance
                )
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
                )
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
                )
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
                )
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
                )
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
                    tolerance: tolerance
                )
            } catch {
                throw contextualized(
                    error,
                    stage: "exact sewing evaluation",
                    tolerance: tolerance
                )
            }
            let topologyLineage: [SubshapeID: TopologyLineage]
            do {
                // This admission owns lineage only, not preceding Boolean phases.
                var lineageInputs = subshapes
                if let lineageAdmission {
                    for _ in subshapes.keys {
                        try lineageAdmission.chargeWork()
                    }
                    let retainedBytes = subshapes.count.multipliedReportingOverflow(
                        by: MemoryLayout<(SubshapeID, TopologyReference)>.stride)
                    guard !retainedBytes.overflow else {
                        throw GeometryConversionError.resourceLimitExceeded("Boolean lineage input storage overflowed.")
                    }
                    try lineageAdmission.chargeStorage(bytes: retainedBytes.partialValue)
                }
                for (id, reference) in toolSubshapes {
                    try CurrentTaskCancellationChecker().checkCancellation()
                    try lineageAdmission?.chargeWork()
                    if lineageInputs[id] == nil {
                        try lineageAdmission?.chargeStorage(bytes: MemoryLayout<(SubshapeID, TopologyReference)>.stride)
                        lineageInputs[id] = reference
                    }
                }
                var lineageOperands = targetBodyIDs
                if let lineageAdmission {
                    for _ in targetBodyIDs { try lineageAdmission.chargeWork() }
                    let count = targetBodyIDs.count.addingReportingOverflow(1)
                    let bytes = count.partialValue.multipliedReportingOverflow(by: MemoryLayout<BodyID>.stride)
                    guard !count.overflow, !bytes.overflow else {
                        throw GeometryConversionError.resourceLimitExceeded("Boolean lineage operand storage overflowed.")
                    }
                    try lineageAdmission.chargeStorage(bytes: bytes.partialValue)
                }
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
                    admission: lineageAdmission
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
            throw KernelError.wrapping(
                error,
                phase: .topology,
                featureID: featureID,
                tolerance: tolerance
            )
        }
    }

    private func contextualized(
        _ error: any Error,
        stage: String,
        tolerance: ModelingTolerance
    ) -> KernelError {
        let wrapped = KernelError.wrapping(
            error,
            phase: .topology,
            tolerance: tolerance
        )
        return KernelError(
            phase: wrapped.phase,
            code: wrapped.code,
            featureID: wrapped.featureID,
            subshapeID: wrapped.subshapeID,
            residual: wrapped.residual,
            tolerance: wrapped.tolerance ?? tolerance,
            message: "Boolean \(stage) failed: \(wrapped.message)"
        )
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
        try operandValidation(
            targetBodyIDs: targetBodyIDs,
            toolBodyID: toolBodyID,
            model: model,
            tolerance: tolerance
        )
        let requirement = try evaluator.intersectionRequirement(
            operation: operation,
            targetBodyIDs: targetBodyIDs,
            toolBodyID: toolBodyID,
            model: model,
            operands: operands ?? .volumes(targetBodyIDs: targetBodyIDs, toolBodyID: toolBodyID),
            tolerance: tolerance
        )
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
            tolerance: tolerance
        )
        let graph = try faceIntersection(
            facePairs: facePairs,
            in: model,
            tolerance: tolerance
        )
        try graph.validate(in: model, tolerance: tolerance)
        return graph
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
        maximumSpanCount: Int, maximumSubdivisionDepth: Int, remainingSourceDepth: Int,
        consumeWork: @escaping @Sendable (Int) throws -> Void,
        consumeStorage: (@Sendable (Int) throws -> Void)?, maximumAlgebraicDepth: Int = 32
    ) throws -> BooleanIntersectionGraph {
        let tolerance = validatedModel.tolerance
        let admission = try BooleanGraphAdmission(maximumSpanCount: maximumSpanCount,
            maximumSubdivisionDepth: maximumSubdivisionDepth, remainingSourceDepth: remainingSourceDepth,
            consumeWork: consumeWork, consumeStorage: consumeStorage, tolerance: tolerance, maximumAlgebraicDepth: maximumAlgebraicDepth)
        try admission.step()
        guard validatedModel.validationLevel != .modeling, !targetBodyIDs.isEmpty else {
            throw KernelError(phase: .validation, code: .invalidInput, tolerance: tolerance,
                message: "Original graph construction requires an exact immutable model and target operands.")
        }
        let model = validatedModel.model
        var operands: Set<BodyID> = [toolBodyID]
        for bodyID in targetBodyIDs {
            try admission.step()
            guard operands.insert(bodyID).inserted else {
                throw KernelError(phase: .validation, code: .invalidInput, tolerance: tolerance,
                    message: "Original graph operands must be distinct.")
            }
        }
        for bodyID in operands {
            try admission.step()
            guard model.bodies[bodyID] != nil else {
                throw KernelError(phase: .validation, code: .missingReference, tolerance: tolerance,
                    message: "An original graph operand is missing from its immutable model.")
            }
        }
        let pairs = try facePairBroadPhase(targetBodyIDs: targetBodyIDs, toolBodyID: toolBodyID,
            operation: operation, in: model, tolerance: tolerance, admission: admission)
        let graph = try faceIntersection(facePairs: pairs, in: model,
            tolerance: tolerance, admission: admission)
        try graph.validate(in: model, tolerance: tolerance, consumeWork: consumeWork)
        try admission.step()
        return graph
    }

    func completeIntersectionGraph(
        targetBodyIDs: [BodyID],
        toolBodyID: BodyID,
        operation: BooleanOperation,
        model: BRepModel,
        tolerance: ModelingTolerance
    ) throws -> BooleanIntersectionGraph {
        try operandValidation(
            targetBodyIDs: targetBodyIDs,
            toolBodyID: toolBodyID,
            model: model,
            tolerance: tolerance
        )
        let facePairs = try facePairBroadPhase(
            targetBodyIDs: targetBodyIDs,
            toolBodyID: toolBodyID,
            operation: operation,
            in: model,
            tolerance: tolerance
        )
        let graph = try faceIntersection(
            facePairs: facePairs,
            in: model,
            tolerance: tolerance
        )
        try graph.validate(in: model, tolerance: tolerance)
        return graph
    }

    /// Prepares complete original intersections for explicitly selected finite faces.
    /// Incident faces may share a body; their original ownership and topology are retained.
    public func completeIntersectionGraph(
        facePairs: [BooleanFacePairCandidate],
        model: BRepModel,
        tolerance: ModelingTolerance
    ) throws -> BooleanIntersectionGraph {
        try CurrentTaskCancellationChecker().checkCancellation()
        try tolerance.validate()
        try model.validate(tolerance: tolerance)
        guard Set(facePairs).count == facePairs.count,
              facePairs.allSatisfy({ $0.targetFaceID != $0.toolFaceID }) else {
            throw KernelError(phase: .validation, code: .invalidInput, tolerance: tolerance,
                message: "Complete finite-face preparation requires distinct unique face pairs.")
        }
        for pair in facePairs {
            guard model.faces[pair.targetFaceID] != nil, model.faces[pair.toolFaceID] != nil else {
                throw KernelError(phase: .validation, code: .missingReference, tolerance: tolerance,
                    message: "A requested original intersection face is missing.")
            }
        }
        let ordered = facePairs.sorted {
            $0.targetFaceID == $1.targetFaceID ? $0.toolFaceID < $1.toolFaceID : $0.targetFaceID < $1.targetFaceID
        }
        let graph = try faceIntersection(facePairs: ordered, in: model, tolerance: tolerance)
        try graph.validate(in: model, tolerance: tolerance)
        try CurrentTaskCancellationChecker().checkCancellation()
        return graph
    }

    /// Complete authored finite-face graph bound to one immutable admitted source.
    public func completeIntersectionGraph(
        facePairs: [BooleanFacePairCandidate], validatedModel: ValidatedBRepModel,
        maximumSpanCount: Int, maximumSubdivisionDepth: Int, remainingSourceDepth: Int,
        consumeWork: @escaping @Sendable (Int) throws -> Void,
        consumeStorage: (@Sendable (Int) throws -> Void)?, maximumAlgebraicDepth: Int = 32
    ) throws -> BooleanIntersectionGraph {
        let tolerance = validatedModel.tolerance
        let admission = try BooleanGraphAdmission(maximumSpanCount: maximumSpanCount,
            maximumSubdivisionDepth: maximumSubdivisionDepth, remainingSourceDepth: remainingSourceDepth,
            consumeWork: consumeWork, consumeStorage: consumeStorage, tolerance: tolerance, maximumAlgebraicDepth: maximumAlgebraicDepth)
        try admission.step()
        guard validatedModel.validationLevel != .modeling else {
            throw KernelError(phase: .validation, code: .invalidInput, tolerance: tolerance,
                message: "Finite-face preparation requires the immutable exact original source.")
        }
        let model = validatedModel.model
        var seen: Set<BooleanFacePairCandidate> = []
        for pair in facePairs {
            try admission.reserve(count: 1, stride: MemoryLayout<BooleanFacePairCandidate>.stride)
            guard pair.targetFaceID != pair.toolFaceID, seen.insert(pair).inserted else {
                throw KernelError(phase: .validation, code: .invalidInput, tolerance: tolerance,
                    message: "Finite-face preparation requires distinct unique original face pairs.")
            }
            try admission.step()
            guard model.faces[pair.targetFaceID] != nil, model.faces[pair.toolFaceID] != nil else {
                throw KernelError(phase: .validation, code: .missingReference, tolerance: tolerance,
                    message: "A finite-face source pair is absent from its immutable original model.")
            }
        }
        try admission.reserve(count: facePairs.count, stride: MemoryLayout<BooleanFacePairCandidate>.stride)
        var ordered = facePairs
        try ordered.sort { first, second in
            try admission.step()
            return first.targetFaceID == second.targetFaceID
                ? first.toolFaceID < second.toolFaceID : first.targetFaceID < second.targetFaceID
        }
        // FIXME(INCOMPLETE_IMPLEMENTATION): This finite-face factory forwards
        // actual original graph/SSI callbacks and reuses the exact source receipt.
        // Complete lower SSI critical/coincident/unbounded coverage and its
        // temporary byte producers remain required for the whole query guarantee.
        let graph = try faceIntersection(facePairs: ordered, in: model,
            tolerance: tolerance, admission: admission)
        try graph.validate(in: model, tolerance: tolerance, consumeWork: consumeWork)
        try admission.step()
        return graph
    }

    public func uvSplitGraph(
        intersectionGraph: BooleanIntersectionGraph,
        model: BRepModel,
        tolerance: ModelingTolerance
    ) throws -> BooleanUVSplitGraph {
        try uvFaceSplitter.splitGraph(
            intersectionGraph: intersectionGraph,
            model: model,
            tolerance: tolerance
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
        try regionClassifier.classificationGraph(
            uvSplitGraph: uvSplitGraph,
            targetBodyIDs: targetBodyIDs,
            toolBodyID: toolBodyID,
            model: model,
            operands: operands ?? .volumes(targetBodyIDs: targetBodyIDs, toolBodyID: toolBodyID),
            tolerance: tolerance
        )
    }

    /// The region selection of one pass; `rule` defaults to both operands taken as solid volumes.
    public func regionSelectionGraph(
        operation: BooleanOperation,
        classificationGraph: BooleanClassificationGraph,
        rule: BooleanRegionSelectionRule = BooleanRegionSelectionRule(solidities: .volumes),
        tolerance: ModelingTolerance
    ) throws -> BooleanRegionSelectionGraph {
        try regionSelector.selectionGraph(
            operation: operation,
            classificationGraph: classificationGraph,
            rule: rule,
            tolerance: tolerance
        )
    }

    private func operandValidation(
        targetBodyIDs: [BodyID],
        toolBodyID: BodyID,
        model: BRepModel,
        tolerance: ModelingTolerance
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
        try model.validate(tolerance: tolerance)
    }

    private func facePairBroadPhase(
        targetBodyIDs: [BodyID],
        toolBodyID: BodyID,
        operation: BooleanOperation,
        in model: BRepModel,
        tolerance: ModelingTolerance,
        admission: BooleanGraphAdmission? = nil
    ) throws -> [BooleanFacePairCandidate] {
        let toolFaceIDs = try faceIDs(for: toolBodyID, in: model, tolerance: tolerance, admission: admission)
        var preparedToolBounds: [FaceID: BoundingBox3D] = [:]
        if let admission {
            for faceID in toolFaceIDs {
                try admission.reserve(count: 1, stride: MemoryLayout<FaceID>.stride + MemoryLayout<BoundingBox3D>.stride)
                preparedToolBounds[faceID] = try bounds(for: faceID, in: model,
                    tolerance: tolerance, admission: admission)
            }
        }
        var candidates: [BooleanFacePairCandidate] = []
        for targetBodyID in targetBodyIDs {
            try admission?.step()
            for targetFaceID in try faceIDs(
                for: targetBodyID,
                in: model,
                tolerance: tolerance,
                admission: admission
            ) {
                try admission?.step()
                let targetBounds = try bounds(
                    for: targetFaceID,
                    in: model,
                    tolerance: tolerance,
                    admission: admission
                )
                for toolFaceID in toolFaceIDs {
                    try admission?.step()
                    let toolBounds = try preparedToolBounds[toolFaceID] ?? bounds(
                        for: toolFaceID,
                        in: model,
                        tolerance: tolerance,
                        admission: admission
                    )
                    guard targetBounds.intersects(
                        toolBounds,
                        tolerance: tolerance.distance
                    ) else {
                        continue
                    }
                    try admission?.reserve(count: 1, stride: MemoryLayout<BooleanFacePairCandidate>.stride)
                    candidates.append(BooleanFacePairCandidate(
                        targetFaceID: targetFaceID,
                        toolFaceID: toolFaceID
                    ))
                }
            }
        }
        try admission?.reserve(count: candidates.count, stride: MemoryLayout<BooleanFacePairCandidate>.stride)
        return try candidates.sorted {
            try admission?.step()
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
        admission: BooleanGraphAdmission? = nil
    ) throws -> BooleanIntersectionGraph {
        var contacts: [BooleanBoundaryContact] = []
        var faceIntersections: [BooleanFaceSurfaceIntersection] = []
        var boundaryContactCache: [
            BoundaryContactCacheKey: BoundaryContactCacheEntry
        ] = [:]
        var surfaceIntersectionCache: [
            Surface3D: [Surface3D: [SurfaceSurfaceIntersection]]
        ] = [:]
        var admittedSurfaceCache: [SurfaceID: [SurfaceID: [SurfaceSurfaceIntersection]]] = [:]
        for pair in facePairs {
            try admission?.step()
            let targetBoundaryContacts = try boundaryContacts(
                curveFaceID: pair.targetFaceID,
                surfaceFaceID: pair.toolFaceID,
                in: model,
                cache: &boundaryContactCache,
                tolerance: tolerance,
                admission: admission
            )
            let toolBoundaryContacts = try boundaryContacts(
                curveFaceID: pair.toolFaceID,
                surfaceFaceID: pair.targetFaceID,
                in: model,
                cache: &boundaryContactCache,
                tolerance: tolerance,
                admission: admission
            )
            try admission?.reserve(count: targetBoundaryContacts.count, stride: MemoryLayout<BooleanBoundaryContact>.stride)
            try admission?.reserve(count: toolBoundaryContacts.count, stride: MemoryLayout<BooleanBoundaryContact>.stride)
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
            try admission?.reserve(count: targetBoundaryContacts.count + toolBoundaryContacts.count,
                stride: MemoryLayout<BooleanBoundaryContact>.stride)
            for contact in targetBoundaryContacts + toolBoundaryContacts {
                try admission?.step()
                guard case let .points(values) = contact.geometry else { continue }
                for value in values {
                    try admission?.reserve(count: 1, stride: MemoryLayout<Point3D>.stride)
                    boundaryPoints.append(value.point)
                }
            }
            do {
                if let admission {
                    if let bounded = try boundedSurfaceIntersector.intersections(first: targetSurface,
                        second: toolSurface, boundaryPoints: boundaryPoints, options: .init(),
                        tolerance: tolerance, maximumSpanCount: admission.maximumSpanCount,
                        maximumSubdivisionDepth: admission.maximumSubdivisionDepth,
                        remainingSourceDepth: admission.remainingSourceDepth,
                        consumeWork: { try admission.step() }, consumeStorage: admission.consumeStorage, maximumAlgebraicDepth: admission.maximumAlgebraicDepth) {
                        intersections = bounded
                    } else if let cached = admittedSurfaceCache[targetFace.surfaceID]?[toolFace.surfaceID] {
                        intersections = cached
                    } else {
                        intersections = try surfaceIntersector.intersections(first: targetSurface,
                            second: toolSurface, options: .init(), tolerance: tolerance,
                            maximumSpanCount: admission.maximumSpanCount,
                            maximumSubdivisionDepth: admission.maximumSubdivisionDepth,
                            remainingSourceDepth: admission.remainingSourceDepth,
                            consumeWork: { try admission.step() }, consumeStorage: admission.consumeStorage, maximumAlgebraicDepth: admission.maximumAlgebraicDepth)
                        try admission.reserve(count: intersections.count, stride: MemoryLayout<SurfaceSurfaceIntersection>.stride)
                        try admission.reserve(count: 2, stride: MemoryLayout<SurfaceID>.stride)
                        admittedSurfaceCache[targetFace.surfaceID, default: [:]][toolFace.surfaceID] = intersections
                    }
                } else if let boundedIntersections = try boundedSurfaceIntersector.intersections(
                    first: targetSurface,
                    second: toolSurface,
                    boundaryPoints: boundaryPoints,
                    options: .init(),
                    tolerance: tolerance
                ) {
                    intersections = boundedIntersections
                } else if let cached = surfaceIntersectionCache[targetSurface]?[toolSurface] {
                    intersections = cached
                } else {
                    intersections = try surfaceIntersector.intersections(
                        first: targetSurface,
                        second: toolSurface,
                        options: .init(),
                        tolerance: tolerance
                    )
                    surfaceIntersectionCache[targetSurface, default: [:]][toolSurface]
                        = intersections
                }
            } catch {
                let wrapped = KernelError.wrapping(
                    error,
                    phase: .geometry,
                    tolerance: tolerance
                )
                throw KernelError(
                    phase: wrapped.phase,
                    code: wrapped.code,
                    featureID: wrapped.featureID,
                    subshapeID: wrapped.subshapeID,
                    residual: wrapped.residual,
                    tolerance: wrapped.tolerance ?? tolerance,
                    message: "Boolean face-pair intersection failed for target face \(pair.targetFaceID) on surface \(targetFace.surfaceID) and tool face \(pair.toolFaceID) on surface \(toolFace.surfaceID): \(wrapped.message)"
                )
            }
            for intersection in intersections {
                try admission?.reserve(count: 1, stride: MemoryLayout<BooleanFaceSurfaceIntersection>.stride)
                faceIntersections.append(BooleanFaceSurfaceIntersection(facePair: pair, geometry: intersection))
            }
        }
        try admission?.reserve(count: contacts.count, stride: MemoryLayout<BooleanBoundaryContact>.stride)
        let orderedContacts = try contacts.sorted {
            try admission?.step()
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
        admission: BooleanGraphAdmission? = nil
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
            try admission?.step()
            guard let loop = model.loops[loopID] else {
                throw KernelError(
                    phase: .topology,
                    code: .missingReference,
                    tolerance: tolerance,
                    message: "Boolean face-pair intersection references a missing loop."
                )
            }
            return try loop.coedges.map { coedge in
                try admission?.step()
                return coedge.edgeID
            }
        }).sorted { first, second in
            try admission?.step()
            return first < second
        }
        var contacts: [BooleanBoundaryContact] = []
        for edgeID in edgeIDs {
            try admission?.step()
            let key = BoundaryContactCacheKey(
                edgeID: edgeID,
                surfaceID: surfaceFace.surfaceID
            )
            if let cached = cache[key] {
                if case let .geometry(geometry) = cached {
                    try admission?.reserve(count: 1, stride: MemoryLayout<BooleanBoundaryContact>.stride)
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
                if let admission {
                    intersections = try intersector.intersections(curve: curve, surface: surface,
                        options: options, tolerance: tolerance,
                        maximumSubdivisionDepth: admission.maximumSubdivisionDepth,
                        consumeWork: admission.consumeWork)
                } else {
                    intersections = try intersector.intersections(
                    curve: curve,
                    surface: surface,
                    options: options,
                    tolerance: tolerance
                )
                }
                if intersections.isEmpty == false {
                    let geometry = BooleanBoundaryContactGeometry.points(intersections)
                    try admission?.reserve(count: 1, stride: MemoryLayout<BoundaryContactCacheKey>.stride + MemoryLayout<BoundaryContactCacheEntry>.stride)
                    try admission?.reserve(count: intersections.count, stride: MemoryLayout<CurveSurfaceIntersection>.stride)
                    cache[key] = .geometry(geometry)
                    try admission?.reserve(count: 1, stride: MemoryLayout<BooleanBoundaryContact>.stride)
                    contacts.append(BooleanBoundaryContact(
                        edgeID: edgeID,
                        curveFaceID: curveFaceID,
                        surfaceFaceID: surfaceFaceID,
                        geometry: geometry
                    ))
                } else {
                    try admission?.reserve(count: 1, stride: MemoryLayout<BoundaryContactCacheKey>.stride + MemoryLayout<BoundaryContactCacheEntry>.stride)
                    cache[key] = .empty
                }
            } catch let error as KernelError where error.code == .nonDiscreteIntersection {
                try admission?.reserve(count: 1, stride: MemoryLayout<BoundaryContactCacheKey>.stride + MemoryLayout<BoundaryContactCacheEntry>.stride)
                cache[key] = .geometry(.coincident)
                try admission?.reserve(count: 1, stride: MemoryLayout<BooleanBoundaryContact>.stride)
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
             .certifiedIntersection, .parameterImage:
            return nil
        }
    }

    private func faceIDs(
        for bodyID: BodyID,
        in model: BRepModel,
        tolerance: ModelingTolerance,
        admission: BooleanGraphAdmission? = nil
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
            try admission?.step()
            guard let shell = model.shells[shellID] else {
                throw KernelError(
                    phase: .topology,
                    code: .missingReference,
                    tolerance: tolerance,
                    message: "Boolean body references a missing shell."
                )
            }
            for faceID in shell.faceIDs {
                try admission?.reserve(count: 1, stride: MemoryLayout<FaceID>.stride)
                faceIDs.append(faceID)
            }
        }
        try admission?.reserve(count: faceIDs.count, stride: MemoryLayout<FaceID>.stride)
        return try faceIDs.sorted { first, second in
            try admission?.step()
            return first < second
        }
    }

    private func bounds(
        for faceID: FaceID,
        in model: BRepModel,
        tolerance: ModelingTolerance,
        admission: BooleanGraphAdmission? = nil
    ) throws -> BoundingBox3D {
        if let admission {
            return try BRepFaceBoundingBoxBuilder().bounds(for: faceID, in: model, tolerance: tolerance,
                maximumSubdivisionDepth: admission.maximumSubdivisionDepth,
                remainingSourceDepth: admission.remainingSourceDepth, maximumAlgebraicDepth: admission.maximumAlgebraicDepth,
                consumeWork: admission.consumeWork, consumeStorage: admission.consumeStorage)
        }
        return try BRepFaceBoundingBoxBuilder().bounds(
            for: faceID,
            in: model,
            tolerance: tolerance
        )
    }
}

#if !hasFeature(Embedded)
extension BooleanPipelinePhase: Codable {}
#endif
