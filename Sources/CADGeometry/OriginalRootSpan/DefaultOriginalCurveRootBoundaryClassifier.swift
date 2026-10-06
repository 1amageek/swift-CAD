import CADCore

/// Original homogeneous axis/plane equations, common GCD and complete Sturm isolation.
public struct DefaultOriginalCurveRootBoundaryClassifier: OriginalCurveRootBoundaryClassifying {
    public init() {}

    public func roots<B: RationalAlgebraAdmitting>(of source: BSplineCurve3D,
        constraint: OriginalCurveIncidenceConstraint, maximumSpanCount: Int,
        maximumSubdivisionDepth: Int, tolerance: ModelingTolerance,
        usage: inout B) throws -> OriginalCurveRootClassification {
        guard source.degree >= 1, source.degree < source.knots.count,
              source.controlPoints.count < source.knots.count else {
            throw GeometryConversionError.invalidInput("Original root source has invalid native dimensions.")
        }
        return try roots(of: source, over: ScalarInterval(lower: source.knots[source.degree],
            upper: source.knots[source.controlPoints.count]), constraint: constraint,
            maximumSpanCount: maximumSpanCount, maximumSubdivisionDepth: maximumSubdivisionDepth,
            tolerance: tolerance, usage: &usage)
    }

    public func roots<B: RationalAlgebraAdmitting>(of source: BSplineCurve3D, over trim: ScalarInterval,
        constraint: OriginalCurveIncidenceConstraint, maximumSpanCount: Int,
        maximumSubdivisionDepth: Int, tolerance: ModelingTolerance,
        usage: inout B) throws -> OriginalCurveRootClassification {
        guard maximumSpanCount > 0, maximumSubdivisionDepth >= 0 else {
            throw GeometryConversionError.invalidInput("Original root classification needs explicit caller span and depth admission.")
        }
        try source.validate(tolerance: tolerance)
        guard trim.lower.isFinite, trim.upper.isFinite, trim.lower <= trim.upper,
              trim.lower >= source.knots[source.degree], trim.upper <= source.knots[source.controlPoints.count] else {
            throw GeometryConversionError.invalidInput("Original root trim exceeds its exact base-native source domain.")
        }
        var roots: [OriginalCurveRootBoundary] = [], coincident: [ScalarInterval] = []
        var spans = 0
        for index in source.degree..<source.controlPoints.count {
            try CurrentTaskCancellationChecker().checkCancellation(); try usage.consumeExactWork(1)
            guard source.knots[index] < source.knots[index + 1] else { continue }
            let lower = max(source.knots[index], trim.lower), upper = min(source.knots[index + 1], trim.upper)
            guard lower <= upper else { continue }
            spans += 1
            guard spans <= maximumSpanCount else {
                throw GeometryConversionError.resourceLimitExceeded("Original root classification exhausted caller native span admission.")
            }
            let original = try OriginalRationalCurvePolynomial(source: source,
                spanIndex: index, tolerance: tolerance, usage: &usage)
            let numerators = try constraint.numerators(from: original, usage: &usage)
            var common: ExactBivariatePolynomial?
            for numerator in numerators where !numerator.isZero {
                common = try common.map { try ExactBivariateGCD().univariateGCD($0, numerator, usage: &usage) } ?? numerator
            }
            guard let common else {
                try usage.retainExactStorage(1)
                coincident.append(try ScalarInterval(lower: lower, upper: upper))
                continue
            }
            guard common.uDegree > 0 else { continue }
            if lower == upper {
                let station = try ExactRationalCoefficient.originalDouble(lower, usage: &usage)
                if try common.evaluated(atU: station, v: .zero, usage: &usage).isZero {
                    try usage.retainExactStorage(1)
                    roots.append(try OriginalCurveRootBoundary(source: source, spanIndex: index,
                        constraint: constraint, isolationLower: station, isolationUpper: station,
                        maximumSubdivisionDepth: maximumSubdivisionDepth, tolerance: tolerance, usage: &usage))
                }
                continue
            }
            let isolated = try ExactUnivariateRootIsolator().isolate(common,
                lower: .originalDouble(lower, usage: &usage), upper: .originalDouble(upper, usage: &usage),
                maximumDepth: maximumSubdivisionDepth, usage: &usage)
            for root in isolated {
                try usage.retainExactStorage(1)
                roots.append(try OriginalCurveRootBoundary(source: source, spanIndex: index,
                    constraint: constraint, isolation: root,
                    maximumSubdivisionDepth: maximumSubdivisionDepth, tolerance: tolerance, usage: &usage))
            }
        }
        return .init(source: source, constraint: constraint, isolated: roots,
            coincidentSpans: coincident, certificationTolerance: tolerance)
    }
}
