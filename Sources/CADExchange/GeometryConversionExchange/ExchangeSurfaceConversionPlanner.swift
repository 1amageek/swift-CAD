import CADCore
import CADGeometry
import CADTopology

struct ExchangeSurfaceConversionPlanner {
    let converter: any CallerAdmittedGeometryConverting
    init(converter: any CallerAdmittedGeometryConverting = CertifiedGeometryConverter()) { self.converter = converter }
    func plan(stores: [GeometryStore], policy: ExchangeGeometryConversionPolicy, format: ExchangeFileFormat,
              tolerance: ModelingTolerance, limits: ExchangeResourceLimits, ledger suppliedLedger: ExchangeConversionLedger? = nil) throws -> ExchangeSurfaceConversionPlan {
        let ledger = try suppliedLedger ?? ExchangeConversionLedger(limits: limits, format: format)
        let accounting = ledger.snapshot()
        guard case .certified(let requirements) = policy else {
            return .init(overrides: [:], guarantees: [], remainingLimits: try ledger.remainingLimits(), budget: accounting.budget)
        }
        var overrides: [Surface3D: BSplineSurface3D] = [:]
        var guarantees: [ExchangeSurfaceConversionGuarantee] = []
        var seen: [SurfaceID: Surface3D] = [:]
        for store in stores {
            let sourceSlots = store.surfaces.count.multipliedReportingOverflow(by: MemoryLayout<SurfaceID>.stride + MemoryLayout<(SurfaceID, Surface3D)>.stride)
            guard !sourceSlots.overflow else { throw GeometryConversionError.resourceLimitExceeded("Surface source index storage overflow.") }
            try ledger.charge(entities: store.surfaces.count, work: store.surfaces.count, bytes: sourceSlots.partialValue)
            for id in store.surfaces.keys.sorted() {
                try accounting.checkTime()
                guard let surface = store.surfaces[id] else { throw IndependentShapeExchangeError.invalidAssociation("Conversion source surface is absent.") }
                try GeometryStructuralComparisonWork.charge(surface: surface) { try ledger.charge(work: $0) }
                if let previous = seen[id] {
                    guard previous == surface else { throw IndependentShapeExchangeError.invalidAssociation("One conversion SurfaceID has conflicting original laws.") }
                    continue
                }
                seen[id] = surface
                // Exact standard primitives and signed offsets retain their source representation.
                guard try requiresConversion(surface, depth: 0, ledger: ledger) else { continue }
                guard case .closed(let lowU, let highU) = surface.uDomain, case .closed(let lowV, let highV) = surface.vDomain else {
                    throw IndependentShapeExchangeError.unsupportedSemantics("Certified exchange requires the complete finite original native domain.")
                }
                let parameters = SurfaceParameterBox(u: try ScalarInterval(lower: lowU, upper: highU), v: try ScalarInterval(lower: lowV, upper: highV))
                let admission = try ledger.admission()
                let source = try NativeSurfaceConversionSource(surface, tolerance: tolerance, admission: admission)
                let result = try converter.approximateSurface(source: source, over: parameters,
                    requirements: requirements, tolerance: tolerance, admission: admission)
                let guarantee = result.guarantee
                guard result.parameters == parameters,
                      Surface3D.bSpline(result.surface).uDomain == surface.uDomain,
                      Surface3D.bSpline(result.surface).vDomain == surface.vDomain,
                      guarantee.positionErrorUpperBound.isFinite, guarantee.positionErrorUpperBound >= 0, guarantee.positionErrorUpperBound <= requirements.maximumPositionError,
                      guarantee.tangentAngleUpperBound.isFinite, guarantee.tangentAngleUpperBound >= 0, guarantee.tangentAngleUpperBound <= requirements.maximumTangentAngle,
                      guarantee.curvatureErrorUpperBound.isFinite, guarantee.curvatureErrorUpperBound >= 0, guarantee.curvatureErrorUpperBound <= requirements.maximumCurvatureError else {
                    throw GeometryConversionError.toleranceRejected
                }
                try accounting.checkTime()
                try ledger.charge(entities: 2, work: 1,
                    bytes: MemoryLayout<(Surface3D, BSplineSurface3D)>.stride + MemoryLayout<ExchangeSurfaceConversionGuarantee>.stride)
                overrides[surface] = result.surface
                guarantees.append(.init(surfaceID: id, originalSurface: surface, parameters: parameters, guarantee: guarantee))
            }
        }
        let remaining = try ledger.remainingLimits()
        return .init(overrides: overrides, guarantees: guarantees, remainingLimits: remaining, budget: accounting.budget)
    }
    private func requiresConversion(_ surface: Surface3D, depth: Int, ledger: ExchangeConversionLedger) throws -> Bool {
        try ledger.snapshot().validateNestingDepth(depth); try ledger.charge(work: 1)
        switch surface {
        case .procedural(.rollingBall), .procedural(.originalRevolution), .procedural(.originalCoons), .procedural(.originalBoundaryCorrected),
             .procedural(.originalAffineWord), .procedural(.originalAngularTransport), .procedural(.originalPlaneDerivative), .procedural(.originalDrafted): return true
        case .procedural(.offset(let offset)): return try requiresConversion(offset.source, depth: depth + 1, ledger: ledger)
        case .procedural(.originalImage(let image)): return try requiresConversion(image.source, depth: depth + 1, ledger: ledger)
        default: return false
        }
    }

}
