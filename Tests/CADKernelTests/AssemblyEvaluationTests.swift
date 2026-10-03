import Foundation
import Testing
import CADCore
import CADGeometry
import CADIR
import CADTopology
@testable import CADKernel

@Suite("Assembly local and world evaluation")
struct AssemblyEvaluationTests {
    private func fixture() throws -> CADDocument {
        let id = FeatureID()
        let feature = FeatureNode(id: id, operation: .primitive(PrimitiveFeature(definition: .box(
            BoxPrimitive(width: .constant(.length(1, unit: .meter)), depth: .constant(.length(2, unit: .meter)),
                         height: .constant(.length(3, unit: .meter)))))), outputs: [FeatureOutput(role: .body)])
        let products = [AssemblyProduct(name: "part"), AssemblyProduct(name: "nested")]
        let formations = products.map { AssemblyProductFormation(productID: $0.id) }
        let part = AssemblyDefinition(formationID: formations[0].id, features: [id])
        let rotated = try RigidTransform3D(basisX: .unitY, basisY: -.unitX, basisZ: .unitZ,
            translation: Vector3D(x: 5, y: 0, z: 0), tolerance: .standard)
        let sub = AssemblyDefinition(formationID: formations[1].id, children: [AssemblyOccurrence(definitionID: part.id, placement: rotated)])
        return CADDocument(units: .meters, designGraph: DesignGraph(nodes: [id: feature], order: [id]),
            assembly: DocumentAssembly(products: products, formations: formations, definitions: [part, sub], roots: [AssemblyOccurrence(definitionID: sub.id),
                AssemblyOccurrence(definitionID: sub.id, placement: .translated(by: Vector3D(x: 0, y: 10, z: 0)))]))
    }
    @Test(.timeLimit(.minutes(1)))
    func nestedSharedPartMaterializesCoordinatesAndExactCorrespondence() throws {
        let document = try fixture()
        let evaluated = try DocumentEvaluator(tolerance: .standard).evaluate(document)
        try evaluated.validate()
        let artifact = try #require(evaluated.assembly)
        #expect(artifact.local.model.bodies.count == 1)
        #expect(evaluated.brep.bodies.count == 2 && evaluated.meshes.count == 2)
        #expect(artifact.occurrences.count == 4)
        let leaves = artifact.occurrences.filter { !$0.features.isEmpty }
        #expect(Set(leaves.map(\.path)).count == 2)
        for occurrence in leaves {
            for source in occurrence.features {
                for (local, world) in source.vertices {
                    let a = try #require(artifact.local.model.vertices[local]?.point)
                    let b = try #require(evaluated.brep.vertices[world]?.point)
                    #expect((b - occurrence.placement.applying(to: a)).length < 1e-12)
                }
            }
        }
        #expect(evaluated.subshapes.entries.keys.allSatisfy { document.designGraph.nodes[$0.featureID] != nil })
        #expect(evaluated.subshapes.entries.keys.allSatisfy { $0.role.hasPrefix("assembly/") })
        let exact = try DocumentEvaluator(tolerance: .standard).evaluateExact(document)
        #expect(exact.meshes.isEmpty && exact.brep == evaluated.brep)
        let restored = try JSONDecoder().decode(EvaluatedDocument.self, from: JSONEncoder().encode(evaluated))
        #expect(restored.brep == evaluated.brep && restored.assembly == artifact)
    }
    @Test(.timeLimit(.minutes(1)))
    func placementAndLocalEditReuseCorrectLocalBase() throws {
        var document = try fixture()
        let evaluator = DocumentEvaluator(tolerance: .standard)
        let first = try evaluator.evaluate(document)
        let originalArtifact = try #require(first.assembly)
        document.assembly?.roots.reverse()
        let reordered = try evaluator.evaluate(document, reusing: first)
        #expect(reordered.brep == first.brep)
        #expect(reordered.evaluationMetrics.reusedFeatureCount == 1)
        document.assembly?.roots[0].placement = .translated(by: Vector3D(x: 0, y: 20, z: 0))
        let moved = try evaluator.evaluate(document, reusing: reordered)
        #expect(moved.evaluationMetrics.reusedFeatureCount == 1)
        #expect(moved.assembly?.local == originalArtifact.local)
        #expect(moved.brep != reordered.brep)
        var feature = try #require(document.designGraph.nodes[document.designGraph.order[0]])
        feature.operation = .primitive(PrimitiveFeature(definition: .box(BoxPrimitive(
            width: .constant(.length(2, unit: .meter)), depth: .constant(.length(2, unit: .meter)), height: .constant(.length(3, unit: .meter))))))
        document.designGraph.nodes[feature.id] = feature
        let edited = try evaluator.evaluate(document, reusing: moved)
        #expect(edited.evaluationMetrics.rebuiltFeatureCount == 1)
        #expect(edited.assembly?.local.model != originalArtifact.local.model)
        try edited.validate()
        #expect(try evaluator.evaluate(document).brep == edited.brep)
    }
    @Test(.timeLimit(.minutes(1)))
    func topologyAndWorkCeilingsRefuseBeforePublishingWorldCopies() throws {
        let document = try fixture()
        #expect(throws: AssemblyError.self) {
            _ = try DocumentEvaluator(tolerance: .standard,
                assemblyResourceLimits: AssemblyResourceLimits(maximumTopologyEntities: 1)).evaluateExact(document)
        }
        #expect(throws: AssemblyError.self) {
            _ = try DocumentEvaluator(tolerance: .standard,
                assemblyResourceLimits: AssemblyResourceLimits(maximumWork: 20)).evaluateExact(document)
        }
        let ordinary = CADDocument(units: document.units, designGraph: document.designGraph)
        let local = try DocumentEvaluator(tolerance: .standard).evaluateExact(ordinary)
        let base = AssemblyLocalEvaluationBase(model: local.brep, subshapes: local.subshapes, lineage: local.lineage)
        var invalid = try #require(document.assembly)
        invalid.definitions[0].features = []
        #expect(throws: AssemblyError.self) {
            _ = try AssemblyEvaluator().evaluate(invalid, in: document.designGraph, local: base, tolerance: .standard)
        }
    }
    @Test(.timeLimit(.minutes(1)))
    func sourceAndWorldPhasesShareOneCumulativeWorkCeiling() throws {
        let document = try fixture(), assembly = try #require(document.assembly)
        let ordinary = CADDocument(units: document.units, designGraph: document.designGraph)
        let local = try DocumentEvaluator(tolerance: .standard).evaluateExact(ordinary)
        let base = AssemblyLocalEvaluationBase(model: local.brep, subshapes: local.subshapes, lineage: local.lineage)
        let expansion = try DocumentAssemblyValidator().expand(assembly, in: document.designGraph,
            tolerance: .standard)
        let evaluator: any AssemblyEvaluating = AssemblyEvaluator()
        let admitted = try evaluator.evaluate(assembly, in: document.designGraph, local: base,
            tolerance: .standard, limits: .standard)
        #expect(expansion.consumedWork > 0 && admitted.consumedWork > expansion.consumedWork)
        // A ceiling sufficient for the world phase alone must still pay for source expansion.
        let worldOnly = admitted.consumedWork - expansion.consumedWork
        #expect(throws: AssemblyError.self) {
            _ = try evaluator.evaluate(assembly, in: document.designGraph, local: base, tolerance: .standard,
                limits: AssemblyResourceLimits(maximumWork: worldOnly))
        }
        let exactBoundary = try evaluator.evaluate(assembly, in: document.designGraph, local: base,
            tolerance: .standard, limits: AssemblyResourceLimits(maximumWork: admitted.consumedWork))
        #expect(exactBoundary.model == admitted.model && exactBoundary.consumedWork == admitted.consumedWork)
    }
    @Test(.timeLimit(.minutes(1)))
    func cancelledEvaluationReturnsNoPartialSnapshot() async throws {
        let document = try fixture()
        let (stream, continuation) = AsyncStream<Void>.makeStream()
        let task = Task {
            for await _ in stream { break }
            return try DocumentEvaluator(tolerance: .standard).evaluateExact(document)
        }
        task.cancel(); continuation.yield(()); continuation.finish()
        do { _ = try await task.value; Issue.record("Cancelled assembly evaluation published a snapshot.") }
        catch is CancellationError {}
    }
}
