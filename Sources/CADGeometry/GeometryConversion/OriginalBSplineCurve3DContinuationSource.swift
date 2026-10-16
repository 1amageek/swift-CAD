import CADCore

/// Original spatial rational endpoint-span law for certification and guided offsets.
public struct OriginalBSplineCurve3DContinuationSource: GeometryCurveConversionSource {
    public let curve: BSplineCurve3D
    private let spans: [RationalBezierCurveJetEncloser.NativeSpan]
    private let preparationTolerance: ModelingTolerance
    private let receipt: OriginalGeometryPreparationReceipt
    private let executionLimits: OriginalQueryExecutionLimits

    public init(curve: BSplineCurve3D, tolerance: ModelingTolerance) throws {
        var execution = OriginalQueryExecution(budget: try OriginalQueryBudget(),
            limits: try OriginalQueryExecutionLimits(maximumValueDepth: 32, maximumCoefficientDepth: 32))
        try self.init(curve: curve, tolerance: tolerance, using: &execution)
    }

    public init(curve: BSplineCurve3D, tolerance: ModelingTolerance,
        using execution: inout OriginalQueryExecution) throws {
        self.curve = curve
        preparationTolerance = tolerance
        executionLimits = execution.effectiveLimits
        let preparation = try execution.withPreparationScope { execution in

        try CurrentTaskCancellationChecker().checkCancellation()
        return try RationalBezierCurveJetEncloser().originalNativeSpans(of: curve,
            tolerance: tolerance, using: &execution)
        }
        spans = preparation.result
        guard !spans.isEmpty else {
            throw GeometryConversionError.invalidInput("Original continuation requires a positive native span.")
        }
        receipt = try OriginalGeometryPreparationReceipt(tolerance: tolerance,
            depth: preparation.depth, using: &execution)
    }

    private func reader() -> OriginalQueryExecution {
        OriginalQueryExecution(budget: receipt.budget, limits: executionLimits)
    }


    public func validate(over parameters: ScalarInterval, tolerance: ModelingTolerance) throws {
        var execution = reader()
        try validate(over: parameters, tolerance: tolerance, using: &execution)
    }

    public func validate(over parameters: ScalarInterval, tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution) throws {
        try CurrentTaskCancellationChecker().checkCancellation()
        try receipt.admit(tolerance: tolerance, using: &execution)
        guard tolerance == preparationTolerance, parameters.width.isFinite, parameters.width > 0 else {
            throw GeometryConversionError.invalidInput("Original 3D continuation requires its exact tolerance and a finite positive requested interval.")
        }
    }

    public func pointAndDerivative(at parameter: Double,
        tolerance: ModelingTolerance) throws -> (point: Point3D, derivative: Vector3D) {
        var execution = reader()
        return try pointAndDerivative(at: parameter, tolerance: tolerance, using: &execution)
    }

    public func pointAndDerivative(at parameter: Double,
        tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution) throws -> (point: Point3D, derivative: Vector3D) {
        let jet = try originalJet(over: ScalarInterval(lower: parameter, upper: parameter), tolerance: tolerance, using: &execution)
        // These finite midpoints construct a numerical candidate only. Publication
        // still uses originalJet's complete outward original-law bounds.
        let point = Point3D(x: jet.x.value.midpoint, y: jet.y.value.midpoint, z: jet.z.value.midpoint)
        let derivative = Vector3D(x: jet.x.derivativeU.midpoint, y: jet.y.derivativeU.midpoint, z: jet.z.derivativeU.midpoint)
        guard point.isFinite, derivative.isFinite else {
            throw GeometryConversionError.resourceLimitExceeded("Original 3D continuation point arithmetic is nonfinite.")
        }
        return (point, derivative)
    }

    public func enclosure(over parameters: ScalarInterval,
        tolerance: ModelingTolerance) throws -> CurveDifferentialEnclosure {
        var execution = reader()
        return try enclosure(over: parameters, tolerance: tolerance, using: &execution)
    }

    public func enclosure(over parameters: ScalarInterval,
        tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution) throws -> CurveDifferentialEnclosure {
        try validate(over: parameters, tolerance: tolerance, using: &execution)
        let jet = try originalJet(over: parameters, tolerance: tolerance, using: &execution)
        func coordinate(_ key: (SurfaceIntervalJet) -> OutwardScalarInterval) throws -> CoordinateEnclosure3D {
            let a = key(jet.x), b = key(jet.y), c = key(jet.z)
            return try CoordinateEnclosure3D(x: ScalarInterval(lower: a.lower, upper: a.upper),
                y: ScalarInterval(lower: b.lower, upper: b.upper), z: ScalarInterval(lower: c.lower, upper: c.upper))
        }
        return try CurveDifferentialEnclosure(position: coordinate({ $0.value }),
            firstDerivative: coordinate({ $0.derivativeU }), secondDerivative: coordinate({ $0.secondDerivativeUU }))
    }

    package func derivatives(over parameters: ScalarInterval, tolerance: ModelingTolerance,
        using execution: inout OriginalQueryExecution) throws -> IntervalVectorDerivativeJet {
        let jet = try originalJet(over: parameters, tolerance: tolerance, using: &execution)
        func component(_ value: SurfaceIntervalJet) -> IntervalDerivativeJet {
            .init(derivatives: [value.value, value.derivativeU,
                value.secondDerivativeUU, value.thirdDerivativeUUU])
        }
        return .init(x: component(jet.x), y: component(jet.y), z: component(jet.z))
    }

    func originalJet(over parameters: ScalarInterval,
        tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution) throws -> SurfaceIntervalVectorJet {
        try CurrentTaskCancellationChecker().checkCancellation()
        try receipt.admit(tolerance: tolerance, using: &execution)
        guard tolerance == preparationTolerance, parameters.lower.isFinite, parameters.upper.isFinite else {
            throw GeometryConversionError.invalidInput("An original endpoint continuation must retain its exact source tolerance and finite parameters.")
        }
        var result: SurfaceIntervalVectorJet?
        for (index, span) in spans.enumerated() {
            try CurrentTaskCancellationChecker().checkCancellation(); try execution.consumeWork(1)
            let lower = index == 0 ? parameters.lower : max(parameters.lower, span.lower)
            let upper = index == spans.count - 1 ? parameters.upper : min(parameters.upper, span.upper)
            guard lower <= upper else { continue }
            let jet = try RationalBezierCurveJetEncloser().continuationEnclosure(of: span,
                over: ScalarInterval(lower: lower, upper: upper), tolerance: tolerance, using: &execution)
            result = result.map { $0.union(jet) } ?? jet
        }
        guard let result else {
            throw GeometryConversionError.invalidInput("Original endpoint continuation lost its complete native-span cover.")
        }
        try CurrentTaskCancellationChecker().checkCancellation()
        return result
    }
}
