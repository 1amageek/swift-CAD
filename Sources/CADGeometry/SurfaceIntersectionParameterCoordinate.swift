public enum SurfaceIntersectionParameterCoordinate: Int, CaseIterable, Sendable, Hashable {
    case firstU = 0
    case firstV = 1
    case secondU = 2
    case secondV = 3
}

#if !hasFeature(Embedded)
extension SurfaceIntersectionParameterCoordinate: Codable {}
#endif
