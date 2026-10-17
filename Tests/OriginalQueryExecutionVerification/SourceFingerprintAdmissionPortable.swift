@main
struct SourceFingerprintAdmissionPortable {
    static func main() throws {
        try SourceFingerprintAdmissionChecks.canonicalBytesAndOriginalDigest()
        print("PASS source-fingerprint canonical-bytes-and-original-digest")
        try SourceFingerprintAdmissionChecks.exactWorkStorageAndPrefix()
        print("PASS source-fingerprint exact-work-storage-and-prefix")
        try SourceFingerprintAdmissionChecks.warmMemoAndRetainedSourceCannotWaiveAdmission()
        print("PASS source-fingerprint warm-memo-and-retained-owner")
        try SourceFingerprintAdmissionChecks.entryBlockAndTerminalCancellationKeepTheirCause()
        print("PASS source-fingerprint entry-block-and-terminal-cancellation")
    }
}
