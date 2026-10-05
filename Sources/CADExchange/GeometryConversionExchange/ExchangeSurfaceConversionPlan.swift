import CADGeometry

struct ExchangeSurfaceConversionPlan: Sendable {
    let overrides: [Surface3D: BSplineSurface3D]
    let guarantees: [ExchangeSurfaceConversionGuarantee]
    let remainingLimits: ExchangeResourceLimits
    let budget: ExchangeProcessingBudget
}
