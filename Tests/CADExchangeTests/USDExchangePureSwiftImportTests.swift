import Foundation
import Testing
import CADCore
import CADIR
@testable import CADExchange

@Suite("USD Exchange Pure Swift Import")
struct USDExchangePureSwiftImportTests {
    @Test(.timeLimit(.minutes(1)))
    func pureSwiftUSDCImportMaterializesMeshExchangeModelWhenTraitEnabled() throws {
        let exchange = USDExchange(importMode: .pureSwift)
        let data = try usdFixture("minimal_mesh.usdc")

        #if CAD_ENABLE_BINARY_USD_IMPORT
        let model = try exchange.import(BorrowedBytes(data), as: .usdc)

        try assertMinimalMeshExchangeModel(model, format: .usdc)
        #else
        expectUnsupportedUSDImport(.unsupportedFormat("USDC")) {
            _ = try exchange.import(BorrowedBytes(data), as: .usdc)
        }
        #endif
    }

    @Test(.timeLimit(.minutes(1)))
    func pureSwiftBinaryUSDImportMaterializesMeshExchangeModelWhenTraitEnabled() throws {
        let exchange = USDExchange(importMode: .pureSwift)
        let data = try usdFixture("minimal_mesh.usdc")

        #if CAD_ENABLE_BINARY_USD_IMPORT
        let model = try exchange.import(BorrowedBytes(data), as: .usd)

        try assertMinimalMeshExchangeModel(model, format: .usd)
        #else
        expectUnsupportedUSDImport(.unsupportedFormat("USDC")) {
            _ = try exchange.import(BorrowedBytes(data), as: .usd)
        }
        #endif
    }

    @Test(.timeLimit(.minutes(1)))
    func pureSwiftUSDZImportMaterializesMeshExchangeModelWhenTraitEnabled() throws {
        let exchange = USDExchange(importMode: .pureSwift)
        let package = try makeAlignedUSDZ(entries: [
            (path: "scene.usdc", data: usdFixture("minimal_mesh.usdc")),
        ])

        #if CAD_ENABLE_USDZ_PACKAGE_IMPORT
        let model = try exchange.import(BorrowedBytes(package), as: .usdz)

        try assertMinimalMeshExchangeModel(model, format: .usdz)
        #else
        expectUnsupportedUSDImport(.unsupportedFormat("USDZ")) {
            _ = try exchange.import(BorrowedBytes(package), as: .usdz)
        }
        #endif
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

private func expectUnsupportedUSDImport(_ expectedError: ImportError, _ body: () throws -> Void) {
    do {
        try body()
        Issue.record("Expected \(expectedError).")
    } catch let error as ImportError {
        #expect(error == expectedError)
    } catch {
        Issue.record("Expected \(expectedError), got \(error).")
    }
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
