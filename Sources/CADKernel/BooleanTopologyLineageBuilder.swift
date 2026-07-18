import CADCore
import CADGeometry
import CADIR
import CADTopology

struct BooleanTopologyLineageBuilder {
    func build(
        featureID: FeatureID,
        operandBodyIDs: [BodyID],
        inputModel: BRepModel,
        resultModel: BRepModel,
        inputSubshapes: [SubshapeID: TopologyReference],
        outputSubshapes: [SubshapeID: TopologyReference],
        inputLineage: [SubshapeID: TopologyLineage],
        tolerance: ModelingTolerance
    ) throws -> [SubshapeID: TopologyLineage] {
        try tolerance.validate()
        let operandSet = Set(operandBodyIDs)
        let inputReferences = inputSubshapes.compactMap { subshapeID, reference -> InputReference? in
            guard belongs(reference, toAny: operandSet, in: inputModel),
                  inputLineage[subshapeID] != nil else {
                return nil
            }
            return InputReference(subshapeID: subshapeID, reference: reference)
        }
        var drafts: [Draft] = []
        for output in outputSubshapes.keys.sorted() {
            guard output.featureID == featureID,
                  let reference = outputSubshapes[output] else {
                throw KernelError(
                    phase: .topology,
                    code: .topologyFailure,
                    featureID: featureID,
                    subshapeID: output,
                    tolerance: tolerance,
                    message: "Boolean output subshape identity does not belong to its feature."
                )
            }
            let parents = try inputReferences.compactMap { candidate -> SubshapeID? in
                try matches(
                    output: reference,
                    input: candidate.reference,
                    inputModel: inputModel,
                    resultModel: resultModel,
                    tolerance: tolerance
                ) ? candidate.subshapeID : nil
            }.sorted()
            drafts.append(Draft(output: output, parents: Array(Set(parents)).sorted()))
        }
        var parentUseCount: [SubshapeID: Int] = [:]
        for draft in drafts {
            for parent in draft.parents {
                parentUseCount[parent, default: 0] += 1
            }
        }
        return Dictionary(uniqueKeysWithValues: drafts.map { draft in
            let relation: TopologyLineageRelation
            if draft.parents.isEmpty {
                relation = .generated
            } else if draft.parents.count > 1 {
                relation = .merged
            } else if parentUseCount[draft.parents[0], default: 0] > 1 {
                relation = .split
            } else {
                relation = .preserved
            }
            let lineage = TopologyLineage(
                output: draft.output,
                parents: draft.parents,
                relation: relation
            )
            return (draft.output, lineage)
        })
    }

    private func matches(
        output: TopologyReference,
        input: TopologyReference,
        inputModel: BRepModel,
        resultModel: BRepModel,
        tolerance: ModelingTolerance
    ) throws -> Bool {
        switch (output, input) {
        case (.body, .body):
            return true
        case let (.face(outputID), .face(inputID)):
            return try facesMatch(
                outputID: outputID,
                inputID: inputID,
                inputModel: inputModel,
                resultModel: resultModel,
                tolerance: tolerance
            )
        case let (.edge(outputID), .edge(inputID)):
            return try edgesMatch(
                outputID: outputID,
                inputID: inputID,
                inputModel: inputModel,
                resultModel: resultModel,
                tolerance: tolerance
            )
        case let (.vertex(outputID), .vertex(inputID)):
            guard let outputPoint = resultModel.vertices[outputID]?.point,
                  let inputPoint = inputModel.vertices[inputID]?.point else {
                return false
            }
            return outputPoint.isApproximatelyEqual(to: inputPoint, tolerance: tolerance.distance)
        default:
            return false
        }
    }

