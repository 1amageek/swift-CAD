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
        moved.assembly?.products.reverse(); moved.assembly?.formations.reverse()
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
        let product = AssemblyProduct(), formation = AssemblyProductFormation(productID: product.id)
        let definition = AssemblyDefinition(formationID: formation.id, features: Array(repeating: featureID, count: 1024))
        let assembly = DocumentAssembly(products: [product], formations: [formation], definitions: [definition], roots: [AssemblyOccurrence(definitionID: definition.id)])
        let validator: any DocumentAssemblyValidating = DocumentAssemblyValidator()
        #expect(throws: AssemblyError.invalidSource("Assembly requires at least one root occurrence.")) {
            _ = try validator.expand(DocumentAssembly(products: [], formations: [], definitions: [], roots: []), in: document.designGraph,
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
        document.assembly?.products[0].description = "product café"
        document.assembly?.definitions[0].definitionDescription = "definition π"
        let original = try document.sourceFingerprint(tolerance: .standard)
        var edited = document
        edited.assembly?.products[0].description = "another product description"
        #expect(try edited.sourceFingerprint(tolerance: .standard) != original)
        edited = document; edited.assembly?.definitions[0].definitionDescription = "another definition description"
        #expect(try edited.sourceFingerprint(tolerance: .standard) != original)
        edited = document; edited.assembly?.products[1].description = ""
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
        let product = AssemblyProduct(name: "required nulls")
        let formation = AssemblyProductFormation(productID: product.id)
        let definition = AssemblyDefinition(formationID: formation.id)
        for data in [try JSONEncoder().encode(product), try JSONEncoder().encode(formation), try JSONEncoder().encode(definition)] {
            let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
            let key = object["definitionDescription"] == nil ? "description" : "definitionDescription"
            #expect(object[key] is NSNull)
            var missing = object; missing.removeValue(forKey: key)
            let bytes = try JSONSerialization.data(withJSONObject: missing)
            if key == "definitionDescription" {
                #expect(throws: DecodingError.self) { _ = try JSONDecoder().decode(AssemblyDefinition.self, from: bytes) }
            } else if object["productID"] != nil {
                #expect(throws: DecodingError.self) { _ = try JSONDecoder().decode(AssemblyProductFormation.self, from: bytes) }
            } else {
                #expect(throws: DecodingError.self) { _ = try JSONDecoder().decode(AssemblyProduct.self, from: bytes) }
            }
        }
        #expect(throws: SchemaError.self) { try SchemaVersion(major: 0, minor: 6, patch: 0).validate() }
        #expect(throws: SchemaError.self) { try SchemaVersion(major: 0, minor: 5, patch: 0).validate() }
    }
    @Test(.timeLimit(.minutes(1)))
    func sharedProductFormationOwnershipAndBoundedMetadataValidateActualSource() throws {
        let product = AssemblyProduct(identifier: "part", name: "shared", description: nil)
        let first = AssemblyProductFormation(productID: product.id, versionIdentifier: "v1", description: "formation", specifiedSource: .made)
        let second = AssemblyProductFormation(productID: product.id, versionIdentifier: "v2", description: "", specifiedSource: .notKnown)
        let a = AssemblyDefinition(formationID: first.id, identifier: "design", definitionDescription: "view A")
        let b = AssemblyDefinition(formationID: first.id, identifier: "analysis", definitionDescription: nil)
        let c = AssemblyDefinition(formationID: second.id, identifier: "", definitionDescription: "")
        let assembly = DocumentAssembly(products: [product], formations: [first, second], definitions: [a,b,c],
            roots: [AssemblyOccurrence(definitionID: a.id), AssemblyOccurrence(definitionID: b.id), AssemblyOccurrence(definitionID: c.id)])
        let document = CADDocument(units: .meters, assembly: assembly)
        try document.validate(tolerance: .standard)
        let original = try document.sourceFingerprint(tolerance: .standard)
        for change in 0..<6 {
            var changed = document
            switch change {
            case 0: changed.assembly?.products[0].identifier = "new identifier"
            case 1: changed.assembly?.products[0].name = "changed name"
            case 2: changed.assembly?.formations[0].versionIdentifier = "new version"
            case 3: changed.assembly?.formations[0].description = nil
            case 4: changed.assembly?.formations[0].specifiedSource = .bought
            default: changed.assembly?.definitions[0].identifier = "another view"
            }
            #expect(try changed.sourceFingerprint(tolerance: .standard) != original)
        }
        let translated = try document.translatingSources(by: .unitX, tolerance: .standard)
        #expect(translated.assembly?.products == assembly.products && translated.assembly?.formations == assembly.formations)
        let restored = try JSONDecoder().decode(CADDocument.self, from: JSONEncoder().encode(document))
        #expect(restored == document)
        let validator: any DocumentAssemblyValidating = DocumentAssemblyValidator()
        for change in 0..<4 {
            var bad = assembly
            switch change {
            case 0: bad.formations[1].versionIdentifier = first.versionIdentifier
            case 1: bad.formations[0].productID = AssemblyProductID()
            case 2: bad.definitions[0].formationID = AssemblyProductFormationID()
            default: bad.products.append(AssemblyProduct(identifier: "unused"))
            }
            #expect(throws: AssemblyError.self) { _ = try validator.expand(bad, in: document.designGraph, tolerance: .standard, limits: .standard) }
        }
        var large = assembly; large.products = Array(repeating: product, count: 10000)
        #expect(throws: AssemblyError.resourceLimitExceeded("source records")) {
            _ = try validator.expand(large, in: document.designGraph, tolerance: .standard,
                limits: AssemblyResourceLimits(maximumRecords: 4))
        }
        var text = assembly; text.products[0].description = String(repeating: "x", count: 10000)
        #expect(throws: AssemblyError.resourceLimitExceeded("source text/work")) {
            _ = try validator.expand(text, in: document.designGraph, tolerance: .standard,
                limits: AssemblyResourceLimits(maximumTextBytes: 64))
        }
        let lookup: any AssemblyProductLookingUp = AssemblyProductLookup()
        let found = try lookup.product(for: b.id, in: assembly, maximumWork: 6)
        #expect(found.product == product && found.consumedWork == 6)
        #expect(throws: AssemblyError.resourceLimitExceeded("product lookup work")) {
            _ = try lookup.product(for: b.id, in: assembly, maximumWork: 5)
        }
        let data = try JSONEncoder().encode(assembly)
        let json = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        for key in ["products", "formations"] {
            var missing = json; missing.removeValue(forKey: key)
            #expect(throws: DecodingError.self) { _ = try JSONDecoder().decode(DocumentAssembly.self, from: JSONSerialization.data(withJSONObject: missing)) }
        }
        var formationJSON = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(first)) as? [String: Any])
        formationJSON.removeValue(forKey: "specifiedSource")
        #expect(throws: DecodingError.self) { _ = try JSONDecoder().decode(AssemblyProductFormation.self, from: JSONSerialization.data(withJSONObject: formationJSON)) }
        formationJSON["specifiedSource"] = "invented"
        #expect(throws: DecodingError.self) { _ = try JSONDecoder().decode(AssemblyProductFormation.self, from: JSONSerialization.data(withJSONObject: formationJSON)) }
    }
    @Test(.timeLimit(.minutes(1)))
    func exactUnicodeTextIdentityKeepsOwnersVersionsAndFingerprintsConsistent() throws {
        let composed = "é", decomposed = "e\u{301}"
        #expect(composed == decomposed && !composed.utf8.elementsEqual(decomposed.utf8))
        var original = fixture()
        original.assembly?.products[0].identifier = composed
        original.assembly?.products[0].name = composed
        original.assembly?.products[0].description = composed
        original.assembly?.formations[0].versionIdentifier = composed
        original.assembly?.formations[0].description = composed
        original.assembly?.definitions[0].identifier = composed
        original.assembly?.definitions[0].definitionDescription = composed
        let fingerprint = try original.sourceFingerprint(tolerance: .standard)
        for field in 0..<7 {
            var changed = original
            switch field {
            case 0: changed.assembly?.products[0].identifier = decomposed
            case 1: changed.assembly?.products[0].name = decomposed
            case 2: changed.assembly?.products[0].description = decomposed
            case 3: changed.assembly?.formations[0].versionIdentifier = decomposed
            case 4: changed.assembly?.formations[0].description = decomposed
            case 5: changed.assembly?.definitions[0].identifier = decomposed
            default: changed.assembly?.definitions[0].definitionDescription = decomposed
            }
            #expect(original != changed && original.assembly != changed.assembly)
            #expect(try changed.sourceFingerprint(tolerance: .standard) != fingerprint)
            #expect(try JSONDecoder().decode(CADDocument.self, from: JSONEncoder().encode(changed)) == changed)
        }
        let product = AssemblyProduct(identifier: "part")
        let first = AssemblyProductFormation(productID: product.id, versionIdentifier: composed)
        let second = AssemblyProductFormation(productID: product.id, versionIdentifier: decomposed)
        let a = AssemblyDefinition(formationID: first.id), b = AssemblyDefinition(formationID: second.id)
        var versions = CADDocument(units: .meters, assembly: DocumentAssembly(products: [product], formations: [first,second],
            definitions: [a,b], roots: [AssemblyOccurrence(definitionID: a.id), AssemblyOccurrence(definitionID: b.id)]))
        try versions.validate(tolerance: .standard)
        versions.assembly?.formations[1].versionIdentifier = composed
        #expect(throws: AssemblyError.invalidSource("Formation version is not unique within its product.")) {
            try versions.validate(tolerance: .standard)
        }
        var productEmpty = product; productEmpty.description = ""
        #expect(productEmpty != product)
        var formationEmpty = first; formationEmpty.description = ""
        #expect(formationEmpty != first)
        var definitionEmpty = a; definitionEmpty.definitionDescription = ""
        #expect(definitionEmpty != a)
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
