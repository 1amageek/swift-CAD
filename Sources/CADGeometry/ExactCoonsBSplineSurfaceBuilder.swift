import CADCore

public struct ExactCoonsBSplineSurfaceBuilder: TransfiniteBSplineSurfaceBuilding {
    private let basisResolver: any BSplineCurveCommonBasisResolving
    public var maximumPatchCount: Int
    public var maximumResultDegree: Int

    public init(
        basisResolver: any BSplineCurveCommonBasisResolving = DefaultBSplineCurveCommonBasisResolver(),
        maximumPatchCount: Int = 65_536,
        maximumResultDegree: Int = 64
    ) {
        self.basisResolver = basisResolver
        self.maximumPatchCount = maximumPatchCount
        self.maximumResultDegree = maximumResultDegree
    }

    public func build(
        vMinimumBoundary: BSplineCurve3D,
        vMaximumBoundary: BSplineCurve3D,
        uMinimumBoundary: BSplineCurve3D,
        uMaximumBoundary: BSplineCurve3D,
        tolerance: ModelingTolerance
    ) throws -> BSplineSurface3D {
        try tolerance.validate()
        guard maximumPatchCount > 0, maximumResultDegree > 0 else {
            throw diagnostic(
                code: .invalidInput,
                tolerance: tolerance,
                message: "Exact Coons construction requires positive resource limits."
            )
        }
        let horizontal = try basisResolver.resolve(
            first: vMinimumBoundary,
            second: vMaximumBoundary,
            tolerance: tolerance
        )
        let vertical = try basisResolver.resolve(
            first: uMinimumBoundary,
            second: uMaximumBoundary,
            tolerance: tolerance
        )
        let corners = try validatedCorners(
            vMinimum: horizontal.first,
            vMaximum: horizontal.second,
            uMinimum: vertical.first,
            uMaximum: vertical.second,
            tolerance: tolerance
        )
        let horizontalMinimumPatches = try patches(
            of: horizontal.first,
            tolerance: tolerance
        )
        let horizontalMaximumPatches = try patches(
            of: horizontal.second,
            tolerance: tolerance
        )
        let verticalMinimumPatches = try patches(
            of: vertical.first,
            tolerance: tolerance
        )
        let verticalMaximumPatches = try patches(
            of: vertical.second,
            tolerance: tolerance
        )
        guard horizontalMinimumPatches.count == horizontalMaximumPatches.count,
              verticalMinimumPatches.count == verticalMaximumPatches.count else {
            throw diagnostic(
                code: .resourceLimitExceeded,
                tolerance: tolerance,
                message: "Exact Coons construction lost an aligned boundary span."
            )
        }
        let patchCount = horizontalMinimumPatches.count * verticalMinimumPatches.count
        guard patchCount <= maximumPatchCount else {
            throw diagnostic(
                code: .resourceLimitExceeded,
                residual: Double(patchCount),
                tolerance: tolerance,
                message: "Exact Coons construction exceeded its tensor patch budget."
            )
        }
        let uDegree = horizontal.first.degree * 2 + 1
        let vDegree = vertical.first.degree * 2 + 1
        guard uDegree <= maximumResultDegree, vDegree <= maximumResultDegree else {
            throw diagnostic(
                code: .resourceLimitExceeded,
                residual: Double(max(uDegree, vDegree)),
                tolerance: tolerance,
                message: "Exact Coons construction exceeded its result-degree budget."
            )
        }

        var tensorPatches: [[TensorPatch]] = []
        tensorPatches.reserveCapacity(verticalMinimumPatches.count)
        for vIndex in verticalMinimumPatches.indices {
            var row: [TensorPatch] = []
            row.reserveCapacity(horizontalMinimumPatches.count)
            for uIndex in horizontalMinimumPatches.indices {
                row.append(try tensorPatch(
                    vMinimum: horizontalMinimumPatches[uIndex],
                    vMaximum: horizontalMaximumPatches[uIndex],
                    uMinimum: verticalMinimumPatches[vIndex],
                    uMaximum: verticalMaximumPatches[vIndex],
                    corners: corners,
                    uDegree: uDegree,
                    vDegree: vDegree,
                    tolerance: tolerance
                ))
            }
            tensorPatches.append(row)
        }
        return try assemble(
            patches: tensorPatches,
            uBreaks: breaks(from: horizontalMinimumPatches),
            vBreaks: breaks(from: verticalMinimumPatches),
            uDegree: uDegree,
            vDegree: vDegree,
            tolerance: tolerance
        )
    }

