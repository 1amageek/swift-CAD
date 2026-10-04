import Testing
import CADCore
import CADGeometry
import CADIR
import CADTopology
@testable import CADKernel

@Suite("Qualified shape element description source receipt")
struct ShapeElementDescriptionResolutionTests {
    @Test(.timeLimit(.minutes(1)))
    func descriptionEditRejectsGenuineStaleExactReceiptAndPreservesSharedGeometryAndValues() throws {
        let id = FeatureID()
        let node = FeatureNode(id: id, operation: .primitive(PrimitiveFeature(definition: .box(BoxPrimitive(
            width: .constant(.length(1, unit: .meter)), depth: .constant(.length(2, unit: .meter)),
            height: .constant(.length(3, unit: .meter)))))), outputs: [FeatureOutput(role: .body)])
        let product = AssemblyProduct(name: "shared geometry"), formation = AssemblyProductFormation(productID: product.id)
        let selected = AssemblyDefinition(formationID: formation.id, features: [id])
        let other = AssemblyDefinition(formationID: formation.id, features: [id])
        var document = CADDocument(units: .meters, designGraph: DesignGraph(nodes: [id: node], order: [id]),
            assembly: DocumentAssembly(products: [product], formations: [formation], definitions: [selected, other], roots: [
                AssemblyOccurrence(definitionID: selected.id), AssemblyOccurrence(definitionID: other.id, placement: .translated(by: Vector3D(x: 3, y: 0, z: 0))),
                AssemblyOccurrence(definitionID: selected.id, placement: .translated(by: Vector3D(x: 6, y: 0, z: 0)))]))
        let evaluator = DocumentEvaluator(tolerance: .standard), resolver = ProductAttributeResolver()
        let initial = try evaluator.evaluateExact(document)
        let local = try #require(initial.assembly?.local)
        let body = try #require(local.subshapes.entries.first { if case .body = $0.value { return true }; return false }?.key)
        let target = ProductAttributeTarget(kind: .body, geometry: try resolver.sourceReference(for: body, in: initial), definitionID: selected.id)
        document.productAttributes.assignments = [ProductAttributeAssignment(target: target, value: .name("selected body"))]
        document.productAttributes.shapeElementDescriptions = [ProductShapeElementDescription(target: target, description: "\u{e9}")]
        let old = try evaluator.evaluateExact(document), before = try resolver.resolve(old)
        #expect(old.assembly?.local.model.bodies.count == 1 && old.brep.bodies.count == 3)
        let named = before.values.filter {
            if case .body = $0.key.topology { return $0.value.properties[.name] != nil }
            return false
        }
        #expect(named.count == 2 && named.keys.allSatisfy { $0.definitionID == selected.id })
        let fingerprint = try document.sourceFingerprint(tolerance: .standard)
        document.productAttributes.shapeElementDescriptions = [ProductShapeElementDescription(target: target, description: "e\u{301}")]
        #expect(try document.sourceFingerprint(tolerance: .standard) != fingerprint)
        let oldReceipt = try #require(old.validatedSourceReceipt), oldBRep = try #require(old.validatedBRep)
        #expect(oldReceipt.document == old.document && oldReceipt.document != document)
        var stale = EvaluatedDocument(document: document, parameters: old.parameters, brep: old.brep, meshes: old.meshes,
            curves: old.curves, caches: old.caches, subshapes: old.subshapes, lineage: old.lineage, configuration: old.configuration,
            assembly: old.assembly, evaluationMetrics: old.evaluationMetrics)
        stale.validatedSourceReceipt = oldReceipt; stale.validatedBRep = oldBRep
        #expect(throws: ProductAttributeError.inconsistentArtifact("Missing or stale producer source/exact B-rep association.")) { _ = try resolver.resolve(stale) }
        let current = try evaluator.evaluateExact(document), after = try resolver.resolve(current)
        #expect(current.brep == old.brep && current.subshapes == old.subshapes && current.lineage == old.lineage)
        #expect(after.values == before.values && after.localGeometry == before.localGeometry)
        #expect(current.caches.brep == nil && old.caches.brep == nil)
        let geometry = try #require(target.geometry)
        #expect(try resolver.sourceReference(for: geometry.subshapeID, in: current) == geometry)
    }
}
