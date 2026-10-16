import CADCore
import CADGeometry

package struct ExactBSplineCurveSpan: Sendable {
    package let curve: BSplineCurve3D
    package let startPoint: Point3D
    package let endPoint: Point3D
    package let originalChart: OriginalCurveSpanParameterChart
    package let correspondence: OriginalCurveSpanCorrespondence

    package init(curve: BSplineCurve3D, tolerance: ModelingTolerance,
        originalChart: OriginalCurveSpanParameterChart? = nil) throws {
        var execution: OriginalQueryExecution
        if let budget = originalChart?.constructionBudget, let limits = originalChart?.constructionLimits {
            execution = try OriginalQueryExecution(budget: budget, limits: limits, contributions: originalChart?.constructionContributions ?? [])
        } else {
            execution = try CurvedSweepSourceBudget(tolerance: tolerance).execution()
        }
        try self.init(curve: curve, tolerance: tolerance, originalChart: originalChart, using: &execution)
    }

    package init(
        curve: BSplineCurve3D,
        tolerance: ModelingTolerance,
        originalChart: OriginalCurveSpanParameterChart? = nil,
        using execution: inout OriginalQueryExecution
    ) throws {
        try curve.validate(tolerance: tolerance, using: &execution)
        guard case let .closed(lower, upper) = curve.domain else {
            throw KernelError(
                phase: .geometry,
                code: .invalidInput,
                tolerance: tolerance,
                message: "Exact curve span requires a bounded B-spline."
            )
        }
        let startPoint = try Self.candidatePoint(curve, parameter: lower, atEnd: false,
            tolerance: tolerance, using: &execution)
        let endPoint = try Self.candidatePoint(curve, parameter: upper, atEnd: true,
            tolerance: tolerance, using: &execution)
        guard startPoint.isApproximatelyEqual(
            to: endPoint,
            tolerance: tolerance.distance
        ) == false else {
            throw KernelError(
                phase: .topology,
                code: .topologyFailure,
                tolerance: tolerance,
                message: "Exact curve span must be split at a closed seam."
            )
        }
        self.curve = curve
        self.startPoint = startPoint
        self.endPoint = endPoint
        let rawChart = originalChart ?? OriginalCurveSpanParameterChart(
            curve: .bSpline(curve), startParameter: lower, endParameter: upper)
        let chart = try rawChart.admittingConstruction(using: &execution)
        self.originalChart = chart
        correspondence = try OriginalCurveSpanCorrespondence(candidate: curve, chart: chart,
            tolerance: tolerance, using: &execution)
    }

    private static func candidatePoint(_ curve: BSplineCurve3D, parameter: Double,
        atEnd: Bool, tolerance: ModelingTolerance,
        using execution: inout OriginalQueryExecution) throws -> Point3D {
        let count = curve.degree + 1
        try execution.consumeWork(count)
        let knots = atEnd ? curve.knots.suffix(count) : curve.knots.prefix(count)
        if knots.count == count, knots.allSatisfy({ $0 == parameter }),
           let point = atEnd ? curve.controlPoints.last : curve.controlPoints.first {
            return point
        }
        return try curve.point(at: parameter, tolerance: tolerance, using: &execution)
    }
}
