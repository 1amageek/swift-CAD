import Foundation
import Testing
import CADCore
@testable import CADIR

@Suite("Global physical characterization source")
struct PhysicalCharacterizationTests {
    private func fixture() -> (CADDocument, ProductAttributeTarget) {
        let id = FeatureID()
        let node = FeatureNode(id: id, operation: .primitive(PrimitiveFeature(definition: .box(BoxPrimitive(
            width: .constant(.length(1, unit: .meter)), depth: .constant(.length(2, unit: .meter)),
            height: .constant(.length(3, unit: .meter)))))), outputs: [FeatureOutput(role: .body)])
        let reference = StableSubshapeReference(subshapeID: SubshapeID(featureID: id, role: "face", ordinal: 0),
            geometrySignature: .untrimmedPlane(origin: .origin))
        let target = ProductAttributeTarget(kind: .face, geometry: reference)
        let attributes = ProductAttributes(assignments: [ProductAttributeAssignment(target: target,
            value: .density(PhysicalDensity(kilogramsPerCubicMeter: 1000)))])
        return (CADDocument(units: .meters, designGraph: DesignGraph(nodes: [id: node], order: [id]), productAttributes: attributes), target)
    }

    @Test(.timeLimit(.minutes(1)))
    func exactTextNullableCodingCopyAndFingerprintHaveOneOwner() throws {
        var (document, target) = fixture()
        let composed = ProductItemCharacterization(target: target, name: "\u{e9}", description: nil)
        let decomposed = ProductItemCharacterization(target: target, name: "e\u{301}", description: nil)
        let emptyDescription = ProductItemCharacterization(target: target, name: "\u{e9}", description: "")
        #expect(composed != decomposed && composed != emptyDescription)
        #expect(Set([composed, decomposed, emptyDescription]).count == 3)
        document.productAttributes.itemCharacterizations = [composed]
        try document.validateProductAttributes()
        let before = try document.sourceFingerprint(tolerance: .standard)
        let restored = try JSONDecoder().decode(CADDocument.self, from: JSONEncoder().encode(document))
        #expect(restored == document)
        var edited = document.productAttributes
        edited.itemCharacterizations = [decomposed]
        let copy = try document.replacingProductAttributes(edited, tolerance: .standard)
        #expect(copy.productAttributes != document.productAttributes)
        #expect(try copy.sourceFingerprint(tolerance: .standard) != before)
        #expect(document.productAttributes.itemCharacterizations == [composed])
        edited.itemCharacterizations = [emptyDescription]
        #expect(try document.replacingProductAttributes(edited, tolerance: .standard).sourceFingerprint(tolerance: .standard) != before)
        var object = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(composed)) as? [String: Any])
        object.removeValue(forKey: "description")
        #expect(throws: ProductAttributeError.invalidSource("Physical characterization requires an explicit nullable description.")) {
            _ = try JSONDecoder().decode(ProductItemCharacterization.self, from: JSONSerialization.data(withJSONObject: object))
        }
        object["description"] = NSNull(); object["unknown"] = true
        #expect(throws: (any Error).self) {
            _ = try JSONDecoder().decode(ProductItemCharacterization.self, from: JSONSerialization.data(withJSONObject: object))
        }
        var container = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(document.productAttributes)) as? [String: Any])
        container.removeValue(forKey: "itemCharacterizations")
        #expect(throws: (any Error).self) {
            _ = try JSONDecoder().decode(ProductAttributes.self, from: JSONSerialization.data(withJSONObject: container))
        }
        let sourceReference = try #require(target.geometry)
        let secondTarget = ProductAttributeTarget(kind: .face, geometry: StableSubshapeReference(
            subshapeID: SubshapeID(featureID: sourceReference.subshapeID.featureID, role: "face", ordinal: 1),
            geometrySignature: .untrimmedPlane(origin: .origin)))
        let second = ProductItemCharacterization(target: secondTarget, name: "second", description: "")
        var ordered = document
        ordered.productAttributes.assignments.append(ProductAttributeAssignment(target: secondTarget,
            value: .density(PhysicalDensity(kilogramsPerCubicMeter: 2000))))
        ordered.productAttributes.itemCharacterizations = [second, composed]
        #expect(ordered.productAttributes.canonicalized.itemCharacterizations == [composed, second])
        let orderedFingerprint = try ordered.sourceFingerprint(tolerance: .standard)
        ordered.productAttributes.itemCharacterizations.reverse()
        #expect(try ordered.sourceFingerprint(tolerance: .standard) == orderedFingerprint)
    }

    @Test(.timeLimit(.minutes(1)))
    func defaultDuplicateAndScopeRefuseWhileIndependentMetadataNeedsNoAttachment() throws {
        var (document, target) = fixture()
        let value = ProductItemCharacterization(target: target, name: "inspection", description: nil)
        let defaultValue = ProductItemCharacterization(target: target, name: "", description: nil)
        document.productAttributes.itemCharacterizations = [defaultValue]
        #expect(document.productAttributes.canonicalized.itemCharacterizations == [defaultValue])
        #expect(throws: ProductAttributeError.invalidSource("Default physical characterization must be absent.")) { try document.validateProductAttributes() }
        document.productAttributes.itemCharacterizations = [value, value]
        #expect(throws: ProductAttributeError.invalidSource("Duplicate physical characterization target.")) { try document.validateProductAttributes() }
        let sourceReference = try #require(target.geometry)
        let competingTarget = ProductAttributeTarget(kind: .face, geometry: StableSubshapeReference(
            subshapeID: sourceReference.subshapeID, geometrySignature: .untrimmedPlane(origin: Point3D(x: 1, y: 0, z: 0))))
        document.productAttributes.assignments.append(ProductAttributeAssignment(target: competingTarget,
            value: .density(PhysicalDensity(kilogramsPerCubicMeter: 2000))))
        document.productAttributes.itemCharacterizations = [value,
            ProductItemCharacterization(target: competingTarget, name: "competing", description: nil)]
        #expect(throws: ProductAttributeError.invalidSource("Duplicate physical characterization target.")) { try document.validateProductAttributes() }
        let scoped = ProductAttributeTarget(kind: .face, geometry: target.geometry, path: AssemblyOccurrencePath([AssemblyOccurrenceID()]))
        document.productAttributes.itemCharacterizations = [ProductItemCharacterization(target: scoped, name: "scoped", description: nil)]
        #expect(throws: ProductAttributeError.invalidSource("Physical characterization requires a global geometry target.")) { try document.validateProductAttributes() }
        document.productAttributes.itemCharacterizations = [value]
        document.productAttributes.assignments = []
        try document.validateProductAttributes()
        #expect(document.productAttributes.assignments.isEmpty && document.productAttributes.itemCharacterizations == [value])
        document.productAttributes.itemCharacterizations = []
        try document.validateProductAttributes()
        document.productAttributes.assignments = [ProductAttributeAssignment(target: target, value: .density(PhysicalDensity(kilogramsPerCubicMeter: 1000)))]
        document.productAttributes.itemCharacterizations = [ProductItemCharacterization(target: target, name: "", description: "")]
        try document.validateProductAttributes()
    }

    @Test(.timeLimit(.minutes(1)))
    func metadataSourceUniquenessRetainsKindWithStableIDAndStillRefusesCompetingSignatures() throws {
        var (document, faceTarget) = fixture()
        let faceReference = try #require(faceTarget.geometry)
        guard case let .face(faceSignature) = faceReference.geometrySignature else {
            Issue.record("Independent source fixture requires a face signature."); return
        }
        let bodyReference = StableSubshapeReference(subshapeID: faceReference.subshapeID,
            geometrySignature: .body(BodyGeometrySignature(kind: .sheet,
                shells: [ShellGeometrySignature(orientation: .forward, faces: [faceSignature])])))
        let bodyTarget = ProductAttributeTarget(kind: .body, geometry: bodyReference)
        let bodyMetadata = ProductItemCharacterization(target: bodyTarget, name: "body metadata", description: nil)
        let faceMetadata = ProductItemCharacterization(target: faceTarget, name: "face metadata", description: nil)
        document.productAttributes.assignments.append(ProductAttributeAssignment(target: bodyTarget,
            value: .density(PhysicalDensity(kilogramsPerCubicMeter: 2000))))
        document.productAttributes.itemCharacterizations = [faceMetadata, bodyMetadata]
        // Source admission validates signature kind, not a role-name convention; evaluated resolution keeps its separate geometry proof.
        try document.validateProductAttributes()
        #expect(document.productAttributes.canonicalized.itemCharacterizations == [bodyMetadata, faceMetadata])
        #expect(try JSONDecoder().decode(CADDocument.self, from: JSONEncoder().encode(document)) == document)
        let competing = ProductItemCharacterization(target: ProductAttributeTarget(kind: .face,
            geometry: StableSubshapeReference(subshapeID: faceReference.subshapeID,
                geometrySignature: .untrimmedPlane(origin: Point3D(x: 1, y: 0, z: 0)))), name: "competing", description: nil)
        document.productAttributes.itemCharacterizations.append(competing)
        #expect(throws: ProductAttributeError.invalidSource("Duplicate physical characterization target.")) { try document.validateProductAttributes() }
    }

    @Test(.timeLimit(.minutes(1)))
    func callerRecordsWorkTextAndCancellationBoundMetadataAdmission() async throws {
        var (document, target) = fixture()
        document.productAttributes.itemCharacterizations = [ProductItemCharacterization(target: target, name: "region", description: "description")]
        for limits in [ProductAttributeLimits(maximumRecords: 1), ProductAttributeLimits(maximumWork: 1), ProductAttributeLimits(maximumTextBytes: 1)] {
            do { try document.validateProductAttributes(limits: limits); Issue.record("Physical metadata exceeded caller limits.") }
            catch let error as ProductAttributeError { guard case .resourceLimitExceeded = error else { Issue.record("Unexpected budget failure: \(error)"); continue } }
        }
        let immutable = document
        let task = Task { withUnsafeCurrentTask { $0?.cancel() }; try immutable.validateProductAttributes() }
        do { try await task.value; Issue.record("Cancelled metadata validation succeeded.") }
        catch is CancellationError {}
    }
}
