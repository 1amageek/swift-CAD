import CADCore
import CADGeometry

/// Extracts every active rational B-spline surface span as a homogeneous
/// Bezier patch. Basis derivatives and tensor Bernstein reconstruction use
/// outward-rounded bounds for clamped and non-clamped knot vectors alike.
struct CertifiedBSplineSurfaceBezierExtractor {
    private typealias Patch = CertifiedHomogeneousBezierSurfacePatch
    private typealias Point = Patch.HomogeneousPoint
    private typealias Scalar = Patch.ScalarBounds

    private let maximumControlOperations: Int

    init(maximumControlOperations: Int = 4_000_000) {
        self.maximumControlOperations = maximumControlOperations
    }

    func patches(
        surface: BSplineSurface3D,
        tolerance: ModelingTolerance
    ) throws -> [CertifiedHomogeneousBezierSurfacePatch]? {
        try tolerance.validate()
        try surface.validate(tolerance: tolerance)
        guard surface.uDegree >= 1,
              surface.vDegree >= 1,
              case let .closed(uDomainLower, uDomainUpper) = surface.uDomain,
              case let .closed(vDomainLower, vDomainUpper) = surface.vDomain,
              uDomainUpper > uDomainLower,
              vDomainUpper > vDomainLower else {
            throw KernelError(
                phase: .topology,
                code: .invalidInput,
                tolerance: tolerance,
                message: "Certified B-spline surface extraction requires positive bounded parameter domains."
            )
        }
        if isSingleBezierPatch(
            degree: surface.uDegree,
            knots: surface.uKnots,
            controlCount: surface.uControlPointCount,
            lower: uDomainLower,
            upper: uDomainUpper
        ), isSingleBezierPatch(
            degree: surface.vDegree,
            knots: surface.vKnots,
            controlCount: surface.vControlPointCount,
            lower: vDomainLower,
            upper: vDomainUpper
        ) {
            let controls = surface.controlPoints.indices.map { vIndex in
                surface.controlPoints[vIndex].indices.map { uIndex in
                    let point = surface.controlPoints[vIndex][uIndex]
                    let weight = Scalar.exact(surface.weights[vIndex][uIndex])
                    return Point(
                        x: Scalar.exact(point.x) * weight,
                        y: Scalar.exact(point.y) * weight,
                        z: Scalar.exact(point.z) * weight,
                        weight: weight
                    )
                }
            }
            guard controls.flatMap({ $0 }).allSatisfy(
                \.isFiniteAndPositiveWeight
            ) else {
                throw KernelError(
                    phase: .topology,
                    code: .singularSystem,
                    tolerance: tolerance,
                    message: "Certified Bezier surface extraction requires finite positive homogeneous controls."
                )
            }
            return [Patch(
                controls: controls,
                uLower: uDomainLower,
                uUpper: uDomainUpper,
                vLower: vDomainLower,
                vUpper: vDomainUpper
            )]
        }
        let uBreaks = parameterBreaks(
            knots: surface.uKnots,
            lower: uDomainLower,
            upper: uDomainUpper
        )
        let vBreaks = parameterBreaks(
            knots: surface.vKnots,
            lower: vDomainLower,
            upper: vDomainUpper
        )
        let constantWeight = exactConstantWeight(surface.weights)
        guard uBreaks.count >= 2, vBreaks.count >= 2 else {
            throw KernelError(
                phase: .topology,
                code: .topologyFailure,
                tolerance: tolerance,
                message: "Certified B-spline surface extraction found no active Bezier patch."
            )
        }

        var operationCount = 0
        var result: [Patch] = []
        result.reserveCapacity((uBreaks.count - 1) * (vBreaks.count - 1))
        for vSpanIndex in 0..<(vBreaks.count - 1) {
            let vLower = vBreaks[vSpanIndex]
            let vUpper = vBreaks[vSpanIndex + 1]
            let vSpan = Scalar.exact(vUpper) - Scalar.exact(vLower)
            guard vSpan.lower > 0.0 else {
                throw nonPositiveSpanFailure(
                    residual: vSpan.lower,
                    tolerance: tolerance
                )
            }
            let vBasis = try basisDerivativeTable(
                parameter: vLower,
                degree: surface.vDegree,
                knots: surface.vKnots,
                count: surface.vControlPointCount,
                operationCount: &operationCount,
                tolerance: tolerance
            )
            let vScales = try bernsteinScales(
                degree: surface.vDegree,
                span: vSpan,
                operationCount: &operationCount,
                tolerance: tolerance
            )
            for uSpanIndex in 0..<(uBreaks.count - 1) {
                let uLower = uBreaks[uSpanIndex]
                let uUpper = uBreaks[uSpanIndex + 1]
                let uSpan = Scalar.exact(uUpper) - Scalar.exact(uLower)
                guard uSpan.lower > 0.0 else {
                    throw nonPositiveSpanFailure(
                        residual: uSpan.lower,
                        tolerance: tolerance
                    )
                }
                let uBasis = try basisDerivativeTable(
                    parameter: uLower,
                    degree: surface.uDegree,
                    knots: surface.uKnots,
                    count: surface.uControlPointCount,
                    operationCount: &operationCount,
                    tolerance: tolerance
                )
                let uScales = try bernsteinScales(
                    degree: surface.uDegree,
                    span: uSpan,
                    operationCount: &operationCount,
                    tolerance: tolerance
                )
                var derivatives = Array(
                    repeating: Array(
                        repeating: zeroPoint,
                        count: surface.uDegree + 1
                    ),
                    count: surface.vDegree + 1
                )
                for vOrder in 0...surface.vDegree {
                    for uOrder in 0...surface.uDegree {
                        derivatives[vOrder][uOrder] = try homogeneousDerivative(
                            surface: surface,
                            uBasis: uBasis[uOrder],
                            vBasis: vBasis[vOrder],
                            operationCount: &operationCount,
                            tolerance: tolerance
                        )
                    }
                }
                var controls = try bernsteinControls(
                    derivatives: derivatives,
                    uScales: uScales,
                    vScales: vScales,
                    operationCount: &operationCount,
                    tolerance: tolerance
                )
                if let constantWeight {
                    controls = controls.map { row in
                        row.map { control in
                            Point(
                                x: control.x,
                                y: control.y,
                                z: control.z,
                                weight: .exact(constantWeight)
                            )
                        }
                    }
                }
                guard controls.flatMap({ $0 }).allSatisfy(
                    \.isFiniteAndPositiveWeight
                ) else {
                    throw KernelError(
                        phase: .topology,
                        code: .singularSystem,
                        tolerance: tolerance,
                        message: "Certified B-spline surface extraction could not prove positive finite homogeneous weights."
                    )
                }
                result.append(Patch(
                    controls: controls,
                    uLower: uLower,
                    uUpper: uUpper,
                    vLower: vLower,
                    vUpper: vUpper
                ))
            }
        }
        return result
    }

