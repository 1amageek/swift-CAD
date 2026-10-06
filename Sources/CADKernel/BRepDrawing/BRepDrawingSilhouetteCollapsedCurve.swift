import CADCore
import CADGeometry

/// A retained native contour range whose original spatial image is certified constant.
public struct BRepDrawingSilhouetteCollapsedCurve: Sendable {
    public let bodyID: BodyID
    public let faceID: FaceID
    public let componentOrdinal: Int
    public let curveOrdinal: Int
    public let curve: OriginalSurfaceSilhouetteCurve
    public let nativeRange: ScalarInterval
    public let spatialEnclosure: CoordinateEnclosure3D
    public let projectedEnclosure: CoordinateEnclosure2D
}
