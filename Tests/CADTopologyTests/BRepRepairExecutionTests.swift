import Testing

@Suite("Direct B-rep repair execution", .timeLimit(.minutes(1)))
struct BRepRepairExecutionTests {
    @Test func ownershipDeduplicationChangesTheOwnedGraph() throws { try BRepRepairExecutionChecks.ownership() }
    @Test func loopOrderingRestoresOriginalDirectedCharts() throws { try BRepRepairExecutionChecks.loopOrdering() }
    @Test func representationReconstructionUsesTheCompleteIncidentLaw() throws { try BRepRepairExecutionChecks.representation() }
    @Test func wireSewingUsesTheDeterministicRetainedVertex() throws { try BRepRepairExecutionChecks.wireSewing() }
    @Test func duplicateUseRemovalRetainsDifferentDirectedUses() throws { try BRepRepairExecutionChecks.duplicateWire() }
    @Test func smallEdgeCollapseRecordsTheWholeOriginalImage() throws { try BRepRepairExecutionChecks.smallEdge() }
    @Test func singularBoundaryRestoresNonzeroParameterIncidence() throws { try BRepRepairExecutionChecks.singularBoundary() }
    @Test func periodicRestorationRetainsTheExactPeriodTranslation() throws { try BRepRepairExecutionChecks.periodicCharts() }
    @Test func duplicateFaceRemovalDeletesOnlyNewlyOrphanedSources() throws { try BRepRepairExecutionChecks.duplicateFace() }
    @Test func shellEdgeSewingRestoresTwoOppositeIncidentUses() throws { try BRepRepairExecutionChecks.shellSewing() }
    @Test func shellOrientationRestoresTheOneDamagedFace() throws { try BRepRepairExecutionChecks.shellOrientation() }
    @Test func solidOrientationRestoresMaterialRoleAndPositiveVolume() throws { try BRepRepairExecutionChecks.solidOrientation() }
    @Test func pruningRemovesOnlyBodyUnreachableSources() throws { try BRepRepairExecutionChecks.pruning() }
    @Test func publicRequestsRefuseEveryMissingRequiredScope() throws { try BRepRepairExecutionChecks.requestScopes() }
    @Test func exactResourceBoundariesPreserveIndependentAxes() throws { try BRepRepairExecutionChecks.resourceBoundariesAndIndependentAxes() }
    @Test func entryInteriorTerminalCancellationAndSourceLifetime() throws { try BRepRepairExecutionChecks.cancellationAndLifetime() }
    @Test func injectedValidationUsesTheSameExecutionAndPreservesAbortCause() throws {
        try BRepRepairExecutionChecks.injectedWitnessAndAbortPreserveOriginalCause()
    }
    @Test func cumulativeCollapseAndTerminalAbortRetainTheOriginalSource() throws {
        try BRepRepairExecutionChecks.cumulativeCollapseAndAbortRetainTheTaskOriginalSource()
    }
    @Test func sourceDepthRemainsIndependentOfAlgebraSelection() throws {
        try BRepRepairExecutionChecks.sourceDepthIsIndependentFromAlgebraSelection()
    }
    @Test func edgeLengthUsesTheRealInjectedArcLengthWitness() throws { try BRepRepairEdgeLengthChecks.intervalsAndRealInjectedResolver() }
    @Test func edgeLengthPreservesResourcesCancellationAndTypedReferences() throws {
        try BRepRepairEdgeLengthChecks.resourcesCancellationAndMissingReferences()
    }
}
