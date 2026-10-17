import CADCore

enum PortableSourceEncodingAdmissionChecks {
    private enum Failure: Error, Equatable { case work, storage, cancelled, overflow
        case assertion(String, Int) }

    /// One invocation-local witness: no stored callback, pointer or shared mutable state.
    private struct Admission: NumericWorkAdmission, ~Copyable {
        var work = 0
        var storage = 0
        var checkpoints = 0
        var workLimit = Int.max
        var storageLimit = Int.max
        var cancelAt: Int? = nil

        mutating func checkpoint() throws {
            checkpoints += 1
            if checkpoints == cancelAt { throw Failure.cancelled }
        }
        mutating func consumeWork(_ units: Int) throws {
            try checkpoint()
            guard units >= 0, units <= workLimit - work else { throw Failure.work }
            work += units
        }
        mutating func retainStorage(count: Int, stride: Int) throws {
            try checkpoint()
            let bytes = count.multipliedReportingOverflow(by: stride)
            guard count >= 0, stride >= 0, !bytes.overflow else { throw Failure.overflow }
            guard bytes.partialValue <= storageLimit - storage else { throw Failure.storage }
            storage += bytes.partialValue
        }
    }

    private struct CollidingKey: PortableSourceEncodable {
        let identity: Int
        func encodeSource<A: NumericWorkAdmission & ~Copyable>(
            to encoder: inout PortableSourceEncoder, using admission: inout A
        ) throws {
            try encoder.tag(0x44, using: &admission)
        }
    }

    private static let limits = PortableSourceEncodingLimits(
        maximumBytes: 1_048_576, maximumWork: 1_048_576, maximumDepth: 64)

    private static func require(_ condition: @autoclosure () -> Bool, line: Int = #line) throws {
        guard condition() else { throw Failure.assertion("Canonical source admission oracle failed.", line) }
    }

    private static func word(_ value: UInt64) -> [UInt8] {
        stride(from: 56, through: 0, by: -8).map { UInt8(truncatingIfNeeded: value >> UInt64($0)) }
    }

    static func canonicalBytesAndLocalMeasurementRemainOriginal() throws {
        var first: [String: Bool] = [:]
        first["z"] = true; first["a"] = false
        var second: [String: Bool] = [:]
        second["a"] = false; second["z"] = true
        var ordinary = try PortableSourceEncoder(limits: limits)
        try ordinary.value(first)
        let expected = [UInt8(0x22)] + word(2)
            + [0x10] + word(1) + [0x61, 0x01]
            + [0x10] + word(1) + [0x7a, 0x02]
        try require(ordinary.bytes == expected)
        var direct = try PortableSourceEncoder(limits: limits)
        var admission = Admission()
        try direct.value(second, using: &admission)
        try require(direct.bytes == expected)
        try require(direct.consumedWork == ordinary.consumedWork)
        try require(direct.consumedBytes == ordinary.consumedBytes)
        try require(admission.work == direct.consumedWork)
        try require(admission.storage == direct.consumedBytes)
        var measuring = Admission()
        let measurement = try PortableSourceEncoder.measure(first, limits: limits, using: &measuring)
        try require(measurement.consumedWork == ordinary.consumedWork)
        try require(measurement.consumedBytes == ordinary.consumedBytes)
        try require(measuring.work == measurement.consumedWork)
        try require(measuring.storage == measurement.consumedBytes)

        var ordered = try PortableSourceEncoder(limits: limits)
        try ordered.value([true, false])
        try require(ordered.bytes == [0x21] + word(2) + [0x02, 0x01])
        var unordered = try PortableSourceEncoder(limits: limits)
        var unorderedAdmission = Admission()
        try unordered.value(Set([UInt8(3), 1, 2]), using: &unorderedAdmission)
        try require(unordered.bytes == [0x23] + word(3) + [0x07, 1, 0x07, 2, 0x07, 3])
        try require(unorderedAdmission.work == unordered.consumedWork)
        try require(unorderedAdmission.storage == unordered.consumedBytes)
        var scalar = try PortableSourceEncoder(limits: limits)
        try scalar.value(-0.0)
        try require(scalar.bytes == [0x08] + word(0x8000_0000_0000_0000))
        var text = try PortableSourceEncoder(limits: limits)
        try text.value("A\0")
        try require(text.bytes == [0x10] + word(2) + [0x41, 0x00])
    }

