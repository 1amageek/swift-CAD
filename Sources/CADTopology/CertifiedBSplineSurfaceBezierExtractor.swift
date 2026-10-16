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

    func patches(surface: BSplineSurface3D, tolerance: ModelingTolerance) throws -> [CertifiedHomogeneousBezierSurfacePatch]? {
        var execution = try OriginalQueryExecution.independentGeometry()
        return try patches(surface: surface, tolerance: tolerance, using: &execution)
    }

    func patches(
        surface: BSplineSurface3D,
        tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution
    ) throws -> [CertifiedHomogeneousBezierSurfacePatch]? {
        try execution.consumeWork(1)
        try execution.checkpoint()
        try tolerance.validate()
        try surface.validate(tolerance: tolerance, using: &execution)
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
        if try isSingleBezierPatch(
            degree: surface.uDegree,
            knots: surface.uKnots,
            controlCount: surface.uControlPointCount,
            lower: uDomainLower,
            upper: uDomainUpper, using: &execution
        ), try isSingleBezierPatch(
            degree: surface.vDegree,
            knots: surface.vKnots,
            controlCount: surface.vControlPointCount,
            lower: vDomainLower,
            upper: vDomainUpper, using: &execution
        ) {
            let controls = (try OriginalParameterQueryStorage.map(surface.controlPoints.indices, using: &execution) { vIndex, execution in
                (try OriginalParameterQueryStorage.map(surface.controlPoints[vIndex].indices, using: &execution) { uIndex, execution in
                    let point = surface.controlPoints[vIndex][uIndex]
                    let weight = Scalar.exact(surface.weights[vIndex][uIndex])
                    return Point(
                        x: Scalar.exact(point.x) * weight,
                        y: Scalar.exact(point.y) * weight,
                        z: Scalar.exact(point.z) * weight,
                        weight: weight
                    )
                })
            })
            guard try OriginalParameterQueryStorage.allSatisfy(controls, using: &execution, predicate: { row, execution in
                try OriginalParameterQueryStorage.allSatisfy(row, using: &execution) { point, execution in point.isFiniteAndPositiveWeight }
            }) else {
                throw KernelError(
                    phase: .topology,
                    code: .singularSystem,
                    tolerance: tolerance,
                    message: "Certified Bezier surface extraction requires finite positive homogeneous controls."
                )
            }
            return try OriginalParameterQueryStorage.repeated(Patch(
                controls: controls,
                uLower: uDomainLower,
                uUpper: uDomainUpper,
                vLower: vDomainLower,
                vUpper: vDomainUpper
            ), count: 1, using: &execution)
        }
        var operationCount = 0
        let uBreaks = try parameterBreaks(
            knots: surface.uKnots,
            lower: uDomainLower,
            upper: uDomainUpper,
            operationCount: &operationCount,
            tolerance: tolerance, using: &execution
        )
        let vBreaks = try parameterBreaks(
            knots: surface.vKnots,
            lower: vDomainLower,
            upper: vDomainUpper,
            operationCount: &operationCount,
            tolerance: tolerance, using: &execution
        )
        let constantWeight = try exactConstantWeight(surface.weights, using: &execution)
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
        try OriginalParameterQueryStorage.reserve(patchCount, in: &result, using: &execution)
        var vSpanCursor = surface.vDegree
        for vSpanIndex in 0..<(vBreaks.count - 1) {
            try execution.consumeWork(1)
            try execution.checkpoint()
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
                tolerance: tolerance, using: &execution
            )
            let vLocalKnots = try localKnots(
                degree: surface.vDegree,
                knots: surface.vKnots,
                span: vSpan,
                operationCount: &operationCount,
                tolerance: tolerance, using: &execution
            )
            let vBasis = try basisDerivativeTable(
                parameter: vLower,
                degree: surface.vDegree,
                knots: vLocalKnots,
                count: surface.vDegree + 1,
                operationCount: &operationCount,
                tolerance: tolerance, using: &execution
            )
            let vScales = try bernsteinScales(
                degree: surface.vDegree,
                span: vSpanWidth,
                operationCount: &operationCount,
                tolerance: tolerance, using: &execution
            )
            var uSpanCursor = surface.uDegree
            for uSpanIndex in 0..<(uBreaks.count - 1) {
                try execution.consumeWork(1)
                try execution.checkpoint()
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
                    tolerance: tolerance, using: &execution
                )
                let uLocalKnots = try localKnots(
                    degree: surface.uDegree,
                    knots: surface.uKnots,
                    span: uSpan,
                    operationCount: &operationCount,
                    tolerance: tolerance, using: &execution
                )
                let uBasis = try basisDerivativeTable(
                    parameter: uLower,
                    degree: surface.uDegree,
                    knots: uLocalKnots,
                    count: surface.uDegree + 1,
                    operationCount: &operationCount,
                    tolerance: tolerance, using: &execution
                )
                let uScales = try bernsteinScales(
                    degree: surface.uDegree,
                    span: uSpanWidth,
                    operationCount: &operationCount,
                    tolerance: tolerance, using: &execution
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
                var derivatives = try OriginalParameterQueryStorage.map(0..<vLocalCount, using: &execution) { _, execution in
                    try OriginalParameterQueryStorage.repeated(zeroPoint, count: uLocalCount, using: &execution)
                }
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
                    try execution.consumeWork(1)
                    for uOrder in 0...surface.uDegree {
                        try execution.consumeWork(1)
                        derivatives[vOrder][uOrder] = try homogeneousDerivative(
                            surface: surface,
                            uBasis: uBasis[uOrder],
                            vBasis: vBasis[vOrder],
                            uControlStart: uControlStart,
                            vControlStart: vControlStart,
                            operationCount: &operationCount,
                            tolerance: tolerance, using: &execution
                        )
                    }
                }
                var controls = try bernsteinControls(
                    derivatives: derivatives,
                    uScales: uScales,
                    vScales: vScales,
                    operationCount: &operationCount,
                    tolerance: tolerance, using: &execution
                )
                if let constantWeight {
                    controls = (try OriginalParameterQueryStorage.map(controls, using: &execution) { row, execution in
                        (try OriginalParameterQueryStorage.map(row, using: &execution) { control, execution in
                            Point(
                                x: control.x,
                                y: control.y,
                                z: control.z,
                                weight: .exact(constantWeight)
                            )
                        })
                    })
                }
                guard try OriginalParameterQueryStorage.allSatisfy(controls, using: &execution, predicate: { row, execution in
                    try OriginalParameterQueryStorage.allSatisfy(row, using: &execution) { point, execution in point.isFiniteAndPositiveWeight }
                }) else {
                    throw KernelError(
                        phase: .topology,
                        code: .singularSystem,
                        tolerance: tolerance,
                        message: "Certified B-spline surface extraction could not prove positive finite homogeneous weights."
                    )
                }
                try OriginalParameterQueryStorage.append(Patch(
                    controls: controls,
                    uLower: uLower,
                    uUpper: uUpper,
                    vLower: vLower,
                    vUpper: vUpper
                ), to: &result, using: &execution)
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
        tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution
    ) throws -> [[Scalar]] {
        try execution.consumeWork(1)
        return try OriginalParameterQueryStorage.map(0...degree, using: &execution) { derivativeOrder, execution in
            try basisDerivativeValues(
                parameter: parameter,
                degree: degree,
                derivativeOrder: derivativeOrder,
                knots: knots,
                count: count,
                operationCount: &operationCount,
                tolerance: tolerance, using: &execution
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
        tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution
    ) throws -> [Scalar] {
        try execution.consumeWork(1)
        if derivativeOrder == 0 {
            return try basisValues(
                parameter: parameter,
                degree: degree,
                knots: knots,
                count: count,
                operationCount: &operationCount,
                tolerance: tolerance, using: &execution
            )
        }
        guard derivativeOrder <= degree else {
            return try OriginalParameterQueryStorage.repeated(Scalar.exact(0.0), count: count, using: &execution)
        }
        let lowerDegree = try basisDerivativeValues(
            parameter: parameter,
            degree: degree - 1,
            derivativeOrder: derivativeOrder - 1,
            knots: knots,
            count: count + 1,
            operationCount: &operationCount,
            tolerance: tolerance, using: &execution
        )
        let factor = Scalar.exact(Double(degree))
        var result = try OriginalParameterQueryStorage.repeated(Scalar.exact(0.0), count: count, using: &execution)
        for index in 0..<count {
            try execution.consumeWork(1)
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
        tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution
    ) throws -> [Scalar] {
        try execution.consumeWork(1)
        guard degree > 0 else {
            return try OriginalParameterQueryStorage.map(0..<count, using: &execution) { index, execution in
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
            tolerance: tolerance, using: &execution
        )
        var result = try OriginalParameterQueryStorage.repeated(Scalar.exact(0.0), count: count, using: &execution)
        for index in 0..<count {
            try execution.consumeWork(1)
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
        tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution
    ) throws -> Int {
        try execution.consumeWork(1)
        var span = spanCursor
        while span + 1 < controlCount {
            try execution.consumeWork(1)
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
        tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution
    ) throws -> [Double] {
        try execution.consumeWork(1)
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
        return try OriginalParameterQueryStorage.map(knots[lowerIndex...upperIndex], using: &execution) { knot, execution in knot }
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
        tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution
    ) throws -> Point {
        try execution.consumeWork(1)
        var result = zeroPoint
        for vIndex in vBasis.indices {
            try execution.consumeWork(1)
            for uIndex in uBasis.indices {
                try execution.consumeWork(1)
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
        tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution
    ) throws -> [[Scalar]] {
        try execution.consumeWork(1)
        var result: [[Scalar]] = []
        try OriginalParameterQueryStorage.reserve(degree + 1, in: &result, using: &execution)
        for controlIndex in 0...degree {
            try execution.consumeWork(1)
            var scales = try OriginalParameterQueryStorage.repeated(Scalar.exact(0.0), count: controlIndex + 1, using: &execution)
            var scale = Scalar.exact(1.0)
            for derivativeOrder in 0...controlIndex {
                try execution.consumeWork(1)
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
            try OriginalParameterQueryStorage.append(scales, to: &result, using: &execution)
        }
        return result
    }

    private func bernsteinControls(
        derivatives: [[Point]],
        uScales: [[Scalar]],
        vScales: [[Scalar]],
        operationCount: inout Int,
        tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution
    ) throws -> [[Point]] {
        try execution.consumeWork(1)
        var result: [[Point]] = []
        try OriginalParameterQueryStorage.reserve(vScales.count, in: &result, using: &execution)
        for vControl in vScales.indices {
            try execution.consumeWork(1)
            var row: [Point] = []
            try OriginalParameterQueryStorage.reserve(uScales.count, in: &row, using: &execution)
            for uControl in uScales.indices {
                try execution.consumeWork(1)
                var control = zeroPoint
                for vOrder in vScales[vControl].indices {
                    try execution.consumeWork(1)
                    for uOrder in uScales[uControl].indices {
                        try execution.consumeWork(1)
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
                try OriginalParameterQueryStorage.append(control, to: &row, using: &execution)
            }
            try OriginalParameterQueryStorage.append(row, to: &result, using: &execution)
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
        tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution
    ) throws -> [Double] {
        try execution.consumeWork(1)
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
        var result: [Double] = []
        try OriginalParameterQueryStorage.append(lower, to: &result, using: &execution)
        for knot in knots {
            try execution.consumeWork(1)
            guard knot > lower && knot < upper && result.last != knot else { continue }
            try OriginalParameterQueryStorage.append(knot, to: &result, using: &execution)
        }
        try OriginalParameterQueryStorage.append(upper, to: &result, using: &execution)
        return result
    }

    private func isSingleBezierPatch(
        degree: Int,
        knots: [Double],
        controlCount: Int,
        lower: Double,
        upper: Double, using execution: inout OriginalQueryExecution
    ) throws -> Bool {
        try execution.consumeWork(1)
        guard controlCount == degree + 1,
              knots.count == 2 * (degree + 1) else {
            return false
        }
        return try OriginalParameterQueryStorage.allSatisfy(knots.prefix(degree + 1), using: &execution) { knot, execution in knot == lower }
            && OriginalParameterQueryStorage.allSatisfy(knots.suffix(degree + 1), using: &execution) { knot, execution in knot == upper }
    }

    private func exactConstantWeight(_ weights: [[Double]], using execution: inout OriginalQueryExecution) throws -> Double? {
        try execution.consumeWork(1)
        guard let first = weights.first?.first,
              (try OriginalParameterQueryStorage.allSatisfy(weights, using: &execution) { row, execution in
                  try !row.isEmpty && (try OriginalParameterQueryStorage.allSatisfy(row, using: &execution) { item, execution in item == first })
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
