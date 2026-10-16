import Testing

@Suite("Original affine plane-lift repair continuity", .timeLimit(.minutes(1)))
struct BRepRepairAffineLiftContinuityTests {
    @Test func bothAxesDirectionsAndClosedSubdomainsRetainWholeCorrespondence() throws {
        try BRepRepairAffineLiftChecks.axesDirectionsSubdomainsAndWholeBound()
    }
    @Test func invalidScopesAndUnrelatedLawsCannotMintContinuity() throws {
        try BRepRepairAffineLiftChecks.scopeAndUnsupportedGuards()
    }
    @Test func callerRefusalsAndCancellationPreserveTheReceiptBoundary() throws {
        try BRepRepairAffineLiftChecks.callerRefusalAndCancellation()
    }
    @Test func retainedSourceSurvivesCallerMutationAndForeignReadmission() throws {
        try BRepRepairAffineLiftChecks.retainedLifetimeAndNonunitStoredPlane()
    }
}
