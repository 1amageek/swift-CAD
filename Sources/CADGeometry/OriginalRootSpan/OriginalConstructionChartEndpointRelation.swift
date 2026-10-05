import CADCore

/// Same symbolic endpoint recipe, without evaluating a rounded native parameter.
package struct OriginalConstructionChartEndpointRelation {
    /// False leaves equality unresolved; it never proves unequal positions.
    package static func matches<B: RationalAlgebraAdmitting>(first: Curve3D, at firstParameter: Double,
        second: Curve3D, at secondParameter: Double, remainingSourceDepth: Int,
        tolerance: ModelingTolerance, usage: inout B) throws -> Bool {
        try usage.consumeExactWork(1)
        guard case .originalConstructionChart(let a) = first,
            case .originalConstructionChart(let b) = second,
            case .parameterLaw(let x) = a.chart, case .parameterLaw(let y) = b.chart,
            firstParameter == 0 || firstParameter == 1,
            secondParameter == 0 || secondParameter == 1 else { return false }
        guard remainingSourceDepth > 0,
            a.certificationTolerance == tolerance, b.certificationTolerance == tolerance else {
            throw GeometryConversionError.resourceLimitExceeded("Original chart corner lacks its source depth or tolerance capability.")
        }
        try GeometryStructuralComparisonWork.charge(curve: first, using: { try usage.consumeExactWork($0) })
        try GeometryStructuralComparisonWork.charge(curve: second, using: { try usage.consumeExactWork($0) })
        guard x.source == y.source else { return false }
        let firstFraction = firstParameter == 0 ? x.firstFraction : x.lastFraction
        let secondFraction = secondParameter == 0 ? y.firstFraction : y.lastFraction
        if x.startParameter == y.startParameter, x.endParameter == y.endParameter,
            x.law == y.law, firstFraction == secondFraction { return true }
        func originalLabel(_ source: OriginalCurveConstructionParameterSource,
            fraction: ExactRationalCoefficient, usage: inout B) throws -> ExactRationalCoefficient? {
            if fraction.isZero { return try .originalDouble(source.startParameter, usage: &usage) }
            if fraction == .one { return try .originalDouble(source.endParameter, usage: &usage) }
            guard case .affine = source.law else { return nil }
            let start = try ExactRationalCoefficient.originalDouble(source.startParameter, usage: &usage)
            let gain = try ExactRationalCoefficient.originalDouble(source.endParameter, usage: &usage)
                .subtracting(start, usage: &usage)
            return try start.adding(gain.multiplied(by: fraction, usage: &usage), usage: &usage)
        }
        guard let firstLabel = try originalLabel(x, fraction: firstFraction, usage: &usage),
            let secondLabel = try originalLabel(y, fraction: secondFraction, usage: &usage) else { return false }
        return firstLabel == secondLabel
    }
}
