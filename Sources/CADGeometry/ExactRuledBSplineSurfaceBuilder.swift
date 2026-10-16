import CADCore

public struct ExactRuledBSplineSurfaceBuilder: RuledBSplineSurfaceBuilding {
    private let basisResolver: any BSplineCurveCommonBasisResolving
    public var maximumResultDegree: Int

    public init(
        basisResolver: any BSplineCurveCommonBasisResolving = DefaultBSplineCurveCommonBasisResolver(),
        maximumResultDegree: Int = 64
    ) {
        self.basisResolver = basisResolver
        self.maximumResultDegree = maximumResultDegree
    }

    public func build(
        startBoundary: BSplineCurve3D,
        endBoundary: BSplineCurve3D,
        tolerance: ModelingTolerance
    ) throws -> BSplineSurface3D {
        var execution = try OriginalQueryExecution.independentGeometry()
        return try build(startBoundary: startBoundary, endBoundary: endBoundary, tolerance: tolerance, using: &execution)
    }

    package func commonDenominatorBoundaries(
        _ curves: [BSplineCurve3D],
        tolerance: ModelingTolerance
    ) throws -> [BSplineCurve3D] {
        var execution = try OriginalQueryExecution.independentGeometry()
        return try commonDenominatorBoundaries(curves, tolerance: tolerance, using: &execution)
    }

    public func build(
        startBoundary: BSplineCurve3D,
        endBoundary: BSplineCurve3D,
        tolerance: ModelingTolerance
    , using execution: inout OriginalQueryExecution) throws -> BSplineSurface3D {
        try execution.consumeWork(1)
        try tolerance.validate()
        guard maximumResultDegree > 0 else {
            throw diagnostic(
                code: .invalidInput,
                tolerance: tolerance,
                message: "Exact ruled construction requires a positive result-degree budget."
            )
        }
        let common = try basisResolver.resolve(
            first: startBoundary,
            second: endBoundary,
            tolerance: tolerance
        , using: &execution)
        if common.first.weights == common.second.weights {
            guard common.first.degree <= maximumResultDegree else {
                throw diagnostic(
                    code: .resourceLimitExceeded,
                    residual: Double(common.first.degree),
                    tolerance: tolerance,
                    message: "Exact ruled construction exceeded its result-degree budget."
                )
            }
            try execution.retainStorage(count: 4, stride: MemoryLayout<Double>.stride)
            try execution.retainStorage(count: 2, stride: MemoryLayout<[Point3D]>.stride)
            try execution.retainStorage(count: 2, stride: MemoryLayout<[Double]>.stride)
            let surface = BSplineSurface3D(
                uDegree: common.first.degree,
                vDegree: 1,
                uKnots: common.first.knots,
                vKnots: [0.0, 0.0, 1.0, 1.0],
                controlPoints: [
                    common.first.controlPoints,
                    common.second.controlPoints,
                ],
                weights: [
                    common.first.weights,
                    common.first.weights,
                ]
            )
            try surface.validate(tolerance: tolerance, using: &execution)
            return surface
        }
        let startPatches = try patches(
            of: common.first,
            tolerance: tolerance
        , using: &execution)
        let endPatches = try patches(
            of: common.second,
            tolerance: tolerance
        , using: &execution)
        guard startPatches.count == endPatches.count,
              startPatches.isEmpty == false else {
            throw diagnostic(
                code: .resourceLimitExceeded,
                tolerance: tolerance,
                message: "Exact ruled construction lost an aligned boundary span."
            )
        }
        let resultDegree = try checkedSum(common.first.degree, common.second.degree)
        guard resultDegree <= maximumResultDegree else {
            throw diagnostic(
                code: .resourceLimitExceeded,
                residual: Double(resultDegree),
                tolerance: tolerance,
                message: "Exact ruled construction exceeded its result-degree budget."
            )
        }

        try execution.retainStorage(count: startPatches.count, stride: MemoryLayout<TensorPatch>.stride)
        try execution.retainStorage(count: startPatches.count, stride: MemoryLayout<Double>.stride)
        try execution.retainStorage(count: 1, stride: MemoryLayout<Double>.stride)
        try execution.retainStorage(count: startPatches.count, stride: MemoryLayout<Double>.stride)
        let tensorPatches = try startPatches.indices.map { index in
            try tensorPatch(
                start: startPatches[index],
                end: endPatches[index],
                tolerance: tolerance
            , using: &execution)
        }
        return try assemble(
            patches: tensorPatches,
            breaks: [startPatches[0].lower] + startPatches.map({ $0.upper }),
            degree: resultDegree,
            tolerance: tolerance
        , using: &execution)
    }

