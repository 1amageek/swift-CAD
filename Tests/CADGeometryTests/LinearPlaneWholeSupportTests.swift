import Testing

@Suite("Original line and whole-plane public relation", .serialized, .timeLimit(.minutes(1)))
struct LinearPlaneWholeSupportTests {
    @Test func finiteAndOrdinaryParity() throws { try LinearPlaneWholeSupportChecks.finiteAndOrdinaryParity() }
    @Test func endpointEmptyAndParallel() throws { try LinearPlaneWholeSupportChecks.endpointEmptyAndParallel() }
    @Test func containedAndRequestedUV() throws { try LinearPlaneWholeSupportChecks.containedAndRequestedUV() }
    @Test func nonsquareNormalAndScale() throws { try LinearPlaneWholeSupportChecks.nonsquareNormalAndScale() }
    @Test func exactWorkAndStorageBoundaries() throws { try LinearPlaneWholeSupportChecks.exactWorkAndStorageBoundaries() }
    @Test func selectedScopeAndIndependentAxes() throws { try LinearPlaneWholeSupportChecks.selectedScopeAndIndependentAxes() }
    @Test func cancellationAtEntryInteriorAndPublication() throws { try LinearPlaneWholeSupportChecks.cancellationAtEntryInteriorAndPublication() }
    @Test func retainedSourceLifetimeAndCOW() throws { try LinearPlaneWholeSupportChecks.retainedSourceLifetimeAndCOW() }
}
