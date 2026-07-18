import CADIR

public struct SketchConstraintSolveResult: Codable, Sendable {
    public let sketch: Sketch
    public let status: SketchConstraintSolveStatus
    public let remainingDegreesOfFreedom: Int
    public let redundantEquationCount: Int
    public let maximumNormalizedResidual: Double
    public let iterations: Int

    public init(
        sketch: Sketch,
        status: SketchConstraintSolveStatus,
        remainingDegreesOfFreedom: Int,
        redundantEquationCount: Int,
        maximumNormalizedResidual: Double,
        iterations: Int
    ) {
        self.sketch = sketch
        self.status = status
        self.remainingDegreesOfFreedom = remainingDegreesOfFreedom
        self.redundantEquationCount = redundantEquationCount
        self.maximumNormalizedResidual = maximumNormalizedResidual
        self.iterations = iterations
    }
}
