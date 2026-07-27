import CADCore
import Foundation

struct BSplineCurveBezierDecomposer {
    func curvePatches(
        curve: BSplineCurve3D,
        tolerance: ModelingTolerance
    ) throws -> [RationalBezierCurvePatch3D] {
        try resolvedCurvePatches(
            curve: curve,
            intersecting: nil,
            tolerance: tolerance
        )
    }

    func curvePatches(
        curve: BSplineCurve3D,
        intersecting interval: ScalarInterval,
        tolerance: ModelingTolerance
    ) throws -> [RationalBezierCurvePatch3D] {
        try resolvedCurvePatches(
            curve: curve,
            intersecting: interval,
            tolerance: tolerance
        )
    }

    private func resolvedCurvePatches(
        curve: BSplineCurve3D,
        intersecting interval: ScalarInterval?,
        tolerance: ModelingTolerance
    ) throws -> [RationalBezierCurvePatch3D] {
        try curve.validate(tolerance: tolerance)
        let breaks = try parameterBreaks(
            knots: curve.knots,
            domain: curve.domain,
            tolerance: tolerance
        )
        var result: [RationalBezierCurvePatch3D] = []
        result.reserveCapacity(breaks.count - 1)
        for index in 0..<(breaks.count - 1) {
            if let interval,
               breaks[index + 1] <= interval.lower
                || breaks[index] >= interval.upper {
                continue
            }
            let patch = try curvePatch(
                curve: curve,
                lower: breaks[index],
                upper: breaks[index + 1],
                tolerance: tolerance
            )
            result.append(patch)
        }
        return result
    }

    private func curvePatch(
        curve: BSplineCurve3D,
        lower: Double,
        upper: Double,
        tolerance: ModelingTolerance
    ) throws -> RationalBezierCurvePatch3D {
        let span = upper - lower
        guard span.isFinite, span > 0.0 else {
            throw KernelError(
                phase: .geometry,
                code: .invalidInput,
                tolerance: tolerance,
                message: "B-spline Bezier extraction requires a positive finite knot span."
            )
        }
        var derivatives: [HomogeneousVector] = []
        derivatives.reserveCapacity(curve.degree + 1)
        for derivativeOrder in 0...curve.degree {
            let basis = BSplineBasis.derivativeValues(
                parameter: lower,
                degree: curve.degree,
                derivativeOrder: derivativeOrder,
                knots: curve.knots,
                count: curve.controlPointCount
            )
            derivatives.append(homogeneousDerivative(curve: curve, basis: basis))
        }
        var controls: [HomogeneousVector] = []
        controls.reserveCapacity(curve.degree + 1)
        for controlIndex in 0...curve.degree {
            var control = HomogeneousVector.zero
            for derivativeOrder in 0...controlIndex {
                let scale = try derivativeToBernsteinScale(
                    degree: curve.degree,
                    controlIndex: controlIndex,
                    derivativeOrder: derivativeOrder,
                    span: span,
                    tolerance: tolerance
                )
                control = control + derivatives[derivativeOrder] * scale
            }
            controls.append(control)
        }
        var points: [Point3D] = []
        var weights: [Double] = []
        points.reserveCapacity(controls.count)
        weights.reserveCapacity(controls.count)
        for control in controls {
            guard control.isFinite,
                  control.weight > Double.ulpOfOne else {
                throw KernelError(
                    phase: .geometry,
                    code: .singularSystem,
                    residual: control.weight,
                    tolerance: tolerance,
                    message: "B-spline Bezier extraction produced a non-positive homogeneous weight."
                )
            }
            points.append(Point3D(
                x: control.x / control.weight,
                y: control.y / control.weight,
                z: control.z / control.weight
            ))
            weights.append(control.weight)
        }
        return RationalBezierCurvePatch3D(
            controlPoints: points,
            weights: weights,
            lower: lower,
            upper: upper
        )
    }

    private func homogeneousDerivative(
        curve: BSplineCurve3D,
        basis: [Double]
    ) -> HomogeneousVector {
        var result = HomogeneousVector.zero
        for index in 0..<curve.controlPointCount {
            let weight = curve.weights[index]
            let coefficient = basis[index] * weight
            guard coefficient != 0.0 else { continue }
            let point = curve.controlPoints[index]
            result = result + HomogeneousVector(
                x: point.x * coefficient,
                y: point.y * coefficient,
                z: point.z * coefficient,
                weight: coefficient
            )
        }
        return result
    }

    private func derivativeToBernsteinScale(
        degree: Int,
        controlIndex: Int,
        derivativeOrder: Int,
        span: Double,
        tolerance: ModelingTolerance
    ) throws -> Double {
        var binomial = 1.0
        if derivativeOrder > 0 {
            for index in 1...derivativeOrder {
                binomial *= Double(controlIndex - derivativeOrder + index) / Double(index)
            }
        }
        var fallingFactorial = 1.0
        var spanPower = 1.0
        if derivativeOrder > 0 {
            for index in 0..<derivativeOrder {
                fallingFactorial *= Double(degree - index)
                spanPower *= span
            }
        }
        let scale = binomial * spanPower / fallingFactorial
        guard scale.isFinite else {
            throw KernelError(
                phase: .geometry,
                code: .resourceLimitExceeded,
                tolerance: tolerance,
                message: "B-spline Bezier extraction exceeded finite derivative scaling."
            )
        }
        return scale
    }

    private func parameterBreaks(
        knots: [Double],
        domain: ParameterDomain,
        tolerance: ModelingTolerance
    ) throws -> [Double] {
        guard case let .closed(lower, upper) = domain else {
            throw KernelError(
                phase: .geometry,
                code: .invalidInput,
                tolerance: tolerance,
                message: "B-spline Bezier decomposition requires a bounded parameter domain."
            )
        }
        var result = [lower]
        for knot in knots where knot > lower && knot < upper {
            if result.last != knot {
                result.append(knot)
            }
        }
        result.append(upper)
        return result
    }

    private struct HomogeneousVector: Sendable {
        let x: Double
        let y: Double
        let z: Double
        let weight: Double

        static let zero = HomogeneousVector(x: 0.0, y: 0.0, z: 0.0, weight: 0.0)

        static func + (lhs: HomogeneousVector, rhs: HomogeneousVector) -> HomogeneousVector {
            HomogeneousVector(
                x: lhs.x + rhs.x,
                y: lhs.y + rhs.y,
                z: lhs.z + rhs.z,
                weight: lhs.weight + rhs.weight
            )
        }

        static func * (lhs: HomogeneousVector, rhs: Double) -> HomogeneousVector {
            HomogeneousVector(
                x: lhs.x * rhs,
                y: lhs.y * rhs,
                z: lhs.z * rhs,
                weight: lhs.weight * rhs
            )
        }

        var isFinite: Bool {
            x.isFinite && y.isFinite && z.isFinite && weight.isFinite
        }
    }
}
