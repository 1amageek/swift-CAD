import CADCore

package struct ExactRationalBezierSurfaceCurveComposer: Sendable {
    private struct HomogeneousPoint4 {
        var x: Double
        var y: Double
        var z: Double
        var weight: Double

        static let zero = HomogeneousPoint4(x: 0.0, y: 0.0, z: 0.0, weight: 0.0)

        static func + (lhs: HomogeneousPoint4, rhs: HomogeneousPoint4) -> HomogeneousPoint4 {
            HomogeneousPoint4(
                x: lhs.x + rhs.x,
                y: lhs.y + rhs.y,
                z: lhs.z + rhs.z,
                weight: lhs.weight + rhs.weight
            )
        }

        static func * (lhs: HomogeneousPoint4, rhs: Double) -> HomogeneousPoint4 {
            HomogeneousPoint4(
                x: lhs.x * rhs,
                y: lhs.y * rhs,
                z: lhs.z * rhs,
                weight: lhs.weight * rhs
            )
        }
    }

    package init() {}

    package func compose(
        surface: BSplineSurface3D,
        parameterCurve: BSplineCurve2D,
        tolerance: ModelingTolerance
    ) throws -> BSplineCurve3D {
        try tolerance.validate()
        try surface.validate(tolerance: tolerance)
        try parameterCurve.validate(tolerance: tolerance)
        guard isSingleBezierSurface(surface),
              isSingleBezierCurve(parameterCurve) else {
            throw KernelError(
                phase: .geometry,
                code: .invalidInput,
                tolerance: tolerance,
                message: "Exact surface-curve composition requires one rational Bezier surface span and one rational Bezier parameter curve span."
            )
        }

        let parameterDegree = parameterCurve.degree
        let weightedU = zip(parameterCurve.controlPoints, parameterCurve.weights).map {
            $0.x * $1
        }
        let weightedV = zip(parameterCurve.controlPoints, parameterCurve.weights).map {
            $0.y * $1
        }
        let weightedOneMinusU = zip(weightedU, parameterCurve.weights).map { u, weight in
            weight - u
        }
        let weightedOneMinusV = zip(weightedV, parameterCurve.weights).map { v, weight in
            weight - v
        }

        let uBasis = try rationalBernsteinBasis(
            degree: surface.uDegree,
            numerator: weightedU,
            complement: weightedOneMinusU,
            sourceDegree: parameterDegree,
            tolerance: tolerance
        )
        let vBasis = try rationalBernsteinBasis(
            degree: surface.vDegree,
            numerator: weightedV,
            complement: weightedOneMinusV,
            sourceDegree: parameterDegree,
            tolerance: tolerance
        )
        let resultDegree = parameterDegree * (surface.uDegree + surface.vDegree)
        var homogeneousControls = Array(
            repeating: HomogeneousPoint4.zero,
            count: resultDegree + 1
        )
        for vIndex in 0...surface.vDegree {
            for uIndex in 0...surface.uDegree {
                let scalarControls = multiply(
                    uBasis[uIndex],
                    degree: parameterDegree * surface.uDegree,
                    by: vBasis[vIndex],
                    degree: parameterDegree * surface.vDegree
                )
                let point = surface.controlPoints[vIndex][uIndex]
                let weight = surface.weights[vIndex][uIndex]
                let source = HomogeneousPoint4(
                    x: point.x * weight,
                    y: point.y * weight,
                    z: point.z * weight,
                    weight: weight
                )
                for index in scalarControls.indices {
                    homogeneousControls[index] = homogeneousControls[index]
                        + source * scalarControls[index]
                }
            }
        }

        var points: [Point3D] = []
        var weights: [Double] = []
        points.reserveCapacity(homogeneousControls.count)
        weights.reserveCapacity(homogeneousControls.count)
        for control in homogeneousControls {
            guard control.x.isFinite,
                  control.y.isFinite,
                  control.z.isFinite,
                  control.weight.isFinite,
                  control.weight > 0.0 else {
                throw KernelError(
                    phase: .geometry,
                    code: .singularSystem,
                    tolerance: tolerance,
                    message: "Exact surface-curve composition produced a non-positive homogeneous weight."
                )
            }
            points.append(Point3D(
                x: control.x / control.weight,
                y: control.y / control.weight,
                z: control.z / control.weight
            ))
            weights.append(control.weight)
        }
        let curve = BSplineCurve3D(
            degree: resultDegree,
            knots: Array(repeating: 0.0, count: resultDegree + 1)
                + Array(repeating: 1.0, count: resultDegree + 1),
            controlPoints: points,
            weights: weights
        )
        try curve.validate(tolerance: tolerance)
        return curve
    }

    private func rationalBernsteinBasis(
        degree: Int,
        numerator: [Double],
        complement: [Double],
        sourceDegree: Int,
        tolerance: ModelingTolerance
    ) throws -> [[Double]] {
        guard numerator.count == sourceDegree + 1,
              complement.count == sourceDegree + 1 else {
            throw KernelError(
                phase: .geometry,
                code: .invalidInput,
                tolerance: tolerance,
                message: "Exact surface-curve composition received inconsistent parameter control counts."
            )
        }
        return (0...degree).map { index in
            let numeratorPower = power(
                numerator,
                degree: sourceDegree,
                exponent: index
            )
            let complementPower = power(
                complement,
                degree: sourceDegree,
                exponent: degree - index
            )
            return multiply(
                numeratorPower,
                degree: sourceDegree * index,
                by: complementPower,
                degree: sourceDegree * (degree - index)
            ).map { $0 * binomial(degree, index) }
        }
    }

    private func power(
        _ controls: [Double],
        degree: Int,
        exponent: Int
    ) -> [Double] {
        guard exponent > 0 else { return [1.0] }
        var result = controls
        var resultDegree = degree
        if exponent > 1 {
            for _ in 1..<exponent {
                result = multiply(
                    result,
                    degree: resultDegree,
                    by: controls,
                    degree: degree
                )
                resultDegree += degree
            }
        }
        return result
    }

    private func multiply(
        _ first: [Double],
        degree firstDegree: Int,
        by second: [Double],
        degree secondDegree: Int
    ) -> [Double] {
        let resultDegree = firstDegree + secondDegree
        var result = Array(repeating: 0.0, count: resultDegree + 1)
        for firstIndex in first.indices {
            for secondIndex in second.indices {
                let resultIndex = firstIndex + secondIndex
                let scale = binomial(firstDegree, firstIndex)
                    * binomial(secondDegree, secondIndex)
                    / binomial(resultDegree, resultIndex)
                result[resultIndex] += first[firstIndex] * second[secondIndex] * scale
            }
        }
        return result
    }

    private func binomial(_ n: Int, _ k: Int) -> Double {
        guard k >= 0, k <= n else { return 0.0 }
        let reduced = min(k, n - k)
        guard reduced > 0 else { return 1.0 }
        var result = 1.0
        for index in 1...reduced {
            result *= Double(n - reduced + index) / Double(index)
        }
        return result
    }

    private func isSingleBezierSurface(_ surface: BSplineSurface3D) -> Bool {
        surface.uControlPointCount == surface.uDegree + 1
            && surface.vControlPointCount == surface.vDegree + 1
            && surface.uKnots.count == 2 * (surface.uDegree + 1)
            && surface.vKnots.count == 2 * (surface.vDegree + 1)
            && surface.uKnots.prefix(surface.uDegree + 1).allSatisfy { $0 == 0.0 }
            && surface.uKnots.suffix(surface.uDegree + 1).allSatisfy { $0 == 1.0 }
            && surface.vKnots.prefix(surface.vDegree + 1).allSatisfy { $0 == 0.0 }
            && surface.vKnots.suffix(surface.vDegree + 1).allSatisfy { $0 == 1.0 }
    }

    private func isSingleBezierCurve(_ curve: BSplineCurve2D) -> Bool {
        curve.controlPointCount == curve.degree + 1
            && curve.knots.count == 2 * (curve.degree + 1)
            && curve.knots.prefix(curve.degree + 1).allSatisfy { $0 == 0.0 }
            && curve.knots.suffix(curve.degree + 1).allSatisfy { $0 == 1.0 }
    }
}
