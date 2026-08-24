import Foundation
import Testing
import CADCore
import CADIR
import CADTopology
import CADKernel
@testable import CADExchange

#if canImport(PDFKit)
import PDFKit
#endif

#if os(macOS)
import Darwin
#endif

private func collectBytes(_ operation: (any ByteSink) throws -> Void) throws -> Data {
    let sink = DataByteSink()
    try operation(sink)
    return sink.bytes
}

private func expectExchangeFailure(_ operation: () throws -> Void) {
    do {
        try operation()
        Issue.record("Expected the exchange operation to fail.")
    } catch {
    }
}

private final class RecordingByteSink: ByteSink {
    private(set) var bytes = Data()
    private(set) var writeCount = 0
    private(set) var maximumWriteSize = 0

    func write(_ bytes: UnsafeRawBufferPointer) throws {
        writeCount += 1
        maximumWriteSize = max(maximumWriteSize, bytes.count)
        self.bytes.append(contentsOf: bytes)
    }
}

private extension STLExporter {
    func exportBinary(meshes: [BodyID: Mesh], options: STLExportOptions = STLExportOptions()) throws -> Data {
        try collectBytes { try writeBinary(meshes: meshes, options: options, to: $0) }
    }
}

private extension STEPExchange {
    func export(meshes: [BodyID: Mesh], units: UnitSystem = .meters) throws -> Data {
        try collectBytes { try write(meshes: meshes, units: units, to: $0) }
    }

    func `import`(_ data: Data) throws -> ImportedExchangeModel {
        try self.import(BorrowedBytes(data))
    }
}

private extension IGESExchange {
    func export(meshes: [BodyID: Mesh], units: UnitSystem = .meters) throws -> Data {
        try collectBytes { try write(meshes: meshes, units: units, to: $0) }
    }

    func `import`(_ data: Data) throws -> ImportedExchangeModel {
        try self.import(BorrowedBytes(data))
    }
}

private extension ThreeMFExchange {
    func export(meshes: [BodyID: Mesh], unit: LengthUnit = .meter) throws -> Data {
        try collectBytes { try write(meshes: meshes, unit: unit, to: $0) }
    }

    func `import`(_ data: Data, fallbackUnit: LengthUnit = .millimeter) throws -> ImportedExchangeModel {
        try self.import(BorrowedBytes(data), fallbackUnit: fallbackUnit)
    }
}

private extension OBJExchange {
    func export(meshes: [BodyID: Mesh], unit: LengthUnit = .meter) throws -> Data {
        try collectBytes { try write(meshes: meshes, unit: unit, to: $0) }
    }

    func `import`(_ data: Data, unit: LengthUnit = .meter) throws -> ImportedExchangeModel {
        try self.import(BorrowedBytes(data), unit: unit)
    }
}

private extension DXFExchange {
    func export(meshes: [BodyID: Mesh], unit: LengthUnit = .meter) throws -> Data {
        try collectBytes { try write(meshes: meshes, unit: unit, to: $0) }
    }

    func `import`(_ data: Data, unit: LengthUnit = .meter) throws -> ImportedExchangeModel {
        try self.import(BorrowedBytes(data), unit: unit)
    }
}

private extension SVGExchange {
    func export(meshes: [BodyID: Mesh], unit: LengthUnit = .meter) throws -> Data {
        try collectBytes { try write(meshes: meshes, unit: unit, to: $0) }
    }

    func `import`(_ data: Data, unit: LengthUnit = .meter) throws -> ImportedExchangeModel {
        try self.import(BorrowedBytes(data), unit: unit)
    }
}

private extension GLBExporter {
    func export(meshes: [BodyID: Mesh]) throws -> Data {
        try collectBytes { try write(meshes: meshes, to: $0) }
    }
}

private extension USDExporter {
    func export(meshes: [BodyID: Mesh], encoding: USDEncoding, unit: LengthUnit = .meter) throws -> Data {
        try collectBytes { try write(meshes: meshes, encoding: encoding, unit: unit, to: $0) }
    }
}

private extension PDFExporter {
    func export(meshes: [BodyID: Mesh], title: String = "Swift-CAD Export") throws -> Data {
        try collectBytes { try write(meshes: meshes, title: title, to: $0) }
    }
}

private extension NativePackageStore {
    func packageData(for document: CADDocument) throws -> Data {
        try collectBytes { try writePackage(for: document, to: $0) }
    }

    func loadDocument(fromPackageData data: Data) throws -> CADDocument {
        try loadDocument(from: BorrowedBytes(data))
    }
}

private extension OfficialFormatExchange {
    func export(_ evaluatedDocument: EvaluatedDocument, as format: ExchangeFileFormat) throws -> Data {
        try collectBytes { try write(evaluatedDocument, as: format, to: $0) }
    }

    func `import`(_ data: Data, as format: ExchangeFileFormat) throws -> ImportedExchangeModel {
        try self.import(BorrowedBytes(data), as: format)
    }
}

@Suite("CADExchange")
struct CADExchangeTests {
    @Test(.timeLimit(.minutes(1)))
    func binarySTLExporterWritesExpectedSize() throws {
        let bodyID = BodyID()
        let mesh = Mesh(
            positions: [
                Point3D(x: 0.0, y: 0.0, z: 0.0),
                Point3D(x: 1.0, y: 0.0, z: 0.0),
                Point3D(x: 0.0, y: 1.0, z: 0.0)
            ],
            normals: [],
            indices: [0, 1, 2]
        )

        let data = try STLExporter(tolerance: .standard).exportBinary(meshes: [bodyID: mesh])
        #expect(data.count == 84 + 50)
    }

    @Test(.timeLimit(.minutes(1)))
    func stlImporterNormalizesOrComputesFacetNormals() throws {
        let nonUnitNormalData = binarySTLWithFacetNormal(Vector3D(x: 0.0, y: 0.0, z: 2.0))
        let computedNormalData = binarySTLWithFacetNormal(.zero)

        let nonUnitModel = try STLExporter(tolerance: .standard).importBinary(nonUnitNormalData)
        let computedModel = try STLExporter(tolerance: .standard).importBinary(computedNormalData)
        let nonUnitNormal = try #require(nonUnitModel.meshes.values.first?.normals.first)
        let computedNormal = try #require(computedModel.meshes.values.first?.normals.first)

        #expect(abs(nonUnitNormal.length - 1.0) < 1.0e-12)
        #expect(nonUnitNormal.z > 0.9)
        #expect(abs(computedNormal.length - 1.0) < 1.0e-12)
        #expect(computedNormal.z > 0.9)
    }

