import Foundation
import CADCore
import CADIR

public struct FaceDraftFeatureEvaluator: FeatureEvaluating {
    private let resolver: ParameterResolving

    public init(resolver: ParameterResolving = ParameterResolver()) {
        self.resolver = resolver
    }

    public func evaluate(feature: FeatureNode, context: EvaluationContext) throws -> EvaluationResult {
        guard case let .faceDraft(faceDraft) = feature.operation else {
            throw FeatureEvaluationError.unsupportedOperation(
                "FaceDraftFeatureEvaluator only supports faceDraft."
            )
        }
        let angle = try resolvedAngle(faceDraft.angle, context: context)
        var model = context.brep
        let bodyID = try targetBodyID(for: faceDraft.target.featureID, context: context)
        let targetFaceIDs = try faceDraft.facePersistentNames.map { name in
            try targetFaceID(for: name, context: context)
        }
        let neutralFaceID = try targetFaceID(for: faceDraft.neutralFacePersistentName, context: context)
        try draftFaces(
            Set(targetFaceIDs),
            neutralFaceID: neutralFaceID,
            angle: angle,
            in: bodyID,
            model: &model,
            tolerance: context.tolerance
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
        return EvaluationResult(
            brep: model,
            generatedNames: generatedNames,
            removedGeneratedNames: removedGeneratedNames(from: context.generatedNames, after: model)
        )
    }

    private func resolvedAngle(_ expression: CADExpression, context: EvaluationContext) throws -> Double {
        let quantity = try resolver.evaluate(expression, parameters: context.parameters, variables: [:])
        guard quantity.kind == .angle else {
            throw UnitError.expectedQuantity(
                operation: "faceDraft.angle",
                expected: .angle,
                actual: quantity.kind
            )
        }
        guard quantity.value.isFinite,
              abs(quantity.value) > context.tolerance.angle else {
            throw FeatureEvaluationError.invalidDistance(quantity.value)
        }
        let maximum = (Double.pi / 2.0) - context.tolerance.angle
        guard abs(quantity.value) < maximum else {
            throw FeatureEvaluationError.unsupportedOperation(
                "Face Draft angle must be smaller than 90 degrees."
            )
        }
        return quantity.value
    }

    private func targetBodyID(
        for featureID: FeatureID,
        context: EvaluationContext
    ) throws -> BodyID {
        let name = PersistentName(components: [.feature(featureID), .generated(GeneratedSubshapeRole.body.rawValue)])
        guard let reference = context.generatedNames[name],
              case let .body(bodyID) = reference else {
            throw FeatureEvaluationError.missingInput("Face Draft target body could not be resolved.")
        }
        return bodyID
    }

    private func targetFaceID(
        for persistentName: PersistentName,
        context: EvaluationContext
    ) throws -> FaceID {
        guard let reference = context.generatedNames[persistentName],
              case let .face(faceID) = reference else {
            throw FeatureEvaluationError.missingInput("Face Draft target face could not be resolved.")
        }
        return faceID
    }

    private func draftFaces(
        _ faceIDs: Set<FaceID>,
        neutralFaceID: FaceID,
        angle: Double,
        in bodyID: BodyID,
        model: inout BRepModel,
        tolerance: ModelingTolerance
    ) throws {
        guard faceIDs.count == 1, let faceID = faceIDs.first else {
            throw FeatureEvaluationError.unsupportedOperation(
                "Face Draft currently supports exactly one target face."
            )
        }
        guard var body = model.bodies[bodyID] else {
            throw TopologyError.missingReference("Missing Face Draft body \(bodyID).")
        }
        guard body.kind == .solid else {
            throw FeatureEvaluationError.unsupportedOperation(
                "Face Draft currently supports solid target bodies only."
            )
        }
        let bodyFaceIDs = try collectFaceIDs(in: body, model: model)
        guard bodyFaceIDs.contains(faceID),
              bodyFaceIDs.contains(neutralFaceID) else {
            throw FeatureEvaluationError.missingInput(
                "Face Draft target and neutral faces must belong to the target body."
            )
        }
        guard faceID != neutralFaceID else {
            throw FeatureEvaluationError.invalidGraph("Face Draft target face and neutral face must be distinct.")
        }
        try validateLineOnlyTopology(in: body, model: model)

        let neutralPlane = try plane(for: neutralFaceID, in: model)
        let targetPlane = try plane(for: faceID, in: model)
        let neutralNormal = try neutralPlane.normal.normalized(tolerance: tolerance.distance)
        let targetNormal = try targetPlane.normal.normalized(tolerance: tolerance.distance)
        let projectedTargetNormal = targetNormal - neutralNormal * targetNormal.dot(neutralNormal)
        guard projectedTargetNormal.length > max(tolerance.distance, tolerance.angle) else {
            throw FeatureEvaluationError.unsupportedOperation(
                "Face Draft target face must not be parallel to the neutral face."
            )
        }
        let draftDirection = try projectedTargetNormal.normalized(tolerance: tolerance.distance)
        let targetVertexIDs = try vertexIDs(on: faceID, model: model)
        let tangent = tan(angle)
        var movedCount = 0
        var neutralCount = 0
        for vertexID in targetVertexIDs {
            guard var vertex = model.vertices[vertexID] else {
                throw TopologyError.missingReference("Missing Face Draft vertex \(vertexID).")
            }
            let distanceFromNeutral = abs((vertex.point - neutralPlane.origin).dot(neutralNormal))
            if distanceFromNeutral <= tolerance.distance {
                neutralCount += 1
                continue
            }
            let offset = draftDirection * (distanceFromNeutral * tangent)
            vertex.point = vertex.point + offset
            try vertex.point.validate()
            model.vertices[vertexID] = vertex
            movedCount += 1
        }
        guard neutralCount >= 2, movedCount >= 2 else {
            throw FeatureEvaluationError.unsupportedOperation(
                "Face Draft currently requires the target face to share one edge with the neutral face."
            )
        }
        try rebuildLineCurves(in: body, model: &model, tolerance: tolerance)
        try rebuildPlanarSurfaces(in: body, model: &model, tolerance: tolerance)
        body.kind = .solid
        model.bodies[bodyID] = body
    }

    private func collectFaceIDs(in body: Body, model: BRepModel) throws -> Set<FaceID> {
        var result: Set<FaceID> = []
        for shellID in body.shellIDs {
            guard let shell = model.shells[shellID] else {
                throw TopologyError.missingReference("Missing Face Draft shell \(shellID).")
            }
            result.formUnion(shell.faceIDs)
        }
        return result
    }

    private func validateLineOnlyTopology(in body: Body, model: BRepModel) throws {
        for edgeID in try edgeIDs(in: body, model: model) {
            guard let edge = model.edges[edgeID],
                  let curve = model.geometry.curves[edge.curveID],
                  case .line = curve else {
                throw FeatureEvaluationError.unsupportedOperation(
                    "Face Draft currently supports line-only planar topology."
                )
            }
        }
    }

    private func plane(for faceID: FaceID, in model: BRepModel) throws -> Plane3D {
        guard let face = model.faces[faceID],
              let surface = model.geometry.surfaces[face.surfaceID],
              case let .plane(plane) = surface else {
            throw FeatureEvaluationError.unsupportedOperation(
                "Face Draft currently supports planar target and neutral faces only."
            )
        }
        return plane
    }

    private func vertexIDs(on faceID: FaceID, model: BRepModel) throws -> Set<VertexID> {
        guard let face = model.faces[faceID] else {
            throw TopologyError.missingReference("Missing Face Draft face \(faceID).")
        }
        var result: Set<VertexID> = []
        for loopID in face.loops {
            result.formUnion(try model.orderedVertexIDs(for: loopID))
        }
        return result
    }

    private func rebuildLineCurves(
        in body: Body,
        model: inout BRepModel,
        tolerance: ModelingTolerance
    ) throws {
        for loopID in try loopIDs(in: body, model: model) {
            guard var loop = model.loops[loopID] else {
                throw TopologyError.missingReference("Missing Face Draft loop \(loopID).")
            }
            for index in loop.edges.indices {
                loop.edges[index].surfaceParameterCurve = nil
            }
            model.loops[loopID] = loop
        }

        for edgeID in try edgeIDs(in: body, model: model) {
            guard var edge = model.edges[edgeID],
                  let start = model.vertices[edge.startVertexID]?.point,
                  let end = model.vertices[edge.endVertexID]?.point else {
                throw TopologyError.missingReference("Missing Face Draft edge \(edgeID).")
            }
            guard let existingCurve = model.geometry.curves[edge.curveID],
                  case .line = existingCurve else {
                throw FeatureEvaluationError.unsupportedOperation(
                    "Face Draft currently supports line-only planar topology."
                )
            }
            let delta = end - start
            let length = delta.length
            guard length > tolerance.distance else {
                throw TopologyError.invalidEdge(edgeID)
            }
            let direction = try delta.normalized(tolerance: tolerance.distance)
            let curveID = CurveID()
            model.geometry.curves.removeValue(forKey: edge.curveID)
            model.geometry.curves[curveID] = .line(Line3D(origin: start, direction: direction))
            edge.curveID = curveID
            edge.trim = CurveTrim(startParameter: 0.0, endParameter: length)
            edge.surfaceApproximationTolerance = nil
            model.edges[edgeID] = edge
        }
    }

    private func rebuildPlanarSurfaces(
        in body: Body,
        model: inout BRepModel,
        tolerance: ModelingTolerance
    ) throws {
        for faceID in try collectFaceIDs(in: body, model: model) {
            guard let face = model.faces[faceID],
                  let loopID = face.loops.first else {
                throw TopologyError.missingReference("Missing Face Draft face \(faceID).")
            }
            for loopID in face.loops {
                guard let loop = model.loops[loopID] else {
                    throw TopologyError.missingReference("Missing Face Draft loop \(loopID).")
                }
                for orientedEdge in loop.edges {
                    guard let edge = model.edges[orientedEdge.edgeID],
                          let curve = model.geometry.curves[edge.curveID],
                          case .line = curve else {
                        throw FeatureEvaluationError.unsupportedOperation(
                            "Face Draft currently supports line-only planar topology."
                        )
                    }
                }
            }
            let points = try model.orderedPoints(for: loopID)
            let normal = try planeNormal(for: points, tolerance: tolerance)
            let plane = Plane3D(origin: points[0], normal: normal)
            try plane.validate(tolerance: tolerance)
            for point in points {
                let distance = abs((point - plane.origin).dot(normal))
                guard distance <= tolerance.distance else {
                    throw FeatureEvaluationError.unsupportedOperation(
                        "Face Draft produced a non-planar face in the current supported subset."
                    )
                }
            }
            model.geometry.surfaces[face.surfaceID] = .plane(plane)
        }
    }

    private func planeNormal(
        for points: [Point3D],
        tolerance: ModelingTolerance
    ) throws -> Vector3D {
        guard points.count >= 3 else {
            throw FeatureEvaluationError.unsupportedOperation(
                "Face Draft produced a degenerate planar face."
            )
        }
        let origin = points[0]
        for firstIndex in 1..<(points.count - 1) {
            for secondIndex in (firstIndex + 1)..<points.count {
                let cross = (points[firstIndex] - origin).cross(points[secondIndex] - origin)
                if cross.length > tolerance.distance * tolerance.distance {
                    return try cross.normalized(tolerance: tolerance.distance)
                }
            }
        }
        throw FeatureEvaluationError.unsupportedOperation(
            "Face Draft produced a degenerate planar face."
        )
    }

    private func loopIDs(in body: Body, model: BRepModel) throws -> Set<LoopID> {
        var result: Set<LoopID> = []
        for faceID in try collectFaceIDs(in: body, model: model) {
            guard let face = model.faces[faceID] else {
                throw TopologyError.missingReference("Missing Face Draft face \(faceID).")
            }
            result.formUnion(face.loops)
        }
        return result
    }

    private func edgeIDs(in body: Body, model: BRepModel) throws -> Set<EdgeID> {
        var result: Set<EdgeID> = []
        for loopID in try loopIDs(in: body, model: model) {
            guard let loop = model.loops[loopID] else {
                throw TopologyError.missingReference("Missing Face Draft loop \(loopID).")
            }
            result.formUnion(loop.edges.map(\.edgeID))
        }
        return result
    }

    private func addCarriedBodyTopologyNames(
        featureID: FeatureID,
        bodyID: BodyID,
        model: BRepModel,
        generatedNames: inout [PersistentName: TopologyReference]
    ) throws {
        guard let body = model.bodies[bodyID] else {
            throw TopologyError.missingReference("Missing Face Draft body \(bodyID).")
        }

        var faceIndex = 0
        var edgeIndex = 0
        var vertexIndex = 0
        for shellID in body.shellIDs {
            guard let shell = model.shells[shellID] else {
                throw TopologyError.missingReference("Missing Face Draft shell \(shellID).")
            }
            for faceID in shell.faceIDs {
                if generatedNames.containsFace(faceID) == false {
                    generatedNames[persistentName(featureID, "carriedFace", faceIndex)] = .face(faceID)
                    faceIndex += 1
                }
                guard let face = model.faces[faceID] else {
                    throw TopologyError.missingReference("Missing Face Draft face \(faceID).")
                }
                for loopID in face.loops {
                    guard let loop = model.loops[loopID] else {
                        throw TopologyError.missingReference("Missing Face Draft loop \(loopID).")
                    }
                    for orientedEdge in loop.edges {
                        let edgeID = orientedEdge.edgeID
                        if generatedNames.containsEdge(edgeID) == false {
                            generatedNames[persistentName(featureID, "carriedEdge", edgeIndex)] = .edge(edgeID)
                            edgeIndex += 1
                        }
                        guard let edge = model.edges[edgeID] else {
                            throw TopologyError.missingReference("Missing Face Draft edge \(edgeID).")
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
            .generated("faceDraft"),
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
