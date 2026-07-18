import Foundation
import Testing
import CADCore
import CADIR
@testable import CADExchange
import OpenUSD
import OpenUSDC
import OpenUSDZ

@Suite("USD Exchange Pure Swift Import")
struct USDExchangePureSwiftImportTests {
    @Test(.timeLimit(.minutes(1)))
    func pureSwiftUSDCImportMaterializesMeshExchangeModel() throws {
        let exchange = USDExchange(tolerance: .standard)
        let data = try usdFixture("minimal_mesh.usdc")

        let model = try exchange.import(BorrowedBytes(data), as: .usdc)

        try assertMinimalMeshExchangeModel(model, format: .usdc)
    }

    @Test(.timeLimit(.minutes(1)))
    func pureSwiftBinaryUSDImportMaterializesMeshExchangeModel() throws {
        let exchange = USDExchange(tolerance: .standard)
        let data = try usdFixture("minimal_mesh.usdc")

        let model = try exchange.import(BorrowedBytes(data), as: .usd)

        try assertMinimalMeshExchangeModel(model, format: .usd)
    }

    @Test(.timeLimit(.minutes(1)))
    func pureSwiftUSDZImportMaterializesMeshExchangeModel() throws {
        let exchange = USDExchange(tolerance: .standard)
        let package = try makeAlignedUSDZ(entries: [
            (path: "scene.usdc", data: usdFixture("minimal_mesh.usdc")),
        ])

        let model = try exchange.import(BorrowedBytes(package), as: .usdz)

        try assertMinimalMeshExchangeModel(model, format: .usdz)
    }

    @Test(.timeLimit(.minutes(1)))
    func pureSwiftUSDZImportComposesPackagedSublayers() throws {
        var childLayer = try USDMeshStageBuilder().stage(
            meshes: [BodyID(): Mesh(
                positions: [
                    Point3D(x: 0.0, y: 0.0, z: 0.0),
                    Point3D(x: 1.0, y: 0.0, z: 0.0),
                    Point3D(x: 0.0, y: 1.0, z: 0.0),
                ],
                indices: [0, 1, 2]
            )],
            unit: .meter,
            tolerance: .standard
        ).sdfRootLayer
        childLayer.identifier = "layers/mesh.usdc"
        let rootLayer = SdfLayer(
            identifier: "root.usda",
            specs: [
                SdfSpec(
                    path: .absoluteRoot,
                    specType: .pseudoRoot,
                    fields: [
                        "subLayers": .stringVector([childLayer.identifier]),
                    ]
                ),
            ]
        )
        let package = try USDZWriter().data(
            for: rootLayer,
            provider: USDInMemoryLayerProvider(layers: [
                childLayer.identifier: childLayer,
            ]),
            rootIdentifier: rootLayer.identifier,
            externalLayerFormat: .usdc
        )

        let model = try USDExchange(tolerance: .standard).import(
            BorrowedBytes(package),
            as: .usdz
        )

        try assertMinimalMeshExchangeModel(model, format: .usdz)
    }

    @Test(.timeLimit(.minutes(1)))
    func pureSwiftUSDAImportEvaluatesRequestedTimeSample() throws {
        let data = Data("""
        #usda 1.0
        (
            defaultPrim = "Triangle"
            metersPerUnit = 1
            upAxis = "Z"
        )

        def Mesh "Triangle"
        {
            point3f[] points.timeSamples = {
                1: [(0, 0, 0), (1, 0, 0), (0, 1, 0)],
                2: [(0, 0, 1), (1, 0, 1), (0, 1, 1)]
            }
            int[] faceVertexCounts = [3]
            int[] faceVertexIndices = [0, 1, 2]
            uniform token subdivisionScheme = "none"
        }
        """.utf8)
        let exchange = USDExchange(
            tolerance: .standard,
            readingOptions: USDReadingOptions(timeCode: 2)
        )

        let model = try exchange.import(BorrowedBytes(data), as: .usda)

        let mesh = try #require(model.meshes.values.first)
        #expect(mesh.positions == [
            Point3D(x: 0, y: 0, z: 1),
            Point3D(x: 1, y: 0, z: 1),
            Point3D(x: 0, y: 1, z: 1),
        ])
        #expect(mesh.indices == [0, 1, 2])
    }

    @Test(.timeLimit(.minutes(1)))
    func standaloneUSDAImportRejectsUnresolvedCompositionArc() throws {
        let data = Data("""
        #usda 1.0
        (
            subLayers = [@missing.usda@]
        )

        def Mesh "Triangle"
        {
            point3f[] points = [(0, 0, 0), (1, 0, 0), (0, 1, 0)]
            int[] faceVertexCounts = [3]
            int[] faceVertexIndices = [0, 1, 2]
            uniform token subdivisionScheme = "none"
        }
        """.utf8)

        do {
            _ = try USDExchange(tolerance: .standard).import(BorrowedBytes(data), as: .usda)
            Issue.record("An unresolved standalone composition arc must not be ignored.")
        } catch let error as ImportError {
            #expect(error == .compositionFailure(
                kind: "unresolvedStandaloneLayerArc",
                message: "Standalone USDA and USDC imports cannot resolve sublayers, references, or payloads. Package the dependency graph as USDZ."
            ))
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func standaloneUSDCImportRejectsUnresolvedCompositionArc() throws {
        let layer = SdfLayer(
            identifier: "root.usdc",
            specs: [
                SdfSpec(
                    path: .absoluteRoot,
                    specType: .pseudoRoot,
                    fields: [
                        "subLayers": .assetPathArray([SdfAssetPath(authoredPath: "missing.usdc")]),
                    ]
                ),
                try SdfSpec(
                    path: "/Triangle",
                    specType: .prim,
                    specifier: .def,
                    typeName: "Mesh"
                ),
            ]
        )
        let data = try USDCWriter().data(for: layer)

        do {
            _ = try USDExchange(tolerance: .standard).import(BorrowedBytes(data), as: .usdc)
            Issue.record("An unresolved standalone USDC composition arc must not be ignored.")
        } catch let error as ImportError {
            #expect(error == .compositionFailure(
                kind: "unresolvedStandaloneLayerArc",
                message: "Standalone USDA and USDC imports cannot resolve sublayers, references, or payloads. Package the dependency graph as USDZ."
            ))
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func standaloneUSDAImportRejectsVariantOpinionBeforeMaterialization() throws {
        let data = Data("""
        #usda 1.0

        def Mesh "Triangle" (
            variants = {
                string lod = "high"
            }
            prepend variantSets = "lod"
        )
        {
            point3f[] points = [(0, 0, 0), (1, 0, 0), (0, 1, 0)]
            int[] faceVertexCounts = [3]
            int[] faceVertexIndices = [0, 1, 2]
            uniform token subdivisionScheme = "none"

            variantSet "lod" = {
                "high" {
                    point3f[] points = [(0, 0, 1), (1, 0, 1), (0, 1, 1)]
                }
            }
        }
        """.utf8)

        do {
            _ = try USDExchange(tolerance: .standard).import(BorrowedBytes(data), as: .usda)
            Issue.record("A standalone variant opinion must not be ignored.")
        } catch let error as ImportError {
            #expect(error == .unsupportedFeature(
                "Standalone USDA and USDC imports require variant opinions to be composed before scene materialization."
            ))
        }
    }
}

