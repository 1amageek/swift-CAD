import CADCore
import CADIR

public struct FaceDeleteFeatureEvaluator: FeatureEvaluating {
    public init() {}

    public func evaluate(feature: FeatureNode, context: EvaluationContext) throws -> EvaluationResult {
        guard case let .faceDelete(faceDelete) = feature.operation else {
            throw FeatureEvaluationError.unsupportedOperation(
                "FaceDeleteFeatureEvaluator only supports faceDelete."
            )
        }
        var model = context.brep
        let bodyID = try targetBodyID(for: faceDelete.target.featureID, context: context)
        let faceIDs = try faceDelete.facePersistentNames.map { name in
            try targetFaceID(for: name, context: context)
        }
        try deleteFaces(
            Set(faceIDs),
            from: bodyID,
            model: &model
        )
        try model.validate(tolerance: context.tolerance)

        var generatedNames: [PersistentName: TopologyReference] = [
            PersistentName(components: [
                .feature(feature.id),
                .generated(GeneratedSubshapeRole.body.rawValue),
            ]): .body(bodyID),
        ]
        try addCarriedBodyTopologyNames(
            featureID: feature.id,
            bodyID: bodyID,
            model: model,
            generatedNames: &generatedNames
        )
        let removedNames = removedGeneratedNames(from: context.generatedNames, after: model)
        return EvaluationResult(
            brep: model,
            generatedNames: generatedNames,
            removedGeneratedNames: removedNames
        )
    }

    private func targetBodyID(
        for featureID: FeatureID,
        context: EvaluationContext
    ) throws -> BodyID {
        let name = PersistentName(components: [.feature(featureID), .generated(GeneratedSubshapeRole.body.rawValue)])
        guard let reference = context.generatedNames[name],
              case let .body(bodyID) = reference else {
            throw FeatureEvaluationError.missingInput("Face Delete target body could not be resolved.")
        }
        return bodyID
    }

    private func targetFaceID(
        for persistentName: PersistentName,
        context: EvaluationContext
    ) throws -> FaceID {
        guard let reference = context.generatedNames[persistentName],
              case let .face(faceID) = reference else {
            throw FeatureEvaluationError.missingInput("Face Delete target face could not be resolved.")
        }
        return faceID
    }

