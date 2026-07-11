import Foundation
import CADCore
import CADIR

struct DocumentEvaluationEngine {
    let parameterResolver: ParameterResolving
    let profileExtractor: SketchProfileExtracting
    let curveExtractor: SketchCurveExtracting
    let featureEvaluator: FeatureEvaluating
    let tessellator: Tessellating
    let tolerance: ModelingTolerance
    let tessellationOptions: TessellationOptions
    let artifactPolicy: EvaluationArtifactPolicy
    let incrementalEvaluatorIdentity: String?

    func evaluate(
        _ validatedDocument: ValidatedCADDocument,
        reusing previous: EvaluatedDocument?,
        stateRecorder: (FeatureID, FeatureEvaluationState) -> Void
    ) throws -> EvaluatedDocument {
        let document = validatedDocument.document
        guard validatedDocument.tolerance == tolerance else {
            throw FeatureEvaluationError.invalidGraph(
                "Validated document tolerance does not match the evaluator tolerance."
            )
        }
        try tolerance.validate()
        try tessellationOptions.validate()

        let sourceFingerprint: CADDocumentSourceFingerprint?
        switch artifactPolicy {
        case .deferred:
            sourceFingerprint = nil
        case .materialized:
            sourceFingerprint = try validatedDocument.sourceFingerprint()
        }
        let parameters = try parameterResolver.resolve(document.parameters)
        let reusableState = reusableState(for: document, from: previous)
        let graphStableChanges: Set<FeatureID>?
        let graphState: IncrementalEvaluationGraphState
        if let reusableState,
           let changes = reusableState.graph.graphStableChanges(for: validatedDocument) {
            graphStableChanges = changes
            graphState = reusableState.graph.reidentified(as: validatedDocument.identity)
        } else {
            graphStableChanges = nil
            graphState = IncrementalEvaluationGraphState(validatedDocument)
        }
        let profileSourceFeatureIDs = graphState.profileSourceFeatureIDs
        let curveSourceFeatureIDs = graphState.curveSourceFeatureIDs
        var invalidatedFeatureIDs = initialInvalidatedFeatureIDs(
            document: document,
            parameters: parameters,
            profileSourceFeatureIDs: profileSourceFeatureIDs,
            curveSourceFeatureIDs: curveSourceFeatureIDs,
            reusableState: reusableState,
            graphStableChanges: graphStableChanges,
            graphState: graphState
        )
        var metrics = DocumentEvaluationMetrics(totalFeatureCount: document.designGraph.order.count)
        let evaluationBase: IncrementalEvaluationBase
        if let reusableState, let previous {
            do {
                evaluationBase = try makeIncrementalEvaluationBase(
                    document: document,
                    previous: previous,
                    reusableState: reusableState,
                    invalidatedFeatureIDs: invalidatedFeatureIDs,
                    graphState: graphState,
                    graphStructureIsStable: graphStableChanges != nil
                )
                metrics.topologyMutationCount += evaluationBase.rollbackMutationCount
            } catch {
                evaluationBase = .empty
                invalidatedFeatureIDs = Set(document.designGraph.order)
                metrics.replayFallbackCount += 1
            }
        } else {
            evaluationBase = .empty
        }
        let brepBuffer = evaluationBase.brepBuffer
        var profiles = reusableState?.profiles ?? [:]
        var curves = reusableState?.curves ?? [:]
        var generatedNames = evaluationBase.generatedNames
        var changedBodyIDs = evaluationBase.affectedBodyIDs
        var featureEntries = reusableState?.featureEntries
            ?? PersistentMap<FeatureID, FeatureEvaluationCacheEntry>()
        if graphStableChanges == nil {
            let currentFeatureIDs = Set(document.designGraph.order)
            let removedFeatureIDs = featureEntries.keys.filter { !currentFeatureIDs.contains($0) }
            for featureID in removedFeatureIDs {
                featureEntries.removeValue(forKey: featureID)
                profiles.removeValue(forKey: featureID)
                curves.removeValue(forKey: featureID)
            }
        }
        for featureID in invalidatedFeatureIDs {
            featureEntries.removeValue(forKey: featureID)
            if profiles[featureID] != nil {
                profiles.removeValue(forKey: featureID)
            }
            if curves[featureID] != nil {
                curves.removeValue(forKey: featureID)
            }
        }

        let invalidatedEvaluationOrder = try graphState.evaluationOrder(
            for: invalidatedFeatureIDs
        )
        for featureID in invalidatedEvaluationOrder {
            guard let feature = document.designGraph.nodes[featureID] else {
                throw FeatureEvaluationError.invalidGraph("Feature order references missing node.")
            }
            let featureKey = try makeFeatureKey(
                feature: feature,
                parameters: parameters,
                extractsProfiles: profileSourceFeatureIDs.contains(featureID),
                extractsCurves: curveSourceFeatureIDs.contains(featureID)
            )

            do {
                let entry = try rebuild(
                    feature,
                    key: featureKey,
                    extractsProfiles: profileSourceFeatureIDs.contains(featureID),
                    extractsCurves: curveSourceFeatureIDs.contains(featureID),
                    parameters: parameters,
                    brepBuffer: brepBuffer,
                    profiles: &profiles,
                    curves: &curves,
                    generatedNames: &generatedNames,
                    changedBodyIDs: &changedBodyIDs,
                    metrics: &metrics
                )
                if let entry {
                    featureEntries[featureID] = entry
                }
                metrics.rebuiltFeatureCount += 1
                stateRecorder(featureID, feature.isSuppressed ? .suppressed : .evaluated)
            } catch {
                recordFailure(
                    error,
                    featureID: featureID,
                    document: document,
                    stateRecorder: stateRecorder
                )
                throw error
            }
        }

        metrics.invalidatedFeatureCount = invalidatedFeatureIDs.count
        metrics.reusedFeatureCount = document.designGraph.order.count - metrics.rebuiltFeatureCount
        let brep = brepBuffer.finalizedModel()
        let validatedBRep = ValidatedBRepModel(
            composingValidatedFeatureResults: brep,
            tolerance: tolerance
        )
        let meshResult = try makeMeshes(
            for: validatedBRep,
            reusing: reusableState == nil ? nil : previous,
            changedBodyIDs: changedBodyIDs
        )
        metrics.tessellatedBodyCount = meshResult.tessellatedBodyCount
        metrics.reusedMeshCount = meshResult.reusedMeshCount

        if brep.bodies.isEmpty, curves.isEmpty {
            throw FeatureEvaluationError.emptyResult("Evaluation produced no bodies or curves.")
        }
        if !brep.bodies.isEmpty, meshResult.meshes.isEmpty {
            throw FeatureEvaluationError.emptyResult("Evaluation produced no body meshes.")
        }

        let caches: DocumentCaches
        if let sourceFingerprint {
            caches = makeCaches(
                document: document,
                sourceFingerprint: sourceFingerprint,
                brep: brep,
                meshes: meshResult.meshes,
                generatedNames: generatedNames
            )
        } else {
            caches = DocumentCaches()
        }
        var evaluatedDocument = EvaluatedDocument(
            document: document,
            parameters: parameters,
            brep: brep,
            meshes: meshResult.meshes,
            curves: curves,
            caches: caches,
            generatedNames: generatedNames,
            configuration: DocumentEvaluationConfiguration(
                tolerance: tolerance,
                tessellationOptions: tessellationOptions
            ),
            evaluationMetrics: metrics
        )
        if let incrementalEvaluatorIdentity {
            evaluatedDocument.incrementalEvaluationState = IncrementalEvaluationState(
                evaluatorIdentity: incrementalEvaluatorIdentity,
                documentID: document.id,
                schemaVersion: document.schemaVersion,
                units: document.units,
                parameterRevision: document.parameters.revision,
                tolerance: tolerance,
                tessellationOptions: tessellationOptions,
                graph: graphState,
                featureEntries: featureEntries,
                profiles: profiles,
                curves: curves
            )
        }
        if incrementalEvaluatorIdentity == nil {
            try evaluatedDocument.validateGeneratedNames()
        }
        try evaluatedDocument.validateCurveOutputs(tolerance: tolerance)
        return evaluatedDocument
    }

