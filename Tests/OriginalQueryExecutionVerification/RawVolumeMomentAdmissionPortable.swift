import CADCore
import CADGeometry
import CADTopology

// Compile both shared check files with -D VOLUME_MOMENT_PORTABLE -D RAW_VOLUME_MOMENT_PORTABLE.
@main
struct RawVolumeMomentAdmissionPortable {
    static func main() throws {
        try RawVolumeMomentAdmissionChecks.ordinaryAndDirectRawCubePublishAllTenMoments()
        print("PASS ordinaryAndDirectRawCubePublishAllTenMoments")
        try RawVolumeMomentAdmissionChecks.rawValidationAndIntegrationShareCallerResourceLimits()
        print("PASS rawValidationAndIntegrationShareCallerResourceLimits")
        try RawVolumeMomentAdmissionChecks.missingBodyRefusesMomentPublication()
        print("PASS missingBodyRefusesMomentPublication")
        try RawVolumeMomentAdmissionChecks.rawQueryRefusesEntryAndInProgressCancellation()
        print("PASS rawQueryRefusesEntryAndInProgressCancellation")
    }
}
