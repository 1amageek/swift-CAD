import CADCore

public protocol OriginalCircularMeasuring: Sendable {
    func measure(_ curve: Curve3D, at boundaryParameter: Double,
        placement: OriginalAffineOperationWord?, tolerance: ModelingTolerance,
        maximumSubdivisionDepth: Int, remainingSourceDepth: Int, maximumAlgebraicDepth: Int,
        using execution: inout OriginalQueryExecution) throws -> OriginalCircularMeasurement
    func measure(_ curve: Curve3D, from startParameter: Double, to endParameter: Double,
        atNormalizedBoundaryParameter: Double, placement: OriginalAffineOperationWord?,
        tolerance: ModelingTolerance, maximumSubdivisionDepth: Int, remainingSourceDepth: Int,
        maximumAlgebraicDepth: Int, using execution: inout OriginalQueryExecution) throws -> OriginalCircularMeasurement
}