    private func rebuild(
        _ feature: FeatureNode,
        key: FeatureEvaluationKey,
        extractsProfiles: Bool,
        extractsCurves: Bool,
        parameters: ResolvedParameterTable,
        brepBuffer: BRepEditBuffer,
        profiles: inout [FeatureID: [Profile]],
        curves: inout [FeatureID: [EvaluatedCurve]],
        generatedNames: inout PersistentMap<PersistentName, TopologyReference>,
        changedBodyIDs: inout Set<BodyID>,
        metrics: inout DocumentEvaluationMetrics
    ) throws -> FeatureEvaluationCacheEntry? {
        var brepDelta = BRepModelDelta()
        var generatedNamesDelta = DictionaryDelta<PersistentName, TopologyReference>()
        var affectedBodyIDs = Set<BodyID>()
        var profileOutput: [Profile]?
        var curveOutput: [EvaluatedCurve]?

        if !feature.isSuppressed {
            switch feature.operation {
            case let .sketch(sketch):
                if extractsProfiles {
                    let extractedProfiles = try profileExtractor.extractProfiles(
                        from: sketch,
                        sourceFeatureID: feature.id,
                        parameters: parameters
                    )
                    profiles[feature.id] = extractedProfiles
                    profileOutput = extractedProfiles
                }
                if extractsCurves {
                    let extractedCurves = try curveExtractor.extractCurves(
                        from: sketch,
                        sourceFeatureID: feature.id,
                        parameters: parameters
                    )
                    curves[feature.id] = extractedCurves
                    curveOutput = extractedCurves
                }
            case .extrude,
                 .revolve,
                 .sweep,
                 .loft,
                 .boolean,
                 .polySpline,
                 .bSplineSurface,
                 .faceLoopOffset,
                 .edgeOffset,
                 .faceKnife,
                 .faceDelete,
                 .faceDraft,
                 .bridgeCurve,
                 .curveEdit,
                 .curveOffset,
                 .curveTrim:
                let scope = try evaluationScope(
                    for: feature,
                    brepBuffer: brepBuffer,
                    generatedNames: generatedNames
                )
                let context = EvaluationContext(
                    parameters: parameters,
                    brep: scope.brep,
                    profiles: profiles,
                    curves: curves,
                    generatedNames: scope.generatedNames,
                    tolerance: tolerance
                )
                let evaluation: ValidatedFeatureEvaluation
                if let validatedEvaluator = featureEvaluator as? any ValidatedFeatureEvaluating {
                    evaluation = try validatedEvaluator.evaluateValidated(
                        feature: feature,
                        context: context
                    )
                } else {
                    let result = try featureEvaluator.evaluate(feature: feature, context: context)
                    evaluation = try ValidatedFeatureEvaluation(
                        validating: result,
                        tolerance: tolerance
                    )
                }
                let result = evaluation.result
                let validatedResult = evaluation.brep
                if incrementalEvaluatorIdentity != nil {
                    brepDelta = BRepModelDelta(before: scope.brep, after: validatedResult.model)
                    try brepBuffer.apply(brepDelta)
                    affectedBodyIDs.formUnion(scope.bodyIDs)
                    affectedBodyIDs.formUnion(brepDelta.changedBodyIDs)
                    changedBodyIDs.formUnion(affectedBodyIDs)
                    metrics.scopedBodyReadCount += scope.bodyCount
                    metrics.maximumScopedBodyReadCount = max(
                        metrics.maximumScopedBodyReadCount,
                        scope.bodyCount
                    )
                    metrics.topologyMutationCount += brepDelta.changeCount
                } else {
                    brepBuffer.replace(with: validatedResult.model)
                }
                generatedNamesDelta = try applyGeneratedNameMutation(
                    result,
                    to: &generatedNames
                )
                if incrementalEvaluatorIdentity != nil {
                    var scopedGeneratedNames = scope.generatedNames
                    try generatedNamesDelta.apply(
                        to: &scopedGeneratedNames,
                        tableName: "scopedGeneratedNames"
                    )
                    try GeneratedNameValidator.validate(
                        scopedGeneratedNames,
                        in: validatedResult.model
                    )
                }
                if !result.generatedCurves.isEmpty {
                    curves[feature.id] = result.generatedCurves
                    curveOutput = result.generatedCurves
                }
            }
        }

        guard incrementalEvaluatorIdentity != nil else {
            return nil
        }
        return FeatureEvaluationCacheEntry(
            key: key,
            brepDelta: brepDelta,
            generatedNamesDelta: generatedNamesDelta,
            affectedBodyIDs: affectedBodyIDs,
            profiles: profileOutput,
            curves: curveOutput
        )
    }

