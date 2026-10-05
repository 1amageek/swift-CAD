import Foundation

struct CRC32 {
    private static let table: [UInt32] = (0..<256).map { value in
        var crc = UInt32(value)
        for _ in 0..<8 {
            if crc & 1 == 1 {
                crc = (crc >> 1) ^ 0xedb88320
            } else {
                crc >>= 1
            }
        }
        return crc
    }

    static func checksum(_ data: Data) -> UInt32 {
        var checksum = CRC32()
        checksum.update(data)
        return checksum.finalize()
    }


    static func checksum(_ data: Data, consumeWork: @Sendable (Int) throws -> Void) throws -> UInt32 {
        var checksum = CRC32()
        for byte in data { try consumeWork(1); checksum.update(byte) }
        return checksum.finalize()
    }

    mutating func update(_ bytes: UnsafeRawBufferPointer, consumeWork: @Sendable (Int) throws -> Void) throws {
        // The borrowed input remains owned by ByteSink.write for this entire loop.
        // The callback never retains the pointer; admission precedes each byte visit.
        for byte in bytes { try consumeWork(1); update(byte) }
    }

    private var crc: UInt32 = 0xffffffff

    init() {}

    mutating func update(_ data: Data) {
        for byte in data {
            update(byte)
        }
    }

    mutating func update(_ bytes: UnsafeRawBufferPointer) {
        for byte in bytes {
            update(byte)
        }
    }

    mutating func update(_ byte: UInt8) {
        crc = (crc >> 8) ^ Self.table[Int((crc ^ UInt32(byte)) & 0xff)]
    }

    func finalize() -> UInt32 {
        crc ^ 0xffffffff
    }
}
