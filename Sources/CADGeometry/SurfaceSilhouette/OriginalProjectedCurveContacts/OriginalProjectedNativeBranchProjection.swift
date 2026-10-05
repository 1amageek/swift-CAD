import CADCore

/// Original critical sections for a square-free common real projected fiber.
struct OriginalProjectedNativeBranchProjection: Sendable {
    enum EventKind: Sendable {
        case nativeLeading, nativeCritical, nativeBoundary
        case fiberLeading, fiberCritical, edgeBoundary, edgeStationary, quotientException
    }
    struct Event: Sendable {
        let kind: EventKind
        let originalUV: ExactBivariatePolynomial
        let freeProjection: ExactBivariatePolynomial
    }
    let originalComponent: ExactSurfaceLocusCommonFiber.Component
    let freeAlongU: Bool
    let selectedLocus: ExactBivariatePolynomial
    let selectedCommon: ExactSurfaceCoefficientPolynomial
    let events: [Event]
    let projection: ExactBivariatePolynomial
    let freeStations: [ExactMonotoneGraphEndpoint]
    let originalTrimFreeCuts: [OriginalSingularRationalCoordinateRoot]
    let hasWholeStationaryEdgeSection: Bool
    let wholeNativeBoundarySections: [ExactRationalCoefficient]
    let wholeEdgeBoundarySections: [ExactRationalCoefficient]

    init(component: ExactSurfaceLocusCommonFiber.Component, domain: SurfaceParameterBox,
        edgeRange: ScalarInterval, freeAlongU selectedFreeAlongU: Bool,
        originalTrimFreeValues: [OriginalSingularFieldElement], usage: inout SurfaceSilhouetteUsage) throws {
        originalComponent = component
        freeAlongU = selectedFreeAlongU
        let locus = try freeAlongU ? component.originalLocus : component.originalLocus.exchangedAxes(usage: &usage)
        selectedLocus = locus
        let common = try freeAlongU ? component.common : Self.exchanged(component.common, usage: &usage)
        selectedCommon = common
        let free = freeAlongU ? domain.u : domain.v
        let transverse = freeAlongU ? domain.v : domain.u
        guard locus.vDegree > 0 else {
            throw rationalAlgebraFailure("Original branch projection lacks a nonconstant transverse source law.")
        }
        var retained: [Event] = []
        var all = try ExactBivariatePolynomial.constant(.one, usage: &usage)
        func retain(_ law: ExactBivariatePolynomial, kind: EventKind, alreadyFree: Bool = false) throws {
            if law.isZero {
                // FIXME(INCOMPLETE_IMPLEMENTATION): Projected section continuation
                // must separate a component-wide nullified critical equation before
                // publishing complete edge overlap coverage on this production path.
                throw rationalAlgebraFailure("Original projected branch event nullifies on its complete component.")
            }
            let projected = try alreadyFree ? law : ExactBivariateResultant().eliminatingV(locus, law, usage: &usage)
            guard !projected.isZero, projected.vDegree <= 0 else {
                // FIXME(INCOMPLETE_IMPLEMENTATION): A component-wide exceptional
                // equation needs original factor separation, not a skipped event.
                throw rationalAlgebraFailure("Original projected branch has an unresolved component-wide event.")
            }
            if projected.uDegree > 0 {
                all = try all.multiplied(by: projected, usage: &usage)
                try RationalAlgebraStorage.retain(1, of: Event.self, usage: &usage)
                retained.append(.init(kind: kind, originalUV: law, freeProjection: projected))
            }
        }
        let leading = try locus.coefficient(ofV: locus.vDegree, usage: &usage)
        try retain(leading, kind: .nativeLeading, alreadyFree: true)
        let transverseDerivative = try locus.differentiated(alongU: false, usage: &usage)
        let discriminant = try ExactBivariateResultant().eliminatingV(locus, transverseDerivative, usage: &usage)
        try retain(discriminant, kind: .nativeCritical, alreadyFree: true)
        var nativeBoundarySections: [ExactRationalCoefficient] = []
        var edgeBoundarySections: [ExactRationalCoefficient] = []
        for index in 0..<2 {
            let station = try ExactRationalCoefficient.originalDouble(index == 0 ? transverse.lower : transverse.upper, usage: &usage)
            let equation = try locus.restricted(alongU: false, station: station, usage: &usage)
            if equation.isZero {
                try RationalAlgebraStorage.retain(1, of: ExactRationalCoefficient.self, usage: &usage)
                nativeBoundarySections.append(station)
                continue
            }
            try retain(equation, kind: .nativeBoundary, alreadyFree: true)
        }
        for exception in component.exceptionalCoefficients {
            let law = try freeAlongU ? exception : exception.exchangedAxes(usage: &usage)
            if law.uDegree > 0 || law.vDegree > 0 { try retain(law, kind: .quotientException) }
        }
        var wholeStationary = false
        if common.degree > 0 {
            guard let fiberLeading = common.coefficients.last else {
                throw rationalAlgebraFailure("Original projected branch lost its separate-parameter leading source.")
            }
            try retain(fiberLeading, kind: .fiberLeading)
            let derivative = try Self.parameterDerivative(common, usage: &usage)
            let critical = try ExactSurfaceCoefficientResultant().eliminatingParameter(common, derivative, usage: &usage)
            try retain(critical, kind: .fiberCritical)
            for index in 0..<2 {
                let station = try ExactRationalCoefficient.originalDouble(index == 0 ? edgeRange.lower : edgeRange.upper, usage: &usage)
                let boundary = try Self.evaluated(common, at: station, usage: &usage)
                let shared = try ExactBivariateGCD().greatestCommonDivisor(locus, boundary, usage: &usage)
                if shared.uDegree == locus.uDegree, shared.vDegree == locus.vDegree,
                    try shared.dividedExactly(by: locus, usage: &usage).uDegree <= 0 {
                    try RationalAlgebraStorage.retain(1, of: ExactRationalCoefficient.self, usage: &usage)
                    edgeBoundarySections.append(station)
                } else { try retain(boundary, kind: .edgeBoundary) }
            }
            let freeDerivative = try locus.differentiated(alongU: true, usage: &usage)
            try RationalAlgebraStorage.retain(common.coefficients.count, of: ExactBivariatePolynomial.self, usage: &usage)
            var stationary: [ExactBivariatePolynomial] = []; stationary.reserveCapacity(common.coefficients.count)
            for coefficient in common.coefficients {
                stationary.append(try coefficient.differentiated(alongU: true, usage: &usage)
                    .multiplied(by: transverseDerivative, usage: &usage)
                    .subtracting(coefficient.differentiated(alongU: false, usage: &usage)
                        .multiplied(by: freeDerivative, usage: &usage), usage: &usage))
            }
            let equation = try ExactSurfaceCoefficientPolynomial(coefficients: stationary, usage: &usage)
            if equation.isZero { wholeStationary = true }
            else {
                let critical = try ExactSurfaceCoefficientResultant().eliminatingParameter(common, equation, usage: &usage)
                if critical.isZero { wholeStationary = true }
                else { try retain(critical, kind: .edgeStationary) }
            }
        }
        events = retained; hasWholeStationaryEdgeSection = wholeStationary
        wholeNativeBoundarySections = nativeBoundarySections
        wholeEdgeBoundarySections = edgeBoundarySections
        var trimCuts: [OriginalSingularRationalCoordinateRoot] = []
        try RationalAlgebraStorage.retain(originalTrimFreeValues.count,
            of: OriginalSingularRationalCoordinateRoot.self, usage: &usage)
        trimCuts.reserveCapacity(originalTrimFreeValues.count)
        for original in originalTrimFreeValues {
            let cut = try OriginalSingularRationalCoordinateRoot(original: original,
                maximumDepth: usage.maximumDepth, maximumAlgebraicDepth: usage.maximumAlgebraicDepth, usage: &usage)
            all = try all.multiplied(by: cut.annihilator, usage: &usage)
            trimCuts.append(cut)
        }
        originalTrimFreeCuts = trimCuts
        let sequence = try ExactUnivariateSturmSequence(all, usage: &usage)
        projection = sequence.source
        let first = try ExactRationalCoefficient.originalDouble(free.lower, usage: &usage)
        let last = try ExactRationalCoefficient.originalDouble(free.upper, usage: &usage)
        freeStations = try OriginalRationalPlaneCurveProjection.sliceRoots(sequence.source, lower: first, upper: last,
            parentDepth: 0, maximumDepth: usage.maximumDepth, usage: &usage)
        try RationalAlgebraStorage.retain(1, of: Self.self, usage: &usage)
    }

