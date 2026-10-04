import Foundation
import Testing
import CADExchange

struct MainWASIDefaultTests {
    @Test(.timeLimit(.minutes(1)))
    func defaultPublicReadReproducesLiteralPayload() throws {
        let payload = Data([0x51, 0x52])
        let archive = try StoredZipArchive.make(entries: [
            StoredZipArchive.Entry(path: "a", data: payload)])
        #expect(try StoredZipArchive.readEntries(from: archive) == ["a": payload])
    }

    @Test(.timeLimit(.minutes(1)))
    func defaultPublicReadRefusesMalformedHeader() {
        #expect(throws: ZipArchiveError.missingEndOfCentralDirectory) {
            _ = try StoredZipArchive.readEntries(from: Data([0x50, 0x4b, 0x03]))
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func defaultPublicReadRefusesOversizedRecordWithoutPayloadAllocation() throws {
        var archive = try StoredZipArchive.make(entries: [
            StoredZipArchive.Entry(path: "a", data: Data([0x51, 0x52]))])
        let footer = archive.count - 22
        var centralOffset: UInt32 = 0
        for index in 0..<4 {
            centralOffset |= UInt32(archive[footer + 16 + index]) << (index * 8)
        }
        let recordedSize: UInt32 = UInt64(Int.max) < UInt64(UInt32.max)
            ? 0x80000000 : UInt32.max
        for field in [20, 24] {
            for index in 0..<4 {
                archive[Int(centralOffset) + field + index] =
                    UInt8(truncatingIfNeeded: recordedSize >> (index * 8))
            }
        }
        let expected: ZipArchiveError = UInt64(Int.max) < UInt64(UInt32.max)
            ? .invalidCentralDirectory : .entryTooLarge("ZIP64")
        #expect(throws: expected) { _ = try StoredZipArchive.readEntries(from: archive) }
    }
}
