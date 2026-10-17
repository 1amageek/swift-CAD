import Testing

@Suite("Original B-rep cache source caller admission", .timeLimit(.minutes(1)))
struct BRepCacheSourceAdmissionTests {
    @Test func canonicalOriginalContentIgnoresRegeneratedTopologyIDs() throws {
        try BRepCacheSourceAdmissionChecks.canonicalOriginalContentIgnoresRegeneratedTopologyIDs()
    }
    @Test func exactCumulativeWorkAndStorageBoundaries() throws {
        try BRepCacheSourceAdmissionChecks.exactCumulativeWorkAndStorageBoundaries()
    }
    @Test func nestedFailuresRetainTheirOriginalTypedCause() throws {
        try BRepCacheSourceAdmissionChecks.nestedFailuresRetainTheirOriginalTypedCause()
    }
    @Test func cancellationAndRetainedSourceLifetime() throws {
        try BRepCacheSourceAdmissionChecks.cancellationAndRetainedSourceLifetime()
    }
}