    private func facesMatch(
        outputID: FaceID,
        inputID: FaceID,
        inputModel: BRepModel,
        resultModel: BRepModel,
        tolerance: ModelingTolerance
    ) throws -> Bool {
        guard let outputFace = resultModel.faces[outputID],
              let inputFace = inputModel.faces[inputID],
              let outputSurface = resultModel.geometry.surfaces[outputFace.surfaceID],
              let inputSurface = inputModel.geometry.surfaces[inputFace.surfaceID] else {
            return false
        }
        if let outputCylinder = cylinder(outputSurface),
           let inputCylinder = cylinder(inputSurface) {
            return try cylindricalFacesMatch(
                outputFace: outputFace,
                outputSurface: outputSurface,
                outputCylinder: outputCylinder,
                outputModel: resultModel,
                inputFaceID: inputID,
                inputCylinder: inputCylinder,
                inputModel: inputModel,
                tolerance: tolerance
            )
        }
        if let outputCone = cone(outputSurface),
           let inputCone = cone(inputSurface) {
            return try conicalFacesMatch(
                outputFace: outputFace,
                outputSurface: outputSurface,
                outputCone: outputCone,
                outputModel: resultModel,
                inputFaceID: inputID,
                inputCone: inputCone,
                inputModel: inputModel,
                tolerance: tolerance
            )
        }
        guard let outputPlane = plane(outputSurface),
              let inputPlane = plane(inputSurface) else {
            return false
        }
        let outputNormal = try outputPlane.normal.normalized(tolerance: tolerance.distance)
        let inputNormal = try inputPlane.normal.normalized(tolerance: tolerance.distance)
        guard abs(abs(outputNormal.dot(inputNormal)) - 1.0) <= tolerance.angle,
              abs((outputPlane.origin - inputPlane.origin).dot(inputNormal)) <= tolerance.distance,
              let outputBounds = try faceBounds(outputFace, model: resultModel),
              let inputBounds = try faceBounds(inputFace, model: inputModel) else {
            return false
        }
        guard outputBounds.intersects(inputBounds, tolerance: tolerance.distance),
              let outputParameters = try faceParameterBounds(
                  outputFace,
                  model: resultModel,
                  projectionSurface: outputSurface,
                  tolerance: tolerance
              ),
              let inputParameters = try faceParameterBounds(
                  inputFace,
                  model: inputModel,
                  projectionSurface: outputSurface,
                  tolerance: tolerance
              ) else {
            return false
        }
        let overlapU = min(outputParameters.maximumU, inputParameters.maximumU)
            - max(outputParameters.minimumU, inputParameters.minimumU)
        let overlapV = min(outputParameters.maximumV, inputParameters.maximumV)
            - max(outputParameters.minimumV, inputParameters.minimumV)
        return overlapU > tolerance.distance && overlapV > tolerance.distance
    }

    private func cylindricalFacesMatch(
        outputFace: Face,
        outputSurface: Surface3D,
        outputCylinder: (origin: Point3D, axis: Vector3D, radius: Double),
        outputModel: BRepModel,
        inputFaceID: FaceID,
        inputCylinder: (origin: Point3D, axis: Vector3D, radius: Double),
        inputModel: BRepModel,
        tolerance: ModelingTolerance
    ) throws -> Bool {
        let outputAxis = try outputCylinder.axis.normalized(tolerance: tolerance.distance)
        let inputAxis = try inputCylinder.axis.normalized(tolerance: tolerance.distance)
        let originOffset = outputCylinder.origin - inputCylinder.origin
        let radialOffset = originOffset - inputAxis * originOffset.dot(inputAxis)
        guard abs(abs(outputAxis.dot(inputAxis)) - 1.0) <= tolerance.angle,
              abs(outputCylinder.radius - inputCylinder.radius) <= tolerance.distance,
              radialOffset.length <= tolerance.distance,
              let sample = try faceInteriorPoint(
                  outputFace,
                  surface: outputSurface,
                  model: outputModel,
                  tolerance: tolerance
              ) else {
            return false
        }
        return try DefaultFacePointContainmentTester().contains(
            sample,
            on: inputFaceID,
            in: inputModel,
            tolerance: tolerance
        )
    }

