import CADCore
import CADGeometry
import CADTopology
import CADKernel

// Compile with the shared moment cube/check file and -D VOLUME_MOMENT_PORTABLE.
@main
struct MassPropertyDirectAdmissionPortable {
    static func main() throws {
        try MassPropertyDirectAdmissionChecks.actualPublicEntriesPreserveMassTensorAndCallerAttribution()
        print("PASS actualPublicEntriesPreserveMassTensorAndCallerAttribution")
        try MassPropertyDirectAdmissionChecks.repeatedOccurrencesAndOriginalPlacementsPreserveComposition()
        print("PASS repeatedOccurrencesAndOriginalPlacementsPreserveComposition")
        try MassPropertyDirectAdmissionChecks.callerResourcesAndCancellationRefusePublication()
        print("PASS callerResourcesAndCancellationRefusePublication")
        try MassPropertyDirectAdmissionChecks.evaluatedSourceAndPublishedResultRetainTheirOwners()
        print("PASS evaluatedSourceAndPublishedResultRetainTheirOwners")
        try MassPropertyDirectAdmissionChecks.authoredDensityAssignmentFeedsTheDirectMassConsumer()
        print("PASS authoredDensityAssignmentFeedsTheDirectMassConsumer")
    }
}
