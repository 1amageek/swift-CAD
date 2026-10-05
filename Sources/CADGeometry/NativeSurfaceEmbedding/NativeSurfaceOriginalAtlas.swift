import CADCore

/// Once-prepared selected original owners; Cartesian construction is independent.
struct NativeSurfaceOriginalAtlas: Sendable {
    let laws: [NativeSurfaceOriginalCellLaw]
    init(source: BSplineSurface3D, over domain: SurfaceParameterBox,
        maximumSpanCount: Int, tolerance: ModelingTolerance,
        admission: NativeSurfaceEmbeddingAdmission) throws {
        let prepared = try PreparedBSplineSurfaceDifferentialEncloser(surface: source,
            tolerance: tolerance, consumeWork: { try admission.work(1) },
            consumeStorage: { try admission.storageBytes($0) })
        let owners = try prepared.originalNativeSpans(over: domain, tolerance: tolerance,
            maximumSpanCount: maximumSpanCount, consumeWork: { try admission.work(1) },
            consumeStorage: { try admission.storageBytes($0) })
        try admission.storage(owners.count)
        laws = try owners.map { try .init(native: $0, source: source,
            tolerance: tolerance, admission: admission) }
    }
    func selected(uSpanIndex: Int, vSpanIndex: Int, admission: NativeSurfaceEmbeddingAdmission) throws -> NativeSurfaceOriginalCellLaw {
        for law in laws {
            try admission.work(1)
            if law.native.uSpanIndex == uSpanIndex, law.native.vSpanIndex == vSpanIndex,
               law.native.uCycle == 0, law.native.vCycle == 0 { return law }
        }
        throw GeometryConversionError.invalidInput("Oriented native cell lost its original base owner indices.")
    }
    func selected(over box: SurfaceParameterBox, admission: NativeSurfaceEmbeddingAdmission) throws -> NativeSurfaceOriginalCellLaw {
        for law in laws {
            try admission.work(1)
            if box.u.lower >= law.native.uBounds.lower, box.u.upper <= law.native.uBounds.upper,
               box.v.lower >= law.native.vBounds.lower, box.v.upper <= law.native.vBounds.upper { return law }
        }
        throw GeometryConversionError.invalidInput("Native embedding cell has no complete original selected owner.")
    }
}
