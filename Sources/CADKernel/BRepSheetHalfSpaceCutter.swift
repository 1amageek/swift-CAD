import CADCore
import CADGeometry
import CADIR
import CADModeling
import CADTopology

/// Retains exact sheet regions inside the enclosing half-space tool, without adding its faces.
struct BRepSheetHalfSpaceCutter {
    let sewer: any BRepSewing

    func cut(
        bodyID: BodyID, toolBodyID: BodyID, planeOrigin: Point3D, planeNormal: Vector3D,
        featureID: FeatureID, model: BRepModel, context: EvaluationContext
    ) throws -> EvaluationResult {
        let tolerance = context.tolerance
        let pipeline = BooleanPipeline(evaluator: ExactBRepBooleanEvaluator())
        let intersections = try pipeline.completeIntersectionGraph(
            targetBodyIDs: [bodyID], toolBodyID: toolBodyID, operation: .intersect,
            model: model, tolerance: tolerance)
        let splits = try pipeline.uvSplitGraph(intersectionGraph: intersections, model: model, tolerance: tolerance)
        guard let body = model.bodies[bodyID] else { throw TopologyError.missingReference("Sheet cut body is missing.") }
        var boundaries: [FaceID: [BooleanFaceArrangementBoundary]] = [:]
        for split in splits.splits {
            guard let face = model.faces[split.facePair.targetFaceID],
                  let surface = model.geometry.surfaces[face.surfaceID] else {
                throw TopologyError.missingReference("Sheet cut face is missing.")
            }
            for component in split.components {
                let reference = BooleanFaceSplitComponentReference(facePair: split.facePair, componentID: component.id)
                let edges = try BooleanFaceArrangementBoundary.edges(
                    reference: reference, geometry: component.geometry, faceID: face.id,
                    surfaceSide: .first, parentSubshapeIDs: context.subshapeIDs(for: .face(face.id)), tolerance: tolerance)
                for (ordinal, edge) in edges.enumerated() {
                    let parameter = edge.startParameter + (edge.endParameter - edge.startParameter) * 0.5
                    let uv = try edge.surfaceParameterCurve.parameter(atNormalizedFraction: 0.5, tolerance: tolerance)
                    let normal = try surface.normal(u: uv.u, v: uv.v, tolerance: tolerance)
                    let tangent = try edge.curve.differentialGeometry(at: parameter, tolerance: tolerance).tangent
                        * (edge.endParameter >= edge.startParameter ? 1.0 : -1.0)
                    // The arrangement's left side is in geometric surface orientation, independent
                    // of the source face's outward orientation.
                    let slope = normal.cross(tangent).dot(planeNormal)
                    guard abs(slope) > tolerance.angle else {
                        throw KernelError(phase: .classification, code: .classificationFailure,
                            featureID: featureID, tolerance: tolerance,
                            message: "Sheet cut intersection has no resolved transverse side.")
                    }
                    boundaries[face.id, default: []].append(BooleanFaceArrangementBoundary(
                        reference: reference, segmentOrdinal: ordinal, faceID: face.id, edge: edge,
                        forwardLeftAction: slope < 0 ? .keep : .discard,
                        forwardRightAction: slope < 0 ? .discard : .keep))
                }
            }
        }
        var patches: [BRepSewingFacePatch] = []
        for shellID in body.shellIDs {
            guard let shell = model.shells[shellID] else { throw TopologyError.missingReference("Sheet cut shell is missing.") }
            for faceID in shell.faceIDs {
                if let edges = boundaries[faceID], !edges.isEmpty {
                    patches += try BooleanOpenFaceArrangementBuilder().build(
                        faceID: faceID, boundaries: edges, model: model,
                        sourceSubshapes: context.subshapes.entries, tolerance: tolerance).patches
                } else {
                    // The complete intersection graph contains no transverse cut of this face.
                    // Its connected interior consequently lies on one side or in the plane.
                    let point = try BRepFaceInteriorPointSampler().point(on: faceID, in: model, tolerance: tolerance)
                    if (point - planeOrigin).dot(planeNormal) <= tolerance.distance {
                        patches.append(try SourceBRepFacePatchBuilder().build(
                            faceID: faceID, stableID: "sheet-cut:face:\(faceID)", from: model,
                            sourceSubshapes: context.subshapes.entries, tolerance: tolerance).patch)
                    }
                }
            }
        }
        guard !patches.isEmpty else {
            throw KernelError(phase: .evaluation, code: .invalidInput, featureID: featureID,
                tolerance: tolerance, message: "The plane cut keeps no sheet material.")
        }
        let shells = try BRepSewingPatchShellPartitioner().shells(
            patches: patches, stablePrefix: "sheet-cut:shell", tolerance: tolerance)
        let result = try sewer.sew(BRepSewingRequest(featureID: featureID, bodyKind: .sheet,
            shells: shells, bodyParentSubshapeIDs: context.subshapeIDs(for: .body(bodyID))), tolerance: tolerance)
        let replaced = try BRepBodyModelReplacer().replacing(bodyID: bodyID,
            with: result.bodyID, from: result.brep, in: context.brep)
        try replaced.validate(level: .exact, tolerance: tolerance)
        return EvaluationResult(brep: replaced, subshapes: result.subshapes,
            removedSubshapeIDs: try BodyTopologyScope(bodyID: bodyID, model: context.brep).subshapeIDs(in: context.subshapes),
            lineage: result.lineage)
    }
}