private func assertMinimalMeshExchangeModel(_ model: ImportedExchangeModel, format: ExchangeFileFormat) throws {
    #expect(model.format == format)
    #expect(model.document == nil)
    #expect(model.units == .meters)
    #expect(model.meshes.count == 1)
    let mesh = try #require(model.meshes.values.first)
    #expect(mesh.positions == [
        Point3D(x: 0, y: 0, z: 0),
        Point3D(x: 1, y: 0, z: 0),
        Point3D(x: 0, y: 1, z: 0),
    ])
    #expect(mesh.indices == [0, 1, 2])
}

private func usdFixture(_ relativePath: String) throws -> Data {
    let url = Bundle.module.resourceURL?
        .appendingPathComponent("Fixtures")
        .appendingPathComponent("USD")
        .appendingPathComponent(relativePath)
    let fixtureURL = try #require(url)
    return try Data(contentsOf: fixtureURL)
}

private func makeAlignedUSDZ(entries: [(path: String, data: Data)]) throws -> Data {
    var archive = Data()
    var centralRecords: [(path: String, localHeaderOffset: UInt32, crc: UInt32, size: UInt32)] = []

    for entry in entries {
        let localHeaderOffset = UInt32(archive.count)
        let nameData = Data(entry.path.utf8)
        let payloadStartWithoutPadding = archive.count + 30 + nameData.count
        let extraLength = (64 - (payloadStartWithoutPadding % 64)) % 64
        let crc = CRC32.checksum(entry.data)
        let size = UInt32(entry.data.count)

        archive.appendLittleEndian(UInt32(0x04034b50))
        archive.appendLittleEndian(UInt16(20))
        archive.appendLittleEndian(UInt16(0))
        archive.appendLittleEndian(UInt16(0))
        archive.appendLittleEndian(UInt16(0))
        archive.appendLittleEndian(UInt16(0))
        archive.appendLittleEndian(crc)
        archive.appendLittleEndian(size)
        archive.appendLittleEndian(size)
        archive.appendLittleEndian(UInt16(nameData.count))
        archive.appendLittleEndian(UInt16(extraLength))
        archive.append(nameData)
        archive.append(Data(repeating: 0, count: extraLength))
        archive.append(entry.data)
        centralRecords.append((entry.path, localHeaderOffset, crc, size))
    }

    let centralDirectoryOffset = UInt32(archive.count)
    var centralDirectory = Data()
    for record in centralRecords {
        let nameData = Data(record.path.utf8)
        centralDirectory.appendLittleEndian(UInt32(0x02014b50))
        centralDirectory.appendLittleEndian(UInt16(20))
        centralDirectory.appendLittleEndian(UInt16(20))
        centralDirectory.appendLittleEndian(UInt16(0))
        centralDirectory.appendLittleEndian(UInt16(0))
        centralDirectory.appendLittleEndian(UInt16(0))
        centralDirectory.appendLittleEndian(UInt16(0))
        centralDirectory.appendLittleEndian(record.crc)
        centralDirectory.appendLittleEndian(record.size)
        centralDirectory.appendLittleEndian(record.size)
        centralDirectory.appendLittleEndian(UInt16(nameData.count))
        centralDirectory.appendLittleEndian(UInt16(0))
        centralDirectory.appendLittleEndian(UInt16(0))
        centralDirectory.appendLittleEndian(UInt16(0))
        centralDirectory.appendLittleEndian(UInt16(0))
        centralDirectory.appendLittleEndian(UInt32(0))
        centralDirectory.appendLittleEndian(record.localHeaderOffset)
        centralDirectory.append(nameData)
    }
    archive.append(centralDirectory)
    archive.appendLittleEndian(UInt32(0x06054b50))
    archive.appendLittleEndian(UInt16(0))
    archive.appendLittleEndian(UInt16(0))
    archive.appendLittleEndian(UInt16(centralRecords.count))
    archive.appendLittleEndian(UInt16(centralRecords.count))
    archive.appendLittleEndian(UInt32(centralDirectory.count))
    archive.appendLittleEndian(centralDirectoryOffset)
    archive.appendLittleEndian(UInt16(0))
    return archive
}
