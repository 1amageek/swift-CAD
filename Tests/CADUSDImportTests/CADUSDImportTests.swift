import Foundation
import Testing
import CADCore
import CADIR
import CADUSD
import OpenUSD
import OpenUSDC
import OpenUSDZ

@Suite("CAD USD Import Modules")
struct CADUSDImportTests {
    @Test(.timeLimit(.minutes(1)))
    func sceneImporterMaterializesUSDCScene() throws {
        let data = try usdFixture("minimal_mesh.usdc")
        let bytes = USDByteStorage(data: data).wholeSlice

        let scene = try USDCReader().read(from: bytes)
        let result = try SceneImporter(tolerance: .standard).importScene(
            scene,
            named: "minimal_mesh.usdc"
        )

        try assertMinimalMesh(result)
    }

    @Test(.timeLimit(.minutes(1)))
    func usdcReaderExposesCanonicalTypedLayerAPI() throws {
        let data = try usdFixture("minimal_mesh.usdc")
        let bytes = USDByteStorage(data: data).wholeSlice
        let reader = USDCReader()

        let layer = try reader.readSdfLayer(from: bytes)

        #expect(layer.specs.contains { $0.typeName == "Mesh" })
        #expect(layer.specs.contains { $0.path.rawValue.hasSuffix(".faceVertexCounts") })
        #expect(layer.specs.contains { $0.path.rawValue.hasSuffix(".faceVertexIndices") })
    }

    @Test(.timeLimit(.minutes(1)))
    func sceneImporterMaterializesUSDZScene() throws {
        let package = try minimalUSDZPackage()
        let bytes = USDByteStorage(data: package).wholeSlice

        let scene = try USDZReader().read(from: bytes)
        let result = try SceneImporter(tolerance: .standard).importScene(
            scene,
            named: "minimal_mesh.usdz"
        )

        try assertMinimalMesh(result)
    }

    @Test(.timeLimit(.minutes(1)))
    func usdzReaderExposesCanonicalLayerGraphAPI() throws {
        let package = try minimalUSDZPackage()
        let bytes = USDByteStorage(data: package).wholeSlice

        let graph = try USDZReader().readLayerGraph(from: bytes)

        #expect(graph.rootPath == "scene.usdc")
        #expect(graph.paths == ["scene.usdc"])
        #expect(graph.layers.first?.hasScene == true)
    }

    @Test(.timeLimit(.minutes(1)))
    func sceneImporterPreservesTypedUnsupportedFeatureDiagnostic() throws {
        let scene = USDScene(meshes: [
            USDMesh(
                points: [
                    USDPoint3D(x: 0, y: 0, z: 0),
                    USDPoint3D(x: 1, y: 0, z: 0),
                    USDPoint3D(x: 0, y: 1, z: 0),
                ],
                faceVertexCounts: [3],
                faceVertexIndices: [0, 1, 2],
                subdivisionScheme: "catmullClark"
            ),
        ])

        do {
            _ = try SceneImporter(tolerance: .standard).importScene(scene)
            Issue.record("Unsupported subdivision must return a typed diagnostic.")
        } catch let error as ImportError {
            #expect(error == .unsupportedFeature(
                "subdivisionScheme catmullClark requires subdivision tessellation."
            ))
        }
    }
}

private func assertMinimalMesh(_ result: ImportResult) throws {
    #expect(result.units == .meters)
    #expect(result.meshes.count == 1)
    let mesh = try #require(result.meshes.values.first)
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

private func minimalUSDZPackage() throws -> Data {
    try makeAlignedUSDZ(entries: [
        (path: "scene.usdc", data: usdFixture("minimal_mesh.usdc")),
    ])
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

private enum CRC32 {
    private static let table: [UInt32] = (0..<256).map { value in
        var crc = UInt32(value)
        for _ in 0..<8 {
            if crc & 1 == 0 {
                crc >>= 1
            } else {
                crc = (crc >> 1) ^ 0xedb8_8320
            }
        }
        return crc
    }

    static func checksum(_ data: Data) -> UInt32 {
        var crc = UInt32.max
        for byte in data {
            let index = Int((crc ^ UInt32(byte)) & 0xff)
            crc = (crc >> 8) ^ table[index]
        }
        return crc ^ UInt32.max
    }
}

private extension Data {
    mutating func appendLittleEndian<T: FixedWidthInteger>(_ value: T) {
        var littleEndian = value.littleEndian
        Swift.withUnsafeBytes(of: &littleEndian) { bytes in
            append(contentsOf: bytes)
        }
    }
}
