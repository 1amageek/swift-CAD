import CADCore
import CADGeometry
import CADTopology

/// Encodes original source fields owned by `CADIR.ProductSavedView`.
extension CADIR.ProductSavedView: PortableSourceEncodable {
    public func encodeSource<A: NumericWorkAdmission & ~Copyable>(to encoder: inout PortableSourceEncoder, using admission: inout A) throws {
        try encoder.record("CADIR.ProductSavedView", fields: 22, using: &admission)
        try encoder.field("annotationPlacements", annotationPlacements, using: &admission)
        try encoder.field("backClipping", backClipping, using: &admission)
        try encoder.field("clippingExpression", clippingExpression, using: &admission)
        try encoder.field("clippingPlanes", clippingPlanes, using: &admission)
        try encoder.field("direction", direction, using: &admission)
        try encoder.field("farDistance", farDistance, using: &admission)
        try encoder.field("focalDistance", focalDistance, using: &admission)
        try encoder.field("frontClipping", frontClipping, using: &admission)
        try encoder.field("horizontalSize", horizontalSize, using: &admission)
        try encoder.field("id", id, using: &admission)
        try encoder.field("name", name, using: &admission)
        try encoder.field("nearDistance", nearDistance, using: &admission)
        try encoder.field("origin", origin, using: &admission)
        try encoder.field("projection", projection, using: &admission)
        try encoder.field("projectionPoint", projectionPoint, using: &admission)
        try encoder.field("sideClipping", sideClipping, using: &admission)
        try encoder.field("up", up, using: &admission)
        try encoder.field("verticalSize", verticalSize, using: &admission)
        try encoder.field("windowDirection", windowDirection, using: &admission)
        try encoder.field("windowOrigin", windowOrigin, using: &admission)
        try encoder.field("windowPlacement", windowPlacement, using: &admission)
        try encoder.field("windowUp", windowUp, using: &admission)
    }
}
