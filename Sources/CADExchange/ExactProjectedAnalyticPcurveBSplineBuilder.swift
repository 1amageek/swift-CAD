import CADCore
import CADGeometry
import Foundation

struct ExactProjectedAnalyticPcurveBSplineBuilder {
    func build(
        _ projected: ProjectedAnalyticSurfaceParameterCurve,
        tolerance: ModelingTolerance,
        using execution: inout OriginalQueryExecution
    ) throws -> BSplineCurve2D {
        try execution.checkpoint()
        try tolerance.validate()
        guard isPlanar(projected.surface) else {
            throw KernelError(
                phase: .exchange,
                code: .unsupportedCapability,
                tolerance: tolerance,
                message: "Exact rational p-curve transfer of a projected analytic curve requires a planar support surface."
            )
        }
        let lower = min(projected.startParameter, projected.endParameter)
        let upper = max(projected.startParameter, projected.endParameter)
        let interval = try ScalarInterval(lower: lower, upper: upper)
        guard let ascending = try AnalyticCurveBSplineBuilder().boundedCurve(
            curve: projected.curve,
            interval: interval,
            maximumSpanCount: 4_096,
            tolerance: tolerance, using: &execution
        ) else {
            throw KernelError(
                phase: .exchange,
                code: .unsupportedCapability,
                tolerance: tolerance,
                message: "The projected analytic curve has no exact rational transfer representation."
            )
        }
        let directed = projected.endParameter >= projected.startParameter
            ? ascending
            : try ascending.reversed(tolerance: tolerance, using: &execution)
        try execution.retainStorage(count: directed.controlPoints.count, stride: MemoryLayout<Point2D>.stride)
        let parameterControlPoints = try directed.controlPoints.map { point in
            try execution.consumeWork(1)
            let parameter = try projected.surface.parameterProjection(
                of: point,
                tolerance: tolerance, using: &execution
            )
            return Point2D(x: parameter.u, y: parameter.v)
        }
        let result = BSplineCurve2D(
            degree: directed.degree,
            knots: directed.knots,
            controlPoints: parameterControlPoints,
            weights: directed.weights
        )
        try result.validate(tolerance: tolerance, using: &execution)
        let expectedStart = try projected.parameter(
            atNormalizedFraction: 0.0,
            tolerance: tolerance, using: &execution
        )
        let expectedEnd = try projected.parameter(
            atNormalizedFraction: 1.0,
            tolerance: tolerance, using: &execution
        )
        let actualStart = try result.point(
            at: try lowerDomainBound(result),
            tolerance: tolerance, using: &execution
        )
        let actualEnd = try result.point(
            at: try upperDomainBound(result),
            tolerance: tolerance, using: &execution
        )
        guard hypot(actualStart.x - expectedStart.u, actualStart.y - expectedStart.v)
                <= tolerance.distance,
              hypot(actualEnd.x - expectedEnd.u, actualEnd.y - expectedEnd.v)
                <= tolerance.distance else {
            throw KernelError(
                phase: .exchange,
                code: .intersectionFailure,
                tolerance: tolerance,
                message: "Exact projected analytic p-curve conversion failed endpoint verification."
            )
        }
        try execution.checkpoint()
        return result
    }

    private func lowerDomainBound(_ curve: BSplineCurve2D) throws -> Double {
        guard case let .closed(lower, _) = curve.domain else {
            throw invalidDomain()
        }
        return lower
    }

    private func upperDomainBound(_ curve: BSplineCurve2D) throws -> Double {
        guard case let .closed(_, upper) = curve.domain else {
            throw invalidDomain()
        }
        return upper
    }

    private func invalidDomain() -> KernelError {
        KernelError(
            phase: .exchange,
            code: .invalidInput,
            tolerance: nil,
            message: "An exact transferred p-curve requires a bounded rational domain."
        )
    }

    private func isPlanar(_ surface: Surface3D) -> Bool {
        switch surface {
        case .plane, .analytic(.plane):
            return true
        case .cylinder, .analytic, .bSpline:
            return false
        case let .procedural(.offset(offset)):
            return isPlanar(offset.source)
        case .procedural(.originalImage(let image)):
            return isPlanar(image.source)
        case .procedural(.ruled), .procedural(.rollingBall), .procedural(.originalRevolution), .procedural(.originalCoons), .procedural(.originalAffineWord):
            return false
        // FIXME(INCOMPLETE_IMPLEMENTATION): These original source laws have no admitted planar neutral transfer carrier.
        // The STEP/IGES projected pcurve caller must refuse until faithful source/chart conversion is proved.
        case .procedural(.originalAngularTransport), .procedural(.originalBoundaryCorrected),
             .procedural(.originalPlaneDerivative), .procedural(.originalDrafted):
            return false
        }
    }
}
