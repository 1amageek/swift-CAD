import CADCore
import CADGeometry
import CADTopology

// Compile with the shared CADTopologyTests checks and -D VOLUME_MOMENT_PORTABLE.
@main
struct VolumeMomentLoopAdmissionPortable {
    static func main() throws {
        try VolumeMomentLoopAdmissionChecks.retainedCubeReceiptAdmitsAllTenIndependentMoments()
        print("PASS retainedCubeReceiptAdmitsAllTenIndependentMoments")
        try VolumeMomentLoopAdmissionChecks.queryUsesExactCumulativeWorkAndStorageBoundaries()
        print("PASS queryUsesExactCumulativeWorkAndStorageBoundaries")
        try VolumeMomentLoopAdmissionChecks.queryPreservesIndependentIncomingAlgebraAxes()
        print("PASS queryPreservesIndependentIncomingAlgebraAxes")
        try VolumeMomentLoopAdmissionChecks.queryRefusesEntryInProgressAndLastCheckpointCancellation()
        print("PASS queryRefusesEntryInProgressAndLastCheckpointCancellation")
        try VolumeMomentLoopAdmissionChecks.receiptSurvivesAuthoredSourceMutationAndResultOutlivesQuery()
        print("PASS receiptSurvivesAuthoredSourceMutationAndResultOutlivesQuery")
    }
}