    private func conicalFacesMatch(
        outputFace: Face,
        outputSurface: Surface3D,
        outputCone: (apex: Point3D, axis: Vector3D, halfAngle: Double),
        outputModel: BRepModel,
        inputFaceID: FaceID,
        inputCone: (apex: Point3D, axis: Vector3D, halfAngle: Double),
        inputModel: BRepModel,
        tolerance: ModelingTolerance
    ) throws -> Bool {
        let outputAxis = try outputCone.axis.normalized(tolerance: tolerance.distance)
        let inputAxis = try inputCone.axis.normalized(tolerance: tolerance.distance)
        guard abs(abs(outputAxis.dot(inputAxis)) - 1.0) <= tolerance.angle,
              abs(outputCone.halfAngle - inputCone.halfAngle) <= tolerance.angle,
              (outputCone.apex - inputCone.apex).length <= tolerance.distance,
              let sample = try faceInteriorPoint(
                  outputFace,
                  surface: outputSurface,
                  model: outputModel,
                  tolerance: tolerance
              ) else {
            return false
        }
        return try DefaultFacePointContainmentTester().contains(
            sample,
            on: inputFaceID,
            in: inputModel,
            tolerance: tolerance
        )
    }

    private func faceInteriorPoint(
        _ face: Face,
        surface: Surface3D,
        model: BRepModel,
        tolerance: ModelingTolerance
    ) throws -> Point3D? {
        guard let outerLoopID = face.loops.first(where: { loopID in
            model.loops[loopID]?.role == .outer
        }), let loop = model.loops[outerLoopID] else {
            return nil
        }
        var parameters: [SurfaceParameter] = []
        parameters.reserveCapacity(loop.coedges.count)
        for coedge in loop.coedges {
            guard let pcurve = coedge.surfaceParameterCurve else {
                return nil
            }
            parameters.append(try pcurve.parameter(
                atNormalizedFraction: 0.5,
                tolerance: tolerance
            ))
        }
        guard parameters.isEmpty == false else { return nil }
        let count = Double(parameters.count)
        let average = parameters.reduce((u: 0.0, v: 0.0)) { partial, parameter in
            (partial.u + parameter.u, partial.v + parameter.v)
        }
        return try surface.point(
            u: average.u / count,
            v: average.v / count,
            tolerance: tolerance
        )
    }

    private func edgesMatch(
        outputID: EdgeID,
        inputID: EdgeID,
        inputModel: BRepModel,
        resultModel: BRepModel,
        tolerance: ModelingTolerance
    ) throws -> Bool {
        guard let outputEdge = resultModel.edges[outputID],
              let inputEdge = inputModel.edges[inputID],
              let outputStart = resultModel.vertices[outputEdge.startVertexID]?.point,
              let outputEnd = resultModel.vertices[outputEdge.endVertexID]?.point,
              let inputStart = inputModel.vertices[inputEdge.startVertexID]?.point,
              let inputEnd = inputModel.vertices[inputEdge.endVertexID]?.point else {
            return false
        }
        let inputDirection = try (inputEnd - inputStart).normalized(tolerance: tolerance.distance)
        let outputDirection = try (outputEnd - outputStart).normalized(tolerance: tolerance.distance)
        guard abs(abs(inputDirection.dot(outputDirection)) - 1.0) <= tolerance.angle,
              (outputStart - inputStart).cross(inputDirection).length <= tolerance.distance,
              (outputEnd - inputStart).cross(inputDirection).length <= tolerance.distance else {
            return false
        }
        let inputLength = (inputEnd - inputStart).length
        let outputLower = min(
            (outputStart - inputStart).dot(inputDirection),
            (outputEnd - inputStart).dot(inputDirection)
        )
        let outputUpper = max(
            (outputStart - inputStart).dot(inputDirection),
            (outputEnd - inputStart).dot(inputDirection)
        )
        return outputLower <= inputLength + tolerance.distance && outputUpper >= -tolerance.distance
    }

