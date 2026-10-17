import CADCore


/// SHA-256 (FIPS 180-4) of a byte buffer, written in Swift so the source fingerprint stays
/// available on every platform the package builds for, WASI included.
///
/// Hashing allocates nothing per block: the message schedule is one stack buffer that every
/// block reuses, full blocks are read in place from the caller's bytes, and only the padded
/// tail (at most two blocks) is copied into a second stack buffer.
enum SHA256Digest {
    private static let roundConstants: [UInt32] = [
        0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5,
        0x3956c25b, 0x59f111f1, 0x923f82a4, 0xab1c5ed5,
        0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3,
        0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174,
        0xe49b69c1, 0xefbe4786, 0x0fc19dc6, 0x240ca1cc,
        0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da,
        0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7,
        0xc6e00bf3, 0xd5a79147, 0x06ca6351, 0x14292967,
        0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13,
        0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85,
        0xa2bfe8a1, 0xa81a664b, 0xc24b8b70, 0xc76c51a3,
        0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070,
        0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5,
        0x391c0cb3, 0x4ed8aa4a, 0x5b9cca4f, 0x682e6ff3,
        0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208,
        0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2,
    ]

    /// The working hash value H(i).
    private struct State {
        var h0: UInt32 = 0x6a09e667
        var h1: UInt32 = 0xbb67ae85
        var h2: UInt32 = 0x3c6ef372
        var h3: UInt32 = 0xa54ff53a
        var h4: UInt32 = 0x510e527f
        var h5: UInt32 = 0x9b05688c
        var h6: UInt32 = 0x1f83d9ab
        var h7: UInt32 = 0x5be0cd19

        var words: [UInt32] { [h0, h1, h2, h3, h4, h5, h6, h7] }
    }

    /// The lowercase hexadecimal digest under the existing ordinary authoring policy.
    static func hexDigest(for bytes: [UInt8]) throws -> String {
        var admission = UnboundedAuthoringAdmission()
        return try sourceHexDigest(for: bytes, using: &admission)
    }

    static func hexDigest(of bytes: UnsafeRawBufferPointer) throws -> String {
        var admission = UnboundedAuthoringAdmission()
        var encoder = try PortableSourceEncoder(limits: unboundedLimits)
        return try sourceHexDigest(of: bytes, encoding: &encoder, using: &admission)
    }

    static func sourceHexDigest(for bytes: [UInt8]) throws -> String {
        var admission = UnboundedAuthoringAdmission()
        return try sourceHexDigest(for: bytes, using: &admission)
    }

    static func sourceHexDigest<A: NumericWorkAdmission & ~Copyable>(for bytes: [UInt8],
        using admission: inout A) throws -> String {
        var encoder = try PortableSourceEncoder(limits: unboundedLimits)
        return try sourceHexDigest(for: bytes, encoding: &encoder, using: &admission)
    }

    static func sourceHexDigest<A: NumericWorkAdmission & ~Copyable>(for bytes: [UInt8],
        encoding encoder: inout PortableSourceEncoder, using admission: inout A) throws -> String {
        try bytes.withUnsafeBytes { buffer in
            try sourceHexDigest(of: buffer, encoding: &encoder, using: &admission)
        }
    }

    private static var unboundedLimits: PortableSourceEncodingLimits {
        .init(maximumBytes: Int.max, maximumWork: Int.max, maximumDepth: Int.max)
    }

    private static func sourceHexDigest<A: NumericWorkAdmission & ~Copyable>(of bytes: UnsafeRawBufferPointer,
        encoding encoder: inout PortableSourceEncoder, using admission: inout A) throws -> String {
        let tailBlocks = bytes.count % 64 < 56 ? 1 : 2
        let blockCount = bytes.count / 64 + tailBlocks
        let (blockWork, overflow) = blockCount.multipliedReportingOverflow(by: 136)
        let (inputWork, inputOverflow) = bytes.count.addingReportingOverflow(192)
        guard !overflow, !inputOverflow else {
            throw PortableSourceEncodingError.resourceLimitExceeded("Source SHA-256 work.")
        }
        // These are the original source-hash work units, paid once through both
        // the local encoding allowance and the caller's cumulative admission.
        try encoder.charge(work: inputWork, using: &admission)
        try encoder.charge(work: blockWork, using: &admission)
        let words = try digest(of: bytes, using: &admission)
        try admission.retainStorage(count: 16, stride: MemoryLayout<UInt8>.stride)
        try admission.retainStorage(count: 64, stride: MemoryLayout<UInt8>.stride)
        let digits = Array("0123456789abcdef".utf8)
        var output: [UInt8] = []
        output.reserveCapacity(64)
        for word in words {
            for shift in stride(from: 28, through: 0, by: -4) {
                output.append(digits[Int((word >> UInt32(shift)) & 0x0f)])
            }
        }
        try admission.retainStorage(count: 64, stride: MemoryLayout<UInt8>.stride)
        let result = String(decoding: output, as: UTF8.self)
        try admission.checkpoint()
        return result
    }

    /// The eight digest words of `message` under the existing ordinary policy.
    static func digest(of message: UnsafeRawBufferPointer) throws -> [UInt32] {
        var admission = UnboundedAuthoringAdmission()
        return try digest(of: message, using: &admission)
    }

