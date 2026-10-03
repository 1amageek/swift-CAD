import Foundation
import Testing
import CADCore
@testable import CADIR

@Suite("Typed product attribute source contracts")
struct ProductAttributesTests {
    private func fixture() -> (CADDocument, ProductAttributeTarget) {
        let leaf = AssemblyDefinition(name: "leaf")
        let child = AssemblyOccurrence(definitionID: leaf.id)
        let middle = AssemblyDefinition(name: "middle", children: [child])
        let parent = AssemblyOccurrence(definitionID: middle.id)
        let outer = AssemblyDefinition(name: "outer", children: [parent])
        let root = AssemblyOccurrence(definitionID: outer.id)
        let document = CADDocument(units: .meters, assembly: DocumentAssembly(definitions: [leaf, middle, outer], roots: [root]))
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