    /// Reexpresses an aligned column with one positive rational denominator.
    /// Callers retain these curves as the shared boundaries of incident faces.
    package func commonDenominatorBoundaries(
        _ curves: [BSplineCurve3D],
        tolerance: ModelingTolerance
    , using execution: inout OriginalQueryExecution) throws -> [BSplineCurve3D] {
        try execution.consumeWork(1)
        try tolerance.validate()
        guard let first = curves.first else { return [] }
        for curve in curves { try curve.validate(tolerance: tolerance, using: &execution) }
        guard curves.allSatisfy({ $0.degree == first.degree && $0.knots == first.knots }),
              maximumResultDegree > 0 else {
            throw diagnostic(code: .invalidInput, tolerance: tolerance,
                message: "Common rational boundaries require aligned bases and a positive degree budget.")
        }
        guard first.degree <= maximumResultDegree else {
            throw diagnostic(code: .resourceLimitExceeded, tolerance: tolerance,
                message: "Common rational boundaries exceeded the result-degree budget.")
        }
        guard curves.contains(where: { $0.weights != first.weights }) else { return curves }
        try execution.retainStorage(count: curves.count, stride: MemoryLayout<BSplineCurve3D>.stride)
        try execution.retainStorage(count: curves.count, stride: MemoryLayout<Int>.stride)
        var factors: [BSplineCurve3D] = []
        var factorIndices: [Int] = []
        for curve in curves {
            try execution.consumeWork(1)
            if let index = factors.firstIndex(where: { $0.weights == curve.weights }) {
                factorIndices.append(index)
            } else {
                factorIndices.append(factors.count)
                factors.append(curve)
            }
        }
        guard first.degree <= maximumResultDegree / factors.count else {
            throw diagnostic(code: .resourceLimitExceeded, tolerance: tolerance,
                message: "Common rational boundaries exceeded the result-degree budget.")
        }
        let degree = first.degree * factors.count
        try execution.retainStorage(count: curves.count, stride: MemoryLayout<[RationalBezierCurvePatch3D]>.stride)
        try execution.retainStorage(count: factors.count, stride: MemoryLayout<[RationalBezierCurvePatch3D]>.stride)
        let sourcePatches = try curves.map { try patches(of: $0, tolerance: tolerance, using: &execution) }
        let factorPatches = try factors.map { try patches(of: $0, tolerance: tolerance, using: &execution) }
        guard let initial = sourcePatches[0].first,
              sourcePatches.allSatisfy({ $0.count == sourcePatches[0].count }) else {
            throw diagnostic(code: .invalidInput, tolerance: tolerance,
                message: "Common rational boundaries require a complete aligned span sequence.")
        }
        try execution.retainStorage(count: 1, stride: MemoryLayout<Double>.stride)
        try execution.retainStorage(count: sourcePatches[0].count, stride: MemoryLayout<Double>.stride)
        try execution.retainStorage(count: sourcePatches[0].count, stride: MemoryLayout<Double>.stride)
        try execution.retainStorage(count: 1, stride: MemoryLayout<Double>.stride)
        let breaks = [initial.lower] + sourcePatches[0].map({ $0.upper })
        try execution.retainStorage(count: curves.count, stride: MemoryLayout<[Point3D]>.stride)
        try execution.retainStorage(count: curves.count, stride: MemoryLayout<HomogeneousControl?>.stride)
        var points = Array(repeating: [Point3D](), count: curves.count)
        var previous = Array<HomogeneousControl?>(repeating: nil, count: curves.count)
        var weights: [Double] = []
        for span in sourcePatches[0].indices {
            try execution.consumeWork(1)
            try execution.retainStorage(count: 1, stride: MemoryLayout<Double>.stride)
            var denominator = [1.0]
            for factor in factorPatches {
                denominator = try product(denominator, factor[span].weights, tolerance: tolerance, using: &execution)
            }
            let localIndices = span == 0 ? 0...degree : 1...degree
            try execution.retainStorage(count: localIndices.count, stride: MemoryLayout<Double>.stride)
            try execution.retainStorage(count: localIndices.count, stride: MemoryLayout<Double>.stride)
            weights.append(contentsOf: localIndices.map { denominator[$0] })
            for curve in curves.indices {
                var numerator = try homogeneousNumerators(sourcePatches[curve][span], using: &execution)
                for factor in factorPatches.indices where factor != factorIndices[curve] {
                    numerator = try vectorTimesScalar(numerator, factorPatches[factor][span].weights,
                        tolerance: tolerance, using: &execution)
                }
                let converted = try controls(numerators: numerator, weights: denominator, tolerance: tolerance, using: &execution)
                if let prior = previous[curve] {
                    try validateSharedControl(prior, converted[0], tolerance: tolerance, using: &execution)
                }
                previous[curve] = converted[degree]
                for index in localIndices {
                    let control = converted[index]
                    try execution.consumeWork(1)
                    try execution.retainStorage(count: 1, stride: MemoryLayout<Point3D>.stride)
                    points[curve].append(Point3D(x: control.numerator.x / control.weight,
                        y: control.numerator.y / control.weight, z: control.numerator.z / control.weight))
                }
            }
        }
        try execution.retainStorage(count: points.count, stride: MemoryLayout<BSplineCurve3D>.stride)
        return try points.map { controls in
            let curve = BSplineCurve3D(degree: degree, knots: try knotVector(breaks: breaks, degree: degree, using: &execution),
                controlPoints: controls, weights: weights)
            try curve.validate(tolerance: tolerance, using: &execution)
            return curve
        }
    }

