import CADCore

/// Typed identities used by structural diagnostics, including geometry references.
public enum TopologyEntityReference: Sendable, Hashable {
    case body(BodyID)
    case shell(ShellID)
    case face(FaceID)
    case loop(LoopID)
    case edge(EdgeID)
    case vertex(VertexID)
    case curve(CurveID)
    case surface(SurfaceID)
}
