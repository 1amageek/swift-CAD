import CADCore
import CADGeometry

public enum BRepDistanceSelection: Hashable, Sendable {
    case point(Point3D)
    case curve(Curve3D, from: Double, to: Double)
    case surfaceStation(Surface3D, SurfaceParameter)
    case vertex(VertexID)
    case edge(EdgeID)
    case face(FaceID)
    case faceRegion(FaceID, SurfaceParameterBox)
    case body(BodyID)
}
