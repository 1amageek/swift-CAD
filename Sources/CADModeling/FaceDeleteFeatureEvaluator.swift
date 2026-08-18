import CADCore
import CADIR
import CADTopology

public struct FaceDeleteFeatureEvaluator: FeatureEvaluating, ValidatedFeatureEvaluating {
    private let subshapeResolver: any StableSubshapeResolving
    private let identityBuilder: any CarriedTopologyIdentityBuilding

    public init(
        subshapeResolver: any StableSubshapeResolving = StableSubshapeResolver()
    ) {
        self.subshapeResolver = subshapeResolver
        identityBuilder = DefaultCarriedTopologyIdentityBuilder()
    }

    public func evaluate(
        feature: FeatureNode,
        context: EvaluationContext
    ) throws -> EvaluationResult {
        try evaluateValidated(feature: feature, context: context).result
    }

    package func evaluateValidated(
        feature: FeatureNode,
        context: EvaluationContext
    ) throws -> ValidatedFeatureEvaluation {
        try FeatureEvaluationBoundary.evaluateValidated(
            featureID: feature.id,
            tolerance: context.tolerance
        ) {
            try evaluateFaceDelete(feature: feature, context: context)
        }
    }

    private func evaluateFaceDelete(
        feature: FeatureNode,
        context: EvaluationContext
    ) throws -> EvaluationResult {
        guard case let .faceDelete(faceDelete) = feature.operation else {
            throw kernelError(
                .invalidInput,
                featureID: feature.id,
                tolerance: context.tolerance,
                "Face delete evaluator requires a faceDelete feature."
            )
        }
        try faceDelete.validate()
        try context.brep.validate(level: .exact, tolerance: context.tolerance)

        let bodyID = try targetBodyID(for: faceDelete.target.featureID, context: context)
        let replacedSubshapeIDs = try BodyTopologyScope(
            bodyID: bodyID,
            model: context.brep
        ).subshapeIDs(in: context.subshapes)
        var resolvedFaceIDs = Set<FaceID>()
        for stableReference in faceDelete.faces {
            let faceID = try targetFaceID(for: stableReference, featureID: feature.id, context: context)
            guard resolvedFaceIDs.insert(faceID).inserted else {
                throw kernelError(
                    .invalidInput,
                    featureID: feature.id,
                    subshapeID: stableReference.subshapeID,
                    tolerance: context.tolerance,
                    "Face delete selections resolve to the same face."
                )
            }
        }

        var model = context.brep
        var topologyIDs = FeatureTopologyIDAllocator(featureID: feature.id)
        try deleteFaces(
            resolvedFaceIDs,
            from: bodyID,
            featureID: feature.id,
            model: &model,
            tolerance: context.tolerance,
            topologyIDs: &topologyIDs
        )
        try model.validate(level: .exact, tolerance: context.tolerance)

        let identity = try identityBuilder.identity(
            featureID: feature.id,
            bodyID: bodyID,
            model: model,
            context: context
        )
        return EvaluationResult(
            brep: model,
            subshapes: identity.subshapes,
            removedSubshapeIDs: replacedSubshapeIDs,
            lineage: identity.lineage
        )
    }

    private func targetBodyID(
        for featureID: FeatureID,
        context: EvaluationContext
    ) throws -> BodyID {
        try context.bodyID(generatedBy: featureID)
    }

    private func targetFaceID(
        for stableReference: StableSubshapeReference,
        featureID: FeatureID,
        context: EvaluationContext
    ) throws -> FaceID {
        let reference = try subshapeResolver.topologyReference(
            for: stableReference,
            model: context.brep,
            subshapes: context.subshapes,
            lineage: context.lineage,
            tolerance: context.tolerance
        )
        guard case let .face(faceID) = reference else {
            throw kernelError(
                .missingReference,
                featureID: featureID,
                subshapeID: stableReference.subshapeID,
                tolerance: context.tolerance,
                "Face delete target did not resolve to a face."
            )
        }
        return faceID
    }

