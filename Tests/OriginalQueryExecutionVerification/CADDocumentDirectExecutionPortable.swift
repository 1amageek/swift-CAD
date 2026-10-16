import CADCore
import CADGeometry
import CADIR

@main
struct CADDocumentDirectExecutionPortable {
    static func main() throws {
        try CADDocumentDirectExecutionChecks.validNonemptyDocumentPreservesOriginalValidation()
        print("PASS document complete original validation")
        try CADDocumentDirectExecutionChecks.zeroCallerWorkRefusesWholeDocumentPublication()
        print("PASS document caller work refusal")
        try CADDocumentDirectExecutionChecks.zeroCallerStorageRefusesWholeDocumentPublication()
        print("PASS document caller typed storage refusal")
        try CADDocumentDirectExecutionChecks.measuredInteriorCallerCancellationRefusesPublication()
        print("PASS document interior caller cancellation")
        try CADDocumentDirectExecutionChecks.measuredExactWorkAndStorageCeilings()
        print("PASS document exact work and storage ceilings")
        try CADDocumentDirectExecutionChecks.independentSourceAncestryAndNumericAxes()
        print("PASS document independent source and numeric axes")
        try CADDocumentDirectExecutionChecks.selectedContributionAndScopeRestoration()
        print("PASS document selected contribution scope")
        try CADDocumentDirectExecutionChecks.originalInvalidOrderAndCopyLifetime()
        print("PASS document original invalid order and copy lifetime")
        try CADDocumentDirectExecutionChecks.terminalCallerCancellationRefusesPublication()
        print("PASS document terminal caller cancellation")
        try CADDocumentDirectExecutionChecks.structuralHashAndFixedScratchUseCallerAdmission()
        print("PASS document structural hash and fixed scratch admission")
    }
}
