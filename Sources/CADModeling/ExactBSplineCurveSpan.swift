import CADCore
import CADGeometry

package struct ExactBSplineCurveSpan: Sendable {
    package let curve: BSplineCurve3D
    package let startPoint: Point3D
    package let endPoint: Point3D
    package let originalChart: OriginalCurveSpanParameterChart
    package let correspondence: OriginalCurveSpanCorrespondence

    package init(
        curve: BSplineCurve3D,
        tolerance: ModelingTolerance,
        originalChart: OriginalCurveSpanParameterChart? = nil,
        admission: GeometryConversionAdmission? = nil
    ) throws {
        if let admission {
            try Curve3D.bSpline(curve).validateOriginalSource(tolerance: tolerance,
                remainingSourceDepth: admission.remainingSourceDepth,
                maximumSubdivisionDepth: admission.maximumSubdivisionDepth,
                consumeWork: { _ in try admission.chargeWork() },
                consumeStorage: { try admission.chargeStorage(bytes: $0) })
        } else { try curve.validate(tolerance: tolerance) }
        guard case let .closed(lower, upper) = curve.domain else {
            throw KernelError(
                phase: .geometry,
                code: .invalidInput,
                tolerance: tolerance,
                message: "Exact curve span requires a bounded B-spline."
            )
        }
        let startPoint = try Self.candidatePoint(curve, parameter: lower, atEnd: false,
            tolerance: tolerance, admission: admission)
        let endPoint = try Self.candidatePoint(curve, parameter: upper, atEnd: true,
            tolerance: tolerance, admission: admission)
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
        let chart = admission.map { rawChart.admittingConstruction($0) } ?? rawChart
        self.originalChart = chart
        correspondence = try OriginalCurveSpanCorrespondence(candidate: curve, chart: chart,
            tolerance: tolerance, admission: admission)
    }

    private static func candidatePoint(_ curve: BSplineCurve3D, parameter: Double,
        atEnd: Bool, tolerance: ModelingTolerance,
        admission: GeometryConversionAdmission?) throws -> Point3D {
        let count = curve.degree + 1
        try admission?.chargeWork(count)
        let knots = atEnd ? curve.knots.suffix(count) : curve.knots.prefix(count)
        if knots.count == count, knots.allSatisfy({ $0 == parameter }),
           let point = atEnd ? curve.controlPoints.last : curve.controlPoints.first {
            return point
        }
        guard let admission else { return try curve.point(at: parameter, tolerance: tolerance) }
        let prepared = try PreparedCurveDifferentialEncloser(curve: .bSpline(curve),
            tolerance: tolerance, remainingSourceDepth: admission.remainingSourceDepth,
            maximumSubdivisionDepth: admission.maximumSubdivisionDepth,
            consumeWork: { try admission.chargeWork() },
            consumeStorage: { try admission.chargeStorage(bytes: $0) })
        let result = try prepared.closedNativeJets(over: ScalarInterval(lower: parameter, upper: parameter),
            tolerance: tolerance, maximumSpanCount: admission.maximumSpanCount,
            maximumSubdivisionDepth: admission.maximumSubdivisionDepth,
            remainingSourceDepth: admission.remainingSourceDepth,
            consumeWork: { try admission.chargeWork() },
            consumeStorage: { try admission.chargeStorage(bytes: $0) })
        var x: OutwardScalarInterval?, y: OutwardScalarInterval?, z: OutwardScalarInterval?
        func hull(_ prior: OutwardScalarInterval?, _ value: OutwardScalarInterval) -> OutwardScalarInterval {
            guard let prior else { return value }
            return .init(lower: min(prior.lower, value.lower), upper: max(prior.upper, value.upper))
        }
        for owner in result.spans {
            try admission.chargeWork()
            x = hull(x, owner.jet.x.value); y = hull(y, owner.jet.y.value); z = hull(z, owner.jet.z.value)
        }
        guard let x, let y, let z, x.isFinite, y.isFinite, z.isFinite else {
            throw GeometryConversionError.resourceLimitExceeded("A candidate endpoint has no complete finite native enclosure.")
        }
        let point = Point3D(x: x.midpoint, y: y.midpoint, z: z.midpoint)
        let residual = IntervalVector3DBounds(x: x - .exact(point.x),
            y: y - .exact(point.y), z: z - .exact(point.z)).lengthUpperBound
        guard residual <= tolerance.distance / 64 else {
            throw GeometryConversionError.toleranceRejected
        }
        return point
    }
}
