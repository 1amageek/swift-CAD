import CADCore
import CADTopology

/// One actual directed topological use of a retained projected original curve.
public struct BRepDrawingProjectedUse: Sendable {
    public let bodyID: BodyID
    public let shellID: ShellID
    public let faceID: FaceID
    public let loopID: LoopID
    public let coedgeOrientation: Orientation
    public let edge: OrthographicProjectedEdge
}
