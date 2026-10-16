import CADCore
import CADGeometry
import CADTopology

// Compile with the same shared checks and VolumeMomentLoopAdmissionTests,
// defining VOLUME_MOMENT_PORTABLE to exclude only the existing Testing wrapper.
@main
struct VolumeCallerAdmissionPortable {
    static func main() throws {
        try VolumeCallerAdmissionChecks.publicVolumesRetainTheirValuesAndMandatoryLowerCost()
        print("PASS publicVolumesRetainTheirValuesAndMandatoryLowerCost")
        try VolumeCallerAdmissionChecks.exactCumulativeWorkAndStorageRefuseShortBudgets()
        print("PASS exactCumulativeWorkAndStorageRefuseShortBudgets")
        try VolumeCallerAdmissionChecks.entryInProgressAndLastCheckpointCancellationPropagate()
        print("PASS entryInProgressAndLastCheckpointCancellationPropagate")
        try VolumeCallerAdmissionChecks.missingReferencesAndSourceLifetimeRemainExplicit()
        print("PASS missingReferencesAndSourceLifetimeRemainExplicit")
    }
}
