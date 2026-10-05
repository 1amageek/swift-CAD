import CADCore

/// Original spatial rational endpoint-span law for certification and guided offsets.
public struct OriginalBSplineCurve3DContinuationSource: GeometryCurveConversionSource {
    public let curve: BSplineCurve3D
    private let spans: [RationalBezierCurveJetEncloser.NativeSpan]
    private let preparationTolerance: ModelingTolerance

    public init(curve: BSplineCurve3D, tolerance: ModelingTolerance,
        consumeWork: () throws -> Void = {}) throws {
        try Task.checkCancellation()
        try curve.validate(tolerance: tolerance)
        self.curve = curve
        preparationTolerance = tolerance
        spans = try RationalBezierCurveJetEncloser().originalNativeSpans(of: curve,
            tolerance: tolerance, consumeWork: consumeWork)
        guard !spans.isEmpty else {
            throw GeometryConversionError.invalidInput("Original 3D continuation requires a positive native span.")
        }
    }

    public func validate(over parameters: ScalarInterval, tolerance: ModelingTolerance) throws {
        try Task.checkCancellation()
        guard tolerance == preparationTolerance, parameters.width.isFinite, parameters.width > 0 else {
            throw GeometryConversionError.invalidInput("Original 3D continuation requires its exact tolerance and a finite positive requested interval.")
        }
    }

    public func pointAndDerivative(at parameter: Double,
        tolerance: ModelingTolerance) throws -> (point: Point3D, derivative: Vector3D) {
        let jet = try originalJet(over: ScalarInterval(lower: parameter, upper: parameter), tolerance: tolerance)
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
        try validate(over: parameters, tolerance: tolerance)
        let jet = try originalJet(over: parameters, tolerance: tolerance)
        func coordinate(_ key: KeyPath<SurfaceIntervalJet, OutwardScalarInterval>) throws -> CoordinateEnclosure3D {
            let a = jet.x[keyPath: key], b = jet.y[keyPath: key], c = jet.z[keyPath: key]
            return try CoordinateEnclosure3D(x: ScalarInterval(lower: a.lower, upper: a.upper),
                y: ScalarInterval(lower: b.lower, upper: b.upper), z: ScalarInterval(lower: c.lower, upper: c.upper))
        }
        return try CurveDifferentialEnclosure(position: coordinate(\.value),
            firstDerivative: coordinate(\.derivativeU), secondDerivative: coordinate(\.secondDerivativeUU))
    }

    package func derivatives(over parameters: ScalarInterval, tolerance: ModelingTolerance,
        consumeWork: () throws -> Void) throws -> IntervalVectorDerivativeJet {
        let jet = try originalJet(over: parameters, tolerance: tolerance, consumeWork: consumeWork)
        func component(_ value: SurfaceIntervalJet) -> IntervalDerivativeJet {
            .init(derivatives: [value.value, value.derivativeU,
                value.secondDerivativeUU, value.thirdDerivativeUUU])
        }
        return .init(x: component(jet.x), y: component(jet.y), z: component(jet.z))
    }

    func originalJet(over parameters: ScalarInterval,
        tolerance: ModelingTolerance, consumeWork: () throws -> Void = {}) throws -> SurfaceIntervalVectorJet {
        try Task.checkCancellation()
        guard tolerance == preparationTolerance, parameters.lower.isFinite, parameters.upper.isFinite else {
            throw GeometryConversionError.invalidInput("An original endpoint continuation must retain its exact source tolerance and finite parameters.")
        }
        var result: SurfaceIntervalVectorJet?
        for (index, span) in spans.enumerated() {
            try Task.checkCancellation(); try consumeWork()
            let lower = index == 0 ? parameters.lower : max(parameters.lower, span.lower)
            let upper = index == spans.count - 1 ? parameters.upper : min(parameters.upper, span.upper)
            guard lower <= upper else { continue }
            let jet = try RationalBezierCurveJetEncloser().continuationEnclosure(of: span,
                over: ScalarInterval(lower: lower, upper: upper), tolerance: tolerance, consumeWork: consumeWork)
            result = result.map { $0.union(jet) } ?? jet
        }
        guard let result else {
            throw GeometryConversionError.invalidInput("Original endpoint continuation lost its complete native-span cover.")
        }
        try Task.checkCancellation()
        return result
    }
}
