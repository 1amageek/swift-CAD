import CADCore

/// Requires complete global exclusion before the separate local embedding proof.
enum OriginalExactEmbeddingSelfContactConsumer {
    static func validate<B: RationalAlgebraAdmitting>(surface: Surface3D, domain: SurfaceParameterBox,
        remainingSourceDepth: Int, maximumCharts: Int, tolerance: ModelingTolerance, usage: inout B
    ) throws {
        let supported: Bool
        switch surface {
        case .bSpline(let native): supported = !native.isUPeriodic && !native.isVPeriodic
        case .procedural(.originalCoons): supported = true
        // FIXME(INCOMPLETE_IMPLEMENTATION): Existing original embedding callers
        // still need periodic/general-source products and scoped identities.
        // Their existing local/cross-contact path is not whole M6 completion.
        default: supported = false
        }
        guard supported else { return }
        // Scalar visits remain governed by B's independent value/coefficient
        // witnesses; the existing public bridge's algorithm cap is not spatial depth.
        var a = NativeExactPublicAdmission(usage:usage,maximumDepth:32)
        defer { usage = a.usage }
        let limits = try OriginalDomainIdentityLimits(source:.init(remainingSourceDepth:remainingSourceDepth),
            maximumTransportDepth:32,maximumCharts:maximumCharts,maximumFamilies:maximumCharts,
            maximumIdentityProofs:maximumCharts)
        let pairs = maximumCharts.multipliedReportingOverflow(by:maximumCharts)
        // A quota above Int.max admits every representable count. Saturating
        // that ceiling preserves it; actual count/allocation overflow still fails.
        let maximumPairs = pairs.overflow ? Int.max : pairs.partialValue
        // This word-based API has no additional algebra-cell/count allowance;
        // existing public structural limits preserve its work/storage admission.
        let structure = try NativeExactPublicLimits.unboundedStructure()
        switch surface {
        case .bSpline(let native):
            let result = try OriginalExactSurfaceSelfContactPreparer.native(surface:native,domain:domain,
                tolerance:tolerance,limits:limits,maximumMaps:maximumCharts,maximumPairs:maximumPairs,
                cellLimits:structure.cells,topologyLimits:structure.topology,using:&a)
            for refined in result.refinements {
                for included in refined.pullback.region.included {
                    try a.consumeWork(1)
                    if included { throw contact(tolerance) }
                }
            }
        case .procedural(.originalCoons(let coons)):
            let result = try OriginalExactSurfaceSelfContactPreparer.coons(surface:coons,domain:domain,
                tolerance:tolerance,limits:limits,maximumPairs:maximumPairs,
                cellLimits:structure.cells,topologyLimits:structure.topology,using:&a)
            for refined in result.refinements {
                for included in refined.pullback.region.included {
                    try a.consumeWork(1)
                    if included { throw contact(tolerance) }
                }
            }
        default: throw NativeExactRelationFailure.invalidDomain
        }
        try a.checkpoint()
    }

    private static func contact(_ tolerance: ModelingTolerance) -> KernelError {
        .init(phase:.topology,code:.topologyFailure,tolerance:tolerance,
            message:"Original embedding has nonstructural contact at distinct source parameters.")
    }
}
