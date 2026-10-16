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
        tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution) throws {
        guard case let .closed(lower, upper) = candidate.domain else {
            throw GeometryConversionError.invalidInput("Original span correspondence requires a closed candidate domain.")
        }
        self.candidate = candidate; self.chart = chart
        parameters = try ScalarInterval(lower: lower, upper: upper)
        requirements = GeometryConversionRequirements(maximumPositionError: tolerance.distance * 0.25,
            maximumTangentAngle: tolerance.angle, maximumCurvatureError: tolerance.distance,
            maximumDegree: max(3, candidate.degree))
        if case .affine = chart.mapping, chart.curve == .bSpline(candidate),
           try chart.authoredEndpointParameter(atEnd: false, tolerance: tolerance, using: &execution) == lower,
           try chart.authoredEndpointParameter(atEnd: true, tolerance: tolerance, using: &execution) == upper {
            isExactIdentity = true; guarantee = nil
            return
        }
        isExactIdentity = false
        let source = try OriginalCurveConstructionSource(chart: chart, domain: parameters,
            tolerance: tolerance, using: &execution)
        guarantee = try CertifiedGeometryConverter().certifyCurve(source: source,
            candidate: candidate, over: parameters, requirements: requirements, tolerance: tolerance, using: &execution)
    }
}
