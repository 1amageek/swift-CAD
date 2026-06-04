import Foundation
import CADUSD

enum USDCIntegerCompression {
    static func decompressUInt32(_ bytes: [UInt8], count: Int) throws -> [UInt32] {
        guard count >= 0 else {
            throw USDImportError.invalidData("USDC compressed integer count is invalid.")
        }
        guard count > 0 else {
            if bytes.isEmpty {
                return []
            }
            let output = try USDCFastCompression.decompress(bytes, maximumOutputByteCount: 0)
            guard output.isEmpty else {
                throw USDImportError.invalidData("USDC compressed integer buffer produced data for an empty vector.")
            }
            return []
        }

        guard !bytes.isEmpty else {
            throw USDImportError.invalidData("USDC compressed integer buffer is empty.")
        }
        guard count <= (Int.max - MemoryLayout<Int32>.size) / 5 else {
            throw USDImportError.invalidData("USDC compressed integer count exceeds platform range.")
        }

        let maximumOutputByteCount = encodedBufferSize(forIntegerCount: count)
        let encoded = try USDCFastCompression.decompress(
            bytes,
            maximumOutputByteCount: maximumOutputByteCount
        )
        return try decodeUInt32(encoded, count: count)
    }

    private static func encodedBufferSize(forIntegerCount count: Int) -> Int {
        MemoryLayout<Int32>.size
            + ((count * 2 + 7) / 8)
            + (count * MemoryLayout<Int32>.size)
    }

    private static func decodeUInt32(_ bytes: [UInt8], count: Int) throws -> [UInt32] {
        var cursor = 0
        let commonValue = try readInt32(from: bytes, cursor: &cursor)
        let codeByteCount = (count * 2 + 7) / 8
        guard cursor <= bytes.count - codeByteCount else {
            throw USDImportError.invalidData("USDC integer code table is truncated.")
        }
        let codesStart = cursor
        cursor += codeByteCount
        var valueCursor = cursor
        var previousValue = Int32(0)
        var output: [UInt32] = []
        output.reserveCapacity(count)

        for index in 0..<count {
            let codeByte = bytes[codesStart + index / 4]
            let code = (codeByte >> UInt8((index % 4) * 2)) & 0x03
            let delta: Int32
            switch code {
            case 0:
                delta = commonValue
            case 1:
                delta = Int32(try readInt8(from: bytes, cursor: &valueCursor))
            case 2:
                delta = Int32(try readInt16(from: bytes, cursor: &valueCursor))
            case 3:
                delta = try readInt32(from: bytes, cursor: &valueCursor)
            default:
                throw USDImportError.invalidData("USDC integer code is invalid.")
            }
            previousValue = previousValue &+ delta
            output.append(UInt32(bitPattern: previousValue))
        }

        guard valueCursor <= bytes.count else {
            throw USDImportError.invalidData("USDC integer value stream is truncated.")
        }
        return output
    }

    private static func readInt8(from bytes: [UInt8], cursor: inout Int) throws -> Int8 {
        guard cursor < bytes.count else {
            throw USDImportError.invalidData("USDC integer value stream is truncated.")
        }
        defer {
            cursor += 1
        }
        return Int8(bitPattern: bytes[cursor])
    }

    private static func readInt16(from bytes: [UInt8], cursor: inout Int) throws -> Int16 {
        let value: UInt16 = try readLittleEndianInteger(from: bytes, cursor: &cursor)
        return Int16(bitPattern: value)
    }

    private static func readInt32(from bytes: [UInt8], cursor: inout Int) throws -> Int32 {
        let value: UInt32 = try readLittleEndianInteger(from: bytes, cursor: &cursor)
        return Int32(bitPattern: value)
    }

    private static func readLittleEndianInteger<T: FixedWidthInteger>(
        from bytes: [UInt8],
        cursor: inout Int
    ) throws -> T {
        let byteCount = MemoryLayout<T>.size
        guard cursor <= bytes.count - byteCount else {
            throw USDImportError.invalidData("USDC integer value stream is truncated.")
        }
        var value: T = 0
        for offset in 0..<byteCount {
            value |= T(bytes[cursor + offset]) << T(offset * 8)
        }
        cursor += byteCount
        return value
    }
}
