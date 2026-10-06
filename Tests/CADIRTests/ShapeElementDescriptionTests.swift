import Foundation
import Testing
import CADCore
@testable import CADIR

@Suite("Definition-qualified shape element description source")
struct ShapeElementDescriptionTests {
    private func fixture() -> (CADDocument, ProductAttributeTarget) {
        let id = FeatureID()
        let node = FeatureNode(id: id, operation: .primitive(PrimitiveFeature(definition: .box(BoxPrimitive(
            width: .constant(.length(1, unit: .meter)), depth: .constant(.length(2, unit: .meter)),
            height: .constant(.length(3, unit: .meter)))))), outputs: [FeatureOutput(role: .body)])
        let product = AssemblyProduct(name: "shared geometry")
        let formation = AssemblyProductFormation(productID: product.id)
        let selected = AssemblyDefinition(formationID: formation.id, features: [id])
        let other = AssemblyDefinition(formationID: formation.id, features: [id])
        let target = ProductAttributeTarget(kind: .face, geometry: StableSubshapeReference(
            subshapeID: SubshapeID(featureID: id, role: "face", ordinal: 0), geometrySignature: .untrimmedPlane(origin: .origin)),
            definitionID: selected.id)
        let attributes = ProductAttributes(assignments: [ProductAttributeAssignment(target: target, value: .name("selected face"))])
        return (CADDocument(units: .meters, designGraph: DesignGraph(nodes: [id: node], order: [id]),
            assembly: DocumentAssembly(products: [product], formations: [formation], definitions: [selected, other], roots: [
                AssemblyOccurrence(definitionID: selected.id), AssemblyOccurrence(definitionID: other.id), AssemblyOccurrence(definitionID: selected.id)]),
            productAttributes: attributes), target)
    }

