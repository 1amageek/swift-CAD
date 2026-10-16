import CADCore

/// Original rational endpoint-span law embedded in XY for common certification.
public struct OriginalBSplineCurve2DContinuationSource: GeometryCurveConversionSource {
    public let curve: BSplineCurve2D
    private let spans: [RationalBezierCurveJetEncloser.NativeSpan]
    private let preparationTolerance: ModelingTolerance
    private let receipt: OriginalGeometryPreparationReceipt
    private let executionLimits: OriginalQueryExecutionLimits

    public init(curve: BSplineCurve2D, tolerance: ModelingTolerance) throws {
        var execution = OriginalQueryExecution(budget: try OriginalQueryBudget(),
            limits: try OriginalQueryExecutionLimits(maximumValueDepth: 32, maximumCoefficientDepth: 32))
        try self.init(curve: curve, tolerance: tolerance, using: &execution)
    }

    public init(curve: BSplineCurve2D, tolerance: ModelingTolerance,
        using execution: inout OriginalQueryExecution) throws {
        self.curve = curve
        preparationTolerance = tolerance
        executionLimits = execution.effectiveLimits
        let preparation = try execution.withPreparationScope { execution in

        try CurrentTaskCancellationChecker().checkCancellation()
        try curve.validate(tolerance: tolerance, using: &execution)
        try OriginalCoefficientAllocation.reserve(count: curve.controlPoints.count, of: Point3D.self, using: &execution)
        let lifted = BSplineCurve3D(degree: curve.degree, knots: curve.knots,
            controlPoints: try curve.controlPoints.map { point in
                try CurrentTaskCancellationChecker().checkCancellation(); try execution.consumeWork(1)
                return Point3D(x: point.x, y: point.y, z: 0)
            },
            weights: curve.weights)
        return try RationalBezierCurveJetEncloser().originalNativeSpans(of: lifted,
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
            throw GeometryConversionError.invalidInput("Original 2D continuation requires its exact tolerance and a finite positive requested interval.")
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
        let point = Point3D(x: jet.x.value.midpoint, y: jet.y.value.midpoint, z: 0)
        let derivative = Vector3D(x: jet.x.derivativeU.midpoint, y: jet.y.derivativeU.midpoint, z: 0)
        guard point.isFinite, derivative.isFinite else {
            throw GeometryConversionError.resourceLimitExceeded("Original 2D continuation point arithmetic is nonfinite.")
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
            let a = key(jet.x), b = key(jet.y)
            return try CoordinateEnclosure3D(x: ScalarInterval(lower: a.lower, upper: a.upper),
                y: ScalarInterval(lower: b.lower, upper: b.upper), z: ScalarInterval(lower: 0, upper: 0))
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

    /// Transforms original Bernstein coefficients directly, then certifies their
    /// Cartesian publication against this retained endpoint law.
    public func continuedCurve(over parameters: ScalarInterval,
        requirements: GeometryConversionRequirements, tolerance: ModelingTolerance)
        throws -> (curve: BSplineCurve2D, guarantee: GeometryConversionGuarantee) {
        var execution = reader()
        return try continuedCurve(over: parameters, requirements: requirements, tolerance: tolerance, using: &execution)
    }

    public func continuedCurve(over parameters: ScalarInterval,
        requirements: GeometryConversionRequirements, tolerance: ModelingTolerance,
        using execution: inout OriginalQueryExecution)
        throws -> (curve: BSplineCurve2D, guarantee: GeometryConversionGuarantee) {
        return try execution.withConversionScope(maximumWorkUnits: requirements.maximumWorkUnits,
            maximumScalarCount: requirements.maximumScalarCount,
            maximumCertificationBoxes: requirements.maximumCertificationBoxes) { execution in
        try validate(over: parameters, tolerance: tolerance, using: &execution)
        try requirements.validate()
        guard curve.degree <= requirements.maximumDegree else {
            throw GeometryConversionError.resourceLimitExceeded("The original continuation degree exceeds its publication allowance.")
        }
        func charge(_ count: Int, using execution: inout OriginalQueryExecution) throws {
            try execution.consumeWork(count)
        }
        let controlCapacity = requirements.maximumControlPointCount
        let knotCapacity = controlCapacity.addingReportingOverflow(curve.degree + 1)
        guard !knotCapacity.overflow else { throw GeometryConversionError.resourceLimitExceeded("Original continuation knot capacity overflowed.") }
        try OriginalCoefficientAllocation.reserve(count: controlCapacity, of: Point3D.self, using: &execution)
        try OriginalCoefficientAllocation.reserve(count: controlCapacity, of: Double.self, using: &execution)
        try OriginalCoefficientAllocation.reserve(count: knotCapacity.partialValue, of: Double.self, using: &execution)
        var controls: [Point3D] = [], weights: [Double] = [], knots: [Double] = []
        controls.reserveCapacity(controlCapacity); weights.reserveCapacity(controlCapacity)
        knots.reserveCapacity(knotCapacity.partialValue)
        for (index, span) in spans.enumerated() {
            try charge(1, using: &execution)
            let lower = index == 0 ? parameters.lower : max(parameters.lower, span.lower)
            let upper = index == spans.count - 1 ? parameters.upper : min(parameters.upper, span.upper)
            guard lower < upper else { continue }
            let width = span.upper - span.lower
            let a = (lower - span.lower) / width, b = (upper - span.lower) / width
            guard a.isFinite, b.isFinite, width.isFinite, width > 0 else {
                throw GeometryConversionError.resourceLimitExceeded("Original Bernstein continuation parameters are nonfinite.")
            }
            let count = curve.degree + 1
            guard controls.count <= requirements.maximumControlPointCount - count else {
                throw GeometryConversionError.resourceLimitExceeded("Original continuation exceeds its native control allowance.")
            }
            // Original blossom coefficients contain only the requested endpoint
            // arguments. They construct the candidate, never its proof authority.
            for coefficient in 0..<count {
                try OriginalCoefficientAllocation.reserve(count: 4, of: Double.self, using: &execution)
                var homogeneous: [Double] = []; homogeneous.reserveCapacity(4)
                for coordinate in 0..<4 {
                    try charge(count, using: &execution)
                    try OriginalCoefficientAllocation.reserve(count: span.coefficients[coordinate].count, of: Double.self, using: &execution)
                    var level = span.coefficients[coordinate].map({ $0.midpoint })
                    for depth in 0..<curve.degree {
                        let parameter = depth < curve.degree - coefficient ? a : b
                        try charge((level.count - 1) * 4, using: &execution)
                        for slot in 0..<(level.count - 1) {
                            level[slot] = (1 - parameter) * level[slot] + parameter * level[slot + 1]
                        }
                        level.removeLast()
                    }
                    homogeneous.append(level[0])
                }
                let weight = homogeneous[3]
                guard homogeneous.allSatisfy({ $0.isFinite }), weight > 0 else {
                    throw GeometryConversionError.toleranceRejected
                }
                let point = Point3D(x: homogeneous[0] / weight, y: homogeneous[1] / weight, z: 0)
                guard point.isFinite else {
                    throw GeometryConversionError.resourceLimitExceeded("Original continuation Cartesian publication is nonfinite.")
                }
                controls.append(point); weights.append(weight)
            }
            if knots.isEmpty { knots.append(contentsOf: repeatElement(lower, count: count)) }
            knots.append(contentsOf: repeatElement(upper, count: count))
        }
        guard !controls.isEmpty else {
            throw GeometryConversionError.invalidInput("The original continuation request has no complete positive span cover.")
        }
        let scalarUsage = controls.count.multipliedReportingOverflow(by: 8)
        guard !scalarUsage.overflow, scalarUsage.partialValue < requirements.maximumScalarCount else {
            throw GeometryConversionError.resourceLimitExceeded("Original continuation publication exhausted its shared storage/work allowance.")
        }
        try execution.charge(scalars: scalarUsage.partialValue)
        let candidate = BSplineCurve3D(degree: curve.degree, knots: knots, controlPoints: controls, weights: weights)
        let guarantee = try CertifiedGeometryConverter().certifyCurve(source: self, candidate: candidate,
            over: parameters, requirements: requirements, tolerance: tolerance, using: &execution)
        try OriginalCoefficientAllocation.reserve(count: controls.count, of: Point2D.self, using: &execution)
        let output = BSplineCurve2D(degree: curve.degree, knots: knots,
            controlPoints: controls.map { Point2D(x: $0.x, y: $0.y) }, weights: weights)
        try execution.checkpoint()
        return (output, guarantee)
        }
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
