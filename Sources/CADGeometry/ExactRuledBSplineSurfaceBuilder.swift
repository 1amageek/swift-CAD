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
        )
        if common.first.weights == common.second.weights {
            guard common.first.degree <= maximumResultDegree else {
                throw diagnostic(
                    code: .resourceLimitExceeded,
                    residual: Double(common.first.degree),
                    tolerance: tolerance,
                    message: "Exact ruled construction exceeded its result-degree budget."
                )
            }
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
            try surface.validate(tolerance: tolerance)
            return surface
        }
        let startPatches = try patches(
            of: common.first,
            tolerance: tolerance
        )
        let endPatches = try patches(
            of: common.second,
            tolerance: tolerance
        )
        guard startPatches.count == endPatches.count,
              startPatches.isEmpty == false else {
            throw diagnostic(
                code: .resourceLimitExceeded,
                tolerance: tolerance,
                message: "Exact ruled construction lost an aligned boundary span."
            )
        }
        let resultDegree = common.first.degree + common.second.degree
        guard resultDegree <= maximumResultDegree else {
            throw diagnostic(
                code: .resourceLimitExceeded,
                residual: Double(resultDegree),
                tolerance: tolerance,
                message: "Exact ruled construction exceeded its result-degree budget."
            )
        }

        let tensorPatches = try startPatches.indices.map { index in
            try tensorPatch(
                start: startPatches[index],
                end: endPatches[index],
                tolerance: tolerance
            )
        }
        return try assemble(
            patches: tensorPatches,
            breaks: [startPatches[0].lower] + startPatches.map(\.upper),
            degree: resultDegree,
            tolerance: tolerance
        )
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
    ) throws -> [RationalBezierCurvePatch3D] {
        try BSplineCurveBezierDecomposer().curvePatches(
            curve: curve,
            tolerance: tolerance
        )
    }

    /// A Euclidean ruling between rational curves C0=N0/W0 and C1=N1/W1 is
    /// represented with the shared denominator W0*W1. Interpolating the two
    /// original homogeneous rows directly would instead interpolate their
    /// denominators and change every interior point when W0 and W1 differ.
    private func tensorPatch(
        start: RationalBezierCurvePatch3D,
        end: RationalBezierCurvePatch3D,
        tolerance: ModelingTolerance
    ) throws -> TensorPatch {
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
        )
        let startNumerator = try vectorTimesScalar(
            homogeneousNumerators(start),
            end.weights,
            tolerance: tolerance
        )
        let endNumerator = try vectorTimesScalar(
            homogeneousNumerators(end),
            start.weights,
            tolerance: tolerance
        )
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
        )
        let endControls = try controls(
            numerators: endNumerator,
            weights: denominator,
            tolerance: tolerance
        )
        return TensorPatch(controls: [startControls, endControls])
    }

    private func homogeneousNumerators(
        _ patch: RationalBezierCurvePatch3D
    ) -> [Vector3D] {
        patch.controlPoints.indices.map { index in
            Vector3D(
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
    ) throws -> [HomogeneousControl] {
        try numerators.indices.map { index in
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
    ) throws -> [Double] {
        let firstDegree = first.count - 1
        let secondDegree = second.count - 1
        let resultDegree = firstDegree + secondDegree
        var result = Array(repeating: 0.0, count: resultDegree + 1)
        for firstIndex in first.indices {
            for secondIndex in second.indices {
                let resultIndex = firstIndex + secondIndex
                let coefficient = try bernsteinProductCoefficient(
                    firstDegree: firstDegree,
                    firstIndex: firstIndex,
                    secondDegree: secondDegree,
                    secondIndex: secondIndex,
                    tolerance: tolerance
                )
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
    ) throws -> [Vector3D] {
        let vectorDegree = vectors.count - 1
        let scalarDegree = scalars.count - 1
        let resultDegree = vectorDegree + scalarDegree
        var result = Array(repeating: Vector3D.zero, count: resultDegree + 1)
        for vectorIndex in vectors.indices {
            for scalarIndex in scalars.indices {
                let resultIndex = vectorIndex + scalarIndex
                let coefficient = try bernsteinProductCoefficient(
                    firstDegree: vectorDegree,
                    firstIndex: vectorIndex,
                    secondDegree: scalarDegree,
                    secondIndex: scalarIndex,
                    tolerance: tolerance
                )
                result[resultIndex] = result[resultIndex]
                    + vectors[vectorIndex]
                        * (scalars[scalarIndex] * coefficient)
            }
        }
        guard result.allSatisfy(\.isFinite) else {
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
    ) throws -> Double {
        let numerator = binomial(firstDegree, firstIndex)
            * binomial(secondDegree, secondIndex)
        let denominator = binomial(
            firstDegree + secondDegree,
            firstIndex + secondIndex
        )
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

    private func binomial(_ degree: Int, _ index: Int) -> Double {
        let reduced = min(index, degree - index)
        guard reduced > 0 else { return 1.0 }
        var result = 1.0
        for step in 1...reduced {
            result *= Double(degree - reduced + step) / Double(step)
        }
        return result
    }

    private func assemble(
        patches: [TensorPatch],
        breaks: [Double],
        degree: Int,
        tolerance: ModelingTolerance
    ) throws -> BSplineSurface3D {
        guard patches.isEmpty == false,
              breaks.count == patches.count + 1 else {
            throw diagnostic(
                code: .resourceLimitExceeded,
                tolerance: tolerance,
                message: "Exact ruled surface assembly requires a complete span sequence."
            )
        }
        let controlCount = patches.count * degree + 1
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
                    let globalU = spanIndex * degree + localU
                    let candidate = patch.controls[vIndex][localU]
                    if let existing = net[vIndex][globalU] {
                        try validateSharedControl(
                            existing,
                            candidate,
                            tolerance: tolerance
                        )
                    } else {
                        net[vIndex][globalU] = candidate
                    }
                }
            }
        }
        var points: [[Point3D]] = []
        var weights: [[Double]] = []
        for row in net {
            var pointRow: [Point3D] = []
            var weightRow: [Double] = []
            for candidate in row {
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
        let surface = BSplineSurface3D(
            uDegree: degree,
            vDegree: 1,
            uKnots: knotVector(breaks: breaks, degree: degree),
            vKnots: [0.0, 0.0, 1.0, 1.0],
            controlPoints: points,
            weights: weights
        )
        try surface.validate(tolerance: tolerance)
        return surface
    }

    private func validateSharedControl(
        _ first: HomogeneousControl,
        _ second: HomogeneousControl,
        tolerance: ModelingTolerance
    ) throws {
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
    ) -> [Double] {
        var result = Array(repeating: breaks[0], count: degree + 1)
        if breaks.count > 2 {
            for value in breaks.dropFirst().dropLast() {
                result.append(contentsOf: repeatElement(value, count: degree))
            }
        }
        result.append(contentsOf: repeatElement(
            breaks[breaks.count - 1],
            count: degree + 1
        ))
        return result
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
