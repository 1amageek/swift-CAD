import CADCore
import CADGeometry
import CADTopology
import HashTreeCollections

// Compile with the shared repair checks/builders, the existing cube helper, and VOLUME_MOMENT_PORTABLE.
@main
struct BRepRepairExecutionPortable {
    static func main() throws {
        try BRepRepairExecutionChecks.ownership()
        print("PASS repair ownership graph")
        try BRepRepairExecutionChecks.loopOrdering()
        print("PASS repair directed loop")
        try BRepRepairExecutionChecks.representation()
        print("PASS repair whole-source reconstruction and unsupported inverse refusal")
        try BRepRepairExecutionChecks.wireSewing()
        print("PASS repair deterministic vertex sewing")
        try BRepRepairExecutionChecks.duplicateWire()
        print("PASS repair duplicate use and reversed control")
        try BRepRepairExecutionChecks.smallEdge()
        print("PASS repair whole-image small edge")
        try BRepRepairExecutionChecks.singularBoundary()
        print("PASS repair original singular parameter incidence")
        try BRepRepairExecutionChecks.periodicCharts()
        print("PASS repair intrinsic periodic chart translation")
        try BRepRepairExecutionChecks.duplicateFace()
        print("PASS repair duplicate face source pruning")
        try BRepRepairExecutionChecks.shellSewing()
        print("PASS repair canonical shell edge")
        try BRepRepairExecutionChecks.shellOrientation()
        print("PASS repair shell face orientation")
        try BRepRepairExecutionChecks.solidOrientation()
        print("PASS repair positive material shell orientation")
        try BRepRepairExecutionChecks.pruning()
        print("PASS repair unreachable source pruning")
        try BRepRepairExecutionChecks.requestScopes()
        print("PASS repair public required-scope guards")
        try BRepRepairExecutionChecks.resourceBoundariesAndIndependentAxes()
        print("PASS repair cumulative exact N and N-1 and independent axes")
        try BRepRepairExecutionChecks.cancellationAndLifetime()
        print("PASS repair entry/interior/terminal cancellation and source lifetime")
        try BRepRepairExecutionChecks.injectedWitnessAndAbortPreserveOriginalCause()
        print("PASS repair injected direct validator, abort and overflow cause")
        try BRepRepairExecutionChecks.cumulativeCollapseAndAbortRetainTheTaskOriginalSource()
        print("PASS repair cumulative original collapse and terminal abort")
        try BRepRepairExecutionChecks.sourceDepthIsIndependentFromAlgebraSelection()
        print("PASS repair source depth independent of rational algebra selection")
        try BRepRepairEdgeLengthChecks.intervalsAndRealInjectedResolver()
        print("PASS repair edge length real direct witness and native/periodic/singular intervals")
        try BRepRepairEdgeLengthChecks.resourcesCancellationAndMissingReferences()
        print("PASS repair edge length exact resources, cancellation and typed references")
        try BRepRepairRollbackChecks.originalDisplacementRollbackRestoresBothCandidateAndCollapsedLedger()
        print("PASS repair original displacement rollback, candidate and collapsed ledger restoration")
        try BRepRepairAffineLiftChecks.run()
        print("PASS repair original affine plane lift continuity, correspondence and caller guards")
        try PeriodicRepairCorrespondenceChecks.run()
        print("PASS repair validated periodic correspondence, source scope and terminal cancellation")
    }
}
