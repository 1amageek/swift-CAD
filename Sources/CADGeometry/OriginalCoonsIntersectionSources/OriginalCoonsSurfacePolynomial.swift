import CADCore

/// Checked original single-native-span Coons laws and their directed source maps.
package struct OriginalCoonsSurfacePolynomial: Sendable {
    package struct NativeBoundary: Sendable {
        package let traversal: OriginalCurveRootSpan3D
        package let source: BSplineCurve3D
        package let nativeSpanIndex: Int
        package let parameterMap: OriginalCurveAffineParameterMap
        package let nativeDomain: OriginalRationalParameterDomain
    }
    package let source: OriginalCoonsSurface3D
    /// Bottom, top, left and right in the source's original normalized directions.
    package let boundaries: [NativeBoundary]
    package let originalAtlas: OriginalCoonsHomogeneousAtlas
    package let domain: SurfaceParameterBox
    package let uDomain: OriginalRationalParameterDomain
    package let vDomain: OriginalRationalParameterDomain
    package var homogeneous: [ExactBivariatePolynomial] { originalAtlas.cells[0].homogeneous }
    package var denominator: ExactBivariatePolynomial { homogeneous[3] }

    package init(source: OriginalCoonsSurface3D,
        over domain: SurfaceParameterBox, remainingSourceDepth: Int,
        tolerance: ModelingTolerance, usage: inout OriginalQueryExecution) throws {
        try intersectionAlgebraStep(&usage)
        try source.validate(tolerance: tolerance, using: &usage)
        guard remainingSourceDepth >= 1 else {
            throw KernelError(phase: .geometry, code: .resourceLimitExceeded, tolerance: tolerance,
                message: "Original Coons source exhausted surface-to-boundary source depth.")
        }
        try RationalAlgebraStorage.retain(4, of: NativeBoundary.self, usage: &usage)
        var boundaries: [NativeBoundary] = []; boundaries.reserveCapacity(4)
        for index in 0..<4 {
            let traversal: OriginalCurveRootSpan3D
            switch index {
            case 0: traversal = source.vMinimumBoundary
            case 1: traversal = source.vMaximumBoundary
            case 2: traversal = source.uMinimumBoundary
            default: traversal = source.uMaximumBoundary
            }
            boundaries.append(try Self.boundary(traversal, tolerance: tolerance, usage: &usage))
        }
        let uDomain = try OriginalRationalParameterDomain(domain.u, usage: &usage)
        let vDomain = try OriginalRationalParameterDomain(domain.v, usage: &usage)
        let unit = try OriginalRationalParameterDomain(lower: .zero, upper: .one, usage: &usage)
        try OriginalRuledRelationEquations.requireContained(uDomain, in: unit, tolerance: tolerance, usage: &usage)
        try OriginalRuledRelationEquations.requireContained(vDomain, in: unit, tolerance: tolerance, usage: &usage)
        try usage.consumeWork(4)
        guard let original = try OriginalCoonsHomogeneousAtlas.prepared(source, usage: &usage),
            original.cells.count == 1, original.boundaryPieces.allSatisfy({ $0.count == 1 }),
            let cell = original.cells.first,
            cell.lowerU == .zero, cell.upperU == .one,
            cell.lowerV == .zero, cell.upperV == .one else {
            throw rationalAlgebraFailure("Single-span original Coons source lost its complete normalized cell law.")
        }
        try RationalAlgebraStorage.retain(1, of: Self.self, usage: &usage)
        try CurrentTaskCancellationChecker().checkCancellation()
        self.source = source; self.boundaries = boundaries; originalAtlas = original
        self.domain = domain; self.uDomain = uDomain; self.vDomain = vDomain
    }

    private static func boundary<B: ExactScalarAdmission & ~Copyable>(_ traversal: OriginalCurveRootSpan3D,
        tolerance: ModelingTolerance, usage: inout B) throws -> NativeBoundary {
        try intersectionAlgebraStep(&usage)
        // FIXME(INCOMPLETE_IMPLEMENTATION): The procedural CS/SSI Coons issuer
        // currently admits authored direct aperiodic single-span Native boundaries.
        // General image, multi-span, periodic and algebraic endpoint publication
        // needs complete source/domain adapters; a differential atlas alone must
        // not count those intersection routes as successful checkpoints.
        guard case .bSpline(let native) = traversal.source, !native.isPeriodic,
            case .authored(let first) = traversal.start, case .authored(let last) = traversal.end else {
            throw unsupported(tolerance)
        }
        try native.validate(tolerance: tolerance, using: &usage)
        var selected: Int?
        for index in native.degree..<native.controlPoints.count {
            try intersectionAlgebraStep(&usage)
            if native.knots[index] < native.knots[index + 1] {
                guard selected == nil else { throw unsupported(tolerance) }; selected = index
            }
        }
        guard let selected, traversal.nativeSpanIndex == nil || traversal.nativeSpanIndex == selected else {
            throw rationalAlgebraFailure("Original Coons traversal changed its selected native source owner.")
        }
        let a = try ExactRationalCoefficient.originalDouble(first, usage: &usage)
        let b = try ExactRationalCoefficient.originalDouble(last, usage: &usage)
        let gain = try b.subtracting(a, usage: &usage)
        guard !gain.isZero else { throw rationalAlgebraFailure("Original Coons boundary has zero directed parameter length.") }
        let nativeDomain = try OriginalRationalParameterDomain(lower: .originalDouble(native.knots[selected], usage: &usage),
            upper: .originalDouble(native.knots[selected + 1], usage: &usage), usage: &usage)
        let directed = try OriginalRationalParameterDomain(lower: gain.isPositive ? a : b,
            upper: gain.isPositive ? b : a, usage: &usage)
        try OriginalRuledRelationEquations.requireContained(directed, in: nativeDomain, tolerance: tolerance, usage: &usage)
        return .init(traversal: traversal, source: native, nativeSpanIndex: selected,
            parameterMap: .init(gain: gain, offset: a), nativeDomain: nativeDomain)
    }

    private static func unsupported(_ tolerance: ModelingTolerance) -> KernelError {
        .init(phase: .geometry, code: .unsupportedCapability, tolerance: tolerance,
            message: "Original Coons intersection source requires four authored direct aperiodic single-span Native boundaries.")
    }
}
