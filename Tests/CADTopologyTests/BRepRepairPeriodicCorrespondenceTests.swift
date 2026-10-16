import Testing

@Suite("Validated original periodic repair correspondence", .timeLimit(.minutes(1)))
struct BRepRepairPeriodicCorrespondenceTests {
    @Test func validatedShiftsRetainWholeExactZeroAndOriginalWrappers() throws {
        try PeriodicRepairCorrespondenceChecks.translatedOriginalHasWholeExactZero()
    }
    @Test func invalidShiftForeignBaseAndCallerSourceCannotMintZero() throws {
        try PeriodicRepairCorrespondenceChecks.invalidShiftForeignBaseAndSourceRefuse()
    }
    @Test func cancellationAndSourceLifetimePreserveTheOriginalPublication() throws {
        try PeriodicRepairCorrespondenceChecks.cancellationAndRetainedSourceLifetime()
    }
}
