public enum OriginalSTEPSplineSurfaceForm: String, Sendable {
    case plane = "PLANE_SURF", cylindrical = "CYLINDRICAL_SURF", conical = "CONICAL_SURF"
    case spherical = "SPHERICAL_SURF", toroidal = "TOROIDAL_SURF", revolution = "SURF_OF_REVOLUTION"
    case ruled = "RULED_SURF", generalisedCone = "GENERALISED_CONE", quadric = "QUADRIC_SURF"
    case linearExtrusion = "SURF_OF_LINEAR_EXTRUSION", unspecified = "UNSPECIFIED"
    public var stepToken: String { "." + rawValue + "." }
}
#if !hasFeature(Embedded)
extension OriginalSTEPSplineSurfaceForm: Codable {}
#endif
