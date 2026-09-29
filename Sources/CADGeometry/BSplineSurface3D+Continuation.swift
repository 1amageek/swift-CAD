import CADCore

extension BSplineSurface3D {
    /// Continues a single Bezier support without changing its parameter chart.
    /// The source face is not replaced; the caller owns the returned error budget.
    package func continuedBezierSupport(
        over parameters: SurfaceParameterBox,
        maximumDeviation: Double,
        tolerance: ModelingTolerance
    ) throws -> (surface: BSplineSurface3D, maximumDeviation: Double) {
        try validate(tolerance: tolerance)
        func failure(_ code: KernelErrorCode, _ message: String) -> KernelError {
            KernelError(phase: .geometry, code: code, tolerance: tolerance, message: message)
        }
        guard case .closed(let u0, let u1) = uDomain,
              case .closed(let v0, let v1) = vDomain,
              uControlPointCount == uDegree + 1, vControlPointCount == vDegree + 1,
              uKnots.prefix(uDegree + 1).allSatisfy({ $0 == u0 }),
              uKnots.suffix(uDegree + 1).allSatisfy({ $0 == u1 }),
              vKnots.prefix(vDegree + 1).allSatisfy({ $0 == v0 }),
              vKnots.suffix(vDegree + 1).allSatisfy({ $0 == v1 }) else {
            throw failure(.unsupportedCapability, "Support continuation requires a single clamped Bezier chart.")
        }
        guard maximumDeviation.isFinite, maximumDeviation > 0,
              parameters.u.lower <= u0, parameters.u.upper >= u1,
              parameters.v.lower <= v0, parameters.v.upper >= v1 else {
            throw failure(.invalidInput, "Continuation requires a containing rectangle and positive finite allowance.")
        }
        if parameters.u.lower == u0, parameters.u.upper == u1,
           parameters.v.lower == v0, parameters.v.upper == v1 { return (self, 0) }
        func normalized(_ value: Double, _ lower: Double, _ upper: Double) throws -> OutwardScalarInterval {
            guard let result = (OutwardScalarInterval.exact(value) - .exact(lower))
                .divided(by: .exact(upper) - .exact(lower)), result.isFinite else {
                throw failure(.resourceLimitExceeded, "Continuation parameter arithmetic is not finite.")
            }
            return result
        }
        func continued(_ controls: [IntervalHomogeneousSurfaceControl],
                       _ lower: OutwardScalarInterval, _ upper: OutwardScalarInterval)
            -> [IntervalHomogeneousSurfaceControl] {
            let degree = controls.count - 1
            return (0...degree).map { index in
                var work = controls
                for level in 0..<degree {
                    let parameter = level < degree - index ? lower : upper
                    for position in 0..<(degree - level) {
                        work[position] = work[position].interpolated(to: work[position + 1], parameter: parameter)
                    }
                }
                return work[0]
            }
        }
        let lowerU = try normalized(parameters.u.lower, u0, u1)
        let upperU = try normalized(parameters.u.upper, u0, u1)
        let lowerV = try normalized(parameters.v.lower, v0, v1)
        let upperV = try normalized(parameters.v.upper, v0, v1)
        var net = controlPoints.indices.map { row in
            controlPoints[row].indices.map { column in
                let point = controlPoints[row][column]
                let weight = OutwardScalarInterval.exact(weights[row][column])
                return IntervalHomogeneousSurfaceControl(x: .exact(point.x) * weight,
                    y: .exact(point.y) * weight, z: .exact(point.z) * weight, weight: weight)
            }
        }
        net = net.map { continued($0, lowerU, upperU) }
        for column in 0..<uControlPointCount {
            let controls = continued(net.map { $0[column] }, lowerV, upperV)
            for row in 0..<vControlPointCount { net[row][column] = controls[row] }
        }
        var points = controlPoints
        var storedWeights = weights
        var numeratorError = [0.0, 0.0, 0.0]
        var coordinateMagnitude = [0.0, 0.0, 0.0]
        var weightError = 0.0
        var minimumWeight = Double.infinity
        for row in net.indices {
            for column in net[row].indices {
                let control = net[row][column]
                guard control.weight.isFinite, control.weight.lower > 0,
                      let x = control.x.divided(by: control.weight), x.isFinite,
                      let y = control.y.divided(by: control.weight), y.isFinite,
                      let z = control.z.divided(by: control.weight), z.isFinite else {
                    throw failure(.singularSystem, "Continuation cannot certify positive finite homogeneous weights.")
                }
                let coordinates = [x.midpoint, y.midpoint, z.midpoint]
                let homogeneous = [control.x, control.y, control.z]
                let weight = control.weight.midpoint
                points[row][column] = Point3D(x: coordinates[0], y: coordinates[1], z: coordinates[2])
                storedWeights[row][column] = weight
                minimumWeight = min(minimumWeight, control.weight.lower)
                weightError = max(weightError, (control.weight - .exact(weight)).absoluteUpperBound)
                for axis in 0..<3 {
                    numeratorError[axis] = max(numeratorError[axis],
                        (homogeneous[axis] - .exact(coordinates[axis]) * .exact(weight)).absoluteUpperBound)
                    coordinateMagnitude[axis] = max(coordinateMagnitude[axis], abs(coordinates[axis]))
                }
            }
        }
        // Positive Bernstein weights bound the denominator below and the
        // stored Cartesian surface by its control hull on the whole rectangle.
        var error = OutwardScalarInterval.exact(0)
        for axis in 0..<3 {
            guard let bound = (OutwardScalarInterval.exact(numeratorError[axis])
                + .exact(coordinateMagnitude[axis]) * .exact(weightError))
                .divided(by: .exact(minimumWeight)) else {
                throw failure(.singularSystem, "Continuation has no positive denominator bound.")
            }
            error = error + bound
        }
        guard error.isFinite, error.upper <= maximumDeviation else {
            throw failure(.resourceLimitExceeded, "Continuation exceeds the caller's geometric allowance.")
        }
        let result = BSplineSurface3D(uDegree: uDegree, vDegree: vDegree,
            uKnots: Array(repeating: parameters.u.lower, count: uDegree + 1)
                + Array(repeating: parameters.u.upper, count: uDegree + 1),
            vKnots: Array(repeating: parameters.v.lower, count: vDegree + 1)
                + Array(repeating: parameters.v.upper, count: vDegree + 1),
            controlPoints: points, weights: storedWeights)
        try result.validate(tolerance: tolerance)
        return (result, error.upper)
    }
}
