import CADUSD
import Foundation

struct USDCCrateValueDecoder {
    private let crate: USDCCrateFile
    private let tokens: [String]
    private let strings: [String]

    init(crate: USDCCrateFile, tokens: [String], strings: [String]) {
        self.crate = crate
        self.tokens = tokens
        self.strings = strings
    }

    func readStringLike(_ valueRep: USDCCrateValueRep) throws -> String {
        let value = try readValue(valueRep)
        guard let string = value.stringValue else {
            throw USDImportError.invalidData("USDC value is not a string-like value.")
        }
        return string
    }

    func readDouble(_ valueRep: USDCCrateValueRep) throws -> Double {
        let value = try readValue(valueRep)
        guard let double = value.doubleValue else {
            throw USDImportError.invalidData("USDC value is not a double value.")
        }
        return double
    }

    func readIntArray(_ valueRep: USDCCrateValueRep) throws -> [Int] {
        let value = try readValue(valueRep)
        guard let array = value.intArrayValue else {
            throw USDImportError.invalidData("USDC value is not an int array.")
        }
        return array
    }

    func readPointArray(_ valueRep: USDCCrateValueRep) throws -> [USDPoint3D] {
        let value = try readValue(valueRep)
        guard let array = value.pointArrayValue else {
            throw USDImportError.invalidData("USDC value is not a point array.")
        }
        return array
    }

    private func readValue(_ valueRep: USDCCrateValueRep) throws -> USDCCrateValue {
        guard let type = valueRep.type else {
            throw USDImportError.invalidData("USDC value has an unknown value type.")
        }
        switch type {
        case .token:
            return .token(try readToken(valueRep))
        case .string:
            return .string(try readString(valueRep))
        case .double:
            return .double(try readDoubleScalar(valueRep))
        case .int:
            guard valueRep.isArray else {
                throw USDImportError.unsupportedFeature("USDC scalar int values are not materialized yet.")
            }
            return .intArray(try readIntArrayValue(valueRep))
        case .vec3f:
            guard valueRep.isArray else {
                throw USDImportError.unsupportedFeature("USDC scalar vec3f values are not materialized yet.")
            }
            return .pointArray(try readVec3fArrayValue(valueRep))
        default:
            throw USDImportError.unsupportedFeature("USDC value type \(type) is not materialized yet.")
        }
    }

    private func readToken(_ valueRep: USDCCrateValueRep) throws -> String {
        let tokenIndex = try readIndexPayload(valueRep, sectionName: "TOKENS")
        guard tokenIndex < tokens.count else {
            throw USDImportError.invalidData("USDC token value references a token outside TOKENS.")
        }
        return tokens[tokenIndex]
    }

    private func readString(_ valueRep: USDCCrateValueRep) throws -> String {
        let stringIndex = try readIndexPayload(valueRep, sectionName: "STRINGS")
        guard stringIndex < strings.count else {
            throw USDImportError.invalidData("USDC string value references a string outside STRINGS.")
        }
        return strings[stringIndex]
    }

    private func readIndexPayload(_ valueRep: USDCCrateValueRep, sectionName: String) throws -> Int {
        let rawIndex: UInt32
        if valueRep.isInlined {
            rawIndex = UInt32(valueRep.payload & UInt64(UInt32.max))
        } else {
            rawIndex = try crate.readFileUInt32(at: try payloadOffset(valueRep, label: sectionName))
        }
        guard let index = Int(exactly: rawIndex) else {
            throw USDImportError.invalidData("USDC \(sectionName) value index exceeds platform range.")
        }
        return index
    }

    private func readDoubleScalar(_ valueRep: USDCCrateValueRep) throws -> Double {
        if valueRep.isInlined {
            let floatBits = UInt32(valueRep.payload & UInt64(UInt32.max))
            return Double(Float32(bitPattern: floatBits))
        }
        let bytes = try crate.readFileBytes(
            at: try payloadOffset(valueRep, label: "double"),
            byteCount: MemoryLayout<UInt64>.size
        )
        let bits = littleEndianUInt64(bytes)
        return Double(bitPattern: bits)
    }

    private func readIntArrayValue(_ valueRep: USDCCrateValueRep) throws -> [Int] {
        guard valueRep.isArray else {
            throw USDImportError.invalidData("USDC int array value is missing the array bit.")
        }
        guard valueRep.payload != 0 else {
            return []
        }
        var cursor = try payloadOffset(valueRep, label: "int array")
        if crate.version < USDCCrateVersion(major: 0, minor: 5, patch: 0) {
            let shapeRank = try crate.readFileUInt32(at: cursor)
            cursor += MemoryLayout<UInt32>.size
            guard shapeRank == 1 else {
                throw USDImportError.unsupportedFeature("Only one-dimensional USDC int arrays are supported.")
            }
        }
        let count = try readArrayCount(cursor: &cursor, label: "USDC int array count")
        guard count <= Int.max / MemoryLayout<Int32>.size else {
            throw USDImportError.invalidData("USDC int array byte count exceeds platform range.")
        }
        if valueRep.isCompressed {
            guard crate.version >= USDCCrateVersion(major: 0, minor: 5, patch: 0) else {
                throw USDImportError.invalidData("USDC int array is marked compressed before compression support.")
            }
            let compressedByteCount = try checkedInt(
                UInt64(try crate.readFileUInt64(at: cursor)),
                label: "USDC compressed int array byte count"
            )
            cursor += MemoryLayout<UInt64>.size
            let compressedBytes = try crate.readFileBytes(at: cursor, byteCount: compressedByteCount)
            return try USDCIntegerCompression.decompressUInt32(compressedBytes, count: count).map {
                Int(Int32(bitPattern: $0))
            }
        }
        let byteCount = count * MemoryLayout<Int32>.size
        let bytes = try crate.readFileBytes(at: cursor, byteCount: byteCount)
        var values: [Int] = []
        values.reserveCapacity(count)
        var byteCursor = 0
        for _ in 0..<count {
            values.append(Int(littleEndianInt32(bytes[byteCursor..<(byteCursor + 4)])))
            byteCursor += MemoryLayout<Int32>.size
        }
        return values
    }

