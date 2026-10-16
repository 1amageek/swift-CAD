import CADCore
import CADGeometry

public struct BRepDrawingSilhouetteSpan: Sendable {
    public let bodyID: BodyID
    public let faceID: FaceID
    public let componentOrdinal: Int
    public let curveOrdinal: Int
    public let curve: OriginalSurfaceSilhouetteCurve
    public let nativeRange: ScalarInterval
    public let frame: OrthographicProjectionFrame

    /// Retains authored native boundaries without replacing algebraic trim expressions.
    public func exactSpan(using execution: inout OriginalQueryExecution) throws -> BRepDrawingExactSilhouetteSpan {
        try execution.retainStorage(bytes: MemoryLayout<BRepDrawingExactSilhouetteSpan>.stride)
        let trimmed = try OriginalSurfaceSilhouetteTrimmedCurve(original: curve,
            from: nativeRange.lower, to: nativeRange.upper, using: &execution)
        return .init(bodyID: bodyID, faceID: faceID, componentOrdinal: componentOrdinal,
            curveOrdinal: curveOrdinal, curve: trimmed, isCoincidentWithTrim: false,
            constantSpatialEnclosure: nil, frame: frame)
    }

    public func point(at parameter: Double, using execution: inout OriginalQueryExecution) throws -> Point2D {
        guard nativeRange.contains(parameter) else {
            throw KernelError(phase: .geometry, code: .invalidInput,
                tolerance: curve.certificationTolerance, message: "Silhouette query exceeds its retained trim.")
        }
        return try frame.project(curve.point(at: parameter, using: &execution))
    }
}
