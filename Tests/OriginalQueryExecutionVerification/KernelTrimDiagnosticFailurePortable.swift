import CADCore
import CADGeometry
import CADModeling
import CADTopology
@testable import CADKernel

@main
struct KernelTrimDiagnosticFailurePortable {
    static func main() throws {
        try KernelTrimDiagnosticFailureChecks.crossingLinesRetainTheirNonemptyContact()
        print("PASS crossingLinesRetainTheirNonemptyContact")
        try KernelTrimDiagnosticFailureChecks.trimContactLowerWorkRefusalRetainsItsOriginalClassification()
        print("PASS trimContactLowerWorkRefusalRetainsItsOriginalClassification")
        try KernelTrimDiagnosticFailureChecks.lowerTrimCallerCancellationRetainsItsOriginalCause()
        print("PASS lowerTrimCallerCancellationRetainsItsOriginalCause")
    }
}
