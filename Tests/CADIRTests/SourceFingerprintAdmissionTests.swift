import Testing

@Suite("Original source fingerprint caller admission", .timeLimit(.minutes(1)))
struct SourceFingerprintAdmissionTests {
    @Test func canonicalBytesAndOriginalDigest() throws {
        try SourceFingerprintAdmissionChecks.canonicalBytesAndOriginalDigest()
    }
    @Test func exactWorkStorageAndPrefix() throws {
        try SourceFingerprintAdmissionChecks.exactWorkStorageAndPrefix()
    }
    @Test func warmMemoAndRetainedSourceCannotWaiveAdmission() throws {
        try SourceFingerprintAdmissionChecks.warmMemoAndRetainedSourceCannotWaiveAdmission()
    }
    @Test func entryBlockAndTerminalCancellationKeepTheirCause() throws {
        try SourceFingerprintAdmissionChecks.entryBlockAndTerminalCancellationKeepTheirCause()
    }
}