    private func makeFeatureKey(
        feature: FeatureNode,
        parameters: ResolvedParameterTable,
        extractsProfiles: Bool,
        extractsCurves: Bool
    ) throws -> FeatureEvaluationKey {
        var resolvedParameters: [ParameterID: Quantity] = [:]
        let parameterIDs = feature.operation.referencedParameterIDs
        resolvedParameters.reserveCapacity(parameterIDs.count)
        for parameterID in parameterIDs {
            resolvedParameters[parameterID] = try parameters.value(for: parameterID)
        }
        return FeatureEvaluationKey(
            feature: feature,
            resolvedParameters: resolvedParameters,
            extractsProfiles: extractsProfiles,
            extractsCurves: extractsCurves
        )
    }

    private func reusableState(
        for document: CADDocument,
        from previous: EvaluatedDocument?
    ) -> IncrementalEvaluationState? {
        guard let incrementalEvaluatorIdentity,
              let state = previous?.incrementalEvaluationState,
              state.evaluatorIdentity == incrementalEvaluatorIdentity,
              state.documentID == document.id,
              state.schemaVersion == document.schemaVersion,
              state.units == document.units,
              state.tolerance == tolerance,
              state.tessellationOptions == tessellationOptions else {
            return nil
        }
        return state
    }

    private func makeIncrementalEvaluationBase(
        document: CADDocument,
        previous: EvaluatedDocument,
        reusableState: IncrementalEvaluationState,
        invalidatedFeatureIDs: Set<FeatureID>,
        graphState: IncrementalEvaluationGraphState,
        graphStructureIsStable: Bool
    ) throws -> IncrementalEvaluationBase {
        let rollbackOrder: [FeatureID]
        if graphStructureIsStable {
            rollbackOrder = try graphState.rollbackOrder(for: invalidatedFeatureIDs)
        } else {
            let currentFeatureIDs = Set(document.designGraph.order)
            rollbackOrder = previous.document.designGraph.order.reversed().filter { featureID in
                !currentFeatureIDs.contains(featureID) || invalidatedFeatureIDs.contains(featureID)
            }
        }
        let brepBuffer = BRepEditBuffer(model: previous.brep)
        var generatedNames = previous.generatedNames
        var rollbackMutationCount = 0
        var affectedBodyIDs = Set<BodyID>()

        for featureID in rollbackOrder {
            guard let entry = reusableState.featureEntries[featureID] else {
                throw IncrementalReplayError.stateMismatch(table: "featureEntries")
            }
            let brepDelta = entry.brepDelta.inverted
            let generatedNamesDelta = entry.generatedNamesDelta.inverted
            try brepBuffer.validate(brepDelta)
            try generatedNamesDelta.validate(
                in: generatedNames,
                tableName: "generatedNames"
            )
            try brepBuffer.apply(brepDelta)
            try generatedNamesDelta.apply(
                to: &generatedNames,
                tableName: "generatedNames"
            )
            affectedBodyIDs.formUnion(entry.affectedBodyIDs)
            rollbackMutationCount += brepDelta.changeCount
        }

        return IncrementalEvaluationBase(
            brepBuffer: brepBuffer,
            generatedNames: generatedNames,
            affectedBodyIDs: affectedBodyIDs,
            rollbackMutationCount: rollbackMutationCount
        )
    }