    private func faceBounds(_ face: Face, model: BRepModel) throws -> BoundingBox3D? {
        var points: [Point3D] = []
        for loopID in face.loops {
            points.append(contentsOf: try model.orderedPoints(for: loopID))
        }
        return points.isEmpty ? nil : try BoundingBox3D(points: points)
    }

    private func faceParameterBounds(
        _ face: Face,
        model: BRepModel,
        projectionSurface: Surface3D,
        tolerance: ModelingTolerance
    ) throws -> ParameterBounds? {
        var parameters: [SurfaceParameterProjection] = []
        for loopID in face.loops {
            parameters.append(contentsOf: try model.orderedPoints(for: loopID).map {
                try projectionSurface.parameterProjection(of: $0, tolerance: tolerance)
            })
        }
        guard let minimumU = parameters.map(\.u).min(),
              let maximumU = parameters.map(\.u).max(),
              let minimumV = parameters.map(\.v).min(),
              let maximumV = parameters.map(\.v).max() else {
            return nil
        }
        return ParameterBounds(
            minimumU: minimumU,
            maximumU: maximumU,
            minimumV: minimumV,
            maximumV: maximumV
        )
    }

    private func plane(_ surface: Surface3D) -> (origin: Point3D, normal: Vector3D)? {
        switch surface {
        case let .plane(plane):
            return (plane.origin, plane.normal)
        case let .analytic(.plane(origin, normal)):
            return (origin, normal)
        case .cylinder, .analytic, .bSpline:
            return nil
        }
    }

    private func cylinder(
        _ surface: Surface3D
    ) -> (origin: Point3D, axis: Vector3D, radius: Double)? {
        switch surface {
        case let .cylinder(cylinder):
            return (cylinder.origin, cylinder.axis, cylinder.radius)
        case let .analytic(.cylinder(origin, axis, radius)):
            return (origin, axis, radius)
        case .plane, .analytic, .bSpline:
            return nil
        }
    }

    private func cone(
        _ surface: Surface3D
    ) -> (apex: Point3D, axis: Vector3D, halfAngle: Double)? {
        guard case let .analytic(.cone(apex, axis, halfAngle)) = surface else {
            return nil
        }
        return (apex, axis, halfAngle)
    }

    private func belongs(
        _ reference: TopologyReference,
        toAny bodyIDs: Set<BodyID>,
        in model: BRepModel
    ) -> Bool {
        bodyIDs.contains { belongs(reference, to: $0, in: model) }
    }

    private func belongs(
        _ reference: TopologyReference,
        to bodyID: BodyID,
        in model: BRepModel
    ) -> Bool {
        guard let body = model.bodies[bodyID] else { return false }
        switch reference {
        case let .body(referenceBodyID):
            return referenceBodyID == bodyID
        case let .face(faceID):
            return body.shellIDs.contains { model.shells[$0]?.faceIDs.contains(faceID) == true }
        case let .edge(edgeID):
            return body.shellIDs.contains { shellID in
                model.shells[shellID]?.faceIDs.contains { faceID in
                    model.faces[faceID]?.loops.contains { loopID in
                        model.loops[loopID]?.coedges.contains { $0.edgeID == edgeID } == true
                    } == true
                } == true
            }
        case let .vertex(vertexID):
            return body.shellIDs.contains { shellID in
                model.shells[shellID]?.faceIDs.contains { faceID in
                    model.faces[faceID]?.loops.contains { loopID in
                        model.loops[loopID]?.coedges.contains { coedge in
                            guard let edge = model.edges[coedge.edgeID] else { return false }
                            return edge.startVertexID == vertexID || edge.endVertexID == vertexID
                        } == true
                    } == true
                } == true
            }
        }
    }

    private struct InputReference {
        let subshapeID: SubshapeID
        let reference: TopologyReference
    }

    private struct Draft {
        let output: SubshapeID
        let parents: [SubshapeID]
    }

    private struct ParameterBounds {
        let minimumU: Double
        let maximumU: Double
        let minimumV: Double
        let maximumV: Double
    }
}
