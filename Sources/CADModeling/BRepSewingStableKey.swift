/// Deterministic semantic key for topology emitted by the exact sewer.
public enum BRepSewingStableKey: Hashable, Sendable {
    case body
    case face(String)
    case edge(String)
    case startVertex(edge: String)
    case endVertex(edge: String)
}