    private func initialInvalidatedFeatureIDs(
        document: CADDocument,
        parameters: ResolvedParameterTable,
        profileSourceFeatureIDs: Set<FeatureID>,
        curveSourceFeatureIDs: Set<FeatureID>,
        reusableState: IncrementalEvaluationState?,
        graphStableChanges: Set<FeatureID>?,
        graphState: IncrementalEvaluationGraphState
    ) -> Set<FeatureID> {
        guard let reusableState else {
            return Set(document.designGraph.order)
        }
        if let graphStableChanges {
            return graphState.invalidationClosure(startingWith: graphStableChanges)
        }
        let directlyChangedFeatureIDs = Set(document.designGraph.order.filter { featureID in
            guard let feature = document.designGraph.nodes[featureID],
                  let previousKey = reusableState.featureEntries[featureID]?.key else {
                return true
            }
            guard previousKey.feature == feature,
                  previousKey.extractsProfiles == profileSourceFeatureIDs.contains(featureID),
                  previousKey.extractsCurves == curveSourceFeatureIDs.contains(featureID) else {
                return true
            }
            guard reusableState.parameterRevision != document.parameters.revision else {
                return false
            }
            do {
                let currentKey = try makeFeatureKey(
                    feature: feature,
                    parameters: parameters,
                    extractsProfiles: previousKey.extractsProfiles,
                    extractsCurves: previousKey.extractsCurves
                )
                return currentKey.resolvedParameters != previousKey.resolvedParameters
            } catch {
                return true
            }
        })
        return graphState.invalidationClosure(startingWith: directlyChangedFeatureIDs)
    }

