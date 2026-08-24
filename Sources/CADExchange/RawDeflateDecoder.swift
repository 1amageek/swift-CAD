import Foundation

enum RawDeflateError: Error, Equatable, Sendable {
    case invalidStream
    case outputLimitExceeded
    case outputSizeMismatch
    case truncatedStream
}

struct RawDeflateDecoder {
    static func decode(
        _ bytes: UnsafeRawBufferPointer,
        expectedByteCount: Int,
        maximumByteCount: Int
    ) throws -> Data {
        guard expectedByteCount >= 0,
              expectedByteCount <= maximumByteCount else {
            throw RawDeflateError.outputLimitExceeded
        }
        var reader = DeflateBitReader(bytes: bytes)
        var output = Data()
        output.reserveCapacity(expectedByteCount)

        var isFinalBlock = false
        while !isFinalBlock {
            isFinalBlock = try reader.readBits(1) == 1
            let blockType = try reader.readBits(2)
            switch blockType {
            case 0:
                try decodeStoredBlock(
                    reader: &reader,
                    output: &output,
                    maximumByteCount: maximumByteCount
                )
            case 1:
                try decodeCompressedBlock(
                    reader: &reader,
                    literalLengthTable: try fixedLiteralLengthTable(),
                    distanceTable: try fixedDistanceTable(),
                    output: &output,
                    maximumByteCount: maximumByteCount
                )
            case 2:
                let tables = try dynamicTables(reader: &reader)
                try decodeCompressedBlock(
                    reader: &reader,
                    literalLengthTable: tables.literalLength,
                    distanceTable: tables.distance,
                    output: &output,
                    maximumByteCount: maximumByteCount
                )
            default:
                throw RawDeflateError.invalidStream
            }
        }

        guard reader.consumedByteCount == bytes.count else {
            throw RawDeflateError.invalidStream
        }
        guard output.count == expectedByteCount else {
            throw RawDeflateError.outputSizeMismatch
        }
        return output
    }

    private static func decodeStoredBlock(
        reader: inout DeflateBitReader,
        output: inout Data,
        maximumByteCount: Int
    ) throws {
        reader.alignToByte()
        let length = try reader.readBits(16)
        let complement = try reader.readBits(16)
        guard UInt16(truncatingIfNeeded: length) ^ UInt16(truncatingIfNeeded: complement) == UInt16.max else {
            throw RawDeflateError.invalidStream
        }
        try validateAppendCount(length, outputCount: output.count, maximumByteCount: maximumByteCount)
        for _ in 0..<length {
            output.append(UInt8(try reader.readBits(8)))
        }
    }

    private static func decodeCompressedBlock(
        reader: inout DeflateBitReader,
        literalLengthTable: DeflateHuffmanTable,
        distanceTable: DeflateHuffmanTable?,
        output: inout Data,
        maximumByteCount: Int
    ) throws {
        while true {
            let symbol = try literalLengthTable.decode(reader: &reader)
            switch symbol {
            case 0...255:
                try validateAppendCount(1, outputCount: output.count, maximumByteCount: maximumByteCount)
                output.append(UInt8(symbol))
            case 256:
                return
            case 257...285:
                let lengthIndex = symbol - 257
                let length = deflateLengthBases[lengthIndex]
                    + (try reader.readBits(deflateLengthExtraBits[lengthIndex]))
                guard let distanceTable else {
                    throw RawDeflateError.invalidStream
                }
                let distanceSymbol = try distanceTable.decode(reader: &reader)
                guard distanceSymbol < deflateDistanceBases.count else {
                    throw RawDeflateError.invalidStream
                }
                let distance = deflateDistanceBases[distanceSymbol]
                    + (try reader.readBits(deflateDistanceExtraBits[distanceSymbol]))
                guard distance > 0, distance <= output.count else {
                    throw RawDeflateError.invalidStream
                }
                try validateAppendCount(length, outputCount: output.count, maximumByteCount: maximumByteCount)
                for _ in 0..<length {
                    output.append(output[output.count - distance])
                }
            default:
                throw RawDeflateError.invalidStream
            }
        }
    }

