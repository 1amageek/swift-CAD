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

    func readDoubleArray(_ valueRep: USDCCrateValueRep) throws -> [Double] {
        let value = try readValue(valueRep)
        guard let array = value.doubleArrayValue else {
            throw USDImportError.invalidData("USDC value is not a double array.")
        }
        return array
    }

    func readTokenArray(_ valueRep: USDCCrateValueRep) throws -> [String] {
        let value = try readValue(valueRep)
        guard let array = value.tokenArrayValue else {
            throw USDImportError.invalidData("USDC value is not a token array.")
        }
        return array
    }

    func readVector3(_ valueRep: USDCCrateValueRep) throws -> USDCVector3D {
        let value = try readValue(valueRep)
        guard let vector = value.vector3Value else {
            throw USDImportError.invalidData("USDC value is not a vector3 value.")
        }
        return vector
    }

    func readQuaternion(_ valueRep: USDCCrateValueRep) throws -> USDCQuaternion {
        let value = try readValue(valueRep)
        guard let quaternion = value.quaternionValue else {
            throw USDImportError.invalidData("USDC value is not a quaternion value.")
        }
        return quaternion
    }

    func readMatrix4x4(_ valueRep: USDCCrateValueRep) throws -> USDCMatrix4x4 {
        let value = try readValue(valueRep)
        guard let matrix = value.matrix4x4Value else {
            throw USDImportError.invalidData("USDC value is not a matrix4d value.")
        }
        return matrix
    }

    func readFirstUnblockedTimeSampleValueRep(_ valueRep: USDCCrateValueRep) throws -> USDCCrateValueRep? {
        guard valueRep.type == .timeSamples, !valueRep.isArray, !valueRep.isInlined else {
            throw USDImportError.invalidData("USDC timeSamples field is malformed.")
        }
        var cursor = try payloadOffset(valueRep, label: "timeSamples")
        cursor = try recursivePayloadEnd(start: cursor, label: "USDC timeSamples times")
        let timesRep = USDCCrateValueRep(rawValue: try crate.readFileUInt64(at: cursor))
        cursor += MemoryLayout<UInt64>.size
        cursor = try recursivePayloadEnd(start: cursor, label: "USDC timeSamples values")
        let valueCount = try checkedInt(
            try crate.readFileUInt64(at: cursor),
            label: "USDC timeSamples value count"
        )
        cursor += MemoryLayout<UInt64>.size
        guard valueCount > 0 else {
            throw USDImportError.invalidData("USDC timeSamples contains no values.")
        }
        let timeCount = try readDoubleVectorCount(timesRep)
        guard timeCount == valueCount else {
            throw USDImportError.invalidData("USDC timeSamples times and values have different counts.")
        }
        for index in 0..<valueCount {
            let sampleCursor = cursor + index * MemoryLayout<UInt64>.size
            let sampleRep = USDCCrateValueRep(rawValue: try crate.readFileUInt64(at: sampleCursor))
            if !isBlockedValue(sampleRep) {
                return sampleRep
            }
        }
        return nil
    }

    func isBlockedValue(_ valueRep: USDCCrateValueRep) -> Bool {
        isValueBlock(valueRep) || isAnimationBlock(valueRep)
    }

    func isValueBlock(_ valueRep: USDCCrateValueRep) -> Bool {
        valueRep.type == .valueBlock
    }

    func isAnimationBlock(_ valueRep: USDCCrateValueRep) -> Bool {
        valueRep.type == .animationBlock
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

    func readPoint2Array(_ valueRep: USDCCrateValueRep) throws -> [USDPoint2D] {
        let value = try readValue(valueRep)
        guard let array = value.point2ArrayValue else {
            throw USDImportError.invalidData("USDC value is not a point2 array.")
        }
        return array
    }

    private func readValue(_ valueRep: USDCCrateValueRep) throws -> USDCCrateValue {
        guard let type = valueRep.type else {
            throw USDImportError.invalidData("USDC value has an unknown value type.")
        }
        switch type {
        case .token:
            if valueRep.isArray {
                return .tokenArray(try readTokenArrayValue(valueRep))
            }
            return .token(try readToken(valueRep))
        case .string:
            return .string(try readString(valueRep))
        case .float:
            if valueRep.isArray {
                return .doubleArray(try readFloatArrayValue(valueRep))
            }
            return .double(Double(try readFloatScalar(valueRep)))
        case .double:
            if valueRep.isArray {
                return .doubleArray(try readDoubleArrayValue(valueRep))
            }
            return .double(try readDoubleScalar(valueRep))
        case .int:
            guard valueRep.isArray else {
                throw USDImportError.unsupportedFeature("USDC scalar int values are not materialized yet.")
            }
            return .intArray(try readIntArrayValue(valueRep))
        case .quatd:
            guard !valueRep.isArray else {
                throw USDImportError.unsupportedFeature("USDC quatd arrays are not materialized yet.")
            }
            return .quaternion(try readQuatdScalar(valueRep))
        case .quatf:
            guard !valueRep.isArray else {
                throw USDImportError.unsupportedFeature("USDC quatf arrays are not materialized yet.")
            }
            return .quaternion(try readQuatfScalar(valueRep))
        case .quath:
            throw USDImportError.unsupportedFeature("USDC quath values are not materialized yet.")
        case .vec3d:
            if valueRep.isArray {
                return .pointArray(try readVec3dArrayValue(valueRep))
            }
            return .vector3(try readVec3dScalar(valueRep))
        case .vec3f:
            if valueRep.isArray {
                return .pointArray(try readVec3fArrayValue(valueRep))
            }
            return .vector3(try readVec3fScalar(valueRep))
        case .vec2d:
            guard valueRep.isArray else {
                throw USDImportError.unsupportedFeature("USDC scalar vec2d values are not materialized yet.")
            }
            return .point2Array(try readVec2dArrayValue(valueRep))
        case .vec2f:
            guard valueRep.isArray else {
                throw USDImportError.unsupportedFeature("USDC scalar vec2f values are not materialized yet.")
            }
            return .point2Array(try readVec2fArrayValue(valueRep))
        case .matrix4d:
            guard !valueRep.isArray else {
                throw USDImportError.unsupportedFeature("USDC matrix4d arrays are not materialized yet.")
            }
            return .matrix4x4(try readMatrix4dScalar(valueRep))
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

    private func readTokenArrayValue(_ valueRep: USDCCrateValueRep) throws -> [String] {
        guard valueRep.isArray else {
            throw USDImportError.invalidData("USDC token array value is missing the array bit.")
        }
        guard valueRep.payload != 0 else {
            return []
        }
        var cursor = try arrayPayloadCursor(valueRep, label: "token array")
        let count = try readArrayCount(cursor: &cursor, label: "USDC token array count")
        let byteCount = try checkedMultiplication(count, MemoryLayout<UInt32>.size, label: "USDC token array byte count")
        let bytes = try arrayBytes(
            valueRep,
            cursor: &cursor,
            byteCount: byteCount,
            label: "token array"
        )
        var values: [String] = []
        values.reserveCapacity(count)
        var byteCursor = 0
        for _ in 0..<count {
            let tokenIndex = littleEndianUInt32(bytes[byteCursor..<(byteCursor + 4)])
            byteCursor += MemoryLayout<UInt32>.size
            guard tokenIndex < UInt32(tokens.count) else {
                throw USDImportError.invalidData("USDC token array references a token outside TOKENS.")
            }
            values.append(tokens[Int(tokenIndex)])
        }
        return values
    }

    private func readFloatScalar(_ valueRep: USDCCrateValueRep) throws -> Float32 {
        guard !valueRep.isArray else {
            throw USDImportError.invalidData("USDC float value is marked as an array.")
        }
        if valueRep.isInlined {
            let bits = UInt32(valueRep.payload & UInt64(UInt32.max))
            return Float32(bitPattern: bits)
        }
        let bytes = try crate.readFileBytes(
            at: try payloadOffset(valueRep, label: "float"),
            byteCount: MemoryLayout<UInt32>.size
        )
        return littleEndianFloat32(bytes[0..<4])
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
        let bits = littleEndianUInt64(bytes[0..<bytes.count])
        return Double(bitPattern: bits)
    }

    private func readVec3fScalar(_ valueRep: USDCCrateValueRep) throws -> USDCVector3D {
        guard !valueRep.isArray else {
            throw USDImportError.invalidData("USDC vec3f value is marked as an array.")
        }
        if valueRep.isInlined {
            return try inlinedVector3(valueRep, scalarName: "vec3f")
        }
        var cursor = try payloadOffset(valueRep, label: "vec3f")
        let vector = try readVector3Float32(cursor: &cursor, label: "USDC vec3f")
        return vector
    }

    private func readVec3dScalar(_ valueRep: USDCCrateValueRep) throws -> USDCVector3D {
        guard !valueRep.isArray else {
            throw USDImportError.invalidData("USDC vec3d value is marked as an array.")
        }
        if valueRep.isInlined {
            return try inlinedVector3(valueRep, scalarName: "vec3d")
        }
        var cursor = try payloadOffset(valueRep, label: "vec3d")
        let vector = try readVector3Float64(cursor: &cursor, label: "USDC vec3d")
        return vector
    }

    private func readQuatfScalar(_ valueRep: USDCCrateValueRep) throws -> USDCQuaternion {
        guard !valueRep.isArray else {
            throw USDImportError.invalidData("USDC quatf value is marked as an array.")
        }
        guard !valueRep.isInlined else {
            throw USDImportError.invalidData("USDC quatf value is unexpectedly inlined.")
        }
        var cursor = try payloadOffset(valueRep, label: "quatf")
        return try readQuaternionFloat32(cursor: &cursor, label: "USDC quatf")
    }

    private func readQuatdScalar(_ valueRep: USDCCrateValueRep) throws -> USDCQuaternion {
        guard !valueRep.isArray else {
            throw USDImportError.invalidData("USDC quatd value is marked as an array.")
        }
        guard !valueRep.isInlined else {
            throw USDImportError.invalidData("USDC quatd value is unexpectedly inlined.")
        }
        var cursor = try payloadOffset(valueRep, label: "quatd")
        return try readQuaternionFloat64(cursor: &cursor, label: "USDC quatd")
    }

    private func readMatrix4dScalar(_ valueRep: USDCCrateValueRep) throws -> USDCMatrix4x4 {
        guard !valueRep.isArray else {
            throw USDImportError.invalidData("USDC matrix4d value is marked as an array.")
        }
        if valueRep.isInlined {
            var values = USDCMatrix4x4.identity.values
            let bytes = inlinedInt8Bytes(valueRep, count: 4)
            for index in 0..<4 {
                values[index * 4 + index] = Double(bytes[index])
            }
            return USDCMatrix4x4(values: values)
        }
        var cursor = try payloadOffset(valueRep, label: "matrix4d")
        var values: [Double] = []
        values.reserveCapacity(16)
        for _ in 0..<16 {
            values.append(try readFloat64(cursor: &cursor, label: "USDC matrix4d component"))
        }
        guard values.allSatisfy(\.isFinite) else {
            throw USDImportError.invalidData("USDC matrix4d contains a non-finite component.")
        }
        return USDCMatrix4x4(values: values)
    }

    private func readDoubleVectorCount(_ valueRep: USDCCrateValueRep) throws -> Int {
        guard valueRep.type == .doubleVector, !valueRep.isArray, !valueRep.isInlined else {
            throw USDImportError.invalidData("USDC timeSamples references a malformed doubleVector.")
        }
        let cursor = try payloadOffset(valueRep, label: "doubleVector")
        return try checkedInt(try crate.readFileUInt64(at: cursor), label: "USDC doubleVector count")
    }

    private func recursivePayloadEnd(start: Int, label: String) throws -> Int {
        let rawOffset = try crate.readFileUInt64(at: start)
        guard rawOffset <= UInt64(Int64.max) else {
            throw USDImportError.invalidData("\(label) recursive offset exceeds platform range.")
        }
        let offset = Int64(bitPattern: rawOffset)
        guard offset >= Int64(MemoryLayout<Int64>.size) else {
            throw USDImportError.invalidData("\(label) recursive offset is malformed.")
        }
        let endResult = Int64(start).addingReportingOverflow(offset)
        guard !endResult.overflow, endResult.partialValue >= 0, endResult.partialValue <= Int64(Int.max) else {
            throw USDImportError.invalidData("\(label) recursive offset exceeds platform range.")
        }
        return Int(endResult.partialValue)
    }

    private func readIntArrayValue(_ valueRep: USDCCrateValueRep) throws -> [Int] {
        guard valueRep.isArray else {
            throw USDImportError.invalidData("USDC int array value is missing the array bit.")
        }
        guard valueRep.payload != 0 else {
            return []
        }
        var cursor = try arrayPayloadCursor(valueRep, label: "int array")
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
        guard valueRep.payload != 0 else {
            return []
        }
        var cursor = try arrayPayloadCursor(valueRep, label: "vec3f array")
        let count = try readArrayCount(cursor: &cursor, label: "USDC vec3f array count")
        let scalarCount = try checkedMultiplication(count, 3, label: "USDC vec3f scalar count")
        let byteCount = try checkedMultiplication(scalarCount, MemoryLayout<Float32>.size, label: "USDC vec3f array byte count")
        let bytes = try arrayBytes(
            valueRep,
            cursor: &cursor,
            byteCount: byteCount,
            label: "vec3f array"
        )
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

    private func readVec3dArrayValue(_ valueRep: USDCCrateValueRep) throws -> [USDPoint3D] {
        guard valueRep.isArray else {
            throw USDImportError.invalidData("USDC vec3d array value is missing the array bit.")
        }
        guard valueRep.payload != 0 else {
            return []
        }
        var cursor = try arrayPayloadCursor(valueRep, label: "vec3d array")
        let count = try readArrayCount(cursor: &cursor, label: "USDC vec3d array count")
        let scalarCount = try checkedMultiplication(count, 3, label: "USDC vec3d scalar count")
        let byteCount = try checkedMultiplication(scalarCount, MemoryLayout<UInt64>.size, label: "USDC vec3d array byte count")
        let bytes = try arrayBytes(
            valueRep,
            cursor: &cursor,
            byteCount: byteCount,
            label: "vec3d array"
        )
        var points: [USDPoint3D] = []
        points.reserveCapacity(count)
        var byteCursor = 0
        for _ in 0..<count {
            let x = try float64(bytes[byteCursor..<(byteCursor + 8)], label: "USDC vec3d array x")
            byteCursor += MemoryLayout<UInt64>.size
            let y = try float64(bytes[byteCursor..<(byteCursor + 8)], label: "USDC vec3d array y")
            byteCursor += MemoryLayout<UInt64>.size
            let z = try float64(bytes[byteCursor..<(byteCursor + 8)], label: "USDC vec3d array z")
            byteCursor += MemoryLayout<UInt64>.size
            points.append(USDPoint3D(x: x, y: y, z: z))
        }
        return points
    }

    private func readFloatArrayValue(_ valueRep: USDCCrateValueRep) throws -> [Double] {
        guard valueRep.isArray else {
            throw USDImportError.invalidData("USDC float array value is missing the array bit.")
        }
        guard valueRep.payload != 0 else {
            return []
        }
        var cursor = try arrayPayloadCursor(valueRep, label: "float array")
        let count = try readArrayCount(cursor: &cursor, label: "USDC float array count")
        let byteCount = try checkedMultiplication(count, MemoryLayout<Float32>.size, label: "USDC float array byte count")
        let bytes = try arrayBytes(
            valueRep,
            cursor: &cursor,
            byteCount: byteCount,
            label: "float array"
        )
        var values: [Double] = []
        values.reserveCapacity(count)
        var byteCursor = 0
        for _ in 0..<count {
            let value = Double(littleEndianFloat32(bytes[byteCursor..<(byteCursor + 4)]))
            byteCursor += MemoryLayout<Float32>.size
            guard value.isFinite else {
                throw USDImportError.invalidData("USDC float array contains a non-finite value.")
            }
            values.append(value)
        }
        return values
    }

    private func readDoubleArrayValue(_ valueRep: USDCCrateValueRep) throws -> [Double] {
        guard valueRep.isArray else {
            throw USDImportError.invalidData("USDC double array value is missing the array bit.")
        }
        guard valueRep.payload != 0 else {
            return []
        }
        var cursor = try arrayPayloadCursor(valueRep, label: "double array")
        let count = try readArrayCount(cursor: &cursor, label: "USDC double array count")
        let byteCount = try checkedMultiplication(count, MemoryLayout<UInt64>.size, label: "USDC double array byte count")
        let bytes = try arrayBytes(
            valueRep,
            cursor: &cursor,
            byteCount: byteCount,
            label: "double array"
        )
        var values: [Double] = []
        values.reserveCapacity(count)
        var byteCursor = 0
        for _ in 0..<count {
            let value = try float64(bytes[byteCursor..<(byteCursor + 8)], label: "USDC double array value")
            byteCursor += MemoryLayout<UInt64>.size
            values.append(value)
        }
        return values
    }

    private func readVec2fArrayValue(_ valueRep: USDCCrateValueRep) throws -> [USDPoint2D] {
        guard valueRep.isArray else {
            throw USDImportError.invalidData("USDC vec2f array value is missing the array bit.")
        }
        guard valueRep.payload != 0 else {
            return []
        }
        var cursor = try arrayPayloadCursor(valueRep, label: "vec2f array")
        let count = try readArrayCount(cursor: &cursor, label: "USDC vec2f array count")
        let scalarCount = try checkedMultiplication(count, 2, label: "USDC vec2f scalar count")
        let byteCount = try checkedMultiplication(scalarCount, MemoryLayout<Float32>.size, label: "USDC vec2f array byte count")
        let bytes = try arrayBytes(
            valueRep,
            cursor: &cursor,
            byteCount: byteCount,
            label: "vec2f array"
        )
        var points: [USDPoint2D] = []
        points.reserveCapacity(count)
        var byteCursor = 0
        for _ in 0..<count {
            let x = Double(littleEndianFloat32(bytes[byteCursor..<(byteCursor + 4)]))
            byteCursor += MemoryLayout<Float32>.size
            let y = Double(littleEndianFloat32(bytes[byteCursor..<(byteCursor + 4)]))
            byteCursor += MemoryLayout<Float32>.size
            guard x.isFinite, y.isFinite else {
                throw USDImportError.invalidData("USDC vec2f array contains a non-finite point.")
            }
            points.append(USDPoint2D(x: x, y: y))
        }
        return points
    }

    private func readVec2dArrayValue(_ valueRep: USDCCrateValueRep) throws -> [USDPoint2D] {
        guard valueRep.isArray else {
            throw USDImportError.invalidData("USDC vec2d array value is missing the array bit.")
        }
        guard valueRep.payload != 0 else {
            return []
        }
        var cursor = try arrayPayloadCursor(valueRep, label: "vec2d array")
        let count = try readArrayCount(cursor: &cursor, label: "USDC vec2d array count")
        let scalarCount = try checkedMultiplication(count, 2, label: "USDC vec2d scalar count")
        let byteCount = try checkedMultiplication(scalarCount, MemoryLayout<UInt64>.size, label: "USDC vec2d array byte count")
        let bytes = try arrayBytes(
            valueRep,
            cursor: &cursor,
            byteCount: byteCount,
            label: "vec2d array"
        )
        var points: [USDPoint2D] = []
        points.reserveCapacity(count)
        var byteCursor = 0
        for _ in 0..<count {
            let x = try float64(bytes[byteCursor..<(byteCursor + 8)], label: "USDC vec2d array x")
            byteCursor += MemoryLayout<UInt64>.size
            let y = try float64(bytes[byteCursor..<(byteCursor + 8)], label: "USDC vec2d array y")
            byteCursor += MemoryLayout<UInt64>.size
            points.append(USDPoint2D(x: x, y: y))
        }
        return points
    }

    private func arrayBytes(
        _ valueRep: USDCCrateValueRep,
        cursor: inout Int,
        byteCount: Int,
        label: String
    ) throws -> [UInt8] {
        guard valueRep.isCompressed else {
            return try crate.readFileBytes(at: cursor, byteCount: byteCount)
        }
        guard crate.version >= USDCCrateVersion(major: 0, minor: 5, patch: 0) else {
            throw USDImportError.invalidData("USDC \(label) is marked compressed before compression support.")
        }
        let compressedByteCount = try checkedInt(
            try crate.readFileUInt64(at: cursor),
            label: "USDC compressed \(label) byte count"
        )
        cursor += MemoryLayout<UInt64>.size
        let compressedBytes = try crate.readFileBytes(at: cursor, byteCount: compressedByteCount)
        return try USDCFastCompression.decompress(compressedBytes, expectedByteCount: byteCount)
    }

    private func arrayPayloadCursor(_ valueRep: USDCCrateValueRep, label: String) throws -> Int {
        var cursor = try payloadOffset(valueRep, label: label)
        if crate.version < USDCCrateVersion(major: 0, minor: 5, patch: 0) {
            let shapeRank = try crate.readFileUInt32(at: cursor)
            cursor += MemoryLayout<UInt32>.size
            guard shapeRank == 1 else {
                throw USDImportError.unsupportedFeature("Only one-dimensional USDC \(label)s are supported.")
            }
        }
        return cursor
    }

    private func inlinedVector3(_ valueRep: USDCCrateValueRep, scalarName: String) throws -> USDCVector3D {
        let bytes = inlinedInt8Bytes(valueRep, count: 3)
        let vector = USDCVector3D(x: Double(bytes[0]), y: Double(bytes[1]), z: Double(bytes[2]))
        guard vector.x.isFinite, vector.y.isFinite, vector.z.isFinite else {
            throw USDImportError.invalidData("USDC \(scalarName) contains a non-finite component.")
        }
        return vector
    }

    private func inlinedInt8Bytes(_ valueRep: USDCCrateValueRep, count: Int) -> [Int8] {
        (0..<count).map { index in
            let byte = UInt8((valueRep.payload >> UInt64(index * 8)) & 0xff)
            return Int8(bitPattern: byte)
        }
    }

    private func readVector3Float32(cursor: inout Int, label: String) throws -> USDCVector3D {
        let byteCount = 3 * MemoryLayout<Float32>.size
        let bytes = try crate.readFileBytes(at: cursor, byteCount: byteCount)
        cursor += byteCount
        let x = Double(littleEndianFloat32(bytes[0..<4]))
        let y = Double(littleEndianFloat32(bytes[4..<8]))
        let z = Double(littleEndianFloat32(bytes[8..<12]))
        guard x.isFinite, y.isFinite, z.isFinite else {
            throw USDImportError.invalidData("\(label) contains a non-finite component.")
        }
        return USDCVector3D(x: x, y: y, z: z)
    }

    private func readVector3Float64(cursor: inout Int, label: String) throws -> USDCVector3D {
        let x = try readFloat64(cursor: &cursor, label: "\(label) x")
        let y = try readFloat64(cursor: &cursor, label: "\(label) y")
        let z = try readFloat64(cursor: &cursor, label: "\(label) z")
        guard x.isFinite, y.isFinite, z.isFinite else {
            throw USDImportError.invalidData("\(label) contains a non-finite component.")
        }
        return USDCVector3D(x: x, y: y, z: z)
    }

    private func readQuaternionFloat32(cursor: inout Int, label: String) throws -> USDCQuaternion {
        let byteCount = 4 * MemoryLayout<Float32>.size
        let bytes = try crate.readFileBytes(at: cursor, byteCount: byteCount)
        cursor += byteCount
        // GfQuat POD payloads store imaginary xyz before real, although USDA text prints real first.
        let imaginaryX = Double(littleEndianFloat32(bytes[0..<4]))
        let imaginaryY = Double(littleEndianFloat32(bytes[4..<8]))
        let imaginaryZ = Double(littleEndianFloat32(bytes[8..<12]))
        let real = Double(littleEndianFloat32(bytes[12..<16]))
        guard real.isFinite, imaginaryX.isFinite, imaginaryY.isFinite, imaginaryZ.isFinite else {
            throw USDImportError.invalidData("\(label) contains a non-finite component.")
        }
        return USDCQuaternion(
            real: real,
            imaginaryX: imaginaryX,
            imaginaryY: imaginaryY,
            imaginaryZ: imaginaryZ
        )
    }

    private func readQuaternionFloat64(cursor: inout Int, label: String) throws -> USDCQuaternion {
        // GfQuat POD payloads store imaginary xyz before real, although USDA text prints real first.
        let imaginaryX = try readFloat64(cursor: &cursor, label: "\(label) imaginary x")
        let imaginaryY = try readFloat64(cursor: &cursor, label: "\(label) imaginary y")
        let imaginaryZ = try readFloat64(cursor: &cursor, label: "\(label) imaginary z")
        let real = try readFloat64(cursor: &cursor, label: "\(label) real")
        return USDCQuaternion(
            real: real,
            imaginaryX: imaginaryX,
            imaginaryY: imaginaryY,
            imaginaryZ: imaginaryZ
        )
    }

    private func readFloat64(cursor: inout Int, label: String) throws -> Double {
        let bytes = try crate.readFileBytes(at: cursor, byteCount: MemoryLayout<UInt64>.size)
        cursor += MemoryLayout<UInt64>.size
        let value = Double(bitPattern: littleEndianUInt64(bytes[0..<bytes.count]))
        guard value.isFinite else {
            throw USDImportError.invalidData("\(label) is not finite.")
        }
        return value
    }

    private func float64(_ bytes: ArraySlice<UInt8>, label: String) throws -> Double {
        let value = Double(bitPattern: littleEndianUInt64(bytes))
        guard value.isFinite else {
            throw USDImportError.invalidData("\(label) is not finite.")
        }
        return value
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

    private func littleEndianUInt64(_ bytes: ArraySlice<UInt8>) -> UInt64 {
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
