import CADCore

public struct NativeCurveConversionSource: GeometryCurveConversionSource {
    public let curve: Curve3D
    private let prepared: PreparedCurveDifferentialEncloser
    private let receipt: OriginalGeometryPreparationReceipt
    private let receiptLimits: OriginalQueryExecutionLimits

    public init(_ curve: Curve3D, tolerance: ModelingTolerance) throws {
        var execution = OriginalQueryExecution(budget: try OriginalQueryBudget(),
            limits: try OriginalQueryExecutionLimits(maximumValueDepth: 32, maximumCoefficientDepth: 32))
        try self.init(curve, tolerance: tolerance, using: &execution)
    }

    public init(_ curve: Curve3D, tolerance: ModelingTolerance,
        using execution: inout OriginalQueryExecution) throws {
        self.curve = curve
        receiptLimits = execution.effectiveLimits
        let preparation = try execution.withPreparationScope { execution in
            try PreparedCurveDifferentialEncloser(curve: curve, tolerance: tolerance, using: &execution)
        }
        prepared = preparation.result
        receipt = try OriginalGeometryPreparationReceipt(tolerance: tolerance,
            depth: preparation.depth, using: &execution)
    }

    public func validate(over parameters: ScalarInterval, tolerance: ModelingTolerance,
        using execution: inout OriginalQueryExecution) throws {
        try execution.consumeWork(1)
        try receipt.admit(tolerance: tolerance, using: &execution)
        guard parameters.lower.isFinite, parameters.upper.isFinite,
            parameters.lower <= parameters.upper else {
            throw GeometryConversionError.invalidInput("Bounded native source requires its paid preparation and finite closed chart.")
        }
        if case .closed(let lower, let upper) = curve.parameterDomain {
            guard parameters.lower >= lower, parameters.upper <= upper else {
                throw GeometryConversionError.invalidInput("Bounded native source query exceeds its original closed chart.")
            }
        }
    }

    public func enclosure(over parameters: ScalarInterval, tolerance: ModelingTolerance,
        using execution: inout OriginalQueryExecution) throws -> CurveDifferentialEnclosure {
        try validate(over: parameters, tolerance: tolerance, using: &execution)
        let receipt = try prepared.closedNativeJets(over: parameters, tolerance: tolerance,
            maximumSpanCount: execution.effectiveLimits.maximumSpans,
            maximumSubdivisionDepth: execution.effectiveLimits.maximumSubdivisionDepth,
            remainingSourceDepth: execution.effectiveLimits.remainingSourceDepth,
            using: &execution)
        guard let first = receipt.spans.first else {
            throw GeometryConversionError.invalidInput("Original bounded source has no owning closed cover.")
        }
        var jet = first.jet
        for span in receipt.spans.dropFirst() { try execution.consumeWork(1); jet = jet.union(span.jet) }
        return try DefaultCurveDifferentialEncloser().publicEnclosure(jet, tolerance: tolerance)
    }

    /// Original knot-owner cuts for consumers that require smooth chord cells.
    // FIXME(INCOMPLETE_IMPLEMENTATION): Drawing linearization consumes this
    // original owning cover before Taylor chord bounds. General mapped/native
    // non-binary joins and lifted/implicit critical covers require their retained
    // station-law producer before complete drawing-domain admission.
    public func owningParameterCover(over parameters: ScalarInterval, tolerance: ModelingTolerance,
        using execution: inout OriginalQueryExecution) throws -> [ScalarInterval] {
        try validate(over: parameters, tolerance: tolerance, using: &execution)
        func supports(_ source: Curve3D, remaining: Int) throws -> Bool {
            try execution.consumeWork(1)
            switch source {
            case .bSpline, .line, .circle, .analytic(.line), .analytic(.circle), .analytic(.ellipse),
                 .analytic(.arc), .analytic(.hyperbola), .analytic(.parabola), .originalAngularTransport: return true
            case .originalEndpointConnector:
                // The corrected polynomial preserves the construction's exact
                // normalized owning cuts; its geometry is queried in full below.
                return true
            case .originalPlaneDerivative(let original):
                guard remaining > 0, original.source.start == .authored(0),
                    original.source.end == .authored(1) else { return false }
                return try supports(original.source.source, remaining: remaining - 1)
            case .rigidImage(let image):
                guard remaining > 0 else { return false }; return try supports(image.source, remaining: remaining - 1)
            case .affineImage(let image):
                guard remaining > 0 else { return false }; return try supports(image.source, remaining: remaining - 1)
            case .originalAffineWord(let image):
                guard remaining > 0 else { return false }; return try supports(image.source, remaining: remaining - 1)
            default: return false
            }
        }
        guard try supports(curve, remaining: execution.effectiveLimits.remainingSourceDepth) else {
            throw KernelError(phase: .geometry, code: .unsupportedCapability, tolerance: tolerance,
                message: "Original drawing source needs its retained mapped owning station cover.")
        }
        let receipt = try prepared.closedNativeJets(over: parameters, tolerance: tolerance,
            maximumSpanCount: execution.effectiveLimits.maximumSpans, maximumSubdivisionDepth: execution.effectiveLimits.maximumSubdivisionDepth,
            remainingSourceDepth: execution.effectiveLimits.remainingSourceDepth, using: &execution)
        let count = receipt.spans.count
        let bytes = count.multipliedReportingOverflow(by: MemoryLayout<ScalarInterval>.stride)
        guard !bytes.overflow else { throw GeometryConversionError.resourceLimitExceeded("Original owning cover storage overflows.") }
        try execution.retainStorage(bytes: bytes.partialValue)
        var result: [ScalarInterval] = []; result.reserveCapacity(count)
        for span in receipt.spans {
            try execution.consumeWork(1)
            guard span.parameters.lower < span.parameters.upper else { continue }
            result.append(span.parameters)
        }
        guard result.first?.lower == parameters.lower, result.last?.upper == parameters.upper else {
            throw GeometryConversionError.invalidInput("Original owning interval cover does not retain the requested endpoints.")
        }
        if result.count > 1 {
            for index in 1..<result.count {
                try execution.consumeWork(1)
                guard result[index - 1].upper == result[index].lower else {
                    throw KernelError(phase: .geometry, code: .unsupportedCapability, tolerance: tolerance,
                        message: "Original native owner cuts require an exact common station carrier.")
                }
            }
        }
        return result
    }