    private func basisDerivativeTable(
        parameter: Double,
        degree: Int,
        knots: [Double],
        count: Int,
        operationCount: inout Int,
        tolerance: ModelingTolerance
    ) throws -> [[Scalar]] {
        try (0...degree).map { derivativeOrder in
            try basisDerivativeValues(
                parameter: parameter,
                degree: degree,
                derivativeOrder: derivativeOrder,
                knots: knots,
                count: count,
                operationCount: &operationCount,
                tolerance: tolerance
            )
        }
    }

    private func basisDerivativeValues(
        parameter: Double,
        degree: Int,
        derivativeOrder: Int,
        knots: [Double],
        count: Int,
        operationCount: inout Int,
        tolerance: ModelingTolerance
    ) throws -> [Scalar] {
        if derivativeOrder == 0 {
            return try basisValues(
                parameter: parameter,
                degree: degree,
                knots: knots,
                count: count,
                operationCount: &operationCount,
                tolerance: tolerance
            )
        }
        guard derivativeOrder <= degree else {
            return Array(repeating: .exact(0.0), count: count)
        }
        let lowerDegree = try basisDerivativeValues(
            parameter: parameter,
            degree: degree - 1,
            derivativeOrder: derivativeOrder - 1,
            knots: knots,
            count: count + 1,
            operationCount: &operationCount,
            tolerance: tolerance
        )
        let factor = Scalar.exact(Double(degree))
        var result = Array(repeating: Scalar.exact(0.0), count: count)
        for index in 0..<count {
            try consume(4, operationCount: &operationCount, tolerance: tolerance)
            let leftDenominator = knots[index + degree] - knots[index]
            let rightDenominator = knots[index + degree + 1] - knots[index + 1]
            let left = leftDenominator > 0.0
                ? factor * lowerDegree[index] / Scalar.exact(leftDenominator)
                : Scalar.exact(0.0)
            let right = rightDenominator > 0.0
                ? factor * lowerDegree[index + 1] / Scalar.exact(rightDenominator)
                : Scalar.exact(0.0)
            result[index] = left - right
        }
        return result
    }

