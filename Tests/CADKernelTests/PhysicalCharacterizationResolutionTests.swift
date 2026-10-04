import Testing
import CADCore
import CADIR
import CADTopology
@testable import CADKernel

@Suite("Physical characterization source receipt")
struct PhysicalCharacterizationResolutionTests {
    @Test(.timeLimit(.minutes(1)))
    func unicodeMetadataEditRejectsStaleExactReceiptWithoutChangingGeometryOrEffectiveValues() throws {
        let id = FeatureID()
        let node = FeatureNode(id: id, operation: .primitive(PrimitiveFeature(definition: .box(BoxPrimitive(
            width: .constant(.length(1, unit: .meter)), depth: .constant(.length(2, unit: .meter)),
            height: .constant(.length(3, unit: .meter)))))), outputs: [FeatureOutput(role: .body)])
        var document = CADDocument(units: .meters, designGraph: DesignGraph(nodes: [id: node], order: [id]))
        let evaluator = DocumentEvaluator(tolerance: .standard), resolver = ProductAttributeResolver()
        let initial = try evaluator.evaluateExact(document)
        let body = try #require(initial.subshapes.entries.first { if case .body = $0.value { return true }; return false }?.key)
        let target = ProductAttributeTarget(kind: .body, geometry: try resolver.sourceReference(for: body, in: initial))
        document.productAttributes.assignments = [ProductAttributeAssignment(target: target, value: .density(PhysicalDensity(kilogramsPerCubicMeter: 1000)))]
        document.productAttributes.physicalCharacterizations = [ProductPhysicalCharacterization(target: target, name: "\u{e9}", description: nil)]
        let old = try evaluator.evaluateExact(document), before = try resolver.resolve(old)
        let fingerprint = try document.sourceFingerprint(tolerance: .standard)
        document.productAttributes.physicalCharacterizations = [ProductPhysicalCharacterization(target: target, name: "e\u{301}", description: nil)]
        #expect(try document.sourceFingerprint(tolerance: .standard) != fingerprint)
        let oldReceipt = try #require(old.validatedSourceReceipt)
        let oldExactBRep = try #require(old.validatedBRep)
        #expect(oldReceipt.document == old.document && oldReceipt.document != document)
        var stale = EvaluatedDocument(document: document, parameters: old.parameters, brep: old.brep,
            meshes: old.meshes, curves: old.curves, caches: old.caches, subshapes: old.subshapes, lineage: old.lineage,
            configuration: old.configuration, assembly: old.assembly, evaluationMetrics: old.evaluationMetrics)
        // Retain the genuine prior producer receipts to exercise source freshness, rather than merely missing receipt admission.
        stale.validatedSourceReceipt = oldReceipt; stale.validatedBRep = oldExactBRep
        #expect(throws: ProductAttributeError.inconsistentArtifact("Missing or stale producer source/exact B-rep association.")) { _ = try resolver.resolve(stale) }
        let current = try evaluator.evaluateExact(document), after = try resolver.resolve(current)
        #expect(current.brep == old.brep && current.subshapes == old.subshapes && current.lineage == old.lineage)
        #expect(after.values == before.values && after.localGeometry == before.localGeometry)
        #expect(current.caches.brep == nil && old.caches.brep == nil)
    }
}
