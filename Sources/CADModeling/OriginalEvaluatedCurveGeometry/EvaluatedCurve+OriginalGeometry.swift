import CADCore
import CADGeometry

extension EvaluatedCurve {
    /// Validates the exact law or authored nil-exact polyline on the caller ledger.
    public func validateOriginalGeometry(tolerance: ModelingTolerance,
        maximumSubdivisionDepth: Int, remainingSourceDepth: Int,
        consumeWork: @escaping @Sendable (Int) throws -> Void,
        consumeStorage: (@Sendable (Int) throws -> Void)? = nil,
        maximumAlgebraicDepth: Int? = nil) throws -> OriginalEvaluatedCurveGeometry {
        try consumeWork(0)
        try CurrentTaskCancellationChecker().checkCancellation()
        guard (0...32).contains(maximumSubdivisionDepth), remainingSourceDepth >= 0 else {
            throw GeometryConversionError.resourceLimitExceeded("Original query preparation has invalid depth limits.")
        }
        guard let curve = exactCurve else {
            return try originalPolyline(tolerance: tolerance,
                maximumSubdivisionDepth: maximumSubdivisionDepth, remainingSourceDepth: remainingSourceDepth,
                consumeWork: consumeWork, consumeStorage: consumeStorage,
                maximumAlgebraicDepth: maximumAlgebraicDepth)
        }
        try curve.validate(tolerance: tolerance, remainingSourceDepth: remainingSourceDepth,
            maximumSubdivisionDepth: maximumSubdivisionDepth, consumeWork: consumeWork,
            consumeStorage: consumeStorage, maximumAlgebraicDepth: maximumAlgebraicDepth)
        let nativeDomain = try originalNativeDomain(of: curve, depth: remainingSourceDepth,
            tolerance: tolerance, consumeWork: consumeWork)
        let domain = exactParameterDomain ?? nativeDomain
        try domain.validate(tolerance: tolerance)
        let start: Double
        let end: Double
        switch domain {
        case .closed(let lower, let upper):
            guard try nativeDomain.containsSpan(from: lower, to: upper, tolerance: tolerance) else {
                throw KernelError(phase: .geometry, code: .invalidInput, tolerance: tolerance,
                    message: "Original evaluated trim lies outside its source native domain.")
            }
            if case .periodic(let period) = nativeDomain {
                let scale = max(abs(lower), abs(upper), period, 1)
                let epsilon = max(tolerance.relative * scale, Double.ulpOfOne * scale * 256)
                guard upper - lower <= period + epsilon else {
                    throw KernelError(phase: .geometry, code: .invalidInput, tolerance: tolerance,
                        message: "Original periodic evaluated trim exceeds one source turn.")
                }
            }
            start = lower; end = upper
        case .periodic(let period):
            guard case .periodic(let nativePeriod) = nativeDomain, nativePeriod == period else {
                throw KernelError(phase: .geometry, code: .invalidInput, tolerance: tolerance,
                    message: "Original periodic query domain must retain its native period.")
            }
            start = 0; end = period
        case .unbounded:
            guard case .unbounded = nativeDomain,
                let parameters = exactPointParameters, parameters.count >= 2,
                let first = parameters.first, let last = parameters.last,
                first.isFinite, last.isFinite, first != last else {
                throw KernelError(phase: .geometry, code: .invalidInput, tolerance: tolerance,
                    message: "Unbounded curve selection requires original finite directed endpoint parameters.")
            }
            for index in parameters.indices {
                try consumeWork(0); try CurrentTaskCancellationChecker().checkCancellation()
                let parameter = parameters[index]
                guard parameter.isFinite,
                    try nativeDomain.contains(parameter, tolerance: tolerance) else {
                    throw KernelError(phase: .geometry, code: .invalidInput, tolerance: tolerance,
                        message: "Unbounded curve selection parameters must retain finite original native values.")
                }
            }
            start = first; end = last
        }
        return OriginalEvaluatedCurveGeometry(sourceFeatureID: sourceFeatureID, source: source,
            kind: kind, curve: curve, parameterDomain: domain,
            startParameter: start, endParameter: end, isClosed: isClosed)
    }