    private func basisValues(
        parameter: Double,
        degree: Int,
        knots: [Double],
        count: Int,
        operationCount: inout Int,
        tolerance: ModelingTolerance
    ) throws -> [Scalar] {
        guard degree > 0 else {
            return (0..<count).map { index in
                parameter >= knots[index] && parameter < knots[index + 1]
                    ? Scalar.exact(1.0)
                    : Scalar.exact(0.0)
            }
        }
        let lowerDegree = try basisValues(
            parameter: parameter,
            degree: degree - 1,
            knots: knots,
            count: count + 1,
            operationCount: &operationCount,
            tolerance: tolerance
        )
        var result = Array(repeating: Scalar.exact(0.0), count: count)
        for index in 0..<count {
            try consume(6, operationCount: &operationCount, tolerance: tolerance)
            let leftDenominator = knots[index + degree] - knots[index]
            let rightDenominator = knots[index + degree + 1] - knots[index + 1]
            let left = leftDenominator > 0.0 && !isExactlyZero(lowerDegree[index])
                ? (Scalar.exact(parameter) - Scalar.exact(knots[index]))
                    * lowerDegree[index]
                    / Scalar.exact(leftDenominator)
                : Scalar.exact(0.0)
            let right = rightDenominator > 0.0
                && !isExactlyZero(lowerDegree[index + 1])
                ? (Scalar.exact(knots[index + degree + 1])
                    - Scalar.exact(parameter))
                    * lowerDegree[index + 1]
                    / Scalar.exact(rightDenominator)
                : Scalar.exact(0.0)
            result[index] = left + right
        }
        return result
    }

    private func homogeneousDerivative(
        surface: BSplineSurface3D,
        uBasis: [Scalar],
        vBasis: [Scalar],
        operationCount: inout Int,
        tolerance: ModelingTolerance
    ) throws -> Point {
        var result = zeroPoint
        for vIndex in 0..<surface.vControlPointCount {
            for uIndex in 0..<surface.uControlPointCount {
                let basis = uBasis[uIndex] * vBasis[vIndex]
                guard !isExactlyZero(basis) else { continue }
                try consume(
                    16,
                    operationCount: &operationCount,
                    tolerance: tolerance
                )
                let weight = Scalar.exact(surface.weights[vIndex][uIndex])
                let coefficient = basis * weight
                let point = surface.controlPoints[vIndex][uIndex]
                result = adding(
                    result,
                    Point(
                        x: Scalar.exact(point.x) * coefficient,
                        y: Scalar.exact(point.y) * coefficient,
                        z: Scalar.exact(point.z) * coefficient,
                        weight: coefficient
                    )
                )
            }
        }
        return result
    }

    private func bernsteinScales(
        degree: Int,
        span: Scalar,
        operationCount: inout Int,
        tolerance: ModelingTolerance
    ) throws -> [[Scalar]] {
        var result: [[Scalar]] = []
        result.reserveCapacity(degree + 1)
        for controlIndex in 0...degree {
            var scales = Array(
                repeating: Scalar.exact(0.0),
                count: controlIndex + 1
            )
            var scale = Scalar.exact(1.0)
            for derivativeOrder in 0...controlIndex {
                scales[derivativeOrder] = scale
                guard derivativeOrder < controlIndex else { continue }
                try consume(
                    6,
                    operationCount: &operationCount,
                    tolerance: tolerance
                )
                scale = scale
                    * Scalar.exact(Double(controlIndex - derivativeOrder))
                    * span
                    / Scalar.exact(Double(derivativeOrder + 1))
                    / Scalar.exact(Double(degree - derivativeOrder))
            }
            result.append(scales)
        }
        return result
    }