    @Test(.timeLimit(.minutes(1)))
    func exactTextAbsenceCopyFingerprintAndCanonicalScopeHaveOneOwner() throws {
        var (document, target) = fixture()
        let absent = document
        let composed = ProductShapeElementDescription(target: target, description: "\u{e9}")
        let decomposed = ProductShapeElementDescription(target: target, description: "e\u{301}")
        let empty = ProductShapeElementDescription(target: target, description: "")
        #expect(Set([composed, decomposed, empty]).count == 3)
        document.productAttributes.shapeElementDescriptions = [empty]
        try document.validateProductAttributes()
        #expect(document != absent && absent.productAttributes.shapeElementDescriptions.isEmpty)
        #expect(try document.sourceFingerprint(tolerance: .standard) != absent.sourceFingerprint(tolerance: .standard))
        let before = try document.sourceFingerprint(tolerance: .standard)
        document.productAttributes.shapeElementDescriptions = [composed]
        #expect(try document.sourceFingerprint(tolerance: .standard) != before)
        let composedFingerprint = try document.sourceFingerprint(tolerance: .standard)
        document.productAttributes.shapeElementDescriptions = [decomposed]
        #expect(try document.sourceFingerprint(tolerance: .standard) != composedFingerprint)
        #expect(try JSONDecoder().decode(CADDocument.self, from: JSONEncoder().encode(document)) == document)
        let other = try #require(document.assembly?.definitions.last?.id)
        let otherTarget = ProductAttributeTarget(kind: .face, geometry: target.geometry, definitionID: other)
        document.productAttributes.assignments.append(ProductAttributeAssignment(target: otherTarget, value: .name("other face")))
        let otherDescription = ProductShapeElementDescription(target: otherTarget, description: "other description")
        document.productAttributes.shapeElementDescriptions.append(otherDescription)
        try document.validateProductAttributes()
        let orderedFingerprint = try document.sourceFingerprint(tolerance: .standard)
        document.productAttributes.shapeElementDescriptions.reverse()
        #expect(try document.sourceFingerprint(tolerance: .standard) == orderedFingerprint)
        let selected = try #require(target.definitionID)
        #expect(document.productAttributes.canonicalized.shapeElementDescriptions.map(\.target.definitionID)
            == [selected, other].sorted().map { Optional($0) })
    }

    @Test(.timeLimit(.minutes(1)))
    func duplicateCompetingSignatureForeignScopeAndUnattachedDescriptionsRefuse() throws {
        var (document, target) = fixture()
        let record = ProductShapeElementDescription(target: target, description: "description")
        document.productAttributes.shapeElementDescriptions = [record, record]
        #expect(throws: ProductAttributeError.invalidSource("Duplicate shape element description target.")) { try document.validateProductAttributes() }
        let reference = try #require(target.geometry)
        let competingTarget = ProductAttributeTarget(kind: .face, geometry: StableSubshapeReference(subshapeID: reference.subshapeID,
            geometrySignature: .untrimmedPlane(origin: Point3D(x: 1, y: 0, z: 0))), definitionID: target.definitionID)
        document.productAttributes.shapeElementDescriptions = [record, ProductShapeElementDescription(target: competingTarget, description: "competing")]
        #expect(throws: ProductAttributeError.invalidSource("Duplicate shape element description target.")) { try document.validateProductAttributes() }
        document.productAttributes.shapeElementDescriptions = [record]
        var foreign = document
        foreign.assembly?.definitions[0].features = []
        #expect(throws: ProductAttributeError.missingTarget("Geometry is not owned by the selected definition.")) { try foreign.validateProductAttributes() }
        document.productAttributes.assignments = []
        #expect(throws: ProductAttributeError.unsupportedSemantics("Standalone shape element description requires a name or physical attachment.")) { try document.validateProductAttributes() }
        document.productAttributes.shapeElementDescriptions = [ProductShapeElementDescription(
            target: ProductAttributeTarget(kind: .face, geometry: reference), description: "global")]
        #expect(throws: ProductAttributeError.invalidSource("Shape element description requires a definition-qualified geometry target.")) { try document.validateProductAttributes() }
        document.productAttributes = ProductAttributes(assignments: [ProductAttributeAssignment(target: target,
            value: .density(PhysicalDensity(kilogramsPerCubicMeter: 1000)))], shapeElementDescriptions: [record])
        try document.validateProductAttributes()
    }

    @Test(.timeLimit(.minutes(1)))
    func strictRequiredStringAndArrayNeverDecodeNullOrUnknownFields() throws {
        var (document, target) = fixture()
        let record = ProductShapeElementDescription(target: target, description: "")
        document.productAttributes.shapeElementDescriptions = [record]
        let encoded = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(record)) as? [String: Any])
        for mutation in 0..<3 {
            var object = encoded
            if mutation == 0 { object.removeValue(forKey: "description") }
            if mutation == 1 { object["description"] = NSNull() }
            if mutation == 2 { object["unknown"] = true }
            #expect(throws: (any Error).self) {
                _ = try JSONDecoder().decode(ProductShapeElementDescription.self, from: JSONSerialization.data(withJSONObject: object))
            }
        }
        var container = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(document.productAttributes)) as? [String: Any])
        container.removeValue(forKey: "shapeElementDescriptions")
        #expect(throws: (any Error).self) { _ = try JSONDecoder().decode(ProductAttributes.self, from: JSONSerialization.data(withJSONObject: container)) }
    }

    @Test(.timeLimit(.minutes(1)))
    func callerBudgetsAndCancellationBoundDescriptionAdmission() async throws {
        var (document, target) = fixture()
        document.productAttributes.shapeElementDescriptions = [ProductShapeElementDescription(target: target, description: "independent description")]
        for limits in [ProductAttributeLimits(maximumRecords: 1), ProductAttributeLimits(maximumWork: 1), ProductAttributeLimits(maximumTextBytes: 1)] {
            do { try document.validateProductAttributes(limits: limits); Issue.record("Description exceeded caller limits.") }
            catch let error as ProductAttributeError { guard case .resourceLimitExceeded = error else { Issue.record("Unexpected budget failure: \(error)"); continue } }
        }
        let immutable = document
        let task = Task { withUnsafeCurrentTask { $0?.cancel() }; try immutable.validateProductAttributes() }
        do { try await task.value; Issue.record("Cancelled description validation succeeded.") }
        catch is CancellationError {}
    }
}