    private struct HomogeneousControl: Sendable {
        let numerator: Vector3D
        let weight: Double
    }

    private struct TensorPatch: Sendable {
        let controls: [[HomogeneousControl]]
    }

    private func patches(
        of curve: BSplineCurve3D,
        tolerance: ModelingTolerance
    , using execution: inout OriginalQueryExecution) throws -> [RationalBezierCurvePatch3D] {
        try execution.consumeWork(1)
        return try BSplineCurveBezierDecomposer().curvePatches(
            curve: curve,
            tolerance: tolerance
        , using: &execution)
    }

    /// A Euclidean ruling between rational curves C0=N0/W0 and C1=N1/W1 is
    /// represented with the shared denominator W0*W1. Interpolating the two
    /// original homogeneous rows directly would instead interpolate their
    /// denominators and change every interior point when W0 and W1 differ.
    private func tensorPatch(
        start: RationalBezierCurvePatch3D,
        end: RationalBezierCurvePatch3D,
        tolerance: ModelingTolerance
    , using execution: inout OriginalQueryExecution) throws -> TensorPatch {
        try execution.consumeWork(1)
        guard start.lower == end.lower,
              start.upper == end.upper else {
            throw diagnostic(
                code: .resourceLimitExceeded,
                tolerance: tolerance,
                message: "Exact ruled boundary spans are not parameter-aligned."
            )
        }
        let denominator = try product(
            start.weights,
            end.weights,
            tolerance: tolerance
        , using: &execution)
        let startNumerator = try vectorTimesScalar(
            try homogeneousNumerators(start, using: &execution),
            end.weights,
            tolerance: tolerance
        , using: &execution)
        let endNumerator = try vectorTimesScalar(
            try homogeneousNumerators(end, using: &execution),
            start.weights,
            tolerance: tolerance
        , using: &execution)
        guard denominator.count == startNumerator.count,
              denominator.count == endNumerator.count else {
            throw diagnostic(
                code: .resourceLimitExceeded,
                tolerance: tolerance,
                message: "Exact ruled Bernstein products have inconsistent dimensions."
            )
        }
        let startControls = try controls(
            numerators: startNumerator,
            weights: denominator,
            tolerance: tolerance
        , using: &execution)
        let endControls = try controls(
            numerators: endNumerator,
            weights: denominator,
            tolerance: tolerance
        , using: &execution)
        try execution.retainStorage(count: 2, stride: MemoryLayout<[HomogeneousControl]>.stride)
        return TensorPatch(controls: [startControls, endControls])
    }