    private struct Corners: Sendable {
        let minimumMinimum: Point3D
        let maximumMinimum: Point3D
        let minimumMaximum: Point3D
        let maximumMaximum: Point3D
    }

    private struct HomogeneousControl: Sendable {
        let numerator: Vector3D
        let weight: Double

        init(point: Point3D, weight: Double) {
            numerator = Vector3D(
                x: point.x * weight,
                y: point.y * weight,
                z: point.z * weight
            )
            self.weight = weight
        }
    }

    private struct TensorPatch: Sendable {
        let controls: [[HomogeneousControl]]
    }

    private func validatedCorners(
        vMinimum: BSplineCurve3D,
        vMaximum: BSplineCurve3D,
        uMinimum: BSplineCurve3D,
        uMaximum: BSplineCurve3D,
        tolerance: ModelingTolerance
    ) throws -> Corners {
        let minimumMinimum = try vMinimum.point(at: 0.0, tolerance: tolerance)
        let maximumMinimum = try vMinimum.point(at: 1.0, tolerance: tolerance)
        let minimumMaximum = try vMaximum.point(at: 0.0, tolerance: tolerance)
        let maximumMaximum = try vMaximum.point(at: 1.0, tolerance: tolerance)
        let residuals = [
            try (minimumMinimum - uMinimum.point(at: 0.0, tolerance: tolerance)).length,
            try (maximumMinimum - uMaximum.point(at: 0.0, tolerance: tolerance)).length,
            try (minimumMaximum - uMinimum.point(at: 1.0, tolerance: tolerance)).length,
            try (maximumMaximum - uMaximum.point(at: 1.0, tolerance: tolerance)).length,
        ]
        let residual = residuals.max() ?? .infinity
        guard residual <= tolerance.distance else {
            throw diagnostic(
                code: .invalidInput,
                residual: residual,
                tolerance: tolerance,
                message: "Oriented patch boundaries do not meet at all four corners."
            )
        }
        return Corners(
            minimumMinimum: minimumMinimum,
            maximumMinimum: maximumMinimum,
            minimumMaximum: minimumMaximum,
            maximumMaximum: maximumMaximum
        )
    }

    private func patches(
        of curve: BSplineCurve3D,
        tolerance: ModelingTolerance
    ) throws -> [RationalBezierCurvePatch3D] {
        let result = try BSplineCurveBezierDecomposer().curvePatches(
            curve: curve,
            tolerance: tolerance
        )
        guard result.isEmpty == false else {
            throw diagnostic(
                code: .invalidInput,
                tolerance: tolerance,
                message: "Exact Coons construction requires non-empty boundary spans."
            )
        }
        return result
    }

