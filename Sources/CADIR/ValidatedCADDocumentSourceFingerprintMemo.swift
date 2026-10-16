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

    func value(_ compute: () throws -> CADDocumentSourceFingerprint) throws -> CADDocumentSourceFingerprint {
        if let existing = read() { return existing }
        return publish(try compute())
    }

    var hasValue: Bool { read() != nil }
}
