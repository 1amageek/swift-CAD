import Foundation
import Testing
@testable import SwiftCAD

private func collectBytes(_ operation: (any ByteSink) throws -> Void) throws -> Data {
    let sink = DataByteSink()
    try operation(sink)
    return sink.bytes
}

private extension CADPipeline {
    func exportBinarySTL(from evaluatedDocument: EvaluatedDocument, lengthUnit: LengthUnit = .meter) throws -> Data {
        try collectBytes { try writeBinarySTL(from: evaluatedDocument, lengthUnit: lengthUnit, to: $0) }
    }

    func packageData(for document: CADDocument) throws -> Data {
        try collectBytes { try writePackage(for: document, to: $0) }
    }

    func loadDocument(fromPackageData data: Data) throws -> CADDocument {
        try loadDocument(from: BorrowedBytes(data))
    }
}

@Suite("SwiftCAD facade")
struct SwiftCADTests {
    @Test(.timeLimit(.minutes(1)))
    func facadeBuildsEvaluatesExportsAndRoundTripsOfficialPipeline() throws {
        let document = try CADDocument.millimeters(named: "Box") { cad in
            let width = cad.lengthParameter(named: "width", 40.0)
            let height = cad.lengthParameter(named: "height", 20.0)
            let depth = cad.lengthParameter(named: "depth", 10.0)

            let profile = try cad.sketch(on: .xy, named: "Base sketch") { sketch in
                sketch.rectangle(width: .parameter(width), height: .parameter(height))
            }

            cad.extrude(profile, distance: depth, named: "Extrude")
        }

        let pipeline = CADPipeline()
        let evaluated = try pipeline.evaluate(document)
        #expect(evaluated.brep.bodies.count == 1)
        #expect(evaluated.brep.faces.count == 6)
        #expect(evaluated.meshes.values.first?.indices.count == 36)
        #expect(evaluated.caches.brep?.parameterRevision == document.parameters.revision)

        let stl = try pipeline.exportBinarySTL(from: evaluated, lengthUnit: .millimeter)
        #expect(stl.count == 84 + 12 * 50)

        let packageData = try pipeline.packageData(for: document)
        let loaded = try pipeline.loadDocument(fromPackageData: packageData)
        #expect(loaded.metadata.name == "Box")
        #expect(loaded.designGraph.order.count == 2)
        #expect(loaded.parameters.parameters.count == 3)
    }

    @Test(.timeLimit(.minutes(1)))
    func facadeBuildsBridgeCurveSweepThroughSharedOperations() throws {
        let document = try CADDocument.millimeters(named: "Bridge Sweep") { cad in
            let width = cad.lengthParameter(named: "width", 40.0)
            let height = cad.lengthParameter(named: "height", 20.0)

            let profile = try cad.sketch(on: .xy, named: "Profile") { sketch in
                sketch.rectangle(width: .parameter(width), height: .parameter(height))
            }
            let path = try cad.bridgeCurve(
                from: BridgeCurveEndpointTarget(
                    curve: .line(Line3D(origin: .origin, direction: .unitZ)),
                    parameter: 0.0,
                    requiredLevel: .tangent
                ),
                to: BridgeCurveEndpointTarget(
                    curve: .line(Line3D(
                        origin: Point3D(x: 0.0, y: 0.0, z: 0.01),
                        direction: .unitZ
                    )),
                    parameter: 0.0,
                    requiredLevel: .tangent
                ),
                named: "Bridge path"
            )

            cad.sweep(profile, along: path, named: "Sweep")
        }

        let pipeline = CADPipeline()
        let evaluated = try pipeline.evaluate(document)
        #expect(evaluated.brep.bodies.count == 1)
        #expect(evaluated.brep.faces.count == 6)

        let packageData = try pipeline.packageData(for: document)
        let loaded = try pipeline.loadDocument(fromPackageData: packageData)
        #expect(loaded.metadata.name == "Bridge Sweep")
        #expect(loaded.designGraph.order.count == 3)
    }

