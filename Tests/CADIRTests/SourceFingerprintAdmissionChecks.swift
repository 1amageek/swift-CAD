import CADCore
import CADGeometry
@testable import CADIR

/// The same original-source and caller-admission checks run on every target.
enum SourceFingerprintAdmissionChecks {
    struct Failure: Error { let message: String; let line: UInt }
    private enum Stop: Error, Equatable { case cancelled }
    private struct Checkpoints: NumericWorkAdmission {
        var visits = 0
        var stopAt: Int?
        mutating func checkpoint() throws {
            visits += 1
            if visits == stopAt { throw Stop.cancelled }
        }
        mutating func consumeWork(_ units: Int) throws {
            guard units >= 0 else { throw Failure(message: "Negative work.", line: #line) }
        }
        mutating func retainStorage(count: Int, stride: Int) throws {
            guard count >= 0, stride >= 0, !count.multipliedReportingOverflow(by: stride).overflow else {
                throw Failure(message: "Invalid typed storage.", line: #line)
            }
        }
    }
    private static func require(_ condition: Bool, _ message: String, line: UInt = #line) throws {
        guard condition else { throw Failure(message: message, line: line) }
    }
    private static func source(_ units: UnitSystem = .millimeters) -> CADDocument {
        CADDocument(units: units, metadata: .init(name: "Admitted fingerprint",
            createdAtReferenceDate: 0, updatedAtReferenceDate: 0))
    }
    private static func execution(_ budget: OriginalQueryBudget) throws -> OriginalQueryExecution {
        OriginalQueryExecution(budget: budget, limits: try .init(maximumValueDepth: 0,
            maximumCoefficientDepth: 0, remainingSourceDepth: 0, maximumTransportDepth: 0,
            maximumSubdivisionDepth: 0))
    }
    private static func axis(_ error: any Error) -> OriginalQueryResourceAxis? {
        if let failure = error as? OriginalQueryFailure { return failure.context.resource?.axis }
        if case .admissionRejected(let cause)? = error as? ExactScalarFailure { return axis(cause) }
        return nil
    }

    private static func originalCause(_ error: any Error) -> any Error {
        if let failure = error as? OriginalQueryFailure { return originalCause(failure.originalError) }
        if case .admissionRejected(let cause)? = error as? ExactScalarFailure { return originalCause(cause) }
        return error
    }

    private static func memoConstructionPrecedesSourceWork() throws {
        let document = source()
        for rawFingerprint in [false, true] {
            let deniedBudget = try OriginalQueryBudget(workLimit: 0, storageByteLimit: 0)
            var denied = try execution(deniedBudget)
            do {
                if rawFingerprint {
                    _ = try document.sourceFingerprint(tolerance: .standard, using: &denied)
                } else {
                    _ = try ValidatedCADDocument(document, tolerance: .standard, using: &denied)
                }
                throw Failure(message: "A direct source constructor allocated beyond zero storage.", line: #line)
            } catch {
                try require(axis(error) == .storageBytes && deniedBudget.snapshot.work == 0
                    && deniedBudget.snapshot.storageBytes == 0,
                    "Memo storage was not refused before source work or its allocation.")
            }
            let cancelledBudget = try OriginalQueryBudget(checkpoint: { throw Stop.cancelled })
            var cancelled = try execution(cancelledBudget)
            do {
                if rawFingerprint {
                    _ = try document.sourceFingerprint(tolerance: .standard, using: &cancelled)
                } else {
                    _ = try ValidatedCADDocument(document, tolerance: .standard, using: &cancelled)
                }
                throw Failure(message: "Entry cancellation constructed a validated source owner.", line: #line)
            } catch {
                try require(originalCause(error) as? Stop == .cancelled
                    && cancelledBudget.snapshot.work == 0 && cancelledBudget.snapshot.storageBytes == 0,
                    "Source construction changed cancellation or charged before its entry checkpoint.")
            }
        }
        let measuredBudget = try OriginalQueryBudget()
        var measured = try execution(measuredBudget)
        _ = try ValidatedCADDocumentSourceFingerprintMemo(using: &measured)
        let bytes = measuredBudget.snapshot.storageBytes
        try require(bytes > MemoryLayout<ValidatedCADDocumentSourceFingerprintMemo>.stride,
            "Memo admission counted only its class reference.")
        let exactBudget = try OriginalQueryBudget(storageByteLimit: bytes)
        var exact = try execution(exactBudget)
        let memo = try ValidatedCADDocumentSourceFingerprintMemo(using: &exact)
        try require(!memo.hasValue && exactBudget.snapshot.storageBytes == bytes,
            "The complete measured memo owner failed at its exact storage allowance.")
        let shortBudget = try OriginalQueryBudget(storageByteLimit: bytes - 1)
        var short = try execution(shortBudget)
        do {
            _ = try ValidatedCADDocumentSourceFingerprintMemo(using: &short)
            throw Failure(message: "An N-1 memo owner allowance succeeded.", line: #line)
        } catch { try require(axis(error) == .storageBytes, "Memo N-1 lost its exact storage refusal.") }
    }

    static func canonicalBytesAndOriginalDigest() throws {
        let document = source()
        let validated = try ValidatedCADDocument(document, tolerance: .standard)
        let limits = PortableSourceEncodingLimits(maximumBytes: Int.max,
            maximumWork: Int.max, maximumDepth: Int.max)
        var ordinary = try PortableSourceEncoder(limits: limits)
        try ordinary.value(PortableDocumentSourcePayload(document: document))
        let budget = try OriginalQueryBudget()
        var admitted = try execution(budget)
        var encoder = try PortableSourceEncoder(limits: limits)
        try encoder.value(PortableDocumentSourcePayload(document: document), using: &admitted)
        try require(encoder.bytes == ordinary.bytes && encoder.consumedBytes == ordinary.consumedBytes
            && encoder.consumedWork == ordinary.consumedWork, "Canonical source bytes or local work changed.")
        let expected = try validated.sourceFingerprint()
        let rawBudget = try OriginalQueryBudget()
        var rawCaller = try execution(rawBudget)
        try require(try document.sourceFingerprint(tolerance: .standard, using: &rawCaller) == expected
            && rawBudget.snapshot.work > 1, "The raw-document public entry lost source validation or its caller.")
        let deniedRawBudget = try OriginalQueryBudget(workLimit: 1)
        var deniedRaw = try execution(deniedRawBudget)
        do {
            _ = try document.sourceFingerprint(tolerance: .standard, using: &deniedRaw)
            throw Failure(message: "Raw source validation reset its caller work.", line: #line)
        } catch { try require(axis(error) == .work, "Raw validation lost its independent typed work refusal.") }
        try require(try validated.sourceFingerprint(using: &admitted) == expected,
            "Direct encoding changed the original fingerprint.")
        try require(try SHA256Digest.sourceHexDigest(for: Array("abc".utf8), using: &admitted)
            == "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad",
            "The admitted SHA-256 does not match the independent published vector.")
        var displayOnly = document
        displayOnly.metadata.name = "Different display metadata"
        try require(try displayOnly.sourceFingerprint(tolerance: .standard) == expected,
            "Display-only document fields entered original source authority.")
        try require(try source(.meters).sourceFingerprint(tolerance: .standard) != expected,
            "The original units were lost from source authority.")
    }

    static func exactWorkStorageAndPrefix() throws {
        let validated = try ValidatedCADDocument(source(), tolerance: .standard)
        let measuredBudget = try OriginalQueryBudget()
        var measured = try execution(measuredBudget)
        let expected = try validated.sourceFingerprint(using: &measured)
        let work = measuredBudget.snapshot.work, bytes = measuredBudget.snapshot.storageBytes
        try require(work > 1 && bytes > 1, "The original traversal and hash were not admitted.")
        let exactBudget = try OriginalQueryBudget(workLimit: work, storageByteLimit: bytes)
        var exact = try execution(exactBudget)
        try require(try validated.sourceFingerprint(using: &exact) == expected
            && exactBudget.snapshot.work == work && exactBudget.snapshot.storageBytes == bytes,
            "Exact measured caller allowances did not reproduce the same source fingerprint.")
        for storage in [false, true] {
            let limited = try OriginalQueryBudget(workLimit: storage ? work : work - 1,
                storageByteLimit: storage ? bytes - 1 : bytes)
            var reader = try execution(limited)
            do {
                _ = try validated.sourceFingerprint(using: &reader)
                throw Failure(message: "An N-1 source fingerprint allowance succeeded.", line: #line)
            } catch {
                try require(axis(error) == (storage ? .storageBytes : .work),
                    "N-1 did not preserve the independent typed caller refusal.")
            }
        }
        var localDepth = try execution(OriginalQueryBudget())
        do {
            _ = try validated.sourceFingerprint(encodingLimits: .init(maximumBytes: Int.max,
                maximumWork: Int.max, maximumDepth: 1), using: &localDepth)
            throw Failure(message: "The local source-encoding depth was waived.", line: #line)
        } catch PortableSourceEncodingError.resourceLimitExceeded(let reason) {
            try require(reason == "Source encoding depth.", "Encoding depth was remapped to a geometric source axis.")
        }
        let prefixedBudget = try OriginalQueryBudget(workLimit: work + 7, storageByteLimit: bytes + 13)
        var prefixed = try execution(prefixedBudget)
        try prefixed.consumeWork(7)
        try prefixed.retainStorage(count: 13, stride: MemoryLayout<UInt8>.stride)
        try require(try validated.sourceFingerprint(using: &prefixed) == expected
            && prefixedBudget.snapshot.work == work + 7 && prefixedBudget.snapshot.storageBytes == bytes + 13,
            "A paid prefix was reset or charged into a different caller.")
    }

    static func warmMemoAndRetainedSourceCannotWaiveAdmission() throws {
        func retained() throws -> ValidatedCADDocument {
            try ValidatedCADDocument(source(), tolerance: .standard)
        }
        let original = try retained(), copy = original
        let expected = try original.sourceFingerprint()
        try require(original.sourceFingerprintMemo.hasValue && copy.sourceFingerprintMemo.hasValue,
            "Immutable copies lost their shared original memo owner.")
        let budget = try OriginalQueryBudget(workLimit: 0)
        var denied = try execution(budget)
        do {
            _ = try copy.sourceFingerprint(using: &denied)
            throw Failure(message: "A warm memo waived caller work.", line: #line)
        } catch { try require(axis(error) == .work, "The warm-memo refusal lost its typed work cause.") }
        var reader = try execution(OriginalQueryBudget())
        let cache = CacheSourceFingerprint.validatedDocument(copy)
        try require(try cache.resolve(using: &reader) == expected,
            "The retained cache/source owner changed the original fingerprint.")
        let coldBudget = try OriginalQueryBudget()
        var cold = try execution(coldBudget)
        _ = try original.sourceFingerprint(using: &cold)
        try require(reader.budget.snapshot.work == coldBudget.snapshot.work,
            "Cache resolution waived or repeated the admitted original traversal.")
        var changed = original.document
        changed.units = .meters
        try require(try copy.sourceFingerprint() == expected
            && changed.sourceFingerprint(tolerance: .standard) != expected,
            "Mutating a source copy changed retained original ownership.")
    }

    static func entryBlockAndTerminalCancellationKeepTheirCause() throws {
        try memoConstructionPrecedesSourceWork()
        let validated = try ValidatedCADDocument(source(), tolerance: .standard)
        var entry = Checkpoints(stopAt: 1)
        do {
            _ = try validated.sourceFingerprint(using: &entry)
            throw Failure(message: "Entry cancellation published a fingerprint.", line: #line)
        } catch Stop.cancelled {}
        try require(!validated.sourceFingerprintMemo.hasValue,
            "Failed direct validation published an ordinary memo.")
        let bytes = [UInt8](repeating: 7, count: 256)
        var block = Checkpoints(stopAt: 2)
        do {
            _ = try SHA256Digest.sourceHexDigest(for: bytes, using: &block)
            throw Failure(message: "Block cancellation published a digest.", line: #line)
        } catch Stop.cancelled {}
        try require(block.visits == 2, "The actual SHA block checkpoint did not reach the caller.")
        var baseline = Checkpoints()
        _ = try validated.sourceFingerprint(using: &baseline)
        var terminal = Checkpoints(stopAt: baseline.visits)
        do {
            _ = try validated.sourceFingerprint(using: &terminal)
            throw Failure(message: "Terminal cancellation published a fingerprint.", line: #line)
        } catch Stop.cancelled {}
        try require(!validated.sourceFingerprintMemo.hasValue,
            "A cancelled admitted fingerprint mutated the memo.")
    }
}