    static func childKeysShareOneAdmissionAndExactResourceBoundaries() throws {
        let source: [String: [UInt64]] = ["z": [2, 3], "a": [4, 5]]
        var measured = Admission()
        try measured.consumeWork(7)
        try measured.retainStorage(count: 11, stride: 1)
        var encoder = try PortableSourceEncoder(limits: limits)
        try encoder.value(source, using: &measured)
        try require(measured.work == encoder.consumedWork + 7)
        try require(measured.storage == encoder.consumedBytes + 11)
        var cumulative = Admission()
        try cumulative.consumeWork(7)
        try cumulative.retainStorage(count: 11, stride: 1)
        for _ in 0..<2 {
            var sibling = try PortableSourceEncoder(limits: limits)
            try sibling.value(source, using: &cumulative)
        }
        try require(cumulative.work == encoder.consumedWork * 2 + 7)
        try require(cumulative.storage == encoder.consumedBytes * 2 + 11)
        let work = measured.work, storage = measured.storage
        var exact = Admission(workLimit: work, storageLimit: storage)
        try exact.consumeWork(7)
        try exact.retainStorage(count: 11, stride: 1)
        var exactEncoder = try PortableSourceEncoder(limits: limits)
        try exactEncoder.value(source, using: &exact)
        try require(exact.work == work && exact.storage == storage)
        try require(exactEncoder.bytes == encoder.bytes)
        for axis in 0..<2 {
            var bounded = Admission(workLimit: axis == 0 ? work - 1 : work,
                storageLimit: axis == 1 ? storage - 1 : storage)
            try bounded.consumeWork(7)
            try bounded.retainStorage(count: 11, stride: 1)
            var candidate = try PortableSourceEncoder(limits: limits)
            do {
                try candidate.value(source, using: &bounded)
                throw Failure.assertion("An exhausted caller admission published a complete source encoding.", #line)
            } catch let error as Failure {
                try require(error == (axis == 0 ? .work : .storage))
            }
        }
        var noWork = Admission(workLimit: 0)
        var unvisited = try PortableSourceEncoder(limits: limits)
        do {
            try unvisited.value(source, using: &noWork)
            throw Failure.assertion("Zero caller work admitted a source traversal.", #line)
        } catch let error as Failure { try require(error == .work) }
        try require(noWork.work == 0 && noWork.storage == 0 && unvisited.bytes.isEmpty)
        var zero = Admission(storageLimit: 0)
        var empty = try PortableSourceEncoder(limits: limits)
        do {
            try empty.value(source, using: &zero)
            throw Failure.assertion("Zero caller storage admitted canonical map scratch.", #line)
        } catch let error as Failure { try require(error == .storage) }
        try require(empty.bytes.isEmpty)
    }

    static func originalGuardsCollisionAndCancellationRemainExplicit() throws {
        var encoder = try PortableSourceEncoder(limits: limits)
        var admission = Admission(workLimit: 0)
        do {
            try Double.nan.encodeSource(to: &encoder, using: &admission)
            throw Failure.assertion("Nonfinite source encoded successfully.", #line)
        } catch let error as PortableSourceEncodingError { try require(error == .nonfiniteScalar) }
        try require(admission.work == 0 && admission.storage == 0)
        var shallow = try PortableSourceEncoder(limits: .init(
            maximumBytes: 1024, maximumWork: 1024, maximumDepth: 1))
        var depthAdmission = Admission()
        do {
            try shallow.value([true], using: &depthAdmission)
            throw Failure.assertion("A source exceeding its local codec depth encoded successfully.", #line)
        } catch let error as PortableSourceEncodingError {
            try require(error == .resourceLimitExceeded("Source encoding depth."))
        }
        var byteBounded = try PortableSourceEncoder(limits: .init(
            maximumBytes: 1, maximumWork: 1024, maximumDepth: 64))
        var byteAdmission = Admission()
        do {
            try byteBounded.value(UInt64(7), using: &byteAdmission)
            throw Failure.assertion("An encoding exceeding its local byte limit succeeded.", #line)
        } catch let error as PortableSourceEncodingError {
            try require(error == .resourceLimitExceeded("Cumulative source encoding allowance."))
        }
        try require(byteAdmission.storage == 1 && byteAdmission.work == 2)
        var collision = try PortableSourceEncoder(limits: limits)
        var collisionAdmission = Admission()
        do {
            try collision.map([(CollidingKey(identity: 1), true),
                               (CollidingKey(identity: 2), false)], using: &collisionAdmission)
            throw Failure.assertion("Distinct source keys with identical complete encodings were accepted.", #line)
        } catch let error as PortableSourceEncodingError { try require(error == .canonicalKeyCollision) }
        let source: [String: [UInt64]] = ["z": [2, 3], "a": [4, 5]]
        var measuring = Admission()
        var completed = try PortableSourceEncoder(limits: limits)
        try completed.value(source, using: &measuring)
        for checkpoint in [1, measuring.checkpoints / 2, measuring.checkpoints] {
            var cancelled = Admission(cancelAt: checkpoint)
            var candidate = try PortableSourceEncoder(limits: limits)
            do {
                try candidate.value(source, using: &cancelled)
                throw Failure.assertion("A cancelled encoding returned a successful complete value.", #line)
            } catch let error as Failure { try require(error == .cancelled) }
            if checkpoint == 1 { try require(cancelled.work == 0 && cancelled.storage == 0) }
        }
    }
}
