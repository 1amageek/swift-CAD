/// Canonical little-endian base-2^32 positive magnitude; an empty buffer is zero.
struct ExactNaturalMagnitude: Equatable, Sendable {
    let words: [UInt32]
    init(_ words: consuming [UInt32]) {
        var canonical = consume words
        while canonical.last == 0 { canonical.removeLast() }
        self.words = canonical
    }
    static let zero = Self([])
    static let one = Self([1])
    var isZero: Bool { words.isEmpty }
    func admittedBitCount<B: RationalAlgebraAdmitting>(usage: inout B) throws -> Int {
        guard let last = words.last else { return 0 }
        try usage.consumeExactWork(1)
        return try exactScalarCount(exactScalarCount(words.count - 1, 32, multiply: true),
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
        let count = try exactScalarCount(max(words.count, other.words.count), 1)
        try usage.consumeExactWork(count); try usage.retainExactStorage(count)
        var output = [UInt32](repeating: 0, count: count); var carry: UInt64 = 0
        for i in 0..<(count - 1) {
            let sum = UInt64(i < words.count ? words[i] : 0)
                + UInt64(i < other.words.count ? other.words[i] : 0) + carry
            output[i] = UInt32(truncatingIfNeeded: sum); carry = sum >> 32
        }
        output[count - 1] = UInt32(carry); return Self(consume output)
    }
    func subtracting<B: RationalAlgebraAdmitting>(_ other: Self, usage: inout B) throws -> Self {
        try usage.consumeExactWork(max(words.count, other.words.count))
        guard compared(to: other) >= 0 else { throw exactScalarBackendFailure("Negative exact magnitude subtraction.") }
        try usage.consumeExactWork(words.count); try usage.retainExactStorage(words.count)
        var output = [UInt32](repeating: 0, count: words.count); var borrow: UInt64 = 0
        for i in words.indices {
            let lhs = UInt64(words[i]); let rhs = UInt64(i < other.words.count ? other.words[i] : 0) + borrow
            output[i] = UInt32(truncatingIfNeeded: lhs &- rhs); borrow = lhs < rhs ? 1 : 0
        }
        return Self(consume output)
    }
    func multiplied<B: RationalAlgebraAdmitting>(by other: Self, usage: inout B) throws -> Self {
        if isZero || other.isZero { return .zero }
        let count = try exactScalarCount(words.count, other.words.count)
        try usage.consumeExactWork(exactScalarCount(words.count, other.words.count, multiply: true))
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
        return Self(consume output)
    }
    func shifted<B: RationalAlgebraAdmitting>(by bits: Int, usage: inout B) throws -> Self {
        guard bits >= 0 else { throw exactScalarBackendFailure("Negative exact magnitude shift.") }
        if isZero { return .zero }
        let count = try exactScalarCount(try exactScalarCount(words.count, bits / 32), 1)
        try usage.consumeExactWork(count); try usage.retainExactStorage(count)
        var output = [UInt32](repeating: 0, count: count); var carry: UInt64 = 0
        for i in words.indices {
            let value = UInt64(words[i]) << (bits % 32) | carry
            output[i + bits / 32] = UInt32(truncatingIfNeeded: value); carry = value >> 32
        }
        output[words.count + bits / 32] = UInt32(carry); return Self(consume output)
    }
    func quotientAndRemainder<B: RationalAlgebraAdmitting>(dividingBy divisor: Self,
                                                          usage: inout B) throws -> (Self, Self) {
        guard !divisor.isZero else { throw exactScalarBackendFailure("Exact integer division by zero.") }
        try usage.consumeExactWork(max(words.count, divisor.words.count))
        if compared(to: divisor) < 0 { return (.zero, self) }
        if divisor.words.count == 1 {
            try usage.retainExactStorage(try exactScalarCount(words.count, 1))
            var quotient = [UInt32](repeating: 0, count: words.count)
            let denominator = UInt64(divisor.words[0])
            var remainder: UInt64 = 0
            for index in words.indices.reversed() {
                try exactScalarTaskCheckpoint(); try usage.consumeExactWork(1)
                // The retained remainder is less than the one-limb divisor,
                // so this base-2^32 partial numerator fits UInt64 exactly.
                let partial = (remainder << 32) | UInt64(words[index])
                quotient[index] = UInt32(partial / denominator)
                remainder = partial % denominator
            }
            return (Self(consume quotient), Self([UInt32(remainder)]))
        }
        let bitCount = try admittedBitCount(usage: &usage)
        let divisorBitCount = try divisor.admittedBitCount(usage: &usage)
        let shift = bitCount - divisorBitCount
        try usage.retainExactStorage(try exactScalarCount(words.count, words.count))
        var quotient = [UInt32](repeating: 0, count: words.count)
        var remainder = words
        var shiftedDivisor = try divisor.shifted(by: shift, usage: &usage).words
        for bit in (0...shift).reversed() {
            try exactScalarTaskCheckpoint()
            try usage.consumeExactWork(words.count)
            var comparison = 0
            for index in words.indices.reversed() {
                let second = index < shiftedDivisor.count ? shiftedDivisor[index] : 0
                if remainder[index] != second {
                    comparison = remainder[index] < second ? -1 : 1
                    break
                }
            }
            if comparison >= 0 {
                try usage.consumeExactWork(words.count)
                var borrow: UInt64 = 0
                for index in remainder.indices {
                    let first = UInt64(remainder[index])
                    let second = UInt64(index < shiftedDivisor.count ? shiftedDivisor[index] : 0) + borrow
                    remainder[index] = UInt32(truncatingIfNeeded: first &- second)
                    borrow = first < second ? 1 : 0
                }
                quotient[bit / 32] |= UInt32(1) << (bit % 32)
            }
            if bit > 0 {
                try usage.consumeExactWork(shiftedDivisor.count)
                // Each iteration aligns the next quotient bit. No new magnitude
                // is materialized for a shifted or subtracted intermediate.
                for index in shiftedDivisor.indices {
                    let high = index + 1 < shiftedDivisor.count ? UInt64(shiftedDivisor[index + 1]) << 32 : 0
                    shiftedDivisor[index] = UInt32(truncatingIfNeeded: (high | UInt64(shiftedDivisor[index])) >> 1)
                }
            }
        }
        return (Self(consume quotient), Self(consume remainder))
    }
    func trailingZeroBits<B: RationalAlgebraAdmitting>(usage: inout B) throws -> Int {
        for i in words.indices {
            try usage.consumeExactWork(1)
            if words[i] != 0 {
                return try exactScalarCount(exactScalarCount(i, 32, multiply: true), words[i].trailingZeroBitCount)
            }
        }
        return 0
    }
    func powerOfTwoExponent<B: RationalAlgebraAdmitting>(usage: inout B) throws -> Int? {
        guard let last = words.last, last.nonzeroBitCount == 1 else { return nil }
        for index in words.indices.dropLast() {
            try exactScalarTaskCheckpoint(); try usage.consumeExactWork(1)
            if words[index] != 0 { return nil }
        }
        try exactScalarTaskCheckpoint(); try usage.consumeExactWork(1)
        return try exactScalarCount(exactScalarCount(words.count - 1, 32, multiply: true),
            last.trailingZeroBitCount)
    }
    func shiftedRight<B: RationalAlgebraAdmitting>(by bits: Int, usage: inout B) throws -> Self {
        guard bits >= 0 else { throw exactScalarBackendFailure("Negative exact magnitude right shift.") }
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
        return Self(consume output)
    }
    static func gcd<B: RationalAlgebraAdmitting>(_ a: Self, _ b: Self, usage: inout B) throws -> Self {
        if a.isZero { return b }; if b.isZero { return a }
        if a == .one || b == .one {
            try exactScalarTaskCheckpoint(); try usage.consumeExactWork(1)
            return .one
        }
        if a.words.count == 1, b.words.count == 1 {
            var first = a.words[0], second = b.words[0]
            while second != 0 {
                try exactScalarTaskCheckpoint(); try usage.consumeExactWork(1)
                let remainder = first % second
                first = second; second = remainder
            }
            if first == 1 { return .one }
            try usage.retainExactStorage(1)
            return Self([first])
        }
        var lhs = a, rhs = b
        while !rhs.isZero {
            try exactScalarTaskCheckpoint()
            try usage.consumeExactWork(max(lhs.words.count, rhs.words.count))
            if rhs == .one { return .one }
            let remainder = try lhs.quotientAndRemainder(dividingBy: rhs, usage: &usage).1
            lhs = rhs; rhs = remainder
        }
        return lhs
    }
}
