import CADCore

/// Exact-real affine owner chart; rounded display stations never replace native law.
struct NativeSurfaceOriginalCellChart: Sendable {
    let law: NativeSurfaceOriginalCellLaw
    let nativeDomain: SurfaceParameterBox
    let workingDomain: SurfaceParameterBox
    let swapsAxes: Bool
    let reversesU: Bool
    let reversesV: Bool

    init(law: NativeSurfaceOriginalCellLaw, nativeDomain: SurfaceParameterBox,
        workingDomain: SurfaceParameterBox, swapsAxes: Bool = false,
        reversesU: Bool = false, reversesV: Bool = false) {
        self.law = law; self.nativeDomain = nativeDomain; self.workingDomain = workingDomain
        self.swapsAxes = swapsAxes; self.reversesU = reversesU; self.reversesV = reversesV
    }

    func nativeBox(over working: SurfaceParameterBox) throws -> SurfaceParameterBox {
        func interval(_ query: ScalarInterval, _ source: ScalarInterval,
            _ target: ScalarInterval, reverse: Bool) throws -> ScalarInterval {
            guard target.lower <= query.lower, query.upper <= target.upper,
                  target.width > 0, source.width > 0 else {
                throw GeometryConversionError.invalidInput("Original cell chart requires its retained positive owner domains.")
            }
            let nativeWidth = OutwardScalarInterval.exact(source.upper) - .exact(source.lower)
            let workingWidth = OutwardScalarInterval.exact(target.upper) - .exact(target.lower)
            func station(_ value: Double) throws -> OutwardScalarInterval {
                if value == target.lower { return .exact(reverse ? source.upper : source.lower) }
                if value == target.upper { return .exact(reverse ? source.lower : source.upper) }
                guard let fraction = (OutwardScalarInterval.exact(value) - .exact(target.lower))
                    .divided(by: workingWidth) else {
                    throw GeometryConversionError.invalidInput("Original cell chart has an unresolved positive parameter width.")
                }
                return reverse ? .exact(source.upper) - nativeWidth * fraction
                    : .exact(source.lower) + nativeWidth * fraction
            }
            let first = try station(query.lower), last = try station(query.upper)
            return try ScalarInterval(lower: max(source.lower, reverse ? last.lower : first.lower),
                upper: min(source.upper, reverse ? first.upper : last.upper))
        }
        if swapsAxes {
            return try SurfaceParameterBox(u: interval(working.v, nativeDomain.u, workingDomain.v, reverse: reversesV),
                v: interval(working.u, nativeDomain.v, workingDomain.u, reverse: reversesU))
        }
        return try SurfaceParameterBox(u: interval(working.u, nativeDomain.u, workingDomain.u, reverse: reversesU),
            v: interval(working.v, nativeDomain.v, workingDomain.v, reverse: reversesV))
    }

    func positionBounds<A: ExactScalarAdmission & ~Copyable>(over working: SurfaceParameterBox,
        using execution: inout A) throws -> BoundingBox3D {
        let jet = try law.native.intervalJet(overClosedBox: nativeBox(over: working), on: law.source,
            tolerance: law.tolerance, using: &execution)
        return try BoundingBox3D(minimum: .init(x: jet.x.value.lower, y: jet.y.value.lower, z: jet.z.value.lower),
            maximum: .init(x: jet.x.value.upper, y: jet.y.value.upper, z: jet.z.value.upper))
    }

    func fields<A: ExactScalarAdmission & ~Copyable>(over working: SurfaceParameterBox, stationary: Set<SurfaceParameterBoundary>,
        using execution: inout A) throws
        -> (RationalBezierSurfaceDifferentialBounds, BoundingBox3D) {
        let box = try nativeBox(over: working)
        try execution.retainStorage(bytes: exactScalarPayloadBytes(count: stationary.count, of: SurfaceParameterBoundary.self))
        var nativeStationary: Set<SurfaceParameterBoundary> = []
        for side in stationary {
            let workingU = side == .uLower || side == .uUpper
            let upper = (side == .uUpper || side == .vUpper) != (workingU ? reversesU : reversesV)
            let nativeU = workingU != swapsAxes
            nativeStationary.insert(nativeU ? (upper ? .uUpper : .uLower) : (upper ? .vUpper : .vLower))
        }
        return try fields(overNative: box, nativeStationary: nativeStationary, using: &execution)
    }

    /// Query owners stay native; derivative gains belong to the retained whole chart frame.
    func fields<A: ExactScalarAdmission & ~Copyable>(overNative box: SurfaceParameterBox, nativeStationary: Set<SurfaceParameterBoundary>,
        using execution: inout A) throws
        -> (RationalBezierSurfaceDifferentialBounds, BoundingBox3D) {
        let original = try law.fields(over: box, stationary: nativeStationary, using: &execution)
        func gain(_ source: ScalarInterval, _ target: ScalarInterval) throws -> OutwardScalarInterval {
            guard let value = (OutwardScalarInterval.exact(source.upper) - .exact(source.lower))
                .divided(by: .exact(target.upper) - .exact(target.lower)), value.lower > 0 else {
                throw GeometryConversionError.invalidInput("Original native owner chart needs a proved positive exact-real gain.")
            }
            return value
        }
        let gu = try gain(swapsAxes ? nativeDomain.v : nativeDomain.u, workingDomain.u)
            * .exact(reversesU ? -1 : 1)
        let gv = try gain(swapsAxes ? nativeDomain.u : nativeDomain.v, workingDomain.v)
            * .exact(reversesV ? -1 : 1)
        func scale(_ value: IntervalVector3DBounds, _ scalar: OutwardScalarInterval) -> IntervalVector3DBounds {
            .init(x: value.x * scalar, y: value.y * scalar, z: value.z * scalar)
        }
        return (RationalBezierSurfaceDifferentialBounds(
            originalTangentU: scale(swapsAxes ? original.0.tangentVNumerator : original.0.tangentUNumerator, gu),
            originalTangentV: scale(swapsAxes ? original.0.tangentUNumerator : original.0.tangentVNumerator, gv),
            originalNormal: scale(original.0.normalNumerator, gu * gv * .exact(swapsAxes ? -1 : 1))), original.1)
    }
}
