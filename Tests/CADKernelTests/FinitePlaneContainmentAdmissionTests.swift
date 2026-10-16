import Testing

@Suite("Finite plane containment admission", .timeLimit(.minutes(1)))
struct FinitePlaneContainmentAdmissionTests {
    @Test func finitePlaneProximityUsesRetainedMaterialAndSource() throws {
        try FinitePlaneContainmentAdmissionChecks.finitePlaneProximityUsesRetainedMaterialAndSource()
    }
    @Test func finiteBoundsAndOutsideToleranceKeepTheirCompletePath() throws {
        try FinitePlaneContainmentAdmissionChecks.finiteBoundsAndOutsideToleranceKeepTheirCompletePath()
    }
    @Test func primitiveProjectionPreservesCallerWorkAndCancellation() throws {
        try FinitePlaneContainmentAdmissionChecks.primitiveProjectionPreservesCallerWorkAndCancellation()
    }
}
