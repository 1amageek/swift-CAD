import CADCore
import Synchronization

/// Immutable document copies share one memo; failed computations store nothing.
/// Hashing remains outside the mutex.
final class ValidatedCADDocumentSourceFingerprintMemo: Sendable {
    private final class Storage: Sendable {
        let fingerprint = Mutex<CADDocumentSourceFingerprint?>(nil)
    }

    private let read: @Sendable () -> CADDocumentSourceFingerprint?
    private let publish: @Sendable (CADDocumentSourceFingerprint) -> CADDocumentSourceFingerprint

    init() {
        let storage = Storage()
        read = { storage.fingerprint.withLock { $0 } }
        publish = { candidate in
            storage.fingerprint.withLock { stored in
                if let existing = stored { return existing }
                stored = candidate
                return candidate
            }
        }
    }

    /// Admit the actual stored owner, inline mutex and retained closure payloads
    /// before the existing constructor creates any of them. Runtime allocation
    /// buckets and optimizer capture elision are not inferred from reference size.
    convenience init<A: NumericWorkAdmission & ~Copyable>(using admission: inout A) throws {
        typealias Read = @Sendable () -> CADDocumentSourceFingerprint?
        typealias Publish = @Sendable (CADDocumentSourceFingerprint) -> CADDocumentSourceFingerprint
        try admission.checkpoint()
        try admission.retainStorage(count: 1, stride: MemoryLayout<ValidatedCADDocumentSourceFingerprintMemo>.stride)
        // Four managed owners: memo, Storage, and the two closure capture contexts.
        try admission.retainStorage(count: 4, stride: MemoryLayout<(UnsafeRawPointer, UnsafeRawPointer)>.stride)
        try admission.retainStorage(count: 1, stride: MemoryLayout<Mutex<CADDocumentSourceFingerprint?>>.stride)
        try admission.retainStorage(count: 1, stride: MemoryLayout<Read>.stride)
        try admission.retainStorage(count: 1, stride: MemoryLayout<Publish>.stride)
        try admission.retainStorage(count: 2, stride: MemoryLayout<Storage>.stride)
        try admission.checkpoint()
        self.init()
        try admission.checkpoint()
    }

    func value(_ compute: () throws -> CADDocumentSourceFingerprint) throws -> CADDocumentSourceFingerprint {
        if let existing = read() { return existing }
        return publish(try compute())
    }

    var hasValue: Bool { read() != nil }
}