    // The caller owns the immutable buffer for this entire scoped borrow. Blocks and
    // padding are indexed only within derived counts; all tail bytes are initialized.
    // Temporary pointers never escape and are released exactly once by their scopes.
    private static func digest<A: NumericWorkAdmission & ~Copyable>(of message: UnsafeRawBufferPointer,
        using admission: inout A) throws -> [UInt32] {
        try admission.checkpoint()
        try CurrentTaskCancellationChecker().checkCancellation()
        try admission.retainStorage(count: 1, stride: MemoryLayout<State>.stride)
        try admission.retainStorage(count: 64, stride: MemoryLayout<UInt32>.stride)
        var state = State()
        try roundConstants.withUnsafeBufferPointer { constants in
            try withUnsafeTemporaryAllocation(of: UInt32.self, capacity: 64) { schedule in
                let fullBlockCount = message.count / 64
                var start = 0
                while start < fullBlockCount &* 64 {
                    try admission.checkpoint()
                    try CurrentTaskCancellationChecker().checkCancellation()
                    compress(
                        UnsafeRawBufferPointer(rebasing: message[start..<(start &+ 64)]),
                        into: &state,
                        schedule: schedule,
                        constants: constants
                    )
                    start &+= 64
                }

                // The tail holds the remaining bytes, the 0x80 marker and the big-endian bit
                // length; it spans two blocks when the remainder leaves no room for the length.
                let remainderStart = fullBlockCount * 64
                let remainderCount = message.count - remainderStart
                let tailCount = remainderCount < 56 ? 64 : 128
                try admission.retainStorage(count: 128, stride: MemoryLayout<UInt8>.stride)
                try withUnsafeTemporaryAllocation(of: UInt8.self, capacity: 128) { tail in
                    tail.initialize(repeating: 0)
                    for index in 0..<remainderCount {
                        tail[index] = message[remainderStart + index]
                    }
                    tail[remainderCount] = 0x80
                    let bitLength = UInt64(message.count) &* 8
                    for index in 0..<8 {
                        tail[tailCount - 1 - index] = UInt8(truncatingIfNeeded: bitLength >> (UInt64(index) * 8))
                    }
                    let tailBytes = UnsafeRawBufferPointer(tail)
                    for offset in stride(from: 0, to: tailCount, by: 64) {
                        try admission.checkpoint()
                        try CurrentTaskCancellationChecker().checkCancellation()
                        compress(
                            UnsafeRawBufferPointer(rebasing: tailBytes[offset..<(offset + 64)]),
                            into: &state,
                            schedule: schedule,
                            constants: constants
                        )
                    }
                }
            }
        }
        try admission.retainStorage(count: 8, stride: MemoryLayout<UInt32>.stride)
        let result = state.words
        try admission.checkpoint()
        return result
    }

    /// Folds one 64-byte block into `state`.
    private static func compress(
        _ block: UnsafeRawBufferPointer,
        into state: inout State,
        schedule: UnsafeMutableBufferPointer<UInt32>,
        constants: UnsafeBufferPointer<UInt32>
    ) {
        // Index loops rather than range iteration: an unoptimized build walks a range through
        // the generic iterator, which dominated the digest's cost.
        var index = 0
        while index < 16 {
            let offset = index &* 4
            schedule[index] = UInt32(block[offset]) << 24
                | UInt32(block[offset &+ 1]) << 16
                | UInt32(block[offset &+ 2]) << 8
                | UInt32(block[offset &+ 3])
            index &+= 1
        }
        while index < 64 {
            schedule[index] = smallSigma1(schedule[index &- 2])
                &+ schedule[index &- 7]
                &+ smallSigma0(schedule[index &- 15])
                &+ schedule[index &- 16]
            index &+= 1
        }

        var a = state.h0
        var b = state.h1
        var c = state.h2
        var d = state.h3
        var e = state.h4
        var f = state.h5
        var g = state.h6
        var h = state.h7
        index = 0
        while index < 64 {
            let temporary1 = h
                &+ bigSigma1(e)
                &+ ((e & f) ^ (~e & g))
                &+ constants[index]
                &+ schedule[index]
            let temporary2 = bigSigma0(a) &+ ((a & b) ^ (a & c) ^ (b & c))
            h = g
            g = f
            f = e
            e = d &+ temporary1
            d = c
            c = b
            b = a
            a = temporary1 &+ temporary2
            index &+= 1
        }
        state.h0 = state.h0 &+ a
        state.h1 = state.h1 &+ b
        state.h2 = state.h2 &+ c
        state.h3 = state.h3 &+ d
        state.h4 = state.h4 &+ e
        state.h5 = state.h5 &+ f
        state.h6 = state.h6 &+ g
        state.h7 = state.h7 &+ h
    }

    private static func rotateRight(_ value: UInt32, by amount: UInt32) -> UInt32 {
        (value >> amount) | (value << (32 - amount))
    }

    private static func bigSigma0(_ value: UInt32) -> UInt32 {
        rotateRight(value, by: 2) ^ rotateRight(value, by: 13) ^ rotateRight(value, by: 22)
    }

    private static func bigSigma1(_ value: UInt32) -> UInt32 {
        rotateRight(value, by: 6) ^ rotateRight(value, by: 11) ^ rotateRight(value, by: 25)
    }

    private static func smallSigma0(_ value: UInt32) -> UInt32 {
        rotateRight(value, by: 7) ^ rotateRight(value, by: 18) ^ (value >> 3)
    }

    private static func smallSigma1(_ value: UInt32) -> UInt32 {
        rotateRight(value, by: 17) ^ rotateRight(value, by: 19) ^ (value >> 10)
    }
}