    private func invalidationClosure(
        startingWith featureIDs: Set<FeatureID>,
        in graph: DesignGraph
    ) -> Set<FeatureID> {
        guard !featureIDs.isEmpty else {
            return []
        }
        var adjacency: [FeatureID: [FeatureID]] = [:]
        adjacency.reserveCapacity(graph.nodes.count)
        for dependency in graph.dependencies {
            adjacency[dependency.source, default: []].append(dependency.target)
        }
        var invalidated: Set<FeatureID> = []
        invalidated.reserveCapacity(graph.nodes.count)
        var pending = Array(featureIDs)
        while let featureID = pending.popLast() {
            guard invalidated.insert(featureID).inserted else {
                continue
            }
            pending.append(contentsOf: adjacency[featureID, default: []])
        }
        return invalidated
    }

    private func makeMeshes(
        for validatedBRep: ValidatedBRepModel,
        reusing previous: EvaluatedDocument?,
        changedBodyIDs requestedChangedBodyIDs: Set<BodyID>
    ) throws -> MeshEvaluationResult {
        let brep = validatedBRep.model
        guard let previous else {
            let meshes = try tessellator.tessellate(
                validatedModel: validatedBRep,
                options: tessellationOptions
            )
            return MeshEvaluationResult(
                meshes: PersistentMap(meshes),
                tessellatedBodyCount: brep.bodies.count,
                reusedMeshCount: 0
            )
        }

        var meshes = previous.meshes
        var bodyIDsToTessellate = Set<BodyID>()
        bodyIDsToTessellate.reserveCapacity(requestedChangedBodyIDs.count)
        for bodyID in requestedChangedBodyIDs {
            if brep.bodies[bodyID] == nil {
                meshes.removeValue(forKey: bodyID)
            } else {
                bodyIDsToTessellate.insert(bodyID)
            }
        }

        if !bodyIDsToTessellate.isEmpty {
            let extractor = BRepBodySubmodelExtractor()
            let changedModel = try extractor.extract(
                bodyIDs: bodyIDsToTessellate,
                from: brep
            )
            let validatedChangedModel = ValidatedBRepModel(
                composingValidatedFeatureResults: changedModel,
                tolerance: tolerance
            )
            let changedMeshes = try tessellator.tessellate(
                validatedModel: validatedChangedModel,
                options: tessellationOptions
            )
            guard Set(changedMeshes.keys) == bodyIDsToTessellate else {
                throw FeatureEvaluationError.emptyResult(
                    "Tessellation did not produce exactly one mesh for every changed body."
                )
            }
            for (bodyID, mesh) in changedMeshes {
                meshes[bodyID] = mesh
            }
        }

        return MeshEvaluationResult(
            meshes: meshes,
            tessellatedBodyCount: bodyIDsToTessellate.count,
            reusedMeshCount: meshes.count - bodyIDsToTessellate.count
        )
    }

