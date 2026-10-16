import Testing

@Suite("Loft retained plane derivative publication")
struct LoftPlaneDerivativeOwnershipTests {
    @Test(.timeLimit(.minutes(1)))
    func admittedFactoryRetainsRepeatedSurfaceAfterLocalRelease() throws {
        try LoftPlaneDerivativeOwnershipChecks.admittedFactoryRetainsRepeatedSurfaceAfterLocalRelease()
    }

    @Test(.timeLimit(.minutes(1)), arguments: [false, true])
    func eachNewCapacityRefusesBeforeCertification(secondReservation: Bool) throws {
        try LoftPlaneDerivativeOwnershipChecks.eachNewCapacityRefusesBeforeCertification(secondReservation: secondReservation)
    }

    @Test(.timeLimit(.minutes(1)))
    func unchangedSourceCasesRetainTheirValuesAndActualLayouts() throws {
        try LoftPlaneDerivativeOwnershipChecks.unchangedSourceCasesRetainTheirValuesAndActualLayouts()
    }

    @Test(.timeLimit(.minutes(1)))
    func actualConverterUsesExactCumulativeStorageBoundary() throws {
        try LoftPlaneDerivativeOwnershipChecks.actualConverterUsesExactCumulativeStorageBoundary()
    }

    @Test(.timeLimit(.minutes(1)))
    func actualConverterFailurePreventsSidePublication() throws {
        try LoftPlaneDerivativeOwnershipChecks.actualConverterFailurePreventsSidePublication()
    }

    @Test(.timeLimit(.minutes(1)))
    func actualConverterCancellationPreventsSidePublication() throws {
        try LoftPlaneDerivativeOwnershipChecks.actualConverterCancellationPreventsSidePublication()
    }
}