    private func tensorPatch(
        vMinimum: RationalBezierCurvePatch3D,
        vMaximum: RationalBezierCurvePatch3D,
        uMinimum: RationalBezierCurvePatch3D,
        uMaximum: RationalBezierCurvePatch3D,
        corners: Corners,
        uDegree: Int,
        vDegree: Int,
        tolerance: ModelingTolerance
    ) throws -> TensorPatch {
        let vMinimumHomogeneous = homogeneous(vMinimum)
        let vMaximumHomogeneous = homogeneous(vMaximum)
        let uMinimumHomogeneous = homogeneous(uMinimum)
        let uMaximumHomogeneous = homogeneous(uMaximum)
        let horizontalWeightProduct = try product(
            vMinimum.weights,
            vMaximum.weights,
            tolerance: tolerance
        )
        let verticalWeightProduct = try product(
            uMinimum.weights,
            uMaximum.weights,
            tolerance: tolerance
        )

        let vMinimumNumerator = try vectorTimesScalar(
            vMinimumHomogeneous.map(\.numerator),
            vMaximum.weights,
            tolerance: tolerance
        )
        let vMaximumNumerator = try vectorTimesScalar(
            vMaximumHomogeneous.map(\.numerator),
            vMinimum.weights,
            tolerance: tolerance
        )
        let uMinimumNumerator = try vectorTimesScalar(
            uMinimumHomogeneous.map(\.numerator),
            uMaximum.weights,
            tolerance: tolerance
        )
        let uMaximumNumerator = try vectorTimesScalar(
            uMaximumHomogeneous.map(\.numerator),
            uMinimum.weights,
            tolerance: tolerance
        )

        let uOneMinus = [1.0 - vMinimum.lower, 1.0 - vMinimum.upper]
        let uValue = [vMinimum.lower, vMinimum.upper]
        let vOneMinus = [1.0 - uMinimum.lower, 1.0 - uMinimum.upper]
        let vValue = [uMinimum.lower, uMinimum.upper]

        let horizontalMinimumVFactor = try product(
            verticalWeightProduct,
            vOneMinus,
            tolerance: tolerance
        )
        let horizontalMaximumVFactor = try product(
            verticalWeightProduct,
            vValue,
            tolerance: tolerance
        )
        let verticalMinimumUFactor = try product(
            horizontalWeightProduct,
            uOneMinus,
            tolerance: tolerance
        )
        let verticalMaximumUFactor = try product(
            horizontalWeightProduct,
            uValue,
            tolerance: tolerance
        )

        var numerator = zeroVectorGrid(uDegree: uDegree, vDegree: vDegree)
        try addOuter(
            uVector: elevated(vMinimumNumerator, to: uDegree),
            vScalar: horizontalMinimumVFactor,
            scale: 1.0,
            to: &numerator,
            tolerance: tolerance
        )
        try addOuter(
            uVector: elevated(vMaximumNumerator, to: uDegree),
            vScalar: horizontalMaximumVFactor,
            scale: 1.0,
            to: &numerator,
            tolerance: tolerance
        )
        try addOuter(
            uScalar: verticalMinimumUFactor,
            vVector: elevated(uMinimumNumerator, to: vDegree),
            scale: 1.0,
            to: &numerator,
            tolerance: tolerance
        )
        try addOuter(
            uScalar: verticalMaximumUFactor,
            vVector: elevated(uMaximumNumerator, to: vDegree),
            scale: 1.0,
            to: &numerator,
            tolerance: tolerance
        )

        try subtractCorner(
            corners.minimumMinimum,
            uFactor: verticalMinimumUFactor,
            vFactor: horizontalMinimumVFactor,
            from: &numerator,
            tolerance: tolerance
        )
        try subtractCorner(
            corners.maximumMinimum,
            uFactor: verticalMaximumUFactor,
            vFactor: horizontalMinimumVFactor,
            from: &numerator,
            tolerance: tolerance
        )
        try subtractCorner(
            corners.minimumMaximum,
            uFactor: verticalMinimumUFactor,
            vFactor: horizontalMaximumVFactor,
            from: &numerator,
            tolerance: tolerance
        )
        try subtractCorner(
            corners.maximumMaximum,
            uFactor: verticalMaximumUFactor,
            vFactor: horizontalMaximumVFactor,
            from: &numerator,
            tolerance: tolerance
        )

        let uWeights = elevated(horizontalWeightProduct, to: uDegree)
        let vWeights = elevated(verticalWeightProduct, to: vDegree)
        var controls: [[HomogeneousControl]] = []
        controls.reserveCapacity(vDegree + 1)
        for vIndex in 0...vDegree {
            var row: [HomogeneousControl] = []
            row.reserveCapacity(uDegree + 1)
            for uIndex in 0...uDegree {
                let weight = uWeights[uIndex] * vWeights[vIndex]
                let value = numerator[vIndex][uIndex]
                guard weight.isFinite,
                      weight > 0.0,
                      value.isFinite else {
                    throw diagnostic(
                        code: .resourceLimitExceeded,
                        residual: weight,
                        tolerance: tolerance,
                        message: "Exact Coons homogeneous control exceeded the finite positive-weight range."
                    )
                }
                row.append(HomogeneousControl(
                    point: Point3D(
                        x: value.x / weight,
                        y: value.y / weight,
                        z: value.z / weight
                    ),
                    weight: weight
                ))
            }
            controls.append(row)
        }
        return TensorPatch(controls: controls)
    }