    private func homogeneousNumerators(
        _ patch: RationalBezierCurvePatch3D
    , using execution: inout OriginalQueryExecution) throws -> [Vector3D] {
        try execution.consumeWork(1)
        try execution.retainStorage(count: patch.controlPoints.count, stride: MemoryLayout<Vector3D>.stride)
        return try patch.controlPoints.indices.map { index in
            try execution.consumeWork(1)
            return Vector3D(
                x: patch.controlPoints[index].x * patch.weights[index],
                y: patch.controlPoints[index].y * patch.weights[index],
                z: patch.controlPoints[index].z * patch.weights[index]
            )
        }
    }

    private func controls(
        numerators: [Vector3D],
        weights: [Double],
        tolerance: ModelingTolerance
    , using execution: inout OriginalQueryExecution) throws -> [HomogeneousControl] {
        try execution.consumeWork(1)
        try execution.retainStorage(count: numerators.count, stride: MemoryLayout<HomogeneousControl>.stride)
        return try numerators.indices.map { index in
            try execution.consumeWork(1)
            let numerator = numerators[index]
            let weight = weights[index]
            guard numerator.isFinite,
                  weight.isFinite,
                  weight > 0.0 else {
                throw diagnostic(
                    code: .resourceLimitExceeded,
                    residual: weight,
                    tolerance: tolerance,
                    message: "Exact ruled homogeneous control exceeded the finite positive-weight range."
                )
            }
            return HomogeneousControl(
                numerator: numerator,
                weight: weight
            )
        }
    }

    private func product(
        _ first: [Double],
        _ second: [Double],
        tolerance: ModelingTolerance
    , using execution: inout OriginalQueryExecution) throws -> [Double] {
        try execution.consumeWork(1)
        let firstDegree = first.count - 1
        let secondDegree = second.count - 1
        let resultDegree = try checkedSum(firstDegree, secondDegree)
        try execution.retainStorage(count: try checkedSum(resultDegree, 1), stride: MemoryLayout<Double>.stride)
        var result = Array(repeating: 0.0, count: try checkedSum(resultDegree, 1))
        for firstIndex in first.indices {
            for secondIndex in second.indices {
                try execution.consumeWork(1)
                let resultIndex = firstIndex + secondIndex
                let coefficient = try bernsteinProductCoefficient(
                    firstDegree: firstDegree,
                    firstIndex: firstIndex,
                    secondDegree: secondDegree,
                    secondIndex: secondIndex,
                    tolerance: tolerance
                , using: &execution)
                result[resultIndex] += first[firstIndex]
                    * second[secondIndex]
                    * coefficient
            }
        }
        guard result.allSatisfy({ $0.isFinite && $0 > 0.0 }) else {
            throw diagnostic(
                code: .resourceLimitExceeded,
                tolerance: tolerance,
                message: "Exact ruled denominator multiplication exceeded the finite positive-weight range."
            )
        }
        return result
    }

