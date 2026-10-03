import Foundation
import Testing
import CADCore
import CADGeometry
@testable import CADIR

@Suite("Document assembly source")
struct DocumentAssemblyTests {
    private func fixture() -> CADDocument {
        let id = FeatureID()
        let feature = FeatureNode(id: id, operation: .primitive(PrimitiveFeature(definition: .box(
            BoxPrimitive(width: .constant(.length(1, unit: .meter)), depth: .constant(.length(2, unit: .meter)),
                         height: .constant(.length(3, unit: .meter)))))), outputs: [FeatureOutput(role: .body)])
        let part = AssemblyDefinition(name: "shared part", features: [id])
        let subassembly = AssemblyDefinition(name: "subassembly", children: [AssemblyOccurrence(definitionID: part.id,
            placement: .translated(by: Vector3D(x: 1, y: 2, z: 3)))])
        return CADDocument(units: .millimeters, designGraph: DesignGraph(nodes: [id: feature], order: [id]),
            assembly: DocumentAssembly(definitions: [part, subassembly], roots: [
                AssemblyOccurrence(definitionID: subassembly.id),
                AssemblyOccurrence(definitionID: subassembly.id, placement: .translated(by: Vector3D(x: 10, y: 0, z: 0)))
            ]))
    }
    @Test(.timeLimit(.minutes(1)))
    func sharedNestedPathsFramesPersistenceAndFingerprint() throws {
        let document = fixture()
        try document.validate(tolerance: .standard)
        let assembly = try #require(document.assembly)
        let expanded = try DocumentAssemblyValidator().expandedOccurrences(of: assembly, in: document.designGraph, tolerance: .standard)
        #expect(expanded.count == 4)
        let leaves = expanded.filter { $0.path.components.count == 2 }
        #expect(leaves.count == 2 && leaves[0].path != leaves[1].path)
        #expect(Set(leaves.map(\.placement.translation.x)) == [1, 11])
        let restored = try JSONDecoder().decode(CADDocument.self, from: JSONEncoder().encode(document))
        #expect(restored == document)
        var moved = document
        moved.assembly?.roots.reverse()
        moved.assembly?.definitions.reverse()
        #expect(try moved.sourceFingerprint(tolerance: .standard) == document.sourceFingerprint(tolerance: .standard))
        moved.assembly?.roots[0].placement = .translated(by: Vector3D(x: 12, y: 0, z: 0))
        #expect(try moved.sourceFingerprint(tolerance: .standard) != document.sourceFingerprint(tolerance: .standard))
    }
    @Test(.timeLimit(.minutes(1)))
    func sourceDeletionSuppressionCyclesAndBoundsRefuse() throws {
        let document = fixture(), assembly = try #require(document.assembly)
        var bad = document
        bad.designGraph.nodes[document.designGraph.order[0]]?.isSuppressed = true
        #expect(throws: AssemblyError.self) { try bad.validate(tolerance: .standard) }
        bad = document
        bad.assembly?.definitions[1].children.append(AssemblyOccurrence(definitionID: assembly.definitions[1].id))
        #expect(throws: AssemblyError.self) { try bad.validate(tolerance: .standard) }
        bad = document
        bad.assembly?.roots[0].definitionID = AssemblyDefinitionID()
        #expect(throws: AssemblyError.self) { try bad.validate(tolerance: .standard) }
        #expect(throws: AssemblyError.self) {
            _ = try DocumentAssemblyValidator().expandedOccurrences(of: assembly, in: document.designGraph,
                tolerance: .standard, limits: AssemblyResourceLimits(maximumOccurrences: 3))
        }
        bad = document
        bad.assembly?.roots[0].placement = try RigidTransform3D.mirrored(across: .origin, normal: .unitX, tolerance: .standard)
        #expect(throws: AssemblyError.self) { try bad.validate(tolerance: .standard) }
    }
    @Test(.timeLimit(.minutes(1)))
    func recordAndWorkAdmissionPrecedesDuplicateFeatureAllocation() throws {
        let document = fixture(), featureID = document.designGraph.order[0]
        let definition = AssemblyDefinition(features: Array(repeating: featureID, count: 1024))
        let assembly = DocumentAssembly(definitions: [definition], roots: [AssemblyOccurrence(definitionID: definition.id)])
        let validator: any DocumentAssemblyValidating = DocumentAssemblyValidator()
        #expect(throws: AssemblyError.invalidSource("Assembly requires at least one root occurrence.")) {
            _ = try validator.expand(DocumentAssembly(definitions: [], roots: []), in: document.designGraph,
                tolerance: .standard, limits: AssemblyResourceLimits(maximumRecords: 4, maximumWork: 4))
        }
        #expect(throws: AssemblyError.resourceLimitExceeded("source records")) {
            _ = try validator.expand(assembly, in: document.designGraph, tolerance: .standard,
                limits: AssemblyResourceLimits(maximumRecords: 4, maximumWork: 4))
        }
        #expect(throws: AssemblyError.resourceLimitExceeded("source work")) {
            _ = try validator.expand(assembly, in: document.designGraph, tolerance: .standard,
                limits: AssemblyResourceLimits(maximumRecords: 2048, maximumWork: 4))
        }
        #expect(throws: AssemblyError.invalidSource("Duplicate definition or local feature reference.")) {
            _ = try validator.expand(assembly, in: document.designGraph, tolerance: .standard,
                limits: .standard)
        }
    }
    @Test(.timeLimit(.minutes(1)))
    func fastTransitionsAndTranslationPreserveLocalAuthority() throws {
        let document = fixture()
        let translated = try document.translatingSources(by: Vector3D(x: 4, y: 5, z: 6), tolerance: .standard)
        #expect(translated.designGraph == document.designGraph)
        #expect(translated.assembly?.definitions == document.assembly?.definitions)
        #expect(translated.assembly?.roots[0].placement.translation == Vector3D(x: 4, y: 5, z: 6))
        let validated = try ValidatedCADDocument(document, tolerance: .standard)
        var replacement = try #require(document.designGraph.nodes[document.designGraph.order[0]])
        replacement.name = "renamed local definition"
        let updated = try validated.replacingGraphStableFeature(replacement)
        #expect(updated.document.assembly == document.assembly)
        try updated.document.validate(tolerance: .standard)
    }
    @Test(.timeLimit(.minutes(1)))
    func descriptionsAreDistinctRequiredNullableSourceOwners() throws {
        var document = fixture()
        document.assembly?.definitions[0].productDescription = "product café"
        document.assembly?.definitions[0].definitionDescription = "definition π"
        let original = try document.sourceFingerprint(tolerance: .standard)
        var edited = document
        edited.assembly?.definitions[0].productDescription = "another product description"
        #expect(try edited.sourceFingerprint(tolerance: .standard) != original)
        edited = document; edited.assembly?.definitions[0].definitionDescription = "another definition description"
        #expect(try edited.sourceFingerprint(tolerance: .standard) != original)
        edited = document; edited.assembly?.definitions[1].productDescription = ""
        #expect(try edited.sourceFingerprint(tolerance: .standard) != original)
        #expect(try JSONDecoder().decode(CADDocument.self, from: JSONEncoder().encode(document)) == document)
        let translated = try document.translatingSources(by: .unitX, tolerance: .standard)
        #expect(translated.assembly?.definitions == document.assembly?.definitions)
        let validated = try ValidatedCADDocument(document, tolerance: .standard)
        var feature = try #require(document.designGraph.nodes[document.designGraph.order[0]])
        feature.name = "local feature edit"
        let updated = try validated.replacingGraphStableFeature(feature)
        #expect(updated.document.assembly == document.assembly)
        #expect(try updated.document.sourceFingerprint(tolerance: .standard) != original)
        let definition = AssemblyDefinition(name: "required nulls")
        let object = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(definition)) as? [String: Any])
        #expect(object["productDescription"] is NSNull && object["definitionDescription"] is NSNull)
        for key in ["productDescription", "definitionDescription"] {
            var missing = object; missing.removeValue(forKey: key)
            #expect(throws: DecodingError.self) {
                _ = try JSONDecoder().decode(AssemblyDefinition.self, from: JSONSerialization.data(withJSONObject: missing))
            }
        }
        #expect(throws: SchemaError.self) { try SchemaVersion(major: 0, minor: 5, patch: 0).validate() }
    }
    @Test(.timeLimit(.minutes(1)))
    func strictNullableFieldOldVersionAndNestedUnknownRefuse() throws {
        let document = fixture()
        let data = try JSONEncoder().encode(document)
        let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        var missing = object; missing.removeValue(forKey: "assembly")
        #expect(throws: (any Error).self) { _ = try JSONDecoder().decode(CADDocument.self, from: JSONSerialization.data(withJSONObject: missing)) }
        var older = document; older.schemaVersion = SchemaVersion(major: 0, minor: 3, patch: 0)
        #expect(throws: SchemaError.self) { try older.validate(tolerance: .standard) }
        var unknown = object
        var assembly = try #require(unknown["assembly"] as? [String: Any])
        var roots = try #require(assembly["roots"] as? [[String: Any]])
        var frame = try #require(roots[0]["placement"] as? [String: Any])
        frame["scale"] = 2; roots[0]["placement"] = frame; assembly["roots"] = roots; unknown["assembly"] = assembly
        #expect(throws: (any Error).self) { _ = try JSONDecoder().decode(CADDocument.self, from: JSONSerialization.data(withJSONObject: unknown)) }
        let plain = CADDocument(units: .meters)
        let plainObject = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(plain)) as? [String: Any])
        #expect(plainObject["assembly"] is NSNull)
    }
}
