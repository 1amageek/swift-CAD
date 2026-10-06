import CADCore

public protocol OriginalCircularMeasuring: Sendable {
    func measure(_ curve: Curve3D, at boundaryParameter: Double,
        placement: OriginalAffineOperationWord?, tolerance: ModelingTolerance,
        maximumSubdivisionDepth: Int, remainingSourceDepth: Int, maximumAlgebraicDepth: Int,
        consumeWork: @escaping @Sendable (Int) throws -> Void,
        consumeStorage: (@Sendable (Int) throws -> Void)?) throws -> OriginalCircularMeasurement
    func measure(_ curve: Curve3D, from startParameter: Double, to endParameter: Double,
        atNormalizedBoundaryParameter: Double, placement: OriginalAffineOperationWord?,
        tolerance: ModelingTolerance, maximumSubdivisionDepth: Int, remainingSourceDepth: Int,
        maximumAlgebraicDepth: Int, consumeWork: @escaping @Sendable (Int) throws -> Void,
        consumeStorage: (@Sendable (Int) throws -> Void)?) throws -> OriginalCircularMeasurement
}