    private func makeCaches(
        document: CADDocument,
        sourceFingerprint: CADDocumentSourceFingerprint,
        brep: BRepModel,
        meshes: PersistentMap<BodyID, Mesh>,
        generatedNames: PersistentMap<PersistentName, TopologyReference>
    ) -> DocumentCaches {
        let brepCache = BRepCache(
            designRevision: document.designGraph.revision,
            parameterRevision: document.parameters.revision,
            sourceFingerprint: sourceFingerprint,
            kernelVersion: .current,
            tolerance: tolerance,
            model: brep,
            persistentNames: PersistentNameMap(generatedNames.materializedDictionary())
        )
        let meshCaches = Dictionary(
            uniqueKeysWithValues: meshes.map { bodyID, mesh in
                (
                    bodyID,
                    MeshCache(
                        bodyID: bodyID,
                        designRevision: document.designGraph.revision,
                        parameterRevision: document.parameters.revision,
                        sourceFingerprint: sourceFingerprint,
                        kernelVersion: .current,
                        tolerance: tolerance,
                        tessellationOptions: tessellationOptions,
                        mesh: mesh
                    )
                )
            }
        )
        return DocumentCaches(brep: brepCache, meshes: meshCaches)
    }

    private func recordFailure(
        _ error: Error,
        featureID: FeatureID,
        document: CADDocument,
        stateRecorder: (FeatureID, FeatureEvaluationState) -> Void
    ) {
        let invalidationSet = invalidationClosure(startingWith: [featureID], in: document.designGraph)
        let invalidated = document.designGraph.order.filter {
            invalidationSet.contains($0) && $0 != featureID
        }
        let failure = FeatureFailure(
            featureID: featureID,
            message: String(describing: error),
            invalidatedFeatureIDs: invalidated
        )
        stateRecorder(featureID, .failed(failure))
        for invalidatedFeatureID in invalidated {
            stateRecorder(invalidatedFeatureID, .blocked(upstreamFeatureID: featureID))
        }
    }

    private func evaluationScope(
        for feature: FeatureNode,
        brepBuffer: BRepEditBuffer,
        generatedNames: PersistentMap<PersistentName, TopologyReference>
    ) throws -> BRepEvaluationScope {
        guard incrementalEvaluatorIdentity != nil else {
            return BRepEvaluationScope(
                brep: brepBuffer.fullModel(),
                generatedNames: generatedNames.materializedDictionary(),
                bodyIDs: Set(brepBuffer.fullModel().bodies.keys),
                bodyCount: 0
            )
        }
        let bodyIDs = try inputBodyIDs(for: feature, generatedNames: generatedNames)
        let brep = try brepBuffer.scopedModel(bodyIDs: bodyIDs)
        return BRepEvaluationScope(
            brep: brep,
            generatedNames: scopedGeneratedNames(from: generatedNames, in: brep),
            bodyIDs: bodyIDs,
            bodyCount: bodyIDs.count
        )
    }