    private static func containsPeriodicCurve(_ curve: Curve3D) -> Bool {
        switch curve {
        case .bSpline(let value): value.isPeriodic
        case .rigidImage(let image): containsPeriodicCurve(image.source)
        case .affineImage(let image): containsPeriodicCurve(image.source)
        case .originalAffineWord(let image): containsPeriodicCurve(image.source)
        case .parameterImage(let image): containsPeriodicCurve(image.source)
        default: false
        }
    }
    public func validate(over parameters: ScalarInterval, tolerance: ModelingTolerance) throws {
        var execution = independentReader()
        try validate(over: parameters, tolerance: tolerance, using: &execution)
    }

    public func pointAndDerivative(at parameter: Double, tolerance: ModelingTolerance) throws -> (point: Point3D, derivative: Vector3D) {
        var execution = independentReader()
        return try pointAndDerivative(at: parameter, tolerance: tolerance, using: &execution)
    }

    public func pointAndDerivative(at parameter: Double, tolerance: ModelingTolerance,
        using execution: inout OriginalQueryExecution) throws -> (point: Point3D, derivative: Vector3D) {
        let value = try enclosure(over: .init(lower: parameter, upper: parameter), tolerance: tolerance, using: &execution)
        return (.init(x: value.position.x.midpoint, y: value.position.y.midpoint, z: value.position.z.midpoint),
            .init(x: value.firstDerivative.x.midpoint, y: value.firstDerivative.y.midpoint, z: value.firstDerivative.z.midpoint))
    }

    private func independentReader() -> OriginalQueryExecution {
        // A later ordinary reader shares cumulative admission, never query-local scopes.
        OriginalQueryExecution(budget: receipt.budget, limits: receiptLimits)
    }

    static func stablePeriodicInterval(_ parameters: ScalarInterval, domain: ParameterDomain, tolerance: ModelingTolerance) throws -> ScalarInterval {
        let scale = max(1, abs(parameters.lower), abs(parameters.upper), parameters.width)
        let resolution = max(domain.parameterResolution(tolerance: tolerance),
            tolerance.relative * scale, Double.ulpOfOne * scale * 256)
        guard resolution.isFinite else { throw GeometryConversionError.resourceLimitExceeded("Periodic enclosure resolution is not finite.") }
        guard parameters.width <= resolution * 4 else { return parameters }
        let lower = parameters.lower - resolution * 4, upper = parameters.upper + resolution * 4
        guard lower.isFinite, upper.isFinite, lower <= parameters.lower, upper >= parameters.upper,
              upper - lower > resolution else {
            throw GeometryConversionError.resourceLimitExceeded("Periodic enclosure could not construct a stable containing interval.")
        }
        return try ScalarInterval(lower: lower, upper: upper)
    }
    public func enclosure(over parameters: ScalarInterval, tolerance: ModelingTolerance) throws -> CurveDifferentialEnclosure {
        var execution = independentReader()
        return try enclosure(over: parameters, tolerance: tolerance, using: &execution)
    }
}