    private func deleteFaces(
        _ faceIDs: Set<FaceID>,
        from bodyID: BodyID,
        featureID: FeatureID,
        model: inout BRepModel,
        tolerance: ModelingTolerance,
        topologyIDs: inout FeatureTopologyIDAllocator
    ) throws {
        guard faceIDs.isEmpty == false else {
            throw kernelError(
                .invalidInput,
                featureID: featureID,
                tolerance: tolerance,
                "Face delete requires at least one face target."
            )
        }
        guard var body = model.bodies[bodyID] else {
            throw TopologyError.missingReference("Missing Face Delete body \(bodyID).")
        }
        guard body.kind == .solid else {
            throw kernelError(
                .unsupportedCapability,
                featureID: featureID,
                tolerance: tolerance,
                "Face delete requires a solid target body."
            )
        }
        let targetBodyFaceIDs = try collectFaceIDs(in: body, model: model)
        guard faceIDs.isSubset(of: targetBodyFaceIDs) else {
            throw kernelError(
                .missingReference,
                featureID: featureID,
                tolerance: tolerance,
                "Face delete target faces must all belong to the target body."
            )
        }

        var remainingShells: [ShellID] = []
        for shellID in body.shellIDs {
            guard let shell = model.shells[shellID] else {
                throw TopologyError.missingReference("Missing Face Delete shell \(shellID).")
            }
            let remainingFaceIDs = shell.faceIDs.filter { faceIDs.contains($0) == false }
            guard remainingFaceIDs.isEmpty == false else {
                throw kernelError(
                    .unsupportedCapability,
                    featureID: featureID,
                    tolerance: tolerance,
                    "Face delete cannot remove every face of a shell."
                )
            }
            let components = try connectedFaceComponents(
                remainingFaceIDs,
                model: model
            )
            for (componentIndex, component) in components.enumerated() {
                let componentShellID = componentIndex == 0
                    ? shellID
                    : topologyIDs.nextShellID()
                model.shells[componentShellID] = Shell(
                    id: componentShellID,
                    faceIDs: component,
                    orientation: shell.orientation
                )
                remainingShells.append(componentShellID)
            }
        }

        for faceID in faceIDs.sorted() {
            guard let face = model.faces.removeValue(forKey: faceID) else {
                throw TopologyError.missingReference("Missing Face Delete face \(faceID).")
            }
            for loopID in face.loops {
                model.loops.removeValue(forKey: loopID)
            }
        }
        body.topology = .sheet(shellIDs: remainingShells)
        model.bodies[bodyID] = body
        pruneUnreferencedTopology(in: &model)
    }

    private func connectedFaceComponents(
        _ faceIDs: [FaceID],
        model: BRepModel
    ) throws -> [[FaceID]] {
        let faceSet = Set(faceIDs)
        var edgeFaces: [EdgeID: [FaceID]] = [:]
        for faceID in faceIDs.sorted() {
            guard let face = model.faces[faceID] else {
                throw TopologyError.missingReference("Missing Face Delete face \(faceID).")
            }
            for loopID in face.loops {
                guard let loop = model.loops[loopID] else {
                    throw TopologyError.missingReference("Missing Face Delete loop \(loopID).")
                }
                for coedge in loop.coedges {
                    edgeFaces[coedge.edgeID, default: []].append(faceID)
                }
            }
        }

        var adjacency: [FaceID: Set<FaceID>] = Dictionary(
            uniqueKeysWithValues: faceIDs.map { ($0, Set<FaceID>()) }
        )
        for incidentFaces in edgeFaces.values {
            let retainedFaces = incidentFaces.filter { faceSet.contains($0) }.sorted()
            for faceID in retainedFaces {
                adjacency[faceID, default: []].formUnion(retainedFaces.filter { $0 != faceID })
            }
        }

        var pending = faceSet
        var components: [[FaceID]] = []
        while let seed = pending.min() {
            var stack = [seed]
            var component = Set<FaceID>()
            pending.remove(seed)
            while let faceID = stack.popLast() {
                guard component.insert(faceID).inserted else { continue }
                let neighbors = adjacency[faceID, default: []]
                    .filter { pending.contains($0) }
                    .sorted(by: >)
                for neighbor in neighbors {
                    pending.remove(neighbor)
                    stack.append(neighbor)
                }
            }
            components.append(component.sorted())
        }
        return components.sorted { lhs, rhs in
            guard let left = lhs.first, let right = rhs.first else {
                return lhs.count < rhs.count
            }
            return left < right
        }
    }

    private func collectFaceIDs(in body: Body, model: BRepModel) throws -> Set<FaceID> {
        var result: Set<FaceID> = []
        for shellID in body.shellIDs {
            guard let shell = model.shells[shellID] else {
                throw TopologyError.missingReference("Missing Face Delete shell \(shellID).")
            }
            result.formUnion(shell.faceIDs)
        }
        return result
    }

    private func pruneUnreferencedTopology(in model: inout BRepModel) {
        let referencedLoopIDs = Set(model.faces.values.flatMap(\.loops))
        model.loops = model.loops.filter { referencedLoopIDs.contains($0.key) }

        let referencedSurfaceIDs = Set(model.faces.values.map(\.surfaceID))
        model.geometry.surfaces = model.geometry.surfaces.filter { referencedSurfaceIDs.contains($0.key) }

        let referencedEdgeIDs = Set(model.loops.values.flatMap { loop in
            loop.edges.map(\.edgeID)
        })
        model.edges = model.edges.filter { referencedEdgeIDs.contains($0.key) }

        let referencedCurveIDs = Set(model.edges.values.map(\.curveID))
        model.geometry.curves = model.geometry.curves.filter { referencedCurveIDs.contains($0.key) }

        let referencedVertexIDs = Set(model.edges.values.flatMap { edge in
            [edge.startVertexID, edge.endVertexID]
        })
        model.vertices = model.vertices.filter { referencedVertexIDs.contains($0.key) }
    }

    private func kernelError(
        _ code: KernelErrorCode,
        featureID: FeatureID,
        subshapeID: SubshapeID? = nil,
        tolerance: ModelingTolerance,
        _ message: String
    ) -> KernelError {
        KernelError(
            phase: code == .topologyFailure ? .topology : .evaluation,
            code: code,
            featureID: featureID,
            subshapeID: subshapeID,
            tolerance: tolerance,
            message: message
        )
    }

}
