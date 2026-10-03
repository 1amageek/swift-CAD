import Foundation
import Testing
import CADCore
@testable import CADIR

@Suite("Typed product attribute source contracts")
struct ProductAttributesTests {
    private func sharedGeometryFixture() -> (CADDocument, StableSubshapeReference, AssemblyDefinitionID) {
        let featureID = FeatureID()
        let feature = FeatureNode(id: featureID, operation: .primitive(PrimitiveFeature(definition: .box(BoxPrimitive(
            width: .constant(.length(1, unit: .meter)), depth: .constant(.length(2, unit: .meter)),
            height: .constant(.length(3, unit: .meter)))))), outputs: [FeatureOutput(role: .body)])
        let product = AssemblyProduct(name: "shared geometry")
        let formation = AssemblyProductFormation(productID: product.id)
        let selected = AssemblyDefinition(formationID: formation.id, identifier: "selected", features: [featureID])
        let other = AssemblyDefinition(formationID: formation.id, identifier: "other", features: [featureID])
        let document = CADDocument(units: .meters, designGraph: DesignGraph(nodes: [featureID: feature], order: [featureID]),
            assembly: DocumentAssembly(products: [product], formations: [formation], definitions: [selected, other], roots: [
                AssemblyOccurrence(definitionID: selected.id), AssemblyOccurrence(definitionID: other.id),
                AssemblyOccurrence(definitionID: selected.id)]))
        let reference = StableSubshapeReference(subshapeID: SubshapeID(featureID: featureID, role: "face", ordinal: 0),
            geometrySignature: .untrimmedPlane(origin: .origin))
        return (document, reference, selected.id)
    }
    @Test(.timeLimit(.minutes(1)))
    func definitionQualifiedGeometryPersistsItsDistinctSourceScope() throws {
        var (document, reference, selected) = sharedGeometryFixture()
        let target = ProductAttributeTarget(kind: .face, geometry: reference, definitionID: selected)
        let assignment = ProductAttributeAssignment(target: target, value: .density(PhysicalDensity(kilogramsPerCubicMeter: 1000)))
        document.productAttributes = ProductAttributes(assignments: [assignment],
            layers: [ProductLayer(name: "selected definition", members: [target])])
        // Admission retains one selected definition without replacing the common geometry owner.
        try document.validateProductAttributes()
        let restored = try JSONDecoder().decode(CADDocument.self, from: JSONEncoder().encode(document))
        #expect(restored == document)
        #expect(restored.productAttributes.assignments[0].target.definitionID == selected)
        let scopedFingerprint = try document.sourceFingerprint(tolerance: .standard)
        document.productAttributes.assignments[0] = ProductAttributeAssignment(id: assignment.id,
            target: ProductAttributeTarget(kind: .face, geometry: reference), value: assignment.value)
        #expect(try document.sourceFingerprint(tolerance: .standard) != scopedFingerprint)
    }
    @Test(.timeLimit(.minutes(1)))
    func definitionQualifiedGeometryRequiresMembershipAndOneScopeSelector() throws {
        var (document, reference, selected) = sharedGeometryFixture()
        document.assembly?.definitions[0].features = []
        let target = ProductAttributeTarget(kind: .face, geometry: reference, definitionID: selected)
        document.productAttributes = ProductAttributes(assignments: [ProductAttributeAssignment(target: target, value: .opacity(0.5))])
        do {
            try document.validateProductAttributes()
            Issue.record("A definition accepted geometry owned only by another definition.")
        } catch let error as ProductAttributeError {
            guard case .missingTarget = error else { Issue.record("Foreign geometry membership was misclassified: \(error)"); return }
        }
        let path = AssemblyOccurrencePath([try #require(document.assembly?.roots.first?.id)])
        let conflicting = ProductAttributeTarget(kind: .face, geometry: reference, definitionID: selected, path: path)
        #expect(throws: ProductAttributeError.invalidSource("Geometry target has invalid payload.")) { try conflicting.validate() }
    }
    private func fixture() -> (CADDocument, ProductAttributeTarget) {
        let products = [AssemblyProduct(name: "leaf"), AssemblyProduct(name: "middle"), AssemblyProduct(name: "outer")]
        let formations = products.map { AssemblyProductFormation(productID: $0.id) }
        let leaf = AssemblyDefinition(formationID: formations[0].id)
        let child = AssemblyOccurrence(definitionID: leaf.id)
        let middle = AssemblyDefinition(formationID: formations[1].id, children: [child])
        let parent = AssemblyOccurrence(definitionID: middle.id)
        let outer = AssemblyDefinition(formationID: formations[2].id, children: [parent])
        let root = AssemblyOccurrence(definitionID: outer.id)
        let document = CADDocument(units: .meters, assembly: DocumentAssembly(products: products, formations: formations, definitions: [leaf, middle, outer], roots: [root]))
        return (document, ProductAttributeTarget(kind: .occurrence, path: AssemblyOccurrencePath([root.id, parent.id, child.id])))
    }
    @Test(.timeLimit(.minutes(1)))
    func depthAdmissionIsResourceFailureForARealCompletePath() throws {
        var (document, target) = fixture()
        document.productAttributes = ProductAttributes(assignments: [ProductAttributeAssignment(target: target, value: .color(ColorRGBA(r: 0, g: 0, b: 1, a: 1)))])
        try document.validateProductAttributes()
        do {
            try document.validateProductAttributes(limits: ProductAttributeLimits(maximumDepth: 2))
            Issue.record("An admitted three-component source path exceeded its depth ceiling.")
        } catch let error as ProductAttributeError {
            guard case .resourceLimitExceeded = error else { Issue.record("Depth was misclassified: \(error)"); return }
        }
    }
    @Test(.timeLimit(.minutes(1)))
    func explicitDensityAndIndependentOverrideChainsPersistAndFingerprint() throws {
        var (document, target) = fixture()
        let material = PhysicalMaterialDescriptor(name: "steel", description: "physical descriptor", density: PhysicalDensity(kilogramsPerCubicMeter: 7850))
        let base = ProductAttributeAssignment(target: target, value: .material(material.id))
        document.productAttributes = ProductAttributes(materials: [material], assignments: [base],
            layers: [ProductLayer(name: "manufacturing", members: [target])])
        try document.validateProductAttributes()
        let before = try document.sourceFingerprint(tolerance: .standard)
        let density = ProductAttributeAssignment(target: target, value: .descriptorDensity(material.id))
        document.productAttributes.assignments.append(density)
        try document.validateProductAttributes()
        #expect(try document.sourceFingerprint(tolerance: .standard) != before)
        #expect(try JSONDecoder().decode(CADDocument.self, from: JSONEncoder().encode(document)) == document)
        #expect(document.productAttributes.assignments.filter { $0.value.property == .density }.count == 1)
        let densityFingerprint = try document.sourceFingerprint(tolerance: .standard)
        let modified = PhysicalMaterialDescriptor(id: material.id, name: material.name, description: material.description, density: PhysicalDensity(kilogramsPerCubicMeter: 7800))
        document.productAttributes.materials = [modified]
        #expect(try document.sourceFingerprint(tolerance: .standard) != densityFingerprint)
    }
    @Test(.timeLimit(.minutes(1)))
    func invalidValuesDanglingTargetsCyclesAndAmbiguityFailExplicitly() throws {
        var (document, target) = fixture()
        for value in [ProductAttributeValue.density(PhysicalDensity(kilogramsPerCubicMeter: .nan)), .opacity(1.1), .color(ColorRGBA(r: 0,g: 0,b: 0,a: 0.5))] {
            document.productAttributes = ProductAttributes(assignments: [ProductAttributeAssignment(target: target, value: value)])
            #expect(throws: (any Error).self) { try document.validateProductAttributes() }
        }
        let a = ProductAttributeID(), b = ProductAttributeID()
        document.productAttributes = ProductAttributes(assignments: [
            ProductAttributeAssignment(id: a, target: target, value: .opacity(0.4), overrides: b),
            ProductAttributeAssignment(id: b, target: target, value: .opacity(0.7), overrides: a)])
        #expect(throws: ProductAttributeError.self) { try document.validateProductAttributes() }
        document.productAttributes = ProductAttributes(assignments: [ProductAttributeAssignment(target: target, value: .opacity(0.4)), ProductAttributeAssignment(target: target, value: .opacity(0.7))])
        #expect(throws: ProductAttributeError.self) { try document.validateProductAttributes() }
        document.productAttributes = ProductAttributes(assignments: [ProductAttributeAssignment(target: ProductAttributeTarget(kind: .part, definitionID: AssemblyDefinitionID()), value: .opacity(0.4))])
        #expect(throws: ProductAttributeError.self) { try document.validateProductAttributes() }
    }
    @Test(.timeLimit(.minutes(1)))
    func strictRequiredContainerAndNestedKeysDoNotDefaultOrDrop() throws {
        let document = fixture().0
        var json = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(document)) as? [String: Any])
        json.removeValue(forKey: "productAttributes")
        #expect(throws: (any Error).self) { _ = try JSONDecoder().decode(CADDocument.self, from: JSONSerialization.data(withJSONObject: json)) }
        json["productAttributes"] = ["materials": [], "assignments": [], "layers": [], "unknown": true] as [String: Any]
        #expect(throws: (any Error).self) { _ = try JSONDecoder().decode(CADDocument.self, from: JSONSerialization.data(withJSONObject: json)) }
    }
}
