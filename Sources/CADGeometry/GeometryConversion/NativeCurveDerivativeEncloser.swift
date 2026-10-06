import CADCore

/// Reuses the original prepared native curve; no conversion changes its law.
package struct NativeCurveDerivativeEncloser: GeometryCurveDerivativeEnclosing {
    package let curve: Curve3D
    private let prepared: PreparedCurveDifferentialEncloser
    private let tolerance: ModelingTolerance

    package init(curve: Curve3D, tolerance: ModelingTolerance,
        consumeWork: () throws -> Void) throws {
        self.curve = curve
        self.tolerance = tolerance
        prepared = try PreparedCurveDifferentialEncloser(curve: curve,
            tolerance: tolerance, consumeWork: consumeWork)
    }

    /// Caller-owned original closed interval derivatives through the requested order.
    package static func originalDerivatives(of curve: Curve3D, over parameters: ScalarInterval,
        tolerance: ModelingTolerance, throughOrder order: Int, maximumSpanCount: Int,
        maximumSubdivisionDepth: Int, remainingSourceDepth: Int,
        consumeWork: () throws -> Void) throws -> IntervalVectorDerivativeJet {
        guard order >= 0 else {
            throw GeometryConversionError.invalidInput("Original derivative order must be nonnegative.")
        }
        let source = try OriginalCurveHigherJetProvider.intervalTaylorJet(of: curve,
            over: parameters, tolerance: tolerance, throughOrder: max(4, order),
            maximumSpanCount: maximumSpanCount, maximumSubdivisionDepth: maximumSubdivisionDepth,
            remainingSourceDepth: remainingSourceDepth, consumeWork: consumeWork)
        func component(_ scalar: SurfaceAreaIntervalTaylorScalarJet) throws -> IntervalDerivativeJet {
            var derivatives: [OutwardScalarInterval] = []
            for k in 0...order {
                try consumeWork()
                var value = try scalar.coefficient(k, 0)
                if k > 1 { for factor in 2...k {
                    try consumeWork(); value = value * .exact(Double(factor))
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
        guard tolerance == self.tolerance else {
            throw GeometryConversionError.invalidInput("A native derivative port requires its exact preparation tolerance.")
        }
        try CurrentTaskCancellationChecker().checkCancellation()
        let jet = try prepared.thirdOrderIntervalJet(over: parameters, tolerance: tolerance)
        func component(_ value: SurfaceIntervalJet) -> IntervalDerivativeJet {
            IntervalDerivativeJet(derivatives: [value.value, value.derivativeU,
                value.secondDerivativeUU, value.thirdDerivativeUUU])
        }
        let result = IntervalVectorDerivativeJet(x: component(jet.x),
            y: component(jet.y), z: component(jet.z))
        try CurrentTaskCancellationChecker().checkCancellation()
        return result
    }
}