    private static func dynamicTables(
        reader: inout DeflateBitReader
    ) throws -> (literalLength: DeflateHuffmanTable, distance: DeflateHuffmanTable?) {
        let literalLengthCount = 257 + (try reader.readBits(5))
        let distanceCount = 1 + (try reader.readBits(5))
        let codeLengthCount = 4 + (try reader.readBits(4))
        guard literalLengthCount <= 286, distanceCount <= 32 else {
            throw RawDeflateError.invalidStream
        }

        var codeLengths = Array(repeating: 0, count: 19)
        for index in 0..<codeLengthCount {
            codeLengths[deflateCodeLengthOrder[index]] = try reader.readBits(3)
        }
        let codeLengthTable = try DeflateHuffmanTable(codeLengths: codeLengths)
        let totalCount = literalLengthCount + distanceCount
        var lengths: [Int] = []
        lengths.reserveCapacity(totalCount)
        while lengths.count < totalCount {
            let symbol = try codeLengthTable.decode(reader: &reader)
            switch symbol {
            case 0...15:
                lengths.append(symbol)
            case 16:
                guard let previous = lengths.last else {
                    throw RawDeflateError.invalidStream
                }
                let repeatCount = 3 + (try reader.readBits(2))
                try appendRepeated(previous, count: repeatCount, totalCount: totalCount, to: &lengths)
            case 17:
                let repeatCount = 3 + (try reader.readBits(3))
                try appendRepeated(0, count: repeatCount, totalCount: totalCount, to: &lengths)
            case 18:
                let repeatCount = 11 + (try reader.readBits(7))
                try appendRepeated(0, count: repeatCount, totalCount: totalCount, to: &lengths)
            default:
                throw RawDeflateError.invalidStream
            }
        }

        let literalLengths = Array(lengths[..<literalLengthCount])
        guard literalLengths[256] != 0 else {
            throw RawDeflateError.invalidStream
        }
        let distanceLengths = Array(lengths[literalLengthCount...])
        let distanceTable = distanceLengths.allSatisfy { $0 == 0 }
            ? nil
            : try DeflateHuffmanTable(codeLengths: distanceLengths)
        return (
            literalLength: try DeflateHuffmanTable(codeLengths: literalLengths),
            distance: distanceTable
        )
    }

    private static func appendRepeated(
        _ value: Int,
        count: Int,
        totalCount: Int,
        to lengths: inout [Int]
    ) throws {
        guard count >= 0, lengths.count <= totalCount - count else {
            throw RawDeflateError.invalidStream
        }
        lengths.append(contentsOf: repeatElement(value, count: count))
    }

    private static func fixedLiteralLengthTable() throws -> DeflateHuffmanTable {
        var lengths = Array(repeating: 0, count: 288)
        for symbol in 0...143 { lengths[symbol] = 8 }
        for symbol in 144...255 { lengths[symbol] = 9 }
        for symbol in 256...279 { lengths[symbol] = 7 }
        for symbol in 280...287 { lengths[symbol] = 8 }
        return try DeflateHuffmanTable(codeLengths: lengths)
    }

    private static func fixedDistanceTable() throws -> DeflateHuffmanTable {
        try DeflateHuffmanTable(codeLengths: Array(repeating: 5, count: 32))
    }

    private static func validateAppendCount(
        _ appendCount: Int,
        outputCount: Int,
        maximumByteCount: Int
    ) throws {
        guard appendCount >= 0,
              outputCount <= maximumByteCount - appendCount else {
            throw RawDeflateError.outputLimitExceeded
        }
    }
}

private struct DeflateBitReader {
    let bytes: UnsafeRawBufferPointer
    private(set) var bitOffset = 0

    var consumedByteCount: Int {
        (bitOffset + 7) / 8
    }

    mutating func readBits(_ count: Int) throws -> Int {
        guard count >= 0, count <= 16 else {
            throw RawDeflateError.invalidStream
        }
        var value = 0
        for bitIndex in 0..<count {
            let byteIndex = bitOffset / 8
            guard byteIndex < bytes.count else {
                throw RawDeflateError.truncatedStream
            }
            let sourceBit = (bytes[byteIndex] >> UInt8(bitOffset % 8)) & 1
            value |= Int(sourceBit) << bitIndex
            bitOffset += 1
        }
        return value
    }

