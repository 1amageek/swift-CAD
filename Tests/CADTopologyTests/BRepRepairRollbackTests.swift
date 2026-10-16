import Testing

@Suite("Repair task-original rollback", .timeLimit(.minutes(1)))
struct BRepRepairRollbackTests {
    @Test
    func displacementRollbackRestoresCandidateLedgerAndSpentCharges() throws {
        try BRepRepairRollbackChecks.originalDisplacementRollbackRestoresBothCandidateAndCollapsedLedger()
    }
}
