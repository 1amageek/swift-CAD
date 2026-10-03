import Foundation
import Testing
import CADCore
@testable import CADIR

@Suite("Document foundation")
struct DocumentFoundationTests {
    @Test(.timeLimit(.minutes(1)))
    func typedValuesAndPersistentIDsRoundTripWithoutUnitRelabeling() throws {
        var document = CADDocument(units: .millimeters)
        let external = DocumentObjectReference(documentID: DocumentID(), target: .parameter(ParameterID()))
        let values: [DocumentAttributeValue] = [
            .boolean(true), .integer(Int64.max), .real(0.125), .text("部品の属性"),
            .quantity(.length(12, unit: .inch)), .quantity(.angle(90, unit: .degree)),
            .integers([Int64.min, 0, Int64.max]), .reals([-1.5, 0, 1.5]), .texts(["", "日本語"]),
            .bytes(Data([0, 1, 254, 255])), .reference(external), .references([external])
        ]
        let owner = DocumentObjectReference(documentID: document.id)
        let records = values.enumerated().map { DocumentAttribute(name: "attribute\($0.offset)", owner: owner, value: $0.element) }
        document.documentFoundation = DocumentFoundation(attributes: records)
        try document.validate(tolerance: .standard)
        let restored = try JSONDecoder().decode(CADDocument.self, from: JSONEncoder().encode(document))
        try restored.validate(tolerance: .standard)
        #expect(restored == document)
        for record in records { #expect(restored.documentFoundation.attribute(id: record.id) == record) }
        guard case .quantity(let length) = records[4].value,
              case .quantity(let angle) = records[5].value else {
            Issue.record("Typed quantities were not retained."); return
        }
        #expect(length.kind == .length && abs(length.value - 0.3048) < 1e-14)
        #expect(angle.kind == .angle && abs(angle.value - Double.pi / 2) < 1e-14)
    }

    @Test(.timeLimit(.minutes(1)))
    func malformedTypedPayloadsAndNonfiniteDomainsAreRejected() throws {
        for json in [
            #"{"kind":"real","real":1,"integer":2}"#,
            #"{"kind":"real"}"#,
            #"{"kind":"unknown","unknown":1}"#,
            #"{"kind":"boolean","boolean":1}"#,
            #"{"kind":"quantity","quantity":{"value":1,"kind":"length","unit":"meter"}}"#,
            #"{"kind":"reference","reference":{"documentID":"00000000-0000-0000-0000-000000000001","target":{"kind":"document","featureID":"00000000-0000-0000-0000-000000000002"}}}"#
        ] {
            #expect(throws: (any Error).self) { _ = try JSONDecoder().decode(DocumentAttributeValue.self, from: Data(json.utf8)) }
        }
        for value: DocumentAttributeValue in [.real(.nan), .real(.infinity), .reals([0, -.infinity]), .quantity(.scalar(.nan))] {
            #expect(throws: DocumentFoundationError.self) { try value.validate() }
            #expect(throws: DocumentFoundationError.self) { _ = try JSONEncoder().encode(value) }
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func localOwnershipAndReferenceIntegrityRejectConcreteDanglingCases() throws {
        var document = CADDocument(units: .meters)
        let owner = DocumentObjectReference(documentID: document.id)
        let valid = DocumentAttribute(name: "name", owner: owner, value: .text("part"))
        document.documentFoundation = DocumentFoundation(attributes: [valid, valid])
        #expect(throws: DocumentFoundationError.self) { try document.validate(tolerance: .standard) }
        document.documentFoundation = DocumentFoundation(attributes: [valid, DocumentAttribute(name: "name", owner: owner, value: .text("duplicate"))])
        #expect(throws: DocumentFoundationError.self) { try document.validate(tolerance: .standard) }
        document.documentFoundation = DocumentFoundation(attributes: [DocumentAttribute(name: "foreign", owner: .init(documentID: DocumentID()), value: .text("part"))])
        #expect(throws: DocumentFoundationError.self) { try document.validate(tolerance: .standard) }
        for target in [DocumentObjectTarget.feature(FeatureID()), .parameter(ParameterID()), .attribute(DocumentAttributeID())] {
            document.documentFoundation = DocumentFoundation(attributes: [DocumentAttribute(name: "dangling", owner: owner,
                value: .reference(.init(documentID: document.id, target: target)))])
            #expect(throws: DocumentFoundationError.self) { try document.validate(tolerance: .standard) }
        }
        let first = DocumentAttributeID(), second = DocumentAttributeID()
        document.documentFoundation = DocumentFoundation(attributes: [
            DocumentAttribute(id: first, name: "a", owner: .init(documentID: document.id, target: .attribute(second)), value: .integer(1)),
            DocumentAttribute(id: second, name: "b", owner: .init(documentID: document.id, target: .attribute(first)), value: .integer(2))
        ])
        #expect(throws: DocumentFoundationError.self) { try document.validate(tolerance: .standard) }
    }

    @Test(.timeLimit(.minutes(1)))
    func ownerForestAndReferenceCyclesHaveDifferentSemantics() throws {
        var document = CADDocument(units: .meters)
        let first = DocumentAttributeID(), second = DocumentAttributeID()
        let parent = DocumentAttribute(id: first, name: "parent", owner: .init(documentID: document.id),
            value: .reference(.init(documentID: document.id, target: .attribute(second))))
        let child = DocumentAttribute(id: second, name: "child", owner: .init(documentID: document.id, target: .attribute(first)),
            value: .reference(.init(documentID: document.id, target: .attribute(first))))
        document.documentFoundation = DocumentFoundation(attributes: [parent, child])
        try document.validate(tolerance: .standard)
        let resolver: any DocumentReferenceResolving = DefaultDocumentReferenceResolver()
        guard case .attribute(let resolved) = try resolver.resolve(.init(documentID: document.id, target: .attribute(second)),
            in: [document.id: document], tolerance: .standard) else { Issue.record("Attribute reference did not resolve."); return }
        #expect(resolved == child)
    }

    @Test(.timeLimit(.minutes(1)))
    func sourceFingerprintTracksAttributesAndCanonicalIdentityOrder() throws {
        var first = CADDocument(units: .meters)
        let owner = DocumentObjectReference(documentID: first.id)
        let a = DocumentAttribute(name: "a", owner: owner, value: .integer(1))
        let b = DocumentAttribute(name: "b", owner: owner, value: .quantity(.length(1, unit: .meter)))
        let emptyFingerprint = try first.sourceFingerprint(tolerance: .standard)
        first.documentFoundation = DocumentFoundation(attributes: [a, b])
        var second = first; second.documentFoundation = DocumentFoundation(attributes: [b, a])
        #expect(try first.sourceFingerprint(tolerance: .standard) == second.sourceFingerprint(tolerance: .standard))
        #expect(try first.sourceFingerprint(tolerance: .standard) != emptyFingerprint)
        var edited = a; edited.value = .integer(2)
        second.documentFoundation = try second.documentFoundation.setting(edited)
        #expect(try first.sourceFingerprint(tolerance: .standard) != second.sourceFingerprint(tolerance: .standard))
        #expect(first.documentFoundation.attribute(id: a.id)?.value == .integer(1))
    }

    @Test(.timeLimit(.minutes(1)))
    func sourceEnvelopeRequiresExplicitFoundationWithoutLegacyDefault() throws {
        let source = CADDocument(units: .meters)
        var object = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(source)) as? [String: Any])
        object.removeValue(forKey: "documentFoundation")
        #expect(throws: DecodingError.self) { _ = try JSONDecoder().decode(CADDocument.self, from: JSONSerialization.data(withJSONObject: object)) }
        #expect(throws: SchemaError.self) { try SchemaVersion(major: 0, minor: 2, patch: 0).validate() }
        #expect(SchemaVersion.current == SchemaVersion(major: 0, minor: 5, patch: 0))
    }

    @Test(.timeLimit(.minutes(1)))
    func cancellationIsPropagatedDuringFoundationValidation() async throws {
        var document = CADDocument(units: .meters)
        document.documentFoundation = DocumentFoundation(attributes: [DocumentAttribute(name: "value", owner: .init(documentID: document.id), value: .integer(1))])
        let source = document
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            try source.validate(tolerance: .standard)
        }
        do { try await task.value; Issue.record("Cancelled foundation validation succeeded.") }
        catch is CancellationError { }
        catch { Issue.record("Cancellation became \(error).") }
    }
}