    private func vectorTimesScalar(
        _ vectors: [Vector3D],
        _ scalars: [Double],
        tolerance: ModelingTolerance
    , using execution: inout OriginalQueryExecution) throws -> [Vector3D] {
        try execution.consumeWork(1)
        let vectorDegree = vectors.count - 1
        let scalarDegree = scalars.count - 1
        let resultDegree = try checkedSum(vectorDegree, scalarDegree)
        try execution.retainStorage(count: try checkedSum(resultDegree, 1), stride: MemoryLayout<Vector3D>.stride)
        var result = Array(repeating: Vector3D.zero, count: try checkedSum(resultDegree, 1))
        for vectorIndex in vectors.indices {
            for scalarIndex in scalars.indices {
                try execution.consumeWork(1)
                let resultIndex = vectorIndex + scalarIndex
                let coefficient = try bernsteinProductCoefficient(
                    firstDegree: vectorDegree,
                    firstIndex: vectorIndex,
                    secondDegree: scalarDegree,
                    secondIndex: scalarIndex,
                    tolerance: tolerance
                , using: &execution)
                result[resultIndex] = result[resultIndex]
                    + vectors[vectorIndex]
                        * (scalars[scalarIndex] * coefficient)
            }
        }
        guard result.allSatisfy({ $0.isFinite }) else {
            throw diagnostic(
                code: .resourceLimitExceeded,
                tolerance: tolerance,
                message: "Exact ruled numerator multiplication exceeded the finite numeric range."
            )
        }
        return result
    }

    private func bernsteinProductCoefficient(
        firstDegree: Int,
        firstIndex: Int,
        secondDegree: Int,
        secondIndex: Int,
        tolerance: ModelingTolerance
    , using execution: inout OriginalQueryExecution) throws -> Double {
        try execution.consumeWork(1)
        let numerator = try binomial(firstDegree, firstIndex, using: &execution)
            * binomial(secondDegree, secondIndex, using: &execution)
        let denominator = try binomial(
            try checkedSum(firstDegree, secondDegree),
            firstIndex + secondIndex
        , using: &execution)
        let result = numerator / denominator
        guard result.isFinite else {
            throw diagnostic(
                code: .resourceLimitExceeded,
                tolerance: tolerance,
                message: "Exact ruled Bernstein product coefficient exceeded the finite numeric range."
            )
        }
        return result
    }

    private func binomial(_ degree: Int, _ index: Int, using execution: inout OriginalQueryExecution) throws -> Double {
        let reduced = min(index, degree - index)
        guard reduced > 0 else { return 1.0 }
        var result = 1.0
        for step in 1...reduced {
            try execution.consumeWork(1)
            result *= Double(degree - reduced + step) / Double(step)
        }
        return result
    }

    private func assemble(
        patches: [TensorPatch],
        breaks: [Double],
        degree: Int,
        tolerance: ModelingTolerance
    , using execution: inout OriginalQueryExecution) throws -> BSplineSurface3D {
        try execution.consumeWork(1)
        guard patches.isEmpty == false,
              breaks.count == patches.count + 1 else {
            throw diagnostic(
                code: .resourceLimitExceeded,
                tolerance: tolerance,
                message: "Exact ruled surface assembly requires a complete span sequence."
            )
        }
        let product = patches.count.multipliedReportingOverflow(by: degree)
        let total = product.partialValue.addingReportingOverflow(1)
        guard !product.overflow, !total.overflow else {
            throw diagnostic(code: .resourceLimitExceeded, tolerance: tolerance,
                message: "Exact ruled control net dimensions overflow.")
        }
        let controlCount = total.partialValue
        try execution.retainStorage(count: 2, stride: MemoryLayout<[HomogeneousControl?]>.stride)
        try execution.retainStorage(count: controlCount, stride: MemoryLayout<HomogeneousControl?>.stride)
        try execution.retainStorage(count: controlCount, stride: MemoryLayout<HomogeneousControl?>.stride)
        var net = Array(
            repeating: Array<HomogeneousControl?>(
                repeating: nil,
                count: controlCount
            ),
            count: 2
        )
        for spanIndex in patches.indices {
            let patch = patches[spanIndex]
            guard patch.controls.count == 2,
                  patch.controls.allSatisfy({ $0.count == degree + 1 }) else {
                throw diagnostic(
                    code: .resourceLimitExceeded,
                    tolerance: tolerance,
                    message: "Exact ruled tensor patch has inconsistent dimensions."
                )
            }
            for vIndex in 0...1 {
                for localU in 0...degree {
                    try execution.consumeWork(1)
                    let globalU = spanIndex * degree + localU
                    let candidate = patch.controls[vIndex][localU]
                    if let existing = net[vIndex][globalU] {
                        try validateSharedControl(
                            existing,
                            candidate,
                            tolerance: tolerance
                        , using: &execution)
                    } else {
                        net[vIndex][globalU] = candidate
                    }
                }
            }
        }
        try execution.retainStorage(count: 2, stride: MemoryLayout<[Point3D]>.stride)
        try execution.retainStorage(count: 2, stride: MemoryLayout<[Double]>.stride)
        var points: [[Point3D]] = []
        var weights: [[Double]] = []
        for row in net {
            try execution.retainStorage(count: row.count, stride: MemoryLayout<Point3D>.stride)
            try execution.retainStorage(count: row.count, stride: MemoryLayout<Double>.stride)
            var pointRow: [Point3D] = []
            var weightRow: [Double] = []
            for candidate in row {
                try execution.consumeWork(1)
                guard let control = candidate else {
                    throw diagnostic(
                        code: .resourceLimitExceeded,
                        tolerance: tolerance,
                        message: "Exact ruled global control net is incomplete."
                    )
                }
                pointRow.append(Point3D(
                    x: control.numerator.x / control.weight,
                    y: control.numerator.y / control.weight,
                    z: control.numerator.z / control.weight
                ))
                weightRow.append(control.weight)
            }
            points.append(pointRow)
            weights.append(weightRow)
        }
        try execution.retainStorage(count: 4, stride: MemoryLayout<Double>.stride)
        let surface = BSplineSurface3D(
            uDegree: degree,
            vDegree: 1,
            uKnots: try knotVector(breaks: breaks, degree: degree, using: &execution),
            vKnots: [0.0, 0.0, 1.0, 1.0],
            controlPoints: points,
            weights: weights
        )
        try surface.validate(tolerance: tolerance, using: &execution)
        return surface
    }

