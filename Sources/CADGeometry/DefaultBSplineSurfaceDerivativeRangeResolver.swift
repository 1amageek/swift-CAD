import CADCore

struct DefaultBSplineSurfaceDerivativeRangeResolver:
    BSplineSurfaceDerivativeRangeResolving
{
    private struct HomogeneousPoint {
        let x: Double
        let y: Double
        let z: Double
        let weight: Double
    }

    func derivativeRanges(
        surface: BSplineSurface3D,
        tolerance: ModelingTolerance
    ) throws -> (
        u: CurveSpatialDerivativeRange,
        v: CurveSpatialDerivativeRange
    ) {
        try surface.validate(tolerance: tolerance)
        let base = surface.controlPoints.indices.map { row in
            surface.controlPoints[row].indices.map { column in
                let point = surface.controlPoints[row][column]
                let weight = surface.weights[row][column]
                return HomogeneousPoint(
                    x: point.x * weight,
                    y: point.y * weight,
                    z: point.z * weight,
                    weight: weight
                )
            }
        }
        let uDerivative = try derivativeU(
            base,
            degree: surface.uDegree,
            knots: surface.uKnots,
            tolerance: tolerance
        )
        let vDerivative = try derivativeV(
            base,
            degree: surface.vDegree,
            knots: surface.vKnots,
            tolerance: tolerance
        )
        return (
            u: try spatialDerivativeRange(
                base: base,
                derivative: uDerivative,
                tolerance: tolerance
            ),
            v: try spatialDerivativeRange(
                base: base,
                derivative: vDerivative,
                tolerance: tolerance
            )
        )
    }

    func derivativeRanges(
        patches: [RationalBezierSurfacePatch3D],
        uInterval: ScalarInterval,
        vInterval: ScalarInterval,
        tolerance: ModelingTolerance
    ) throws -> (
        u: CurveSpatialDerivativeRange,
        v: CurveSpatialDerivativeRange
    ) {
        var resolved: [(
            u: CurveSpatialDerivativeRange,
            v: CurveSpatialDerivativeRange
        )] = []
        resolved.reserveCapacity(patches.count)
        for patch in patches {
            let uLower = max(uInterval.lower, patch.uLower)
            let uUpper = min(uInterval.upper, patch.uUpper)
            let vLower = max(vInterval.lower, patch.vLower)
            let vUpper = min(vInterval.upper, patch.vUpper)
            guard uUpper > uLower, vUpper > vLower else { continue }
            let trimmed = try patch.trimmed(
                uFrom: uLower,
                uTo: uUpper,
                vFrom: vLower,
                vTo: vUpper,
                tolerance: tolerance
            )
            resolved.append(try derivativeRanges(
                patch: trimmed,
                tolerance: tolerance
            ))
        }
        guard let first = resolved.first else {
            throw KernelError(
                phase: .geometry,
                code: .intersectionFailure,
                tolerance: tolerance,
                message: "Surface derivative certification found no Bezier patch intersecting the parameter cell."
            )
        }
        var result = first
        for ranges in resolved.dropFirst() {
            result = (
                u: try union(result.u, ranges.u),
                v: try union(result.v, ranges.v)
            )
        }
        return result
    }

    private func derivativeRanges(
        patch: RationalBezierSurfacePatch3D,
        tolerance: ModelingTolerance
    ) throws -> (
        u: CurveSpatialDerivativeRange,
        v: CurveSpatialDerivativeRange
    ) {
        let base = patch.controlPoints.indices.map { row in
            patch.controlPoints[row].indices.map { column in
                let point = patch.controlPoints[row][column]
                let weight = patch.weights[row][column]
                return HomogeneousPoint(
                    x: point.x * weight,
                    y: point.y * weight,
                    z: point.z * weight,
                    weight: weight
                )
            }
        }
        guard let firstRow = base.first, firstRow.isEmpty == false else {
            throw KernelError(
                phase: .geometry,
                code: .invalidInput,
                tolerance: tolerance,
                message: "Bezier surface derivative certification requires a nonempty control net."
            )
        }
        let uDerivative = try bezierDerivativeU(
            base,
            degree: firstRow.count - 1,
            span: patch.uUpper - patch.uLower,
            tolerance: tolerance
        )
        let vDerivative = try bezierDerivativeV(
            base,
            degree: base.count - 1,
            span: patch.vUpper - patch.vLower,
            tolerance: tolerance
        )
        return (
            u: try spatialDerivativeRange(
                base: base,
                derivative: uDerivative,
                tolerance: tolerance
            ),
            v: try spatialDerivativeRange(
                base: base,
                derivative: vDerivative,
                tolerance: tolerance
            )
        )
    }

    private func bezierDerivativeU(
        _ values: [[HomogeneousPoint]],
        degree: Int,
        span: Double,
        tolerance: ModelingTolerance
    ) throws -> [[HomogeneousPoint]] {
        guard degree > 0 else {
            return values.map { row in row.map { _ in zero } }
        }
        guard span.isFinite, span > 0.0 else {
            throw collapsedBezierSpan(span, tolerance: tolerance)
        }
        let scale = Double(degree) / span
        return values.map { row in
            (0..<degree).map { index in
                difference(from: row[index], to: row[index + 1], scale: scale)
            }
        }
    }

    private func bezierDerivativeV(
        _ values: [[HomogeneousPoint]],
        degree: Int,
        span: Double,
        tolerance: ModelingTolerance
    ) throws -> [[HomogeneousPoint]] {
        guard degree > 0 else {
            return values.map { row in row.map { _ in zero } }
        }
        guard span.isFinite, span > 0.0 else {
            throw collapsedBezierSpan(span, tolerance: tolerance)
        }
        let scale = Double(degree) / span
        return (0..<degree).map { row in
            values[row].indices.map { column in
                difference(
                    from: values[row][column],
                    to: values[row + 1][column],
                    scale: scale
                )
            }
        }
    }

    private func difference(
        from lower: HomogeneousPoint,
        to upper: HomogeneousPoint,
        scale: Double
    ) -> HomogeneousPoint {
        HomogeneousPoint(
            x: (upper.x - lower.x) * scale,
            y: (upper.y - lower.y) * scale,
            z: (upper.z - lower.z) * scale,
            weight: (upper.weight - lower.weight) * scale
        )
    }

    private func union(
        _ first: CurveSpatialDerivativeRange,
        _ second: CurveSpatialDerivativeRange
    ) throws -> CurveSpatialDerivativeRange {
        CurveSpatialDerivativeRange(
            x: try union(first.x, second.x),
            y: try union(first.y, second.y),
            z: try union(first.z, second.z)
        )
    }

    private func union(
        _ first: ScalarInterval,
        _ second: ScalarInterval
    ) throws -> ScalarInterval {
        try ScalarInterval(
            lower: min(first.lower, second.lower).nextDown,
            upper: max(first.upper, second.upper).nextUp
        )
    }

    private func collapsedBezierSpan(
        _ span: Double,
        tolerance: ModelingTolerance
    ) -> KernelError {
        KernelError(
            phase: .geometry,
            code: .singularSystem,
            residual: span,
            tolerance: tolerance,
            message: "Bezier surface derivative control interval collapsed."
        )
    }

    private func spatialDerivativeRange(
        base: [[HomogeneousPoint]],
        derivative: [[HomogeneousPoint]],
        tolerance: ModelingTolerance
    ) throws -> CurveSpatialDerivativeRange {
        let baseValues = base.flatMap { $0 }
        let derivativeValues = derivative.flatMap { $0 }
        let weight = try outwardInterval(baseValues.map(\.weight))
        guard weight.lower > 0.0 else {
            throw KernelError(
                phase: .geometry,
                code: .singularSystem,
                residual: weight.lower,
                tolerance: tolerance,
                message: "Rational surface derivative certification requires a positive denominator."
            )
        }
        let derivativeWeight = try outwardInterval(
            derivativeValues.map(\.weight)
        )
        let denominator = try multiplied(weight, weight)
        return try CurveSpatialDerivativeRange(
            x: quotientDerivative(
                coordinate: try outwardInterval(baseValues.map(\.x)),
                derivativeCoordinate:
                    try outwardInterval(derivativeValues.map(\.x)),
                weight: weight,
                derivativeWeight: derivativeWeight,
                denominator: denominator
            ),
            y: quotientDerivative(
                coordinate: try outwardInterval(baseValues.map(\.y)),
                derivativeCoordinate:
                    try outwardInterval(derivativeValues.map(\.y)),
                weight: weight,
                derivativeWeight: derivativeWeight,
                denominator: denominator
            ),
            z: quotientDerivative(
                coordinate: try outwardInterval(baseValues.map(\.z)),
                derivativeCoordinate:
                    try outwardInterval(derivativeValues.map(\.z)),
                weight: weight,
                derivativeWeight: derivativeWeight,
                denominator: denominator
            )
        )
    }

    private func quotientDerivative(
        coordinate: ScalarInterval,
        derivativeCoordinate: ScalarInterval,
        weight: ScalarInterval,
        derivativeWeight: ScalarInterval,
        denominator: ScalarInterval
    ) throws -> ScalarInterval {
        let numerator = try subtracting(
            multiplied(derivativeCoordinate, weight),
            multiplied(coordinate, derivativeWeight)
        )
        return try divided(numerator, by: denominator)
    }

    private func derivativeU(
        _ values: [[HomogeneousPoint]],
        degree: Int,
        knots: [Double],
        tolerance: ModelingTolerance
    ) throws -> [[HomogeneousPoint]] {
        guard degree > 0 else {
            return values.map { row in
                row.map { _ in zero }
            }
        }
        return try values.map { row in
            try (0..<(row.count - 1)).map { index in
                let denominator =
                    knots[index + degree + 1] - knots[index + 1]
                return try derivative(
                    from: row[index],
                    to: row[index + 1],
                    degree: degree,
                    denominator: denominator,
                    tolerance: tolerance
                )
            }
        }
    }

    private func derivativeV(
        _ values: [[HomogeneousPoint]],
        degree: Int,
        knots: [Double],
        tolerance: ModelingTolerance
    ) throws -> [[HomogeneousPoint]] {
        guard degree > 0 else {
            return values.map { row in
                row.map { _ in zero }
            }
        }
        return try (0..<(values.count - 1)).map { row in
            try values[row].indices.map { column in
                let denominator =
                    knots[row + degree + 1] - knots[row + 1]
                return try derivative(
                    from: values[row][column],
                    to: values[row + 1][column],
                    degree: degree,
                    denominator: denominator,
                    tolerance: tolerance
                )
            }
        }
    }

    private func derivative(
        from lower: HomogeneousPoint,
        to upper: HomogeneousPoint,
        degree: Int,
        denominator: Double,
        tolerance: ModelingTolerance
    ) throws -> HomogeneousPoint {
        guard denominator.isFinite, denominator > 0.0 else {
            throw KernelError(
                phase: .geometry,
                code: .singularSystem,
                residual: denominator,
                tolerance: tolerance,
                message: "Rational surface derivative control interval collapsed."
            )
        }
        let scale = Double(degree) / denominator
        return HomogeneousPoint(
            x: (upper.x - lower.x) * scale,
            y: (upper.y - lower.y) * scale,
            z: (upper.z - lower.z) * scale,
            weight: (upper.weight - lower.weight) * scale
        )
    }

    private var zero: HomogeneousPoint {
        HomogeneousPoint(x: 0.0, y: 0.0, z: 0.0, weight: 0.0)
    }

    private func outwardInterval(
        _ values: [Double]
    ) throws -> ScalarInterval {
        guard let minimum = values.min(),
              let maximum = values.max(),
              minimum.isFinite,
              maximum.isFinite else {
            throw arithmeticFailure()
        }
        return try ScalarInterval(
            lower: minimum.nextDown,
            upper: maximum.nextUp
        )
    }

    private func multiplied(
        _ first: ScalarInterval,
        _ second: ScalarInterval
    ) throws -> ScalarInterval {
        try outwardInterval([
            first.lower * second.lower,
            first.lower * second.upper,
            first.upper * second.lower,
            first.upper * second.upper,
        ])
    }

    private func subtracting(
        _ first: ScalarInterval,
        _ second: ScalarInterval
    ) throws -> ScalarInterval {
        try outwardInterval([
            first.lower - second.upper,
            first.upper - second.lower,
        ])
    }

    private func divided(
        _ numerator: ScalarInterval,
        by denominator: ScalarInterval
    ) throws -> ScalarInterval {
        guard denominator.lower > 0.0 else {
            throw arithmeticFailure()
        }
        return try outwardInterval([
            numerator.lower / denominator.lower,
            numerator.lower / denominator.upper,
            numerator.upper / denominator.lower,
            numerator.upper / denominator.upper,
        ])
    }

    private func arithmeticFailure() -> KernelError {
        KernelError(
            phase: .geometry,
            code: .resourceLimitExceeded,
            tolerance: nil,
            message: "Rational surface derivative interval arithmetic exceeded finite representation."
        )
    }
}