    mutating func alignToByte() {
        bitOffset = (bitOffset + 7) & ~7
    }
}

private struct DeflateHuffmanTable {
    private let symbolsByLengthAndCode: [[Int: Int]]
    private let maximumCodeLength: Int

    init(codeLengths: [Int]) throws {
        let maximumCodeLength = codeLengths.max() ?? 0
        guard maximumCodeLength > 0, maximumCodeLength <= 15 else {
            throw RawDeflateError.invalidStream
        }
        var counts = Array(repeating: 0, count: maximumCodeLength + 1)
        for length in codeLengths {
            guard length >= 0, length <= maximumCodeLength else {
                throw RawDeflateError.invalidStream
            }
            if length > 0 {
                counts[length] += 1
            }
        }
        var remainingCodeSpace = 1
        for length in 1...maximumCodeLength {
            remainingCodeSpace = remainingCodeSpace * 2 - counts[length]
            guard remainingCodeSpace >= 0 else {
                throw RawDeflateError.invalidStream
            }
        }

        var nextCode = Array(repeating: 0, count: maximumCodeLength + 1)
        var code = 0
        if maximumCodeLength > 1 {
            for length in 1...maximumCodeLength {
                code = (code + counts[length - 1]) << 1
                nextCode[length] = code
            }
        } else {
            nextCode[1] = 0
        }
        var mappings = Array(repeating: [Int: Int](), count: maximumCodeLength + 1)
        for (symbol, length) in codeLengths.enumerated() where length > 0 {
            let canonicalCode = nextCode[length]
            nextCode[length] += 1
            let transmittedCode = reverseBits(canonicalCode, count: length)
            guard mappings[length].updateValue(symbol, forKey: transmittedCode) == nil else {
                throw RawDeflateError.invalidStream
            }
        }
        symbolsByLengthAndCode = mappings
        self.maximumCodeLength = maximumCodeLength
    }

    func decode(reader: inout DeflateBitReader) throws -> Int {
        var code = 0
        for length in 1...maximumCodeLength {
            code |= try reader.readBits(1) << (length - 1)
            if let symbol = symbolsByLengthAndCode[length][code] {
                return symbol
            }
        }
        throw RawDeflateError.invalidStream
    }
}

private func reverseBits(_ value: Int, count: Int) -> Int {
    var source = value
    var reversed = 0
    for _ in 0..<count {
        reversed = (reversed << 1) | (source & 1)
        source >>= 1
    }
    return reversed
}

private let deflateCodeLengthOrder = [
    16, 17, 18, 0, 8, 7, 9, 6, 10, 5, 11, 4, 12, 3, 13, 2, 14, 1, 15,
]

private let deflateLengthBases = [
    3, 4, 5, 6, 7, 8, 9, 10,
    11, 13, 15, 17,
    19, 23, 27, 31,
    35, 43, 51, 59,
    67, 83, 99, 115,
    131, 163, 195, 227,
    258,
]

private let deflateLengthExtraBits = [
    0, 0, 0, 0, 0, 0, 0, 0,
    1, 1, 1, 1,
    2, 2, 2, 2,
    3, 3, 3, 3,
    4, 4, 4, 4,
    5, 5, 5, 5,
    0,
]

private let deflateDistanceBases = [
    1, 2, 3, 4,
    5, 7,
    9, 13,
    17, 25,
    33, 49,
    65, 97,
    129, 193,
    257, 385,
    513, 769,
    1_025, 1_537,
    2_049, 3_073,
    4_097, 6_145,
    8_193, 12_289,
    16_385, 24_577,
]

private let deflateDistanceExtraBits = [
    0, 0, 0, 0,
    1, 1,
    2, 2,
    3, 3,
    4, 4,
    5, 5,
    6, 6,
    7, 7,
    8, 8,
    9, 9,
    10, 10,
    11, 11,
    12, 12,
    13, 13,
]
