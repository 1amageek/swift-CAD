import CADCore

/// The unchanged native-U, linear-V homogeneous law of an original ruled source.
package struct OriginalRuledSurfacePolynomial: Sendable {
    package let source: RuledSurface3D
    package let start: OriginalRationalCurvePolynomial
    package let end: OriginalRationalCurvePolynomial
    package let domain: SurfaceParameterBox
    package let uDomain: OriginalRationalParameterDomain
    package let vDomain: OriginalRationalParameterDomain
    package let homogeneous: [ExactBivariatePolynomial]
    package var denominator: ExactBivariatePolynomial { homogeneous[3] }

    package init<B: ExactScalarAdmission & ~Copyable>(source: RuledSurface3D,
        over domain: SurfaceParameterBox, remainingSourceDepth: Int,
        tolerance: ModelingTolerance, usage: inout B) throws {
        try intersectionAlgebraStep(&usage)
        try tolerance.validate()
        guard remainingSourceDepth > 0 else {
            throw KernelError(phase: .geometry, code: .resourceLimitExceeded, tolerance: tolerance,
                message: "Original ruled source exhausted surface-to-boundary source depth.")
        }
        guard case .closed(let lower, let upper) = source.uDomain,
            lower.isFinite, upper.isFinite,
            upper - lower > max(tolerance.angle, tolerance.distance) else {
            throw GeometryError.invalidDistance(0)
        }
        let start = try Self.boundary(source.startBoundary, tolerance: tolerance, usage: &usage)
        let end = try Self.boundary(source.endBoundary, tolerance: tolerance, usage: &usage)
        let originalU = try OriginalRationalParameterDomain(lower: .originalDouble(lower, usage: &usage),
            upper: .originalDouble(upper, usage: &usage), usage: &usage)
        try Self.requireContained(originalU, in: start, tolerance: tolerance, usage: &usage)
        try Self.requireContained(originalU, in: end, tolerance: tolerance, usage: &usage)
        let uDomain = try OriginalRationalParameterDomain(domain.u, usage: &usage)
        let vDomain = try OriginalRationalParameterDomain(domain.v, usage: &usage)
        try OriginalRuledRelationEquations.requireContained(uDomain, in: originalU,
            tolerance: tolerance, usage: &usage)
        let originalV = try OriginalRationalParameterDomain(lower: .zero, upper: .one, usage: &usage)
        try OriginalRuledRelationEquations.requireContained(vDomain, in: originalV,
            tolerance: tolerance, usage: &usage)
        let v = try ExactBivariatePolynomial.coordinate(alongU: false, usage: &usage)
        let oneMinusV = try ExactBivariatePolynomial.constant(.one, usage: &usage)
            .subtracting(v, usage: &usage)
        try RationalAlgebraStorage.retain(4, of: ExactBivariatePolynomial.self, usage: &usage)
        var h: [ExactBivariatePolynomial] = []; h.reserveCapacity(4)
        for axis in 0..<3 {
            try intersectionAlgebraStep(&usage)
            let first = try start.homogeneous[axis].multiplied(by: end.homogeneous[3], usage: &usage)
                .multiplied(by: oneMinusV, usage: &usage)
            let second = try end.homogeneous[axis].multiplied(by: start.homogeneous[3], usage: &usage)
                .multiplied(by: v, usage: &usage)
            h.append(try first.adding(second, usage: &usage))
        }
        h.append(try start.homogeneous[3].multiplied(by: end.homogeneous[3], usage: &usage))
        try RationalAlgebraStorage.retain(1, of: Self.self, usage: &usage)
        try CurrentTaskCancellationChecker().checkCancellation()
        self.source = source; self.start = start; self.end = end; self.domain = domain
        self.uDomain = uDomain; self.vDomain = vDomain; homogeneous = h
    }

    private static func boundary<B: ExactScalarAdmission & ~Copyable>(_ source: Curve3D,
        tolerance: ModelingTolerance, usage: inout B) throws -> OriginalRationalCurvePolynomial {
        try intersectionAlgebraStep(&usage)
        // FIXME(INCOMPLETE_IMPLEMENTATION): Procedural CS/SSI source composition
        // currently covers direct aperiodic single-span Native boundaries only.
        // Other families and multi-span/periodic sources need complete original
        // chart issuers before this checkpoint can authorize their publication.
        guard case .bSpline(let native) = source, !native.isPeriodic else {
            throw unsupported(tolerance)
        }
        try native.validate(tolerance: tolerance, using: &usage)
        var selected: Int?
        for index in native.degree..<native.controlPoints.count {
            try intersectionAlgebraStep(&usage)
            if native.knots[index] < native.knots[index + 1] {
                guard selected == nil else { throw unsupported(tolerance) }
                selected = index
            }
        }
        guard let selected else { throw GeometryError.invalidDistance(0) }
        return try .init(source: native, spanIndex: selected, tolerance: tolerance, usage: &usage)
    }

    private static func unsupported(_ tolerance: ModelingTolerance) -> KernelError {
        .init(phase: .geometry, code: .unsupportedCapability, tolerance: tolerance,
            message: "Original ruled intersection source requires two direct aperiodic single-span Native rational boundaries.")
    }

    private static func requireContained<B: ExactScalarAdmission & ~Copyable>(_ domain: OriginalRationalParameterDomain,
        in curve: OriginalRationalCurvePolynomial, tolerance: ModelingTolerance, usage: inout B) throws {
        let native = try OriginalRationalParameterDomain(lower: curve.lowerParameter,
            upper: curve.upperParameter, usage: &usage)
        try OriginalRuledRelationEquations.requireContained(domain, in: native,
            tolerance: tolerance, usage: &usage)
    }
}
