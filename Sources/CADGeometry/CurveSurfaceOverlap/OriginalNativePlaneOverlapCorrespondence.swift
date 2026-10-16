import CADCore

/// Retains one exact native sector and the cumulative budget that prepared its plane.
struct OriginalNativePlaneOverlapCorrespondence: Sendable {
    let sector: OriginalNativePlaneContactProducer.Overlap.PreparedSector
    let preparedPlane: PreparedSurfaceDifferentialEncloser
    let options: CurveSurfaceIntersectionOptions
    let tolerance: ModelingTolerance
    let budget: OriginalQueryBudget
    let contributions: [OriginalQueryContributionHandle]
    let limits: OriginalQueryExecutionLimits
    let context: OriginalQueryFailureContext
    let maximumParameterWidth: Double

    func sourceBounds() throws -> ScalarInterval {
        var execution = try OriginalQueryExecution(budget: budget, limits: limits, context: membershipContext, contributions: contributions)
        return try sourceBounds(using: &execution)
    }

    func sourceBounds(using execution: inout OriginalQueryExecution) throws -> ScalarInterval {
        do {
        let result = try sector.bounds(over: .init(lower: 0, upper: 1),
            maximumParameterWidth: maximumParameterWidth,
            maximumAlgebraicDepth: limits.maximumValueDepth, usage: &execution).sourceParameter
        try execution.checkpoint()
        return result
        } catch { throw OriginalQueryFailure.published(error, context: execution.context, tolerance: tolerance) }
    }

    func endpoint(at fraction: Double) throws -> CurveSurfaceOverlapEndpoint {
        var execution = try OriginalQueryExecution(budget: budget, limits: limits, context: membershipContext, contributions: contributions)
        return try endpoint(at: fraction, using: &execution)
    }

    func endpoint(at fraction: Double, using execution: inout OriginalQueryExecution) throws -> CurveSurfaceOverlapEndpoint {
        do {
        guard fraction.isFinite, fraction >= 0, fraction <= 1 else {
            throw GeometryConversionError.invalidInput("Original overlap correspondence requires a normalized fraction in [0,1].")
        }
        var width = maximumParameterWidth
        for _ in 0..<options.maximumIterations {
            try execution.consumeWork(1)
            let bounds = try sector.bounds(over: .init(lower: fraction, upper: fraction),
                maximumParameterWidth: width, maximumAlgebraicDepth: limits.maximumValueDepth,
                usage: &execution)
            func representative(_ interval: ScalarInterval, requested: ScalarInterval?) -> Double {
                guard let requested else { return interval.midpoint }
                return min(requested.upper, max(requested.lower, interval.midpoint))
            }
            let u = representative(bounds.planeUV.u, requested: options.surfaceURange)
            let v = representative(bounds.planeUV.v, requested: options.surfaceVRange)
            let point = Point3D(x: bounds.position.x.midpoint,
                y: bounds.position.y.midpoint, z: bounds.position.z.midpoint)
            let target = try preparedPlane.positionBounds(over: .init(u: .init(lower: u, upper: u),
                v: .init(lower: v, upper: v)), tolerance: tolerance,
                maximumSpanCount: limits.maximumSpans,
                maximumSubdivisionDepth: limits.maximumSubdivisionDepth,
                remainingSourceDepth: limits.remainingSourceDepth, using: &execution)
            let pointBox = IntervalVector3DBounds(x: .exact(point.x), y: .exact(point.y), z: .exact(point.z))
            let radius = (bounds.position - pointBox).lengthUpperBound
            let residual = (bounds.position - target).lengthUpperBound
            if radius <= tolerance.distance, residual <= tolerance.distance {
                try execution.checkpoint()
                return .init(curveParameter: bounds.sourceParameter.midpoint, point: point,
                    surfaceParameter: .init(u: u, v: v), residual: residual, isSurfaceChartSingular: false)
            }
            let next = width * 0.5
            guard next.isFinite, next > 0, next < width else {
                throw GeometryConversionError.resourceLimitExceeded("Original overlap numerical correspondence cannot refine its root enclosure.")
            }
            width = next
        }
        throw GeometryConversionError.resourceLimitExceeded("Original overlap correspondence exhausted caller localization iterations.")
        } catch { throw OriginalQueryFailure.published(error, context: execution.context, tolerance: tolerance) }
    }
    private var membershipContext: OriginalQueryFailureContext {
        .init(operation: context.operation, entry: .membership, stage: .membership,
            first: context.first, second: context.second,
            firstOwner: context.firstOwner, secondOwner: context.secondOwner)
    }
}
