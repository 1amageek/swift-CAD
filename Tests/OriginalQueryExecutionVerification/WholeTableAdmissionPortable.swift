import CADModeling

@main
struct WholeTableAdmissionPortable {
    static func main() throws {
        try WholeTableAdmissionChecks.completeRootsRetainOriginalUnitsAndValues()
        print("PASS table complete roots and original quantities")
        try WholeTableAdmissionChecks.originalRejectionsKeepTheirOrderAndCause()
        print("PASS table original failure order and cause")
        try WholeTableAdmissionChecks.exactWorkAndTypedStorageCeilings()
        print("PASS table exact work and typed storage ceilings")
        try WholeTableAdmissionChecks.independentSourceAndValueDepths()
        print("PASS table independent source and value depths")
        try WholeTableAdmissionChecks.selectedContributionsAndPrefixRemainCumulative()
        print("PASS table selected cumulative caller scope")
        try WholeTableAdmissionChecks.entryInteriorAndFinalCancellationPublishNothing()
        print("PASS table entry interior and final cancellation")
        try WholeTableAdmissionChecks.outputSurvivesSourceAndCallerRelease()
        print("PASS table source release and independent reader")
        try WholeTableAdmissionChecks.legacyProviderExplicitlyRefusesDirectCapability()
        print("PASS table legacy provider explicit direct refusal")
    }
}
