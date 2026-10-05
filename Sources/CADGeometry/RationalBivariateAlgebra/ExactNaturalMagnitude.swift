import CADCore

/// Canonical little-endian base-2^32 positive magnitude; an empty buffer is zero.
struct ExactNaturalMagnitude: Equatable, Sendable {
    let words: [UInt32]
    init(_ words: [UInt32]) {
        var canonical = words
        while canonical.last == 0 { canonical.removeLast() }
        self.words = canonical
    }
    static let zero = Self([])
    static let one = Self([1])
    var isZero: Bool { words.isEmpty }
    func admittedBitCount<B: RationalAlgebraAdmitting>(usage: inout B) throws -> Int {
        guard let last = words.last else { return 0 }
        try usage.consumeExactWork(1)
        return try rationalAlgebraCount(rationalAlgebraCount(words.count - 1, 32, multiply: true),
            32 - last.leadingZeroBitCount)
    }
    func compared(to other: Self) -> Int {
        if words.count != other.words.count { return words.count < other.words.count ? -1 : 1 }
        for i in words.indices.reversed() {
            if words[i] != other.words[i] { return words[i] < other.words[i] ? -1 : 1 }
        }
        return 0
    }
    func adding<B: RationalAlgebraAdmitting>(_ other: Self, usage: inout B) throws -> Self {
        let count = try rationalAlgebraCount(max(words.count, other.words.count), 1)
        try usage.consumeExactWork(count); try usage.retainExactStorage(count)
        var output = [UInt32](repeating: 0, count: count); var carry: UInt64 = 0
        for i in 0..<(count - 1) {
            let sum = UInt64(i < words.count ? words[i] : 0)
                + UInt64(i < other.words.count ? other.words[i] : 0) + carry
            output[i] = UInt32(truncatingIfNeeded: sum); carry = sum >> 32
        }
        output[count - 1] = UInt32(carry); return Self(output)
    }
    func subtracting<B: RationalAlgebraAdmitting>(_ other: Self, usage: inout B) throws -> Self {
        guard compared(to: other) >= 0 else { throw rationalAlgebraFailure("Negative exact magnitude subtraction.") }
        try usage.consumeExactWork(words.count); try usage.retainExactStorage(words.count)
        var output = [UInt32](repeating: 0, count: words.count); var borrow: UInt64 = 0
        for i in words.indices {
            let lhs = UInt64(words[i]); let rhs = UInt64(i < other.words.count ? other.words[i] : 0) + borrow
            output[i] = UInt32(truncatingIfNeeded: lhs &- rhs); borrow = lhs < rhs ? 1 : 0
        }
        return Self(output)
    }
    func multiplied<B: RationalAlgebraAdmitting>(by other: Self, usage: inout B) throws -> Self {
        if isZero || other.isZero { return .zero }
        let count = try rationalAlgebraCount(words.count, other.words.count)
        try usage.consumeExactWork(rationalAlgebraCount(words.count, other.words.count, multiply: true))
        try usage.retainExactStorage(count)
        var output = [UInt32](repeating: 0, count: count)
        for i in words.indices {
            var carry: UInt64 = 0
            for j in other.words.indices {
                let product = UInt64(words[i]) * UInt64(other.words[j]) + UInt64(output[i+j]) + carry
                output[i+j] = UInt32(truncatingIfNeeded: product); carry = product >> 32
            }
            output[i+other.words.count] = UInt32(carry)
        }
        return Self(output)
    }
    func shifted<B: RationalAlgebraAdmitting>(by bits: Int, usage: inout B) throws -> Self {
        guard bits >= 0 else { throw rationalAlgebraFailure("Negative exact magnitude shift.") }
        if isZero { return .zero }
        let count = try rationalAlgebraCount(try rationalAlgebraCount(words.count, bits / 32), 1)
        try usage.consumeExactWork(count); try usage.retainExactStorage(count)
        var output = [UInt32](repeating: 0, count: count); var carry: UInt64 = 0
        for i in words.indices {
            let value = UInt64(words[i]) << (bits % 32) | carry
            output[i + bits / 32] = UInt32(truncatingIfNeeded: value); carry = value >> 32
        }
        output[words.count + bits / 32] = UInt32(carry); return Self(output)
    }
    func quotientAndRemainder<B: RationalAlgebraAdmitting>(dividingBy divisor: Self,
                                                          usage: inout B) throws -> (Self, Self) {
        guard !divisor.isZero else { throw rationalAlgebraFailure("Exact integer division by zero.") }
        if compared(to: divisor) < 0 { return (.zero, self) }
        let bitCount = try admittedBitCount(usage: &usage)
        try usage.retainExactStorage(words.count)
        var quotient = [UInt32](repeating: 0, count: words.count); var remainder = Self.zero
        for bit in (0..<bitCount).reversed() {
            try Task.checkCancellation(); try usage.consumeExactWork(1)
            remainder = try remainder.shifted(by: 1, usage: &usage)
            if words[bit / 32] & (UInt32(1) << (bit % 32)) != 0 {
                remainder = try remainder.adding(.one, usage: &usage)
            }
            if remainder.compared(to: divisor) >= 0 {
                remainder = try remainder.subtracting(divisor, usage: &usage)
                quotient[bit / 32] |= UInt32(1) << (bit % 32)
            }
        }
        return (Self(quotient), remainder)
    }
    func trailingZeroBits<B: RationalAlgebraAdmitting>(usage: inout B) throws -> Int {
        for i in words.indices {
            try usage.consumeExactWork(1)
            if words[i] != 0 {
                return try rationalAlgebraCount(rationalAlgebraCount(i, 32, multiply: true), words[i].trailingZeroBitCount)
            }
        }
        return 0
    }
    func shiftedRight<B: RationalAlgebraAdmitting>(by bits: Int, usage: inout B) throws -> Self {
        guard bits >= 0 else { throw rationalAlgebraFailure("Negative exact magnitude right shift.") }
        let offset = bits / 32
        if offset >= words.count { return .zero }
        let count = words.count - offset
        try usage.consumeExactWork(count); try usage.retainExactStorage(count)
        var output = [UInt32](repeating: 0, count: count)
        for i in 0..<count {
            let position = i + offset
            let high = position + 1 < words.count ? UInt64(words[position + 1]) << 32 : 0
            output[i] = UInt32(truncatingIfNeeded: (high | UInt64(words[position])) >> (bits % 32))
        }
        return Self(output)
    }
    static func gcd<B: RationalAlgebraAdmitting>(_ a: Self, _ b: Self, usage: inout B) throws -> Self {
        if a.isZero { return b }; if b.isZero { return a }
        let az = try a.trailingZeroBits(usage: &usage), bz = try b.trailingZeroBits(usage: &usage)
        let common = min(az, bz)
        var lhs = try a.shiftedRight(by: az, usage: &usage)
        var rhs = try b.shiftedRight(by: bz, usage: &usage)
        while true {
            try Task.checkCancellation(); try usage.consumeExactWork(max(lhs.words.count, rhs.words.count))
            let comparison = lhs.compared(to: rhs)
            if comparison == 0 { return try lhs.shifted(by: common, usage: &usage) }
            if comparison > 0 {
                lhs = try lhs.subtracting(rhs, usage: &usage)
                lhs = try lhs.shiftedRight(by: lhs.trailingZeroBits(usage: &usage), usage: &usage)
            } else {
                rhs = try rhs.subtracting(lhs, usage: &usage)
                rhs = try rhs.shiftedRight(by: rhs.trailingZeroBits(usage: &usage), usage: &usage)
            }
        }
    }
}