    private static func exchanged(_ original: ExactSurfaceCoefficientPolynomial,
        usage: inout SurfaceSilhouetteUsage) throws -> ExactSurfaceCoefficientPolynomial {
        try RationalAlgebraStorage.retain(original.coefficients.count, of: ExactBivariatePolynomial.self, usage: &usage)
        var values: [ExactBivariatePolynomial] = []; values.reserveCapacity(original.coefficients.count)
        for value in original.coefficients { values.append(try value.exchangedAxes(usage: &usage)) }
        return try .init(coefficients: values, usage: &usage)
    }
    private static func parameterDerivative(_ original: ExactSurfaceCoefficientPolynomial,
        usage: inout SurfaceSilhouetteUsage) throws -> ExactSurfaceCoefficientPolynomial {
        try RationalAlgebraStorage.retain(max(0, original.degree), of: ExactBivariatePolynomial.self, usage: &usage)
        var values: [ExactBivariatePolynomial] = []; values.reserveCapacity(max(0, original.degree))
        if original.degree > 0 { for index in 1...original.degree {
            values.append(try original.coefficients[index].scaled(by: .natural(index, usage: &usage), usage: &usage))
        } }
        return try .init(coefficients: values, usage: &usage)
    }
    private static func evaluated(_ original: ExactSurfaceCoefficientPolynomial,
        at station: ExactRationalCoefficient, usage: inout SurfaceSilhouetteUsage) throws -> ExactBivariatePolynomial {
        var result = ExactBivariatePolynomial.zero
        for coefficient in original.coefficients.reversed() {
            result = try result.scaled(by: station, usage: &usage).adding(coefficient, usage: &usage)
        }
        return result
    }
}
