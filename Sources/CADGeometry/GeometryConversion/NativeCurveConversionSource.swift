import CADCore

public struct NativeCurveConversionSource: GeometryCurveConversionSource {
    public let curve: Curve3D
    private let prepared: PreparedCurveDifferentialEncloser?
    private let boundedPreparationTolerance: ModelingTolerance?
    private let boundedPreparationAdmission: GeometryConversionAdmission?

    public init(_ curve: Curve3D, tolerance: ModelingTolerance) throws {
        self.curve = curve
        boundedPreparationTolerance = nil
        boundedPreparationAdmission = nil
        try curve.validate(tolerance: tolerance)
        prepared = try PreparedCurveDifferentialEncloser(curve: curve, tolerance: tolerance)
    }
    public init(_ curve: Curve3D, tolerance: ModelingTolerance,
        admission: GeometryConversionAdmission) throws {
        self.curve = curve
        boundedPreparationTolerance = tolerance
        boundedPreparationAdmission = admission
        try curve.validateOriginalSource(tolerance: tolerance,
            remainingSourceDepth: admission.remainingSourceDepth,
            maximumSubdivisionDepth: admission.maximumSubdivisionDepth,
            consumeWork: { _ in try admission.chargeWork() },
            consumeStorage: { try admission.chargeStorage(bytes: $0) },
            maximumAlgebraicDepth: admission.maximumAlgebraicDepth)
        prepared = try PreparedCurveDifferentialEncloser(curve: curve, tolerance: tolerance,
            remainingSourceDepth: admission.remainingSourceDepth,
            maximumSubdivisionDepth: admission.maximumSubdivisionDepth,
            consumeWork: { try admission.chargeWork() },
            consumeStorage: { try admission.chargeStorage(bytes: $0) }, maximumAlgebraicDepth: admission.maximumAlgebraicDepth)
    }

    public func validate(over parameters: ScalarInterval, tolerance: ModelingTolerance,
        admission: GeometryConversionAdmission) throws {
        try admission.chargeWork()
        guard let boundedPreparationAdmission,
            boundedPreparationAdmission.belongsToSameInvocation(as: admission),
            boundedPreparationTolerance == tolerance, prepared != nil,
            parameters.lower.isFinite, parameters.upper.isFinite,
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
        admission: GeometryConversionAdmission) throws -> CurveDifferentialEnclosure {
        try validate(over: parameters, tolerance: tolerance, admission: admission)
        guard let prepared else { throw GeometryConversionError.invalidInput("Original source preparation is unavailable.") }
        let receipt = try prepared.closedNativeJets(over: parameters, tolerance: tolerance,
            maximumSpanCount: admission.maximumSpanCount,
            maximumSubdivisionDepth: admission.maximumSubdivisionDepth,
            remainingSourceDepth: admission.remainingSourceDepth,
            consumeWork: { try admission.chargeWork() },
            consumeStorage: { try admission.chargeStorage(bytes: $0) })
        guard let first = receipt.spans.first else {
            throw GeometryConversionError.invalidInput("Original bounded source has no owning closed cover.")
        }
        var jet = first.jet
        for span in receipt.spans.dropFirst() { try admission.chargeWork(); jet = jet.union(span.jet) }
        return try DefaultCurveDifferentialEncloser().publicEnclosure(jet, tolerance: tolerance)
    }