    private struct PolylineAdmission: RationalAlgebraAdmitting {
        let work: @Sendable (Int) throws -> Void
        let storage: (@Sendable (Int) throws -> Void)?
        let algebraDepth: Int
        mutating func visitExactCell(depth: Int) throws {
            guard depth >= 0, depth <= algebraDepth else {
                throw GeometryConversionError.resourceLimitExceeded("Original polyline exceeds its selected algebra depth.")
            }
            try work(0)
        }
        mutating func visitCoefficientCell(depth: Int) throws { try visitExactCell(depth: depth) }
        mutating func consumeExactWork(_ count: Int) throws {
            guard count >= 0 else { throw GeometryConversionError.invalidInput("Original polyline work is negative.") }
            for _ in 0..<count { try work(0); try CurrentTaskCancellationChecker().checkCancellation() }
        }
        mutating func retainExactStorage(_ words: Int) throws {
            let bytes = words.multipliedReportingOverflow(by: MemoryLayout<UInt32>.stride)
            guard words >= 0, !bytes.overflow else {
                throw GeometryConversionError.resourceLimitExceeded("Original polyline storage overflows bytes.")
            }
            // Nil preserves the original caller's explicit absence of a byte ceiling.
            try storage?(bytes.partialValue)
        }
    }

    private func originalPolyline(tolerance: ModelingTolerance,
        maximumSubdivisionDepth: Int, remainingSourceDepth: Int,
        consumeWork: @escaping @Sendable (Int) throws -> Void,
        consumeStorage: (@Sendable (Int) throws -> Void)?,
        maximumAlgebraicDepth: Int?) throws -> OriginalEvaluatedCurveGeometry {
        try tolerance.validate()
        guard exactPointParameters == nil, points.count >= 2 else {
            throw GeometryConversionError.invalidInput("Authored polyline requires adjacent original points and no exact-curve parameters.")
        }
        let domain = exactParameterDomain ?? .closed(0, 1)
        try domain.validate(tolerance: tolerance)
        // FIXME(INCOMPLETE_IMPLEMENTATION): Legacy nil-exact queries clamp the
        // Euclidean clock independently of custom domain metadata. This original
        // receipt cannot yet retain that piecewise selector for noncanonical domains;
        // source-bound query publication must not reinterpret those authored labels.
        guard domain == .closed(0, 1) else {
            throw KernelError(phase: .geometry, code: .unsupportedCapability, tolerance: tolerance,
                message: "Original polyline custom query labels require a retained clamp selector.")
        }
        for index in points.indices {
            try consumeWork(0); try points[index].validate()
            if index > 0 {
                try consumeWork(0)
                guard (points[index] - points[index - 1]).length > tolerance.distance else {
                    throw SketchError.unsupportedEntity("Authored polyline has a degenerate adjacent span.")
                }
            }
        }
        if isClosed {
            try consumeWork(0)
            guard points[0].isApproximatelyEqual(to: points[points.count - 1], tolerance: tolerance.distance) else {
                throw SketchError.openProfile
            }
        }
        // FIXME(INCOMPLETE_IMPLEMENTATION): The legacy no-selected-algebra path
        // remains a numerical candidate query. Issuing a new exact Euclidean clock
        // requires the public caller's explicit coefficient capability; nil cannot
        // create a private intrinsic allowance or certify that legacy candidate.
        guard let algebra = maximumAlgebraicDepth else {
            throw KernelError(phase: .geometry, code: .unsupportedCapability, tolerance: tolerance,
                message: "Original authored polyline receipt requires an explicit caller algebra depth.")
        }
        var admission = PolylineAdmission(work: consumeWork, storage: consumeStorage, algebraDepth: algebra)
        let original = try OriginalPolylineCurve3D(points: points, isClosed: isClosed,
            tolerance: tolerance, remainingSourceDepth: remainingSourceDepth,
            maximumSubdivisionDepth: maximumSubdivisionDepth, maximumAlgebraicDepth: algebra, usage: &admission)
        try consumeStorage?(MemoryLayout<OriginalEvaluatedCurveGeometry>.stride)
        return OriginalEvaluatedCurveGeometry(sourceFeatureID: sourceFeatureID, source: source,
            kind: kind, curve: .originalPolyline(original), parameterDomain: domain,
            startParameter: 0, endParameter: 1, isClosed: isClosed)
    }

    private func originalNativeDomain(of curve: Curve3D, depth: Int,
        tolerance: ModelingTolerance, consumeWork: @Sendable (Int) throws -> Void) throws -> ParameterDomain {
        try consumeWork(0); try CurrentTaskCancellationChecker().checkCancellation()
        let source: Curve3D
        switch curve {
        case .rigidImage(let image): source = image.source
        case .affineImage(let image): source = image.source
        case .originalAffineWord(let image): source = image.source
        default: return curve.parameterDomain
        }
        guard depth > 0 else {
            throw GeometryConversionError.resourceLimitExceeded("Original native-domain traversal exhausted source depth.")
        }
        return try originalNativeDomain(of: source, depth: depth - 1,
            tolerance: tolerance, consumeWork: consumeWork)
    }
}
