import Foundation
import Testing
import CADCore
import CADGeometry
import CADTopology
@testable import CADIR

@Suite("Independent shape document composition", .timeLimit(.minutes(1)))
struct IndependentShapeDocumentTests {
    private func source(name: String = "original curve") -> IndependentShapeSource {
        let curveID = CurveID(highBits: 21, lowBits: 1)
        let itemID = IndependentShapeItemID(highBits: 22, lowBits: 1)
        let curve = Curve3D.line(Line3D(origin: .init(x: 1, y: 2, z: 3), direction: .unitX))
        return IndependentShapeSource(geometry: GeometryStore(curves: [curveID: curve]),
            items: [.init(id: itemID, name: name, geometry: .curve(curveID, trim: .init(startParameter: 2, endParameter: -1)))],
            roots: [.item(itemID)])
    }

    @Test
    func completeOriginalSourceSurvivesStrictDocumentEncoding() throws {
        let document = CADDocument(units: .meters, independentShapes: source(name: "e\u{301}"))
        try document.validate(tolerance: .standard)
        let encoded = try JSONEncoder().encode(document)
        let restored = try JSONDecoder().decode(CADDocument.self, from: encoded)
        #expect(restored == document)
        #expect(restored.independentShapes?.items.first?.name.utf8.elementsEqual("e\u{301}".utf8) == true)
        var object = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        object.removeValue(forKey: "independentShapes")
        let missing = try JSONSerialization.data(withJSONObject: object)
        #expect(throws: IndependentShapeSourceError.self) {
            _ = try JSONDecoder().decode(CADDocument.self, from: missing)
        }
        let empty = CADDocument(units: .meters)
        let emptyObject = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(empty)) as? [String: Any])
        #expect(emptyObject["independentShapes"] is NSNull)
    }

    @Test
    func sourceFingerprintTracksOriginalSelectionText() throws {
        var document = CADDocument(units: .meters)
        let absent = try document.sourceFingerprint(tolerance: .standard)
        document.independentShapes = source(name: "original")
        let original = try document.sourceFingerprint(tolerance: .standard)
        document.independentShapes = source(name: "changed")
        let changed = try document.sourceFingerprint(tolerance: .standard)
        #expect(absent != original)
        #expect(original != changed)
        #expect(changed == (try document.sourceFingerprint(tolerance: .standard)))
    }

    @Test
    func documentValidationRejectsForeignShapeReference() throws {
        let original = source()
        let invalid = IndependentShapeSource(geometry: original.geometry, items: original.items,
            roots: [.item(.init(highBits: 22, lowBits: 2))])
        let document = CADDocument(units: .meters, independentShapes: invalid)
        #expect(throws: IndependentShapeSourceError.self) { try document.validate(tolerance: .standard) }
    }
}
