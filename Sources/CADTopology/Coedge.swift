import CADCore
import CADGeometry

/// A face-local oriented use of an edge with its exact parameter-space curve.
public struct Coedge: Codable, Equatable, Sendable {
    public var edgeID: EdgeID
    public var orientation: Orientation
    public var surfaceParameterCurve: SurfaceParameterCurve?

    public init(
        edgeID: EdgeID,
        orientation: Orientation = .forward,
        surfaceParameterCurve: SurfaceParameterCurve? = nil
    ) {
        self.edgeID = edgeID
        self.orientation = orientation
        self.surfaceParameterCurve = surfaceParameterCurve
    }
}