    private func homogeneous(
        _ patch: RationalBezierCurvePatch3D
    ) -> [HomogeneousControl] {
        patch.controlPoints.indices.map { index in
            HomogeneousControl(
                point: patch.controlPoints[index],
                weight: patch.weights[index]
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
                result[resultIndex] += first[firstIndex] * second[secondIndex] * coefficient
            }
        }
        guard result.allSatisfy(\.isFinite) else {
            throw diagnostic(
                code: .resourceLimitExceeded,
                tolerance: tolerance,
                message: "Bernstein scalar multiplication exceeded the finite numeric range."
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
                    + vectors[vectorIndex] * (scalars[scalarIndex] * coefficient)
            }
        }
        guard result.allSatisfy(\.isFinite) else {
            throw diagnostic(
                code: .resourceLimitExceeded,
                tolerance: tolerance,
                message: "Bernstein vector multiplication exceeded the finite numeric range."
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
                message: "Bernstein product coefficient exceeded the finite numeric range."
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

    private func elevated(_ values: [Double], to targetDegree: Int) -> [Double] {
        var result = values
        while result.count - 1 < targetDegree {
            let degree = result.count - 1
            var next = Array(repeating: 0.0, count: result.count + 1)
            next[0] = result[0]
            next[next.count - 1] = result[result.count - 1]
            if degree > 0 {
                for index in 1...degree {
                    let alpha = Double(index) / Double(degree + 1)
                    next[index] = result[index - 1] * alpha
                        + result[index] * (1.0 - alpha)
                }
            }
            result = next
        }
        return result
    }

    private func elevated(
        _ values: [Vector3D],
        to targetDegree: Int
    ) -> [Vector3D] {
        var result = values
        while result.count - 1 < targetDegree {
            let degree = result.count - 1
            var next = Array(repeating: Vector3D.zero, count: result.count + 1)
            next[0] = result[0]
            next[next.count - 1] = result[result.count - 1]
            if degree > 0 {
                for index in 1...degree {
                    let alpha = Double(index) / Double(degree + 1)
                    next[index] = result[index - 1] * alpha
                        + result[index] * (1.0 - alpha)
                }
            }
            result = next
        }
        return result
    }

    private func zeroVectorGrid(
        uDegree: Int,
        vDegree: Int
    ) -> [[Vector3D]] {
        Array(
            repeating: Array(repeating: .zero, count: uDegree + 1),
            count: vDegree + 1
        )
    }

    private func addOuter(
        uVector: [Vector3D],
        vScalar: [Double],
        scale: Double,
        to result: inout [[Vector3D]],
        tolerance: ModelingTolerance
    ) throws {
        guard result.count == vScalar.count,
              result.allSatisfy({ $0.count == uVector.count }) else {
            throw diagnostic(
                code: .resourceLimitExceeded,
                tolerance: tolerance,
                message: "Exact Coons horizontal tensor dimensions are inconsistent."
            )
        }
        for vIndex in vScalar.indices {
            for uIndex in uVector.indices {
                result[vIndex][uIndex] = result[vIndex][uIndex]
                    + uVector[uIndex] * (vScalar[vIndex] * scale)
            }
        }
    }

    private func addOuter(
        uScalar: [Double],
        vVector: [Vector3D],
        scale: Double,
        to result: inout [[Vector3D]],
        tolerance: ModelingTolerance
    ) throws {
        guard result.count == vVector.count,
              result.allSatisfy({ $0.count == uScalar.count }) else {
            throw diagnostic(
                code: .resourceLimitExceeded,
                tolerance: tolerance,
                message: "Exact Coons vertical tensor dimensions are inconsistent."
            )
        }
        for vIndex in vVector.indices {
            for uIndex in uScalar.indices {
                result[vIndex][uIndex] = result[vIndex][uIndex]
                    + vVector[vIndex] * (uScalar[uIndex] * scale)
            }
        }
    }

    private func subtractCorner(
        _ point: Point3D,
        uFactor: [Double],
        vFactor: [Double],
        from result: inout [[Vector3D]],
        tolerance: ModelingTolerance
    ) throws {
        let vector = Vector3D(x: point.x, y: point.y, z: point.z)
        let uVector = uFactor.map { vector * $0 }
        try addOuter(
            uVector: uVector,
            vScalar: vFactor,
            scale: -1.0,
            to: &result,
            tolerance: tolerance
        )
    }

    private func breaks(
        from patches: [RationalBezierCurvePatch3D]
    ) -> [Double] {
        [patches[0].lower] + patches.map(\.upper)
    }

    private func assemble(
        patches: [[TensorPatch]],
        uBreaks: [Double],
        vBreaks: [Double],
        uDegree: Int,
        vDegree: Int,
        tolerance: ModelingTolerance
    ) throws -> BSplineSurface3D {
        let uCount = (uBreaks.count - 1) * uDegree + 1
        let vCount = (vBreaks.count - 1) * vDegree + 1
        var net = Array(
            repeating: Array<HomogeneousControl?>(repeating: nil, count: uCount),
            count: vCount
        )
        for vSpan in patches.indices {
            for uSpan in patches[vSpan].indices {
                let patch = patches[vSpan][uSpan]
                for localV in 0...vDegree {
                    for localU in 0...uDegree {
                        let globalV = vSpan * vDegree + localV
                        let globalU = uSpan * uDegree + localU
                        let candidate = patch.controls[localV][localU]
                        if let existing = net[globalV][globalU] {
                            try validateSharedControl(
                                existing,
                                candidate,
                                tolerance: tolerance
                            )
                        } else {
                            net[globalV][globalU] = candidate
                        }
                    }
                }
            }
        }
        var controlPoints: [[Point3D]] = []
        var weights: [[Double]] = []
        controlPoints.reserveCapacity(vCount)
        weights.reserveCapacity(vCount)
        for row in net {
            var pointRow: [Point3D] = []
            var weightRow: [Double] = []
            pointRow.reserveCapacity(uCount)
            weightRow.reserveCapacity(uCount)
            for value in row {
                guard let control = value,
                      control.weight.isFinite,
                      control.weight > 0.0,
                      control.numerator.isFinite else {
                    throw diagnostic(
                        code: .resourceLimitExceeded,
                        tolerance: tolerance,
                        message: "Exact Coons global control net is incomplete or non-finite."
                    )
                }
                pointRow.append(Point3D(
                    x: control.numerator.x / control.weight,
                    y: control.numerator.y / control.weight,
                    z: control.numerator.z / control.weight
                ))
                weightRow.append(control.weight)
            }
            controlPoints.append(pointRow)
            weights.append(weightRow)
        }
        let surface = BSplineSurface3D(
            uDegree: uDegree,
            vDegree: vDegree,
            uKnots: knotVector(breaks: uBreaks, degree: uDegree),
            vKnots: knotVector(breaks: vBreaks, degree: vDegree),
            controlPoints: controlPoints,
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
                message: "Adjacent exact Coons tensor patches did not retain one homogeneous boundary control."
            )
        }
    }

    private func knotVector(breaks: [Double], degree: Int) -> [Double] {
        var result = Array(repeating: breaks[0], count: degree + 1)
        if breaks.count > 2 {
            for value in breaks.dropFirst().dropLast() {
                result.append(contentsOf: repeatElement(value, count: degree))
            }
        }
        result.append(contentsOf: repeatElement(breaks[breaks.count - 1], count: degree + 1))
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
