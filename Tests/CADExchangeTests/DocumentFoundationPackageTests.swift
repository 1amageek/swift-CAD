import Foundation
import Testing
import CADCore
import CADIR
import CADExchange

@Suite("Document foundation native persistence")
struct DocumentFoundationPackageTests {
    @Test(.timeLimit(.minutes(1)))
    func memoryAndURLPersistenceRetainTypedValuesOwnershipAndExternalLinks() throws {
        let store = NativePackageStore(tolerance: .standard)
        var target = CADDocument(units: .meters)
        let targetAttribute = DocumentAttribute(name: "length", owner: .init(documentID: target.id),
            value: .quantity(.length(12, unit: .inch)))
        target.documentFoundation = DocumentFoundation(attributes: [targetAttribute])
        let reference = DocumentObjectReference(documentID: target.id, target: .attribute(targetAttribute.id))
        var source = CADDocument(units: .millimeters)
        let owner = DocumentObjectReference(documentID: source.id)
        let parent = DocumentAttribute(name: "link", owner: owner, value: .reference(reference))
        let records = [parent,
            DocumentAttribute(name: "integer", owner: owner, value: .integer(Int64.max)),
            DocumentAttribute(name: "bytes", owner: .init(documentID: source.id, target: .attribute(parent.id)),
                value: .bytes(Data([0, 128, 255])))]
        source.documentFoundation = DocumentFoundation(attributes: records)
        let sink = DataByteSink()
        try store.writePackage(for: source, to: sink)
        let restored = try store.loadDocument(from: BorrowedBytes(sink.bytes))
        #expect(restored == source)
        #expect(try restored.sourceFingerprint(tolerance: .standard) == source.sourceFingerprint(tolerance: .standard))
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { do { try FileManager.default.removeItem(at: directory) } catch { Issue.record("Temporary package cleanup failed: \(error).") } }
        let sourceURL = directory.appendingPathComponent("source.swiftcad")
        let targetURL = directory.appendingPathComponent("target.swiftcad")
        try store.save(restored, to: sourceURL)
        try store.save(target, to: targetURL)
        let loadedSource = try store.load(from: sourceURL)
        let loadedTarget = try store.load(from: targetURL)
        #expect(loadedSource == source)
        #expect(loadedTarget == target)
        let resolver: any DocumentReferenceResolving = DefaultDocumentReferenceResolver()
        #expect(throws: DocumentFoundationError.missingDocument(target.id)) {
            _ = try resolver.resolve(reference, in: [loadedSource.id: loadedSource], tolerance: .standard)
        }
        guard case .attribute(let resolved) = try resolver.resolve(reference,
            in: [loadedTarget.id: loadedTarget], tolerance: .standard) else {
            Issue.record("Persisted external attribute did not resolve."); return
        }
        #expect(resolved == targetAttribute)
        guard case .quantity(let quantity) = resolved.value else { Issue.record("Resolved quantity changed type."); return }
        #expect(quantity.kind == .length && abs(quantity.value - 0.3048) < 1e-14)
    }

    @Test(.timeLimit(.minutes(1)))
    func strictNativeAdmissionRejectsMalformedFoundationInsteadOfDiscardingFields() throws {
        let store = NativePackageStore(tolerance: .standard)
        var document = CADDocument(units: .meters)
        document.documentFoundation = DocumentFoundation(attributes: [
            DocumentAttribute(name: "length", owner: .init(documentID: document.id), value: .quantity(.length(1, unit: .meter)))])
        let sink = DataByteSink()
        try store.writePackage(for: document, to: sink)
        let mutations: [(inout [String: Any]) -> Void] = [
            { $0["legacyField"] = true },
            { $0["value"] = ["kind": "unknown", "unknown": 1] },
            { $0["value"] = ["kind": "integer", "integer": "1"] },
            { $0["value"] = ["kind": "real", "real": 1, "integer": 1] },
            { $0["value"] = ["kind": "quantity", "quantity": ["value": 1, "kind": "length", "unit": "meter"]] },
            { $0["owner"] = ["documentID": document.id.description,
                "target": ["kind": "document", "attributeID": DocumentAttributeID().description]] },
            { $0["value"] = ["kind": "reference", "reference": ["documentID": document.id.description,
                "target": ["kind": "attribute", "attributeID": DocumentAttributeID().description]]] }
        ]
        for mutation in mutations {
            let bytes = try alteredPackage(sink.bytes) { object in
                var foundation = try #require(object["documentFoundation"] as? [String: Any])
                var records = try #require(foundation["attributes"] as? [[String: Any]])
                mutation(&records[0])
                foundation["attributes"] = records
                object["documentFoundation"] = foundation
            }
            #expect(throws: (any Error).self) { _ = try store.loadDocument(from: BorrowedBytes(bytes)) }
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func currentPackageRequiresFoundationAndRejectsPreviousDevelopmentEnvelope() throws {
        let store = NativePackageStore(tolerance: .standard)
        let sink = DataByteSink()
        try store.writePackage(for: CADDocument(units: .meters), to: sink)
        let missing = try alteredPackage(sink.bytes) { $0.removeValue(forKey: "documentFoundation") }
        #expect(throws: SchemaError.self) { _ = try store.loadDocument(from: BorrowedBytes(missing)) }
        let previous = try alteredPackage(sink.bytes, manifest: { $0["schemaVersion"] = ["major": 0, "minor": 2, "patch": 0] }) {
            $0["schemaVersion"] = ["major": 0, "minor": 2, "patch": 0]
        }
        #expect(throws: SchemaError.self) { _ = try store.loadDocument(from: BorrowedBytes(previous)) }
    }

    @Test(.timeLimit(.minutes(1)))
    func invalidSaveCannotReplaceExistingFileOrPublishSinkBytes() throws {
        let store = NativePackageStore(tolerance: .standard)
        let valid = CADDocument(units: .meters)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".swiftcad")
        defer { do { try FileManager.default.removeItem(at: url) } catch { Issue.record("Temporary package cleanup failed: \(error).") } }
        try store.save(valid, to: url)
        let original = try Data(contentsOf: url)
        var invalid = valid
        invalid.documentFoundation = DocumentFoundation(attributes: [DocumentAttribute(name: "orphan",
            owner: .init(documentID: valid.id, target: .feature(FeatureID())), value: .integer(1))])
        #expect(throws: DocumentFoundationError.self) { try store.save(invalid, to: url) }
        #expect(try Data(contentsOf: url) == original)
        #expect(try store.load(from: url) == valid)
        let sink = DataByteSink()
        #expect(throws: DocumentFoundationError.self) { try store.writePackage(for: invalid, to: sink) }
        #expect(sink.bytes.isEmpty)
    }

    private func alteredPackage(_ data: Data, manifest: ((inout [String: Any]) throws -> Void)? = nil,
                                document: (inout [String: Any]) throws -> Void) throws -> Data {
        try StoredZipArchive.withEntries(from: BorrowedBytes(data)) { entries in
            let documentBytes = try #require(entries["document.json"])
            var source = try #require(JSONSerialization.jsonObject(with: documentBytes) as? [String: Any])
            try document(&source)
            let manifestBytes = try #require(entries["manifest.json"])
            var header = try #require(JSONSerialization.jsonObject(with: manifestBytes) as? [String: Any])
            if let manifest { try manifest(&header) }
            return try StoredZipArchive.make(entries: [
                .init(path: "manifest.json", data: JSONSerialization.data(withJSONObject: header, options: [.sortedKeys])),
                .init(path: "document.json", data: JSONSerialization.data(withJSONObject: source, options: [.sortedKeys]))])
        }
    }
}
