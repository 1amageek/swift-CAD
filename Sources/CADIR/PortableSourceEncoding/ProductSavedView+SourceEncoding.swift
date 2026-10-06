import CADCore
import CADGeometry
import CADTopology

/// Encodes original source fields owned by `CADIR.ProductSavedView`.
extension CADIR.ProductSavedView: PortableSourceEncodable {
    public func encodeSource(to encoder: inout PortableSourceEncoder) throws {
        try encoder.record("CADIR.ProductSavedView", fields: 22)
        try encoder.field("annotationPlacements", annotationPlacements)
        try encoder.field("backClipping", backClipping)
        try encoder.field("clippingExpression", clippingExpression)
        try encoder.field("clippingPlanes", clippingPlanes)
        try encoder.field("direction", direction)
        try encoder.field("farDistance", farDistance)
        try encoder.field("focalDistance", focalDistance)
        try encoder.field("frontClipping", frontClipping)
        try encoder.field("horizontalSize", horizontalSize)
        try encoder.field("id", id)
        try encoder.field("name", name)
        try encoder.field("nearDistance", nearDistance)
        try encoder.field("origin", origin)
        try encoder.field("projection", projection)
        try encoder.field("projectionPoint", projectionPoint)
        try encoder.field("sideClipping", sideClipping)
        try encoder.field("up", up)
        try encoder.field("verticalSize", verticalSize)
        try encoder.field("windowDirection", windowDirection)
        try encoder.field("windowOrigin", windowOrigin)
        try encoder.field("windowPlacement", windowPlacement)
        try encoder.field("windowUp", windowUp)
    }
}
