import CADCore
import CADGeometry

/// Exact finite decimal publication of canonical rational values under the caller allowance.
package enum OriginalIGESDecimalWriting {
    package static func literal(_ value: ExactRationalCoefficient,
        usage: inout IndependentShapeExchangeUsage) throws -> String {
        if value.isZero { try usage.charge(bytes: 1, work: 1); return "0" }
        var denominator = try copy(value.canonicalDenominatorWords, usage: &usage)
        var twos = 0, fives = 0
        while denominator.count != 1 || denominator.first != 1 {
            let byTwo = try divided(denominator, by: 2, usage: &usage)
            if byTwo.remainder == 0 { denominator = byTwo.words; twos = try increment(twos); continue }
            let byFive = try divided(denominator, by: 5, usage: &usage)
            guard byFive.remainder == 0 else {
                throw IndependentShapeExchangeError.metadataLoss("Original rational IGES coordinate has no exact finite decimal representation.")
            }
            denominator = byFive.words; fives = try increment(fives)
        }
        let places = max(twos, fives)
        var numerator = try copy(value.canonicalNumeratorWords, usage: &usage)
        for _ in twos..<places { numerator = try multiplied(numerator, by: 2, usage: &usage) }
        for _ in fives..<places { numerator = try multiplied(numerator, by: 5, usage: &usage) }
        var reversed: [UInt8] = []
        while !numerator.isEmpty {
            let next = try divided(numerator, by: 10, usage: &usage)
            try usage.charge(bytes: 1, work: 1); reversed.append(UInt8(next.remainder) + 48); numerator = next.words
        }
        let count = try increment(max(reversed.count, places))
        let signCount = value.isNegative ? 1 : 0
        let total = count.addingReportingOverflow(signCount + (places > 0 ? 1 : 0))
        guard !total.overflow else { throw overflow() }
        try usage.charge(bytes: total.partialValue, work: total.partialValue)
        var output: [UInt8] = []; output.reserveCapacity(total.partialValue)
        if value.isNegative { output.append(45) }
        if places == 0 { output.append(contentsOf: reversed.reversed()) }
        else {
            let integerCount = max(1, reversed.count - places)
            for index in stride(from: integerCount + places - 1, through: 0, by: -1) {
                if index == places - 1 { output.append(46) }
                output.append(index < reversed.count ? reversed[index] : 48)
            }
        }
        try usage.charge(bytes: output.count, work: output.count)
        return String(decoding: output, as: UTF8.self)
    }
    private static func copy(_ words: [UInt32], usage: inout IndependentShapeExchangeUsage) throws -> [UInt32] {
        try RationalAlgebraStorage.retain(words.count, of: UInt32.self, usage: &usage)
        try usage.charge(work: words.count)
        return Array(words)
    }
    private static func divided(_ words: [UInt32], by divisor: UInt32,
        usage: inout IndependentShapeExchangeUsage) throws -> (words: [UInt32], remainder: UInt32) {
        var output = try copy(words, usage: &usage); var remainder: UInt64 = 0
        for index in words.indices.reversed() {
            try usage.charge(work: 1)
            let current = (remainder << 32) | UInt64(words[index])
            output[index] = UInt32(current / UInt64(divisor)); remainder = current % UInt64(divisor)
        }
        while output.last == 0 { try usage.charge(work: 1); output.removeLast() }
        return (output, UInt32(remainder))
    }
    private static func multiplied(_ words: [UInt32], by factor: UInt32,
        usage: inout IndependentShapeExchangeUsage) throws -> [UInt32] {
        let count = try increment(words.count)
        try RationalAlgebraStorage.retain(count, of: UInt32.self, usage: &usage)
        var output = [UInt32](repeating: 0, count: count); var carry: UInt64 = 0
        for index in words.indices {
            try usage.charge(work: 1)
            let value = UInt64(words[index]) * UInt64(factor) + carry
            output[index] = UInt32(truncatingIfNeeded: value); carry = value >> 32
        }
        output[words.count] = UInt32(carry)
        if output.last == 0 { output.removeLast() }
        return output
    }
    private static func increment(_ value: Int) throws -> Int {
        let next = value.addingReportingOverflow(1); guard !next.overflow else { throw overflow() }; return next.partialValue
    }
    private static func overflow() -> IndependentShapeExchangeError { .resourceLimitExceeded("Exact IGES decimal publication size overflows.") }
}
