import CADCore
import CADIR
import CADModeling
import CADTopology
import Testing
@testable import CADKernel

@Suite("Face Delete Feature")
struct FaceDeleteFeatureTests {
    @Test(.timeLimit(.minutes(1)))
    func removesOneFaceAsDeterministicExactSheetWithPreservedLineage() throws {
        var document = makeRectangleExtrudeDocument(documentUnits: .meters)
        let sourceFeatureID = try #require(document.designGraph.order.last)
        let source = try DocumentEvaluator(tolerance: .standard, artifactPolicy: .deferred).evaluate(document)
        let removedFaceID = SubshapeID(
            featureID: sourceFeatureID,
            role: GeneratedSubshapeRole.startFace.rawValue,
            ordinal: 0
        )
        let deleteFeatureID = FeatureID()
        try appendFaceDelete(
            featureID: deleteFeatureID,
            sourceFeatureID: sourceFeatureID,
            faces: [try source.stableSubshapeReference(for: removedFaceID)],
            to: &document
        )

        let evaluator = DocumentEvaluator(tolerance: .standard, artifactPolicy: .deferred)
        let evaluated = try evaluator.evaluate(document)
        let repeated = try evaluator.evaluate(document)
        let body = try #require(evaluated.brep.bodies.values.first)
        let outputLineage = evaluated.lineage.values.filter {
            $0.output.featureID == deleteFeatureID
        }

        #expect(body.kind == .sheet)
        #expect(body.shellIDs.count == 1)
        #expect(evaluated.brep.faces.count == 5)
        #expect(evaluated.brep.edges.count == 12)
        #expect(evaluated.brep.vertices.count == 8)
        #expect(evaluated.subshapes[removedFaceID] == nil)
        #expect(outputLineage.count == 26)
        #expect(outputLineage.allSatisfy {
            $0.relation == .preserved && $0.parents.count == 1
        })
        #expect(evaluated.brep.loops.values.flatMap(\.coedges).allSatisfy {
            $0.surfaceParameterCurve != nil
        })
        #expect(evaluated.brep == repeated.brep)
        #expect(evaluated.subshapes == repeated.subshapes)
        #expect(evaluated.lineage == repeated.lineage)
        try evaluated.brep.validate(level: .exact, tolerance: .standard)
    }

    @Test(.timeLimit(.minutes(1)))
    func partitionsDisconnectedRemainingFacesIntoDeterministicSheetShells() throws {
        var document = makeRectangleExtrudeDocument(documentUnits: .meters)
        let sourceFeatureID = try #require(document.designGraph.order.last)
        let source = try DocumentEvaluator(tolerance: .standard, artifactPolicy: .deferred).evaluate(document)
        let sideFaces = try (0..<4).map { ordinal in
            try source.stableSubshapeReference(for: SubshapeID(
                featureID: sourceFeatureID,
                role: GeneratedSubshapeRole.sideFace.rawValue,
                ordinal: ordinal
            ))
        }
        let deleteFeatureID = FeatureID()
        try appendFaceDelete(
            featureID: deleteFeatureID,
            sourceFeatureID: sourceFeatureID,
            faces: sideFaces,
            to: &document
        )

        let evaluator = DocumentEvaluator(tolerance: .standard, artifactPolicy: .deferred)
        let evaluated = try evaluator.evaluate(document)
        let repeated = try evaluator.evaluate(document)
        let body = try #require(evaluated.brep.bodies.values.first)
        let shells = try body.shellIDs.map { shellID in
            try #require(evaluated.brep.shells[shellID])
        }
        let outputLineage = evaluated.lineage.values.filter {
            $0.output.featureID == deleteFeatureID
        }

        #expect(body.kind == .sheet)
        #expect(shells.count == 2)
        #expect(shells.allSatisfy { $0.faceIDs.count == 1 })
        #expect(evaluated.brep.faces.count == 2)
        #expect(evaluated.brep.edges.count == 8)
        #expect(evaluated.brep.vertices.count == 8)
        #expect(outputLineage.count == 19)
        #expect(outputLineage.allSatisfy {
            $0.relation == .preserved && $0.parents.count == 1
        })
        #expect(evaluated.brep == repeated.brep)
        #expect(evaluated.subshapes == repeated.subshapes)
        #expect(evaluated.lineage == repeated.lineage)
        try evaluated.brep.validate(level: .exact, tolerance: .standard)
    }

    @Test(.timeLimit(.minutes(1)))
    func preservesUnrelatedBodyIdentitiesWhenEvaluatedAgainstAFullModel() throws {
        let firstDocument = makeRectangleExtrudeDocument(documentUnits: .meters)
        let secondDocument = makeRectangleExtrudeDocument(
            width: 30.0,
            height: 15.0,
            depth: 5.0,
            documentUnits: .meters
        )
        let evaluator = DocumentEvaluator(tolerance: .standard, artifactPolicy: .deferred)
        let first = try evaluator.evaluate(firstDocument)
        let second = try evaluator.evaluate(secondDocument)
        let firstFeatureID = try #require(firstDocument.designGraph.order.last)
        let removedFaceID = SubshapeID(
            featureID: firstFeatureID,
            role: GeneratedSubshapeRole.startFace.rawValue,
            ordinal: 0
        )
        let deleteFeatureID = FeatureID()
        let feature = FeatureNode(
            id: deleteFeatureID,
            operation: .faceDelete(FaceDeleteFeature(
                target: FaceDeleteTargetReference(featureID: firstFeatureID),
                faces: [try first.stableSubshapeReference(for: removedFaceID)]
            )),
            inputs: [FeatureInput(featureID: firstFeatureID, role: .target)],
            outputs: [FeatureOutput(role: .sheet)]
        )
        let combined = try combinedContext(first, second)

        let result = try FaceDeleteFeatureEvaluator().evaluate(
            feature: feature,
            context: combined
        )
        let firstSubshapeIDs = Set(first.subshapes.entries.keys)
        let secondSubshapeIDs = Set(second.subshapes.entries.keys)

        #expect(result.removedSubshapeIDs == firstSubshapeIDs)
        #expect(result.removedSubshapeIDs.isDisjoint(with: secondSubshapeIDs))
        for bodyID in second.brep.bodies.keys {
            #expect(result.brep.bodies[bodyID] == second.brep.bodies[bodyID])
        }
        try result.brep.validate(level: .exact, tolerance: .standard)
    }

    @Test(.timeLimit(.minutes(1)))
    func rejectsDeletingEveryFaceOfASourceShell() throws {
        var document = makeRectangleExtrudeDocument(documentUnits: .meters)
        let sourceFeatureID = try #require(document.designGraph.order.last)
        let source = try DocumentEvaluator(
            tolerance: .standard,
            artifactPolicy: .deferred
        ).evaluate(document)
        let faceSubshapeIDs = source.subshapes.entries.compactMap {
            subshapeID,
            reference -> SubshapeID? in
            guard subshapeID.featureID == sourceFeatureID,
                  case .face = reference else {
                return nil
            }
            return subshapeID
        }.sorted()
        let faceReferences = try faceSubshapeIDs.map {
            try source.stableSubshapeReference(for: $0)
        }
        let deleteFeatureID = FeatureID()
        try appendFaceDelete(
            featureID: deleteFeatureID,
            sourceFeatureID: sourceFeatureID,
            faces: faceReferences,
            to: &document
        )

        do {
            _ = try DocumentEvaluator(
                tolerance: .standard,
                artifactPolicy: .deferred
            ).evaluate(document)
            Issue.record("Deleting every face of a shell must not succeed.")
        } catch let error as KernelError {
            #expect(error.code == .unsupportedCapability)
            #expect(error.featureID == deleteFeatureID)
            #expect(error.tolerance == .standard)
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func rejectsFaceOwnedByAnotherTargetBody() throws {
        let firstDocument = makeRectangleExtrudeDocument(documentUnits: .meters)
        let secondDocument = makeRectangleExtrudeDocument(
            width: 30.0,
            height: 15.0,
            depth: 5.0,
            documentUnits: .meters
        )
        let evaluator = DocumentEvaluator(
            tolerance: .standard,
            artifactPolicy: .deferred
        )
        let first = try evaluator.evaluate(firstDocument)
        let second = try evaluator.evaluate(secondDocument)
        let firstFeatureID = try #require(firstDocument.designGraph.order.last)
        let secondFeatureID = try #require(secondDocument.designGraph.order.last)
        let secondFaceID = SubshapeID(
            featureID: secondFeatureID,
            role: GeneratedSubshapeRole.startFace.rawValue,
            ordinal: 0
        )
        let deleteFeatureID = FeatureID()

        do {
            _ = try FaceDeleteFeatureEvaluator().evaluate(
                feature: FeatureNode(
                    id: deleteFeatureID,
                    operation: .faceDelete(FaceDeleteFeature(
                        target: FaceDeleteTargetReference(
                            featureID: firstFeatureID
                        ),
                        faces: [try second.stableSubshapeReference(
                            for: secondFaceID
                        )]
                    )),
                    inputs: [FeatureInput(featureID: firstFeatureID, role: .target)],
                    outputs: [FeatureOutput(role: .sheet)]
                ),
                context: try combinedContext(first, second)
            )
            Issue.record("A face from another target body must not be deleted.")
        } catch let error as KernelError {
            #expect(error.code == .missingReference)
            #expect(error.featureID == deleteFeatureID)
            #expect(error.tolerance == .standard)
        }
    }

    private func appendFaceDelete(
        featureID: FeatureID,
        sourceFeatureID: FeatureID,
        faces: [StableSubshapeReference],
        to document: inout CADDocument
    ) throws {
        let operation = FeatureOperation.faceDelete(FaceDeleteFeature(
            target: FaceDeleteTargetReference(featureID: sourceFeatureID),
            faces: faces
        ))
        let node = try FeatureNodeFactory.make(
            operation: operation,
            id: featureID,
            in: document,
            tolerance: .standard
        )
        document.designGraph.nodes[featureID] = node
        document.designGraph.order.append(featureID)
        document.designGraph.dependencies.append(DependencyEdge(
            source: sourceFeatureID,
            target: featureID
        ))
        document.designGraph.revision = document.designGraph.revision.advanced()
    }

    private func combinedContext(
        _ first: EvaluatedDocument,
        _ second: EvaluatedDocument
    ) throws -> EvaluationContext {
        var model = first.brep
        for (id, curve) in second.brep.geometry.curves {
            model.geometry.curves[id] = curve
        }
        for (id, surface) in second.brep.geometry.surfaces {
            model.geometry.surfaces[id] = surface
        }
        for (id, body) in second.brep.bodies {
            model.bodies[id] = body
        }
        for (id, shell) in second.brep.shells {
            model.shells[id] = shell
        }
        for (id, face) in second.brep.faces {
            model.faces[id] = face
        }
        for (id, loop) in second.brep.loops {
            model.loops[id] = loop
        }
        for (id, edge) in second.brep.edges {
            model.edges[id] = edge
        }
        for (id, vertex) in second.brep.vertices {
            model.vertices[id] = vertex
        }
        try model.validate(level: .exact, tolerance: .standard)

        var subshapes = first.subshapes.entries
        for (subshapeID, reference) in second.subshapes.entries {
            subshapes[subshapeID] = reference
        }
        var lineage = first.lineage
        for (subshapeID, entry) in second.lineage {
            lineage[subshapeID] = entry
        }
        return EvaluationContext(
            parameters: first.parameters,
            brep: model,
            profiles: [:],
            curves: [:],
            subshapes: SubshapeIndex(subshapes),
            lineage: lineage,
            tolerance: .standard
        )
    }
}