    @Test(.timeLimit(.minutes(1)))
    func facadeExposesIntentFilteredSnapQueries() throws {
        let document = try makeBoxDocument(named: "Snap Box")
        let pipeline = CADPipeline()
        let evaluated = try pipeline.evaluate(document)
        let result = try pipeline.snapCandidates(
            near: Point3D(x: 0.0, y: -0.012, z: -0.002),
            in: evaluated,
            options: SnapQueryOptions(maximumDistance: 0.003, intent: .face)
        )

        let first = try #require(result.candidates.first)
        #expect(first.kind == .face)
        guard case .surface(.parameter) = first.selection else {
            Issue.record("Expected facade snap query to return a surface parameter reference.")
            return
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func facadeSavesLoadsExportsAndImportsThroughMappedFiles() throws {
        let document = try makeBoxDocument(named: "Mapped Box")
        let pipeline = CADPipeline()

        try withTemporaryDirectory { directoryURL in
            let nativeURL = directoryURL.appendingPathComponent("box.swcad")
            try pipeline.save(document, to: nativeURL)

            let loaded = try pipeline.load(from: nativeURL)
            #expect(loaded.metadata.name == "Mapped Box")
            #expect(loaded.designGraph.order.count == 2)

            let importedNative = try pipeline.importExchange(MappedFileByteSource(url: nativeURL), as: .swiftCAD)
            #expect(importedNative.document?.metadata.name == "Mapped Box")

            let evaluated = try pipeline.evaluate(loaded)
            let stlURL = directoryURL.appendingPathComponent("box.stl")
            let stlSink = try FileByteSink(url: stlURL)
            try pipeline.write(evaluated, as: .stl, to: stlSink)
            try stlSink.close()

            let attributes = try FileManager.default.attributesOfItem(atPath: stlURL.path)
            let byteCount = try #require(attributes[.size] as? NSNumber).intValue
            #expect(byteCount == 84 + 12 * 50)

            let importedSTL = try pipeline.importExchange(MappedFileByteSource(url: stlURL), as: .stl)
            #expect(importedSTL.format == .stl)
            #expect(importedSTL.units.length == .millimeter)
            #expect(importedSTL.meshes.count == 1)
            for mesh in importedSTL.meshes.values {
                try mesh.validate()
            }
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func facadeWritesEveryOfficialFormatAndImportsSupportedExports() throws {
        let document = try makeBoxDocument(named: "Format Matrix")
        let pipeline = CADPipeline()
        let evaluated = try pipeline.evaluate(document)

        for format in ExchangeFileFormat.allCases {
            let exported = try collectBytes { sink in
                try pipeline.write(evaluated, as: format, to: sink)
            }
            #expect(!exported.isEmpty)

            guard format.supportsImport else {
                continue
            }

            let imported = try pipeline.importExchange(BorrowedBytes(exported), as: format)
            #expect(imported.format == format)
            if format == .swiftCAD {
                #expect(imported.document?.metadata.name == "Format Matrix")
            } else {
                #expect(!imported.meshes.isEmpty)
                #expect(imported.units.length == .millimeter)
                for mesh in imported.meshes.values {
                    try mesh.validate()
                }
            }
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func facadeRejectsMalformedMappedImportFiles() throws {
        let pipeline = CADPipeline()

        try withTemporaryDirectory { directoryURL in
            let invalidNativeURL = directoryURL.appendingPathComponent("broken.swcad")
            try Data("not a native package".utf8).write(to: invalidNativeURL)
            #expect(throws: SchemaError.self) {
                _ = try pipeline.importExchange(MappedFileByteSource(url: invalidNativeURL), as: .swiftCAD)
            }

            let invalidImportCases: [(format: ExchangeFileFormat, fileName: String, data: Data)] = [
                (.step, "broken.step", Data("""
                ISO-10303-21;
                HEADER;
                ENDSEC;
                DATA;
                ENDSEC;
                END-ISO-10303-21;
                """.utf8)),
                (.iges, "broken.iges", Data()),
                (.stl, "broken.stl", Data(count: 83)),
                (.threeMF, "broken.3mf", Data("not a zip archive".utf8)),
                (.obj, "broken.obj", Data("""
                # Swift-CAD OBJ
                # unit millimeter
                v 0 0 0
                """.utf8)),
                (.dxf, "broken.dxf", Data("""
                0
                SECTION
                2
                ENTITIES
                0
                ENDSEC
                0
                EOF
                """.utf8)),
                (.svg, "broken.svg", Data("""
                <svg xmlns="http://www.w3.org/2000/svg" data-unit="millimeter"></svg>
                """.utf8)),
                (.usda, "broken.usda", Data("""
                #usda 1.0
                (
                    metersPerUnit = 0.001
                    upAxis = "Z"
                )
                """.utf8))
            ]

            for testCase in invalidImportCases {
                let url = directoryURL.appendingPathComponent(testCase.fileName)
                try testCase.data.write(to: url)
                #expect(throws: ImportError.self) {
                    _ = try pipeline.importExchange(MappedFileByteSource(url: url), as: testCase.format)
                }
            }
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func facadeRejectsFormatMismatchesAndUnsupportedImports() throws {
        let document = try makeBoxDocument(named: "Mismatch Matrix")
        let pipeline = CADPipeline()
        let evaluated = try pipeline.evaluate(document)
        let packageData = try pipeline.packageData(for: document)
        let stlData = try pipeline.exportBinarySTL(from: evaluated, lengthUnit: .millimeter)

        #expect(throws: ImportError.self) {
            _ = try pipeline.importExchange(BorrowedBytes(packageData), as: .stl)
        }
        #expect(throws: SchemaError.self) {
            _ = try pipeline.importExchange(BorrowedBytes(stlData), as: .swiftCAD)
        }
        #expect(throws: ImportError.self) {
            _ = try pipeline.importExchange(BorrowedBytes(stlData), as: .obj)
        }

        for format in ExchangeFileFormat.allCases where !format.supportsImport {
            #expect(throws: ImportError.self) {
                _ = try pipeline.importExchange(BorrowedBytes(stlData), as: format)
            }
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func failedFacadeNativeSavePreservesExistingFileContents() throws {
        var document = try makeBoxDocument(named: "Invalid Save")
        document.schemaVersion = SchemaVersion(major: SchemaVersion.current.major + 1, minor: 0, patch: 0)
        let pipeline = CADPipeline()

        try withTemporaryDirectory { directoryURL in
            let url = directoryURL.appendingPathComponent("existing.swcad")
            let originalData = Data("existing native payload".utf8)
            try originalData.write(to: url)

            #expect(throws: SchemaError.self) {
                try pipeline.save(document, to: url)
            }
            let preservedData = try Data(contentsOf: url)
            #expect(preservedData == originalData)
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func facadePropagatesSinkFailuresWithoutSwallowingErrors() throws {
        let document = try makeBoxDocument(named: "Failing Sink")
        let pipeline = CADPipeline()
        let evaluated = try pipeline.evaluate(document)

        #expect(throws: FailingByteSink.Error.self) {
            try pipeline.write(evaluated, as: .stl, to: FailingByteSink())
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func facadeRejectsInvalidDocumentsDuringBuild() {
        #expect(throws: ParameterError.self) {
            _ = try CADDocument.millimeters { cad in
                cad.lengthParameter(named: "width", 40.0)
                cad.lengthParameter(named: "width", 20.0)
            }
        }

        #expect(throws: UnitError.self) {
            var builder = DocumentBuilder(units: .millimeters)
            builder.lengthParameter(named: "depth", .nan)
            _ = try builder.build()
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func facadeRejectsStaleEvaluatedDocumentBeforeSTLExport() throws {
        let document = try CADDocument.millimeters { cad in
            let width = cad.lengthParameter(named: "width", 40.0)
            let height = cad.lengthParameter(named: "height", 20.0)
            let depth = cad.lengthParameter(named: "depth", 10.0)
            let profile = try cad.sketch(on: .xy) { sketch in
                sketch.rectangle(width: .parameter(width), height: .parameter(height))
            }
            cad.extrude(profile, distance: depth)
        }
        let pipeline = CADPipeline()
        var evaluated = try pipeline.evaluate(document)
        let bodyID = try #require(evaluated.meshes.keys.first)
        evaluated.meshes[bodyID]?.positions[0].x += 0.25

        #expect(throws: CacheValidationError.self) {
            _ = try pipeline.exportBinarySTL(from: evaluated, lengthUnit: .millimeter)
        }
    }
}

private struct FailingByteSink: ByteSink {
    enum Error: Swift.Error, Equatable {
        case forced
    }

    func write(_ bytes: UnsafeRawBufferPointer) throws {
        throw Error.forced
    }
}

private func makeBoxDocument(named name: String) throws -> CADDocument {
    try CADDocument.millimeters(named: name) { cad in
        let width = cad.lengthParameter(named: "width", 40.0)
        let height = cad.lengthParameter(named: "height", 20.0)
        let depth = cad.lengthParameter(named: "depth", 10.0)

        let profile = try cad.sketch(on: .xy, named: "Base sketch") { sketch in
            sketch.rectangle(width: .parameter(width), height: .parameter(height))
        }

        cad.extrude(profile, distance: depth, named: "Extrude")
    }
}

private func withTemporaryDirectory<Result>(_ body: (URL) throws -> Result) throws -> Result {
    let fileManager = FileManager.default
    let directoryURL = fileManager.temporaryDirectory.appendingPathComponent(
        "SwiftCADFacadeTests-\(UUID().uuidString)",
        isDirectory: true
    )
    try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
    do {
        let result = try body(directoryURL)
        try fileManager.removeItem(at: directoryURL)
        return result
    } catch {
        let primaryError = error
        do {
            try fileManager.removeItem(at: directoryURL)
        } catch {
        }
        throw primaryError
    }
}
