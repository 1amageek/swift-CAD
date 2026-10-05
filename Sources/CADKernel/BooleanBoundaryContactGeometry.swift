import CADGeometry

public enum BooleanBoundaryContactGeometry: Hashable, Sendable {
    case points([CurveSurfaceIntersection])
    case coincident
}

#if !hasFeature(Embedded)
extension BooleanBoundaryContactGeometry: Codable {}
#endif
