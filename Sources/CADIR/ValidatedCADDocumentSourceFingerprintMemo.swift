import Synchronization

/// The source fingerprint of one validated document, computed at most once and shared by every
/// copy of that `ValidatedCADDocument`.
///
/// A validated document never changes the document it holds, so its fingerprint is a pure
/// function of the memo's owner. The fingerprint is computed outside the lock: two readers racing
/// on the first read both compute the same value and the first stored one is kept, and no reader
/// waits on another's hashing. A failed computation stores nothing and is reported to its caller.
///
/// The store needs `Mutex` (macOS 15, iOS 18, visionOS 2). On the earlier systems the package
/// still supports there is no store, and every read computes the same value again.
final class ValidatedCADDocumentSourceFingerprintMemo: Sendable {
    @available(macOS 15.0, iOS 18.0, visionOS 2.0, *)
    private final class Storage: Sendable {
        let fingerprint = Mutex<CADDocumentSourceFingerprint?>(nil)
    }

    /// A `Storage` wherever `Mutex` exists, nil before.
    private let storage: (any Sendable)?

    init() {
        if #available(macOS 15.0, iOS 18.0, visionOS 2.0, *) {
            storage = Storage()
        } else {
            storage = nil
        }
    }

    /// The stored fingerprint, or the one `compute` produces, which is then stored.
    func value(
        _ compute: () throws -> CADDocumentSourceFingerprint
    ) throws -> CADDocumentSourceFingerprint {
        guard #available(macOS 15.0, iOS 18.0, visionOS 2.0, *),
              let storage = storage as? Storage else {
            return try compute()
        }
        if let fingerprint = storage.fingerprint.withLock({ $0 }) {
            return fingerprint
        }
        let fingerprint = try compute()
        return storage.fingerprint.withLock { stored in
            if let existing = stored {
                return existing
            }
            stored = fingerprint
            return fingerprint
        }
    }

    /// Whether a fingerprint has been stored; read by tests that prove it is computed once.
    var hasValue: Bool {
        guard #available(macOS 15.0, iOS 18.0, visionOS 2.0, *),
              let storage = storage as? Storage else {
            return false
        }
        return storage.fingerprint.withLock { $0 != nil }
    }
}
