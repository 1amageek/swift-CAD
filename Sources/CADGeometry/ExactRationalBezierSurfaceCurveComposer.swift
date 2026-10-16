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
        var execution = try OriginalQueryExecution.independentGeometry()
        return try compose(surface: surface, parameterCurve: parameterCurve, tolerance: tolerance, using: &execution)
    }

    package func compose(
        surface: BSplineSurface3D,
        parameterCurve: BSplineCurve2D,
        tolerance: ModelingTolerance
    , using execution: inout OriginalQueryExecution) throws -> BSplineCurve3D {
        try execution.consumeWork(1)
        try tolerance.validate()
        try surface.validate(tolerance: tolerance, using: &execution)
        try parameterCurve.validate(tolerance: tolerance, using: &execution)
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
        for _ in 0..<4 {
            try execution.consumeWork(1); try execution.retainStorage(count: parameterCurve.controlPoints.count, stride: MemoryLayout<Double>.stride) }
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
        , using: &execution)
        let vBasis = try rationalBernsteinBasis(
            degree: surface.vDegree,
            numerator: weightedV,
            complement: weightedOneMinusV,
            sourceDegree: parameterDegree,
            tolerance: tolerance
        , using: &execution)
        let surfaceOrder = surface.uDegree.addingReportingOverflow(surface.vDegree)
        let degreeProduct = parameterDegree.multipliedReportingOverflow(by: surfaceOrder.partialValue)
        guard !surfaceOrder.overflow, !degreeProduct.overflow else { throw ExactScalarFailure.countOverflow }
        let resultDegree = degreeProduct.partialValue
        try execution.retainStorage(count: resultDegree + 1, stride: MemoryLayout<HomogeneousPoint4>.stride)
        var homogeneousControls = Array(
            repeating: HomogeneousPoint4.zero,
            count: resultDegree + 1
        )
        for vIndex in 0...surface.vDegree {
            try execution.consumeWork(1);
            for uIndex in 0...surface.uDegree {
            try execution.consumeWork(1);
                let scalarControls = try multiply(
                    uBasis[uIndex],
                    degree: parameterDegree * surface.uDegree,
                    by: vBasis[vIndex],
                    degree: parameterDegree * surface.vDegree
                , using: &execution)
                let point = surface.controlPoints[vIndex][uIndex]
                let weight = surface.weights[vIndex][uIndex]
                let source = HomogeneousPoint4(
                    x: point.x * weight,
                    y: point.y * weight,
                    z: point.z * weight,
                    weight: weight
                )
                for index in scalarControls.indices {
            try execution.consumeWork(1);
                    homogeneousControls[index] = homogeneousControls[index]
                        + source * scalarControls[index]
                }
            }
        }

        try execution.retainStorage(count: homogeneousControls.count, stride: MemoryLayout<Point3D>.stride)
        try execution.retainStorage(count: homogeneousControls.count, stride: MemoryLayout<Double>.stride)
        for _ in 0..<4 {
            try execution.consumeWork(1); try execution.retainStorage(count: resultDegree + 1, stride: MemoryLayout<Double>.stride) }
        var points: [Point3D] = []
        var weights: [Double] = []
        points.reserveCapacity(homogeneousControls.count)
        weights.reserveCapacity(homogeneousControls.count)
        for control in homogeneousControls {
            try execution.consumeWork(1);
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
        try curve.validate(tolerance: tolerance, using: &execution)
        return curve
    }

    private func rationalBernsteinBasis(
        degree: Int,
        numerator: [Double],
        complement: [Double],
        sourceDegree: Int,
        tolerance: ModelingTolerance
    , using execution: inout OriginalQueryExecution) throws -> [[Double]] {
        try execution.consumeWork(1)
        guard numerator.count == sourceDegree + 1,
              complement.count == sourceDegree + 1 else {
            throw KernelError(
                phase: .geometry,
                code: .invalidInput,
                tolerance: tolerance,
                message: "Exact surface-curve composition received inconsistent parameter control counts."
            )
        }
        try execution.retainStorage(count: degree + 1, stride: MemoryLayout<[Double]>.stride)
        return try (0...degree).map { index in
            let numeratorPower = try power(
                numerator,
                degree: sourceDegree,
                exponent: index
            , using: &execution)
            let complementPower = try power(
                complement,
                degree: sourceDegree,
                exponent: degree - index
            , using: &execution)
            return try multiply(
                numeratorPower,
                degree: sourceDegree * index,
                by: complementPower,
                degree: sourceDegree * (degree - index)
            , using: &execution).map { try execution.consumeWork(1); return $0 * (try binomial(degree, index, using: &execution)) }
        }
    }

    private func power(
        _ controls: [Double],
        degree: Int,
        exponent: Int
    , using execution: inout OriginalQueryExecution) throws -> [Double] {
        try execution.consumeWork(1)
        guard exponent > 0 else { try execution.retainStorage(count: 1, stride: MemoryLayout<Double>.stride); return [1.0] }
        var result = controls
        var resultDegree = degree
        if exponent > 1 {
            for _ in 1..<exponent {
            try execution.consumeWork(1);
                result = try multiply(
                    result,
                    degree: resultDegree,
                    by: controls,
                    degree: degree
                , using: &execution)
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
    , using execution: inout OriginalQueryExecution) throws -> [Double] {
        try execution.consumeWork(1)
        let resultDegree = firstDegree + secondDegree
        try execution.retainStorage(count: resultDegree + 1, stride: MemoryLayout<Double>.stride)
        var result = Array(repeating: 0.0, count: resultDegree + 1)
        for firstIndex in first.indices {
            try execution.consumeWork(1);
            for secondIndex in second.indices {
            try execution.consumeWork(1);
                let resultIndex = firstIndex + secondIndex
                let scale = try binomial(firstDegree, firstIndex, using: &execution)
                    * binomial(secondDegree, secondIndex, using: &execution)
                    / binomial(resultDegree, resultIndex, using: &execution)
                result[resultIndex] += first[firstIndex] * second[secondIndex] * scale
            }
        }
        return result
    }

    private func binomial(_ n: Int, _ k: Int, using execution: inout OriginalQueryExecution) throws -> Double {
        try execution.consumeWork(1)
        guard k >= 0, k <= n else { return 0.0 }
        let reduced = min(k, n - k)
        guard reduced > 0 else { return 1.0 }
        var result = 1.0
        for index in 1...reduced {
            try execution.consumeWork(1);
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
