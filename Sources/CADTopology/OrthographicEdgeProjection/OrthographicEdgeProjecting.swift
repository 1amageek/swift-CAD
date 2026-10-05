import CADCore
import CADGeometry

/// Projects one selected original edge, without using tessellation or visibility.
public protocol OrthographicEdgeProjecting: Sendable {
    func project(
        edgeID: EdgeID,
        in model: BRepModel,
        orientation: Orientation,
        onto frame: OrthographicProjectionFrame,
        tolerance: ModelingTolerance
    ) throws -> OrthographicProjectedEdge
}
