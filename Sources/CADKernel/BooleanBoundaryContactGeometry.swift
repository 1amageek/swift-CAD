import CADGeometry

public enum BooleanBoundaryContactGeometry: Codable, Hashable, Sendable {
    case points([CurveSurfaceIntersection])
    case coincident
}
