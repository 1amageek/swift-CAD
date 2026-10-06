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
        try checkCancellation()
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
        var operationCount = 0
        let uBreaks = try parameterBreaks(
            knots: surface.uKnots,
            lower: uDomainLower,
            upper: uDomainUpper,
            operationCount: &operationCount,
            tolerance: tolerance
        )
        let vBreaks = try parameterBreaks(
            knots: surface.vKnots,
            lower: vDomainLower,
            upper: vDomainUpper,
            operationCount: &operationCount,
            tolerance: tolerance
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

        var result: [Patch] = []
        let uPatchCount = try checkedDifference(
            uBreaks.count,
            1,
            tolerance: tolerance
        )
        let vPatchCount = try checkedDifference(
            vBreaks.count,
            1,
            tolerance: tolerance
        )
        let patchCount = try checkedProduct(
            uPatchCount,
            vPatchCount,
            tolerance: tolerance
        )
        try consume(
            patchCount,
            operationCount: &operationCount,
            tolerance: tolerance
        )
        result.reserveCapacity(patchCount)
        var vSpanCursor = surface.vDegree
        for vSpanIndex in 0..<(vBreaks.count - 1) {
            try checkCancellation()
            let vLower = vBreaks[vSpanIndex]
            let vUpper = vBreaks[vSpanIndex + 1]
            let vSpanWidth = Scalar.exact(vUpper) - Scalar.exact(vLower)
            guard vSpanWidth.lower > 0.0 else {
                throw nonPositiveSpanFailure(
                    residual: vSpanWidth.lower,
                    tolerance: tolerance
                )
            }
            let vSpan = try localSpan(
                lower: vLower,
                degree: surface.vDegree,
                knots: surface.vKnots,
                controlCount: surface.vControlPointCount,
                spanCursor: &vSpanCursor,
                operationCount: &operationCount,
                tolerance: tolerance
            )
            let vLocalKnots = try localKnots(
                degree: surface.vDegree,
                knots: surface.vKnots,
                span: vSpan,
                operationCount: &operationCount,
                tolerance: tolerance
            )
            let vBasis = try basisDerivativeTable(
                parameter: vLower,
                degree: surface.vDegree,
                knots: vLocalKnots,
                count: surface.vDegree + 1,
                operationCount: &operationCount,
                tolerance: tolerance
            )
            let vScales = try bernsteinScales(
                degree: surface.vDegree,
                span: vSpanWidth,
                operationCount: &operationCount,
                tolerance: tolerance
            )
            var uSpanCursor = surface.uDegree
            for uSpanIndex in 0..<(uBreaks.count - 1) {
                try checkCancellation()
                let uLower = uBreaks[uSpanIndex]
                let uUpper = uBreaks[uSpanIndex + 1]
                let uSpanWidth = Scalar.exact(uUpper) - Scalar.exact(uLower)
                guard uSpanWidth.lower > 0.0 else {
                    throw nonPositiveSpanFailure(
                        residual: uSpanWidth.lower,
                        tolerance: tolerance
                    )
                }
                let uSpan = try localSpan(
                    lower: uLower,
                    degree: surface.uDegree,
                    knots: surface.uKnots,
                    controlCount: surface.uControlPointCount,
                    spanCursor: &uSpanCursor,
                    operationCount: &operationCount,
                    tolerance: tolerance
                )
                let uLocalKnots = try localKnots(
                    degree: surface.uDegree,
                    knots: surface.uKnots,
                    span: uSpan,
                    operationCount: &operationCount,
                    tolerance: tolerance
                )
                let uBasis = try basisDerivativeTable(
                    parameter: uLower,
                    degree: surface.uDegree,
                    knots: uLocalKnots,
                    count: surface.uDegree + 1,
                    operationCount: &operationCount,
                    tolerance: tolerance
                )
                let uScales = try bernsteinScales(
                    degree: surface.uDegree,
                    span: uSpanWidth,
                    operationCount: &operationCount,
                    tolerance: tolerance
                )
                // Charge both local source windows before reading their control
                // points or weights. The basis arrays contain only the active
                // degree + 1 functions in each direction.
                let uLocalCount = try checkedIncrement(
                    surface.uDegree,
                    tolerance: tolerance
                )
                let vLocalCount = try checkedIncrement(
                    surface.vDegree,
                    tolerance: tolerance
                )
                let localNetCount = try checkedProduct(
                    uLocalCount,
                    vLocalCount,
                    tolerance: tolerance
                )
                let localMaterializationCost = try checkedProduct(
                    localNetCount,
                    2,
                    tolerance: tolerance
                )
                try consume(
                    localMaterializationCost,
                    operationCount: &operationCount,
                    tolerance: tolerance
                )
                var derivatives = Array(
                    repeating: Array(
                        repeating: zeroPoint,
                        count: uLocalCount
                    ),
                    count: vLocalCount
                )
                let uControlStart = try checkedDifference(
                    uSpan,
                    surface.uDegree,
                    tolerance: tolerance
                )
                let vControlStart = try checkedDifference(
                    vSpan,
                    surface.vDegree,
                    tolerance: tolerance
                )
                for vOrder in 0...surface.vDegree {
                    for uOrder in 0...surface.uDegree {
                        derivatives[vOrder][uOrder] = try homogeneousDerivative(
                            surface: surface,
                            uBasis: uBasis[uOrder],
                            vBasis: vBasis[vOrder],
                            uControlStart: uControlStart,
                            vControlStart: vControlStart,
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

    /// Returns the last active knot index for the span starting at `lower`.
    /// The cursor is monotonic for one parameter direction, so a span never
    /// restarts a scan over the original knot vector.
    private func localSpan(
        lower: Double,
        degree: Int,
        knots: [Double],
        controlCount: Int,
        spanCursor: inout Int,
        operationCount: inout Int,
        tolerance: ModelingTolerance
    ) throws -> Int {
        var span = spanCursor
        while span + 1 < controlCount {
            try consume(
                1,
                operationCount: &operationCount,
                tolerance: tolerance
            )
            guard knots[span + 1] <= lower else { break }
            span += 1
        }
        spanCursor = span
        return span
    }

    /// Materializes only the original knot slice supported on one span. The
    /// checked charge occurs before any source read or Array allocation.
    private func localKnots(
        degree: Int,
        knots: [Double],
        span: Int,
        operationCount: inout Int,
        tolerance: ModelingTolerance
    ) throws -> [Double] {
        let lowerIndex = try checkedDifference(
            span,
            degree,
            tolerance: tolerance
        )
        let upperBase = try checkedSum(
            span,
            degree,
            tolerance: tolerance
        )
        let upperIndex = try checkedIncrement(
            upperBase,
            tolerance: tolerance
        )
        guard lowerIndex >= 0, upperIndex < knots.count else {
            throw KernelError(
                phase: .topology,
                code: .topologyFailure,
                tolerance: tolerance,
                message: "Certified B-spline surface extraction lost its local knot span."
            )
        }
        let localKnotBaseCount = try checkedDifference(
            upperIndex,
            lowerIndex,
            tolerance: tolerance
        )
        let localKnotCount = try checkedIncrement(
            localKnotBaseCount,
            tolerance: tolerance
        )
        try consume(
            localKnotCount,
            operationCount: &operationCount,
            tolerance: tolerance
        )
        return Array(knots[lowerIndex...upperIndex])
    }

    private func checkedIncrement(
        _ value: Int,
        tolerance: ModelingTolerance
    ) throws -> Int {
        let result = value.addingReportingOverflow(1)
        guard result.overflow == false else {
            throw resourceLimitFailure(tolerance: tolerance)
        }
        return result.partialValue
    }

    private func checkedSum(
        _ lhs: Int,
        _ rhs: Int,
        tolerance: ModelingTolerance
    ) throws -> Int {
        let result = lhs.addingReportingOverflow(rhs)
        guard result.overflow == false else {
            throw resourceLimitFailure(tolerance: tolerance)
        }
        return result.partialValue
    }

    private func checkedDifference(
        _ lhs: Int,
        _ rhs: Int,
        tolerance: ModelingTolerance
    ) throws -> Int {
        let result = lhs.subtractingReportingOverflow(rhs)
        guard result.overflow == false else {
            throw resourceLimitFailure(tolerance: tolerance)
        }
        return result.partialValue
    }

    private func checkedProduct(
        _ lhs: Int,
        _ rhs: Int,
        tolerance: ModelingTolerance
    ) throws -> Int {
        let result = lhs.multipliedReportingOverflow(by: rhs)
        guard result.overflow == false else {
            throw resourceLimitFailure(tolerance: tolerance)
        }
        return result.partialValue
    }

    private func homogeneousDerivative(
        surface: BSplineSurface3D,
        uBasis: [Scalar],
        vBasis: [Scalar],
        uControlStart: Int,
        vControlStart: Int,
        operationCount: inout Int,
        tolerance: ModelingTolerance
    ) throws -> Point {
        var result = zeroPoint
        for vIndex in vBasis.indices {
            for uIndex in uBasis.indices {
                let basis = uBasis[uIndex] * vBasis[vIndex]
                guard !isExactlyZero(basis) else { continue }
                try consume(
                    16,
                    operationCount: &operationCount,
                    tolerance: tolerance
                )
                let sourceVIndex = vControlStart + vIndex
                let sourceUIndex = uControlStart + uIndex
                let weight = Scalar.exact(surface.weights[sourceVIndex][sourceUIndex])
                let coefficient = basis * weight
                let point = surface.controlPoints[sourceVIndex][sourceUIndex]
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
              operationCount <= maximumControlOperations,
              amount <= maximumControlOperations - operationCount else {
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

    private func checkCancellation() throws {
        try Task.checkCancellation()
    }

    private func resourceLimitFailure(
        tolerance: ModelingTolerance
    ) -> KernelError {
        KernelError(
            phase: .topology,
            code: .resourceLimitExceeded,
            tolerance: tolerance,
            message: "Certified B-spline surface extraction exceeded its checked local materialization range."
        )
    }

    private func parameterBreaks(
        knots: [Double],
        lower: Double,
        upper: Double,
        operationCount: inout Int,
        tolerance: ModelingTolerance
    ) throws -> [Double] {
        let scanAndSlotCount = try checkedSum(
            knots.count,
            2,
            tolerance: tolerance
        )
        try consume(
            scanAndSlotCount,
            operationCount: &operationCount,
            tolerance: tolerance
        )
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
