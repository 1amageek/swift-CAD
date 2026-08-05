import Testing
import CADCore
import CADIR
import CADModeling
import CADTopology
@testable import CADKernel

@Suite("Face offset feature")
struct FaceOffsetFeatureTests {
    @Test(.timeLimit(.minutes(1)))
    func translatesImportedAnalyticPlaneRepresentation() throws {
        let document = makeRectangleExtrudeDocument(documentUnits: .meters)
        let sourceFeatureID = try #require(document.designGraph.order.last)
        let source = try DocumentEvaluator(tolerance: .standard, artifactPolicy: .deferred).evaluate(document)
        let faceSubshapeID = SubshapeID(
            featureID: sourceFeatureID,
            role: GeneratedSubshapeRole.endFace.rawValue,
            ordinal: 0
        )
        let resolved = try StableSubshapeResolver().topologyReference(
            for: source.stableSubshapeReference(for: faceSubshapeID),
            model: source.brep,
            subshapes: source.subshapes,
            lineage: source.lineage,
            tolerance: .standard
        )
        guard case let .face(faceID) = resolved,
              let face = source.brep.faces[faceID],
              case let .plane(plane) = source.brep.geometry.surfaces[face.surfaceID] else {
            Issue.record("Extruded end face must provide the canonical planar fixture.")
            return
        }
        let bodyID = try #require(source.brep.bodies.keys.first)
        let loopID = try #require(face.loops.first)
        let vertexIDs = try source.brep.orderedVertexIDs(for: loopID)
        let originalPoints = try Dictionary(uniqueKeysWithValues: vertexIDs.map { vertexID in
            (vertexID, try #require(source.brep.vertices[vertexID]).point)
        })
        var importedModel = source.brep
        importedModel.geometry.surfaces[face.surfaceID] = .analytic(.plane(
            origin: plane.origin,
            normal: plane.normal
        ))
        let displacement = Vector3D(x: 0.001, y: 0.002, z: 0.003)
        let translator = PlanarFaceTranslator()

        let outwardNormal = try translator.outwardNormal(
            faceID: faceID,
            bodyID: bodyID,
            featureID: FeatureID(),
            model: importedModel,
            tolerance: .standard
        )
        try translator.translate(
            faceID: faceID,
            bodyID: bodyID,
            displacement: displacement,
            featureID: FeatureID(),
            model: &importedModel,
            tolerance: .standard
        )

        #expect(outwardNormal.dot(.unitZ) > 1.0 - 1.0e-12)
        for vertexID in vertexIDs {
            let original = try #require(originalPoints[vertexID])
            let translated = try #require(importedModel.vertices[vertexID]).point
            #expect((translated - (original + displacement)).length <= 1.0e-12)
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func offsetsPlanarFaceAlongItsOutwardNormalWithExactLineage() throws {
        let sourceDocument = makeRectangleExtrudeDocument(documentUnits: .meters)
        let sourceFeatureID = try #require(sourceDocument.designGraph.order.last)
        let source = try DocumentEvaluator(tolerance: .standard, artifactPolicy: .deferred).evaluate(sourceDocument)
        let faceSubshapeID = SubshapeID(
            featureID: sourceFeatureID,
            role: GeneratedSubshapeRole.endFace.rawValue,
            ordinal: 0
        )
        let faceReference = try source.stableSubshapeReference(for: faceSubshapeID)

        for distance in [0.005, -0.005] {
            var document = sourceDocument
            let offsetID = FeatureID()
            let operation = FeatureOperation.faceOffset(FaceOffsetFeature(
                target: FaceOffsetTargetReference(featureID: sourceFeatureID),
                face: faceReference,
                distance: .constant(.length(distance, unit: .meter))
            ))
            let node = try FeatureNodeFactory.make(operation: operation, id: offsetID, in: document, tolerance: .standard)
            document.designGraph.nodes[offsetID] = node
            document.designGraph.order.append(offsetID)
            document.designGraph.dependencies.append(DependencyEdge(source: sourceFeatureID, target: offsetID))
            document.designGraph.revision = document.designGraph.revision.advanced()

            let evaluator = DocumentEvaluator(tolerance: .standard, artifactPolicy: .deferred)
            let evaluated = try evaluator.evaluate(document)
            let repeated = try evaluator.evaluate(document)
            let expectedDepth = 0.010 + distance
            try evaluated.brep.validate(level: .volumetric, tolerance: .standard)
            #expect(evaluated.brep.faces.count == 6)
            #expect(evaluated.brep.edges.count == 12)
            #expect(evaluated.brep.vertices.count == 8)
            #expect(abs(try evaluated.brep.volume(tolerance: .standard) - 0.040 * 0.020 * expectedDepth) <= 1.0e-12)
            #expect(evaluated.brep == repeated.brep)
            #expect(evaluated.subshapes == repeated.subshapes)
            #expect(evaluated.lineage == repeated.lineage)
            #expect(evaluated.brep.loops.values.allSatisfy { loop in
                loop.coedges.allSatisfy { $0.surfaceParameterCurve != nil }
            })
            let offsetLineage = evaluated.lineage.values.filter { $0.output.featureID == offsetID }
            #expect(offsetLineage.count == 27)
            #expect(offsetLineage.allSatisfy { $0.relation == .preserved && $0.parents.count == 1 })
            let resolved = try StableSubshapeResolver().topologyReference(
                for: faceReference,
                model: evaluated.brep,
                subshapes: evaluated.subshapes,
                lineage: evaluated.lineage,
                tolerance: .standard
            )
            guard case let .face(faceID) = resolved,
                  let face = evaluated.brep.faces[faceID],
                  case let .plane(plane) = evaluated.brep.geometry.surfaces[face.surfaceID] else {
                Issue.record("Offset stable face must resolve to its exact planar descendant.")
                return
            }
            #expect(abs(plane.origin.z - expectedDepth) <= 1.0e-12)
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func scopesReplacementAndLineageToTheTargetBody() throws {
        let targetDocument = makeRectangleExtrudeDocument(documentUnits: .meters)
        let unrelatedDocument = makeRectangleExtrudeDocument(documentUnits: .meters)
        let targetFeatureID = try #require(targetDocument.designGraph.order.last)
        let target = try DocumentEvaluator(tolerance: .standard, artifactPolicy: .deferred).evaluate(targetDocument)
        let unrelated = try DocumentEvaluator(tolerance: .standard, artifactPolicy: .deferred).evaluate(unrelatedDocument)
        let faceSubshapeID = SubshapeID(
            featureID: targetFeatureID,
            role: GeneratedSubshapeRole.endFace.rawValue,
            ordinal: 0
        )
        let fixture = try EvaluationFixtureCombiner.combine([
            (target.brep, target.subshapes, target.lineage),
            (unrelated.brep, unrelated.subshapes, unrelated.lineage),
        ])
        let offsetID = FeatureID()
        let result = try FaceOffsetFeatureEvaluator().evaluate(
            feature: FeatureNode(
                id: offsetID,
                operation: .faceOffset(FaceOffsetFeature(
                    target: FaceOffsetTargetReference(featureID: targetFeatureID),
                    face: try target.stableSubshapeReference(for: faceSubshapeID),
                    distance: .constant(.length(0.005, unit: .meter))
                )),
                inputs: [FeatureInput(featureID: targetFeatureID, role: .target)],
                outputs: [FeatureOutput(role: .body)]
            ),
            context: context(for: fixture)
        )
        let targetSubshapeIDs = Set(target.subshapes.entries.keys)
        let unrelatedSubshapeIDs = Set(unrelated.subshapes.entries.keys)
        let outputLineage = result.lineage.values.filter {
            $0.output.featureID == offsetID
        }

        #expect(result.removedSubshapeIDs == targetSubshapeIDs)
        #expect(result.removedSubshapeIDs.isDisjoint(with: unrelatedSubshapeIDs))
        #expect(outputLineage.isEmpty == false)
        #expect(outputLineage.allSatisfy {
            Set($0.parents).isSubset(of: targetSubshapeIDs)
        })
        for bodyID in unrelated.brep.bodies.keys {
            #expect(result.brep.bodies[bodyID] == unrelated.brep.bodies[bodyID])
        }
        try result.brep.validate(level: .volumetric, tolerance: .standard)
    }

    @Test(.timeLimit(.minutes(1)))
    func rejectsFaceOwnedByAnotherTargetBody() throws {
        let targetDocument = makeRectangleExtrudeDocument(documentUnits: .meters)
        let foreignDocument = makeRectangleExtrudeDocument(documentUnits: .meters)
        let targetFeatureID = try #require(targetDocument.designGraph.order.last)
        let foreignFeatureID = try #require(foreignDocument.designGraph.order.last)
        let target = try DocumentEvaluator(tolerance: .standard, artifactPolicy: .deferred).evaluate(targetDocument)
        let foreign = try DocumentEvaluator(tolerance: .standard, artifactPolicy: .deferred).evaluate(foreignDocument)
        let foreignFaceSubshapeID = SubshapeID(
            featureID: foreignFeatureID,
            role: GeneratedSubshapeRole.endFace.rawValue,
            ordinal: 0
        )
        let foreignFace = try foreign.stableSubshapeReference(for: foreignFaceSubshapeID)
        let fixture = try EvaluationFixtureCombiner.combine([
            (target.brep, target.subshapes, target.lineage),
            (foreign.brep, foreign.subshapes, foreign.lineage),
        ])
        let offsetID = FeatureID()

        do {
            _ = try FaceOffsetFeatureEvaluator().evaluate(
                feature: FeatureNode(
                    id: offsetID,
                    operation: .faceOffset(FaceOffsetFeature(
                        target: FaceOffsetTargetReference(featureID: targetFeatureID),
                        face: foreignFace,
                        distance: .constant(.length(0.005, unit: .meter))
                    )),
                    inputs: [FeatureInput(featureID: targetFeatureID, role: .target)],
                    outputs: [FeatureOutput(role: .body)]
                ),
                context: context(for: fixture)
            )
            Issue.record("A face owned by another target body must be rejected.")
        } catch let error as KernelError {
            #expect(error.code == .missingReference)
            #expect(error.featureID == offsetID)
            #expect(error.subshapeID == foreignFace.subshapeID)
            #expect(error.tolerance == .standard)
        } catch {
            Issue.record("Expected a typed KernelError, got \(error).")
        }
    }

    private func context(
        for fixture: (
            brep: BRepModel,
            subshapes: SubshapeIndex,
            lineage: [SubshapeID: TopologyLineage]
        )
    ) -> EvaluationContext {
        EvaluationContext(
            parameters: ResolvedParameterTable(),
            brep: fixture.brep,
            profiles: [:],
            subshapes: fixture.subshapes,
            lineage: fixture.lineage,
            tolerance: .standard
        )
    }
}
