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
        tolerance: ModelingTolerance,
        retainedLineage: [SubshapeID: TopologyLineage] = [:],
        admission: GeometryConversionAdmission? = nil
    ) throws -> [SubshapeID: TopologyLineage] {
        try tolerance.validate()
        var result: [SubshapeID: TopologyLineage] = [:]
        // Issued sewing provenance is authoritative; geometry cannot replace it.
        for (output, entry) in retainedLineage {
            try visit(admission)
            guard output.featureID == featureID, outputSubshapes[output] != nil,
                  entry.output == output, output.isValid else {
                throw invalidLineage(featureID: featureID, output: output, tolerance: tolerance)
            }
            var previous: SubshapeID?
            for parent in entry.parents {
                try visit(admission)
                guard parent.isValid, parent != output,
                      previous.map({ $0 < parent }) ?? true else {
                    throw invalidLineage(featureID: featureID, output: output, tolerance: tolerance)
                }
                previous = parent
            }
            let validCount: Bool
            switch entry.relation {
            case .generated: validCount = entry.parents.isEmpty
            case .preserved, .split: validCount = entry.parents.count == 1
            case .merged: validCount = entry.parents.count > 1
            }
            guard validCount else {
                throw invalidLineage(featureID: featureID, output: output, tolerance: tolerance)
            }
            try reserve(1, of: (SubshapeID, TopologyLineage).self, admission: admission)
            result[output] = entry
        }
        var missingOutputs: [SubshapeID] = []
        for output in outputSubshapes.keys {
            try visit(admission)
            guard output.featureID == featureID else {
                throw invalidLineage(featureID: featureID, output: output, tolerance: tolerance)
            }
            if result[output] == nil {
                try reserve(1, of: SubshapeID.self, admission: admission)
                missingOutputs.append(output)
            }
        }
        guard !missingOutputs.isEmpty else { return result }
        try reserve(missingOutputs.count, of: SubshapeID.self, admission: admission)
        missingOutputs = try missingOutputs.sorted {
            try visit(admission)
            return $0 < $1
        }
        var inputReferences: [InputReference] = []
        for (id, reference) in inputSubshapes {
            try visit(admission)
            guard try belongs(reference, toAny: operandBodyIDs, in: inputModel,
                              admission: admission) else { continue }
            try reserve(1, of: InputReference.self, admission: admission)
            inputReferences.append(InputReference(subshapeID: id, reference: reference))
        }
        var drafts: [Draft] = []
        for output in missingOutputs {
            try visit(admission)
            guard let reference = outputSubshapes[output] else {
                throw invalidLineage(featureID: featureID, output: output, tolerance: tolerance)
            }
            var parents: [SubshapeID] = []
            // Only the unchanged-tool producer may issue preservation from a
            // retained reference. Equal IDs in arbitrary result/input models do
            // not prove that their reachable original geometry stayed unchanged.
            if parents.isEmpty {
                // FIXME(INCOMPLETE_IMPLEMENTATION): BooleanPipeline invokes this
                // compatibility branch only for generated outputs lacking issued
                // provenance. General original finite-face and partial-span
                // correspondence must share the selected admission before bounded
                // history can publish; legacy matching is not that producer.
                guard admission == nil else {
                    throw KernelError(phase: .topology, code: .unsupportedCapability,
                        featureID: featureID, subshapeID: output, tolerance: tolerance,
                        message: "Bounded Boolean history requires original generated-output correspondence.")
                }
                for candidate in inputReferences {
                    try visit(nil)
                    if try matches(output: reference, input: candidate.reference,
                        inputModel: inputModel, resultModel: resultModel, tolerance: tolerance) {
                        parents.append(candidate.subshapeID)
                    }
                }
            }
            try reserve(parents.count, of: SubshapeID.self, admission: admission)
            parents = try parents.sorted { try visit(admission); return $0 < $1 }
            try reserve(1, of: Draft.self, admission: admission)
            drafts.append(Draft(output: output, parents: parents))
        }
        var parentUseCount: [SubshapeID: Int] = [:]
        for entry in result.values {
            for parent in entry.parents {
                try visit(admission)
                try reserve(1, of: (SubshapeID, Int).self, admission: admission)
                let increment = parentUseCount[parent, default: 0].addingReportingOverflow(1)
                guard !increment.overflow else {
                    throw GeometryConversionError.resourceLimitExceeded("Boolean lineage parent-use count overflowed.")
                }
                parentUseCount[parent] = increment.partialValue
            }
        }
        for draft in drafts {
            for parent in draft.parents {
                try visit(admission)
                try reserve(1, of: (SubshapeID, Int).self, admission: admission)
                let increment = parentUseCount[parent, default: 0].addingReportingOverflow(1)
                guard !increment.overflow else {
                    throw GeometryConversionError.resourceLimitExceeded("Boolean lineage parent-use count overflowed.")
                }
                parentUseCount[parent] = increment.partialValue
            }
        }
        for draft in drafts {
            try visit(admission)
            let relation: TopologyLineageRelation
            if draft.parents.isEmpty { relation = .generated }
            else if draft.parents.count > 1 { relation = .merged }
            else if parentUseCount[draft.parents[0], default: 0] > 1 { relation = .split }
            else { relation = .preserved }
            // Canonicalization retains a new parent buffer at publication.
            try reserve(draft.parents.count, of: SubshapeID.self, admission: admission)
            try reserve(1, of: (SubshapeID, TopologyLineage).self, admission: admission)
            result[draft.output] = TopologyLineage(output: draft.output,
                parents: draft.parents, relation: relation)
        }
        return result
    }

    private func visit(_ admission: GeometryConversionAdmission?) throws {
        try CurrentTaskCancellationChecker().checkCancellation()
        try admission?.chargeWork()
    }

    // FIXME(INCOMPLETE_IMPLEMENTATION): The public lineage-only admission meters
    // requested typed entries before use. Dictionary growth, canonicalization
    // scratch and physical allocator retention still require actual lower storage
    // owners before this phase can claim a complete cumulative byte guarantee.
    private func reserve<T>(_ count: Int, of type: T.Type,
                            admission: GeometryConversionAdmission?) throws {
        let bytes = count.multipliedReportingOverflow(by: MemoryLayout<T>.stride)
        guard count >= 0, !bytes.overflow else {
            throw GeometryConversionError.resourceLimitExceeded("Boolean lineage storage request overflowed.")
        }
        try admission?.chargeStorage(bytes: bytes.partialValue)
    }

    private func invalidLineage(featureID: FeatureID, output: SubshapeID,
                                tolerance: ModelingTolerance) -> KernelError {
        KernelError(phase: .topology, code: .topologyFailure, featureID: featureID,
            subshapeID: output, tolerance: tolerance,
            message: "Boolean provenance is not structurally bound to its published output.")
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
        if let outputCylinder = try cylinder(
            outputSurface,
            tolerance: tolerance
        ), let inputCylinder = try cylinder(
            inputSurface,
            tolerance: tolerance
        ) {
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
        guard let outputPlane = try plane(
            outputSurface,
            tolerance: tolerance
        ), let inputPlane = try plane(
            inputSurface,
            tolerance: tolerance
        ) else {
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

    private func plane(
        _ surface: Surface3D,
        tolerance: ModelingTolerance
    ) throws -> (origin: Point3D, normal: Vector3D)? {
        guard let plane = try DefaultPlanarSurfaceResolver().exactPlane(
            for: surface,
            tolerance: tolerance
        ) else {
            return nil
        }
        return (plane.origin, plane.normal)
    }

    private func cylinder(
        _ surface: Surface3D,
        tolerance: ModelingTolerance
    ) throws -> (origin: Point3D, axis: Vector3D, radius: Double)? {
        switch surface {
        case let .cylinder(cylinder):
            return (cylinder.origin, cylinder.axis, cylinder.radius)
        case let .analytic(.cylinder(origin, axis, radius)):
            return (origin, axis, radius)
        case let .procedural(.offset(offset)):
            guard let equivalent = try offset.exactChartPreservingSurface(
                tolerance: tolerance
            ) else {
                return nil
            }
            return try cylinder(equivalent, tolerance: tolerance)
        case .procedural(.ruled), .procedural(.rollingBall), .procedural(.originalImage),
             .procedural(.originalRevolution), .procedural(.originalAffineWord),
             .procedural(.originalAngularTransport), .procedural(.originalCoons),
             .procedural(.originalBoundaryCorrected), .procedural(.originalPlaneDerivative),
             .procedural(.originalDrafted):
            return nil
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

    private func belongs(_ reference: TopologyReference, toAny bodyIDs: [BodyID],
                         in model: BRepModel, admission: GeometryConversionAdmission?) throws -> Bool {
        for bodyID in bodyIDs {
            try visit(admission)
            guard let body = model.bodies[bodyID] else { continue }
            if case let .body(id) = reference { if id == bodyID { return true }; continue }
            for shellID in body.shellIDs {
                try visit(admission)
                guard let shell = model.shells[shellID] else { continue }
                for faceID in shell.faceIDs {
                    try visit(admission)
                    if case let .face(id) = reference { if id == faceID { return true }; continue }
                    guard let face = model.faces[faceID] else { continue }
                    for loopID in face.loops {
                        try visit(admission)
                        guard let loop = model.loops[loopID] else { continue }
                        for coedge in loop.coedges {
                            try visit(admission)
                            if case let .edge(id) = reference, id == coedge.edgeID { return true }
                            if case let .vertex(id) = reference,
                               let edge = model.edges[coedge.edgeID],
                               edge.startVertexID == id || edge.endVertexID == id { return true }
                        }
                    }
                }
            }
        }
        return false
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
