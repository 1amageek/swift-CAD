/// The original standard representation family, independent of a product association.
public enum IndependentShapeRepresentationFamily: String, Sendable {
    case representation = "REPRESENTATION"
    case shape = "SHAPE_REPRESENTATION"
    case geometricallyBoundedWireframe = "GEOMETRICALLY_BOUNDED_WIREFRAME_SHAPE_REPRESENTATION"
    case geometricallyBoundedSurface = "GEOMETRICALLY_BOUNDED_SURFACE_SHAPE_REPRESENTATION"
}

#if !hasFeature(Embedded)
extension IndependentShapeRepresentationFamily: Codable {}
#endif
