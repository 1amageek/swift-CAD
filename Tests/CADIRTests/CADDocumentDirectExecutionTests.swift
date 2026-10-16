import Testing

@Suite("Complete CADDocument caller execution", .timeLimit(.minutes(1)))
struct CADDocumentDirectExecutionTests {
    @Test func validNonemptyDocumentPreservesOriginalValidation() throws {
        try CADDocumentDirectExecutionChecks.validNonemptyDocumentPreservesOriginalValidation()
    }
    @Test func zeroCallerWorkRefusesWholeDocumentPublication() throws {
        try CADDocumentDirectExecutionChecks.zeroCallerWorkRefusesWholeDocumentPublication()
    }
    @Test func zeroCallerStorageRefusesWholeDocumentPublication() throws {
        try CADDocumentDirectExecutionChecks.zeroCallerStorageRefusesWholeDocumentPublication()
    }
    @Test func measuredInteriorCallerCancellationRefusesPublication() throws {
        try CADDocumentDirectExecutionChecks.measuredInteriorCallerCancellationRefusesPublication()
    }
    @Test func measuredExactWorkAndStorageCeilings() throws {
        try CADDocumentDirectExecutionChecks.measuredExactWorkAndStorageCeilings()
    }

    @Test func independentSourceAncestryAndNumericAxes() throws {
        try CADDocumentDirectExecutionChecks.independentSourceAncestryAndNumericAxes()
    }

    @Test func selectedContributionAndScopeRestoration() throws {
        try CADDocumentDirectExecutionChecks.selectedContributionAndScopeRestoration()
    }

    @Test func originalInvalidOrderAndCopyLifetime() throws {
        try CADDocumentDirectExecutionChecks.originalInvalidOrderAndCopyLifetime()
    }

    @Test func terminalCallerCancellationRefusesPublication() throws {
        try CADDocumentDirectExecutionChecks.terminalCallerCancellationRefusesPublication()
    }

    @Test func structuralHashAndFixedScratchUseCallerAdmission() throws {
        try CADDocumentDirectExecutionChecks.structuralHashAndFixedScratchUseCallerAdmission()
    }

}
