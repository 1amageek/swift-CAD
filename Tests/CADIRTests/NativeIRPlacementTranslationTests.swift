import Testing
import CADCore
import CADGeometry
@testable import CADIR

@Suite("Native IR original placement translation")
struct NativeIRPlacementTranslationTests {
    private func fixture() -> CADDocument {
        let id = FeatureID()
        let feature = FeatureNode(id: id, operation: .primitive(PrimitiveFeature(definition: .box(
            BoxPrimitive(width: .constant(.length(1, unit: .meter)), depth: .constant(.length(2, unit: .meter)),
                         height: .constant(.length(3, unit: .meter)))))), outputs: [FeatureOutput(role: .body)])
        let products = [AssemblyProduct(name: "shared part"), AssemblyProduct(name: "subassembly")]
        let formations = products.map { AssemblyProductFormation(productID: $0.id) }
        let part = AssemblyDefinition(formationID: formations[0].id, features: [id])
        let subassembly = AssemblyDefinition(formationID: formations[1].id, children: [AssemblyOccurrence(definitionID: part.id,
            placement: .translated(by: Vector3D(x: 1, y: 2, z: 3)))])
        return CADDocument(units: .millimeters, designGraph: DesignGraph(nodes: [id: feature], order: [id]),
            assembly: DocumentAssembly(products: products, formations: formations, definitions: [part, subassembly], roots: [
                AssemblyOccurrence(definitionID: subassembly.id),
                AssemblyOccurrence(definitionID: subassembly.id, placement: .translated(by: Vector3D(x: 10, y: 0, z: 0)))
            ]))
    }
    @Test(.timeLimit(.minutes(1)))
    func translationRetainsOriginalSTEPPlacementFactor() throws {
        var document = fixture()
        let location = OriginalSTEPPlacementElement(id: .init(high: 12, low: 34),
            name: "original model point", coordinates: .init(x: 1000, y: 2000, z: 3000))
        let original = OriginalSTEPPlacementSource.axis2(.init(lengthUnit: .millimeter,
            location: location, axis: nil, referenceDirection: nil))
        document.assembly?.roots[0].placement = .step(original)
        let displacement = Vector3D(x: 4, y: 5, z: 6)
        let translated = try document.translatingSources(by: displacement, tolerance: .standard)
        guard case .word(let word) = translated.assembly?.roots[0].placement else {
            Issue.record("Expected translated original placement word."); return
        }
        #expect(word.factors == [.forward(.translated(by: displacement)), .forward(.step(original))])
        #expect(document.assembly?.roots[0].placement == .step(original))
        #expect(translated.assembly?.definitions == document.assembly?.definitions)
    }

}
