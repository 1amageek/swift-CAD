import CADCore
import CADGeometry

/// Retains the original native owning charts for a drafted open sheet.
package struct OriginalDraftedWallPartition {
    package init() {}
    package func walls(curve: Curve3D, parameters: ScalarInterval,
        normal: Vector3D, axis: Vector3D, pull: Vector3D, lowerHeight: Double,
        upperHeight: Double, angle: Double, tolerance: ModelingTolerance,
        using execution: inout OriginalQueryExecution,
        reversedTraversal: Bool = false) throws -> [OriginalDraftedRuledSurface3D] {
        var generators = try generators(curve: curve, parameters: parameters,
            tolerance: tolerance, remainingSourceDepth: execution.effectiveLimits.remainingSourceDepth, using: &execution)
        if reversedTraversal {
            for index in 0..<((generators.count + 1) / 2) {
                try execution.consumeWork(1)
                let opposite = generators.count - 1 - index
                let first = generators[index], last = generators[opposite]
                generators[index] = last.reversed()
                if index != opposite { generators[opposite] = first.reversed() }
            }
        }
        let bytes = generators.count.multipliedReportingOverflow(by: MemoryLayout<OriginalDraftedRuledSurface3D>.stride)
        guard !bytes.overflow else { throw GeometryConversionError.resourceLimitExceeded("Original draft wall payload overflows.") }
        try execution.retainStorage(bytes: bytes.partialValue)
        var walls: [OriginalDraftedRuledSurface3D] = []; walls.reserveCapacity(generators.count)
        for generator in generators {
            try execution.consumeWork(1)
            let start = try OriginalDraftedCurve3D(generator: generator, normal: normal,
                axis: axis, pull: pull, height: lowerHeight, angle: angle,
                remainingSourceDepth: execution.effectiveLimits.remainingSourceDepth, tolerance: tolerance, usage: &execution)
            walls.append(try OriginalDraftedRuledSurface3D(start: start, endHeight: upperHeight,
                remainingSourceDepth: execution.effectiveLimits.remainingSourceDepth, tolerance: tolerance, usage: &execution))
        }
        return walls
    }

    private func generators(curve: Curve3D, parameters: ScalarInterval,
        tolerance: ModelingTolerance, remainingSourceDepth: Int,
        using execution: inout OriginalQueryExecution) throws -> [OriginalCurveRootSpan3D] {
        try execution.consumeWork(1)
        guard remainingSourceDepth >= 0 else {
            throw GeometryConversionError.resourceLimitExceeded("Original draft chart traversal exhausted source nesting.")
        }
        if case let .parameterImage(image) = curve,
            image.offset == 0, image.parameterGain == .binary(-1) {
            var result = try generators(curve: image.source,
                parameters: .init(lower: -parameters.upper, upper: -parameters.lower),
                tolerance: tolerance, remainingSourceDepth: remainingSourceDepth - 1, using: &execution)
            for i in 0..<((result.count + 1)/2) {
                try execution.consumeWork(1)
                let j = result.count-1-i, first = result[i], last = result[j]
                result[i] = last.reversed()
                if i != j { result[j] = first.reversed() }
            }
            return result
        }
        func prepared(_ lower: Double, _ upper: Double, _ span: Int?) throws -> OriginalCurveRootSpan3D {
            try OriginalCurveRootSpan3D(source: curve, start: .authored(lower), end: .authored(upper),
                nativeSpanIndex: span,
                maximumParameterWidth: curve.parameterDomain.parameterResolution(tolerance: tolerance),
                maximumSubdivisionDepth: min(32, execution.effectiveLimits.maximumSubdivisionDepth), tolerance: tolerance,
                usage: &execution,
                maximumSpanCount: min(4096, execution.effectiveLimits.maximumSpans),
                remainingSourceDepth: remainingSourceDepth,
                maximumAlgebraicDepth: execution.effectiveLimits.maximumValueDepth)
        }
        guard case let .bSpline(spline) = curve else {
            try execution.retainStorage(bytes: MemoryLayout<OriginalCurveRootSpan3D>.stride)
            return [try prepared(parameters.lower, parameters.upper, nil)]
        }
        guard parameters.lower >= spline.knots[spline.degree],
            parameters.upper <= spline.knots[spline.controlPoints.count] else {
            // FIXME(INCOMPLETE_IMPLEMENTATION): Original translated periodic
            // knot charts need retained cycle/native span authority. This public
            // draft route cannot omit the portion outside the native base cover.
            throw KernelError(phase: .geometry, code: .unsupportedCapability, tolerance: tolerance,
                message: "Original drafted periodic wall partition requires retained translated owning charts.")
        }
        var count = 0
        for i in spline.degree..<spline.controlPoints.count {
            try execution.consumeWork(1)
            if max(parameters.lower,spline.knots[i]) < min(parameters.upper,spline.knots[i+1]) { count += 1 }
        }
        guard count > 0, count <= min(4096, execution.effectiveLimits.maximumSpans) else {
            throw GeometryConversionError.resourceLimitExceeded("Original draft native owning charts exceed their admitted count.")
        }
        let bytes = count.multipliedReportingOverflow(by: MemoryLayout<OriginalCurveRootSpan3D>.stride)
        guard !bytes.overflow else { throw GeometryConversionError.resourceLimitExceeded("Original draft generator payload overflows.") }
        try execution.retainStorage(bytes: bytes.partialValue)
        var result: [OriginalCurveRootSpan3D] = []; result.reserveCapacity(count)
        for i in spline.degree..<spline.controlPoints.count {
            try execution.consumeWork(1)
            let lower = max(parameters.lower,spline.knots[i]), upper = min(parameters.upper,spline.knots[i+1])
            if lower < upper { result.append(try prepared(lower,upper,i)) }
        }
        return result
    }
}
