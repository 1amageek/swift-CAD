import CADCore

/// The dimensional root of a shape, without an implied material ownership change.
public indirect enum ShapeReference: Equatable, Sendable {
    case vertex(VertexID)
    case edge(EdgeID)
    case wire(ShapeWire)
    case face(FaceID)
    case shell(ShellID)
    case solid(BodyID)
    case compound([ShapeReference])
}
