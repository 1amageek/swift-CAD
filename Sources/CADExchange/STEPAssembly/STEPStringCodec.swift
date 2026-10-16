import CADGeometry

/// Standard lexical decoding preserves Unicode scalars without normalization or repair.
public struct STEPStringCodec: STEPStringCoding {
    public init() {}
    public func decode(_ token: String, limits: STEPStringLimits = .standard) throws -> STEPStringResult {
        try limits.validate(); try Task.checkCancellation()
        let bytes = try inputByteCount(token, ceiling: min(limits.maximumInputBytes, min(32769, limits.maximumWork)))
        guard token.unicodeScalars.first?.value == 39, token.unicodeScalars.last?.value == 39, bytes >= 2 else {
            throw STEPStringError.malformed("Expected a complete quoted STEP token.")
        }
        let scalars = token.unicodeScalars
        var cursor = scalars.index(after: scalars.startIndex)
        let end = scalars.index(before: scalars.endIndex)
        var output = "", outputBytes = 0, work = bytes, page = 0
        func take() throws -> Unicode.Scalar {
            guard cursor < end else { throw STEPStringError.malformed("Truncated STEP directive.") }
            let scalar = scalars[cursor]; cursor = scalars.index(after: cursor); return scalar
        }
        func expect(_ value: UInt32) throws {
            guard try take().value == value else { throw STEPStringError.malformed("Malformed STEP directive.") }
        }
        func append(_ scalar: Unicode.Scalar) throws {
            let size = scalar.value <= 0x7F ? 1 : scalar.value <= 0x7FF ? 2 : scalar.value <= 0xFFFF ? 3 : 4
            guard size <= limits.maximumOutputBytes - outputBytes, work < limits.maximumWork else {
                throw STEPStringError.resourceLimitExceeded
            }
            outputBytes += size; work += 1; output.unicodeScalars.append(scalar)
        }
        func hexadecimal(_ count: Int) throws -> Unicode.Scalar {
            var value: UInt32 = 0
            for _ in 0..<count {
                let digit = try take().value
                let nibble: UInt32
                if digit >= 48 && digit <= 57 { nibble = digit - 48 }
                else if digit >= 65 && digit <= 70 { nibble = digit - 55 }
                else { throw STEPStringError.malformed("Expected uppercase hexadecimal scalar digits.") }
                value = value * 16 + nibble
            }
            guard let scalar = Unicode.Scalar(value) else {
                throw STEPStringError.malformed("Invalid UCS scalar.")
            }
            return scalar
        }
        while cursor < end {
            try Task.checkCancellation()
            let scalar = try take()
            if scalar.value == 39 {
                try expect(39); try append(scalar)
            } else if scalar.value == 92 {
                let directive = try take().value
                switch directive {
                case 92: try append(scalar)
                case 80:
                    let alphabet = try take().value
                    guard alphabet >= 65 && alphabet <= 73 else { throw STEPStringError.malformed("Unknown ISO 8859 alphabet.") }
                    try expect(92); page = Int(alphabet - 65)
                case 83:
                    try expect(92)
                    let basic = try take().value
                    guard basic >= 32 && basic <= 126 else { throw STEPStringError.malformed("Invalid shifted basic character.") }
                    // An apostrophe or reverse solidus retains its doubled lexical representation.
                    if basic == 39 || basic == 92 { try expect(basic) }
                    try append(STEPISO8859.scalar(page: page, basic: basic))
                case 88:
                    let kind = try take().value
                    if kind == 92 { try append(hexadecimal(2)) }
                    else if kind == 50 || kind == 52 {
                        try expect(92)
                        var count = 0
                        while true {
                            guard cursor < end else { throw STEPStringError.malformed("Unterminated UCS block.") }
                            if scalars[cursor].value == 92 {
                                try expect(92); try expect(88); try expect(48); try expect(92)
                                guard count > 0 else { throw STEPStringError.malformed("Empty UCS block.") }
                                break
                            }
                            try append(hexadecimal(kind == 50 ? 4 : 8)); count += 1
                        }
                    } else { throw STEPStringError.malformed("Unknown UCS directive.") }
                default: throw STEPStringError.malformed("Unknown STEP string directive.")
                }
            } else {
                guard scalar.value >= 32 && scalar.value != 127 else { throw STEPStringError.malformed("Unencoded control character.") }
                try append(scalar)
            }
        }
        return STEPStringResult(value: output, consumedWork: work, outputBytes: outputBytes)
    }
    private func inputByteCount(_ value: String, ceiling: Int) throws -> Int {
        var count = 0
        for _ in value.utf8 {
            try Task.checkCancellation()
            guard count < ceiling else { throw STEPStringError.resourceLimitExceeded }
            count += 1
        }
        return count
    }
    public func encode(_ value: String, limits: STEPStringLimits = .standard) throws -> STEPStringResult {
        var execution = try OriginalQueryExecution.independentGeometry()
        return try encode(value, limits: limits, using: &execution)
    }
    public func encode<A: ExactScalarAdmission & ~Copyable>(_ value: String,
        limits: STEPStringLimits = .standard, using execution: inout A) throws -> STEPStringResult {
        try limits.validate(); try Task.checkCancellation()
        var inputBytes = 0
        for _ in value.utf8 {
            try execution.consumeWork(1)
            guard inputBytes < min(limits.maximumInputBytes, limits.maximumWork) else { throw STEPStringError.resourceLimitExceeded }
            inputBytes += 1
        }
        var capacity = 2
        for scalar in value.unicodeScalars {
            try execution.consumeWork(1)
            let size: Int
            switch scalar.value {
            case 39, 92: size = 2
            case 32...126: size = 1
            default: size = scalar.value <= 255 ? 5 : scalar.value <= 65535 ? 12 : 16
            }
            guard size <= min(limits.maximumOutputBytes, 32769) - capacity else { throw STEPStringError.resourceLimitExceeded }
            capacity += size
        }
        guard capacity <= min(limits.maximumOutputBytes, 32769) else { throw STEPStringError.resourceLimitExceeded }
        try execution.retainStorage(bytes: capacity)
        var output = "", bytes = 0, work = inputBytes
        output.reserveCapacity(capacity)
        func append(_ piece: String) throws {
            let count = piece.utf8.count
            guard count <= min(limits.maximumOutputBytes, 32769) - bytes,
                  count <= limits.maximumWork - work else { throw STEPStringError.resourceLimitExceeded }
            try execution.consumeWork(count)
            bytes += count; work += count; output += piece
        }
        try append("'")
        for scalar in value.unicodeScalars {
            try Task.checkCancellation()
            switch scalar.value {
            case 39: try append("''")
            case 92: try append(#"\\"#)
            case 32...126: try append(String(scalar))
            default:
                let width = scalar.value <= 255 ? 2 : scalar.value <= 65535 ? 4 : 8
                let hex = String(scalar.value, radix: 16, uppercase: true)
                let digits = String(repeating: "0", count: width - hex.count) + hex
                if width == 2 {
                    try append(#"\X\"#); try append(digits)
                } else {
                    try append(width == 4 ? #"\X2\"# : #"\X4\"#)
                    try append(digits); try append(#"\X0\"#)
                }
            }
        }
        try append("'")
        return STEPStringResult(value: output, consumedWork: work, outputBytes: bytes)
    }
}
