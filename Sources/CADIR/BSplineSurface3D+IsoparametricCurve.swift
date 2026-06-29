import CADCore

public extension BSplineSurface3D {
    func uIsoparametricCurve(
        atV v: Double,
        tolerance: ModelingTolerance = .standard
    ) throws -> BSplineCurve3D {
        try validate(tolerance: tolerance)
        guard try vDomain.contains(v, tolerance: tolerance) else {
            throw GeometryError.invalidDistance(v)
        }
        let clampedV = BSplineBasis.clampedParameter(v, knots: vKnots, degree: vDegree)
        let vBasis = BSplineBasis.values(
            parameter: clampedV,
            degree: vDegree,
            knots: vKnots,
            count: vControlPointCount
        )
        var curveControlPoints: [Point3D] = []
        var curveWeights: [Double] = []
        curveControlPoints.reserveCapacity(uControlPointCount)
        curveWeights.reserveCapacity(uControlPointCount)
        for uIndex in 0..<uControlPointCount {
            let point = try homogeneousUIsoparametricControlPoint(uIndex: uIndex, vBasis: vBasis)
            curveControlPoints.append(point.point)
            curveWeights.append(point.weight)
        }
        let curve = BSplineCurve3D(
            degree: uDegree,
            knots: uKnots,
            controlPoints: curveControlPoints,
            weights: curveWeights
        )
        try curve.validate(tolerance: tolerance)
        return curve
    }

    func vIsoparametricCurve(
        atU u: Double,
        tolerance: ModelingTolerance = .standard
    ) throws -> BSplineCurve3D {
        try validate(tolerance: tolerance)
        guard try uDomain.contains(u, tolerance: tolerance) else {
            throw GeometryError.invalidDistance(u)
        }
        let clampedU = BSplineBasis.clampedParameter(u, knots: uKnots, degree: uDegree)
        let uBasis = BSplineBasis.values(
            parameter: clampedU,
            degree: uDegree,
            knots: uKnots,
            count: uControlPointCount
        )
        var curveControlPoints: [Point3D] = []
        var curveWeights: [Double] = []
        curveControlPoints.reserveCapacity(vControlPointCount)
        curveWeights.reserveCapacity(vControlPointCount)
        for vIndex in 0..<vControlPointCount {
            let point = try homogeneousVIsoparametricControlPoint(vIndex: vIndex, uBasis: uBasis)
            curveControlPoints.append(point.point)
            curveWeights.append(point.weight)
        }
        let curve = BSplineCurve3D(
            degree: vDegree,
            knots: vKnots,
            controlPoints: curveControlPoints,
            weights: curveWeights
        )
        try curve.validate(tolerance: tolerance)
        return curve
    }

    private func homogeneousUIsoparametricControlPoint(
        uIndex: Int,
        vBasis: [Double]
    ) throws -> (point: Point3D, weight: Double) {
        var weightedPoint = Vector3D.zero
        var weightSum = 0.0
        for vIndex in 0..<vControlPointCount {
            let weightedBasis = vBasis[vIndex] * weights[vIndex][uIndex]
            guard weightedBasis != 0.0 else {
                continue
            }
            weightedPoint = weightedPoint + vector(from: controlPoints[vIndex][uIndex]) * weightedBasis
            weightSum += weightedBasis
        }
        return try resolvedPoint(weightedPoint: weightedPoint, weight: weightSum)
    }

    private func homogeneousVIsoparametricControlPoint(
        vIndex: Int,
        uBasis: [Double]
    ) throws -> (point: Point3D, weight: Double) {
        var weightedPoint = Vector3D.zero
        var weightSum = 0.0
        for uIndex in 0..<uControlPointCount {
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
