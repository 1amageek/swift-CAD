import CADCore

/// Original atlas parameters and spatial truth retained independently of geometric images.
public struct OriginalCurveCurveContact: Sendable {
    public let firstSource: OriginalCurveContactSource
    public let secondSource: OriginalCurveContactSource
    public let firstParameters: ScalarInterval
    public let secondParameters: ScalarInterval
    public let position: CoordinateEnclosure3D
    public let tolerance: ModelingTolerance
    public let parameterAuthority: OriginalCurveContactParameterAuthority?
    package let firstNativeSpanIndex: Int?

    /// Evaluates the retained validated law; paid preparation is never replayed here.
    public func firstPoint(allowance: inout OriginalCurveContactAllowance) throws -> Point3D {
        guard allowance.budget.tolerance == tolerance else {
            throw KernelError(phase: .geometry, code: .invalidInput, tolerance: tolerance,
                message: "Original contact materialization requires its exact tolerance-bound caller allowance.")
        }
        let cost = try OriginalCurveContactCost(source: firstSource.curve, budget: &allowance.budget)
        try allowance.budget.work(cost.jet)
        return try firstSource.curve.pointAssumingValid(at: firstParameters.midpoint, tolerance: tolerance)
    }

    init(firstSource: OriginalCurveContactSource, secondSource: OriginalCurveContactSource,
         firstParameters: ScalarInterval, secondParameters: ScalarInterval, position: CoordinateEnclosure3D, tolerance: ModelingTolerance,
         parameterAuthority: OriginalCurveContactParameterAuthority? = nil,
         firstNativeSpanIndex: Int? = nil) {
        self.firstSource = firstSource
        self.secondSource = secondSource
        self.firstParameters = firstParameters
        self.secondParameters = secondParameters
        self.position = position
        self.tolerance = tolerance
        self.parameterAuthority = parameterAuthority
        self.firstNativeSpanIndex = firstNativeSpanIndex
    }
}