    @Test(.timeLimit(.minutes(1)))
    func stlImporterRejectsFacetNormalsOpposingTriangleWinding() {
        let data = binarySTLWithFacetNormal(-Vector3D.unitZ)

        #expect(throws: ImportError.self) {
            _ = try STLExporter(tolerance: .standard).importBinary(data)
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func stlImporterRejectsPayloadSizeMismatch() throws {
        let validData = try STLExporter(tolerance: .standard).exportBinary(meshes: [BodyID(): unitTriangleMesh(unit: .meter)])
        var dataWithTrailingByte = validData
        dataWithTrailingByte.append(0)
        let truncatedData = Data(validData.dropLast())

        #expect(throws: ImportError.self) {
            _ = try STLExporter(tolerance: .standard).importBinary(dataWithTrailingByte)
        }
        #expect(throws: ImportError.self) {
            _ = try STLExporter(tolerance: .standard).importBinary(truncatedData)
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func stlImporterRejectsTriangleCountBeyondMeshIndexRange() throws {
        let oversizedHeader = binarySTLHeaderOnly(triangleCount: UInt32.max)

        do {
            _ = try STLExporter(tolerance: .standard).importBinary(oversizedHeader)
            Issue.record("Expected oversized STL triangle count to fail.")
        } catch let ImportError.invalidData(message) {
            #expect(message == "Binary STL triangle count exceeds UInt32 index range.")
        } catch {
            Issue.record("Unexpected error: \(error).")
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func stlImporterRejectsUnsupportedFacetAttributes() throws {
        var data = try STLExporter(tolerance: .standard).exportBinary(meshes: [BodyID(): unitTriangleMesh(unit: .meter)])
        data.replaceSubrange((data.count - 2)..<data.count, with: Data([0x01, 0x00]))

        #expect(throws: ImportError.self) {
            _ = try STLExporter(tolerance: .standard).importBinary(data)
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func float32MeshExportersRejectCoordinatesOutsideFloat32Range() {
        let huge = Double(Float32.greatestFiniteMagnitude) * 2.0
        let mesh = Mesh(
            positions: [
                Point3D(x: 0.0, y: 0.0, z: 0.0),
                Point3D(x: huge, y: 0.0, z: 0.0),
                Point3D(x: 0.0, y: 1.0, z: 0.0)
            ],
            normals: [],
            indices: [0, 1, 2]
        )

        #expect(throws: ExportError.self) {
            _ = try STLExporter(tolerance: .standard).exportBinary(meshes: [BodyID(): mesh])
        }
        #expect(throws: ExportError.self) {
            _ = try GLBExporter(tolerance: .standard).export(meshes: [BodyID(): mesh])
        }
        #expect(throws: ExportError.self) {
            _ = try USDExporter(tolerance: .standard).export(meshes: [BodyID(): mesh], encoding: .usda)
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func textAndPackageExportersWriteIncrementallyToByteSink() throws {
        let mesh = unitTriangleMesh(unit: .meter)
        let meshes = [BodyID(): mesh]

        let objSink = RecordingByteSink()
        try OBJExchange(tolerance: .standard).write(meshes: meshes, to: objSink)
        #expect(objSink.writeCount > 1)

        let dxfSink = RecordingByteSink()
        try DXFExchange(tolerance: .standard).write(meshes: meshes, to: dxfSink)
        #expect(dxfSink.writeCount > 1)

        let svgSink = RecordingByteSink()
        try SVGExchange(tolerance: .standard).write(meshes: meshes, to: svgSink)
        #expect(svgSink.writeCount > 1)

        let usdSink = RecordingByteSink()
        try USDExporter(tolerance: .standard).write(meshes: meshes, encoding: .usda, to: usdSink)
        #expect(usdSink.writeCount == 1)

        let threeMFSink = RecordingByteSink()
        try ThreeMFExchange(tolerance: .standard).write(meshes: meshes, to: threeMFSink)
        #expect(threeMFSink.writeCount > 1)
        #expect(threeMFSink.maximumWriteSize < threeMFSink.bytes.count)
    }

    @Test(.timeLimit(.minutes(1)))
    func exactCadExportRejectsMeshInputs() {
        let mesh = unitTriangleMesh(unit: .meter)

        #expect(throws: KernelError.self) {
            _ = try STEPExchange(tolerance: .standard).export(meshes: [BodyID(): mesh])
        }
        #expect(throws: KernelError.self) {
            _ = try IGESExchange(tolerance: .standard).export(meshes: [BodyID(): mesh])
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func textMeshExportersRejectNonFiniteTargetUnitCoordinates() {
        let mesh = largeFiniteTriangleMeshThatOverflowsMillimeters()

        #expect(throws: ExportError.self) {
            _ = try OBJExchange(tolerance: .standard).export(meshes: [BodyID(): mesh], unit: .millimeter)
        }
        #expect(throws: ExportError.self) {
            _ = try ThreeMFExchange(tolerance: .standard).export(meshes: [BodyID(): mesh], unit: .millimeter)
        }
        #expect(throws: ExportError.self) {
            _ = try DXFExchange(tolerance: .standard).export(meshes: [BodyID(): mesh], unit: .millimeter)
        }
        #expect(throws: ExportError.self) {
            _ = try SVGExchange(tolerance: .standard).export(meshes: [BodyID(): mesh], unit: .millimeter)
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func glbExporterOmitsNormalsWhenMergedMeshesHaveMixedNormalAvailability() throws {
        let meshWithoutNormals = unitTriangleMesh(unit: .meter)
        let meshWithNormals = Mesh(
            positions: [
                Point3D(x: 0.0, y: 0.0, z: 1.0),
                Point3D(x: 1.0, y: 0.0, z: 1.0),
                Point3D(x: 0.0, y: 1.0, z: 1.0)
            ],
            normals: Array(repeating: Vector3D.unitZ, count: 3),
            indices: [0, 1, 2]
        )

        let data = try GLBExporter(tolerance: .standard).export(meshes: [
            BodyID(): meshWithoutNormals,
            BodyID(): meshWithNormals
        ])
        let json = try glbJSONText(from: data)

        #expect(!json.contains("\"NORMAL\""))
    }

    @Test(.timeLimit(.minutes(1)))
    func glbExporterAccessorBoundsMatchStoredFloat32Positions() throws {
        let roundedInput = 0.1
        let mesh = Mesh(
            positions: [
                Point3D(x: roundedInput, y: 0.0, z: 0.0),
                Point3D(x: 1.0, y: 0.0, z: 0.0),
                Point3D(x: roundedInput, y: 1.0, z: 0.0)
            ],
            normals: [],
            indices: [0, 1, 2]
        )

        let data = try GLBExporter(tolerance: .standard).export(meshes: [BodyID(): mesh])
        let json = try glbJSONText(from: data)
        let rootObject = try JSONSerialization.jsonObject(with: Data(json.utf8))
        let root = try #require(rootObject as? [String: Any])
        let accessors = try #require(root["accessors"] as? [[String: Any]])
        let positionAccessor = try #require(accessors.first)
        let minValues = try #require(positionAccessor["min"] as? [Any])
        let minX = try #require(minValues.first as? NSNumber)

        #expect(abs(minX.doubleValue - Double(Float32(roundedInput))) < 1.0e-15)
    }

    @Test(.timeLimit(.minutes(1)))
    func pdfExporterEscapesLiteralStringControlCharacters() throws {
        let title = "A\nB\rC\tD\u{08}E\u{0C}F (G) \\ H"

        let data = try PDFExporter(tolerance: .standard).export(
            meshes: [BodyID(): unitTriangleMesh(unit: .meter)],
            title: title
        )
        let text = try #require(String(data: data, encoding: .utf8))

        #expect(text.contains("(A\\nB\\rC\\tD\\bE\\fF \\(G\\) \\\\ H) Tj"))
        #expect(!text.contains("(A\nB"))
    }

    @Test(.timeLimit(.minutes(1)))
    func pdfExporterWritesEveryTriangleAsAFittedVectorPathWithAValidCrossReference() throws {
        let mesh = Mesh(
            positions: [
                Point3D(x: 0.0, y: 0.0, z: 0.0),
                Point3D(x: 0.0, y: 2.0, z: 0.0),
                Point3D(x: 0.0, y: 0.0, z: 3.0),
                Point3D(x: 0.0, y: 2.0, z: 3.0),
            ],
            normals: [],
            indices: [0, 1, 2, 1, 3, 2]
        )

        let data = try PDFExporter(tolerance: .standard).export(meshes: [BodyID(): mesh])
        let text = try #require(String(data: data, encoding: .utf8))

        #expect(text.contains("% Swift-CAD projection YZ"))
        #expect(text.components(separatedBy: " h S\n").count - 1 == 2)
        try validatePDFCrossReference(data)
        #if canImport(PDFKit)
        let document = try #require(PDFDocument(data: data))
        #expect(document.pageCount == 1)
        #endif
    }

    @Test(.timeLimit(.minutes(1)))
    func pdfExporterIsDeterministicAcrossDictionaryInsertionOrder() throws {
        let firstID = BodyID(try fixedUUID("00000000-0000-0000-0000-000000000001"))
        let secondID = BodyID(try fixedUUID("00000000-0000-0000-0000-000000000002"))
        let firstMesh = unitTriangleMesh(unit: .meter)
        let secondMesh = Mesh(
            positions: firstMesh.positions.map { Point3D(x: $0.x + 5.0, y: $0.y, z: $0.z) },
            normals: [],
            indices: firstMesh.indices
        )
        let exporter = PDFExporter(tolerance: .standard)

        let forward = try exporter.export(meshes: Dictionary(uniqueKeysWithValues: [
            (firstID, firstMesh),
            (secondID, secondMesh),
        ]))
        let reverse = try exporter.export(meshes: Dictionary(uniqueKeysWithValues: [
            (secondID, secondMesh),
            (firstID, firstMesh),
        ]))

        #expect(forward == reverse)
    }

    @Test(.timeLimit(.minutes(1)))
    func pdfExporterEncodesUnicodeTitleAsUTF16BETextString() throws {
        let data = try PDFExporter(tolerance: .standard).export(
            meshes: [BodyID(): unitTriangleMesh(unit: .meter)],
            title: "CAD 設計"
        )
        let text = try #require(String(data: data, encoding: .utf8))

        #expect(text.contains("<FEFF00430041004400208A2D8A08> Tj"))
        #if canImport(PDFKit)
        #expect(PDFDocument(data: data) != nil)
        #endif
    }

    @Test(.timeLimit(.minutes(1)))
    func pdfExporterEnforcesEntityAndByteLimitsWithTypedFailures() throws {
        let mesh = unitTriangleMesh(unit: .meter)
        let entityLimited = PDFExporter(
            tolerance: .standard,
            resourceLimits: ExchangeResourceLimits(maximumEntities: 4)
        )
        let byteLimited = PDFExporter(
            tolerance: .standard,
            resourceLimits: ExchangeResourceLimits(maximumBytes: 128)
        )

        do {
            _ = try entityLimited.export(meshes: [BodyID(): mesh])
            Issue.record("Expected the PDF entity limit to reject the mesh.")
        } catch let error as KernelError {
            #expect(error.phase == .exchange)
            #expect(error.code == .resourceLimitExceeded)
        }
        do {
            _ = try byteLimited.export(meshes: [BodyID(): mesh])
            Issue.record("Expected the PDF byte limit to reject the output.")
        } catch let error as KernelError {
            #expect(error.phase == .exchange)
            #expect(error.code == .resourceLimitExceeded)
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func nativePackageRoundTripsSourceDocumentWithoutCaches() throws {
        let document = CADDocument(
            units: .millimeters,
            metadata: DocumentMetadata(
                createdAt: Date(timeIntervalSinceReferenceDate: 123.456789123),
                updatedAt: Date(timeIntervalSinceReferenceDate: 456.789123456)
            )
        )
        let store = NativePackageStore(tolerance: .standard)
        let packageData = try store.packageData(for: document)
        let loaded = try store.loadDocument(fromPackageData: packageData)

        #expect(loaded.id == document.id)
        #expect(loaded.schemaVersion == document.schemaVersion)
        #expect(loaded.units == document.units)
        #expect(loaded.metadata.createdAt == document.metadata.createdAt)
        #expect(loaded.metadata.updatedAt == document.metadata.updatedAt)
        let entries = try StoredZipArchive.readEntries(from: packageData)
        let documentData = try #require(entries["document.json"])
        let json = try #require(String(data: documentData, encoding: .utf8))
        #expect(!json.contains("\"caches\""))
    }

    @Test(.timeLimit(.minutes(1)))
    func nativePackageRoundTripsSweepSections() throws {
        let fixture = nativeSweepDocumentFixture()
        let store = NativePackageStore(tolerance: .standard)
        let packageData = try store.packageData(for: fixture.document)

        let loaded = try store.loadDocument(fromPackageData: packageData)
        let loadedFeature = try #require(loaded.designGraph.nodes[fixture.sweepID])
        guard case .sweep(let sweep) = loadedFeature.operation else {
            Issue.record("Expected loaded sweep feature.")
            return
        }

        #expect(sweep.sections == [.profile(ProfileReference(featureID: fixture.profileID))])
        #expect(sweep.path == SweepPathReference(featureID: fixture.pathID))
    }

    @Test(.timeLimit(.minutes(1)))
    func nativePackageRoundTripsLoftSectionSmoothTangentScale() throws {
        let fixture = nativeLoftDocumentFixture()
        let store = NativePackageStore(tolerance: .standard)
        let packageData = try store.packageData(for: fixture.document)

        let loaded = try store.loadDocument(fromPackageData: packageData)
        let loadedFeature = try #require(loaded.designGraph.nodes[fixture.loftID])
        guard case .loft(let loft) = loadedFeature.operation else {
            Issue.record("Expected loaded Loft feature.")
            return
        }

        #expect(loft.sections.map(\.featureID) == [
            fixture.firstProfileID,
            fixture.secondProfileID,
            fixture.thirdProfileID,
        ])
        #expect(loft.sections.map(\.smoothTangentScale) == [0.75, nil, nil])
        #expect(loft.sections.map(\.smoothTangentMode) == [.zero, .automatic, .automatic])
    }

    @Test(.timeLimit(.minutes(1)))
    func nativePackageRejectsInvalidLoftOptionValues() throws {
        let fixture = nativeLoftDocumentFixture()
        let store = NativePackageStore(tolerance: .standard)
        let packageData = try store.packageData(for: fixture.document)
        let entries = try StoredZipArchive.readEntries(from: packageData)
        let manifestData = try #require(entries["manifest.json"])
        let documentData = try #require(entries["document.json"])
        let invalidResultKindDocumentData = try documentDataBySettingLoftOption(
            "resultKind",
            to: "wire",
            in: documentData
        )
        let invalidSectionMatchingDocumentData = try documentDataBySettingLoftOption(
            "sectionMatching",
            to: "byArea",
            in: documentData
        )
        let invalidSmoothTangentScaleDocumentData = try documentDataBySettingLoftOption(
            "smoothTangentScale",
            to: 0.0,
            in: documentData
        )
        let invalidSectionSmoothTangentScaleDocumentData = try documentDataBySettingLoftSectionField(
            "smoothTangentScale",
            to: 0.0,
            sectionIndex: 0,
            in: documentData
        )
        let invalidSectionSmoothTangentModeDocumentData = try documentDataBySettingLoftSectionField(
            "smoothTangentMode",
            to: "flat",
            sectionIndex: 0,
            in: documentData
        )
        let booleanSmoothTangentScaleDocumentData = try documentDataBySettingLoftOption(
            "smoothTangentScale",
            to: true,
            in: documentData
        )
        let booleanSectionSmoothTangentScaleDocumentData = try documentDataBySettingLoftSectionField(
            "smoothTangentScale",
            to: true,
            sectionIndex: 0,
            in: documentData
        )
        let packageWithInvalidResultKind = try StoredZipArchive.make(entries: [
            StoredZipArchive.Entry(path: "manifest.json", data: manifestData),
            StoredZipArchive.Entry(path: "document.json", data: invalidResultKindDocumentData)
        ])
        let packageWithInvalidSectionMatching = try StoredZipArchive.make(entries: [
            StoredZipArchive.Entry(path: "manifest.json", data: manifestData),
            StoredZipArchive.Entry(path: "document.json", data: invalidSectionMatchingDocumentData)
        ])
        let packageWithInvalidSmoothTangentScale = try StoredZipArchive.make(entries: [
            StoredZipArchive.Entry(path: "manifest.json", data: manifestData),
            StoredZipArchive.Entry(path: "document.json", data: invalidSmoothTangentScaleDocumentData)
        ])
        let packageWithInvalidSectionSmoothTangentScale = try StoredZipArchive.make(entries: [
            StoredZipArchive.Entry(path: "manifest.json", data: manifestData),
            StoredZipArchive.Entry(path: "document.json", data: invalidSectionSmoothTangentScaleDocumentData)
        ])
        let packageWithInvalidSectionSmoothTangentMode = try StoredZipArchive.make(entries: [
            StoredZipArchive.Entry(path: "manifest.json", data: manifestData),
            StoredZipArchive.Entry(path: "document.json", data: invalidSectionSmoothTangentModeDocumentData)
        ])
        let packageWithBooleanSmoothTangentScale = try StoredZipArchive.make(entries: [
            StoredZipArchive.Entry(path: "manifest.json", data: manifestData),
            StoredZipArchive.Entry(path: "document.json", data: booleanSmoothTangentScaleDocumentData)
        ])
        let packageWithBooleanSectionSmoothTangentScale = try StoredZipArchive.make(entries: [
            StoredZipArchive.Entry(path: "manifest.json", data: manifestData),
            StoredZipArchive.Entry(path: "document.json", data: booleanSectionSmoothTangentScaleDocumentData)
        ])

        #expect(throws: SchemaError.self) {
            _ = try store.loadDocument(fromPackageData: packageWithInvalidResultKind)
        }
        #expect(throws: SchemaError.self) {
            _ = try store.loadDocument(fromPackageData: packageWithInvalidSectionMatching)
        }
        #expect(throws: SchemaError.self) {
            _ = try store.loadDocument(fromPackageData: packageWithInvalidSmoothTangentScale)
        }
        #expect(throws: SchemaError.self) {
            _ = try store.loadDocument(fromPackageData: packageWithInvalidSectionSmoothTangentScale)
        }
        #expect(throws: SchemaError.self) {
            _ = try store.loadDocument(fromPackageData: packageWithInvalidSectionSmoothTangentMode)
        }
        #expect(throws: SchemaError.self) {
            _ = try store.loadDocument(fromPackageData: packageWithBooleanSmoothTangentScale)
        }
        #expect(throws: SchemaError.self) {
            _ = try store.loadDocument(fromPackageData: packageWithBooleanSectionSmoothTangentScale)
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func nativePackageRoundTripsBooleanFeature() throws {
        let fixture = nativeBooleanDocumentFixture()
        let store = NativePackageStore(tolerance: .standard)
        let packageData = try store.packageData(for: fixture.document)

        let loaded = try store.loadDocument(fromPackageData: packageData)
        let loadedFeature = try #require(loaded.designGraph.nodes[fixture.booleanID])
        guard case .boolean(let boolean) = loadedFeature.operation else {
            Issue.record("Expected loaded boolean feature.")
            return
        }

        #expect(boolean.targets == [BooleanTargetReference(featureID: fixture.targetID)])
        #expect(boolean.tool == BooleanToolReference(featureID: fixture.toolID))
        #expect(boolean.operation == .difference)
        #expect(boolean.keepTools)
        #expect(loadedFeature.inputs == [
            FeatureInput(featureID: fixture.targetID, role: .target),
            FeatureInput(featureID: fixture.toolID, role: .body),
        ])
        #expect(loadedFeature.outputs == [FeatureOutput(role: .body)])
    }

    @Test(.timeLimit(.minutes(1)))
    func nativePackageRejectsLegacySweepProfilesField() throws {
        let fixture = nativeSweepDocumentFixture()
        let store = NativePackageStore(tolerance: .standard)
        let packageData = try store.packageData(for: fixture.document)
        let entries = try StoredZipArchive.readEntries(from: packageData)
        let manifestData = try #require(entries["manifest.json"])
        let documentData = try #require(entries["document.json"])
        let patchedDocumentData = try documentDataByAddingLegacySweepProfiles(
            to: documentData,
            profileID: fixture.profileID
        )
        let patchedPackageData = try StoredZipArchive.make(entries: [
            StoredZipArchive.Entry(path: "manifest.json", data: manifestData),
            StoredZipArchive.Entry(path: "document.json", data: patchedDocumentData)
        ])

        #expect(throws: SchemaError.self) {
            _ = try store.loadDocument(fromPackageData: patchedPackageData)
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func nativePackageRoundTripsSelectionDimensions() throws {
        let sketchID = FeatureID()
        let lineID = SketchEntityID()
        let pointID = SketchEntityID()
        let dimensionID = SelectionDimensionID()
        let pointDimensionID = SelectionDimensionID()
        let topologyDimensionID = SelectionDimensionID()
        let edgeTopologyDimensionID = SelectionDimensionID()
        let curve = CurveOutputReference(featureID: sketchID)
        let firstTopologyPoint = StableSubshapeReference(
            subshapeID: SubshapeID(featureID: sketchID, role: "vertex", ordinal: 0),
            geometrySignature: .vertex(point: Point3D(x: 0.0, y: 0.0, z: 0.0))
        )
        let secondTopologyPoint = StableSubshapeReference(
            subshapeID: SubshapeID(featureID: sketchID, role: "vertex", ordinal: 1),
            geometrySignature: .vertex(point: Point3D(x: 0.010, y: 0.0, z: 0.0))
        )
        let topologyEdge = StableSubshapeReference(
            subshapeID: SubshapeID(featureID: sketchID, role: "edge", ordinal: 0),
            geometrySignature: try .lineEdge(
                startPoint: .origin,
                endPoint: Point3D(x: 0.010, y: 0.0, z: 0.0)
            )
        )
        let document = CADDocument(
            units: .millimeters,
            designGraph: DesignGraph(
                nodes: [
                    sketchID: FeatureNode(
                        id: sketchID,
                        operation: .sketch(Sketch(
                            plane: .xy,
                            entities: [
                                lineID: .line(SketchLine(
                                    start: SketchPoint(
                                        x: .constant(.length(0.0, unit: .millimeter)),
                                        y: .constant(.length(0.0, unit: .millimeter))
                                    ),
                                    end: SketchPoint(
                                        x: .constant(.length(10.0, unit: .millimeter)),
                                        y: .constant(.length(0.0, unit: .millimeter))
                                    )
                                )),
                                pointID: .point(SketchPoint(
                                    x: .constant(.length(5.0, unit: .millimeter)),
                                    y: .constant(.length(0.0, unit: .millimeter))
                                )),
                            ]
                        )),
                        outputs: [
                            FeatureOutput(role: .profile),
                            FeatureOutput(role: .curve),
                        ]
                    )
                ],
                order: [sketchID]
            ),
            selectionDimensions: [
                SelectionDimension(
                    id: dimensionID,
                    name: "Line length",
                    kind: .distance,
                    first: .curve(.parameter(CurveParameterReference(curve: curve, parameter: 0.0))),
                    second: .curve(.parameter(CurveParameterReference(curve: curve, parameter: 0.010))),
                    target: .constant(.length(10.0, unit: .millimeter))
                ),
                SelectionDimension(
                    id: pointDimensionID,
                    name: "Point to line start",
                    kind: .distance,
                    first: .sketchPoint(SketchPointSelectionReference(
                        featureID: sketchID,
                        entityID: pointID
                    )),
                    second: .curve(.parameter(CurveParameterReference(curve: curve, parameter: 0.0))),
                    target: .constant(.length(5.0, unit: .millimeter))
                ),
                SelectionDimension(
                    id: topologyDimensionID,
                    name: "Stable topology distance",
                    kind: .distance,
                    first: .subshape(firstTopologyPoint),
                    second: .subshape(secondTopologyPoint),
                    target: .constant(.length(10.0, unit: .millimeter))
                ),
                SelectionDimension(
                    id: edgeTopologyDimensionID,
                    name: "Stable topology edge distance",
                    kind: .distance,
                    first: .subshape(topologyEdge),
                    second: .subshape(secondTopologyPoint),
                    target: .constant(.length(0.0, unit: .millimeter))
                )
            ]
        )
        let store = NativePackageStore(tolerance: .standard)
        let packageData = try store.packageData(for: document)
        let entries = try StoredZipArchive.readEntries(from: packageData)
        let manifestData = try #require(entries["manifest.json"])
        let documentData = try #require(entries["document.json"])
        let loaded = try store.loadDocument(fromPackageData: packageData)

        #expect(loaded.selectionDimensions == document.selectionDimensions)

        let documentWithUnsupportedDimensionField = try documentDataByAddingUnsupportedSelectionDimensionField(
            to: documentData
        )
        let packageWithUnsupportedDimensionField = try StoredZipArchive.make(entries: [
            StoredZipArchive.Entry(path: "manifest.json", data: manifestData),
            StoredZipArchive.Entry(path: "document.json", data: documentWithUnsupportedDimensionField)
        ])
        #expect(throws: SchemaError.self) {
            _ = try store.loadDocument(fromPackageData: packageWithUnsupportedDimensionField)
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func nativePackageRoundTripsSketchArcEntity() throws {
        let sketchID = FeatureID()
        let arcID = SketchEntityID()
        let document = CADDocument(
            units: .meters,
            designGraph: DesignGraph(
                nodes: [
                    sketchID: FeatureNode(
                        id: sketchID,
                        operation: .sketch(Sketch(
                            plane: .xy,
                            entities: [
                                arcID: .arc(SketchArc(
                                    center: SketchPoint(
                                        x: .constant(.length(0.0, unit: .meter)),
                                        y: .constant(.length(0.0, unit: .meter))
                                    ),
                                    radius: .constant(.length(1.0, unit: .meter)),
                                    startAngle: .constant(.angle(0.0, unit: .degree)),
                                    endAngle: .constant(.angle(90.0, unit: .degree))
                                ))
                            ]
                        )),
                        outputs: [FeatureOutput(role: .profile)]
                    )
                ],
                order: [sketchID]
            )
        )

        let store = NativePackageStore(tolerance: .standard)
        let packageData = try store.packageData(for: document)
        let loaded = try store.loadDocument(fromPackageData: packageData)
        let loadedFeature = try #require(loaded.designGraph.nodes[sketchID])
        guard case .sketch(let loadedSketch) = loadedFeature.operation,
              case .arc(let loadedArc) = loadedSketch.entities[arcID] else {
            Issue.record("Expected the native package to preserve the sketch arc entity.")
            return
        }

        #expect(loadedArc.center == SketchPoint(
            x: .constant(.length(0.0, unit: .meter)),
            y: .constant(.length(0.0, unit: .meter))
        ))
    }

    @Test(.timeLimit(.minutes(1)))
    func nativePackageBytesAreStableForInsertionOrderIndependentDictionaries() throws {
        let store = NativePackageStore(tolerance: .standard)
        let first = try nativePackageStabilityDocument(reversedDictionaries: false)
        let second = try nativePackageStabilityDocument(reversedDictionaries: true)

        let firstData = try store.packageData(for: first)
        let secondData = try store.packageData(for: second)

        #expect(firstData == secondData)
    }

    @Test(.timeLimit(.minutes(1)))
    func nativePackageRejectsUnsupportedCacheFields() throws {
        let document = CADDocument(units: .millimeters)
        let store = NativePackageStore(tolerance: .standard)
        let packageData = try store.packageData(for: document)
        let entries = try StoredZipArchive.readEntries(from: packageData)
        let manifestData = try #require(entries["manifest.json"])
        let documentData = try #require(entries["document.json"])
        let documentWithCachesData = try jsonData(
            byAdding: ["caches": ["meshes": [:]]],
            to: documentData
        )
        let manifestWithCacheManifestData = try jsonData(
            byAdding: ["cacheManifest": "caches/manifest.json"],
            to: manifestData
        )

        let packageWithDocumentCaches = try StoredZipArchive.make(entries: [
            StoredZipArchive.Entry(path: "manifest.json", data: manifestData),
            StoredZipArchive.Entry(path: "document.json", data: documentWithCachesData)
        ])
        let packageWithCacheManifest = try StoredZipArchive.make(entries: [
            StoredZipArchive.Entry(path: "manifest.json", data: manifestWithCacheManifestData),
            StoredZipArchive.Entry(path: "document.json", data: documentData)
        ])
        let packageWithCacheEntry = try StoredZipArchive.make(entries: [
            StoredZipArchive.Entry(path: "manifest.json", data: manifestData),
            StoredZipArchive.Entry(path: "document.json", data: documentData),
            StoredZipArchive.Entry(path: "caches/mesh.bin", data: Data([0x00]))
        ])
        let packageWithAttachmentEntry = try StoredZipArchive.make(entries: [
            StoredZipArchive.Entry(path: "manifest.json", data: manifestData),
            StoredZipArchive.Entry(path: "document.json", data: documentData),
            StoredZipArchive.Entry(path: "attachments/readme.txt", data: Data("ignored".utf8))
        ])

        #expect(throws: SchemaError.self) {
            _ = try store.loadDocument(fromPackageData: packageWithDocumentCaches)
        }
        #expect(throws: SchemaError.self) {
            _ = try store.loadDocument(fromPackageData: packageWithCacheManifest)
        }
        #expect(throws: SchemaError.self) {
            _ = try store.loadDocument(fromPackageData: packageWithCacheEntry)
        }
        #expect(throws: SchemaError.self) {
            _ = try store.loadDocument(fromPackageData: packageWithAttachmentEntry)
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func nativePackageRejectsUnreferencedLocalPackageEntries() throws {
        let document = CADDocument(units: .millimeters)
        let store = NativePackageStore(tolerance: .standard)
        let packageData = try store.packageData(for: document)
        let entries = try StoredZipArchive.readEntries(from: packageData)
        let manifestData = try #require(entries["manifest.json"])
        let documentData = try #require(entries["document.json"])
        let packageWithHiddenEntry = storedZipArchiveWithUnreferencedLocalEntry(visibleEntries: [
            (path: "manifest.json", data: manifestData),
            (path: "document.json", data: documentData)
        ])

        #expect(throws: SchemaError.self) {
            _ = try store.loadDocument(fromPackageData: packageWithHiddenEntry)
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func nativePackageRejectsManifestDocumentSchemaMismatch() throws {
        let document = CADDocument(units: .millimeters)
        let store = NativePackageStore(tolerance: .standard)
        let packageData = try store.packageData(for: document)
        let entries = try StoredZipArchive.readEntries(from: packageData)
        let manifestData = try #require(entries["manifest.json"])
        let documentData = try #require(entries["document.json"])
        let patchedManifestData = try manifestDataWithFutureSchema(from: manifestData)
        let patchedPackageData = try StoredZipArchive.make(entries: [
            StoredZipArchive.Entry(path: "manifest.json", data: patchedManifestData),
            StoredZipArchive.Entry(path: "document.json", data: documentData)
        ])

        #expect(throws: SchemaError.self) {
            _ = try store.loadDocument(fromPackageData: patchedPackageData)
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func nativePackageRejectsInvalidDocumentMetadata() {
        let document = CADDocument(
            units: .millimeters,
            metadata: DocumentMetadata(
                createdAt: Date(timeIntervalSinceReferenceDate: 100.0),
                updatedAt: Date(timeIntervalSinceReferenceDate: 99.0)
            )
        )

        #expect(throws: SchemaError.self) {
            _ = try NativePackageStore(tolerance: .standard).packageData(for: document)
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func nativePackageRejectsInvalidManifestTimestamps() throws {
        let document = CADDocument(
            units: .millimeters,
            metadata: DocumentMetadata(
                createdAt: Date(timeIntervalSinceReferenceDate: 0.0),
                updatedAt: Date(timeIntervalSinceReferenceDate: 3_600.0)
            )
        )
        let store = NativePackageStore(tolerance: .standard)
        let packageData = try store.packageData(for: document)
        let entries = try StoredZipArchive.readEntries(from: packageData)
        let manifestData = try #require(entries["manifest.json"])
        let documentData = try #require(entries["document.json"])
        let manifestWithEarlierUpdatedAt = try jsonData(
            byAdding: ["updatedAt": "2000-12-31T00:00:00Z"],
            to: manifestData
        )
        let manifestWithMismatchedCreatedAt = try jsonData(
            byAdding: ["createdAt": "2001-01-01T00:00:01Z"],
            to: manifestData
        )
        let packageWithInvalidOrder = try StoredZipArchive.make(entries: [
            StoredZipArchive.Entry(path: "manifest.json", data: manifestWithEarlierUpdatedAt),
            StoredZipArchive.Entry(path: "document.json", data: documentData)
        ])
        let packageWithMetadataMismatch = try StoredZipArchive.make(entries: [
            StoredZipArchive.Entry(path: "manifest.json", data: manifestWithMismatchedCreatedAt),
            StoredZipArchive.Entry(path: "document.json", data: documentData)
        ])

        #expect(throws: SchemaError.self) {
            _ = try store.loadDocument(fromPackageData: packageWithInvalidOrder)
        }
        #expect(throws: SchemaError.self) {
            _ = try store.loadDocument(fromPackageData: packageWithMetadataMismatch)
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func nativePackageRejectsRemovedISO8601Timestamps() throws {
        let document = CADDocument(
            units: .millimeters,
            metadata: DocumentMetadata(
                createdAt: Date(timeIntervalSinceReferenceDate: 0.0),
                updatedAt: Date(timeIntervalSinceReferenceDate: 3_600.0)
            )
        )
        let store = NativePackageStore(tolerance: .standard)
        let packageData = try store.packageData(for: document)
        let entries = try StoredZipArchive.readEntries(from: packageData)
        let manifestData = try #require(entries["manifest.json"])
        let documentData = try #require(entries["document.json"])
        let legacyManifestData = try jsonData(
            byAdding: [
                "createdAt": "2001-01-01T00:00:00Z",
                "updatedAt": "2001-01-01T01:00:00Z"
            ],
            to: manifestData
        )
        let legacyDocumentData = try documentDataWithMetadata(
            createdAt: "2001-01-01T00:00:00Z",
            updatedAt: "2001-01-01T01:00:00Z",
            from: documentData
        )
        let legacyPackageData = try StoredZipArchive.make(entries: [
            StoredZipArchive.Entry(path: "manifest.json", data: legacyManifestData),
            StoredZipArchive.Entry(path: "document.json", data: legacyDocumentData)
        ])

        #expect(throws: SchemaError.self) {
            _ = try store.loadDocument(fromPackageData: legacyPackageData)
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func nativePackageRejectsInactiveUnionPayloads() throws {
        let sketchID = FeatureID()
        let document = CADDocument(
            units: .millimeters,
            designGraph: DesignGraph(
                nodes: [
                    sketchID: FeatureNode(
                        id: sketchID,
                        operation: .sketch(Sketch(plane: .xy)),
                        outputs: [FeatureOutput(role: .profile)]
                    )
                ],
                order: [sketchID]
            )
        )
        let store = NativePackageStore(tolerance: .standard)
        let packageData = try store.packageData(for: document)
        let entries = try StoredZipArchive.readEntries(from: packageData)
        let manifestData = try #require(entries["manifest.json"])
        let documentData = try #require(entries["document.json"])
        let patchedDocumentData = try documentDataWithInactiveOperationPayload(from: documentData)
        let patchedPackageData = try StoredZipArchive.make(entries: [
            StoredZipArchive.Entry(path: "manifest.json", data: manifestData),
            StoredZipArchive.Entry(path: "document.json", data: patchedDocumentData)
        ])

        #expect(throws: SchemaError.self) {
            _ = try store.loadDocument(fromPackageData: patchedPackageData)
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func nativePackageWrapsMalformedJSONAsSchemaError() throws {
        let document = CADDocument(units: .millimeters)
        let store = NativePackageStore(tolerance: .standard)
        let packageData = try store.packageData(for: document)
        let entries = try StoredZipArchive.readEntries(from: packageData)
        let manifestData = try #require(entries["manifest.json"])
        let documentData = try #require(entries["document.json"])
        let badManifestPackage = try StoredZipArchive.make(entries: [
            StoredZipArchive.Entry(path: "manifest.json", data: Data("{".utf8)),
            StoredZipArchive.Entry(path: "document.json", data: documentData)
        ])
        let badDocumentPackage = try StoredZipArchive.make(entries: [
            StoredZipArchive.Entry(path: "manifest.json", data: manifestData),
            StoredZipArchive.Entry(path: "document.json", data: Data("{".utf8))
        ])

        #expect(throws: SchemaError.self) {
            _ = try store.loadDocument(fromPackageData: badManifestPackage)
        }
        #expect(throws: SchemaError.self) {
            _ = try store.loadDocument(fromPackageData: badDocumentPackage)
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func nativePackageRejectsDuplicateTopLevelJSONKeys() throws {
        let document = CADDocument(units: .millimeters)
        let store = NativePackageStore(tolerance: .standard)
        let packageData = try store.packageData(for: document)
        let entries = try StoredZipArchive.readEntries(from: packageData)
        let manifestData = try #require(entries["manifest.json"])
        let documentData = try #require(entries["document.json"])
        let manifestWithDuplicateFormat = try jsonDataWithDuplicateTopLevelStringField(
            named: "format",
            in: manifestData
        )
        let documentWithDuplicateID = try jsonDataWithDuplicateTopLevelStringField(
            named: "id",
            in: documentData
        )
        let packageWithDuplicateManifestKey = try StoredZipArchive.make(entries: [
            StoredZipArchive.Entry(path: "manifest.json", data: manifestWithDuplicateFormat),
            StoredZipArchive.Entry(path: "document.json", data: documentData)
        ])
        let packageWithDuplicateDocumentKey = try StoredZipArchive.make(entries: [
            StoredZipArchive.Entry(path: "manifest.json", data: manifestData),
            StoredZipArchive.Entry(path: "document.json", data: documentWithDuplicateID)
        ])

        #expect(throws: SchemaError.self) {
            _ = try store.loadDocument(fromPackageData: packageWithDuplicateManifestKey)
        }
        #expect(throws: SchemaError.self) {
            _ = try store.loadDocument(fromPackageData: packageWithDuplicateDocumentKey)
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func nativePackageRejectsNestedUnsupportedJSONKeys() throws {
        let document = CADDocument(units: .millimeters)
        let store = NativePackageStore(tolerance: .standard)
        let packageData = try store.packageData(for: document)
        let entries = try StoredZipArchive.readEntries(from: packageData)
        let manifestData = try #require(entries["manifest.json"])
        let documentData = try #require(entries["document.json"])
        let manifestWithUnsupportedSchemaVersionField = try jsonData(
            byAdding: ["unexpected": true],
            at: ["schemaVersion"],
            to: manifestData
        )
        let documentWithUnsupportedMetadataField = try jsonData(
            byAdding: ["unexpected": true],
            at: ["metadata"],
            to: documentData
        )

        let packageWithUnsupportedManifestNestedKey = try StoredZipArchive.make(entries: [
            StoredZipArchive.Entry(path: "manifest.json", data: manifestWithUnsupportedSchemaVersionField),
            StoredZipArchive.Entry(path: "document.json", data: documentData)
        ])
        let packageWithUnsupportedDocumentNestedKey = try StoredZipArchive.make(entries: [
            StoredZipArchive.Entry(path: "manifest.json", data: manifestData),
            StoredZipArchive.Entry(path: "document.json", data: documentWithUnsupportedMetadataField)
        ])

        #expect(throws: SchemaError.self) {
            _ = try store.loadDocument(fromPackageData: packageWithUnsupportedManifestNestedKey)
        }
        #expect(throws: SchemaError.self) {
            _ = try store.loadDocument(fromPackageData: packageWithUnsupportedDocumentNestedKey)
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func nativePackageRejectsUnsupportedFieldsInsideArrayEncodedDictionaries() throws {
        let parameterID = ParameterID()
        let sketchID = FeatureID()
        let document = CADDocument(
            units: .millimeters,
            parameters: ParameterTable(parameters: [
                parameterID: Parameter(
                    id: parameterID,
                    name: "width",
                    expression: .constant(.length(10.0, unit: .millimeter)),
                    kind: .length
                )
            ]),
            designGraph: DesignGraph(
                nodes: [
                    sketchID: FeatureNode(
                        id: sketchID,
                        operation: .sketch(Sketch(plane: .xy)),
                        outputs: [FeatureOutput(role: .profile)]
                    )
                ],
                order: [sketchID]
            )
        )
        let store = NativePackageStore(tolerance: .standard)
        let packageData = try store.packageData(for: document)
        let entries = try StoredZipArchive.readEntries(from: packageData)
        let manifestData = try #require(entries["manifest.json"])
        let documentData = try #require(entries["document.json"])
        let documentWithUnsupportedParameterField = try jsonData(
            byAdding: ["unexpected": true],
            atFirstDynamicDictionaryValue: ["parameters", "parameters"],
            to: documentData
        )
        let documentWithUnsupportedNodeField = try jsonData(
            byAdding: ["unexpected": true],
            atFirstDynamicDictionaryValue: ["designGraph", "nodes"],
            to: documentData
        )

        let packageWithUnsupportedParameterField = try StoredZipArchive.make(entries: [
            StoredZipArchive.Entry(path: "manifest.json", data: manifestData),
            StoredZipArchive.Entry(path: "document.json", data: documentWithUnsupportedParameterField)
        ])
        let packageWithUnsupportedNodeField = try StoredZipArchive.make(entries: [
            StoredZipArchive.Entry(path: "manifest.json", data: manifestData),
            StoredZipArchive.Entry(path: "document.json", data: documentWithUnsupportedNodeField)
        ])

        #expect(throws: SchemaError.self) {
            _ = try store.loadDocument(fromPackageData: packageWithUnsupportedParameterField)
        }
        #expect(throws: SchemaError.self) {
            _ = try store.loadDocument(fromPackageData: packageWithUnsupportedNodeField)
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func nativePackageRejectsDuplicateKeysInsideArrayEncodedDictionaries() throws {
        let parameterID = ParameterID()
        let sketchID = FeatureID()
        let pointID = SketchEntityID()
        let document = CADDocument(
            units: .millimeters,
            parameters: ParameterTable(parameters: [
                parameterID: Parameter(
                    id: parameterID,
                    name: "width",
                    expression: .constant(.length(10.0, unit: .millimeter)),
                    kind: .length
                )
            ]),
            designGraph: DesignGraph(
                nodes: [
                    sketchID: FeatureNode(
                        id: sketchID,
                        operation: .sketch(Sketch(
                            plane: .xy,
                            entities: [
                                pointID: .point(SketchPoint(
                                    x: .constant(.length(0.0, unit: .millimeter)),
                                    y: .constant(.length(0.0, unit: .millimeter))
                                ))
                            ]
                        )),
                        outputs: [FeatureOutput(role: .profile)]
                    )
                ],
                order: [sketchID]
            )
        )
        let store = NativePackageStore(tolerance: .standard)
        let packageData = try store.packageData(for: document)
        let entries = try StoredZipArchive.readEntries(from: packageData)
        let manifestData = try #require(entries["manifest.json"])
        let documentData = try #require(entries["document.json"])
        let documentWithDuplicateParameterKey = try jsonData(
            byDuplicatingFirstDynamicDictionaryEntryAt: ["parameters", "parameters"],
            in: documentData
        )
        let documentWithDuplicateNodeKey = try jsonData(
            byDuplicatingFirstDynamicDictionaryEntryAt: ["designGraph", "nodes"],
            in: documentData
        )
        let documentWithDuplicateSketchEntityKey = try jsonDataByDuplicatingFirstSketchEntityEntry(in: documentData)

        let packageWithDuplicateParameterKey = try StoredZipArchive.make(entries: [
            StoredZipArchive.Entry(path: "manifest.json", data: manifestData),
            StoredZipArchive.Entry(path: "document.json", data: documentWithDuplicateParameterKey)
        ])
        let packageWithDuplicateNodeKey = try StoredZipArchive.make(entries: [
            StoredZipArchive.Entry(path: "manifest.json", data: manifestData),
            StoredZipArchive.Entry(path: "document.json", data: documentWithDuplicateNodeKey)
        ])
        let packageWithDuplicateSketchEntityKey = try StoredZipArchive.make(entries: [
            StoredZipArchive.Entry(path: "manifest.json", data: manifestData),
            StoredZipArchive.Entry(path: "document.json", data: documentWithDuplicateSketchEntityKey)
        ])

        #expect(throws: SchemaError.self) {
            _ = try store.loadDocument(fromPackageData: packageWithDuplicateParameterKey)
        }
        #expect(throws: SchemaError.self) {
            _ = try store.loadDocument(fromPackageData: packageWithDuplicateNodeKey)
        }
        #expect(throws: SchemaError.self) {
            _ = try store.loadDocument(fromPackageData: packageWithDuplicateSketchEntityKey)
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func nativePackageRejectsDuplicateLogicalIDKeysInsideArrayEncodedDictionaries() throws {
        let parameterID = ParameterID()
        let sketchID = FeatureID()
        let pointID = SketchEntityID()
        let document = CADDocument(
            units: .millimeters,
            parameters: ParameterTable(parameters: [
                parameterID: Parameter(
                    id: parameterID,
                    name: "width",
                    expression: .constant(.length(10.0, unit: .millimeter)),
                    kind: .length
                )
            ]),
            designGraph: DesignGraph(
                nodes: [
                    sketchID: FeatureNode(
                        id: sketchID,
                        operation: .sketch(Sketch(
                            plane: .xy,
                            entities: [
                                pointID: .point(SketchPoint(
                                    x: .constant(.length(0.0, unit: .millimeter)),
                                    y: .constant(.length(0.0, unit: .millimeter))
                                ))
                            ]
                        )),
                        outputs: [FeatureOutput(role: .profile)]
                    )
                ],
                order: [sketchID]
            )
        )
        let store = NativePackageStore(tolerance: .standard)
        let packageData = try store.packageData(for: document)
        let entries = try StoredZipArchive.readEntries(from: packageData)
        let manifestData = try #require(entries["manifest.json"])
        let documentData = try #require(entries["document.json"])
        let documentWithCaseVariantParameterKey = try jsonData(
            byDuplicatingFirstDynamicDictionaryEntryWithLowercaseKeyAt: ["parameters", "parameters"],
            in: documentData
        )
        let documentWithCaseVariantNodeKey = try jsonData(
            byDuplicatingFirstDynamicDictionaryEntryWithLowercaseKeyAt: ["designGraph", "nodes"],
            in: documentData
        )
        let documentWithCaseVariantSketchEntityKey = try jsonDataByDuplicatingFirstSketchEntityEntryWithLowercaseKey(
            in: documentData
        )

        let packageWithCaseVariantParameterKey = try StoredZipArchive.make(entries: [
            StoredZipArchive.Entry(path: "manifest.json", data: manifestData),
            StoredZipArchive.Entry(path: "document.json", data: documentWithCaseVariantParameterKey)
        ])
        let packageWithCaseVariantNodeKey = try StoredZipArchive.make(entries: [
            StoredZipArchive.Entry(path: "manifest.json", data: manifestData),
            StoredZipArchive.Entry(path: "document.json", data: documentWithCaseVariantNodeKey)
        ])
        let packageWithCaseVariantSketchEntityKey = try StoredZipArchive.make(entries: [
            StoredZipArchive.Entry(path: "manifest.json", data: manifestData),
            StoredZipArchive.Entry(path: "document.json", data: documentWithCaseVariantSketchEntityKey)
        ])

        #expect(throws: SchemaError.self) {
            _ = try store.loadDocument(fromPackageData: packageWithCaseVariantParameterKey)
        }
        #expect(throws: SchemaError.self) {
            _ = try store.loadDocument(fromPackageData: packageWithCaseVariantNodeKey)
        }
        #expect(throws: SchemaError.self) {
            _ = try store.loadDocument(fromPackageData: packageWithCaseVariantSketchEntityKey)
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func nativePackageLoadsObjectMapEncodedIDDictionaries() throws {
        let parameterID = ParameterID()
        let sketchID = FeatureID()
        let pointID = SketchEntityID()
        let document = CADDocument(
            units: .millimeters,
            parameters: ParameterTable(parameters: [
                parameterID: Parameter(
                    id: parameterID,
                    name: "width",
                    expression: .constant(.length(10.0, unit: .millimeter)),
                    kind: .length
                )
            ]),
            designGraph: DesignGraph(
                nodes: [
                    sketchID: FeatureNode(
                        id: sketchID,
                        operation: .sketch(Sketch(
                            plane: .xy,
                            entities: [
                                pointID: .point(SketchPoint(
                                    x: .constant(.length(0.0, unit: .millimeter)),
                                    y: .constant(.length(0.0, unit: .millimeter))
                                ))
                            ]
                        )),
                        outputs: [FeatureOutput(role: .profile)]
                    )
                ],
                order: [sketchID]
            )
        )
        let store = NativePackageStore(tolerance: .standard)
        let packageData = try store.packageData(for: document)
        let entries = try StoredZipArchive.readEntries(from: packageData)
        let manifestData = try #require(entries["manifest.json"])
        let documentData = try #require(entries["document.json"])
        let objectMapDocumentData = try jsonDataByConvertingNativeDynamicDictionariesToObjectMaps(in: documentData)
        let objectMapPackageData = try StoredZipArchive.make(entries: [
            StoredZipArchive.Entry(path: "manifest.json", data: manifestData),
            StoredZipArchive.Entry(path: "document.json", data: objectMapDocumentData)
        ])

        let loaded = try store.loadDocument(fromPackageData: objectMapPackageData)

        #expect(loaded.parameters.parameters[parameterID]?.name == "width")
        #expect(loaded.designGraph.nodes[sketchID] != nil)
        guard case let .sketch(sketch) = loaded.designGraph.nodes[sketchID]?.operation else {
            Issue.record("Expected loaded sketch node.")
            return
        }
        #expect(sketch.entities[pointID] != nil)
    }

    @Test(.timeLimit(.minutes(1)))
    func officialFormatRegistryMatchesSupportMatrix() {
        #expect(ExchangeFileFormat.swiftCAD.fileExtensions == ["swcad"])
        #expect(ExchangeFileFormat.format(forFileExtension: ".swcad") == .swiftCAD)
        #expect(ExchangeFileFormat.format(forFileExtension: "stp") == .step)
        #expect(ExchangeFileFormat.format(forFileExtension: "igs") == .iges)
        #expect(ExchangeFileFormat.format(forFileExtension: "3mf") == .threeMF)
        #expect(Set(ExchangeFileFormat.allCases.filter { $0.supportsExport }) == Set([
            .swiftCAD, .stl, .threeMF, .obj, .dxf, .svg, .glb, .usd, .usda, .usdc, .usdz, .pdf
        ]))

        var importFormats: Set<ExchangeFileFormat> = [
            .swiftCAD,
            .stl,
            .threeMF,
            .obj,
            .dxf,
            .svg,
            .usd,
            .usda
        ]
        #if os(macOS)
        importFormats.formUnion([.usdc, .usdz])
        #endif
        #expect(Set(ExchangeFileFormat.allCases.filter { $0.supportsImport }) == importFormats)
    }

    @Test(.timeLimit(.minutes(1)))
    func officialExchangeExportsEverySupportedFormat() throws {
        let evaluated = try makeEvaluatedDocument()
        let exchange = OfficialFormatExchange(tolerance: .standard)

        for format in ExchangeFileFormat.allCases where format.supportsExport {
            let data = try exchange.export(evaluated, as: format)
            #expect(!data.isEmpty)
            #expect(try signatureMatches(data, format: format))
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func officialExchangeImportsEveryImportSupportedFormat() throws {
        let evaluated = try makeEvaluatedDocument()
        let exchange = OfficialFormatExchange(tolerance: .standard)

        for format in ExchangeFileFormat.allCases where format.supportsImport {
            let data = try exchange.export(evaluated, as: format)
            let imported = try exchange.import(data, as: format)
            #expect(imported.format == format)
            if format == .swiftCAD {
                #expect(imported.document != nil)
                #expect(imported.document?.units.length == .millimeter)
            } else {
                #expect(!imported.meshes.isEmpty)
                #expect(imported.units.length == .millimeter)
                #expect(try imported.meshes.values.reduce(0) { partial, mesh in
                    try mesh.validate(tolerance: .standard)
                    return partial + mesh.indices.count
                } > 0)
                let extents = try meshExtents(imported.meshes)
                #expect(abs(extents.width - 0.04) < 1.0e-6)
                #expect(abs(extents.height - 0.02) < 1.0e-6)
                if format == .svg {
                    #expect(abs(extents.depth) < 1.0e-9)
                } else {
                    #expect(abs(extents.depth - 0.01) < 1.0e-6)
                }
            }
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func urlImportUsesMappedByteSourceForExchangeAndNativePackages() throws {
        let evaluated = try makeEvaluatedDocument()
        let exchange = OfficialFormatExchange(tolerance: .standard)
        let stlURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("swift-cad-mapped-\(UUID().uuidString).stl")
        let nativeURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("swift-cad-mapped-\(UUID().uuidString).swcad")
        defer {
            do {
                try FileManager.default.removeItem(at: stlURL)
            } catch {
            }
            do {
                try FileManager.default.removeItem(at: nativeURL)
            } catch {
            }
        }

        try exchange.export(evaluated, to: stlURL)
        try NativePackageStore(tolerance: .standard).save(evaluated.document, to: nativeURL)

        let importedSTL = try exchange.import(from: stlURL)
        let loadedDocument = try NativePackageStore(tolerance: .standard).load(from: nativeURL)

        #expect(importedSTL.format == .stl)
        #expect(!importedSTL.meshes.isEmpty)
        #expect(loadedDocument.id == evaluated.document.id)
        #expect(loadedDocument.schemaVersion == evaluated.document.schemaVersion)
        #expect(loadedDocument.units == evaluated.document.units)
    }

    @Test(.timeLimit(.minutes(1)))
    func officialExchangeRejectsImportUnsupportedFormats() throws {
        let exchange = OfficialFormatExchange(tolerance: .standard)

        for format in ExchangeFileFormat.allCases where !format.supportsImport {
            let data = Data()
            #expect(throws: ImportError.self) {
                _ = try exchange.import(data, as: format)
            }
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func officialExchangeRejectsStaleEvaluatedDocumentBeforeExport() throws {
        let evaluated = try makeEvaluatedDocument()
        let bodyID = try #require(evaluated.meshes.keys.first)
        var staleMeshes = evaluated.meshes
        staleMeshes[bodyID]?.positions[0].x += 0.25
        let staleEvaluated = replacing(evaluated, meshes: staleMeshes)

        #expect(throws: CacheValidationError.self) {
            _ = try OfficialFormatExchange(tolerance: .standard).export(staleEvaluated, as: .stl)
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func failedURLExportPreservesExistingFileContents() throws {
        let evaluated = try makeEvaluatedDocument()
        let bodyID = try #require(evaluated.meshes.keys.first)
        var staleMeshes = evaluated.meshes
        staleMeshes[bodyID]?.positions[0].x += 0.25
        let staleEvaluated = replacing(evaluated, meshes: staleMeshes)
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("swift-cad-existing-\(UUID().uuidString).stl")
        let originalData = Data("existing export payload".utf8)
        try originalData.write(to: url)
        defer {
            do {
                try FileManager.default.removeItem(at: url)
            } catch {
            }
        }

        #expect(throws: CacheValidationError.self) {
            try OfficialFormatExchange(tolerance: .standard).export(staleEvaluated, to: url)
        }
        let preservedData = try Data(contentsOf: url)
        #expect(preservedData == originalData)
    }

    @Test(.timeLimit(.minutes(1)))
    func officialExchangeRejectsStaleTopLevelBRepBeforeExport() throws {
        let evaluated = try makeEvaluatedDocument()
        let bodyID = try #require(evaluated.brep.bodies.keys.first)
        var staleBRep = evaluated.brep
        staleBRep.bodies[bodyID]?.name = "stale-body"
        let staleEvaluated = replacing(evaluated, brep: staleBRep)

        #expect(throws: CacheValidationError.self) {
            _ = try OfficialFormatExchange(tolerance: .standard).export(staleEvaluated, as: .stl)
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func failedNativeSavePreservesExistingFileContents() throws {
        let evaluated = try makeEvaluatedDocument()
        var staleDocument = evaluated.document
        staleDocument.schemaVersion = SchemaVersion(
            major: SchemaVersion.current.major + 1,
            minor: 0,
            patch: 0
        )
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("swift-cad-existing-\(UUID().uuidString).swcad")
        let originalData = Data("existing native payload".utf8)
        try originalData.write(to: url)
        defer {
            do {
                try FileManager.default.removeItem(at: url)
            } catch {
            }
        }

        #expect(throws: SchemaError.self) {
            try NativePackageStore(tolerance: .standard).save(staleDocument, to: url)
        }
        let preservedData = try Data(contentsOf: url)
        #expect(preservedData == originalData)
    }

    @Test(.timeLimit(.minutes(1)))
    func officialExchangeRejectsSourceGraphMutationWithoutRevisionAdvanceBeforeExport() throws {
        let evaluated = try makeEvaluatedDocument()
        var staleDocument = evaluated.document
        let extrudeFeatureID = try #require(staleDocument.designGraph.order.last)
        staleDocument.designGraph.nodes[extrudeFeatureID]?.isSuppressed = true
        try staleDocument.validate(tolerance: .standard)
        let staleEvaluated = replacing(evaluated, document: staleDocument)

        #expect(throws: CacheValidationError.self) {
            _ = try OfficialFormatExchange(tolerance: .standard).export(staleEvaluated, as: .stl)
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func urlImportMissingFilesThrowTypedImportError() throws {
        let missingNativeURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("missing-\(UUID().uuidString)")
            .appendingPathExtension("swcad")
        let missingSTLURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("missing-\(UUID().uuidString)")
            .appendingPathExtension("stl")

        #expect(throws: ImportError.self) {
            _ = try NativePackageStore(tolerance: .standard).load(from: missingNativeURL)
        }
        #expect(throws: ImportError.self) {
            _ = try OfficialFormatExchange(tolerance: .standard).import(from: missingSTLURL)
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func meshImportersRejectEmptyGeometryWithImportError() throws {
        let emptySTL = Data(count: 84)
        let emptyOBJ = Data("# Swift-CAD OBJ\n# unit millimeter\n".utf8)
        let emptyDXF = Data("0\nSECTION\n2\nENTITIES\n0\nENDSEC\n0\nEOF\n".utf8)
        let emptySVG = Data("<svg xmlns=\"http://www.w3.org/2000/svg\" data-unit=\"millimeter\"></svg>".utf8)
        let emptyThreeMF = try emptyThreeMFPackageData()

        #expect(throws: ImportError.self) {
            _ = try STLExporter(tolerance: .standard).importBinary(emptySTL)
        }
        #expect(throws: ImportError.self) {
            _ = try OBJExchange(tolerance: .standard).import(emptyOBJ)
        }
        #expect(throws: ImportError.self) {
            _ = try DXFExchange(tolerance: .standard).import(emptyDXF)
        }
        #expect(throws: ImportError.self) {
            _ = try SVGExchange(tolerance: .standard).import(emptySVG)
        }
        #expect(throws: ImportError.self) {
            _ = try ThreeMFExchange(tolerance: .standard).import(emptyThreeMF)
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func threeMFImporterWrapsInvalidPackageAndEncodingAsImportError() throws {
        let invalidZip = Data("not a zip".utf8)
        let invalidXMLPackage = try threeMFPackage(modelData: Data([0xff, 0xfe, 0xfd]))

        #expect(throws: ImportError.self) {
            _ = try ThreeMFExchange(tolerance: .standard).import(invalidZip)
        }
        #expect(throws: ImportError.self) {
            _ = try ThreeMFExchange(tolerance: .standard).import(invalidXMLPackage)
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func xmlImportersIgnoreCommentsAndHandleSingleQuotedAttributes() throws {
        let threeMFModel = try ThreeMFExchange(tolerance: .standard).import(threeMFPackageWithCommentsAndSingleQuotes())
        #expect(threeMFModel.units.length == .inch)
        let threeMFExtents = try meshExtents(threeMFModel.meshes)
        #expect(abs(threeMFExtents.width - LengthUnit.inch.toInternal(2.0)) < 1.0e-9)
        #expect(abs(threeMFExtents.height - LengthUnit.inch.toInternal(3.0)) < 1.0e-9)
        #expect(abs(threeMFExtents.depth - LengthUnit.inch.toInternal(4.0)) < 1.0e-9)

        let svg = Data("""
        <svg xmlns='http://www.w3.org/2000/svg' data-unit='centimeter'>
          <!-- <polygon points='999,999 1000,999 999,1000'/> -->
          <polygon points='0 0,2 0,0 -3'/>
        </svg>
        """.utf8)
        let svgModel = try SVGExchange(tolerance: .standard).import(svg)
        #expect(svgModel.units.length == .centimeter)
        let svgExtents = try meshExtents(svgModel.meshes)
        #expect(abs(svgExtents.width - LengthUnit.centimeter.toInternal(2.0)) < 1.0e-9)
        #expect(abs(svgExtents.height - LengthUnit.centimeter.toInternal(3.0)) < 1.0e-9)
        #expect(abs(svgExtents.depth) < 1.0e-9)
    }

    @Test(.timeLimit(.minutes(1)))
    func xmlImportersRequireRootFormatElements() throws {
        let svg = Data("""
        <document data-unit="meter">
          <polygon points="0,0 2,0 0,-3"/>
        </document>
        """.utf8)

        #expect(throws: ImportError.self) {
            _ = try SVGExchange(tolerance: .standard).import(svg)
        }
        #expect(throws: ImportError.self) {
            _ = try ThreeMFExchange(tolerance: .standard).import(threeMFPackageWithWrongRootElement())
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func xmlImportersUseOnlyRootScopedUnitMetadata() throws {
        let svg = Data("""
        <svg xmlns="http://www.w3.org/2000/svg" data-unit="meter">
          <g data-unit="millimeter">
            <polygon points="0,0 2,0 0,-3"/>
          </g>
        </svg>
        """.utf8)

        let svgModel = try SVGExchange(tolerance: .standard).import(svg)
        let svgExtents = try meshExtents(svgModel.meshes)
        #expect(svgModel.units.length == .meter)
        #expect(abs(svgExtents.width - 2.0) < 1.0e-9)
        #expect(abs(svgExtents.height - 3.0) < 1.0e-9)

        let threeMFModel = try ThreeMFExchange(tolerance: .standard).import(threeMFPackageWithNestedExtensionUnitTrap())
        let threeMFExtents = try meshExtents(threeMFModel.meshes)
        #expect(threeMFModel.units.length == .meter)
        #expect(abs(threeMFExtents.width - 2.0) < 1.0e-9)
        #expect(abs(threeMFExtents.height - 3.0) < 1.0e-9)
    }

    @Test(.timeLimit(.minutes(1)))
    func threeMFImporterUsesMillimetersWhenModelUnitIsOmitted() throws {
        let model = try ThreeMFExchange(tolerance: .standard).import(threeMFPackageWithOmittedModelUnit())
        let extents = try meshExtents(model.meshes)

        #expect(model.units.length == .millimeter)
        #expect(abs(extents.width - LengthUnit.millimeter.toInternal(1.0)) < 1.0e-12)
        #expect(abs(extents.height - LengthUnit.millimeter.toInternal(1.0)) < 1.0e-12)
    }

    @Test(.timeLimit(.minutes(1)))
    func xmlImportersRejectWrongNamespaces() throws {
        let svgWithoutNamespace = Data("""
        <svg data-unit="meter">
          <polygon points="0,0 2,0 0,-3"/>
        </svg>
        """.utf8)

        #expect(throws: ImportError.self) {
            _ = try SVGExchange(tolerance: .standard).import(svgWithoutNamespace)
        }
        #expect(throws: ImportError.self) {
            _ = try ThreeMFExchange(tolerance: .standard).import(threeMFPackageWithWrongModelNamespace())
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func svgImporterRejectsUnsupportedGeometryAndContainers() throws {
        let svgWithMissingPolygonPoints = Data("""
        <svg xmlns="http://www.w3.org/2000/svg" data-unit="meter">
          <polygon/>
          <polygon points="0,0 1,0 0,1"/>
        </svg>
        """.utf8)
        let svgWithUnsupportedPath = Data("""
        <svg xmlns="http://www.w3.org/2000/svg" data-unit="meter">
          <path d="M0 0 L1 0 L0 1 Z"/>
          <polygon points="0,0 1,0 0,1"/>
        </svg>
        """.utf8)
        let svgWithPolygonInDefs = Data("""
        <svg xmlns="http://www.w3.org/2000/svg" data-unit="meter">
          <defs>
            <polygon points="0,0 1,0 0,1"/>
          </defs>
        </svg>
        """.utf8)
        let svgWithNestedSVGContainer = Data("""
        <svg xmlns="http://www.w3.org/2000/svg" data-unit="meter">
          <svg>
            <polygon points="0,0 1,0 0,1"/>
          </svg>
        </svg>
        """.utf8)
        let svgWithEmptyNestedSVGContainer = Data("""
        <svg xmlns="http://www.w3.org/2000/svg" data-unit="meter">
          <polygon points="0,0 1,0 0,1"/>
          <svg/>
        </svg>
        """.utf8)
        let svgWithGroupTransform = Data("""
        <svg xmlns="http://www.w3.org/2000/svg" data-unit="meter">
          <g transform="scale(2)">
            <polygon points="0,0 1,0 0,1"/>
          </g>
        </svg>
        """.utf8)
        let svgWithPolygonTransform = Data("""
        <svg xmlns="http://www.w3.org/2000/svg" data-unit="meter">
          <polygon transform="translate(1,0)" points="0,0 1,0 0,1"/>
        </svg>
        """.utf8)
        let svgWithUnsupportedText = Data("""
        <svg xmlns="http://www.w3.org/2000/svg" data-unit="meter">
          <text x="0" y="0">label</text>
          <polygon points="0,0 1,0 0,1"/>
        </svg>
        """.utf8)

        #expect(throws: ImportError.self) {
            _ = try SVGExchange(tolerance: .standard).import(svgWithMissingPolygonPoints)
        }
        #expect(throws: ImportError.self) {
            _ = try SVGExchange(tolerance: .standard).import(svgWithUnsupportedPath)
        }
        #expect(throws: ImportError.self) {
            _ = try SVGExchange(tolerance: .standard).import(svgWithPolygonInDefs)
        }
        #expect(throws: ImportError.self) {
            _ = try SVGExchange(tolerance: .standard).import(svgWithNestedSVGContainer)
        }
        #expect(throws: ImportError.self) {
            _ = try SVGExchange(tolerance: .standard).import(svgWithEmptyNestedSVGContainer)
        }
        #expect(throws: ImportError.self) {
            _ = try SVGExchange(tolerance: .standard).import(svgWithGroupTransform)
        }
        #expect(throws: ImportError.self) {
            _ = try SVGExchange(tolerance: .standard).import(svgWithPolygonTransform)
        }
        #expect(throws: ImportError.self) {
            _ = try SVGExchange(tolerance: .standard).import(svgWithUnsupportedText)
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func svgImporterRejectsNonWhitespaceCharacterData() {
        let svgWithRootTextPayload = Data("""
        <svg xmlns="http://www.w3.org/2000/svg" data-unit="meter">
          hidden payload
          <polygon points="0,0 1,0 0,1"/>
        </svg>
        """.utf8)
        let svgWithGroupTextPayload = Data("""
        <svg xmlns="http://www.w3.org/2000/svg" data-unit="meter">
          <g>
            hidden payload
            <polygon points="0,0 1,0 0,1"/>
          </g>
        </svg>
        """.utf8)

        #expect(throws: ImportError.self) {
            _ = try SVGExchange(tolerance: .standard).import(svgWithRootTextPayload)
        }
        #expect(throws: ImportError.self) {
            _ = try SVGExchange(tolerance: .standard).import(svgWithGroupTextPayload)
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func svgImporterRejectsUnsupportedAttributes() throws {
        let exported = try SVGExchange(tolerance: .standard).export(meshes: [BodyID(): unitTriangleMesh(unit: .meter)], unit: .meter)
        _ = try SVGExchange(tolerance: .standard).import(exported)

        let svgWithRootPayloadAttribute = Data("""
        <svg xmlns="http://www.w3.org/2000/svg" data-unit="meter" id="hidden-root">
          <polygon points="0,0 1,0 0,1"/>
        </svg>
        """.utf8)
        let svgWithGroupPayloadAttribute = Data("""
        <svg xmlns="http://www.w3.org/2000/svg" data-unit="meter">
          <g class="hidden-group">
            <polygon points="0,0 1,0 0,1"/>
          </g>
        </svg>
        """.utf8)
        let svgWithPolygonPayloadAttribute = Data("""
        <svg xmlns="http://www.w3.org/2000/svg" data-unit="meter">
          <polygon points="0,0 1,0 0,1" onclick="hidden()"/>
        </svg>
        """.utf8)

        #expect(throws: ImportError.self) {
            _ = try SVGExchange(tolerance: .standard).import(svgWithRootPayloadAttribute)
        }
        #expect(throws: ImportError.self) {
            _ = try SVGExchange(tolerance: .standard).import(svgWithGroupPayloadAttribute)
        }
        #expect(throws: ImportError.self) {
            _ = try SVGExchange(tolerance: .standard).import(svgWithPolygonPayloadAttribute)
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func svgImporterRejectsEmptyPointListFields() {
        let malformedPointLists = [
            ",0,0 1,0 0,1",
            "0,0 1,0 0,1,",
            "0,0 1,,0 0,1"
        ]

        for points in malformedPointLists {
            let svg = Data("""
            <svg xmlns="http://www.w3.org/2000/svg" data-unit="meter">
              <polygon points="\(points)"/>
            </svg>
            """.utf8)

            #expect(throws: ImportError.self) {
                _ = try SVGExchange(tolerance: .standard).import(svg)
            }
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func svgImporterTriangulatesConcavePolygonAndPreservesArea() throws {
        let svg = Data("""
        <svg xmlns="http://www.w3.org/2000/svg" data-unit="meter">
          <polygon points="0,0 2,0 2,2 1,1 0,2"/>
        </svg>
        """.utf8)

        let imported = try SVGExchange(tolerance: .standard).import(svg)
        let mesh = try #require(imported.meshes.values.first)

        #expect(mesh.positions.count == 9)
        #expect(mesh.indices == [0, 1, 2, 3, 4, 5, 6, 7, 8])
        #expect(abs(triangleMeshArea(mesh) - 3.0) < 1.0e-12)
    }

    @Test(.timeLimit(.minutes(1)))
    func svgImporterRejectsSelfIntersectionAndUnsupportedXMLContent() {
        let selfIntersecting = Data("""
        <svg xmlns="http://www.w3.org/2000/svg" data-unit="meter">
          <polygon points="0,0 2,2 0,2 2,0"/>
        </svg>
        """.utf8)
        let entityDeclaration = Data("""
        <!DOCTYPE svg [<!ENTITY payload "hidden">]>
        <svg xmlns="http://www.w3.org/2000/svg" data-unit="meter">
          <polygon points="0,0 1,0 0,1"/>
        </svg>
        """.utf8)
        let nonWhitespaceCDATA = Data("""
        <svg xmlns="http://www.w3.org/2000/svg" data-unit="meter"><![CDATA[hidden]]>
          <polygon points="0,0 1,0 0,1"/>
        </svg>
        """.utf8)
        let externalPaint = Data("""
        <svg xmlns="http://www.w3.org/2000/svg" data-unit="meter">
          <polygon points="0,0 1,0 0,1" fill="url(https://example.invalid/paint)"/>
        </svg>
        """.utf8)

        for source in [selfIntersecting, entityDeclaration, nonWhitespaceCDATA, externalPaint] {
            #expect(throws: ImportError.self) {
                _ = try SVGExchange(tolerance: .standard).import(source)
            }
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func svgExchangeEnforcesTypedByteEntityAndNestingLimits() throws {
        let triangle = Data("""
        <svg xmlns="http://www.w3.org/2000/svg" data-unit="meter">
          <polygon points="0,0 1,0 0,1"/>
        </svg>
        """.utf8)
        let nested = Data("""
        <svg xmlns="http://www.w3.org/2000/svg" data-unit="meter">
          <g><g><polygon points="0,0 1,0 0,1"/></g></g>
        </svg>
        """.utf8)
        let byteLimited = SVGExchange(
            tolerance: .standard,
            resourceLimits: ExchangeResourceLimits(maximumBytes: 32)
        )
        let entityLimited = SVGExchange(
            tolerance: .standard,
            resourceLimits: ExchangeResourceLimits(maximumEntities: 4)
        )
        let nestingLimited = SVGExchange(
            tolerance: .standard,
            resourceLimits: ExchangeResourceLimits(maximumNesting: 2)
        )

        let operations: [() throws -> Void] = [
            { _ = try byteLimited.import(triangle) },
            { _ = try entityLimited.import(triangle) },
            { _ = try nestingLimited.import(nested) },
            { _ = try byteLimited.export(meshes: [BodyID(): unitTriangleMesh(unit: .meter)]) },
        ]
        for operation in operations {
            do {
                _ = try operation()
                Issue.record("Expected SVG resource accounting to reject the operation.")
            } catch let error as KernelError {
                #expect(error.phase == .exchange)
                #expect(error.code == .resourceLimitExceeded)
            } catch {
                Issue.record("Expected a typed KernelError, received \(error).")
            }
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func threeMFImporterRejectsCoreLookalikesInsideMetadata() throws {
        #expect(throws: ImportError.self) {
            _ = try ThreeMFExchange(tolerance: .standard).import(threeMFPackageWithCoreModelInsideMetadata())
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func threeMFImporterRejectsGeometryOutsideMeshContainers() throws {
        #expect(throws: ImportError.self) {
            _ = try ThreeMFExchange(tolerance: .standard).import(threeMFPackageWithVertexOutsideVertices())
        }
        #expect(throws: ImportError.self) {
            _ = try ThreeMFExchange(tolerance: .standard).import(threeMFPackageWithTriangleOutsideTriangles())
        }
        #expect(throws: ImportError.self) {
            _ = try ThreeMFExchange(tolerance: .standard).import(threeMFPackageWithVertexInsideNestedLookalikeContainer())
        }
        #expect(throws: ImportError.self) {
            _ = try ThreeMFExchange(tolerance: .standard).import(threeMFPackageWithTriangleInsideNestedLookalikeContainer())
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func threeMFImporterRejectsUnsupportedMeshElementsInsteadOfPartialImport() throws {
        #expect(throws: ImportError.self) {
            _ = try ThreeMFExchange(tolerance: .standard).import(threeMFPackageWithUnsupportedMeshElement())
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func threeMFImporterRejectsKnownContainersInWrongPath() throws {
        #expect(throws: ImportError.self) {
            _ = try ThreeMFExchange(tolerance: .standard).import(threeMFPackageWithMeshContainerInsideBuild())
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func threeMFImporterRejectsUnsupportedPackageEntries() throws {
        #expect(throws: ImportError.self) {
            _ = try ThreeMFExchange(tolerance: .standard).import(threeMFPackageWithUnsupportedPackageEntry())
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func threeMFImporterRejectsMissingRequiredPackageEntries() throws {
        let modelOnlyPackage = try StoredZipArchive.make(entries: [
            StoredZipArchive.Entry(path: "3D/3dmodel.model", data: Data(validThreeMFModelXML().utf8))
        ])
        let missingRelationshipsPackage = try StoredZipArchive.make(entries: [
            StoredZipArchive.Entry(path: "[Content_Types].xml", data: Data(threeMFContentTypesXML.utf8)),
            StoredZipArchive.Entry(path: "3D/3dmodel.model", data: Data(validThreeMFModelXML().utf8))
        ])

        #expect(throws: ImportError.self) {
            _ = try ThreeMFExchange(tolerance: .standard).import(modelOnlyPackage)
        }
        #expect(throws: ImportError.self) {
            _ = try ThreeMFExchange(tolerance: .standard).import(missingRelationshipsPackage)
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func threeMFImporterRejectsInvalidPackageMetadataContents() throws {
        let emptyContentTypesPackage = try threeMFPackage(
            contentTypesXML: """
            <?xml version="1.0" encoding="UTF-8"?>
            <Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types"/>
            """,
            relationshipsXML: threeMFRelationshipsXML,
            modelXML: validThreeMFModelXML()
        )
        let wrongModelContentTypePackage = try threeMFPackage(
            contentTypesXML: """
            <?xml version="1.0" encoding="UTF-8"?>
            <Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">
              <Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>
              <Default Extension="model" ContentType="application/xml"/>
            </Types>
            """,
            relationshipsXML: threeMFRelationshipsXML,
            modelXML: validThreeMFModelXML()
        )
        let wrongRelationshipTargetPackage = try threeMFPackage(
            contentTypesXML: threeMFContentTypesXML,
            relationshipsXML: """
            <?xml version="1.0" encoding="UTF-8"?>
            <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
              <Relationship Target="/Metadata/hidden.model" Id="rel0" Type="http://schemas.microsoft.com/3dmanufacturing/2013/01/3dmodel"/>
            </Relationships>
            """,
            modelXML: validThreeMFModelXML()
        )
        let duplicateRelationshipPackage = try threeMFPackage(
            contentTypesXML: threeMFContentTypesXML,
            relationshipsXML: """
            <?xml version="1.0" encoding="UTF-8"?>
            <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
              <Relationship Target="/3D/3dmodel.model" Id="rel0" Type="http://schemas.microsoft.com/3dmanufacturing/2013/01/3dmodel"/>
              <Relationship Target="/3D/3dmodel.model" Id="rel1" Type="http://schemas.microsoft.com/3dmanufacturing/2013/01/3dmodel"/>
            </Relationships>
            """,
            modelXML: validThreeMFModelXML()
        )

        #expect(throws: ImportError.self) {
            _ = try ThreeMFExchange(tolerance: .standard).import(emptyContentTypesPackage)
        }
        #expect(throws: ImportError.self) {
            _ = try ThreeMFExchange(tolerance: .standard).import(wrongModelContentTypePackage)
        }
        #expect(throws: ImportError.self) {
            _ = try ThreeMFExchange(tolerance: .standard).import(wrongRelationshipTargetPackage)
        }
        #expect(throws: ImportError.self) {
            _ = try ThreeMFExchange(tolerance: .standard).import(duplicateRelationshipPackage)
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func threeMFImporterRejectsUnbuiltResourceObjects() throws {
        #expect(throws: ImportError.self) {
            _ = try ThreeMFExchange(tolerance: .standard).import(threeMFPackageWithUnbuiltResourceObject())
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func threeMFImporterResolvesBuiltObjectLocalTriangleIndices() throws {
        let model = try ThreeMFExchange(tolerance: .standard).import(threeMFPackageWithMultipleBuiltObjects())
        let extents = try meshExtents(model.meshes)

        #expect(model.meshes.count == 2)
        #expect(model.meshes.values.map(\.positions.count).sorted() == [3, 3])
        #expect(model.meshes.values.map(\.indices).allSatisfy { $0 == [0, 1, 2] })
        #expect(abs(extents.width - 12.0) < 1.0e-9)
        #expect(abs(extents.height - 2.0) < 1.0e-9)
        #expect(abs(extents.depth) < 1.0e-9)
    }

    @Test(.timeLimit(.minutes(1)))
    func threeMFRoundTripPreservesObjectsAsSeparateMeshes() throws {
        let firstMesh = unitTriangleMesh(unit: .meter)
        let secondMesh = Mesh(
            positions: [
                Point3D(x: 10.0, y: 0.0, z: 0.0),
                Point3D(x: 11.0, y: 0.0, z: 0.0),
                Point3D(x: 10.0, y: 1.0, z: 0.0)
            ],
            normals: [],
            indices: [0, 1, 2]
        )

        let data = try ThreeMFExchange(tolerance: .standard).export(
            meshes: [
                BodyID(): firstMesh,
                BodyID(): secondMesh
            ],
            unit: .meter
        )
        let imported = try ThreeMFExchange(tolerance: .standard).import(data)

        #expect(imported.meshes.count == 2)
        #expect(imported.meshes.values.map(\.positions.count).sorted() == [3, 3])
        #expect(imported.meshes.values.map(\.indices).allSatisfy { $0 == [0, 1, 2] })

        let minimumXValues = imported.meshes.values.compactMap { mesh in
            mesh.positions.map(\.x).min()
        }.sorted()
        #expect(minimumXValues == [0.0, 10.0])
    }

    @Test(.timeLimit(.minutes(1)))
    func threeMFImporterReadsDeflatedEntriesWithDescriptorsAndUTF8Flags() throws {
        let package = try deflatedZipArchive(entries: [
            StoredZipArchive.Entry(path: "[Content_Types].xml", data: Data(threeMFContentTypesXML.utf8)),
            StoredZipArchive.Entry(path: "_rels/.rels", data: Data(threeMFRelationshipsXML.utf8)),
            StoredZipArchive.Entry(path: "3D/3dmodel.model", data: Data(validThreeMFModelXML().utf8)),
        ], usesDataDescriptors: true)

        let imported = try ThreeMFExchange(tolerance: .standard).import(package)
        let mesh = try #require(imported.meshes.values.first)

        #expect(imported.units.length == .meter)
        #expect(mesh.indices == [0, 1, 2])
        #expect(abs(triangleMeshArea(mesh) - 0.5) < 1.0e-12)
    }

    @Test(.timeLimit(.minutes(1)))
    func threeMFExchangeEnforcesArchiveXMLAndOutputResourceLimits() throws {
        let package = try threeMFPackage(modelXML: validThreeMFModelXML())
        let exchanges = [
            ThreeMFExchange(
                tolerance: .standard,
                resourceLimits: ExchangeResourceLimits(maximumBytes: 128)
            ),
            ThreeMFExchange(
                tolerance: .standard,
                resourceLimits: ExchangeResourceLimits(maximumEntities: 4)
            ),
            ThreeMFExchange(
                tolerance: .standard,
                resourceLimits: ExchangeResourceLimits(maximumNesting: 4)
            ),
            ThreeMFExchange(
                tolerance: .standard,
                resourceLimits: ExchangeResourceLimits(maximumIterations: 128)
            ),
        ]
        let operations: [() throws -> Void] = [
            { _ = try exchanges[0].import(package) },
            { _ = try exchanges[1].import(package) },
            { _ = try exchanges[2].import(package) },
            { _ = try exchanges[3].import(package) },
            {
                _ = try exchanges[0].export(
                    meshes: [BodyID(): unitTriangleMesh(unit: .meter)],
                    unit: .meter
                )
            },
        ]

        for operation in operations {
            do {
                try operation()
                Issue.record("Expected 3MF resource accounting to reject the operation.")
            } catch let error as KernelError {
                #expect(error.phase == .exchange)
                #expect(error.code == .resourceLimitExceeded)
            } catch {
                Issue.record("Expected a typed KernelError, received \(error).")
            }
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func threeMFImporterRejectsDTDCDATAAndProcessingInstructions() throws {
        let model = validThreeMFModelXML()
        let documents = [
            model.replacingOccurrences(
                of: "<model ",
                with: "<!DOCTYPE model [<!ENTITY xxe SYSTEM 'file:///etc/passwd'>]>\n<model "
            ).replacingOccurrences(
                of: "<resources>",
                with: "<metadata name='unsafe'>&xxe;</metadata><resources>"
            ),
            model.replacingOccurrences(
                of: "<resources>",
                with: "<metadata name='unsafe'><![CDATA[content]]></metadata><resources>"
            ),
            model.replacingOccurrences(
                of: "<resources>",
                with: "<?unsafe content?><resources>"
            ),
        ]

        for document in documents {
            #expect(throws: ImportError.self) {
                _ = try ThreeMFExchange(tolerance: .standard).import(
                    threeMFPackage(modelXML: document)
                )
            }
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func threeMFImporterRejectsUnsupportedBuildReferences() throws {
        #expect(throws: ImportError.self) {
            _ = try ThreeMFExchange(tolerance: .standard).import(threeMFPackageWithBuildItemTransform())
        }
        #expect(throws: ImportError.self) {
            _ = try ThreeMFExchange(tolerance: .standard).import(threeMFPackageWithMissingBuildObjectReference())
        }
        #expect(throws: ImportError.self) {
            _ = try ThreeMFExchange(tolerance: .standard).import(threeMFPackageWithNestedBuildItemLookalikeContainer())
        }
        #expect(throws: ImportError.self) {
            _ = try ThreeMFExchange(tolerance: .standard).import(threeMFPackageWithNestedResourcesObjectLookalikeContainer())
        }
        #expect(throws: ImportError.self) {
            _ = try ThreeMFExchange(tolerance: .standard).import(threeMFPackageWithUnsupportedObjectComponent())
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func threeMFImporterRejectsUnsupportedPropertyReferences() throws {
        #expect(throws: ImportError.self) {
            _ = try ThreeMFExchange(tolerance: .standard).import(threeMFPackageWithTrianglePropertyReference())
        }
        #expect(throws: ImportError.self) {
            _ = try ThreeMFExchange(tolerance: .standard).import(threeMFPackageWithObjectPropertyReference())
        }
        #expect(throws: ImportError.self) {
            _ = try ThreeMFExchange(tolerance: .standard).import(threeMFPackageWithUnsupportedPropertyResource())
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func threeMFImporterRejectsUnsupportedCoreAttributes() throws {
        let exported = try ThreeMFExchange(tolerance: .standard).export(meshes: [BodyID(): unitTriangleMesh(unit: .meter)], unit: .meter)
        _ = try ThreeMFExchange(tolerance: .standard).import(exported)

        let coreElementOpenings = [
            "<model unit='meter'",
            "<resources",
            "<object id='1' type='model'",
            "<mesh",
            "<vertices",
            "<vertex x='0' y='0' z='0'",
            "<triangles",
            "<triangle v1='0' v2='1' v3='2'",
            "<build",
            "<item objectid='1'"
        ]

        for opening in coreElementOpenings {
            let package = try threeMFPackageWithUnsupportedCoreAttribute(after: opening)
            #expect(throws: ImportError.self) {
                _ = try ThreeMFExchange(tolerance: .standard).import(package)
            }
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func numericImportersRejectNonFiniteCoordinatesWithImportError() throws {
        let obj = Data("""
        # unit millimeter
        v nan 0 0
        v 1 0 0
        v 0 1 0
        f 1 2 3
        """.utf8)
        let dxf = Data("""
        0
        SECTION
        2
        ENTITIES
        0
        3DFACE
        10
        inf
        20
        0
        30
        0
        11
        1
        21
        0
        31
        0
        12
        0
        22
        1
        32
        0
        0
        ENDSEC
        0
        EOF
        """.utf8)
        let stl = binarySTLWithNonFiniteVertex()

        #expect(throws: ImportError.self) {
            _ = try OBJExchange(tolerance: .standard).import(obj)
        }
        #expect(throws: ImportError.self) {
            _ = try DXFExchange(tolerance: .standard).import(dxf)
        }
        #expect(throws: ImportError.self) {
            _ = try STLExporter(tolerance: .standard).importBinary(stl)
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func numericImportersRejectUnreferencedNonFiniteValues() throws {
        let obj = Data("""
        # unit millimeter
        v nan 0 0
        v 0 0 0
        v 1 0 0
        v 0 1 0
        f 2 3 4
        """.utf8)
        let objWithUnreferencedZeroNormal = Data("""
        # unit millimeter
        v 0 0 0
        v 1 0 0
        v 0 1 0
        vn 0 0 0
        f 1 2 3
        """.utf8)
        let threeMF = try threeMFPackageWithUnreferencedNonFiniteVertex()
        let svg = Data("""
        <svg xmlns='http://www.w3.org/2000/svg' data-unit='millimeter'>
          <polygon points='0 0,1e309 0,0 1'/>
        </svg>
        """.utf8)

        #expect(throws: ImportError.self) {
            _ = try OBJExchange(tolerance: .standard).import(obj)
        }
        #expect(throws: ImportError.self) {
            _ = try OBJExchange(tolerance: .standard).import(objWithUnreferencedZeroNormal)
        }
        #expect(throws: ImportError.self) {
            _ = try ThreeMFExchange(tolerance: .standard).import(threeMF)
        }
        #expect(throws: ImportError.self) {
            _ = try SVGExchange(tolerance: .standard).import(svg)
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func objImporterAcceptsTabSeparatedRecords() throws {
        let obj = Data("""
        # unit millimeter
        v\t0\t0\t0
        v\t2\t0\t0
        v\t0\t3\t0
        f\t1\t2\t3
        """.utf8)

        let imported = try OBJExchange(tolerance: .standard).import(obj)
        #expect(imported.units.length == .millimeter)
        let extents = try meshExtents(imported.meshes)
        #expect(abs(extents.width - 0.002) < 1.0e-12)
        #expect(abs(extents.height - 0.003) < 1.0e-12)
    }

    @Test(.timeLimit(.minutes(1)))
    func objImporterAcceptsValidatedNormalReferences() throws {
        let obj = Data("""
        # unit meter
        v 0 0 0
        v 1 0 0
        v 0 1 0
        vn 0 0 1
        f 1//1 2//1 3//1
        """.utf8)

        let imported = try OBJExchange(tolerance: .standard).import(obj)
        let mesh = try #require(imported.meshes.values.first)
        #expect(mesh.indices == [0, 1, 2])
        #expect(mesh.normals == [
            Vector3D.unitZ,
            Vector3D.unitZ,
            Vector3D.unitZ
        ])
    }

    @Test(.timeLimit(.minutes(1)))
    func objRoundTripPreservesObjectRecordsAsSeparateMeshes() throws {
        let firstMesh = unitTriangleMesh(unit: .meter)
        let secondMesh = Mesh(
            positions: [
                Point3D(x: 10.0, y: 0.0, z: 0.0),
                Point3D(x: 11.0, y: 0.0, z: 0.0),
                Point3D(x: 10.0, y: 1.0, z: 0.0)
            ],
            normals: [],
            indices: [0, 1, 2]
        )

        let data = try OBJExchange(tolerance: .standard).export(
            meshes: [
                BodyID(): firstMesh,
                BodyID(): secondMesh
            ],
            unit: .meter
        )
        let imported = try OBJExchange(tolerance: .standard).import(data)

        #expect(imported.meshes.count == 2)
        #expect(imported.meshes.values.map(\.positions.count).sorted() == [3, 3])
        #expect(imported.meshes.values.map(\.indices).allSatisfy { $0 == [0, 1, 2] })

        let minimumXValues = imported.meshes.values.compactMap { mesh in
            mesh.positions.map(\.x).min()
        }.sorted()
        #expect(minimumXValues == [0.0, 10.0])
    }

    @Test(.timeLimit(.minutes(1)))
    func objImporterUsesGroupRecordsAsMeshBoundaries() throws {
        let obj = Data("""
        # unit meter
        g first
        v 0 0 0
        v 1 0 0
        v 0 1 0
        f 1 2 3
        g second
        v 10 0 0
        v 11 0 0
        v 10 1 0
        f 4 5 6
        """.utf8)

        let imported = try OBJExchange(tolerance: .standard).import(obj)

        #expect(imported.meshes.count == 2)
        #expect(imported.meshes.values.map(\.positions.count).sorted() == [3, 3])
        #expect(imported.meshes.values.map(\.indices).allSatisfy { $0 == [0, 1, 2] })

        let minimumXValues = imported.meshes.values.compactMap { mesh in
            mesh.positions.map(\.x).min()
        }.sorted()
        #expect(minimumXValues == [0.0, 10.0])
    }

    @Test(.timeLimit(.minutes(1)))
    func objImporterTriangulatesConcavePolygonAndPreservesFaceVaryingAttributes() throws {
        let obj = Data("""
        # unit meter
        v 0 0 0
        v 2 0 0
        v 2 2 0
        v 1 1 0
        v 0 2 0
        vt 0 0
        vt 1 0
        vt 1 1
        vt 0.5 0.5
        vt 0 1
        vn 0 0 1
        f -5/1/1 -4/2/1 -3/3/1 -2/4/1 -1/5/1
        """.utf8)

        let imported = try OBJExchange(tolerance: .standard).import(obj)
        let mesh = try #require(imported.meshes.values.first)

        #expect(mesh.indices.count == 9)
        #expect(mesh.positions.count == 9)
        #expect(mesh.normals == Array(repeating: .unitZ, count: 9))
        #expect(mesh.textureCoordinates.count == 9)
        let twiceArea = stride(from: 0, to: mesh.indices.count, by: 3).reduce(0.0) { result, index in
            let first = mesh.positions[Int(mesh.indices[index])]
            let second = mesh.positions[Int(mesh.indices[index + 1])]
            let third = mesh.positions[Int(mesh.indices[index + 2])]
            return result + (second - first).cross(third - first).length
        }
        #expect(abs(twiceArea - 6.0) <= 1.0e-12)
    }

    @Test(.timeLimit(.minutes(1)))
    func objImporterResolvesHomogeneousVerticesNormalizesNormalsAndIgnoresInlineComments() throws {
        let obj = Data("""
        # unit meter
        v 0 0 0 2 # homogeneous origin
        v 2 0 0 2
        v 0 2 0 2
        vn 0 0 4
        f 1//1 2//1 3//1 # one triangle
        """.utf8)

        let imported = try OBJExchange(tolerance: .standard).import(obj)
        let mesh = try #require(imported.meshes.values.first)

        #expect(mesh.positions == [
            .origin,
            Point3D(x: 1.0, y: 0.0, z: 0.0),
            Point3D(x: 0.0, y: 1.0, z: 0.0),
        ])
        #expect(mesh.normals == Array(repeating: .unitZ, count: 3))
    }

    @Test(.timeLimit(.minutes(1)))
    func objRoundTripPreservesTextureCoordinates() throws {
        let mesh = Mesh(
            positions: [
                Point3D(x: 0.0, y: 0.0, z: 0.0),
                Point3D(x: 1.0, y: 0.0, z: 0.0),
                Point3D(x: 0.0, y: 1.0, z: 0.0),
            ],
            normals: [.unitZ, .unitZ, .unitZ],
            indices: [0, 1, 2],
            textureCoordinates: [
                Point2D(x: 0.0, y: 0.0),
                Point2D(x: 1.0, y: 0.0),
                Point2D(x: 0.0, y: 1.0),
            ]
        )

        let exchange = OBJExchange(tolerance: .standard)
        let data = try exchange.export(meshes: [BodyID(): mesh])
        let imported = try exchange.import(data)
        let roundTripped = try #require(imported.meshes.values.first)

        #expect(roundTripped.positions == mesh.positions)
        #expect(roundTripped.normals == mesh.normals)
        #expect(roundTripped.textureCoordinates == mesh.textureCoordinates)
    }

    @Test(.timeLimit(.minutes(1)))
    func objImporterPartitionsFacesWithDifferentAttributeLayouts() throws {
        let obj = Data("""
        # unit meter
        v 0 0 0
        v 1 0 0
        v 1 1 0
        v 0 1 0
        vn 0 0 1
        f 1//1 2//1 3//1
        f 1 3 4
        """.utf8)

        let imported = try OBJExchange(tolerance: .standard).import(obj)
        let meshes = Array(imported.meshes.values)

        #expect(meshes.count == 2)
        #expect(meshes.map(\.normals.count).sorted() == [0, 3])
        #expect(meshes.allSatisfy { $0.indices.count == 3 })
        #expect(abs(meshes.reduce(0.0) { $0 + triangleMeshArea($1) } - 1.0) < 1.0e-12)
    }

    @Test(.timeLimit(.minutes(1)))
    func objExchangeEnforcesTypedInputAndOutputResourceLimits() throws {
        let mesh = unitTriangleMesh(unit: .meter)
        let entityLimited = OBJExchange(
            tolerance: .standard,
            resourceLimits: ExchangeResourceLimits(maximumEntities: 4)
        )
        let byteLimited = OBJExchange(
            tolerance: .standard,
            resourceLimits: ExchangeResourceLimits(maximumBytes: 16)
        )

        do {
            _ = try entityLimited.export(meshes: [BodyID(): mesh])
            Issue.record("Expected OBJ entity accounting to reject the export.")
        } catch let error as KernelError {
            #expect(error.phase == .exchange)
            #expect(error.code == .resourceLimitExceeded)
        }
        do {
            _ = try byteLimited.import(Data("v 0 0 0\nv 1 0 0\nv 0 1 0\nf 1 2 3\n".utf8))
            Issue.record("Expected OBJ input byte accounting to reject the import.")
        } catch let error as KernelError {
            #expect(error.phase == .exchange)
            #expect(error.code == .resourceLimitExceeded)
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func objImporterRejectsUnsupportedGeometryRecords() {
        let objWithLine = Data("""
        # unit meter
        v 0 0 0
        v 1 0 0
        v 0 1 0
        l 1 2
        f 1 2 3
        """.utf8)
        let objWithPoint = Data("""
        # unit meter
        v 0 0 0
        v 1 0 0
        v 0 1 0
        p 1
        f 1 2 3
        """.utf8)
        let objWithFreeFormConnectivity = Data("""
        # unit meter
        v 0 0 0
        v 1 0 0
        v 0 1 0
        con 1 1 1 1 1 1 1 1
        f 1 2 3
        """.utf8)

        #expect(throws: ImportError.self) {
            _ = try OBJExchange(tolerance: .standard).import(objWithLine)
        }
        #expect(throws: ImportError.self) {
            _ = try OBJExchange(tolerance: .standard).import(objWithPoint)
        }
        #expect(throws: ImportError.self) {
            _ = try OBJExchange(tolerance: .standard).import(objWithFreeFormConnectivity)
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func objImporterRejectsUnsupportedSemanticRecords() {
        let objWithMaterialLibrary = Data("""
        # unit meter
        mtllib materials.mtl
        v 0 0 0
        v 1 0 0
        v 0 1 0
        f 1 2 3
        """.utf8)
        let objWithMaterialAssignment = Data("""
        # unit meter
        v 0 0 0
        v 1 0 0
        v 0 1 0
        usemtl red
        f 1 2 3
        """.utf8)
        let objWithSmoothingGroup = Data("""
        # unit meter
        v 0 0 0
        v 1 0 0
        v 0 1 0
        s 1
        f 1 2 3
        """.utf8)

        #expect(throws: ImportError.self) {
            _ = try OBJExchange(tolerance: .standard).import(objWithMaterialLibrary)
        }
        #expect(throws: ImportError.self) {
            _ = try OBJExchange(tolerance: .standard).import(objWithMaterialAssignment)
        }
        #expect(throws: ImportError.self) {
            _ = try OBJExchange(tolerance: .standard).import(objWithSmoothingGroup)
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func objImporterRejectsUnrecognizedRecordsInsteadOfPartialImport() {
        let objWithMergingGroup = Data("""
        # unit meter
        v 0 0 0
        v 1 0 0
        v 0 1 0
        mg 1 0.5
        f 1 2 3
        """.utf8)

        #expect(throws: ImportError.self) {
            _ = try OBJExchange(tolerance: .standard).import(objWithMergingGroup)
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func meshImportersRejectMalformedKnownRecordsInsteadOfPartialImport() {
        let objWithIncompleteVertex = Data("""
        # unit meter
        v 0 0
        v 0 0 0
        v 1 0 0
        v 0 1 0
        f 2 3 4
        """.utf8)
        let objWithIncompleteFace = Data("""
        # unit meter
        v 0 0 0
        v 1 0 0
        v 0 1 0
        f 1 2
        f 1 2 3
        """.utf8)
        let objWithExtraVertexFields = Data("""
        # unit meter
        v 0 0 0 1 2
        v 1 0 0
        v 0 1 0
        f 1 2 3
        """.utf8)
        let objWithMalformedNormal = Data("""
        # unit meter
        v 0 0 0
        v 1 0 0
        v 0 1 0
        vn nan 0 1
        f 1 2 3
        """.utf8)
        let objWithMalformedFaceSubfield = Data("""
        # unit meter
        v 0 0 0
        v 1 0 0
        v 0 1 0
        f 1//bad 2//bad 3//bad
        """.utf8)
        let objWithUnsupportedTextureDepth = Data("""
        # unit meter
        v 0 0 0
        v 1 0 0
        v 0 1 0
        vt 0 0 1
        f 1/1 2/1 3/1
        """.utf8)
        let objWithMixedNormalReferences = Data("""
        # unit meter
        v 0 0 0
        v 1 0 0
        v 0 1 0
        vn 0 0 1
        f 1//1 2 3//1
        """.utf8)
        let dxfWithMalformedCoordinate = Data("""
        0
        SECTION
        2
        ENTITIES
        0
        3DFACE
        10
        bad
        10
        0
        20
        0
        30
        0
        11
        1
        21
        0
        31
        0
        12
        0
        22
        1
        32
        0
        0
        ENDSEC
        0
        EOF
        """.utf8)
        let dxfWithDuplicateCoordinate = Data("""
        0
        SECTION
        2
        ENTITIES
        0
        3DFACE
        10
        0
        10
        0
        20
        0
        30
        0
        11
        1
        21
        0
        31
        0
        12
        0
        22
        1
        32
        0
        0
        ENDSEC
        0
        EOF
        """.utf8)
        let svgWithIncompletePolygon = Data("""
        <svg xmlns="http://www.w3.org/2000/svg" data-unit="meter">
          <polygon points="0,0 1,0"/>
          <polygon points="0,0 1,0 0,1"/>
        </svg>
        """.utf8)

        #expect(throws: ImportError.self) {
            _ = try OBJExchange(tolerance: .standard).import(objWithIncompleteVertex)
        }
        #expect(throws: ImportError.self) {
            _ = try OBJExchange(tolerance: .standard).import(objWithIncompleteFace)
        }
        #expect(throws: ImportError.self) {
            _ = try OBJExchange(tolerance: .standard).import(objWithExtraVertexFields)
        }
        #expect(throws: ImportError.self) {
            _ = try OBJExchange(tolerance: .standard).import(objWithMalformedNormal)
        }
        #expect(throws: ImportError.self) {
            _ = try OBJExchange(tolerance: .standard).import(objWithMalformedFaceSubfield)
        }
        #expect(throws: ImportError.self) {
            _ = try OBJExchange(tolerance: .standard).import(objWithUnsupportedTextureDepth)
        }
        #expect(throws: ImportError.self) {
            _ = try OBJExchange(tolerance: .standard).import(objWithMixedNormalReferences)
        }
        #expect(throws: ImportError.self) {
            _ = try DXFExchange(tolerance: .standard).import(dxfWithMalformedCoordinate)
        }
        #expect(throws: ImportError.self) {
            _ = try DXFExchange(tolerance: .standard).import(dxfWithDuplicateCoordinate)
        }
        #expect(throws: ImportError.self) {
            _ = try SVGExchange(tolerance: .standard).import(svgWithIncompletePolygon)
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func polygonImportersTriangulateSupportedPolygonRecords() throws {
        let obj = Data("""
        # unit meter
        v 0 0 0
        v 1 0 0
        v 1 1 0
        v 0 1 0
        f 1 2 3 4
        """.utf8)
        let svg = Data("""
        <svg xmlns="http://www.w3.org/2000/svg" data-unit="meter">
          <polygon points="0,0 2,0 1,1 2,2 0,2"/>
        </svg>
        """.utf8)
        let dxf = Data(dxfQuadrilateral3DFACE().utf8)

        let objMesh = try #require(OBJExchange(tolerance: .standard).import(obj).meshes.values.first)
        let svgMesh = try #require(SVGExchange(tolerance: .standard).import(svg).meshes.values.first)
        let dxfMesh = try #require(DXFExchange(tolerance: .standard).import(dxf).meshes.values.first)

        #expect(objMesh.indices.count == 6)
        #expect(svgMesh.indices.count == 9)
        #expect(dxfMesh.indices.count == 6)
        #expect(abs(triangleMeshArea(objMesh) - 1.0) < 1.0e-12)
        #expect(abs(triangleMeshArea(svgMesh) - 3.0) < 1.0e-12)
        #expect(abs(triangleMeshArea(dxfMesh) - 1.0) < 1.0e-12)
    }

    @Test(.timeLimit(.minutes(1)))
    func storedZipRejectsLocalCentralHeaderMismatch() throws {
        let archive = try StoredZipArchive.make(entries: [
            StoredZipArchive.Entry(path: "a.txt", data: Data("content".utf8))
        ])
        var corrupted = archive
        corrupted.replaceSubrange(30..<35, with: Data("b.txt".utf8))

        #expect(throws: ZipArchiveError.self) {
            _ = try StoredZipArchive.readEntries(from: corrupted)
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func rawDeflateDecoderHandlesFixedAndDynamicHuffmanBlocksWithBounds() throws {
        let fixed = try data(hexEncoded: "cb48cdc9c957c8409000")
        let fixedDecoded = try fixed.withUnsafeBytes {
            try RawDeflateDecoder.decode($0, expectedByteCount: 17, maximumByteCount: 17)
        }
        #expect(fixedDecoded == Data("hello hello hello".utf8))

        let dynamic = try data(hexEncoded: "edcbd10983301400c055de00a593b884c4200f8c9124eedf417af77f5b1fb5453ef36d71f4ab8f98b9626f757da2f47bd6b2ea7a47ec473e394bde67d42bd737365114455114455114455114455114455114455114455114455114455114455114ff35fe00")
        let expected = Data(String(repeating: "Lorem ipsum dolor sit amet, consectetur adipiscing elit. ", count: 200).utf8)
        let dynamicDecoded = try dynamic.withUnsafeBytes {
            try RawDeflateDecoder.decode(
                $0,
                expectedByteCount: expected.count,
                maximumByteCount: expected.count
            )
        }
        #expect(dynamicDecoded == expected)

        #expect(throws: RawDeflateError.self) {
            _ = try dynamic.withUnsafeBytes {
                try RawDeflateDecoder.decode(
                    $0,
                    expectedByteCount: expected.count,
                    maximumByteCount: expected.count - 1
                )
            }
        }
        var trailing = fixed
        trailing.append(0)
        #expect(throws: RawDeflateError.self) {
            _ = try trailing.withUnsafeBytes {
                try RawDeflateDecoder.decode($0, expectedByteCount: 17, maximumByteCount: 17)
            }
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func storedZipBoundsDeflatedExpansionAndRejectsCorruption() throws {
        let uncompressed = Data(
            String(repeating: "Lorem ipsum dolor sit amet, consectetur adipiscing elit. ", count: 200).utf8
        )
        let compressed = try data(hexEncoded: "edcbd10983301400c055de00a593b884c4200f8c9124eedf417af77f5b1fb5453ef36d71f4ab8f98b9626f757da2f47bd6b2ea7a47ec473e394bde67d42bd737365114455114455114455114455114455114455114455114455114455114455114ff35fe00")
        let archive = try deflatedZipArchive(
            entries: [StoredZipArchive.Entry(path: "model.xml", data: uncompressed)],
            usesDataDescriptors: false,
            compression: { _ in compressed }
        )
        let nameLength = Int(archive[26]) | (Int(archive[27]) << 8)
        let extraLength = Int(archive[28]) | (Int(archive[29]) << 8)
        let compressedStart = 30 + nameLength + extraLength
        let compressedEnd = compressedStart + compressed.count
        let archivedCompressedPayload = Data(archive[compressedStart..<compressedEnd])
        #expect(archivedCompressedPayload == compressed)
        let decodedPayload = try archivedCompressedPayload.withUnsafeBytes {
            try RawDeflateDecoder.decode(
                $0,
                expectedByteCount: uncompressed.count,
                maximumByteCount: Int(UInt32.max)
            )
        }
        #expect(decodedPayload == uncompressed)

        #expect(throws: ZipArchiveError.self) {
            _ = try StoredZipArchive.withBorrowedEntries(
                from: archive,
                maximumEntryCount: 1,
                maximumTotalUncompressedBytes: uncompressed.count - 1
            ) { $0 }
        }
        let decoded = try StoredZipArchive.readEntries(from: archive)
        #expect(decoded["model.xml"] == uncompressed)

        var corrupted = archive
        corrupted[compressedStart] ^= 0xff
        #expect(throws: ZipArchiveError.self) {
            _ = try StoredZipArchive.readEntries(from: corrupted)
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func storedZipRejectsMismatchedDataDescriptors() throws {
        var archive = try deflatedZipArchive(
            entries: [StoredZipArchive.Entry(path: "a.txt", data: Data("content".utf8))],
            usesDataDescriptors: true
        )
        let signature = Data([0x50, 0x4b, 0x07, 0x08])
        let descriptorRange = try #require(archive.range(of: signature))
        archive[descriptorRange.upperBound] ^= 0xff

        #expect(throws: ZipArchiveError.self) {
            _ = try StoredZipArchive.readEntries(from: archive)
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func storedZipRejectsUnsafeAndDuplicateEntryPaths() throws {
        #expect(throws: ZipArchiveError.self) {
            _ = try StoredZipArchive.make(entries: [
                StoredZipArchive.Entry(path: "../document.json", data: Data())
            ])
        }
        #expect(throws: ZipArchiveError.self) {
            _ = try StoredZipArchive.make(entries: [
                StoredZipArchive.Entry(path: "document.json", data: Data("first".utf8)),
                StoredZipArchive.Entry(path: "document.json", data: Data("second".utf8))
            ])
        }
        #expect(throws: ZipArchiveError.self) {
            _ = try StoredZipArchive.readEntries(from: storedZipArchiveWithUnsafePath())
        }
        #expect(throws: ZipArchiveError.self) {
            _ = try StoredZipArchive.readEntries(from: storedZipArchiveWithDuplicateCentralEntries())
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func storedZipRejectsUnreferencedLocalEntries() {
        let archive = storedZipArchiveWithUnreferencedLocalEntry()

        #expect(throws: ZipArchiveError.self) {
            _ = try StoredZipArchive.readEntries(from: archive)
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func storedZipRejectsEndOfCentralDirectoryCommentMismatch() throws {
        var archive = try StoredZipArchive.make(entries: [
            StoredZipArchive.Entry(path: "a.txt", data: Data("content".utf8))
        ])
        archive.append(0)

        #expect(throws: ZipArchiveError.self) {
            _ = try StoredZipArchive.readEntries(from: archive)
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func storedZipRejectsEndOfCentralDirectoryComments() throws {
        var archive = try StoredZipArchive.make(entries: [
            StoredZipArchive.Entry(path: "a.txt", data: Data("content".utf8))
        ])
        var comment = Data()
        comment.appendLittleEndian(UInt32(0x06054b50))
        comment.append(Data("not-an-eocd-record-padding".utf8))
        var commentLength = Data()
        commentLength.appendLittleEndian(UInt16(comment.count))
        archive.replaceSubrange((archive.count - 2)..<archive.count, with: commentLength)
        archive.append(comment)

        #expect(throws: ZipArchiveError.self) {
            _ = try StoredZipArchive.readEntries(from: archive)
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func storedZipRejectsExtraAndFileCommentFields() {
        let archiveWithCentralExtra = storedZipArchive(
            path: "document.json",
            data: Data("content".utf8),
            centralExtra: Data([0x00])
        )
        let archiveWithCentralComment = storedZipArchive(
            path: "document.json",
            data: Data("content".utf8),
            centralComment: Data("comment".utf8)
        )
        let archiveWithLocalExtra = storedZipArchive(
            path: "document.json",
            data: Data("content".utf8),
            localExtra: Data([0x00])
        )

        #expect(throws: ZipArchiveError.self) {
            _ = try StoredZipArchive.readEntries(from: archiveWithCentralExtra)
        }
        #expect(throws: ZipArchiveError.self) {
            _ = try StoredZipArchive.readEntries(from: archiveWithCentralComment)
        }
        #expect(throws: ZipArchiveError.self) {
            _ = try StoredZipArchive.readEntries(from: archiveWithLocalExtra)
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func storedZipRejectsCentralDirectoryStoredSizeMismatch() {
        let archive = storedZipArchive(
            path: "document.json",
            data: Data("content".utf8),
            centralUncompressedSize: 8
        )

        #expect(throws: ZipArchiveError.self) {
            _ = try StoredZipArchive.readEntries(from: archive)
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func storedZipRejectsUnsupportedGeneralPurposeFlags() {
        let archiveWithCentralFlag = storedZipArchive(
            path: "document.json",
            data: Data("content".utf8),
            centralFlags: 1
        )
        let archiveWithLocalFlag = storedZipArchive(
            path: "document.json",
            data: Data("content".utf8),
            localFlags: 1
        )

        #expect(throws: ZipArchiveError.self) {
            _ = try StoredZipArchive.readEntries(from: archiveWithCentralFlag)
        }
        #expect(throws: ZipArchiveError.self) {
            _ = try StoredZipArchive.readEntries(from: archiveWithLocalFlag)
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func meshExchangeFormatsPreserveAllLengthUnits() throws {
        for unit in LengthUnit.allCases {
            let mesh = unitTriangleMesh(unit: unit)
            let expected = expectedExtents(unit: unit)
            var importedModels: [(format: ExchangeFileFormat, model: ImportedExchangeModel)] = [
                (.stl, try STLExporter(tolerance: .standard).importBinary(STLExporter(tolerance: .standard).exportBinary(meshes: [BodyID(): mesh], options: STLExportOptions(lengthUnit: unit)))),
                (.obj, try OBJExchange(tolerance: .standard).import(OBJExchange(tolerance: .standard).export(meshes: [BodyID(): mesh], unit: unit))),
                (.dxf, try DXFExchange(tolerance: .standard).import(DXFExchange(tolerance: .standard).export(meshes: [BodyID(): mesh], unit: unit))),
                (.svg, try SVGExchange(tolerance: .standard).import(SVGExchange(tolerance: .standard).export(meshes: [BodyID(): mesh], unit: unit)))
            ]
            if isThreeMFSupportedLengthUnit(unit) {
                importedModels.append(
                    (
                        .threeMF,
                        try ThreeMFExchange(tolerance: .standard).import(
                            ThreeMFExchange(tolerance: .standard).export(meshes: [BodyID(): mesh], unit: unit)
                        )
                    )
                )
            }

            for imported in importedModels {
                #expect(imported.model.units.length == unit)
                let extents = try meshExtents(imported.model.meshes)
                #expect(abs(extents.width - expected.width) < 1.0e-5)
                #expect(abs(extents.height - expected.height) < 1.0e-5)
                if imported.format == .svg {
                    #expect(abs(extents.depth) < 1.0e-9)
                } else {
                    #expect(abs(extents.depth - expected.depth) < 1.0e-5)
                }
            }
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func threeMFExporterRejectsKilometerUnits() throws {
        let mesh = unitTriangleMesh(unit: .kilometer)

        #expect(throws: ExportError.self) {
            _ = try ThreeMFExchange(tolerance: .standard).export(meshes: [BodyID(): mesh], unit: .kilometer)
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func exactIGESExportDoesNotDowngradeMeshes() throws {
        let mesh = unitTriangleMesh(unit: .meter)
        #expect(throws: KernelError.self) {
            _ = try IGESExchange(tolerance: .standard).export(meshes: [BodyID(): mesh])
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func dxfImporterUsesHeaderSectionForLengthUnit() throws {
        let imported = try DXFExchange(tolerance: .standard).import(Data(dxfWithEntitySectionUnitTrap().utf8), unit: .meter)
        let extents = try meshExtents(imported.meshes)

        #expect(imported.units.length == .meter)
        #expect(abs(extents.width - 2.0) < 1.0e-9)
        #expect(abs(extents.height - 3.0) < 1.0e-9)
        #expect(abs(extents.depth - 4.0) < 1.0e-9)
    }

    @Test(.timeLimit(.minutes(1)))
    func dxfImporterUsesFallbackForUnitlessHeader() throws {
        let imported = try DXFExchange(tolerance: .standard).import(dxfWithUnitlessHeader(), unit: .centimeter)
        let extents = try meshExtents(imported.meshes)

        #expect(imported.units.length == .centimeter)
        #expect(abs(extents.width - LengthUnit.centimeter.toInternal(2.0)) < 1.0e-9)
        #expect(abs(extents.height - LengthUnit.centimeter.toInternal(3.0)) < 1.0e-9)
        #expect(abs(extents.depth - LengthUnit.centimeter.toInternal(4.0)) < 1.0e-9)
    }

    @Test(.timeLimit(.minutes(1)))
    func dxfImporterTriangulatesQuadrilateral3DFACEWithoutChangingArea() throws {
        let imported = try DXFExchange(tolerance: .standard).import(Data(dxfQuadrilateral3DFACE().utf8))
        let mesh = try #require(imported.meshes.values.first)

        #expect(mesh.positions.count == 6)
        #expect(mesh.indices == [0, 1, 2, 3, 4, 5])
        #expect(abs(triangleMeshArea(mesh) - 1.0) < 1.0e-12)
    }

    @Test(.timeLimit(.minutes(1)))
    func dxfExchangeWritesAC1027AndRejectsAnotherDeclaredVersion() throws {
        let exchange = DXFExchange(tolerance: .standard)
        let exported = try exchange.export(meshes: [BodyID(): unitTriangleMesh(unit: .meter)])
        let text = try #require(String(data: exported, encoding: .ascii))
        #expect(text.contains("$ACADVER\n1\nAC1027"))

        let unsupported = Data(text.replacingOccurrences(of: "AC1027", with: "AC1032").utf8)
        #expect(throws: ImportError.self) {
            _ = try exchange.import(unsupported)
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func dxfExchangeRejectsNonASCIIAndEnforcesTypedResourceLimits() throws {
        let nonASCII = Data(dxfQuadrilateral3DFACE().replacingOccurrences(of: "SwiftCAD", with: "SwiftCAD設").utf8)
        #expect(throws: ImportError.self) {
            _ = try DXFExchange(tolerance: .standard).import(nonASCII)
        }

        let mesh = unitTriangleMesh(unit: .meter)
        let entityLimited = DXFExchange(
            tolerance: .standard,
            resourceLimits: ExchangeResourceLimits(maximumEntities: 4)
        )
        let byteLimited = DXFExchange(
            tolerance: .standard,
            resourceLimits: ExchangeResourceLimits(maximumBytes: 16)
        )

        do {
            _ = try entityLimited.export(meshes: [BodyID(): mesh])
            Issue.record("Expected DXF entity accounting to reject the export.")
        } catch let error as KernelError {
            #expect(error.phase == .exchange)
            #expect(error.code == .resourceLimitExceeded)
        }
        do {
            _ = try byteLimited.import(Data(dxfQuadrilateral3DFACE().utf8))
            Issue.record("Expected DXF input byte accounting to reject the import.")
        } catch let error as KernelError {
            #expect(error.phase == .exchange)
            #expect(error.code == .resourceLimitExceeded)
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func dxfImporterRejectsDuplicateHeaderUnitDeclarations() {
        #expect(throws: ImportError.self) {
            _ = try DXFExchange(tolerance: .standard).import(Data(dxfWithDuplicateHeaderUnitDeclarations().utf8))
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func dxfImporterRejects3DFACEOutsideEntitiesSection() {
        #expect(throws: ImportError.self) {
            _ = try DXFExchange(tolerance: .standard).import(Data(dxfWithHeader3DFACETrap().utf8))
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func dxfImporterRejectsUnsupportedRecordsOutsideEntitiesSection() {
        let dxfWithTopLevelEntity = Data("""
        0
        SECTION
        2
        HEADER
        0
        ENDSEC
        0
        LINE
        10
        0
        20
        0
        30
        0
        11
        1
        21
        0
        31
        0
        0
        SECTION
        2
        ENTITIES
        0
        3DFACE
        10
        0
        20
        0
        30
        0
        11
        1
        21
        0
        31
        0
        12
        0
        22
        1
        32
        0
        0
        ENDSEC
        0
        EOF
        """.utf8)
        let dxfWithTopLevelGroupPayload = Data("""
        0
        SECTION
        2
        ENTITIES
        0
        3DFACE
        10
        0
        20
        0
        30
        0
        11
        1
        21
        0
        31
        0
        12
        0
        22
        1
        32
        0
        0
        ENDSEC
        999
        hidden payload
        0
        EOF
        """.utf8)

        #expect(throws: ImportError.self) {
            _ = try DXFExchange(tolerance: .standard).import(dxfWithTopLevelEntity)
        }
        #expect(throws: ImportError.self) {
            _ = try DXFExchange(tolerance: .standard).import(dxfWithTopLevelGroupPayload)
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func dxfImporterRejectsUnsupportedEntitiesInsteadOfPartialImport() {
        let dxf = Data("""
        0
        SECTION
        2
        ENTITIES
        0
        LINE
        10
        0
        20
        0
        30
        0
        11
        1
        21
        0
        31
        0
        0
        3DFACE
        10
        0
        20
        0
        30
        0
        11
        1
        21
        0
        31
        0
        12
        0
        22
        1
        32
        0
        0
        ENDSEC
        0
        EOF
        """.utf8)

        #expect(throws: ImportError.self) {
            _ = try DXFExchange(tolerance: .standard).import(dxf)
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func dxfImporterRejectsUnsupportedAndDuplicateSections() {
        let dxfWithUnsupportedSection = Data("""
        0
        SECTION
        2
        TABLES
        999
        hidden payload
        0
        ENDSEC
        0
        SECTION
        2
        ENTITIES
        0
        3DFACE
        10
        0
        20
        0
        30
        0
        11
        1
        21
        0
        31
        0
        12
        0
        22
        1
        32
        0
        0
        ENDSEC
        0
        EOF
        """.utf8)
        let dxfWithDuplicateHeader = Data("""
        0
        SECTION
        2
        HEADER
        9
        $INSUNITS
        70
        6
        0
        ENDSEC
        0
        SECTION
        2
        HEADER
        9
        $INSUNITS
        70
        4
        0
        ENDSEC
        0
        SECTION
        2
        ENTITIES
        0
        3DFACE
        10
        0
        20
        0
        30
        0
        11
        1
        21
        0
        31
        0
        12
        0
        22
        1
        32
        0
        0
        ENDSEC
        0
        EOF
        """.utf8)

        #expect(throws: ImportError.self) {
            _ = try DXFExchange(tolerance: .standard).import(dxfWithUnsupportedSection)
        }
        #expect(throws: ImportError.self) {
            _ = try DXFExchange(tolerance: .standard).import(dxfWithDuplicateHeader)
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func dxfImporterRejectsMalformedTokenStreamAndUnterminatedHeader() {
        let dxfWithDanglingGroupCode = Data([
            "0", "SECTION",
            "2", "ENTITIES",
            "0", "3DFACE",
            "10", "0", "20", "0", "30", "0",
            "11", "1", "21", "0", "31", "0",
            "12", "0", "22", "1", "32", "0",
            "0", "ENDSEC",
            "999"
        ].joined(separator: "\n").utf8)
        let dxfWithNonIntegerGroupCode = Data([
            "0", "SECTION",
            "2", "ENTITIES",
            "BAD", "3DFACE",
            "0", "ENDSEC",
            "0", "EOF"
        ].joined(separator: "\n").utf8)
        let dxfWithoutEOF = Data([
            "0", "SECTION",
            "2", "ENTITIES",
            "0", "3DFACE",
            "10", "0", "20", "0", "30", "0",
            "11", "1", "21", "0", "31", "0",
            "12", "0", "22", "1", "32", "0",
            "0", "ENDSEC"
        ].joined(separator: "\n").utf8)
        let dxfWithTrailingRecordsAfterEOF = Data([
            "0", "SECTION",
            "2", "ENTITIES",
            "0", "3DFACE",
            "10", "0", "20", "0", "30", "0",
            "11", "1", "21", "0", "31", "0",
            "12", "0", "22", "1", "32", "0",
            "0", "ENDSEC",
            "0", "EOF",
            "999", "trailing"
        ].joined(separator: "\n").utf8)

        #expect(throws: ImportError.self) {
            _ = try DXFExchange(tolerance: .standard).import(dxfWithDanglingGroupCode)
        }
        #expect(throws: ImportError.self) {
            _ = try DXFExchange(tolerance: .standard).import(dxfWithNonIntegerGroupCode)
        }
        #expect(throws: ImportError.self) {
            _ = try DXFExchange(tolerance: .standard).import(dxfWithoutEOF)
        }
        #expect(throws: ImportError.self) {
            _ = try DXFExchange(tolerance: .standard).import(dxfWithTrailingRecordsAfterEOF)
        }
        #expect(throws: ImportError.self) {
            _ = try DXFExchange(tolerance: .standard).import(Data(dxfWithUnterminatedHeaderSection().utf8))
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func objImporterUsesLeadingPreambleForLengthUnit() throws {
        let obj = Data("""
        # Third-party OBJ without Swift-CAD unit metadata
        v 0 0 0
        v 2 0 0
        # unit millimeter
        v 0 3 4
        f 1 2 3
        """.utf8)

        let imported = try OBJExchange(tolerance: .standard).import(obj, unit: .meter)
        let extents = try meshExtents(imported.meshes)

        #expect(imported.units.length == .meter)
        #expect(abs(extents.width - 2.0) < 1.0e-9)
        #expect(abs(extents.height - 3.0) < 1.0e-9)
        #expect(abs(extents.depth - 4.0) < 1.0e-9)
    }

    @Test(.timeLimit(.minutes(1)))
    func objImporterRejectsDuplicateLeadingUnitDeclarations() {
        let obj = Data("""
        # unit meter
        # unit millimeter
        v 0 0 0
        v 1 0 0
        v 0 1 0
        f 1 2 3
        """.utf8)

        #expect(throws: ImportError.self) {
            _ = try OBJExchange(tolerance: .standard).import(obj)
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func stlImporterUsesSwiftCADHeaderPrefixForLengthUnit() throws {
        let imported = try STLExporter(tolerance: .standard).importBinary(binarySTLWithNonSwiftCADUnitMarkerTrap())
        let extents = try meshExtents(imported.meshes)

        #expect(imported.units.length == .meter)
        #expect(abs(extents.width - 2.0) < 1.0e-9)
        #expect(abs(extents.height - 3.0) < 1.0e-9)
        #expect(abs(extents.depth - 4.0) < 1.0e-9)
    }

    @Test(.timeLimit(.minutes(1)))
    func stlImporterRejectsMalformedSwiftCADUnitHeaders() throws {
        let headers = [
            Data("millimeter hidden".utf8),
            Data("millimeter\0hidden".utf8),
            Data(" millimeter".utf8)
        ]

        for header in headers {
            let stl = try binarySTLWithSwiftCADUnitHeaderSuffix(header)
            #expect(throws: ImportError.self) {
                _ = try STLExporter(tolerance: .standard).importBinary(stl)
            }
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func meshImportersRejectInvalidUnitMetadata() throws {
        let stl = try binarySTLWithUnitHeader("parsec")
        let obj = Data("""
        # unit parsec
        v 0 0 0
        v 1 0 0
        v 0 1 0
        f 1 2 3
        """.utf8)
        let dxf = try dxfWithInvalidUnitCode()
        let svg = Data("""
        <svg xmlns="http://www.w3.org/2000/svg" data-unit="parsec">
          <polygon points="0,0 1,0 0,1"/>
        </svg>
        """.utf8)
        let threeMF = try threeMFPackageWithInvalidUnit()

        #expect(throws: ImportError.self) {
            _ = try STLExporter(tolerance: .standard).importBinary(stl)
        }
        #expect(throws: ImportError.self) {
            _ = try OBJExchange(tolerance: .standard).import(obj)
        }
        #expect(throws: ImportError.self) {
            _ = try DXFExchange(tolerance: .standard).import(dxf)
        }
        #expect(throws: ImportError.self) {
            _ = try SVGExchange(tolerance: .standard).import(svg)
        }
        #expect(throws: ImportError.self) {
            _ = try ThreeMFExchange(tolerance: .standard).import(threeMF)
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func cadExchangeImportersRejectNonFiniteNumericPayloadsWithoutCrashing() throws {
        let step = try stepWithNonFiniteFaceIndex()
        let iges = Data(igesWithNonFiniteLineCoordinate().utf8)

        #expect(throws: KernelError.self) {
            _ = try STEPExchange(tolerance: .standard).import(step)
        }
        #expect(throws: ImportError.self) {
            _ = try IGESExchange(tolerance: .standard).import(iges)
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func stepImporterRejectsMalformedEntityStructure() throws {
        expectExchangeFailure {
            _ = try STEPExchange(tolerance: .standard).import(stepWithUnexpectedTupleContent())
        }
        expectExchangeFailure {
            _ = try STEPExchange(tolerance: .standard).import(stepWithDuplicateEntityID())
        }
        expectExchangeFailure {
            _ = try STEPExchange(tolerance: .standard).import(stepWithMalformedTopLevelEntityMarker())
        }
        expectExchangeFailure {
            _ = try STEPExchange(tolerance: .standard).import(stepWithTrailingCommaPointTuple())
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func stepImporterRejectsUnreferencedPointLists() throws {
        #expect(throws: KernelError.self) {
            _ = try STEPExchange(tolerance: .standard).import(stepWithUnreferencedPointList())
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func stepImporterRejectsUnsupportedDataEntitiesInsteadOfPartialImport() throws {
        expectExchangeFailure {
            _ = try STEPExchange(tolerance: .standard).import(stepWithUnsupportedDataEntity())
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func stepImporterRejectsEntitiesOutsideDataSection() {
        #expect(throws: ImportError.self) {
            _ = try STEPExchange(tolerance: .standard).import(stepWithHeaderEntityTrap())
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func stepImporterRejectsIncompleteOrTrailingExchangeEnvelope() throws {
        #expect(throws: ImportError.self) {
            _ = try STEPExchange(tolerance: .standard).import(stepWithoutExchangeTerminator())
        }
        #expect(throws: ImportError.self) {
            _ = try STEPExchange(tolerance: .standard).import(stepWithTrailingPayloadAfterExchangeTerminator())
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func stepImporterIgnoresQuotedStringsWhileScanningStructure() throws {
        #expect(throws: KernelError.self) {
            _ = try STEPExchange(tolerance: .standard).import(stepWithQuotedParserTraps())
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func stepImporterIgnoresUnitTokensInsideEntityQuotedStrings() throws {
        #expect(throws: KernelError.self) {
            _ = try STEPExchange(tolerance: .standard).import(stepWithOnlyQuotedUnitTokens())
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func stepImporterUsesGlobalUnitContextForLengthUnit() throws {
        #expect(throws: KernelError.self) {
            _ = try STEPExchange(tolerance: .standard).import(stepWithUnreferencedLengthUnitsBeforeContextUnit())
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func stepImporterRejectsUnsupportedGlobalLengthUnit() {
        expectExchangeFailure {
            _ = try STEPExchange(tolerance: .standard).import(stepWithUnsupportedGlobalLengthUnit())
        }
        expectExchangeFailure {
            _ = try STEPExchange(tolerance: .standard).import(stepWithUnrelatedLengthUnitAfterGlobalContextList())
        }
        expectExchangeFailure {
            _ = try STEPExchange(tolerance: .standard).import(stepWithMissingGlobalUnitReference())
        }
        expectExchangeFailure {
            _ = try STEPExchange(tolerance: .standard).import(stepWithAmbiguousGlobalLengthUnits())
        }
        expectExchangeFailure {
            _ = try STEPExchange(tolerance: .standard).import(stepWithMismatchedConversionLengthFactor())
        }
        expectExchangeFailure {
            _ = try STEPExchange(tolerance: .standard).import(stepWithMissingConversionLengthFactor())
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func igesImporterUsesGlobalSectionForLengthUnit() throws {
        expectExchangeFailure {
            _ = try IGESExchange(tolerance: .standard).import(igesWithStartSectionUnitTrap())
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func igesImporterRejectsMalformedType110Records() {
        #expect(throws: ImportError.self) {
            _ = try IGESExchange(tolerance: .standard).import(Data(igesWithMalformedType110BeforeValidTriangle().utf8))
        }
        #expect(throws: ImportError.self) {
            _ = try IGESExchange(tolerance: .standard).import(Data(igesWithUnterminatedType110Record().utf8))
        }
        #expect(throws: ImportError.self) {
            _ = try IGESExchange(tolerance: .standard).import(Data(igesWithTrailingCommaType110Record().utf8))
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func igesImporterRejectsUnsupportedEntityTypes() {
        #expect(throws: ImportError.self) {
            _ = try IGESExchange(tolerance: .standard).import(Data(igesWithUnsupportedEntityBeforeValidTriangle().utf8))
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func igesImporterRejectsOutOfBandRecordsAndInvalidSectionCounts() throws {
        let baseData = try igesWithStartSectionUnitTrap()
        let baseText = try #require(String(data: baseData, encoding: .utf8))

        let igesWithTrailingOutOfBandRecord = Data((baseText + "\nhidden payload").utf8)
        var unsupportedSectionRecords = baseText.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        let unsupportedSectionTerminateRecord = unsupportedSectionRecords.removeLast()
        unsupportedSectionRecords.append(igesTestSectionRecord("hidden payload", section: "X", sequence: 1))
        unsupportedSectionRecords.append(unsupportedSectionTerminateRecord)
        let igesWithUnsupportedSectionRecord = Data(unsupportedSectionRecords.joined(separator: "\n").utf8)
        var countMismatchRecords = baseText.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        let terminateRecord = try #require(countMismatchRecords.last)
        countMismatchRecords[countMismatchRecords.count - 1] = terminateRecord.replacingOccurrences(
            of: "P      3",
            with: "P      2"
        )
        let igesWithMismatchedTerminateCounts = Data(countMismatchRecords.joined(separator: "\n").utf8)

        #expect(throws: ImportError.self) {
            _ = try IGESExchange(tolerance: .standard).import(igesWithTrailingOutOfBandRecord)
        }
        #expect(throws: ImportError.self) {
            _ = try IGESExchange(tolerance: .standard).import(igesWithUnsupportedSectionRecord)
        }
        #expect(throws: ImportError.self) {
            _ = try IGESExchange(tolerance: .standard).import(igesWithMismatchedTerminateCounts)
        }
        #expect(throws: ImportError.self) {
            _ = try IGESExchange(tolerance: .standard).import(Data(igesWithParameterSectionButNoGlobalOrDirectory().utf8))
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func littleEndianReadersUseRelativeOffsetsForDataSlices() throws {
        let data = Data([0x99, 0x88, 0x34, 0x12, 0x78, 0x56])
        let slice = data[2..<6]

        #expect(try slice.littleEndianUInt16(at: 0) == 0x1234)
        #expect(try slice.littleEndianUInt32(at: 0) == 0x56781234)
    }

    @Test(.timeLimit(.minutes(1)))
    func stepNumberRoundTripsDoublePrecision() throws {
        let value = 1.2345678901234567
        let encoded = stepNumber(value)
        let decoded = try #require(Double(encoded))

        #expect(decoded == value)
    }

    @Test(.timeLimit(.minutes(1)))
    func svgExporterWritesViewBoxForProjectedPolygons() throws {
        let data = try SVGExchange(tolerance: .standard).export(meshes: [BodyID(): unitTriangleMesh(unit: .meter)], unit: .meter)
        let text = try #require(String(data: data, encoding: .utf8))

        #expect(text.contains("viewBox=\""))
    }
}

private let removedArchiveMarker = ["SWIFTCAD", "MESH", "ARCHIVE"].joined(separator: "_")

private func manifestDataWithFutureSchema(from manifestData: Data) throws -> Data {
    guard var manifest = try JSONSerialization.jsonObject(with: manifestData) as? [String: Any],
          var schemaVersion = manifest["schemaVersion"] as? [String: Any] else {
        throw SchemaError.invalidPackage("Manifest JSON shape is invalid.")
    }
    schemaVersion["major"] = 1
    manifest["schemaVersion"] = schemaVersion
    return try JSONSerialization.data(withJSONObject: manifest, options: [.sortedKeys])
}

private func documentDataWithInactiveOperationPayload(from documentData: Data) throws -> Data {
    guard var document = try JSONSerialization.jsonObject(with: documentData) as? [String: Any],
          var designGraph = document["designGraph"] as? [String: Any] else {
        throw SchemaError.invalidPackage("Document JSON shape is invalid.")
    }
    if var nodes = designGraph["nodes"] as? [String: Any],
       let nodeID = nodes.keys.sorted().first,
       var node = nodes[nodeID] as? [String: Any] {
        try addInactiveOperationPayload(to: &node)
        nodes[nodeID] = node
        designGraph["nodes"] = nodes
    } else if var nodes = designGraph["nodes"] as? [Any],
              nodes.count >= 2,
              var node = nodes[1] as? [String: Any] {
        try addInactiveOperationPayload(to: &node)
        nodes[1] = node
        designGraph["nodes"] = nodes
    } else {
        throw SchemaError.invalidPackage("Document JSON shape is invalid.")
    }
    document["designGraph"] = designGraph
    return try JSONSerialization.data(withJSONObject: document, options: [.sortedKeys])
}

private func documentDataWithMetadata(createdAt: String, updatedAt: String, from documentData: Data) throws -> Data {
    guard var document = try JSONSerialization.jsonObject(with: documentData) as? [String: Any],
          var metadata = document["metadata"] as? [String: Any] else {
        throw SchemaError.invalidPackage("Document JSON shape is invalid.")
    }
    metadata["createdAt"] = createdAt
    metadata["updatedAt"] = updatedAt
    document["metadata"] = metadata
    return try JSONSerialization.data(withJSONObject: document, options: [.sortedKeys])
}

private func nativeSweepDocumentFixture() -> (document: CADDocument, profileID: FeatureID, pathID: FeatureID, sweepID: FeatureID) {
    let profileID = FeatureID()
    let pathID = FeatureID()
    let sweepID = FeatureID()
    let sweep = SweepFeature(
        sections: [.profile(ProfileReference(featureID: profileID))],
        path: SweepPathReference(featureID: pathID)
    )
    let document = CADDocument(
        units: .meters,
        designGraph: DesignGraph(
            nodes: [
                profileID: FeatureNode(
                    id: profileID,
                    operation: .sketch(Sketch(plane: .xy)),
                    outputs: [FeatureOutput(role: .profile)]
                ),
                pathID: FeatureNode(
                    id: pathID,
                    operation: .sketch(Sketch(plane: .xy)),
                    outputs: [FeatureOutput(role: .curve)]
                ),
                sweepID: FeatureNode(
                    id: sweepID,
                    operation: .sweep(sweep),
                    inputs: [
                        FeatureInput(featureID: profileID, role: .profile),
                        FeatureInput(featureID: pathID, role: .path),
                    ],
                    outputs: [FeatureOutput(role: .body)]
                ),
            ],
            order: [profileID, pathID, sweepID],
            dependencies: [
                DependencyEdge(source: profileID, target: sweepID),
                DependencyEdge(source: pathID, target: sweepID),
            ]
        )
    )
    return (document, profileID, pathID, sweepID)
}

private func nativeLoftDocumentFixture() -> (
    document: CADDocument,
    firstProfileID: FeatureID,
    secondProfileID: FeatureID,
    thirdProfileID: FeatureID,
    loftID: FeatureID
) {
    let firstProfileID = FeatureID()
    let secondProfileID = FeatureID()
    let thirdProfileID = FeatureID()
    let loftID = FeatureID()
    let loft = LoftFeature(
        sections: [
            LoftSectionReference(
                profile: ProfileReference(featureID: firstProfileID),
                smoothTangentScale: 0.75,
                smoothTangentMode: .zero
            ),
            LoftSectionReference(profile: ProfileReference(featureID: secondProfileID)),
            LoftSectionReference(profile: ProfileReference(featureID: thirdProfileID)),
        ],
        options: LoftOptions(resultKind: .sheet, closesSectionLoop: true)
    )
    let document = CADDocument(
        units: .meters,
        designGraph: DesignGraph(
            nodes: [
                firstProfileID: FeatureNode(
                    id: firstProfileID,
                    operation: .sketch(Sketch(plane: .xy)),
                    outputs: [FeatureOutput(role: .profile)]
                ),
                secondProfileID: FeatureNode(
                    id: secondProfileID,
                    operation: .sketch(Sketch(plane: .xy)),
                    outputs: [FeatureOutput(role: .profile)]
                ),
                thirdProfileID: FeatureNode(
                    id: thirdProfileID,
                    operation: .sketch(Sketch(plane: .xy)),
                    outputs: [FeatureOutput(role: .profile)]
                ),
                loftID: FeatureNode(
                    id: loftID,
                    operation: .loft(loft),
                    inputs: [
                        FeatureInput(featureID: firstProfileID, role: .profile),
                        FeatureInput(featureID: secondProfileID, role: .profile),
                        FeatureInput(featureID: thirdProfileID, role: .profile),
                    ],
                    outputs: [FeatureOutput(role: .sheet)]
                ),
            ],
            order: [firstProfileID, secondProfileID, thirdProfileID, loftID],
            dependencies: [
                DependencyEdge(source: firstProfileID, target: loftID),
                DependencyEdge(source: secondProfileID, target: loftID),
                DependencyEdge(source: thirdProfileID, target: loftID),
            ]
        )
    )
    return (document, firstProfileID, secondProfileID, thirdProfileID, loftID)
}

private func nativeBooleanDocumentFixture() -> (document: CADDocument, targetID: FeatureID, toolID: FeatureID, booleanID: FeatureID) {
    let targetProfileID = FeatureID()
    let toolProfileID = FeatureID()
    let targetID = FeatureID()
    let toolID = FeatureID()
    let booleanID = FeatureID()
    let targetExtrude = ExtrudeFeature(
        profile: ProfileReference(featureID: targetProfileID),
        distance: .constant(.length(1.0, unit: .meter))
    )
    let toolExtrude = ExtrudeFeature(
        profile: ProfileReference(featureID: toolProfileID),
        distance: .constant(.length(1.0, unit: .meter))
    )
    let boolean = BooleanFeature(
        targets: [BooleanTargetReference(featureID: targetID)],
        tool: BooleanToolReference(featureID: toolID),
        operation: .difference,
        keepTools: true
    )
    let document = CADDocument(
        units: .meters,
        designGraph: DesignGraph(
            nodes: [
                targetProfileID: FeatureNode(
                    id: targetProfileID,
                    operation: .sketch(Sketch(plane: .xy)),
                    outputs: [FeatureOutput(role: .profile)]
                ),
                toolProfileID: FeatureNode(
                    id: toolProfileID,
                    operation: .sketch(Sketch(plane: .xy)),
                    outputs: [FeatureOutput(role: .profile)]
                ),
                targetID: FeatureNode(
                    id: targetID,
                    operation: .extrude(targetExtrude),
                    inputs: [FeatureInput(featureID: targetProfileID, role: .profile)],
                    outputs: [FeatureOutput(role: .body)]
                ),
                toolID: FeatureNode(
                    id: toolID,
                    operation: .extrude(toolExtrude),
                    inputs: [FeatureInput(featureID: toolProfileID, role: .profile)],
                    outputs: [FeatureOutput(role: .body)]
                ),
                booleanID: FeatureNode(
                    id: booleanID,
                    operation: .boolean(boolean),
                    inputs: [
                        FeatureInput(featureID: targetID, role: .target),
                        FeatureInput(featureID: toolID, role: .body),
                    ],
                    outputs: [FeatureOutput(role: .body)]
                ),
            ],
            order: [targetProfileID, toolProfileID, targetID, toolID, booleanID],
            dependencies: [
                DependencyEdge(source: targetProfileID, target: targetID),
                DependencyEdge(source: toolProfileID, target: toolID),
                DependencyEdge(source: targetID, target: booleanID),
                DependencyEdge(source: toolID, target: booleanID),
            ]
        )
    )
    return (document, targetID, toolID, booleanID)
}

private func documentDataByAddingLegacySweepProfiles(to documentData: Data, profileID: FeatureID) throws -> Data {
    guard var text = String(data: documentData, encoding: .utf8) else {
        throw SchemaError.invalidPackage("Document JSON fixture is not UTF-8.")
    }
    guard let sectionsRange = text.range(of: "\"sections\"") else {
        throw SchemaError.invalidPackage("Document JSON fixture does not contain sweep sections.")
    }
    let legacyProfiles = "\"profiles\":[{\"featureID\":\"\(profileID.description)\",\"profileIndex\":0}],"
    text.insert(contentsOf: legacyProfiles, at: sectionsRange.lowerBound)
    return Data(text.utf8)
}

private func documentDataBySettingLoftOption(_ option: String, to value: Any, in documentData: Data) throws -> Data {
    guard var document = try JSONSerialization.jsonObject(with: documentData) as? [String: Any],
          var designGraph = document["designGraph"] as? [String: Any] else {
        throw SchemaError.invalidPackage("Document JSON shape is invalid.")
    }
    var didUpdate = false
    if var nodes = designGraph["nodes"] as? [String: Any] {
        for nodeID in nodes.keys.sorted() {
            guard var node = nodes[nodeID] as? [String: Any] else {
                continue
            }
            if try setLoftOption(option, to: value, in: &node) {
                nodes[nodeID] = node
                didUpdate = true
                break
            }
        }
        designGraph["nodes"] = nodes
    } else if var nodes = designGraph["nodes"] as? [Any] {
        for index in nodes.indices {
            guard var node = nodes[index] as? [String: Any] else {
                continue
            }
            if try setLoftOption(option, to: value, in: &node) {
                nodes[index] = node
                didUpdate = true
                break
            }
        }
        designGraph["nodes"] = nodes
    } else {
        throw SchemaError.invalidPackage("Document JSON shape is invalid.")
    }
    guard didUpdate else {
        throw SchemaError.invalidPackage("Document JSON fixture does not contain a Loft operation.")
    }
    document["designGraph"] = designGraph
    return try JSONSerialization.data(withJSONObject: document, options: [.sortedKeys])
}

private func documentDataBySettingLoftSectionField(
    _ field: String,
    to value: Any,
    sectionIndex: Int,
    in documentData: Data
) throws -> Data {
    guard var document = try JSONSerialization.jsonObject(with: documentData) as? [String: Any],
          var designGraph = document["designGraph"] as? [String: Any] else {
        throw SchemaError.invalidPackage("Document JSON shape is invalid.")
    }
    var didUpdate = false
    if var nodes = designGraph["nodes"] as? [String: Any] {
        for nodeID in nodes.keys.sorted() {
            guard var node = nodes[nodeID] as? [String: Any] else {
                continue
            }
            if try setLoftSectionField(field, to: value, sectionIndex: sectionIndex, in: &node) {
                nodes[nodeID] = node
                didUpdate = true
                break
            }
        }
        designGraph["nodes"] = nodes
    } else if var nodes = designGraph["nodes"] as? [Any] {
        for index in nodes.indices {
            guard var node = nodes[index] as? [String: Any] else {
                continue
            }
            if try setLoftSectionField(field, to: value, sectionIndex: sectionIndex, in: &node) {
                nodes[index] = node
                didUpdate = true
                break
            }
        }
        designGraph["nodes"] = nodes
    } else {
        throw SchemaError.invalidPackage("Document JSON shape is invalid.")
    }
    guard didUpdate else {
        throw SchemaError.invalidPackage("Document JSON fixture does not contain a Loft operation.")
    }
    document["designGraph"] = designGraph
    return try JSONSerialization.data(withJSONObject: document, options: [.sortedKeys])
}

private func setLoftOption(_ option: String, to value: Any, in node: inout [String: Any]) throws -> Bool {
    guard var operation = node["operation"] as? [String: Any],
          var loft = operation["loft"] as? [String: Any] else {
        return false
    }
    guard var options = loft["options"] as? [String: Any] else {
        throw SchemaError.invalidPackage("Document JSON Loft fixture does not contain options.")
    }
    options[option] = value
    loft["options"] = options
    operation["loft"] = loft
    node["operation"] = operation
    return true
}

private func setLoftSectionField(
    _ field: String,
    to value: Any,
    sectionIndex: Int,
    in node: inout [String: Any]
) throws -> Bool {
    guard var operation = node["operation"] as? [String: Any],
          var loft = operation["loft"] as? [String: Any] else {
        return false
    }
    guard var sections = loft["sections"] as? [[String: Any]] else {
        throw SchemaError.invalidPackage("Document JSON Loft fixture does not contain sections.")
    }
    guard sections.indices.contains(sectionIndex) else {
        throw SchemaError.invalidPackage("Document JSON Loft fixture does not contain section index \(sectionIndex).")
    }
    sections[sectionIndex][field] = value
    loft["sections"] = sections
    operation["loft"] = loft
    node["operation"] = operation
    return true
}

private func addInactiveOperationPayload(to node: inout [String: Any]) throws {
    guard var operation = node["operation"] as? [String: Any] else {
        throw SchemaError.invalidPackage("Document JSON shape is invalid.")
    }
    operation["extrude"] = try jsonObject(from: JSONEncoder().encode(ExtrudeFeature(
        profile: ProfileReference(featureID: FeatureID()),
        distance: .constant(.length(1.0, unit: .meter))
    )))
    node["operation"] = operation
}

private func jsonDataWithDuplicateTopLevelStringField(named field: String, in data: Data) throws -> Data {
    guard let text = String(data: data, encoding: .utf8) else {
        throw SchemaError.invalidPackage("JSON fixture is not UTF-8.")
    }
    guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
          let value = object[field] as? String else {
        throw SchemaError.invalidPackage("JSON fixture does not contain a string field \(field).")
    }
    guard let openingBrace = text.firstIndex(of: "{") else {
        throw SchemaError.invalidPackage("JSON fixture is not an object.")
    }
    var patched = text
    let insertionIndex = patched.index(after: openingBrace)
    let duplicateField = "\n  \"\(jsonEscapedString(field))\" : \"\(jsonEscapedString(value))\","
    patched.insert(contentsOf: duplicateField, at: insertionIndex)
    return Data(patched.utf8)
}

private func jsonEscapedString(_ value: String) -> String {
    var output = ""
    for character in value {
        switch character {
        case "\"":
            output.append("\\\"")
        case "\\":
            output.append("\\\\")
        case "\n":
            output.append("\\n")
        case "\r":
            output.append("\\r")
        case "\t":
            output.append("\\t")
        default:
            output.append(character)
        }
    }
    return output
}

private func jsonData(byAdding fields: [String: Any], to data: Data) throws -> Data {
    guard var object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
        throw SchemaError.invalidPackage("Expected JSON object fixture.")
    }
    for (key, value) in fields {
        object[key] = value
    }
    return try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
}

private func jsonData(byAdding fields: [String: Any], at path: [String], to data: Data) throws -> Data {
    guard var object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
        throw SchemaError.invalidPackage("Expected JSON object fixture.")
    }
    try addJSONFields(fields, at: path[...], in: &object)
    return try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
}

private func jsonData(
    byAdding fields: [String: Any],
    atFirstDynamicDictionaryValue path: [String],
    to data: Data
) throws -> Data {
    guard var object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
        throw SchemaError.invalidPackage("Expected JSON object fixture.")
    }
    try addJSONFieldsToFirstDynamicDictionaryValue(fields, at: path[...], in: &object)
    return try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
}

private func jsonData(
    byDuplicatingFirstDynamicDictionaryEntryAt path: [String],
    in data: Data
) throws -> Data {
    guard var object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
        throw SchemaError.invalidPackage("Expected JSON object fixture.")
    }
    try duplicateFirstDynamicDictionaryEntry(at: path[...], in: &object)
    return try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
}

private func jsonData(
    byDuplicatingFirstDynamicDictionaryEntryWithLowercaseKeyAt path: [String],
    in data: Data
) throws -> Data {
    guard var object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
        throw SchemaError.invalidPackage("Expected JSON object fixture.")
    }
    try duplicateFirstDynamicDictionaryEntryWithLowercaseKey(at: path[...], in: &object)
    return try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
}

private func jsonDataByDuplicatingFirstSketchEntityEntry(in data: Data) throws -> Data {
    guard var document = try JSONSerialization.jsonObject(with: data) as? [String: Any],
          var designGraph = document["designGraph"] as? [String: Any],
          var nodes = designGraph["nodes"] as? [Any],
          nodes.count >= 2,
          var node = nodes[1] as? [String: Any],
          var operation = node["operation"] as? [String: Any],
          var sketch = operation["sketch"] as? [String: Any],
          var entities = sketch["entities"] as? [Any],
          entities.count >= 2 else {
        throw SchemaError.invalidPackage("Expected array-encoded sketch entities fixture.")
    }
    entities.append(entities[0])
    entities.append(entities[1])
    sketch["entities"] = entities
    operation["sketch"] = sketch
    node["operation"] = operation
    nodes[1] = node
    designGraph["nodes"] = nodes
    document["designGraph"] = designGraph
    return try JSONSerialization.data(withJSONObject: document, options: [.sortedKeys])
}

private func jsonDataByDuplicatingFirstSketchEntityEntryWithLowercaseKey(in data: Data) throws -> Data {
    guard var document = try JSONSerialization.jsonObject(with: data) as? [String: Any],
          var designGraph = document["designGraph"] as? [String: Any],
          var nodes = designGraph["nodes"] as? [Any],
          nodes.count >= 2,
          var node = nodes[1] as? [String: Any],
          var operation = node["operation"] as? [String: Any],
          var sketch = operation["sketch"] as? [String: Any],
          var entities = sketch["entities"] as? [Any],
          entities.count >= 2,
          let key = entities[0] as? String else {
        throw SchemaError.invalidPackage("Expected array-encoded sketch entities fixture.")
    }
    entities.append(key.lowercased())
    entities.append(entities[1])
    sketch["entities"] = entities
    operation["sketch"] = sketch
    node["operation"] = operation
    nodes[1] = node
    designGraph["nodes"] = nodes
    document["designGraph"] = designGraph
    return try JSONSerialization.data(withJSONObject: document, options: [.sortedKeys])
}

private func documentDataByAddingUnsupportedSelectionDimensionField(to data: Data) throws -> Data {
    guard var document = try JSONSerialization.jsonObject(with: data) as? [String: Any],
          var dimensions = document["selectionDimensions"] as? [[String: Any]],
          dimensions.isEmpty == false else {
        throw SchemaError.invalidPackage("Expected native selection dimension fixture.")
    }
    dimensions[0]["unexpected"] = true
    document["selectionDimensions"] = dimensions
    return try JSONSerialization.data(withJSONObject: document, options: [.sortedKeys])
}

private func jsonDataByConvertingNativeDynamicDictionariesToObjectMaps(in data: Data) throws -> Data {
    guard var document = try JSONSerialization.jsonObject(with: data) as? [String: Any],
          var parameters = document["parameters"] as? [String: Any],
          var designGraph = document["designGraph"] as? [String: Any],
          var nodes = designGraph["nodes"] as? [Any] else {
        throw SchemaError.invalidPackage("Expected native document fixture.")
    }

    parameters["parameters"] = try objectMap(fromDynamicPairs: parameters["parameters"])
    document["parameters"] = parameters

    var valueIndex = 1
    while valueIndex < nodes.count {
        if var node = nodes[valueIndex] as? [String: Any] {
            try convertSketchEntitiesToObjectMap(in: &node)
            nodes[valueIndex] = node
        }
        valueIndex += 2
    }
    designGraph["nodes"] = try objectMap(fromDynamicPairs: nodes)
    document["designGraph"] = designGraph
    return try JSONSerialization.data(withJSONObject: document, options: [.sortedKeys])
}

private func convertSketchEntitiesToObjectMap(in node: inout [String: Any]) throws {
    guard var operation = node["operation"] as? [String: Any],
          var sketch = operation["sketch"] as? [String: Any] else {
        return
    }
    sketch["entities"] = try objectMap(fromDynamicPairs: sketch["entities"])
    operation["sketch"] = sketch
    node["operation"] = operation
}

private func objectMap(fromDynamicPairs value: Any?) throws -> [String: Any] {
    guard let pairs = value as? [Any],
          pairs.count.isMultiple(of: 2) else {
        throw SchemaError.invalidPackage("Expected array-encoded dynamic dictionary fixture.")
    }
    var output: [String: Any] = [:]
    var valueIndex = 1
    while valueIndex < pairs.count {
        guard let key = pairs[valueIndex - 1] as? String else {
            throw SchemaError.invalidPackage("Expected dynamic dictionary key fixture.")
        }
        output[key] = pairs[valueIndex]
        valueIndex += 2
    }
    return output
}

private func addJSONFields(
    _ fields: [String: Any],
    at path: ArraySlice<String>,
    in object: inout [String: Any]
) throws {
    guard let key = path.first else {
        for (field, value) in fields {
            object[field] = value
        }
        return
    }
    guard var nestedObject = object[key] as? [String: Any] else {
        throw SchemaError.invalidPackage("Expected nested JSON object fixture.")
    }
    try addJSONFields(fields, at: path.dropFirst(), in: &nestedObject)
    object[key] = nestedObject
}

private func addJSONFieldsToFirstDynamicDictionaryValue(
    _ fields: [String: Any],
    at path: ArraySlice<String>,
    in object: inout [String: Any]
) throws {
    guard let key = path.first else {
        throw SchemaError.invalidPackage("Expected dynamic dictionary path.")
    }
    if path.count == 1 {
        if var nestedObject = object[key] as? [String: Any],
           let nestedKey = nestedObject.keys.sorted().first,
           var valueObject = nestedObject[nestedKey] as? [String: Any] {
            for (field, value) in fields {
                valueObject[field] = value
            }
            nestedObject[nestedKey] = valueObject
            object[key] = nestedObject
            return
        }
        if var nestedArray = object[key] as? [Any],
           let valueIndex = nestedArray.indices.first(where: { nestedArray[$0] is [String: Any] }),
           var valueObject = nestedArray[valueIndex] as? [String: Any] {
            for (field, value) in fields {
                valueObject[field] = value
            }
            nestedArray[valueIndex] = valueObject
            object[key] = nestedArray
            return
        }
        throw SchemaError.invalidPackage("Expected dynamic dictionary fixture.")
    }
    guard var nestedObject = object[key] as? [String: Any] else {
        throw SchemaError.invalidPackage("Expected nested JSON object fixture.")
    }
    try addJSONFieldsToFirstDynamicDictionaryValue(fields, at: path.dropFirst(), in: &nestedObject)
    object[key] = nestedObject
}

private func duplicateFirstDynamicDictionaryEntry(
    at path: ArraySlice<String>,
    in object: inout [String: Any]
) throws {
    guard let key = path.first else {
        throw SchemaError.invalidPackage("Expected dynamic dictionary path.")
    }
    if path.count == 1 {
        guard var nestedArray = object[key] as? [Any],
              nestedArray.count >= 2 else {
            throw SchemaError.invalidPackage("Expected array-encoded dynamic dictionary fixture.")
        }
        nestedArray.append(nestedArray[0])
        nestedArray.append(nestedArray[1])
        object[key] = nestedArray
        return
    }
    guard var nestedObject = object[key] as? [String: Any] else {
        throw SchemaError.invalidPackage("Expected nested JSON object fixture.")
    }
    try duplicateFirstDynamicDictionaryEntry(at: path.dropFirst(), in: &nestedObject)
    object[key] = nestedObject
}

private func duplicateFirstDynamicDictionaryEntryWithLowercaseKey(
    at path: ArraySlice<String>,
    in object: inout [String: Any]
) throws {
    guard let key = path.first else {
        throw SchemaError.invalidPackage("Expected dynamic dictionary path.")
    }
    if path.count == 1 {
        guard var nestedArray = object[key] as? [Any],
              nestedArray.count >= 2,
              let firstKey = nestedArray[0] as? String else {
            throw SchemaError.invalidPackage("Expected array-encoded dynamic dictionary fixture.")
        }
        nestedArray.append(firstKey.lowercased())
        nestedArray.append(nestedArray[1])
        object[key] = nestedArray
        return
    }
    guard var nestedObject = object[key] as? [String: Any] else {
        throw SchemaError.invalidPackage("Expected nested JSON object fixture.")
    }
    try duplicateFirstDynamicDictionaryEntryWithLowercaseKey(at: path.dropFirst(), in: &nestedObject)
    object[key] = nestedObject
}

private func jsonObject(from data: Data) throws -> [String: Any] {
    guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
        throw SchemaError.invalidPackage("Expected JSON object fixture.")
    }
    return object
}

private func unitTriangleMesh(unit: LengthUnit) -> Mesh {
    let dimensions = unitTriangleDimensions(unit: unit)
    return Mesh(
        positions: [
            Point3D(x: 0.0, y: 0.0, z: 0.0),
            Point3D(x: unit.toInternal(dimensions.width), y: 0.0, z: 0.0),
            Point3D(x: 0.0, y: unit.toInternal(dimensions.height), z: unit.toInternal(dimensions.depth))
        ],
        normals: [],
        indices: [0, 1, 2]
    )
}

private func triangleMeshArea(_ mesh: Mesh) -> Double {
    stride(from: 0, to: mesh.indices.count, by: 3).reduce(0.0) { area, offset in
        let first = mesh.positions[Int(mesh.indices[offset])]
        let second = mesh.positions[Int(mesh.indices[offset + 1])]
        let third = mesh.positions[Int(mesh.indices[offset + 2])]
        return area + 0.5 * (second - first).cross(third - first).length
    }
}

private func data(hexEncoded text: String) throws -> Data {
    guard text.count.isMultiple(of: 2) else {
        throw ImportError.invalidData("Hex fixture must contain complete bytes.")
    }
    var bytes: [UInt8] = []
    bytes.reserveCapacity(text.count / 2)
    var index = text.startIndex
    while index < text.endIndex {
        let next = text.index(index, offsetBy: 2)
        guard let byte = UInt8(text[index..<next], radix: 16) else {
            throw ImportError.invalidData("Hex fixture contains an invalid byte.")
        }
        bytes.append(byte)
        index = next
    }
    return Data(bytes)
}

private func validatePDFCrossReference(_ data: Data) throws {
    let bytes = [UInt8](data)
    let marker = Array("startxref\n".utf8)
    guard let markerStart = bytes.indices.reversed().first(where: { index in
        index + marker.count <= bytes.count
            && Array(bytes[index..<(index + marker.count)]) == marker
    }) else {
        throw ExportError.invalidMesh("PDF startxref marker is missing.")
    }
    let offsetStart = markerStart + marker.count
    guard let offsetEnd = bytes[offsetStart...].firstIndex(of: 0x0a),
          let offset = Int(String(decoding: bytes[offsetStart..<offsetEnd], as: UTF8.self)),
          offset >= 0,
          offset < bytes.count else {
        throw ExportError.invalidMesh("PDF startxref offset is invalid.")
    }
    #expect(bytes[offset...].starts(with: Array("xref\n0 6\n".utf8)))

    let xrefText = String(decoding: bytes[offset..<markerStart], as: UTF8.self)
    let lines = xrefText.split(separator: "\n", omittingEmptySubsequences: false)
    guard lines.count >= 8 else {
        throw ExportError.invalidMesh("PDF cross-reference table is incomplete.")
    }
    for objectNumber in 1...5 {
        let entry = lines[2 + objectNumber].split(separator: " ", omittingEmptySubsequences: true)
        guard let encodedOffset = entry.first,
              let objectOffset = Int(encodedOffset),
              objectOffset >= 0,
              objectOffset < bytes.count else {
            throw ExportError.invalidMesh("PDF object offset is invalid.")
        }
        let expected = Array("\(objectNumber) 0 obj".utf8)
        #expect(bytes[objectOffset...].starts(with: expected))
    }
}

private func unitTriangleDimensions(unit: LengthUnit) -> (width: Double, height: Double, depth: Double) {
    let scale = max(1.0, 0.01 / unit.metersPerUnit)
    return (
        width: 2.0 * scale,
        height: 3.0 * scale,
        depth: 4.0 * scale
    )
}

private func largeFiniteTriangleMeshThatOverflowsMillimeters() -> Mesh {
    Mesh(
        positions: [
            Point3D(x: 0.0, y: 0.0, z: 0.0),
            Point3D(x: 1.0e306, y: 0.0, z: 0.0),
            Point3D(x: 1.0e306, y: 1.0e-306, z: 0.0)
        ],
        normals: [],
        indices: [0, 1, 2]
    )
}

private func nativePackageStabilityDocument(reversedDictionaries: Bool) throws -> CADDocument {
    let documentID = DocumentID(try fixedUUID("00000000-0000-0000-0000-000000000001"))
    let widthID = ParameterID(try fixedUUID("00000000-0000-0000-0000-000000000011"))
    let heightID = ParameterID(try fixedUUID("00000000-0000-0000-0000-000000000012"))
    let sketchID = FeatureID(try fixedUUID("00000000-0000-0000-0000-000000000021"))
    let extrudeID = FeatureID(try fixedUUID("00000000-0000-0000-0000-000000000022"))
    let firstLineID = SketchEntityID(try fixedUUID("00000000-0000-0000-0000-000000000031"))
    let secondLineID = SketchEntityID(try fixedUUID("00000000-0000-0000-0000-000000000032"))
    let createdAt = Date(timeIntervalSinceReferenceDate: 1_000.25)
    let updatedAt = Date(timeIntervalSinceReferenceDate: 1_000.5)

    let width = Parameter(
        id: widthID,
        name: "width",
        expression: .constant(.length(40.0, unit: .millimeter)),
        kind: .length
    )
    let height = Parameter(
        id: heightID,
        name: "height",
        expression: .constant(.length(20.0, unit: .millimeter)),
        kind: .length
    )
    let parameters: [(ParameterID, Parameter)] = reversedDictionaries
        ? [(heightID, height), (widthID, width)]
        : [(widthID, width), (heightID, height)]

    let firstLine = SketchEntity.line(SketchLine(
        start: SketchPoint(x: .constant(.length(0.0, unit: .millimeter)), y: .constant(.length(0.0, unit: .millimeter))),
        end: SketchPoint(x: .reference(widthID), y: .constant(.length(0.0, unit: .millimeter)))
    ))
    let secondLine = SketchEntity.line(SketchLine(
        start: SketchPoint(x: .reference(widthID), y: .constant(.length(0.0, unit: .millimeter))),
        end: SketchPoint(x: .reference(widthID), y: .reference(heightID))
    ))
    let entities: [(SketchEntityID, SketchEntity)] = reversedDictionaries
        ? [(secondLineID, secondLine), (firstLineID, firstLine)]
        : [(firstLineID, firstLine), (secondLineID, secondLine)]

    let sketch = Sketch(
        id: SketchID(try fixedUUID("00000000-0000-0000-0000-000000000041")),
        plane: .xy,
        entities: Dictionary(uniqueKeysWithValues: entities)
    )
    let sketchNode = FeatureNode(
        id: sketchID,
        operation: .sketch(sketch),
        outputs: [FeatureOutput(role: .profile)]
    )
    let extrudeNode = FeatureNode(
        id: extrudeID,
        operation: .extrude(ExtrudeFeature(
            profile: ProfileReference(featureID: sketchID),
            distance: .constant(.length(10.0, unit: .millimeter))
        )),
        inputs: [FeatureInput(featureID: sketchID, role: .profile)],
        outputs: [FeatureOutput(role: .body)]
    )
    let nodes: [(FeatureID, FeatureNode)] = reversedDictionaries
        ? [(extrudeID, extrudeNode), (sketchID, sketchNode)]
        : [(sketchID, sketchNode), (extrudeID, extrudeNode)]

    return CADDocument(
        id: documentID,
        units: .millimeters,
        parameters: ParameterTable(parameters: Dictionary(uniqueKeysWithValues: parameters)),
        designGraph: DesignGraph(
            nodes: Dictionary(uniqueKeysWithValues: nodes),
            order: [sketchID, extrudeID],
            dependencies: [DependencyEdge(source: sketchID, target: extrudeID)]
        ),
        metadata: DocumentMetadata(name: "Native Stability", createdAt: createdAt, updatedAt: updatedAt)
    )
}

private func fixedUUID(_ string: String) throws -> UUID {
    guard let uuid = UUID(uuidString: string) else {
        throw SchemaError.invalidPackage("Invalid fixed UUID fixture.")
    }
    return uuid
}

private func expectedExtents(unit: LengthUnit) -> (width: Double, height: Double, depth: Double) {
    let dimensions = unitTriangleDimensions(unit: unit)
    return (
        width: unit.toInternal(dimensions.width),
        height: unit.toInternal(dimensions.height),
        depth: unit.toInternal(dimensions.depth)
    )
}

private let threeMFContentTypesXML = """
<?xml version="1.0" encoding="UTF-8"?>
<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">
  <Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>
  <Default Extension="model" ContentType="application/vnd.ms-package.3dmanufacturing-3dmodel+xml"/>
</Types>
"""

private let threeMFRelationshipsXML = """
<?xml version="1.0" encoding="UTF-8"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
  <Relationship Target="/3D/3dmodel.model" Id="rel0" Type="http://schemas.microsoft.com/3dmanufacturing/2013/01/3dmodel"/>
</Relationships>
"""

private func threeMFPackage(
    modelXML: String,
    additionalEntries: [StoredZipArchive.Entry] = []
) throws -> Data {
    try threeMFPackage(modelData: Data(modelXML.utf8), additionalEntries: additionalEntries)
}

private func threeMFPackage(
    modelData: Data,
    additionalEntries: [StoredZipArchive.Entry] = []
) throws -> Data {
    var entries = [
        StoredZipArchive.Entry(path: "[Content_Types].xml", data: Data(threeMFContentTypesXML.utf8)),
        StoredZipArchive.Entry(path: "_rels/.rels", data: Data(threeMFRelationshipsXML.utf8)),
        StoredZipArchive.Entry(path: "3D/3dmodel.model", data: modelData)
    ]
    entries.append(contentsOf: additionalEntries)
    return try StoredZipArchive.make(entries: entries)
}

private func threeMFPackage(
    contentTypesXML: String,
    relationshipsXML: String,
    modelXML: String
) throws -> Data {
    try StoredZipArchive.make(entries: [
        StoredZipArchive.Entry(path: "[Content_Types].xml", data: Data(contentTypesXML.utf8)),
        StoredZipArchive.Entry(path: "_rels/.rels", data: Data(relationshipsXML.utf8)),
        StoredZipArchive.Entry(path: "3D/3dmodel.model", data: Data(modelXML.utf8))
    ])
}

private func validThreeMFModelXML() -> String {
    """
    <?xml version='1.0' encoding='UTF-8'?>
    <model unit='meter' xml:lang='en-US' xmlns='http://schemas.microsoft.com/3dmanufacturing/core/2015/02'>
      <resources>
        <object id='1' type='model'>
          <mesh>
            <vertices>
              <vertex x='0' y='0' z='0'/>
              <vertex x='1' y='0' z='0'/>
              <vertex x='0' y='1' z='0'/>
            </vertices>
            <triangles>
              <triangle v1='0' v2='1' v3='2'/>
            </triangles>
          </mesh>
        </object>
      </resources>
      <build>
        <item objectid='1'/>
      </build>
    </model>
    """
}

private func storedZipArchiveWithUnsafePath() -> Data {
    storedZipArchive(path: "../document.json", data: Data("content".utf8))
}

private func storedZipArchiveWithDuplicateCentralEntries() -> Data {
    storedZipArchive(path: "document.json", data: Data("content".utf8), duplicateCentralEntry: true)
}

private func storedZipArchiveWithUnreferencedLocalEntry() -> Data {
    storedZipArchiveWithUnreferencedLocalEntry(visibleEntries: [
        (path: "document.json", data: Data("content".utf8))
    ])
}

private func storedZipArchiveWithUnreferencedLocalEntry(
    visibleEntries: [(path: String, data: Data)]
) -> Data {
    let hiddenLocalEntry = storedZipLocalEntry(path: "caches/hidden.bin", data: Data("hidden".utf8))
    var archive = hiddenLocalEntry
    var centralDirectory = Data()
    for entry in visibleEntries {
        let pathData = Data(entry.path.utf8)
        let crc = CRC32.checksum(entry.data)
        let size = UInt32(entry.data.count)
        let localOffset = UInt32(archive.count)
        archive.append(storedZipLocalEntry(path: entry.path, data: entry.data))
        centralDirectory.append(storedZipCentralDirectoryRecord(
            pathData: pathData,
            crc: crc,
            size: size,
            localOffset: localOffset
        ))
    }

    let centralOffset = UInt32(archive.count)
    archive.append(centralDirectory)
    archive.appendLittleEndian(UInt32(0x06054b50))
    archive.appendLittleEndian(UInt16(0))
    archive.appendLittleEndian(UInt16(0))
    archive.appendLittleEndian(UInt16(visibleEntries.count))
    archive.appendLittleEndian(UInt16(visibleEntries.count))
    archive.appendLittleEndian(UInt32(centralDirectory.count))
    archive.appendLittleEndian(centralOffset)
    archive.appendLittleEndian(UInt16(0))
    return archive
}

private func storedZipLocalEntry(path: String, data entryData: Data) -> Data {
    let nameData = Data(path.utf8)
    let crc = CRC32.checksum(entryData)
    let size = UInt32(entryData.count)
    var entry = Data()
    entry.appendLittleEndian(UInt32(0x04034b50))
    entry.appendLittleEndian(UInt16(20))
    entry.appendLittleEndian(UInt16(0))
    entry.appendLittleEndian(UInt16(0))
    entry.appendLittleEndian(UInt16(0))
    entry.appendLittleEndian(UInt16(0))
    entry.appendLittleEndian(crc)
    entry.appendLittleEndian(size)
    entry.appendLittleEndian(size)
    entry.appendLittleEndian(UInt16(nameData.count))
    entry.appendLittleEndian(UInt16(0))
    entry.append(nameData)
    entry.append(entryData)
    return entry
}

private func deflatedZipArchive(
    entries: [StoredZipArchive.Entry],
    usesDataDescriptors: Bool,
    compression: (Data) -> Data = rawStoredDeflate
) throws -> Data {
    guard entries.count <= Int(UInt16.max) else {
        throw ZipArchiveError.tooManyEntries
    }
    let flags: UInt16 = 0x0800 | (usesDataDescriptors ? 0x0008 : 0)
    var archive = Data()
    var centralDirectory = Data()
    for entry in entries {
        let pathData = Data(entry.path.utf8)
        let compressed = compression(entry.data)
        let crc = CRC32.checksum(entry.data)
        guard archive.count <= Int(UInt32.max),
              compressed.count <= Int(UInt32.max),
              entry.data.count <= Int(UInt32.max) else {
            throw ZipArchiveError.entryTooLarge(entry.path)
        }
        let localOffset = UInt32(archive.count)
        let compressedSize = UInt32(compressed.count)
        let uncompressedSize = UInt32(entry.data.count)
        let extra = zipTimestampExtraField()

        archive.appendLittleEndian(UInt32(0x04034b50))
        archive.appendLittleEndian(UInt16(20))
        archive.appendLittleEndian(flags)
        archive.appendLittleEndian(UInt16(8))
        archive.appendLittleEndian(UInt16(0))
        archive.appendLittleEndian(UInt16(0))
        archive.appendLittleEndian(usesDataDescriptors ? UInt32(0) : crc)
        archive.appendLittleEndian(usesDataDescriptors ? UInt32(0) : compressedSize)
        archive.appendLittleEndian(usesDataDescriptors ? UInt32(0) : uncompressedSize)
        archive.appendLittleEndian(UInt16(pathData.count))
        archive.appendLittleEndian(UInt16(extra.count))
        archive.append(pathData)
        archive.append(extra)
        archive.append(compressed)
        if usesDataDescriptors {
            archive.appendLittleEndian(UInt32(0x08074b50))
            archive.appendLittleEndian(crc)
            archive.appendLittleEndian(compressedSize)
            archive.appendLittleEndian(uncompressedSize)
        }

        centralDirectory.append(storedZipCentralDirectoryRecord(
            pathData: pathData,
            crc: crc,
            size: compressedSize,
            uncompressedSize: uncompressedSize,
            extra: extra,
            localOffset: localOffset,
            flags: flags,
            method: 8
        ))
    }
    guard archive.count <= Int(UInt32.max), centralDirectory.count <= Int(UInt32.max) else {
        throw ZipArchiveError.entryTooLarge("archive")
    }
    let centralOffset = UInt32(archive.count)
    archive.append(centralDirectory)
    archive.appendLittleEndian(UInt32(0x06054b50))
    archive.appendLittleEndian(UInt16(0))
    archive.appendLittleEndian(UInt16(0))
    archive.appendLittleEndian(UInt16(entries.count))
    archive.appendLittleEndian(UInt16(entries.count))
    archive.appendLittleEndian(UInt32(centralDirectory.count))
    archive.appendLittleEndian(centralOffset)
    archive.appendLittleEndian(UInt16(0))
    return archive
}

private func rawStoredDeflate(_ data: Data) -> Data {
    var result = Data()
    if data.isEmpty {
        result.append(0x01)
        result.appendLittleEndian(UInt16(0))
        result.appendLittleEndian(UInt16.max)
        return result
    }
    var offset = 0
    while offset < data.count {
        let count = min(Int(UInt16.max), data.count - offset)
        let isFinal = offset + count == data.count
        result.append(isFinal ? 0x01 : 0x00)
        let length = UInt16(count)
        result.appendLittleEndian(length)
        result.appendLittleEndian(~length)
        result.append(data[offset..<(offset + count)])
        offset += count
    }
    return result
}

private func zipTimestampExtraField() -> Data {
    var extra = Data()
    extra.appendLittleEndian(UInt16(0x5455))
    extra.appendLittleEndian(UInt16(1))
    extra.append(0)
    return extra
}

private func storedZipArchive(
    path: String,
    data entryData: Data,
    duplicateCentralEntry: Bool = false,
    centralUncompressedSize: UInt32? = nil,
    centralExtra: Data = Data(),
    centralComment: Data = Data(),
    centralFlags: UInt16 = 0,
    localExtra: Data = Data(),
    localFlags: UInt16 = 0
) -> Data {
    let nameData = Data(path.utf8)
    let crc = CRC32.checksum(entryData)
    let size = UInt32(entryData.count)
    let localOffset = UInt32(0)
    var archive = Data()

    archive.appendLittleEndian(UInt32(0x04034b50))
    archive.appendLittleEndian(UInt16(20))
    archive.appendLittleEndian(localFlags)
    archive.appendLittleEndian(UInt16(0))
    archive.appendLittleEndian(UInt16(0))
    archive.appendLittleEndian(UInt16(0))
    archive.appendLittleEndian(crc)
    archive.appendLittleEndian(size)
    archive.appendLittleEndian(size)
    archive.appendLittleEndian(UInt16(nameData.count))
    archive.appendLittleEndian(UInt16(localExtra.count))
    archive.append(nameData)
    archive.append(localExtra)
    archive.append(entryData)

    let centralOffset = UInt32(archive.count)
    var centralDirectory = storedZipCentralDirectoryRecord(
        pathData: nameData,
        crc: crc,
        size: size,
        uncompressedSize: centralUncompressedSize,
        extra: centralExtra,
        comment: centralComment,
        localOffset: localOffset,
        flags: centralFlags
    )
    if duplicateCentralEntry {
        centralDirectory.append(storedZipCentralDirectoryRecord(
            pathData: nameData,
            crc: crc,
            size: size,
            uncompressedSize: centralUncompressedSize,
            extra: centralExtra,
            comment: centralComment,
            localOffset: localOffset,
            flags: centralFlags
        ))
    }
    let entryCount: UInt16 = duplicateCentralEntry ? 2 : 1
    archive.append(centralDirectory)
    archive.appendLittleEndian(UInt32(0x06054b50))
    archive.appendLittleEndian(UInt16(0))
    archive.appendLittleEndian(UInt16(0))
    archive.appendLittleEndian(entryCount)
    archive.appendLittleEndian(entryCount)
    archive.appendLittleEndian(UInt32(centralDirectory.count))
    archive.appendLittleEndian(centralOffset)
    archive.appendLittleEndian(UInt16(0))
    return archive
}

private func storedZipCentralDirectoryRecord(
    pathData: Data,
    crc: UInt32,
    size: UInt32,
    uncompressedSize: UInt32? = nil,
    extra: Data = Data(),
    comment: Data = Data(),
    localOffset: UInt32,
    flags: UInt16 = 0,
    method: UInt16 = 0
) -> Data {
    var record = Data()
    record.appendLittleEndian(UInt32(0x02014b50))
    record.appendLittleEndian(UInt16(20))
    record.appendLittleEndian(UInt16(20))
    record.appendLittleEndian(flags)
    record.appendLittleEndian(method)
    record.appendLittleEndian(UInt16(0))
    record.appendLittleEndian(UInt16(0))
    record.appendLittleEndian(crc)
    record.appendLittleEndian(size)
    record.appendLittleEndian(uncompressedSize ?? size)
    record.appendLittleEndian(UInt16(pathData.count))
    record.appendLittleEndian(UInt16(extra.count))
    record.appendLittleEndian(UInt16(comment.count))
    record.appendLittleEndian(UInt16(0))
    record.appendLittleEndian(UInt16(0))
    record.appendLittleEndian(UInt32(0))
    record.appendLittleEndian(localOffset)
    record.append(pathData)
    record.append(extra)
    record.append(comment)
    return record
}

private func glbJSONText(from data: Data) throws -> String {
    guard data.count >= 20,
          try data.littleEndianUInt32(at: 0) == 0x46546c67,
          try data.littleEndianUInt32(at: 16) == 0x4e4f534a else {
        throw ImportError.invalidData("Invalid GLB header.")
    }
    let jsonLength = Int(try data.littleEndianUInt32(at: 12))
    let jsonStart = 20
    let jsonEnd = jsonStart + jsonLength
    guard jsonEnd <= data.count,
          let text = String(data: data[jsonStart..<jsonEnd], encoding: .utf8) else {
        throw ImportError.invalidData("Invalid GLB JSON chunk.")
    }
    return text.trimmingCharacters(in: .whitespacesAndNewlines)
}

private func emptyThreeMFPackageData() throws -> Data {
    let model = """
    <?xml version="1.0" encoding="UTF-8"?>
    <model unit="millimeter" xml:lang="en-US" xmlns="http://schemas.microsoft.com/3dmanufacturing/core/2015/02">
      <resources>
        <object id="1" type="model">
          <mesh>
            <vertices/>
            <triangles/>
          </mesh>
        </object>
      </resources>
      <build>
        <item objectid="1"/>
      </build>
    </model>
    """
    return try threeMFPackage(modelXML: model)
}

private func threeMFPackageWithCommentsAndSingleQuotes() throws -> Data {
    let model = """
    <?xml version='1.0' encoding='UTF-8'?>
    <model unit='inch' xml:lang='en-US' xmlns='http://schemas.microsoft.com/3dmanufacturing/core/2015/02'>
      <resources>
        <object id='1' type='model'>
          <mesh>
            <vertices>
              <!-- <vertex x='999' y='999' z='999'/> -->
              <vertex z='0' y='0' x='0'/>
              <vertex y='0' x='2' z='0'/>
              <vertex x='0' z='4' y='3'/>
            </vertices>
            <triangles>
              <!-- <triangle v1='0' v2='0' v3='0'/> -->
              <triangle v3='2' v1='0' v2='1'/>
            </triangles>
          </mesh>
        </object>
      </resources>
      <build>
        <item objectid='1'/>
      </build>
    </model>
    """
    return try threeMFPackage(modelXML: model)
}

private func threeMFPackageWithWrongRootElement() throws -> Data {
    let model = """
    <?xml version='1.0' encoding='UTF-8'?>
    <package unit='meter' xmlns='http://schemas.microsoft.com/3dmanufacturing/core/2015/02'>
      <resources>
        <object id='1' type='model'>
          <mesh>
            <vertices>
              <vertex x='0' y='0' z='0'/>
              <vertex x='2' y='0' z='0'/>
              <vertex x='0' y='3' z='0'/>
            </vertices>
            <triangles>
              <triangle v1='0' v2='1' v3='2'/>
            </triangles>
          </mesh>
        </object>
      </resources>
      <build>
        <item objectid='1'/>
      </build>
    </package>
    """
    return try threeMFPackage(modelXML: model)
}

private func threeMFPackageWithWrongModelNamespace() throws -> Data {
    let model = """
    <?xml version='1.0' encoding='UTF-8'?>
    <model unit='meter' xmlns='urn:wrong'>
      <resources>
        <object id='1' type='model'>
          <mesh>
            <vertices>
              <vertex x='0' y='0' z='0'/>
              <vertex x='2' y='0' z='0'/>
              <vertex x='0' y='3' z='0'/>
            </vertices>
            <triangles>
              <triangle v1='0' v2='1' v3='2'/>
            </triangles>
          </mesh>
        </object>
      </resources>
      <build>
        <item objectid='1'/>
      </build>
    </model>
    """
    return try threeMFPackage(modelXML: model)
}

private func threeMFPackageWithNestedExtensionUnitTrap() throws -> Data {
    let model = """
    <?xml version='1.0' encoding='UTF-8'?>
    <model unit='meter' xmlns='http://schemas.microsoft.com/3dmanufacturing/core/2015/02'>
      <metadata name='trap'>
        <ext:unit xmlns:ext='urn:swift-cad-test' value='millimeter'/>
      </metadata>
      <resources>
        <object id='1' type='model'>
          <mesh>
            <vertices>
              <vertex x='0' y='0' z='0'/>
              <vertex x='2' y='0' z='0'/>
              <vertex x='0' y='3' z='0'/>
            </vertices>
            <triangles>
              <triangle v1='0' v2='1' v3='2'/>
            </triangles>
          </mesh>
        </object>
      </resources>
      <build>
        <item objectid='1'/>
      </build>
    </model>
    """
    return try threeMFPackage(modelXML: model)
}

private func threeMFPackageWithOmittedModelUnit() throws -> Data {
    try threeMFPackage(modelXML: validThreeMFModelXML().replacingOccurrences(of: " unit='meter'", with: ""))
}

private func threeMFPackageWithCoreModelInsideMetadata() throws -> Data {
    let model = """
    <?xml version='1.0' encoding='UTF-8'?>
    <model unit='meter' xmlns='http://schemas.microsoft.com/3dmanufacturing/core/2015/02'>
      <metadata name='trap'>
        <model unit='millimeter'/>
      </metadata>
      <resources>
        <object id='1' type='model'>
          <mesh>
            <vertices>
              <vertex x='0' y='0' z='0'/>
              <vertex x='2' y='0' z='0'/>
              <vertex x='0' y='3' z='0'/>
            </vertices>
            <triangles>
              <triangle v1='0' v2='1' v3='2'/>
            </triangles>
          </mesh>
        </object>
      </resources>
      <build>
        <item objectid='1'/>
      </build>
    </model>
    """
    return try threeMFPackage(modelXML: model)
}

private func threeMFPackageWithUnreferencedNonFiniteVertex() throws -> Data {
    let model = """
    <?xml version='1.0' encoding='UTF-8'?>
    <model unit='millimeter' xmlns='http://schemas.microsoft.com/3dmanufacturing/core/2015/02'>
      <resources>
        <object id='1' type='model'>
          <mesh>
            <vertices>
              <vertex x='nan' y='0' z='0'/>
              <vertex x='0' y='0' z='0'/>
              <vertex x='1' y='0' z='0'/>
              <vertex x='0' y='1' z='0'/>
            </vertices>
            <triangles>
              <triangle v1='1' v2='2' v3='3'/>
            </triangles>
          </mesh>
        </object>
      </resources>
      <build>
        <item objectid='1'/>
      </build>
    </model>
    """
    return try threeMFPackage(modelXML: model)
}

private func threeMFPackageWithVertexOutsideVertices() throws -> Data {
    let model = """
    <?xml version='1.0' encoding='UTF-8'?>
    <model unit='millimeter' xmlns='http://schemas.microsoft.com/3dmanufacturing/core/2015/02'>
      <resources>
        <object id='1' type='model'>
          <mesh>
            <vertex x='99' y='99' z='99'/>
            <vertices>
              <vertex x='0' y='0' z='0'/>
              <vertex x='1' y='0' z='0'/>
              <vertex x='0' y='1' z='0'/>
            </vertices>
            <triangles>
              <triangle v1='0' v2='1' v3='2'/>
            </triangles>
          </mesh>
        </object>
      </resources>
    </model>
    """
    return try threeMFPackage(modelXML: model)
}

private func threeMFPackageWithTriangleOutsideTriangles() throws -> Data {
    let model = """
    <?xml version='1.0' encoding='UTF-8'?>
    <model unit='millimeter' xmlns='http://schemas.microsoft.com/3dmanufacturing/core/2015/02'>
      <resources>
        <object id='1' type='model'>
          <mesh>
            <vertices>
              <vertex x='0' y='0' z='0'/>
              <vertex x='1' y='0' z='0'/>
              <vertex x='0' y='1' z='0'/>
            </vertices>
            <triangle v1='0' v2='1' v3='2'/>
            <triangles>
              <triangle v1='0' v2='1' v3='2'/>
            </triangles>
          </mesh>
        </object>
      </resources>
    </model>
    """
    return try threeMFPackage(modelXML: model)
}

private func threeMFPackageWithVertexInsideNestedLookalikeContainer() throws -> Data {
    let model = """
    <?xml version='1.0' encoding='UTF-8'?>
    <model unit='millimeter' xmlns='http://schemas.microsoft.com/3dmanufacturing/core/2015/02'>
      <resources>
        <object id='1' type='model'>
          <mesh>
            <metadata name='trap'>
              <vertices>
                <vertex x='99' y='99' z='99'/>
              </vertices>
            </metadata>
            <vertices>
              <vertex x='0' y='0' z='0'/>
              <vertex x='1' y='0' z='0'/>
              <vertex x='0' y='1' z='0'/>
            </vertices>
            <triangles>
              <triangle v1='0' v2='1' v3='2'/>
            </triangles>
          </mesh>
        </object>
      </resources>
      <build>
        <item objectid='1'/>
      </build>
    </model>
    """
    return try threeMFPackage(modelXML: model)
}

private func threeMFPackageWithTriangleInsideNestedLookalikeContainer() throws -> Data {
    let model = """
    <?xml version='1.0' encoding='UTF-8'?>
    <model unit='millimeter' xmlns='http://schemas.microsoft.com/3dmanufacturing/core/2015/02'>
      <resources>
        <object id='1' type='model'>
          <mesh>
            <vertices>
              <vertex x='0' y='0' z='0'/>
              <vertex x='1' y='0' z='0'/>
              <vertex x='0' y='1' z='0'/>
            </vertices>
            <metadata name='trap'>
              <triangles>
                <triangle v1='0' v2='1' v3='2'/>
              </triangles>
            </metadata>
            <triangles>
              <triangle v1='0' v2='1' v3='2'/>
            </triangles>
          </mesh>
        </object>
      </resources>
      <build>
        <item objectid='1'/>
      </build>
    </model>
    """
    return try threeMFPackage(modelXML: model)
}

private func threeMFPackageWithUnsupportedMeshElement() throws -> Data {
    let model = """
    <?xml version='1.0' encoding='UTF-8'?>
    <model unit='meter' xmlns='http://schemas.microsoft.com/3dmanufacturing/core/2015/02'>
      <resources>
        <object id='1' type='model'>
          <mesh>
            <beamlattice>
              <beam v1='0' v2='1'/>
            </beamlattice>
            <vertices>
              <vertex x='0' y='0' z='0'/>
              <vertex x='1' y='0' z='0'/>
              <vertex x='0' y='1' z='0'/>
            </vertices>
            <triangles>
              <triangle v1='0' v2='1' v3='2'/>
            </triangles>
          </mesh>
        </object>
      </resources>
      <build>
        <item objectid='1'/>
      </build>
    </model>
    """
    return try threeMFPackage(modelXML: model)
}

private func threeMFPackageWithMeshContainerInsideBuild() throws -> Data {
    let model = """
    <?xml version='1.0' encoding='UTF-8'?>
    <model unit='meter' xmlns='http://schemas.microsoft.com/3dmanufacturing/core/2015/02'>
      <resources>
        <object id='1' type='model'>
          <mesh>
            <vertices>
              <vertex x='0' y='0' z='0'/>
              <vertex x='1' y='0' z='0'/>
              <vertex x='0' y='1' z='0'/>
            </vertices>
            <triangles>
              <triangle v1='0' v2='1' v3='2'/>
            </triangles>
          </mesh>
        </object>
      </resources>
      <build>
        <mesh/>
        <item objectid='1'/>
      </build>
    </model>
    """
    return try threeMFPackage(modelXML: model)
}

private func threeMFPackageWithUnsupportedPackageEntry() throws -> Data {
    let model = """
    <?xml version='1.0' encoding='UTF-8'?>
    <model unit='meter' xmlns='http://schemas.microsoft.com/3dmanufacturing/core/2015/02'>
      <resources>
        <object id='1' type='model'>
          <mesh>
            <vertices>
              <vertex x='0' y='0' z='0'/>
              <vertex x='1' y='0' z='0'/>
              <vertex x='0' y='1' z='0'/>
            </vertices>
            <triangles>
              <triangle v1='0' v2='1' v3='2'/>
            </triangles>
          </mesh>
        </object>
      </resources>
      <build>
        <item objectid='1'/>
      </build>
    </model>
    """
    return try threeMFPackage(
        modelXML: model,
        additionalEntries: [
            StoredZipArchive.Entry(path: "Metadata/hidden.xml", data: Data("<hidden/>".utf8))
        ]
    )
}

private func threeMFPackageWithUnbuiltResourceObject() throws -> Data {
    let model = """
    <?xml version='1.0' encoding='UTF-8'?>
    <model unit='meter' xmlns='http://schemas.microsoft.com/3dmanufacturing/core/2015/02'>
      <resources>
        <object id='1' type='model'>
          <mesh>
            <vertices>
              <vertex x='0' y='0' z='0'/>
              <vertex x='1' y='0' z='0'/>
              <vertex x='0' y='1' z='0'/>
            </vertices>
            <triangles>
              <triangle v1='0' v2='1' v3='2'/>
            </triangles>
          </mesh>
        </object>
        <object id='2' type='model'>
          <mesh>
            <vertices>
              <vertex x='10' y='0' z='0'/>
              <vertex x='11' y='0' z='0'/>
              <vertex x='10' y='1' z='0'/>
            </vertices>
            <triangles>
              <triangle v1='0' v2='1' v3='2'/>
            </triangles>
          </mesh>
        </object>
      </resources>
      <build>
        <item objectid='1'/>
      </build>
    </model>
    """
    return try threeMFPackage(modelXML: model)
}

private func threeMFPackageWithMultipleBuiltObjects() throws -> Data {
    let model = """
    <?xml version='1.0' encoding='UTF-8'?>
    <model unit='meter' xmlns='http://schemas.microsoft.com/3dmanufacturing/core/2015/02'>
      <resources>
        <object id='1' type='model'>
          <mesh>
            <vertices>
              <vertex x='0' y='0' z='0'/>
              <vertex x='1' y='0' z='0'/>
              <vertex x='0' y='1' z='0'/>
            </vertices>
            <triangles>
              <triangle v1='0' v2='1' v3='2'/>
            </triangles>
          </mesh>
        </object>
        <object id='2' type='model'>
          <mesh>
            <vertices>
              <vertex x='10' y='0' z='0'/>
              <vertex x='12' y='0' z='0'/>
              <vertex x='10' y='2' z='0'/>
            </vertices>
            <triangles>
              <triangle v1='0' v2='1' v3='2'/>
            </triangles>
          </mesh>
        </object>
      </resources>
      <build>
        <item objectid='1'/>
        <item objectid='2'/>
      </build>
    </model>
    """
    return try threeMFPackage(modelXML: model)
}

private func threeMFPackageWithBuildItemTransform() throws -> Data {
    let model = """
    <?xml version='1.0' encoding='UTF-8'?>
    <model unit='meter' xmlns='http://schemas.microsoft.com/3dmanufacturing/core/2015/02'>
      <resources>
        <object id='1' type='model'>
          <mesh>
            <vertices>
              <vertex x='0' y='0' z='0'/>
              <vertex x='1' y='0' z='0'/>
              <vertex x='0' y='1' z='0'/>
            </vertices>
            <triangles>
              <triangle v1='0' v2='1' v3='2'/>
            </triangles>
          </mesh>
        </object>
      </resources>
      <build>
        <item objectid='1' transform='1 0 0 5 0 1 0 0 0 0 1 0'/>
      </build>
    </model>
    """
    return try threeMFPackage(modelXML: model)
}

private func threeMFPackageWithUnsupportedObjectComponent() throws -> Data {
    let model = """
    <?xml version='1.0' encoding='UTF-8'?>
    <model unit='meter' xmlns='http://schemas.microsoft.com/3dmanufacturing/core/2015/02'>
      <resources>
        <object id='1' type='model'>
          <mesh>
            <vertices>
              <vertex x='0' y='0' z='0'/>
              <vertex x='1' y='0' z='0'/>
              <vertex x='0' y='1' z='0'/>
            </vertices>
            <triangles>
              <triangle v1='0' v2='1' v3='2'/>
            </triangles>
          </mesh>
          <components>
            <component objectid='2'/>
          </components>
        </object>
      </resources>
      <build>
        <item objectid='1'/>
      </build>
    </model>
    """
    return try threeMFPackage(modelXML: model)
}

private func threeMFPackageWithTrianglePropertyReference() throws -> Data {
    let model = """
    <?xml version='1.0' encoding='UTF-8'?>
    <model unit='meter' xmlns='http://schemas.microsoft.com/3dmanufacturing/core/2015/02'>
      <resources>
        <object id='1' type='model'>
          <mesh>
            <vertices>
              <vertex x='0' y='0' z='0'/>
              <vertex x='1' y='0' z='0'/>
              <vertex x='0' y='1' z='0'/>
            </vertices>
            <triangles>
              <triangle v1='0' v2='1' v3='2' pid='7' p1='0' p2='0' p3='0'/>
            </triangles>
          </mesh>
        </object>
      </resources>
      <build>
        <item objectid='1'/>
      </build>
    </model>
    """
    return try threeMFPackage(modelXML: model)
}

private func threeMFPackageWithObjectPropertyReference() throws -> Data {
    let model = """
    <?xml version='1.0' encoding='UTF-8'?>
    <model unit='meter' xmlns='http://schemas.microsoft.com/3dmanufacturing/core/2015/02'>
      <resources>
        <object id='1' type='model' pid='7' pindex='0'>
          <mesh>
            <vertices>
              <vertex x='0' y='0' z='0'/>
              <vertex x='1' y='0' z='0'/>
              <vertex x='0' y='1' z='0'/>
            </vertices>
            <triangles>
              <triangle v1='0' v2='1' v3='2'/>
            </triangles>
          </mesh>
        </object>
      </resources>
      <build>
        <item objectid='1'/>
      </build>
    </model>
    """
    return try threeMFPackage(modelXML: model)
}

private func threeMFPackageWithUnsupportedPropertyResource() throws -> Data {
    let model = """
    <?xml version='1.0' encoding='UTF-8'?>
    <model unit='meter' xmlns='http://schemas.microsoft.com/3dmanufacturing/core/2015/02'>
      <resources>
        <basematerials id='7'>
          <base name='material' displaycolor='#ff0000ff'/>
        </basematerials>
        <object id='1' type='model'>
          <mesh>
            <vertices>
              <vertex x='0' y='0' z='0'/>
              <vertex x='1' y='0' z='0'/>
              <vertex x='0' y='1' z='0'/>
            </vertices>
            <triangles>
              <triangle v1='0' v2='1' v3='2'/>
            </triangles>
          </mesh>
        </object>
      </resources>
      <build>
        <item objectid='1'/>
      </build>
    </model>
    """
    return try threeMFPackage(modelXML: model)
}

private func threeMFPackageWithUnsupportedCoreAttribute(after elementOpening: String) throws -> Data {
    let model = """
    <?xml version='1.0' encoding='UTF-8'?>
    <model unit='meter' xmlns='http://schemas.microsoft.com/3dmanufacturing/core/2015/02'>
      <resources>
        <object id='1' type='model'>
          <mesh>
            <vertices>
              <vertex x='0' y='0' z='0'/>
              <vertex x='1' y='0' z='0'/>
              <vertex x='0' y='1' z='0'/>
            </vertices>
            <triangles>
              <triangle v1='0' v2='1' v3='2'/>
            </triangles>
          </mesh>
        </object>
      </resources>
      <build>
        <item objectid='1'/>
      </build>
    </model>
    """
    let mutated = model.replacingOccurrences(
        of: elementOpening,
        with: "\(elementOpening) data-hidden='payload'"
    )
    guard mutated != model else {
        throw ImportError.invalidData("Test fixture marker was not found.")
    }
    return try threeMFPackage(modelXML: mutated)
}

private func threeMFPackageWithMissingBuildObjectReference() throws -> Data {
    let model = """
    <?xml version='1.0' encoding='UTF-8'?>
    <model unit='meter' xmlns='http://schemas.microsoft.com/3dmanufacturing/core/2015/02'>
      <resources>
        <object id='1' type='model'>
          <mesh>
            <vertices>
              <vertex x='0' y='0' z='0'/>
              <vertex x='1' y='0' z='0'/>
              <vertex x='0' y='1' z='0'/>
            </vertices>
            <triangles>
              <triangle v1='0' v2='1' v3='2'/>
            </triangles>
          </mesh>
        </object>
      </resources>
      <build>
        <item objectid='2'/>
      </build>
    </model>
    """
    return try threeMFPackage(modelXML: model)
}

private func threeMFPackageWithNestedBuildItemLookalikeContainer() throws -> Data {
    let model = """
    <?xml version='1.0' encoding='UTF-8'?>
    <model unit='meter' xmlns='http://schemas.microsoft.com/3dmanufacturing/core/2015/02'>
      <resources>
        <object id='1' type='model'>
          <mesh>
            <vertices>
              <vertex x='0' y='0' z='0'/>
              <vertex x='1' y='0' z='0'/>
              <vertex x='0' y='1' z='0'/>
            </vertices>
            <triangles>
              <triangle v1='0' v2='1' v3='2'/>
            </triangles>
          </mesh>
        </object>
      </resources>
      <metadata name='trap'>
        <build>
          <item objectid='1'/>
        </build>
      </metadata>
    </model>
    """
    return try threeMFPackage(modelXML: model)
}

private func threeMFPackageWithNestedResourcesObjectLookalikeContainer() throws -> Data {
    let model = """
    <?xml version='1.0' encoding='UTF-8'?>
    <model unit='meter' xmlns='http://schemas.microsoft.com/3dmanufacturing/core/2015/02'>
      <metadata name='trap'>
        <resources>
          <object id='1' type='model'>
            <mesh>
              <vertices>
                <vertex x='0' y='0' z='0'/>
                <vertex x='1' y='0' z='0'/>
                <vertex x='0' y='1' z='0'/>
              </vertices>
              <triangles>
                <triangle v1='0' v2='1' v3='2'/>
              </triangles>
            </mesh>
          </object>
        </resources>
      </metadata>
      <build>
        <item objectid='1'/>
      </build>
    </model>
    """
    return try threeMFPackage(modelXML: model)
}

private func binarySTLWithNonFiniteVertex() -> Data {
    var data = Data(count: 80)
    data.appendLittleEndian(UInt32(1))
    data.appendLittleEndianFloat32(0.0)
    data.appendLittleEndianFloat32(0.0)
    data.appendLittleEndianFloat32(1.0)
    data.appendLittleEndianFloat32(.infinity)
    data.appendLittleEndianFloat32(0.0)
    data.appendLittleEndianFloat32(0.0)
    data.appendLittleEndianFloat32(1.0)
    data.appendLittleEndianFloat32(0.0)
    data.appendLittleEndianFloat32(0.0)
    data.appendLittleEndianFloat32(0.0)
    data.appendLittleEndianFloat32(1.0)
    data.appendLittleEndianFloat32(0.0)
    data.appendLittleEndian(UInt16(0))
    return data
}

private func binarySTLWithFacetNormal(_ normal: Vector3D) -> Data {
    var data = Data(count: 80)
    data.appendLittleEndian(UInt32(1))
    data.appendLittleEndianFloat32(Float32(normal.x))
    data.appendLittleEndianFloat32(Float32(normal.y))
    data.appendLittleEndianFloat32(Float32(normal.z))
    data.appendLittleEndianFloat32(0.0)
    data.appendLittleEndianFloat32(0.0)
    data.appendLittleEndianFloat32(0.0)
    data.appendLittleEndianFloat32(1.0)
    data.appendLittleEndianFloat32(0.0)
    data.appendLittleEndianFloat32(0.0)
    data.appendLittleEndianFloat32(0.0)
    data.appendLittleEndianFloat32(1.0)
    data.appendLittleEndianFloat32(0.0)
    data.appendLittleEndian(UInt16(0))
    return data
}

private func binarySTLHeaderOnly(triangleCount: UInt32) -> Data {
    var data = Data(count: 80)
    data.appendLittleEndian(triangleCount)
    return data
}

private func binarySTLWithUnitHeader(_ unit: String) throws -> Data {
    try binarySTLWithSwiftCADUnitHeaderSuffix(Data(unit.utf8))
}

private func binarySTLWithSwiftCADUnitHeaderSuffix(_ suffix: Data) throws -> Data {
    var data = try STLExporter(tolerance: .standard).exportBinary(meshes: [BodyID(): unitTriangleMesh(unit: .meter)])
    var header = Data("Swift-CAD binary STL unit=".utf8)
    header.append(suffix)
    header = Data(header.prefix(80))
    if header.count < 80 {
        header.append(Data(repeating: 0, count: 80 - header.count))
    }
    data.replaceSubrange(0..<80, with: header)
    return data
}

private func binarySTLWithNonSwiftCADUnitMarkerTrap() throws -> Data {
    var data = try STLExporter(tolerance: .standard).exportBinary(meshes: [BodyID(): unitTriangleMesh(unit: .meter)])
    let headerText = "Third-party binary STL metadata unit=millimeter"
    var header = Data(headerText.utf8.prefix(80))
    if header.count < 80 {
        header.append(Data(repeating: 0, count: 80 - header.count))
    }
    data.replaceSubrange(0..<80, with: header)
    return data
}

private func dxfWithInvalidUnitCode() throws -> Data {
    let data = try DXFExchange(tolerance: .standard).export(meshes: [BodyID(): unitTriangleMesh(unit: .meter)], unit: .meter)
    let text = try #require(String(data: data, encoding: .utf8))
    return Data(text.replacingOccurrences(of: "70\n6", with: "70\n999").utf8)
}

private func dxfWithUnitlessHeader() throws -> Data {
    let data = try DXFExchange(tolerance: .standard).export(meshes: [BodyID(): unitTriangleMesh(unit: .meter)], unit: .meter)
    let text = try #require(String(data: data, encoding: .utf8))
    return Data(text.replacingOccurrences(of: "70\n6", with: "70\n0").utf8)
}

private func dxfWithEntitySectionUnitTrap() -> String {
    """
    0
    SECTION
    2
    ENTITIES
    9
    $INSUNITS
    70
    4
    0
    3DFACE
    10
    0
    20
    0
    30
    0
    11
    2
    21
    0
    31
    0
    12
    0
    22
    3
    32
    4
    0
    ENDSEC
    0
    EOF
    """
}

private func dxfWithDuplicateHeaderUnitDeclarations() -> String {
    """
    0
    SECTION
    2
    HEADER
    9
    $INSUNITS
    70
    6
    9
    $INSUNITS
    70
    4
    0
    ENDSEC
    0
    SECTION
    2
    ENTITIES
    0
    3DFACE
    10
    0
    20
    0
    30
    0
    11
    1
    21
    0
    31
    0
    12
    0
    22
    1
    32
    0
    0
    ENDSEC
    0
    EOF
    """
}

private func dxfWithHeader3DFACETrap() -> String {
    """
    0
    SECTION
    2
    HEADER
    0
    3DFACE
    10
    0
    20
    0
    30
    0
    11
    100
    21
    0
    31
    0
    12
    0
    22
    100
    32
    0
    0
    ENDSEC
    0
    SECTION
    2
    ENTITIES
    0
    3DFACE
    10
    0
    20
    0
    30
    0
    11
    1
    21
    0
    31
    0
    12
    0
    22
    1
    32
    0
    0
    ENDSEC
    0
    EOF
    """
}

private func dxfWithUnterminatedHeaderSection() -> String {
    """
    0
    SECTION
    2
    HEADER
    9
    $INSUNITS
    70
    6
    0
    SECTION
    2
    ENTITIES
    0
    3DFACE
    10
    0
    20
    0
    30
    0
    11
    1
    21
    0
    31
    0
    12
    0
    22
    1
    32
    0
    0
    ENDSEC
    0
    EOF
    """
}

private func threeMFPackageWithInvalidUnit() throws -> Data {
    let model = """
    <?xml version='1.0' encoding='UTF-8'?>
    <model unit='parsec' xmlns='http://schemas.microsoft.com/3dmanufacturing/core/2015/02'>
      <resources>
        <object id='1' type='model'>
          <mesh>
            <vertices>
              <vertex x='0' y='0' z='0'/>
              <vertex x='1' y='0' z='0'/>
              <vertex x='0' y='1' z='0'/>
            </vertices>
            <triangles>
              <triangle v1='0' v2='1' v3='2'/>
            </triangles>
          </mesh>
        </object>
      </resources>
      <build>
        <item objectid='1'/>
      </build>
    </model>
    """
    return try threeMFPackage(modelXML: model)
}

private func dxfQuadrilateral3DFACE() -> String {
    """
    0
    SECTION
    2
    ENTITIES
    0
    3DFACE
    8
    SwiftCAD
    10
    0
    20
    0
    30
    0
    11
    1
    21
    0
    31
    0
    12
    1
    22
    1
    32
    0
    13
    0
    23
    1
    33
    0
    0
    ENDSEC
    0
    EOF
    """
}

private func stepWithNonFiniteFaceIndex() throws -> Data {
    let data = stepWithOnlyQuotedUnitTokens()
    let text = try #require(String(data: data, encoding: .utf8))
    return Data(text.replacingOccurrences(of: "((1,2,3))", with: "((1,nan,3))").utf8)
}

private func stepWithUnexpectedTupleContent() throws -> Data {
    let data = stepWithOnlyQuotedUnitTokens()
    let text = try #require(String(data: data, encoding: .utf8))
    return Data(text.replacingOccurrences(of: "((1,2,3))", with: "((1,2,3),bad)").utf8)
}

private func stepWithDuplicateEntityID() throws -> Data {
    let data = stepWithOnlyQuotedUnitTokens()
    let text = try #require(String(data: data, encoding: .utf8))
    let duplicate = "#16=CARTESIAN_POINT_LIST_3D('',((0,0,0),(1,0,0),(0,1,0)));"
    return Data(text.replacingOccurrences(of: "DATA;", with: "DATA;\n\(duplicate)").utf8)
}

private func stepWithMalformedTopLevelEntityMarker() throws -> Data {
    let data = stepWithOnlyQuotedUnitTokens()
    let text = try #require(String(data: data, encoding: .utf8))
    return Data(text.replacingOccurrences(
        of: "DATA;",
        with: "DATA;\n#broken STEP entity marker;"
    ).utf8)
}

private func stepWithTrailingCommaPointTuple() throws -> Data {
    let data = stepWithOnlyQuotedUnitTokens()
    let text = try #require(String(data: data, encoding: .utf8))
    return Data(text.replacingOccurrences(of: "((0,0,0),", with: "((0,0,0,),").utf8)
}

private func stepWithUnreferencedPointList() throws -> Data {
    let data = stepWithOnlyQuotedUnitTokens()
    let text = try #require(String(data: data, encoding: .utf8))
    let hiddenPointList = "#999=CARTESIAN_POINT_LIST_3D('',((10,10,10),(11,10,10),(10,11,10)));"
    return Data(text.replacingOccurrences(of: "DATA;", with: "DATA;\n\(hiddenPointList)").utf8)
}

private func stepWithUnsupportedDataEntity() throws -> Data {
    let data = stepWithOnlyQuotedUnitTokens()
    let text = try #require(String(data: data, encoding: .utf8))
    let unsupportedEntity = "#999=ADVANCED_BREP_SHAPE_REPRESENTATION('',(),#9);"
    return Data(text.replacingOccurrences(of: "DATA;", with: "DATA;\n\(unsupportedEntity)").utf8)
}

private func stepWithHeaderEntityTrap() -> Data {
    Data("""
    ISO-10303-21;
    HEADER;
    FILE_DESCRIPTION(('Swift-CAD test'),'2;1');
    FILE_SCHEMA(('AP242_MANAGED_MODEL_BASED_3D_ENGINEERING_MIM_LF'));
    #1=CARTESIAN_POINT_LIST_3D('',((0,0,0),(2,0,0),(0,3,4)));
    #2=TRIANGULATED_FACE_SET('',#1,$,$,.T.,((1,2,3)),$);
    ENDSEC;
    DATA;
    ENDSEC;
    END-ISO-10303-21;
    """.utf8)
}

private func stepWithoutExchangeTerminator() throws -> Data {
    let data = stepWithOnlyQuotedUnitTokens()
    let text = try #require(String(data: data, encoding: .utf8))
    return Data(text.replacingOccurrences(of: "END-ISO-10303-21;", with: "").utf8)
}

private func stepWithTrailingPayloadAfterExchangeTerminator() throws -> Data {
    let data = stepWithOnlyQuotedUnitTokens()
    let text = try #require(String(data: data, encoding: .utf8))
    return Data((text + "\nTRAILING_PAYLOAD").utf8)
}

private func stepWithQuotedParserTraps() throws -> Data {
    stepWithOnlyQuotedUnitTokens()
}

private func stepWithOnlyQuotedUnitTokens() -> Data {
    Data("""
    ISO-10303-21;
    HEADER;
    FILE_DESCRIPTION(('Swift-CAD test'),'2;1');
    FILE_SCHEMA(('AP242_MANAGED_MODEL_BASED_3D_ENGINEERING_MIM_LF'));
    ENDSEC;
    DATA;
    #1=PRODUCT('LENGTH_UNIT() SI_UNIT(.MILLI.,.METRE.)','quoted only','',());
    #2=CARTESIAN_POINT_LIST_3D('',((0,0,0),(2,0,0),(0,3,4)));
    #3=TRIANGULATED_FACE_SET('',#2,$,$,.T.,((1,2,3)),$);
    ENDSEC;
    END-ISO-10303-21;
    """.utf8)
}

private func stepWithUnreferencedLengthUnitsBeforeContextUnit() -> Data {
    Data("""
    ISO-10303-21;
    HEADER;
    FILE_DESCRIPTION(('Swift-CAD test'),'2;1');
    FILE_SCHEMA(('AP242_MANAGED_MODEL_BASED_3D_ENGINEERING_MIM_LF'));
    ENDSEC;
    DATA;
    #1=APPLICATION_CONTEXT('mechanical design');
    #9=(GEOMETRIC_REPRESENTATION_CONTEXT(3) GLOBAL_UNIT_ASSIGNED_CONTEXT((#20,#21,#22)) REPRESENTATION_CONTEXT('Swift-CAD 3D context','3D'));
    #10=(LENGTH_UNIT() NAMED_UNIT(*) SI_UNIT(.MILLI.,.METRE.));
    #11=(LENGTH_UNIT() NAMED_UNIT(*) SI_UNIT(.CENTI.,.METRE.));
    #12=(CONVERSION_BASED_UNIT('INCH',#13) LENGTH_UNIT() NAMED_UNIT(#14));
    #13=LENGTH_MEASURE_WITH_UNIT(LENGTH_MEASURE(0.025399999999999999),#15);
    #14=DIMENSIONAL_EXPONENTS(1.,0.,0.,0.,0.,0.,0.);
    #15=(LENGTH_UNIT() NAMED_UNIT(*) SI_UNIT($,.METRE.));
    #20=(LENGTH_UNIT() NAMED_UNIT(*) SI_UNIT($,.METRE.));
    #21=(NAMED_UNIT(*) PLANE_ANGLE_UNIT() SI_UNIT($,.RADIAN.));
    #22=(NAMED_UNIT(*) SOLID_ANGLE_UNIT() SI_UNIT($,.STERADIAN.));
    #30=CARTESIAN_POINT_LIST_3D('',((0,0,0),(2,0,0),(0,3,4)));
    #31=TRIANGULATED_FACE_SET('',#30,$,$,.T.,((1,2,3)),$);
    ENDSEC;
    END-ISO-10303-21;
    """.utf8)
}

private func stepWithUnsupportedGlobalLengthUnit() -> Data {
    Data("""
    ISO-10303-21;
    HEADER;
    FILE_DESCRIPTION(('Swift-CAD test'),'2;1');
    FILE_SCHEMA(('AP242_MANAGED_MODEL_BASED_3D_ENGINEERING_MIM_LF'));
    ENDSEC;
    DATA;
    #9=(GEOMETRIC_REPRESENTATION_CONTEXT(3) GLOBAL_UNIT_ASSIGNED_CONTEXT((#20,#21,#22)) REPRESENTATION_CONTEXT('Swift-CAD 3D context','3D'));
    #20=(LENGTH_UNIT() NAMED_UNIT(*) SI_UNIT(.DECI.,.METRE.));
    #21=(NAMED_UNIT(*) PLANE_ANGLE_UNIT() SI_UNIT($,.RADIAN.));
    #22=(NAMED_UNIT(*) SOLID_ANGLE_UNIT() SI_UNIT($,.STERADIAN.));
    #30=CARTESIAN_POINT_LIST_3D('',((0,0,0),(2,0,0),(0,3,4)));
    #31=TRIANGULATED_FACE_SET('',#30,$,$,.T.,((1,2,3)),$);
    ENDSEC;
    END-ISO-10303-21;
    """.utf8)
}

private func stepWithMismatchedConversionLengthFactor() -> Data {
    Data("""
    ISO-10303-21;
    HEADER;
    FILE_DESCRIPTION(('Swift-CAD test'),'2;1');
    FILE_SCHEMA(('AP242_MANAGED_MODEL_BASED_3D_ENGINEERING_MIM_LF'));
    ENDSEC;
    DATA;
    #9=(GEOMETRIC_REPRESENTATION_CONTEXT(3) GLOBAL_UNIT_ASSIGNED_CONTEXT((#20,#21,#22)) REPRESENTATION_CONTEXT('Swift-CAD 3D context','3D'));
    #20=(CONVERSION_BASED_UNIT('INCH',#23) LENGTH_UNIT() NAMED_UNIT(#24));
    #21=(NAMED_UNIT(*) PLANE_ANGLE_UNIT() SI_UNIT($,.RADIAN.));
    #22=(NAMED_UNIT(*) SOLID_ANGLE_UNIT() SI_UNIT($,.STERADIAN.));
    #23=LENGTH_MEASURE_WITH_UNIT(LENGTH_MEASURE(1.0),#25);
    #24=DIMENSIONAL_EXPONENTS(1.,0.,0.,0.,0.,0.,0.);
    #25=(LENGTH_UNIT() NAMED_UNIT(*) SI_UNIT($,.METRE.));
    #30=CARTESIAN_POINT_LIST_3D('',((0,0,0),(2,0,0),(0,3,4)));
    #31=TRIANGULATED_FACE_SET('',#30,$,$,.T.,((1,2,3)),$);
    ENDSEC;
    END-ISO-10303-21;
    """.utf8)
}

private func stepWithMissingConversionLengthFactor() -> Data {
    Data("""
    ISO-10303-21;
    HEADER;
    FILE_DESCRIPTION(('Swift-CAD test'),'2;1');
    FILE_SCHEMA(('AP242_MANAGED_MODEL_BASED_3D_ENGINEERING_MIM_LF'));
    ENDSEC;
    DATA;
    #9=(GEOMETRIC_REPRESENTATION_CONTEXT(3) GLOBAL_UNIT_ASSIGNED_CONTEXT((#20,#21,#22)) REPRESENTATION_CONTEXT('Swift-CAD 3D context','3D'));
    #20=(CONVERSION_BASED_UNIT('FOOT',#999) LENGTH_UNIT() NAMED_UNIT(#24));
    #21=(NAMED_UNIT(*) PLANE_ANGLE_UNIT() SI_UNIT($,.RADIAN.));
    #22=(NAMED_UNIT(*) SOLID_ANGLE_UNIT() SI_UNIT($,.STERADIAN.));
    #24=DIMENSIONAL_EXPONENTS(1.,0.,0.,0.,0.,0.,0.);
    #25=(LENGTH_UNIT() NAMED_UNIT(*) SI_UNIT($,.METRE.));
    #30=CARTESIAN_POINT_LIST_3D('',((0,0,0),(2,0,0),(0,3,4)));
    #31=TRIANGULATED_FACE_SET('',#30,$,$,.T.,((1,2,3)),$);
    ENDSEC;
    END-ISO-10303-21;
    """.utf8)
}

private func stepWithUnrelatedLengthUnitAfterGlobalContextList() -> Data {
    Data("""
    ISO-10303-21;
    HEADER;
    FILE_DESCRIPTION(('Swift-CAD test'),'2;1');
    FILE_SCHEMA(('AP242_MANAGED_MODEL_BASED_3D_ENGINEERING_MIM_LF'));
    ENDSEC;
    DATA;
    #9=(GEOMETRIC_REPRESENTATION_CONTEXT(3) GLOBAL_UNIT_ASSIGNED_CONTEXT((#21,#22)) REPRESENTATION_CONTEXT('Swift-CAD 3D context','3D') EXTRA_REFERENCE(#20));
    #20=(LENGTH_UNIT() NAMED_UNIT(*) SI_UNIT($,.METRE.));
    #21=(NAMED_UNIT(*) PLANE_ANGLE_UNIT() SI_UNIT($,.RADIAN.));
    #22=(NAMED_UNIT(*) SOLID_ANGLE_UNIT() SI_UNIT($,.STERADIAN.));
    #30=CARTESIAN_POINT_LIST_3D('',((0,0,0),(2,0,0),(0,3,4)));
    #31=TRIANGULATED_FACE_SET('',#30,$,$,.T.,((1,2,3)),$);
    ENDSEC;
    END-ISO-10303-21;
    """.utf8)
}

private func stepWithMissingGlobalUnitReference() -> Data {
    Data("""
    ISO-10303-21;
    HEADER;
    FILE_DESCRIPTION(('Swift-CAD test'),'2;1');
    FILE_SCHEMA(('AP242_MANAGED_MODEL_BASED_3D_ENGINEERING_MIM_LF'));
    ENDSEC;
    DATA;
    #9=(GEOMETRIC_REPRESENTATION_CONTEXT(3) GLOBAL_UNIT_ASSIGNED_CONTEXT((#20,#21,#22)) REPRESENTATION_CONTEXT('Swift-CAD 3D context','3D'));
    #20=(LENGTH_UNIT() NAMED_UNIT(*) SI_UNIT($,.METRE.));
    #21=(NAMED_UNIT(*) PLANE_ANGLE_UNIT() SI_UNIT($,.RADIAN.));
    #30=CARTESIAN_POINT_LIST_3D('',((0,0,0),(2,0,0),(0,3,4)));
    #31=TRIANGULATED_FACE_SET('',#30,$,$,.T.,((1,2,3)),$);
    ENDSEC;
    END-ISO-10303-21;
    """.utf8)
}

private func stepWithAmbiguousGlobalLengthUnits() -> Data {
    Data("""
    ISO-10303-21;
    HEADER;
    FILE_DESCRIPTION(('Swift-CAD test'),'2;1');
    FILE_SCHEMA(('AP242_MANAGED_MODEL_BASED_3D_ENGINEERING_MIM_LF'));
    ENDSEC;
    DATA;
    #9=(GEOMETRIC_REPRESENTATION_CONTEXT(3) GLOBAL_UNIT_ASSIGNED_CONTEXT((#20,#21,#22)) REPRESENTATION_CONTEXT('Swift-CAD 3D context','3D'));
    #20=(LENGTH_UNIT() NAMED_UNIT(*) SI_UNIT($,.METRE.));
    #21=(LENGTH_UNIT() NAMED_UNIT(*) SI_UNIT(.MILLI.,.METRE.));
    #22=(NAMED_UNIT(*) PLANE_ANGLE_UNIT() SI_UNIT($,.RADIAN.));
    #30=CARTESIAN_POINT_LIST_3D('',((0,0,0),(2,0,0),(0,3,4)));
    #31=TRIANGULATED_FACE_SET('',#30,$,$,.T.,((1,2,3)),$);
    ENDSEC;
    END-ISO-10303-21;
    """.utf8)
}

private func igesWithNonFiniteLineCoordinate() -> String {
    [
        igesTestSectionRecord("Swift-CAD test", section: "S", sequence: 1),
        igesTestParameterRecord("110,nan,0,0,1,0,0;", sequence: 1),
        igesTestParameterRecord("110,1,0,0,0,1,0;", sequence: 2),
        igesTestParameterRecord("110,0,1,0,nan,0,0;", sequence: 3),
        igesTestSectionRecord("S      1G      0D      0P      3", section: "T", sequence: 1)
    ].joined(separator: "\n")
}

private func igesWithStartSectionUnitTrap() throws -> Data {
    let globalRecords = igesTestSectionRecords(igesGlobalFixture(), section: "G")
    let records = [
        igesTestSectionRecord("Swift-CAD 2HMM ignored start text", section: "S", sequence: 1),
    ] + globalRecords + [
        igesTestSectionRecord(igesDirectoryFixture(), section: "D", sequence: 1),
        igesTestSectionRecord(igesDirectoryFixture(second: true), section: "D", sequence: 2),
        igesTestParameterRecord("110,0,0,0,1,0,0;", sequence: 1),
        igesTestSectionRecord("S      1G      (globalRecords.count)D      2P      1", section: "T", sequence: 1)
    ]
    return Data(records.joined(separator: "\n").utf8)
}

private func igesGlobalFixture() -> String {
    "1H,,1H;,4HSWFT,13Hswift-cad.igs,9HSwift-CAD,9HSwift-CAD,32,38,6,308,15,1.0,2,6,1HM,1,0.001,15H20260603.000000,1.0E-6,0.0,9H1amageek,9HSwift-CAD,11,0,15H20260603.000000;"
}

private func igesDirectoryFixture(second: Bool = false) -> String {
    if second {
        return "     110       0       0       1       0       0       0       0       0"
    }
    return "     110       1       0       0       0       0       0       0       0"
}

private func igesWithParameterSectionButNoGlobalOrDirectory() -> String {
    [
        igesTestSectionRecord("Swift-CAD test", section: "S", sequence: 1),
        igesTestParameterRecord("110,0,0,0,1,0,0;", sequence: 1),
        igesTestParameterRecord("110,1,0,0,0,1,0;", sequence: 2),
        igesTestParameterRecord("110,0,1,0,0,0,0;", sequence: 3),
        igesTestSectionRecord("S      1G      0D      0P      3", section: "T", sequence: 1)
    ].joined(separator: "\n")
}

private func igesWithMalformedType110BeforeValidTriangle() -> String {
    [
        igesTestSectionRecord("Swift-CAD test", section: "S", sequence: 1),
        igesTestParameterRecord("110;", sequence: 1),
        igesTestParameterRecord("110,0,0,0,1,0,0;", sequence: 2),
        igesTestParameterRecord("110,1,0,0,0,1,0;", sequence: 3),
        igesTestParameterRecord("110,0,1,0,0,0,0;", sequence: 4),
        igesTestSectionRecord("S      1G      0D      0P      4", section: "T", sequence: 1)
    ].joined(separator: "\n")
}

private func igesWithUnsupportedEntityBeforeValidTriangle() -> String {
    [
        igesTestSectionRecord("Swift-CAD test", section: "S", sequence: 1),
        igesTestParameterRecord("116,0,0,0;", sequence: 1),
        igesTestParameterRecord("110,0,0,0,1,0,0;", sequence: 2),
        igesTestParameterRecord("110,1,0,0,0,1,0;", sequence: 3),
        igesTestParameterRecord("110,0,1,0,0,0,0;", sequence: 4),
        igesTestSectionRecord("S      1G      0D      0P      4", section: "T", sequence: 1)
    ].joined(separator: "\n")
}

private func igesWithUnterminatedType110Record() -> String {
    [
        igesTestSectionRecord("Swift-CAD test", section: "S", sequence: 1),
        igesTestParameterRecord("110,0,0,0,1,0,0;", sequence: 1),
        igesTestParameterRecord("110,1,0,0,0,1,0;", sequence: 2),
        igesTestParameterRecord("110,0,1,0,0,0,0", sequence: 3),
        igesTestSectionRecord("S      1G      0D      0P      3", section: "T", sequence: 1)
    ].joined(separator: "\n")
}

private func igesWithTrailingCommaType110Record() -> String {
    [
        igesTestSectionRecord("Swift-CAD test", section: "S", sequence: 1),
        igesTestParameterRecord("110,0,0,0,1,0,0,;", sequence: 1),
        igesTestParameterRecord("110,1,0,0,0,1,0;", sequence: 2),
        igesTestParameterRecord("110,0,1,0,0,0,0;", sequence: 3),
        igesTestSectionRecord("S      1G      0D      0P      3", section: "T", sequence: 1)
    ].joined(separator: "\n")
}

private func igesTestParameterRecord(_ content: String, sequence: Int) -> String {
    let body = content.padding(toLength: 64, withPad: " ", startingAt: 0)
        + String(format: "%8d", locale: Locale(identifier: "en_US_POSIX"), 1)
    return body + "P" + String(format: "%7d", locale: Locale(identifier: "en_US_POSIX"), sequence)
}

private func igesTestSectionRecord(_ content: String, section: Character, sequence: Int) -> String {
    let body = content.padding(toLength: 72, withPad: " ", startingAt: 0)
    return body + String(section) + String(format: "%7d", locale: Locale(identifier: "en_US_POSIX"), sequence)
}

private func igesTestSectionRecords(_ content: String, section: Character) -> [String] {
    let characters = Array(content)
    guard !characters.isEmpty else {
        return [igesTestSectionRecord("", section: section, sequence: 1)]
    }
    var records: [String] = []
    var offset = 0
    var sequence = 1
    while offset < characters.count {
        let end = min(offset + 72, characters.count)
        records.append(igesTestSectionRecord(
            String(characters[offset..<end]),
            section: section,
            sequence: sequence
        ))
        offset = end
        sequence += 1
    }
    return records
}

private func igesGlobalText(in data: Data) throws -> String {
    let text = try #require(String(data: data, encoding: .utf8))
    return text
        .split(separator: "\n", omittingEmptySubsequences: false)
        .filter { line in
            let characters = Array(line)
            return characters.count >= 73 && characters[72] == "G"
        }
        .map { String($0.prefix(72)) }
        .joined()
}

private func makeEvaluatedDocument() throws -> EvaluatedDocument {
    let widthID = ParameterID()
    let heightID = ParameterID()
    let depthID = ParameterID()
    let parameters = ParameterTable(parameters: [
        widthID: Parameter(id: widthID, name: "width", expression: .constant(.length(40, unit: .millimeter)), kind: .length),
        heightID: Parameter(id: heightID, name: "height", expression: .constant(.length(20, unit: .millimeter)), kind: .length),
        depthID: Parameter(id: depthID, name: "depth", expression: .constant(.length(10, unit: .millimeter)), kind: .length)
    ])

    let sketchFeatureID = FeatureID()
    let extrudeFeatureID = FeatureID()
    let sketch = Sketch(
        plane: .xy,
        entities: rectangleEntities(widthID: widthID, heightID: heightID),
        constraints: [],
        dimensions: []
    )
    let document = CADDocument(
        units: .millimeters,
        parameters: parameters,
        designGraph: DesignGraph(
            nodes: [
                sketchFeatureID: FeatureNode(
                    id: sketchFeatureID,
                    operation: .sketch(sketch),
                    outputs: [FeatureOutput(role: .profile)]
                ),
                extrudeFeatureID: FeatureNode(
                    id: extrudeFeatureID,
                    operation: .extrude(ExtrudeFeature(profile: ProfileReference(featureID: sketchFeatureID), distance: .reference(depthID))),
                    inputs: [FeatureInput(featureID: sketchFeatureID, role: .profile)],
                    outputs: [FeatureOutput(role: .body)]
                )
            ],
            order: [sketchFeatureID, extrudeFeatureID],
            dependencies: [DependencyEdge(source: sketchFeatureID, target: extrudeFeatureID)]
        ),
        metadata: DocumentMetadata(name: "Official Formats")
    )
    return try DocumentEvaluator(tolerance: .standard).evaluate(document)
}

private func replacing(
    _ evaluated: EvaluatedDocument,
    document: CADDocument? = nil,
    brep: BRepModel? = nil,
    meshes: PersistentMap<BodyID, Mesh>? = nil
) -> EvaluatedDocument {
    EvaluatedDocument(
        document: document ?? evaluated.document,
        parameters: evaluated.parameters,
        brep: brep ?? evaluated.brep,
        meshes: meshes ?? evaluated.meshes,
        curves: evaluated.curves,
        caches: evaluated.caches,
        subshapes: evaluated.subshapes,
        lineage: evaluated.lineage,
        configuration: evaluated.configuration,
        evaluationMetrics: evaluated.evaluationMetrics
    )
}

private func rectangleEntities(widthID: ParameterID, heightID: ParameterID) -> [SketchEntityID: SketchEntity] {
    let two = CADExpression.constant(.scalar(2))
    let minusOne = CADExpression.constant(.scalar(-1))
    let halfWidth = CADExpression.divide(.reference(widthID), two)
    let halfHeight = CADExpression.divide(.reference(heightID), two)
    let negativeHalfWidth = CADExpression.multiply(minusOne, halfWidth)
    let negativeHalfHeight = CADExpression.multiply(minusOne, halfHeight)
    let bottomLeft = SketchPoint(x: negativeHalfWidth, y: negativeHalfHeight)
    let bottomRight = SketchPoint(x: halfWidth, y: negativeHalfHeight)
    let topRight = SketchPoint(x: halfWidth, y: halfHeight)
    let topLeft = SketchPoint(x: negativeHalfWidth, y: halfHeight)
    return [
        SketchEntityID(): .line(SketchLine(start: bottomLeft, end: bottomRight)),
        SketchEntityID(): .line(SketchLine(start: bottomRight, end: topRight)),
        SketchEntityID(): .line(SketchLine(start: topRight, end: topLeft)),
        SketchEntityID(): .line(SketchLine(start: topLeft, end: bottomLeft))
    ]
}

private func signatureMatches(_ data: Data, format: ExchangeFileFormat) throws -> Bool {
    let text = String(data: data, encoding: .utf8) ?? ""
    switch format {
    case .swiftCAD:
        return data.count >= 4 && data[0] == 0x50 && data[1] == 0x4b
    case .threeMF:
        let entries = try StoredZipArchive.readEntries(from: data)
        guard let modelData = entries["3D/3dmodel.model"],
              let modelText = String(data: modelData, encoding: .utf8) else {
            return false
        }
        return data.count >= 4
            && data[0] == 0x50
            && data[1] == 0x4b
            && modelText.contains("unit=\"millimeter\"")
    case .step:
        return text.contains("ISO-10303-21")
            && text.contains("FILE_SCHEMA(('AP242_MANAGED_MODEL_BASED_3D_ENGINEERING_MIM_LF'))")
            && text.contains("CARTESIAN_POINT_LIST_3D")
            && text.contains("TRIANGULATED_FACE_SET")
            && !text.contains(removedArchiveMarker)
    case .iges:
        return text.contains("S      1")
            && text.contains("D      1")
            && text.contains("P      1")
            && text.contains("T      1")
            && text.contains("110,")
            && !text.contains(removedArchiveMarker)
    case .stl:
        let header = String(data: Data(data[0..<80]), encoding: .utf8) ?? ""
        return data.count == 84 + 12 * 50 && header.contains("unit=millimeter")
    case .obj:
        return text.contains("# Swift-CAD OBJ") && text.contains("\nf ")
    case .dxf:
        return text.contains("SECTION") && text.contains("$INSUNITS") && text.contains("3DFACE")
    case .svg:
        return text.contains("<svg") && text.contains("data-unit=\"millimeter\"") && text.contains("<polygon")
    case .glb:
        return try data.littleEndianUInt32(at: 0) == 0x46546c67
    case .usd, .usda:
        let usdIsLoadable = try usdCheckerAccepts(data, fileExtension: format.rawValue)
        return text.contains("#usda 1.0")
            && text.contains("def Mesh")
            && text.contains("upAxis = \"Z\"")
            && usdIsLoadable
    case .usdc:
        let usdIsLoadable = try usdCheckerAccepts(data, fileExtension: "usdc")
        return data.count >= 8
            && Data(data[0..<8]) == Data("PXR-USDC".utf8)
            && usdIsLoadable
    case .usdz:
        let usdIsLoadable = try usdCheckerAccepts(data, fileExtension: "usdz")
        return data.count >= 4
            && data[0] == 0x50
            && data[1] == 0x4b
            && usdIsLoadable
    case .pdf:
        return text.hasPrefix("%PDF-1.4")
    }
}

private func meshExtents(_ meshes: [BodyID: Mesh]) throws -> (width: Double, height: Double, depth: Double) {
    let points = meshes.values.flatMap(\.positions)
    guard let first = points.first else {
        throw ImportError.invalidData("Imported mesh has no positions.")
    }
    var minX = first.x
    var maxX = first.x
    var minY = first.y
    var maxY = first.y
    var minZ = first.z
    var maxZ = first.z
    for point in points.dropFirst() {
        minX = min(minX, point.x)
        maxX = max(maxX, point.x)
        minY = min(minY, point.y)
        maxY = max(maxY, point.y)
        minZ = min(minZ, point.z)
        maxZ = max(maxZ, point.z)
    }
    return (maxX - minX, maxY - minY, maxZ - minZ)
}

private func usdCheckerAccepts(_ data: Data, fileExtension: String) throws -> Bool {
    let fileManager = FileManager.default
    let directoryURL = fileManager.temporaryDirectory.appendingPathComponent("SwiftCADTests-\(UUID().uuidString)", isDirectory: true)
    try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
    let fileURL = directoryURL.appendingPathComponent("scene").appendingPathExtension(fileExtension)
    do {
        try data.write(to: fileURL, options: .atomic)
        let result = try runTool(named: "usdchecker", arguments: [fileURL.path])
        try fileManager.removeItem(at: directoryURL)
        return result
    } catch {
        let primaryError = error
        do {
            try fileManager.removeItem(at: directoryURL)
        } catch {
            throw ExportError.fileWriteFailure(
                "Failed to remove temporary USD test directory after error \(primaryError.localizedDescription): \(error.localizedDescription)"
            )
        }
        throw primaryError
    }
}

private func runTool(named name: String, arguments: [String]) throws -> Bool {
    guard let executableURL = testExecutableURL(named: name) else {
        throw ExportError.externalToolUnavailable(name)
    }
    let process = Process()
    process.executableURL = executableURL
    process.arguments = arguments
    let outputURL = FileManager.default.temporaryDirectory.appendingPathComponent(
        "SwiftCAD-Test-\(name)-\(UUID().uuidString).log"
    )
    guard FileManager.default.createFile(atPath: outputURL.path, contents: nil) else {
        throw ExportError.fileWriteFailure("Failed to create USD test tool output file.")
    }
    let outputHandle: FileHandle
    do {
        outputHandle = try FileHandle(forWritingTo: outputURL)
    } catch {
        throw ExportError.fileWriteFailure(error.localizedDescription)
    }
    defer {
        outputHandle.closeFile()
    }
    process.standardOutput = outputHandle
    process.standardError = outputHandle
    do {
        try process.run()
    } catch {
        let outputText = testToolOutputText(from: outputURL)
        let cleanupMessage = removeTestToolOutputLogMessage(at: outputURL)
        throw ExportError.externalToolFailure(
            tool: name,
            output: testToolDiagnostic(
                primary: "Failed to launch \(name): \(error.localizedDescription)",
                outputText: outputText,
                cleanupMessage: cleanupMessage
            )
        )
    }
    let deadline = Date().addingTimeInterval(testToolTimeoutSeconds)
    while process.isRunning {
        if Date() >= deadline {
            let terminationText = terminateTestTool(process, name: name)
            let outputText = testToolOutputText(from: outputURL)
            let cleanupMessage = removeTestToolOutputLogMessage(at: outputURL)
            throw ExportError.externalToolFailure(
                tool: name,
                output: testToolDiagnostic(
                    primary: terminationText,
                    outputText: outputText,
                    cleanupMessage: cleanupMessage
                )
            )
        }
        Thread.sleep(forTimeInterval: 0.02)
    }
    let outputText = testToolOutputText(from: outputURL)
    if process.terminationStatus != 0 {
        let cleanupMessage = removeTestToolOutputLogMessage(at: outputURL)
        throw ExportError.externalToolFailure(
            tool: name,
            output: testToolDiagnostic(
                primary: "\(name) exited with status \(process.terminationStatus).",
                outputText: outputText,
                cleanupMessage: cleanupMessage
            )
        )
    }
    try removeTestToolOutputLog(at: outputURL)
    return true
}

private let testToolTimeoutSeconds: TimeInterval = 30.0
private let testToolTerminationGraceSeconds: TimeInterval = 2.0

private func testToolOutputText(from url: URL) -> String {
    do {
        let output = try Data(contentsOf: url)
        return String(data: output, encoding: .utf8) ?? "USD test tool output was not valid UTF-8."
    } catch {
        return "Failed to read USD test tool output log: \(error.localizedDescription)"
    }
}

private func terminateTestTool(_ process: Process, name: String) -> String {
    process.terminate()
    let terminationDeadline = Date().addingTimeInterval(testToolTerminationGraceSeconds)
    if waitForTestToolExit(process, until: terminationDeadline) {
        return "Timed out after \(testToolTimeoutSeconds) seconds; \(name) terminated after SIGTERM."
    }
    let didSendKill = sendKillSignal(to: process)
    let killDeadline = Date().addingTimeInterval(testToolTerminationGraceSeconds)
    if waitForTestToolExit(process, until: killDeadline) {
        if didSendKill {
            return "Timed out after \(testToolTimeoutSeconds) seconds; \(name) required SIGKILL."
        }
        return "Timed out after \(testToolTimeoutSeconds) seconds; \(name) exited after SIGTERM grace elapsed."
    }
    if didSendKill {
        return "Timed out after \(testToolTimeoutSeconds) seconds; \(name) remained running after SIGKILL."
    }
    return "Timed out after \(testToolTimeoutSeconds) seconds; failed to send SIGKILL to \(name)."
}

private func waitForTestToolExit(_ process: Process, until deadline: Date) -> Bool {
    while process.isRunning {
        if Date() >= deadline {
            return false
        }
        Thread.sleep(forTimeInterval: 0.02)
    }
    return true
}

private func sendKillSignal(to process: Process) -> Bool {
    #if os(macOS)
    return Darwin.kill(process.processIdentifier, SIGKILL) == 0
    #else
    process.terminate()
    return false
    #endif
}

private func removeTestToolOutputLog(at url: URL) throws {
    do {
        try FileManager.default.removeItem(at: url)
    } catch {
        throw ExportError.fileWriteFailure(
            "Failed to remove USD test tool output log: \(error.localizedDescription)"
        )
    }
}

private func removeTestToolOutputLogMessage(at url: URL) -> String? {
    do {
        try FileManager.default.removeItem(at: url)
        return nil
    } catch {
        return "Failed to remove USD test tool output log: \(error.localizedDescription)"
    }
}

private func testToolDiagnostic(primary: String, outputText: String, cleanupMessage: String?) -> String {
    var lines = [primary, outputText].filter { !$0.isEmpty }
    if let cleanupMessage {
        lines.append(cleanupMessage)
    }
    return lines.joined(separator: "\n")
}

private func testExecutableURL(named name: String) -> URL? {
    let environmentPath = ProcessInfo.processInfo.environment["PATH"] ?? ""
    var searchPaths = environmentPath.split(separator: ":").map(String.init)
    searchPaths.append(contentsOf: ["/usr/bin", "/usr/local/bin", "/opt/homebrew/bin"])
    var visited: Set<String> = []
    for path in searchPaths where !visited.contains(path) {
        visited.insert(path)
        let candidate = URL(fileURLWithPath: path).appendingPathComponent(name)
        if FileManager.default.isExecutableFile(atPath: candidate.path) {
            return candidate
        }
    }
    return nil
}
