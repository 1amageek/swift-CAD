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
    var execution = try OriginalQueryExecution.independentGeometry()
    return try curve(edgeID: edgeID, followsStoredDirection: followsStoredDirection, model: model, tolerance: tolerance, featureID: featureID, using: &execution)
  }

  package func curve(
        edgeID: EdgeID,
        followsStoredDirection: Bool,
        model: BRepModel,
        tolerance: ModelingTolerance,
        featureID: FeatureID
    , using execution: inout OriginalQueryExecution) throws -> BSplineCurve3D {
    try execution.consumeWork(1)
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
            startParameter = try curve.parameterProjection(of: start, tolerance: tolerance, using: &execution).parameter
            endParameter = try curve.parameterProjection(of: end, tolerance: tolerance, using: &execution).parameter
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
        var spline: BSplineCurve3D
        if let exact = try exactCurveBuilder.boundedCurve(
            curve: curve,
            interval: interval,
            maximumSpanCount: 4_096,
            tolerance: tolerance, using: &execution
        ) {
            spline = exact
        } else {
            // FIXME(INCOMPLETE_IMPLEMENTATION): Nonrepresentable original boundary laws have no exact B-spline conversion here.
            // SurfaceFill and source-boundary consumers reach this branch; success requires an exact source-preserving
            // representation accepted by the consuming patch contract and verified over its complete trim.
            throw KernelError.unsupportedEvaluation(featureID: featureID, tolerance: tolerance,
                message: "The original boundary curve has no supported exact B-spline representation.")
        }
        let increasingParameterFollowsStoredDirection = startParameter < endParameter
        if increasingParameterFollowsStoredDirection != followsStoredDirection {
            spline = try spline.reversed(tolerance: tolerance, using: &execution)
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
        let startResidual = try (spline.point(at: lower, tolerance: tolerance, using: &execution) - expectedStart).length
        let endResidual = try (spline.point(at: upper, tolerance: tolerance, using: &execution) - expectedEnd).length
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
