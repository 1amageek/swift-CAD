import CADCore
import CADGeometry

/// Token serialization retains immutable authority in the actual common budget.
struct DrawingSilhouetteJSONAccounting: NativeJSONAccounting {
    let drawing: DrawingExchangeOwner
    let silhouette: SurfaceSilhouetteContext
    var limits: ExchangeResourceLimits { drawing.resources.limits }
    var format: ExchangeFileFormat { drawing.resources.format }
    var byteCount: Int { drawing.resources.byteCount }
    func checkTime() throws { try drawing.check() }
    func validateNestingDepth(_ depth: Int) throws { try drawing.resources.validateNestingDepth(depth) }
    func charge(entities: Int, work: Int, bytes: Int) throws {
        try checkTime()
        guard entities >= 0, work >= 0, bytes >= 0,
            silhouette.budget === drawing.resources.originalBudget else {
            throw ExportError.invalidMesh("Negative or foreign silhouette JSON admission.")
        }
        let words = bytes / 4 + (bytes % 4 == 0 ? 0 : 1)
        let totalWork = work.addingReportingOverflow(words)
        guard !totalWork.overflow else { throw ExactScalarFailure.countOverflow }
        try silhouette.budget.chargeSource(records: entities, work: totalWork.partialValue,
            storageBytes: bytes, contributions: silhouette.retainedContributions)
    }
    func recordIterations(_ count: Int) throws { try charge(entities: 0, work: count, bytes: 0) }
    func recordBytes(_ count: Int, label: String) throws { try charge(entities: 0, work: 0, bytes: count) }
}
