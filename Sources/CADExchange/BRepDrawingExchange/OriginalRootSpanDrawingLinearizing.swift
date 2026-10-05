import CADGeometry

public protocol OriginalRootSpanDrawingLinearizing: Sendable {
    func linearize(_ span: OriginalCurveRootSpan3D, operationWord: OriginalAffineOperationWord,
        maximumDeviation: Double, usage: inout DrawingExchangeUsage) throws -> OriginalRootSpanDrawingPath
}