    private func validateSharedControl(
        _ first: HomogeneousControl,
        _ second: HomogeneousControl,
        tolerance: ModelingTolerance
    , using execution: inout OriginalQueryExecution) throws {
        try execution.consumeWork(1)
        let firstPoint = first.numerator / first.weight
        let secondPoint = second.numerator / second.weight
        let pointResidual = (firstPoint - secondPoint).length
        let weightScale = max(1.0, abs(first.weight), abs(second.weight))
        let weightResidual = abs(first.weight - second.weight) / weightScale
        guard pointResidual <= tolerance.distance,
              weightResidual <= tolerance.relative * 128.0 else {
            throw diagnostic(
                code: .resourceLimitExceeded,
                residual: max(pointResidual, weightResidual),
                tolerance: tolerance,
                message: "Adjacent exact ruled tensor patches did not retain one homogeneous boundary control."
            )
        }
    }

    private func knotVector(
        breaks: [Double],
        degree: Int
    , using execution: inout OriginalQueryExecution) throws -> [Double] {
        try execution.consumeWork(1)
        try execution.retainStorage(count: try checkedSum(degree, 1), stride: MemoryLayout<Double>.stride)
        try execution.retainStorage(count: try checkedSum(degree, 1), stride: MemoryLayout<Double>.stride)
        var result = Array(repeating: breaks[0], count: try checkedSum(degree, 1))
        if breaks.count > 2 {
            for value in breaks.dropFirst().dropLast() {
                try execution.consumeWork(1)
                try execution.retainStorage(count: degree, stride: MemoryLayout<Double>.stride)
                result.append(contentsOf: repeatElement(value, count: degree))
            }
        }
        result.append(contentsOf: repeatElement(
            breaks[breaks.count - 1],
            count: try checkedSum(degree, 1)
        ))
        return result
    }

    private func checkedSum(_ first: Int, _ second: Int) throws -> Int {
        let result = first.addingReportingOverflow(second)
        guard !result.overflow, result.partialValue >= 0 else {
            throw GeometryConversionError.resourceLimitExceeded("Exact ruled buffer dimensions overflow.")
        }
        return result.partialValue
    }

    private func diagnostic(
        code: KernelErrorCode,
        residual: Double? = nil,
        tolerance: ModelingTolerance,
        message: String
    ) -> KernelError {
        KernelError(
            phase: .geometry,
            code: code,
            residual: residual,
            tolerance: tolerance,
            message: message
        )
    }
}
