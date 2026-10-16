import CADCore

/// Once-prepared selected original owners; Cartesian construction is independent.
struct NativeSurfaceOriginalAtlas: Sendable {
    let laws: [NativeSurfaceOriginalCellLaw]
    init<A: ExactScalarAdmission & ~Copyable>(source: BSplineSurface3D, over domain: SurfaceParameterBox,
        maximumSpanCount: Int, tolerance: ModelingTolerance,
        using execution: inout A) throws {
        let prepared = try PreparedBSplineSurfaceDifferentialEncloser(surface: source,
            tolerance: tolerance, using: &execution)
        let owners = try prepared.originalNativeSpans(over: domain, tolerance: tolerance,
            maximumSpanCount: maximumSpanCount, using: &execution)
        try execution.retainStorage(bytes: exactScalarPayloadBytes(count: owners.count, of: NativeSurfaceOriginalCellLaw.self))
        laws = try owners.map { try .init(native: $0, source: source,
            tolerance: tolerance, using: &execution) }
    }
    func selected<A: ExactScalarAdmission & ~Copyable>(uSpanIndex: Int, vSpanIndex: Int, using execution: inout A) throws -> NativeSurfaceOriginalCellLaw {
        for law in laws {
            try execution.consumeWork(1)
            if law.native.uSpanIndex == uSpanIndex, law.native.vSpanIndex == vSpanIndex,
               law.native.uCycle == 0, law.native.vCycle == 0 { return law }
        }
        throw GeometryConversionError.invalidInput("Oriented native cell lost its original base owner indices.")
    }
    func selected<A: ExactScalarAdmission & ~Copyable>(over box: SurfaceParameterBox, using execution: inout A) throws -> NativeSurfaceOriginalCellLaw {
        for law in laws {
            try execution.consumeWork(1)
            if box.u.lower >= law.native.uBounds.lower, box.u.upper <= law.native.uBounds.upper,
               box.v.lower >= law.native.vBounds.lower, box.v.upper <= law.native.vBounds.upper { return law }
        }
        throw GeometryConversionError.invalidInput("Native embedding cell has no complete original selected owner.")
    }
}
