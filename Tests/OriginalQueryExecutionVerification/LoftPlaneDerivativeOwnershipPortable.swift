/// Runs the same ownership controls as the Native Swift Testing wrappers.
@main
struct LoftPlaneDerivativeOwnershipPortable {
    static func main() throws {
        try LoftPlaneDerivativeOwnershipChecks.admittedFactoryRetainsRepeatedSurfaceAfterLocalRelease()
        print("PASS loft original source copy and guarantee lifetime")
        try LoftPlaneDerivativeOwnershipChecks.eachNewCapacityRefusesBeforeCertification(secondReservation: false)
        try LoftPlaneDerivativeOwnershipChecks.eachNewCapacityRefusesBeforeCertification(secondReservation: true)
        print("PASS loft each typed payload capacity refuses before certification")
        try LoftPlaneDerivativeOwnershipChecks.unchangedSourceCasesRetainTheirValuesAndActualLayouts()
        print("PASS loft source cases and actual value layouts")
        try LoftPlaneDerivativeOwnershipChecks.actualConverterUsesExactCumulativeStorageBoundary()
        print("PASS loft actual converter cumulative storage N and N-minus-1")
        try LoftPlaneDerivativeOwnershipChecks.actualConverterFailurePreventsSidePublication()
        print("PASS loft actual converter refusal prevents side publication")
        try LoftPlaneDerivativeOwnershipChecks.actualConverterCancellationPreventsSidePublication()
        print("PASS loft actual converter cancellation and retained source lifetime")
    }
}