    private func deleteFaces(
        _ faceIDs: Set<FaceID>,
        from bodyID: BodyID,
        model: inout BRepModel
    ) throws {
        guard faceIDs.isEmpty == false else {
            throw FeatureEvaluationError.invalidGraph("Face Delete requires at least one face target.")
        }
        guard var body = model.bodies[bodyID] else {
            throw TopologyError.missingReference("Missing Face Delete body \(bodyID).")
        }
        guard body.kind == .solid else {
            throw FeatureEvaluationError.unsupportedOperation(
                "Face Delete currently supports solid target bodies only."
            )
        }
        let targetBodyFaceIDs = try collectFaceIDs(in: body, model: model)
        guard faceIDs.isSubset(of: targetBodyFaceIDs) else {
            throw FeatureEvaluationError.missingInput("Face Delete target faces must all belong to the target body.")
        }

        var remainingShells: [ShellID] = []
        var didDelete = false
        for shellID in body.shellIDs {
            guard var shell = model.shells[shellID] else {
                throw TopologyError.missingReference("Missing Face Delete shell \(shellID).")
            }
            let originalCount = shell.faceIDs.count
            shell.faceIDs.removeAll { faceID in
                faceIDs.contains(faceID)
            }
            didDelete = didDelete || shell.faceIDs.count != originalCount
            guard shell.faceIDs.isEmpty == false else {
                throw FeatureEvaluationError.unsupportedOperation(
                    "Face Delete would remove an entire shell."
                )
            }
            model.shells[shellID] = shell
            remainingShells.append(shellID)
        }
        guard didDelete else {
            throw FeatureEvaluationError.missingInput("Face Delete target face is not on the target body.")
        }

        for faceID in faceIDs {
            guard let face = model.faces.removeValue(forKey: faceID) else {
                throw TopologyError.missingReference("Missing Face Delete face \(faceID).")
            }
            for loopID in face.loops {
                model.loops.removeValue(forKey: loopID)
            }
        }
        body.shellIDs = remainingShells
        body.kind = .sheet
        model.bodies[bodyID] = body
        pruneUnreferencedTopology(in: &model)
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

    private func addCarriedBodyTopologyNames(
        featureID: FeatureID,
        bodyID: BodyID,
        model: BRepModel,
        generatedNames: inout [PersistentName: TopologyReference]
    ) throws {
        guard let body = model.bodies[bodyID] else {
            throw TopologyError.missingReference("Missing Face Delete body \(bodyID).")
        }

        var faceIndex = 0
        var edgeIndex = 0
        var vertexIndex = 0
        for shellID in body.shellIDs {
            guard let shell = model.shells[shellID] else {
                throw TopologyError.missingReference("Missing Face Delete shell \(shellID).")
            }
            for faceID in shell.faceIDs {
                if generatedNames.containsFace(faceID) == false {
                    generatedNames[persistentName(featureID, "carriedFace", faceIndex)] = .face(faceID)
                    faceIndex += 1
                }
                guard let face = model.faces[faceID] else {
                    throw TopologyError.missingReference("Missing Face Delete face \(faceID).")
                }
                for loopID in face.loops {
                    guard let loop = model.loops[loopID] else {
                        throw TopologyError.missingReference("Missing Face Delete loop \(loopID).")
                    }
                    for orientedEdge in loop.edges {
                        let edgeID = orientedEdge.edgeID
                        if generatedNames.containsEdge(edgeID) == false {
                            generatedNames[persistentName(featureID, "carriedEdge", edgeIndex)] = .edge(edgeID)
                            edgeIndex += 1
                        }
                        guard let edge = model.edges[edgeID] else {
                            throw TopologyError.missingReference("Missing Face Delete edge \(edgeID).")
                        }
                        if generatedNames.containsVertex(edge.startVertexID) == false {
                            generatedNames[persistentName(featureID, "carriedVertex", vertexIndex)] = .vertex(edge.startVertexID)
                            vertexIndex += 1
                        }
                        if generatedNames.containsVertex(edge.endVertexID) == false {
                            generatedNames[persistentName(featureID, "carriedVertex", vertexIndex)] = .vertex(edge.endVertexID)
                            vertexIndex += 1
                        }
                    }
                }
            }
        }
    }

    private func persistentName(
        _ featureID: FeatureID,
        _ role: String,
        _ index: Int?
    ) -> PersistentName {
        var components: [NameComponent] = [
            .feature(featureID),
            .generated("faceDelete"),
            .subshape(role),
        ]
        if let index {
            components.append(.index(index))
        }
        return PersistentName(components: components)
    }

    private func removedGeneratedNames(
        from generatedNames: [PersistentName: TopologyReference],
        after model: BRepModel
    ) -> Set<PersistentName> {
        Set(generatedNames.compactMap { name, reference in
            switch reference {
            case .body(let bodyID):
                return model.bodies[bodyID] == nil ? name : nil
            case .face(let faceID):
                return model.faces[faceID] == nil ? name : nil
            case .edge(let edgeID):
                return model.edges[edgeID] == nil ? name : nil
            case .vertex(let vertexID):
                return model.vertices[vertexID] == nil ? name : nil
            }
        })
    }
}

private extension Dictionary where Key == PersistentName, Value == TopologyReference {
    func containsFace(_ faceID: FaceID) -> Bool {
        values.contains { reference in
            if case .face(let referenceFaceID) = reference {
                return referenceFaceID == faceID
            }
            return false
        }
    }

    func containsEdge(_ edgeID: EdgeID) -> Bool {
        values.contains { reference in
            if case .edge(let referenceEdgeID) = reference {
                return referenceEdgeID == edgeID
            }
            return false
        }
    }

    func containsVertex(_ vertexID: VertexID) -> Bool {
        values.contains { reference in
            if case .vertex(let referenceVertexID) = reference {
                return referenceVertexID == vertexID
            }
            return false
        }
    }
}
