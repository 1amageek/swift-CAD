import CADCore
import CADGeometry

/// Token serialization borrows both existing owners through the lower admission.
struct DrawingSilhouetteJSONAccounting: NativeJSONAccounting {
    let drawing: DrawingExchangeUsage
    let silhouette: SurfaceSilhouetteUsage
    var limits: ExchangeResourceLimits { drawing.resources.limits }
    var format: ExchangeFileFormat { drawing.resources.format }
    var byteCount: Int { drawing.resources.byteCount }
    func checkTime() throws { try drawing.check() }
    func validateNestingDepth(_ depth: Int) throws { try drawing.resources.validateNestingDepth(depth) }
    func charge(entities: Int, work: Int, bytes: Int) throws {
        try checkTime()
        guard entities >= 0, work >= 0, bytes >= 0 else { throw ExportError.invalidMesh("Negative silhouette JSON admission.") }
        if entities > 0 { try drawing.resources.recordEntities(entities) }
        var original = silhouette
        if work > 0 { try original.consumeWork(work) }
        if bytes > 0 { try original.preparationStorageCallback(bytes) }
    }
    func recordIterations(_ count: Int) throws { try charge(entities: 0, work: count, bytes: 0) }
    func recordBytes(_ count: Int, label: String) throws { try charge(entities: 0, work: 0, bytes: count) }
}
