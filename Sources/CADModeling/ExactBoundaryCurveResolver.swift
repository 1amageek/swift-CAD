import CADCore
import CADGeometry
import CADTopology

package struct ExactBoundaryCurveResolver: Sendable {
    private let exactCurveBuilder = AnalyticCurveBSplineBuilder()

    package init() {}

    package func curve(
        edgeID: EdgeID,
        followsStoredDirection: Bool,
        model: BRepModel,
        tolerance: ModelingTolerance,
        featureID: FeatureID
    ) throws -> BSplineCurve3D {
        guard let edge = model.edges[edgeID],
              let curve = model.geometry.curves[edge.curveID],
              let start = model.vertices[edge.startVertexID]?.point,
              let end = model.vertices[edge.endVertexID]?.point else {
            throw TopologyError.missingReference("Boundary edge curve or vertex is missing.")
        }
        let startParameter: Double
        let endParameter: Double
        if let trim = edge.trim {
            startParameter = trim.startParameter
            endParameter = trim.endParameter
        } else {
            startParameter = try curve.parameterProjection(of: start, tolerance: tolerance).parameter
            endParameter = try curve.parameterProjection(of: end, tolerance: tolerance).parameter
        }
        guard startParameter != endParameter else {
            throw KernelError.unsupportedEvaluation(
                featureID: featureID,
                tolerance: tolerance,
                message: "A boundary edge cannot have a zero-parameter trim."
            )
        }
        let interval = try ScalarInterval(
            lower: min(startParameter, endParameter),
            upper: max(startParameter, endParameter)
        )
        guard var spline = try exactCurveBuilder.boundedCurve(
            curve: curve,
            interval: interval,
            maximumSpanCount: 4_096,
            tolerance: tolerance
        ) else {
            throw KernelError.unsupportedEvaluation(
                featureID: featureID,
                tolerance: tolerance,
                message: "The boundary curve kind cannot be converted exactly to a B-spline."
            )
        }
        let increasingParameterFollowsStoredDirection = startParameter < endParameter
        if increasingParameterFollowsStoredDirection != followsStoredDirection {
            spline = try spline.reversed(tolerance: tolerance)
        }
        let expectedStart = followsStoredDirection ? start : end
        let expectedEnd = followsStoredDirection ? end : start
        guard case let .closed(lower, upper) = spline.domain else {
            throw KernelError.unsupportedEvaluation(
                featureID: featureID,
                tolerance: tolerance,
                message: "A source boundary curve must have a finite closed parameter domain."
            )
        }
        let startResidual = try (spline.point(at: lower, tolerance: tolerance) - expectedStart).length
        let endResidual = try (spline.point(at: upper, tolerance: tolerance) - expectedEnd).length
        let residual = max(startResidual, endResidual)
        guard residual <= tolerance.distance else {
            throw KernelError(
                phase: .geometry,
                code: .intersectionFailure,
                featureID: featureID,
                residual: residual,
                tolerance: tolerance,
                message: "Exact boundary conversion does not preserve the source edge vertices."
            )
        }
        return spline
    }
}
