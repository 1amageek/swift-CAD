import Foundation
import Testing
import CADCore
import CADIR
import CADKernel
@testable import CADExchange

@Suite("Native definition-qualified product geometry scope")
struct ProductAttributesNativeScopeTests {
    @Test(.timeLimit(.minutes(1)))
    func sharedGeometryScopePersistsAndRejectsOldOrInvalidSourceAtomically() throws {
        let featureID = FeatureID()
        let feature = FeatureNode(id: featureID, operation: .primitive(PrimitiveFeature(definition: .box(BoxPrimitive(
            width: .constant(.length(1, unit: .meter)), depth: .constant(.length(2, unit: .meter)),
            height: .constant(.length(3, unit: .meter)))))), outputs: [FeatureOutput(role: .body)])
        let product = AssemblyProduct(name: "shared native source"), formation = AssemblyProductFormation(productID: product.id)
        let selected = AssemblyDefinition(formationID: formation.id, identifier: "selected", features: [featureID])
        let other = AssemblyDefinition(formationID: formation.id, identifier: "other", features: [featureID])
        var document = CADDocument(units: .meters, designGraph: DesignGraph(nodes: [featureID: feature], order: [featureID]),
            assembly: DocumentAssembly(products: [product], formations: [formation], definitions: [selected, other], roots: [
                AssemblyOccurrence(definitionID: selected.id), AssemblyOccurrence(definitionID: other.id),
                AssemblyOccurrence(definitionID: selected.id)]))
        let evaluator = DocumentEvaluator(tolerance: .standard), resolver = ProductAttributeResolver()
        let base = try evaluator.evaluateExact(document), local = try #require(base.assembly?.local)
        let bodyKey = try #require(local.subshapes.entries.keys.sorted().first { key in
            if let topology = local.subshapes.entries[key], case .body = topology { return true }; return false
        })
        let reference = try resolver.sourceReference(for: bodyKey, in: base)
        let target = ProductAttributeTarget(kind: .body, geometry: reference, definitionID: selected.id)
        let assignment = ProductAttributeAssignment(target: target, value: .density(PhysicalDensity(kilogramsPerCubicMeter: 1000)))
        document.productAttributes = ProductAttributes(assignments: [assignment],
            layers: [ProductLayer(name: "selected only", members: [target])])
        let store = NativePackageStore(tolerance: .standard), sink = DataByteSink()
        try store.writePackage(for: document, to: sink)
        let loaded = try store.loadDocument(from: sink.bytes)
        #expect(loaded == document && loaded.schemaVersion == SchemaVersion(major: 0, minor: 12, patch: 0))
        #expect(loaded.designGraph.nodes.count == 1)
        #expect(loaded.assembly?.definitions.allSatisfy { $0.features == [featureID] } == true)
        let evaluated = try evaluator.evaluateExact(loaded), view = try resolver.resolve(evaluated)
        #expect(evaluated.assembly?.local.model.bodies.count == 1 && evaluated.brep.bodies.count == 3)
        let selectedBodies = view.values.filter { key, _ in
            if case .body = key.topology { return key.definitionID == selected.id }; return false
        }
        let otherBodies = view.values.filter { key, _ in
            if case .body = key.topology { return key.definitionID == other.id }; return false
        }
        #expect(selectedBodies.count == 2 && selectedBodies.values.allSatisfy { $0.properties[.density]?.value == assignment.value })
        #expect(otherBodies.count == 1 && otherBodies.values.allSatisfy { $0.properties[.density] == nil })
        let oldEnvelope = try StoredZipArchive.withEntries(from: BorrowedBytes(sink.bytes)) { entries in
            var output: [StoredZipArchive.Entry] = []
            for path in ["manifest.json", "document.json"] {
                let data = try #require(entries[path])
                var object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
                var version = try #require(object["schemaVersion"] as? [String: Any])
                version["minor"] = 7; object["schemaVersion"] = version
                output.append(.init(path: path, data: try JSONSerialization.data(withJSONObject: object)))
            }
            return try StoredZipArchive.make(entries: output)
        }
        #expect(throws: SchemaError.self) { _ = try store.loadDocument(from: BorrowedBytes(oldEnvelope)) }
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { do { try FileManager.default.removeItem(at: directory) } catch { Issue.record("Unable to remove native scope fixture directory: \(error)") } }
        let url = directory.appendingPathComponent("scope.swiftcad")
        try store.save(document, to: url)
        #expect(try store.load(from: url) == document)
        let original = try Data(contentsOf: url)
        var foreign = document
        foreign.assembly?.definitions[0].features = []
        #expect(throws: ProductAttributeError.missingTarget("Geometry is not owned by the selected definition.")) {
            try store.save(foreign, to: url)
        }
        #expect(try Data(contentsOf: url) == original)
        let path = AssemblyOccurrencePath([try #require(document.assembly?.roots.first?.id)])
        document.productAttributes.assignments[0] = ProductAttributeAssignment(id: assignment.id,
            target: ProductAttributeTarget(kind: .body, geometry: reference, definitionID: selected.id, path: path), value: assignment.value)
        #expect(throws: ProductAttributeError.invalidSource("Geometry target has invalid payload.")) { try store.save(document, to: url) }
        #expect(try Data(contentsOf: url) == original)
    }
}
