import CADCore

public extension BSplineSurface3D {
    func uIsoparametricCurve(atV v: Double, tolerance: ModelingTolerance) throws -> BSplineCurve3D {
        var execution = try OriginalQueryExecution.independentGeometry()
        return try uIsoparametricCurve(atV: v, tolerance: tolerance, using: &execution)
    }
    func vIsoparametricCurve(atU u: Double, tolerance: ModelingTolerance) throws -> BSplineCurve3D {
        var execution = try OriginalQueryExecution.independentGeometry()
        return try vIsoparametricCurve(atU: u, tolerance: tolerance, using: &execution)
    }

    func uIsoparametricCurve<A: ExactScalarAdmission & ~Copyable>(
        atV v: Double,
        tolerance: ModelingTolerance,
    using execution: inout A) throws -> BSplineCurve3D {
        try validate(tolerance: tolerance, using: &execution)
        guard try vDomain.contains(v, tolerance: tolerance) else {
            throw GeometryError.invalidDistance(v)
        }
        let clampedV = try basisParameter(v, direction: .v, tolerance: tolerance)
        let vBasis = try BSplineBasis.values(
            parameter: clampedV,
            degree: vDegree,
            knots: vKnots,
            count: vControlPointCount, using: &execution
        )
        let count = uControlPointCount
        try execution.retainStorage(bytes: exactScalarPayloadBytes(count: count, of: Point3D.self))
        try execution.retainStorage(bytes: exactScalarPayloadBytes(count: count, of: Double.self))
        var curveControlPoints: [Point3D] = []
        var curveWeights: [Double] = []
        curveControlPoints.reserveCapacity(uControlPointCount)
        curveWeights.reserveCapacity(uControlPointCount)
        for uIndex in 0..<uControlPointCount {
            let point = try homogeneousUIsoparametricControlPoint(uIndex: uIndex, vBasis: vBasis, using: &execution)
            curveControlPoints.append(point.point)
            curveWeights.append(point.weight)
        }
        let curve = BSplineCurve3D(
            degree: uDegree,
            knots: uKnots,
            controlPoints: curveControlPoints,
            weights: curveWeights,
            isPeriodic: isUPeriodic, periodicOrigin: uPeriodicOrigin
        )
        try curve.validate(tolerance: tolerance, using: &execution)
        try execution.checkpoint()
        return curve
    }

    func vIsoparametricCurve<A: ExactScalarAdmission & ~Copyable>(
        atU u: Double,
        tolerance: ModelingTolerance,
    using execution: inout A) throws -> BSplineCurve3D {
        try validate(tolerance: tolerance, using: &execution)
        guard try uDomain.contains(u, tolerance: tolerance) else {
            throw GeometryError.invalidDistance(u)
        }
        let clampedU = try basisParameter(u, direction: .u, tolerance: tolerance)
        let uBasis = try BSplineBasis.values(
            parameter: clampedU,
            degree: uDegree,
            knots: uKnots,
            count: uControlPointCount, using: &execution
        )
        let count = vControlPointCount
        try execution.retainStorage(bytes: exactScalarPayloadBytes(count: count, of: Point3D.self))
        try execution.retainStorage(bytes: exactScalarPayloadBytes(count: count, of: Double.self))
        var curveControlPoints: [Point3D] = []
        var curveWeights: [Double] = []
        curveControlPoints.reserveCapacity(vControlPointCount)
        curveWeights.reserveCapacity(vControlPointCount)
        for vIndex in 0..<vControlPointCount {
            let point = try homogeneousVIsoparametricControlPoint(vIndex: vIndex, uBasis: uBasis, using: &execution)
            curveControlPoints.append(point.point)
            curveWeights.append(point.weight)
        }
        let curve = BSplineCurve3D(
            degree: vDegree,
            knots: vKnots,
            controlPoints: curveControlPoints,
            weights: curveWeights,
            isPeriodic: isVPeriodic, periodicOrigin: vPeriodicOrigin
        )
        try curve.validate(tolerance: tolerance, using: &execution)
        try execution.checkpoint()
        return curve
    }

    private func homogeneousUIsoparametricControlPoint<A: ExactScalarAdmission & ~Copyable>(
        uIndex: Int,
        vBasis: [Double],
    using execution: inout A) throws -> (point: Point3D, weight: Double) {
        var weightedPoint = Vector3D.zero
        var weightSum = 0.0
        for vIndex in 0..<vControlPointCount {
            try execution.consumeWork(1)
            let weightedBasis = vBasis[vIndex] * weights[vIndex][uIndex]
            guard weightedBasis != 0.0 else {
                continue
            }
            weightedPoint = weightedPoint + vector(from: controlPoints[vIndex][uIndex]) * weightedBasis
            weightSum += weightedBasis
        }
        return try resolvedPoint(weightedPoint: weightedPoint, weight: weightSum)
    }

    private func homogeneousVIsoparametricControlPoint<A: ExactScalarAdmission & ~Copyable>(
        vIndex: Int,
        uBasis: [Double],
    using execution: inout A) throws -> (point: Point3D, weight: Double) {
        var weightedPoint = Vector3D.zero
        var weightSum = 0.0
        for uIndex in 0..<uControlPointCount {
            try execution.consumeWork(1)
            let weightedBasis = uBasis[uIndex] * weights[vIndex][uIndex]
            guard weightedBasis != 0.0 else {
                continue
            }
            weightedPoint = weightedPoint + vector(from: controlPoints[vIndex][uIndex]) * weightedBasis
            weightSum += weightedBasis
        }
        return try resolvedPoint(weightedPoint: weightedPoint, weight: weightSum)
    }

    private func resolvedPoint(
        weightedPoint: Vector3D,
        weight: Double
    ) throws -> (point: Point3D, weight: Double) {
        guard weightedPoint.isFinite,
              weight.isFinite,
              weight > Double.ulpOfOne else {
            throw GeometryError.invalidDistance(weight)
        }
        let point = weightedPoint / weight
        return (Point3D(x: point.x, y: point.y, z: point.z), weight)
    }

    private func vector(from point: Point3D) -> Vector3D {
        Vector3D(x: point.x, y: point.y, z: point.z)
    }
}
