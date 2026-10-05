import CADCore
import CADGeometry

/// A certificate bound to the actual final coefficients and retained original chart.
package struct OriginalCurveSpanCorrespondence: Sendable {
    package let candidate: BSplineCurve3D
    package let chart: OriginalCurveSpanParameterChart
    package let parameters: ScalarInterval
    package let requirements: GeometryConversionRequirements
    package let guarantee: GeometryConversionGuarantee?
    package let isExactIdentity: Bool

    package init(candidate: BSplineCurve3D, chart: OriginalCurveSpanParameterChart,
        tolerance: ModelingTolerance, admission: GeometryConversionAdmission? = nil) throws {
        guard case let .closed(lower, upper) = candidate.domain else {
            throw GeometryConversionError.invalidInput("Original span correspondence requires a closed candidate domain.")
        }
        self.candidate = candidate; self.chart = chart
        parameters = try ScalarInterval(lower: lower, upper: upper)
        requirements = GeometryConversionRequirements(maximumPositionError: tolerance.distance * 0.25,
            maximumTangentAngle: tolerance.angle, maximumCurvatureError: tolerance.distance,
            maximumDegree: max(3, candidate.degree))
        if case .affine = chart.mapping, chart.curve == .bSpline(candidate),
           try chart.authoredEndpointParameter(atEnd: false, tolerance: tolerance) == lower,
           try chart.authoredEndpointParameter(atEnd: true, tolerance: tolerance) == upper {
            isExactIdentity = true; guarantee = nil
            return
        }
        isExactIdentity = false
        let selectedAdmission: GeometryConversionAdmission
        if let admission = admission ?? chart.constructionAdmission { selectedAdmission = admission }
        else {
            let budget = try CurvedSweepSourceBudget(tolerance: tolerance)
            selectedAdmission = try GeometryConversionAdmission(maximumSpanCount: budget.maximumSpanCount,
                maximumSubdivisionDepth: budget.maximumDepth, remainingSourceDepth: budget.maximumDepth,
                consumeWork: { try budget.consumeExactWork($0) },
                consumeStorage: { try budget.retainBytes($0) })
        }
        let source = try OriginalCurveConstructionSource(chart: chart, domain: parameters,
            tolerance: tolerance, admission: selectedAdmission)
        guarantee = try CertifiedGeometryConverter().certifyCurve(source: source,
            candidate: candidate, over: parameters, requirements: requirements, tolerance: tolerance, admission: selectedAdmission)
    }
}