    private func bernsteinControls(
        derivatives: [[Point]],
        uScales: [[Scalar]],
        vScales: [[Scalar]],
        operationCount: inout Int,
        tolerance: ModelingTolerance
    ) throws -> [[Point]] {
        var result: [[Point]] = []
        result.reserveCapacity(vScales.count)
        for vControl in vScales.indices {
            var row: [Point] = []
            row.reserveCapacity(uScales.count)
            for uControl in uScales.indices {
                var control = zeroPoint
                for vOrder in vScales[vControl].indices {
                    for uOrder in uScales[uControl].indices {
                        try consume(
                            16,
                            operationCount: &operationCount,
                            tolerance: tolerance
                        )
                        control = adding(
                            control,
                            scaled(
                                derivatives[vOrder][uOrder],
                                by: uScales[uControl][uOrder]
                                    * vScales[vControl][vOrder]
                            )
                        )
                    }
                }
                row.append(control)
            }
            result.append(row)
        }
        return result
    }

    private func consume(
        _ amount: Int,
        operationCount: inout Int,
        tolerance: ModelingTolerance
    ) throws {
        guard amount >= 0,
              operationCount <= maximumControlOperations - amount else {
            throw KernelError(
                phase: .topology,
                code: .resourceLimitExceeded,
                residual: Double(operationCount),
                tolerance: tolerance,
                message: "Certified B-spline surface extraction exhausted its control-operation budget."
            )
        }
        operationCount += amount
    }

    private func parameterBreaks(
        knots: [Double],
        lower: Double,
        upper: Double
    ) -> [Double] {
        var result = [lower]
        for knot in knots where knot > lower && knot < upper && result.last != knot {
            result.append(knot)
        }
        result.append(upper)
        return result
    }

    private func isSingleBezierPatch(
        degree: Int,
        knots: [Double],
        controlCount: Int,
        lower: Double,
        upper: Double
    ) -> Bool {
        guard controlCount == degree + 1,
              knots.count == 2 * (degree + 1) else {
            return false
        }
        return knots.prefix(degree + 1).allSatisfy { $0 == lower }
            && knots.suffix(degree + 1).allSatisfy { $0 == upper }
    }

    private func exactConstantWeight(_ weights: [[Double]]) -> Double? {
        guard let first = weights.first?.first,
              weights.allSatisfy({ row in
                  !row.isEmpty && row.allSatisfy { $0 == first }
              }) else {
            return nil
        }
        return first
    }

    private func adding(_ lhs: Point, _ rhs: Point) -> Point {
        Point(
            x: lhs.x + rhs.x,
            y: lhs.y + rhs.y,
            z: lhs.z + rhs.z,
            weight: lhs.weight + rhs.weight
        )
    }

    private func scaled(_ point: Point, by scalar: Scalar) -> Point {
        Point(
            x: point.x * scalar,
            y: point.y * scalar,
            z: point.z * scalar,
            weight: point.weight * scalar
        )
    }

    private func isExactlyZero(_ value: Scalar) -> Bool {
        value.lower == 0.0 && value.upper == 0.0
    }

    private var zeroPoint: Point {
        Point(
            x: .exact(0.0),
            y: .exact(0.0),
            z: .exact(0.0),
            weight: .exact(0.0)
        )
    }

    private func nonPositiveSpanFailure(
        residual: Double,
        tolerance: ModelingTolerance
    ) -> KernelError {
        KernelError(
            phase: .topology,
            code: .topologyFailure,
            residual: residual,
            tolerance: tolerance,
            message: "Certified B-spline surface extraction found a non-positive active span."
        )
    }
}