    /// Original knot-owner cuts for consumers that require smooth chord cells.
    // FIXME(INCOMPLETE_IMPLEMENTATION): Drawing linearization consumes this
    // original owning cover before Taylor chord bounds. General mapped/native
    // non-binary joins and lifted/implicit critical covers require their retained
    // station-law producer before complete drawing-domain admission.
    public func owningParameterCover(over parameters: ScalarInterval, tolerance: ModelingTolerance,
        admission: GeometryConversionAdmission) throws -> [ScalarInterval] {
        try validate(over: parameters, tolerance: tolerance, admission: admission)
        func supports(_ source: Curve3D, remaining: Int) throws -> Bool {
            try admission.chargeWork()
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
        guard try supports(curve, remaining: admission.remainingSourceDepth), let prepared else {
            throw KernelError(phase: .geometry, code: .unsupportedCapability, tolerance: tolerance,
                message: "Original drawing source needs its retained mapped owning station cover.")
        }
        let receipt = try prepared.closedNativeJets(over: parameters, tolerance: tolerance,
            maximumSpanCount: admission.maximumSpanCount, maximumSubdivisionDepth: admission.maximumSubdivisionDepth,
            remainingSourceDepth: admission.remainingSourceDepth, consumeWork: { try admission.chargeWork() },
            consumeStorage: { try admission.chargeStorage(bytes: $0) })
        let count = receipt.spans.count
        let bytes = count.multipliedReportingOverflow(by: MemoryLayout<ScalarInterval>.stride)
        guard !bytes.overflow else { throw GeometryConversionError.resourceLimitExceeded("Original owning cover storage overflows.") }
        try admission.chargeStorage(bytes: bytes.partialValue)
        var result: [ScalarInterval] = []; result.reserveCapacity(count)
        for span in receipt.spans {
            try admission.chargeWork()
            guard span.parameters.lower < span.parameters.upper else { continue }
            result.append(span.parameters)
        }
        guard result.first?.lower == parameters.lower, result.last?.upper == parameters.upper else {
            throw GeometryConversionError.invalidInput("Original owning interval cover does not retain the requested endpoints.")
        }
        if result.count > 1 {
            for index in 1..<result.count {
                try admission.chargeWork()
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
        try tolerance.validate()
        guard parameters.width > 0, parameters.width.isFinite,
              try curve.parameterDomain.containsSpan(from: parameters.lower, to: parameters.upper, tolerance: tolerance) else {
            throw GeometryConversionError.invalidInput("Curve conversion requires a finite, positive, contained parameter interval.")
        }
    }
    public func pointAndDerivative(at parameter: Double, tolerance: ModelingTolerance) throws -> (point: Point3D, derivative: Vector3D) {
        let value = try curve.differentialGeometry(at: parameter, tolerance: tolerance)
        return (value.position, value.firstDerivative)
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
        // Periodic extraction must expand the requested cycle before restricting it.
        let jet: SurfaceIntervalVectorJet
        if let prepared {
            let original = try prepared.closedNativeJets(over: parameters, tolerance: tolerance,
                consumeWork: { try Task.checkCancellation() })
            guard let first = original.spans.first else {
                throw GeometryConversionError.invalidInput("Native conversion source has no original closed owning cover.")
            }
            // Separate original owning sides supply a derivative hull, not a
            // continuity certificate for a general lifted or implicit join.
            jet = original.spans.dropFirst().reduce(first.jet) { $0.union($1.jet) }
        } else {
            jet = try DefaultCurveDifferentialEncloser().thirdOrderIntervalJet(
                of: curve, over: Self.stablePeriodicInterval(parameters, domain: curve.parameterDomain, tolerance: tolerance), tolerance: tolerance)
        }
        func coordinates(_ key: KeyPath<SurfaceIntervalJet, OutwardScalarInterval>) throws -> CoordinateEnclosure3D {
            let x = jet.x[keyPath: key], y = jet.y[keyPath: key], z = jet.z[keyPath: key]
            return try CoordinateEnclosure3D(x: ScalarInterval(lower: x.lower, upper: x.upper),
                y: ScalarInterval(lower: y.lower, upper: y.upper), z: ScalarInterval(lower: z.lower, upper: z.upper))
        }
        return try CurveDifferentialEnclosure(position: coordinates(\.value),
            firstDerivative: coordinates(\.derivativeU), secondDerivative: coordinates(\.secondDerivativeUU))
    }
}
