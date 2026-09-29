import CADCore
import CADGeometry
import CADIR
import CADModeling
import CADTopology

/// Copies one component of a body, or chosen faces of it, as a body of its own beside the source,
/// which it leaves as it is. The copy is the source's exact faces sewn under the extraction's
/// identity, each copied subshape's lineage leading to the source subshape it copies.
struct ExtractFeatureEvaluator: FeatureEvaluating, ValidatedFeatureEvaluating {
    private let subshapeResolver: any StableSubshapeResolving

    init(subshapeResolver: any StableSubshapeResolving = StableSubshapeResolver()) {
        self.subshapeResolver = subshapeResolver
    }

    func evaluate(feature: FeatureNode, context: EvaluationContext) throws -> EvaluationResult {
        try evaluateValidated(feature: feature, context: context).result
    }

    func evaluateValidated(feature: FeatureNode, context: EvaluationContext) throws -> ValidatedFeatureEvaluation {
        try FeatureEvaluationBoundary.evaluateValidated(featureID: feature.id, tolerance: context.tolerance) {
            try extract(feature: feature, context: context)
        }
    }

    private func extract(feature: FeatureNode, context: EvaluationContext) throws -> EvaluationResult {
        guard case let .extract(extract) = feature.operation else {
            throw error(.invalidInput, feature.id, context, "Extract evaluator requires an extract feature.")
        }
        try FeatureEvaluationBoundary.validateRequest(featureID: feature.id, tolerance: context.tolerance) {
            try extract.validate()
        }
        let tolerance = context.tolerance
        let sourceBodyID = try context.bodyID(generatedBy: extract.target.featureID)
        guard let body = context.brep.bodies[sourceBodyID] else {
            throw error(.missingReference, feature.id, context, "Extract source body is missing.")
        }
        let extraction = try DefaultBRepFacePatchExtractor().extract(
            bodyID: sourceBodyID,
            featureID: feature.id,
            from: context.brep,
            sourceSubshapes: context.subshapes.entries,
            tolerance: tolerance
        )
        // The extractor names shell i of the body "shell:i" and its face j "shell:i:face:j".
        let shellStableIDs = Dictionary(uniqueKeysWithValues: body.shellIDs.enumerated().map { ($1, "shell:\($0)") })
        let request: BRepSewingRequest
        switch extract.selection {
        case let .component(index, count):
            let components = try orderedComponents(of: body, model: context.brep, subshapes: context.subshapes.entries, featureID: feature.id, context: context)
            guard components.count == count else {
                throw error(
                    .invalidInput, feature.id, context,
                    "The source now has \(components.count) components, not the \(count) this extraction was made for."
                )
            }
            let component = components[index]
            let keptShells = Set(component.shellIDs.compactMap { shellStableIDs[$0] })
            let shells = extraction.request.shells.filter { keptShells.contains($0.stableID) }
            let topology: BRepSewingBodyTopology
            switch component {
            case let .solid(solid):
                guard let outer = shellStableIDs[solid.outerShellID] else {
                    throw error(.missingReference, feature.id, context, "Extract lost a component's outer shell.")
                }
                topology = .solid(components: [BRepSewingSolidComponent(
                    outerShellStableID: outer,
                    voidShellStableIDs: solid.voidShellIDs.compactMap { shellStableIDs[$0] }
                )])
            case let .sheet(shellID):
                guard let stableID = shellStableIDs[shellID] else {
                    throw error(.missingReference, feature.id, context, "Extract lost a component's shell.")
                }
                topology = .sheet(shellStableIDs: [stableID])
            }
            request = BRepSewingRequest(featureID: feature.id, bodyTopology: topology, shells: shells)
        case let .faces(references):
            var chosen = Set<String>()
            for reference in references {
                let topology = try subshapeResolver.topologyReference(
                    for: reference,
                    model: context.brep,
                    subshapes: context.subshapes,
                    lineage: context.lineage,
                    tolerance: tolerance
                )
                guard case let .face(faceID) = topology,
                      let shellIndex = body.shellIDs.firstIndex(where: { context.brep.shells[$0]?.faceIDs.contains(faceID) == true }),
                      let faceIndex = context.brep.shells[body.shellIDs[shellIndex]]?.faceIDs.firstIndex(of: faceID) else {
                    throw error(.missingReference, feature.id, context, "An extracted face is not a face of the source body.")
                }
                guard chosen.insert("shell:\(shellIndex):face:\(faceIndex)").inserted else {
                    throw error(.invalidInput, feature.id, context, "Extracted faces resolve to the same face.")
                }
            }
            let patches = extraction.request.shells.flatMap(\.patches).filter { chosen.contains($0.stableID) }
            let shells = try BRepSewingPatchShellPartitioner().shells(
                patches: patches,
                stablePrefix: "extract:shell",
                tolerance: tolerance
            )
            request = BRepSewingRequest(featureID: feature.id, bodyKind: .sheet, shells: shells)
        }
        let sewn = try DefaultBRepSewer().sew(request, tolerance: tolerance)
        var model = context.brep
        try BRepModelCombiner().merge(sewn.brep, into: &model)
        return EvaluationResult(brep: model, subshapes: sewn.subshapes, lineage: sewn.lineage)
    }

    private enum Component {
        case solid(SolidShellComponent)
        case sheet(ShellID)

        var shellIDs: [ShellID] {
            switch self {
            case let .solid(solid): [solid.outerShellID] + solid.voidShellIDs
            case let .sheet(shellID): [shellID]
            }
        }
    }

    /// The body's components, ordered by the smallest identity of their faces.
    private func orderedComponents(
        of body: Body,
        model: BRepModel,
        subshapes: [SubshapeID: TopologyReference],
        featureID: FeatureID,
        context: EvaluationContext
    ) throws -> [Component] {
        let components: [Component] = switch body.topology {
        case let .solid(solids): solids.map { .solid($0) }
        case let .sheet(shellIDs): shellIDs.map { .sheet($0) }
        }
        var faceIdentity: [FaceID: SubshapeID] = [:]
        for (subshapeID, reference) in subshapes {
            guard case let .face(faceID) = reference else { continue }
            if let known = faceIdentity[faceID], known < subshapeID { continue }
            faceIdentity[faceID] = subshapeID
        }
        let keyed = try components.map { component -> (SubshapeID, Component) in
            let identities = component.shellIDs.flatMap { model.shells[$0]?.faceIDs ?? [] }.compactMap { faceIdentity[$0] }
            guard let key = identities.min() else {
                throw error(.missingReference, featureID, context, "A source component has no published face identity to order it by.")
            }
            return (key, component)
        }
        return keyed.sorted { $0.0 < $1.0 }.map(\.1)
    }

    private func error(_ code: KernelErrorCode, _ featureID: FeatureID, _ context: EvaluationContext, _ message: String) -> KernelError {
        KernelError(phase: .evaluation, code: code, featureID: featureID, tolerance: context.tolerance, message: message)
    }
}
