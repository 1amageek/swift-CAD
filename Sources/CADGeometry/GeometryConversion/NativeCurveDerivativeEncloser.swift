import CADCore

/// Reuses the original prepared native curve; no conversion changes its law.
package struct NativeCurveDerivativeEncloser: GeometryCurveDerivativeEnclosing {
    package let curve: Curve3D
    private let prepared: PreparedCurveDifferentialEncloser
    private let tolerance: ModelingTolerance
    private let receipt: OriginalGeometryPreparationReceipt

    package init(curve: Curve3D, tolerance: ModelingTolerance,
        using execution: inout OriginalQueryExecution) throws {
        self.curve = curve
        self.tolerance = tolerance
        let preparation = try execution.withPreparationScope { execution in
            try PreparedCurveDifferentialEncloser(curve: curve, tolerance: tolerance, using: &execution)
        }
        prepared = preparation.result
        receipt = try OriginalGeometryPreparationReceipt(tolerance: tolerance, depth: preparation.depth, using: &execution)
    }

    /// Caller-owned original closed interval derivatives through the requested order.
    package static func originalDerivatives(of curve: Curve3D, over parameters: ScalarInterval,
        tolerance: ModelingTolerance, throughOrder order: Int, maximumSpanCount: Int,
        maximumSubdivisionDepth: Int, remainingSourceDepth: Int,
        using execution: inout OriginalQueryExecution) throws -> IntervalVectorDerivativeJet {
        guard order >= 0 else {
            throw GeometryConversionError.invalidInput("Original derivative order must be nonnegative.")
        }
        let source = try OriginalCurveHigherJetProvider.intervalTaylorJet(of: curve,
            over: parameters, tolerance: tolerance, throughOrder: max(4, order),
            maximumSpanCount: maximumSpanCount, maximumSubdivisionDepth: maximumSubdivisionDepth,
            remainingSourceDepth: remainingSourceDepth, using: &execution)
        func component(_ scalar: SurfaceAreaIntervalTaylorScalarJet) throws -> IntervalDerivativeJet {
            let capacity = order.addingReportingOverflow(1)
            guard !capacity.overflow else { throw GeometryConversionError.resourceLimitExceeded("Original derivative capacity overflowed.") }
            try OriginalCoefficientAllocation.reserve(count: capacity.partialValue, of: OutwardScalarInterval.self, using: &execution)
            var derivatives: [OutwardScalarInterval] = []; derivatives.reserveCapacity(capacity.partialValue)
            for k in 0...order {
                try execution.consumeWork(1)
                var value = try scalar.coefficient(k, 0)
                if k > 1 { for factor in 2...k {
                    try execution.consumeWork(1); value = value * .exact(Double(factor))
                } }
                guard value.isFinite else {
                    throw GeometryConversionError.resourceLimitExceeded("Original requested derivative has nonfinite scaling bounds.")
                }
                derivatives.append(value)
            }
            return IntervalDerivativeJet(derivatives: derivatives)
        }
        return try IntervalVectorDerivativeJet(x: component(source.x), y: component(source.y), z: component(source.z))
    }

    package func derivatives(over parameters: ScalarInterval,
        tolerance: ModelingTolerance) throws -> IntervalVectorDerivativeJet {
        var execution = try receipt.makeExecution()
        return try derivatives(over: parameters, tolerance: tolerance, using: &execution)
    }

    package func derivatives(over parameters: ScalarInterval, tolerance: ModelingTolerance,
        using execution: inout OriginalQueryExecution) throws -> IntervalVectorDerivativeJet {
        try receipt.admit(tolerance: tolerance, using: &execution)
        guard tolerance == self.tolerance else {
            throw GeometryConversionError.invalidInput("A native derivative port requires its exact preparation tolerance.")
        }
        try CurrentTaskCancellationChecker().checkCancellation()
        let jet = try prepared.thirdOrderIntervalJet(over: parameters, tolerance: tolerance, using: &execution)
        func component(_ value: SurfaceIntervalJet) -> IntervalDerivativeJet {
            IntervalDerivativeJet(derivatives: [value.value, value.derivativeU,
                value.secondDerivativeUU, value.thirdDerivativeUUU])
        }
        try OriginalCoefficientAllocation.reserve(count: 12, of: OutwardScalarInterval.self, using: &execution)
        let result = IntervalVectorDerivativeJet(x: component(jet.x),
            y: component(jet.y), z: component(jet.z))
        try CurrentTaskCancellationChecker().checkCancellation()
        return result
    }
}