    private func readVec3fArrayValue(_ valueRep: USDCCrateValueRep) throws -> [USDPoint3D] {
        guard valueRep.isArray else {
            throw USDImportError.invalidData("USDC vec3f array value is missing the array bit.")
        }
        guard !valueRep.isCompressed else {
            throw USDImportError.unsupportedFeature("Compressed USDC vec3f arrays are not supported.")
        }
        guard valueRep.payload != 0 else {
            return []
        }
        var cursor = try payloadOffset(valueRep, label: "vec3f array")
        if crate.version < USDCCrateVersion(major: 0, minor: 5, patch: 0) {
            let shapeRank = try crate.readFileUInt32(at: cursor)
            cursor += MemoryLayout<UInt32>.size
            guard shapeRank == 1 else {
                throw USDImportError.unsupportedFeature("Only one-dimensional USDC vec3f arrays are supported.")
            }
        }
        let count = try readArrayCount(cursor: &cursor, label: "USDC vec3f array count")
        let scalarCount = try checkedMultiplication(count, 3, label: "USDC vec3f scalar count")
        let byteCount = try checkedMultiplication(scalarCount, MemoryLayout<Float32>.size, label: "USDC vec3f array byte count")
        let bytes = try crate.readFileBytes(at: cursor, byteCount: byteCount)
        var points: [USDPoint3D] = []
        points.reserveCapacity(count)
        var byteCursor = 0
        for _ in 0..<count {
            let x = Double(littleEndianFloat32(bytes[byteCursor..<(byteCursor + 4)]))
            byteCursor += MemoryLayout<Float32>.size
            let y = Double(littleEndianFloat32(bytes[byteCursor..<(byteCursor + 4)]))
            byteCursor += MemoryLayout<Float32>.size
            let z = Double(littleEndianFloat32(bytes[byteCursor..<(byteCursor + 4)]))
            byteCursor += MemoryLayout<Float32>.size
            guard x.isFinite, y.isFinite, z.isFinite else {
                throw USDImportError.invalidData("USDC vec3f array contains a non-finite point.")
            }
            points.append(USDPoint3D(x: x, y: y, z: z))
        }
        return points
    }

    private func readArrayCount(cursor: inout Int, label: String) throws -> Int {
        if crate.version < USDCCrateVersion(major: 0, minor: 7, patch: 0) {
            let count = try crate.readFileUInt32(at: cursor)
            cursor += MemoryLayout<UInt32>.size
            return Int(count)
        }
        let count = try checkedInt(try crate.readFileUInt64(at: cursor), label: label)
        cursor += MemoryLayout<UInt64>.size
        return count
    }

    private func payloadOffset(_ valueRep: USDCCrateValueRep, label: String) throws -> Int {
        try checkedInt(valueRep.payload, label: "USDC \(label) payload offset")
    }

    private func checkedInt(_ value: UInt64, label: String) throws -> Int {
        guard value <= UInt64(Int.max) else {
            throw USDImportError.invalidData("\(label) exceeds platform range.")
        }
        return Int(value)
    }

    private func checkedMultiplication(_ lhs: Int, _ rhs: Int, label: String) throws -> Int {
        guard lhs >= 0, rhs >= 0, lhs <= Int.max / rhs else {
            throw USDImportError.invalidData("\(label) exceeds platform range.")
        }
        return lhs * rhs
    }

    private func littleEndianUInt64(_ bytes: [UInt8]) -> UInt64 {
        bytes.enumerated().reduce(UInt64(0)) { result, element in
            result | (UInt64(element.element) << UInt64(element.offset * 8))
        }
    }

    private func littleEndianInt32(_ bytes: ArraySlice<UInt8>) -> Int32 {
        Int32(bitPattern: littleEndianUInt32(bytes))
    }

    private func littleEndianFloat32(_ bytes: ArraySlice<UInt8>) -> Float32 {
        Float32(bitPattern: littleEndianUInt32(bytes))
    }

    private func littleEndianUInt32(_ bytes: ArraySlice<UInt8>) -> UInt32 {
        bytes.enumerated().reduce(UInt32(0)) { result, element in
            result | (UInt32(element.element) << UInt32(element.offset * 8))
        }
    }
}