    private func inputBodyIDs(
        for feature: FeatureNode,
        generatedNames: PersistentMap<PersistentName, TopologyReference>
    ) throws -> Set<BodyID> {
        var bodyIDs = Set<BodyID>()
        for input in feature.inputs {
            switch input.role {
            case .target, .body, .sheet:
                break
            case .profile, .curve, .path, .guide:
                continue
            }
            let name = PersistentName(components: [
                .feature(input.featureID),
                .generated(GeneratedSubshapeRole.body.rawValue),
            ])
            guard let reference = generatedNames[name] else {
                continue
            }
            guard case let .body(bodyID) = reference else {
                throw FeatureEvaluationError.invalidGraph(
                    "Feature body input persistent name did not resolve to a body."
                )
            }
            bodyIDs.insert(bodyID)
        }
        return bodyIDs
    }

    private func scopedGeneratedNames(
        from generatedNames: PersistentMap<PersistentName, TopologyReference>,
        in brep: BRepModel
    ) -> [PersistentName: TopologyReference] {
        guard !brep.bodies.isEmpty else {
            return [:]
        }
        var scopedNames: [PersistentName: TopologyReference] = [:]
        for (name, reference) in generatedNames {
            switch reference {
            case .body(let bodyID):
                if brep.bodies[bodyID] != nil {
                    scopedNames[name] = reference
                }
            case .face(let faceID):
                if brep.faces[faceID] != nil {
                    scopedNames[name] = reference
                }
            case .edge(let edgeID):
                if brep.edges[edgeID] != nil {
                    scopedNames[name] = reference
                }
            case .vertex(let vertexID):
                if brep.vertices[vertexID] != nil {
                    scopedNames[name] = reference
                }
            }
        }
        return scopedNames
    }

    private func applyGeneratedNameMutation(
        _ result: EvaluationResult,
        to generatedNames: inout PersistentMap<PersistentName, TopologyReference>
    ) throws -> DictionaryDelta<PersistentName, TopologyReference> {
        var removed: [PersistentName: TopologyReference] = [:]
        var inserted: [PersistentName: TopologyReference] = [:]
        var updated: [
            PersistentName: DictionaryDelta<PersistentName, TopologyReference>.Update
        ] = [:]

        for name in result.removedGeneratedNames {
            if let reference = generatedNames.removeValue(forKey: name) {
                removed[name] = reference
            }
        }
        for (name, reference) in result.generatedNames {
            if let previousReference = removed.removeValue(forKey: name) {
                if previousReference != reference {
                    updated[name] = .init(before: previousReference, after: reference)
                }
            } else {
                guard generatedNames[name] == nil else {
                    throw FeatureEvaluationError.invalidGraph(
                        "Generated persistent name collision."
                    )
                }
                inserted[name] = reference
            }
            generatedNames[name] = reference
        }
        return DictionaryDelta(
            removed: removed,
            inserted: inserted,
            updated: updated
        )
    }
}

private struct BRepEvaluationScope {
    var brep: BRepModel
    var generatedNames: [PersistentName: TopologyReference]
    var bodyIDs: Set<BodyID>
    var bodyCount: Int
}

private struct IncrementalEvaluationBase {
    var brepBuffer: BRepEditBuffer
    var generatedNames: PersistentMap<PersistentName, TopologyReference>
    var affectedBodyIDs: Set<BodyID>
    var rollbackMutationCount: Int

    static var empty: IncrementalEvaluationBase {
        IncrementalEvaluationBase(
            brepBuffer: BRepEditBuffer(),
            generatedNames: [:],
            affectedBodyIDs: [],
            rollbackMutationCount: 0
        )
    }
}

private struct MeshEvaluationResult {
    var meshes: PersistentMap<BodyID, Mesh>
    var tessellatedBodyCount: Int
    var reusedMeshCount: Int
}
