import CADCore

/// Retains one exact native sector and the invocation that prepared its plane.
struct OriginalNativePlaneOverlapCorrespondence: Sendable {
    let sector: OriginalNativePlaneContactProducer.Overlap.PreparedSector
    let preparedPlane: PreparedSurfaceDifferentialEncloser
    let options: CurveSurfaceIntersectionOptions
    let tolerance: ModelingTolerance
    let invocation: CurveSurfaceQueryInvocation
    let maximumParameterWidth: Double

    private struct Usage: RationalAlgebraAdmitting {
        let invocation: CurveSurfaceQueryInvocation
        mutating func consumeExactWork(_ count: Int) throws {
            guard count >= 0 else { throw GeometryConversionError.invalidInput("Original overlap work count is invalid.") }
            for _ in 0..<count { try invocation.consumeFixedWork() }
        }
        mutating func retainExactStorage(_ count: Int) throws {
            try invocation.reserve(count: count, stride: MemoryLayout<UInt32>.stride)
            try consumeExactWork(count)
        }
        mutating func visitExactCell(depth: Int) throws {
            guard depth >= 0, depth <= (invocation.maximumAlgebraicDepth ?? 32) else {
                throw GeometryConversionError.resourceLimitExceeded("Original overlap exhausted its independent algebra depth.")
            }
            try invocation.consumeFixedWork()
        }
        mutating func visitCoefficientCell(depth: Int) throws { try visitExactCell(depth: depth) }
    }

    func sourceBounds() throws -> ScalarInterval {
        var usage = Usage(invocation: invocation)
        return try sector.bounds(over: .init(lower: 0, upper: 1),
            maximumParameterWidth: maximumParameterWidth,
            maximumAlgebraicDepth: invocation.maximumAlgebraicDepth ?? 32, usage: &usage).sourceParameter
    }

    func endpoint(at fraction: Double) throws -> CurveSurfaceOverlapEndpoint {
        guard fraction.isFinite, fraction >= 0, fraction <= 1 else {
            throw GeometryConversionError.invalidInput("Original overlap correspondence requires a normalized fraction in [0,1].")
        }
        var usage = Usage(invocation: invocation)
        var width = maximumParameterWidth
        for _ in 0..<options.maximumIterations {
            try invocation.consumeFixedWork()
            let bounds = try sector.bounds(over: .init(lower: fraction, upper: fraction),
                maximumParameterWidth: width, maximumAlgebraicDepth: invocation.maximumAlgebraicDepth ?? 32,
                usage: &usage)
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
                maximumSpanCount: invocation.maximumSpanCount,
                maximumSubdivisionDepth: invocation.maximumSubdivisionDepth,
                remainingSourceDepth: invocation.remainingSourceDepth,
                consumeWork: invocation.consumeFixedWork, consumeStorage: invocation.consumeStorage)
            let pointBox = IntervalVector3DBounds(x: .exact(point.x), y: .exact(point.y), z: .exact(point.z))
            let radius = (bounds.position - pointBox).lengthUpperBound
            let residual = (bounds.position - target).lengthUpperBound
            if radius <= tolerance.distance, residual <= tolerance.distance {
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
    }
}
