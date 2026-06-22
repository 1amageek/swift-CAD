import Foundation
import Testing
import CADCore
import CADIR
import CADUSD
import CADUSDC
import CADUSDZ
import OpenUSD

@Suite("CAD USD Import Modules")
struct CADUSDImportTests {
    @Test(.timeLimit(.minutes(1)))
    func usdcMeshImporterMaterializesMinimalMesh() throws {
        let data = try usdFixture("minimal_mesh.usdc")

        let result = try USDCMeshImporter().importMeshes(from: data, named: "minimal_mesh.usdc")

        try assertMinimalMesh(result)
    }

    @Test(.timeLimit(.minutes(1)))
    func usdcSceneReaderExposesLayerAndSceneReadAPIs() throws {
        let data = try usdFixture("minimal_mesh.usdc")
        let reader = USDCSceneReader()

        let layer = try reader.readLayer(from: data)
        let scene = try reader.read(from: data)

        #expect(layer.specs.contains { $0.typeName == "Mesh" })
        let mesh = try #require(scene.meshes.first)
        #expect(mesh.points == [
            USDPoint3D(x: 0, y: 0, z: 0),
            USDPoint3D(x: 1, y: 0, z: 0),
            USDPoint3D(x: 0, y: 1, z: 0),
        ])
        #expect(mesh.faceVertexCounts == [3])
        #expect(mesh.faceVertexIndices == [0, 1, 2])
    }

    @Test(.timeLimit(.minutes(1)))
    func usdzMeshImporterMaterializesMinimalMeshPackage() throws {
        let package = try minimalUSDZPackage()

        let result = try USDZMeshImporter().importMeshes(from: package, named: "minimal_mesh.usdz")

        try assertMinimalMesh(result)
    }

    @Test(.timeLimit(.minutes(1)))
    func usdzPackageReaderExposesLayerGraphAPI() throws {
        let package = try minimalUSDZPackage()

        let graph = try USDZPackageReader().readLayerGraph(from: package)

        #expect(graph.rootPath == "scene.usdc")
        #expect(graph.paths == ["scene.usdc"])
        #expect(graph.layers.first?.hasScene == true)
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
