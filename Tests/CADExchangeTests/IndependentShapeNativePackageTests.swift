import Foundation
import Testing
import CADCore
import CADGeometry
import CADTopology
import CADIR
@testable import CADExchange

@Suite("Independent shape Native package", .timeLimit(.minutes(1)))
struct IndependentShapeNativePackageTests {
    @Test
    func originalSelectionAndDirectedTrimSurvivePublicNativeTransport() throws {
        let curveID = CurveID(highBits: 31, lowBits: 1)
        let itemID = IndependentShapeItemID(highBits: 32, lowBits: 1)
        let source = IndependentShapeSource(
            geometry: GeometryStore(curves: [curveID: .line(.init(origin: .init(x: 2, y: 3, z: 4), direction: .unitY))]),
            items: [.init(id: itemID, name: "original independent curve", geometry: .curve(curveID,
                trim: .init(startParameter: 3, endParameter: -2)))], curveNames: [curveID: ""], roots: [.item(itemID)])
        let document = CADDocument(units: .millimeters, independentShapes: source)
        let store = NativePackageStore(tolerance: .standard)
        let sink = DataByteSink()
        try store.writePackage(for: document, to: sink)
        let restored = try store.loadDocument(from: sink.bytes)
        #expect(restored == document)
        #expect(restored.independentShapes == source)
        #expect(restored.schemaVersion == SchemaVersion(major: 0, minor: 12, patch: 0))
        #expect(try restored.sourceFingerprint(tolerance: .standard) == document.sourceFingerprint(tolerance: .standard))
        let malformed = try StoredZipArchive.withEntries(from: BorrowedBytes(sink.bytes)) { entries in
            let documentData = try #require(entries["document.json"])
            var object = try #require(JSONSerialization.jsonObject(with: documentData) as? [String: Any])
            object.removeValue(forKey: "independentShapes")
            return try StoredZipArchive.make(entries: [
                .init(path: "manifest.json", data: #require(entries["manifest.json"])),
                .init(path: "document.json", data: JSONSerialization.data(withJSONObject: object))])
        }
        #expect(throws: SchemaError.self) { _ = try store.loadDocument(from: BorrowedBytes(malformed)) }
    }
    @Test
    func originalPlaneFrameSurvivesNativeTransport() throws {
        let surfaceID = SurfaceID(highBits: 41, lowBits: 1)
        let itemID = IndependentShapeItemID(highBits: 42, lowBits: 1)
        let plane = Plane3D(origin: .init(x: 2, y: 3, z: 4), normal: .unitZ,
                            uDirection: .init(x: 0.6, y: 0.8, z: 0))
        let source = IndependentShapeSource(
            geometry: GeometryStore(surfaces: [surfaceID: .plane(plane)]),
            items: [.init(id: itemID, name: "original parameter frame", geometry: .surface(surfaceID))],
            roots: [.item(itemID)])
        let document = CADDocument(units: .millimeters, independentShapes: source)
        let store = NativePackageStore(tolerance: .standard)
        let sink = DataByteSink()
        try store.writePackage(for: document, to: sink)
        let restored = try store.loadDocument(from: sink.bytes)
        #expect(restored == document)
        let surface = try #require(restored.independentShapes?.geometry.surfaces[surfaceID])
        let point = try surface.point(u: 5, v: -2, tolerance: .standard)
        #expect(abs(point.x - 6.6) < 1e-12)
        #expect(abs(point.y - 5.8) < 1e-12)
        #expect(point.z == 4)
        #expect(try restored.sourceFingerprint(tolerance: .standard) == document.sourceFingerprint(tolerance: .standard))
    }

    @Test
    func originalSharedPrimitivePositionMapsAreStrictAndFingerprintOwned() throws {
        let curveID = CurveID(highBits: 51, lowBits: 1)
        let surfaceID = SurfaceID(highBits: 52, lowBits: 1)
        let position = IndependentShapeFrame(id: .init(highBits: 53, lowBits: 1), name: "é",
            placement: try .init(basisX: .unitY, basisY: -.unitX, basisZ: .unitZ, translation: .init(x: 0.01, y: 0.02, z: 0.03)))
        let curve = Curve3D.affineImage(try .init(source: .circle(.init(center: .origin, normal: .unitZ, radius: 0.004)),
            transform: position.placement, tolerance: .standard))
        let plane = Surface3D.plane(.init(origin: .init(x: 0.01, y: 0.02, z: 0.03), normal: .unitZ, uDirection: .unitY))
        let first = IndependentShapeItem(id: .init(highBits: 54, lowBits: 1), name: "circle", geometry: .curve(curveID, trim: nil))
        let second = IndependentShapeItem(id: .init(highBits: 54, lowBits: 2), name: "plane", geometry: .surface(surfaceID))
        func source(name: String) -> IndependentShapeSource {
            .init(geometry: GeometryStore(curves: [curveID: curve], surfaces: [surfaceID: plane]), items: [first, second],
                frames: [.init(id: position.id, name: name, placement: position.placement)],
                curveNames: [curveID: first.name], surfaceNames: [surfaceID: second.name],
                curvePositionFrames: [curveID: .init(frameID: position.id)], surfacePositionFrames: [surfaceID: .init(frameID: position.id)],
                roots: [.item(first.id), .item(second.id)])
        }
        let document = CADDocument(units: .millimeters, independentShapes: source(name: position.name))
        let store = NativePackageStore(tolerance: .standard), sink = DataByteSink()
        try store.writePackage(for: document, to: sink)
        let restored = try store.loadDocument(from: sink.bytes)
        #expect(restored == document)
        #expect(restored.independentShapes?.frames.count == 1)
        #expect(restored.independentShapes?.curvePositionFrames[curveID]?.frameID == position.id)
        #expect(restored.independentShapes?.surfacePositionFrames[surfaceID]?.frameID == position.id)
        let changed = CADDocument(id: document.id, units: document.units, independentShapes: source(name: "e\u{301}"), metadata: document.metadata)
        #expect(changed.independentShapes != document.independentShapes)
        #expect(try changed.sourceFingerprint(tolerance: .standard) != document.sourceFingerprint(tolerance: .standard))
        for mutation in 0..<3 {
            let malformed = try StoredZipArchive.withEntries(from: BorrowedBytes(sink.bytes)) { entries in
                let manifestData = try #require(entries["manifest.json"])
                let documentData = try #require(entries["document.json"])
                var object = try #require(JSONSerialization.jsonObject(with: documentData) as? [String: Any])
                var original = try #require(object["independentShapes"] as? [String: Any])
                var pairs = try #require(original["curvePositionFrames"] as? [Any])
                var association = try #require(pairs[1] as? [String: Any])
                switch mutation {
                case 0: association.removeValue(forKey: "parameterLengthUnit")
                case 1: association["unknownPositionMeaning"] = true
                default: association["parameterLengthUnit"] = "millimeter"
                }
                pairs[1] = association; original["curvePositionFrames"] = pairs; object["independentShapes"] = original
                return try StoredZipArchive.make(entries: [.init(path: "manifest.json", data: manifestData),
                    .init(path: "document.json", data: JSONSerialization.data(withJSONObject: object))])
            }
            if mutation == 2 {
                #expect(throws: IndependentShapeSourceError.invalidSource("Original curve position association disagrees with its stored parameter law.")) {
                    _ = try store.loadDocument(from: BorrowedBytes(malformed))
                }
            } else {
                #expect(throws: SchemaError.self) { _ = try store.loadDocument(from: BorrowedBytes(malformed)) }
            }
        }
        for field in ["curvePositionFrames", "surfacePositionFrames"] {
            let malformed = try StoredZipArchive.withEntries(from: BorrowedBytes(sink.bytes)) { entries in
                let manifestData = try #require(entries["manifest.json"])
                let documentData = try #require(entries["document.json"])
                var object = try #require(JSONSerialization.jsonObject(with: documentData) as? [String: Any])
                var original = try #require(object["independentShapes"] as? [String: Any])
                original.removeValue(forKey: field); object["independentShapes"] = original
                return try StoredZipArchive.make(entries: [.init(path: "manifest.json", data: manifestData),
                    .init(path: "document.json", data: JSONSerialization.data(withJSONObject: object))])
            }
            #expect(throws: SchemaError.self) { _ = try store.loadDocument(from: BorrowedBytes(malformed)) }
        }
    }

}
