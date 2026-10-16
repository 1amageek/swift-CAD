import Testing

@Suite("Public volume caller admission", .timeLimit(.minutes(1)))
struct VolumeCallerAdmissionTests {
    @Test func publicVolumesRetainTheirValuesAndMandatoryLowerCost() throws {
        try VolumeCallerAdmissionChecks.publicVolumesRetainTheirValuesAndMandatoryLowerCost()
    }
    @Test func exactCumulativeWorkAndStorageRefuseShortBudgets() throws {
        try VolumeCallerAdmissionChecks.exactCumulativeWorkAndStorageRefuseShortBudgets()
    }
    @Test func entryInProgressAndLastCheckpointCancellationPropagate() throws {
        try VolumeCallerAdmissionChecks.entryInProgressAndLastCheckpointCancellationPropagate()
    }
    @Test func missingReferencesAndSourceLifetimeRemainExplicit() throws {
        try VolumeCallerAdmissionChecks.missingReferencesAndSourceLifetimeRemainExplicit()
    }
}
