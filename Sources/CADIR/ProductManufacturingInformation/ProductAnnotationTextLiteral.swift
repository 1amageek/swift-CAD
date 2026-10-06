import CADCore

/// Original standard drawing-text occurrence and literal placement.
public struct ProductAnnotationTextLiteral: Equatable, Sendable {
    public enum Placement: String, Sendable { case twoDimensional, threeDimensional }
    public enum Path: String, Sendable { case left, right, up, down }
    public let id: ProductMetadataID
    public var literalName: String
    public var occurrenceName: String
    public var text: String
    public var origin: Point3D
    public var direction: Vector3D
    public var up: Vector3D
    public var placement: Placement
    public var alignment: String
    public var path: Path
    public var fontName: String
    public init(id: ProductMetadataID = ProductMetadataID(), literalName: String = "", occurrenceName: String = "",
        text: String, origin: Point3D = .origin, direction: Vector3D = .unitZ, up: Vector3D = .unitY,
        placement: Placement = .threeDimensional, alignment: String = "bottom left", path: Path = .right,
        fontName: String = "ISO 3098") {
        self.id=id; self.literalName=literalName; self.occurrenceName=occurrenceName; self.text=text
        self.origin=origin; self.direction=direction; self.up=up; self.placement=placement
        self.alignment=alignment; self.path=path; self.fontName=fontName
    }
}

#if !hasFeature(Embedded)
extension ProductAnnotationTextLiteral: Codable {
    private enum CodingKeys: String, CodingKey { case id, literalName, occurrenceName, text, origin, direction, up, placement, alignment, path, fontName }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy:CodingKeys.self)
        try c.validateOnlyExpectedKeys([.id,.literalName,.occurrenceName,.text,.origin,.direction,.up,.placement,.alignment,.path,.fontName],in:decoder)
        id=try c.decode(ProductMetadataID.self,forKey:.id)
        literalName=try c.decode(String.self,forKey:.literalName)
        occurrenceName=try c.decode(String.self,forKey:.occurrenceName)
        text=try c.decode(String.self,forKey:.text)
        origin=try c.decode(Point3D.self,forKey:.origin)
        direction=try c.decode(Vector3D.self,forKey:.direction)
        up=try c.decode(Vector3D.self,forKey:.up)
        placement=try c.decode(Placement.self,forKey:.placement)
        alignment=try c.decode(String.self,forKey:.alignment)
        path=try c.decode(Path.self,forKey:.path)
        fontName=try c.decode(String.self,forKey:.fontName)
    }
}
extension ProductAnnotationTextLiteral.Placement: Codable {}
extension ProductAnnotationTextLiteral.Path: Codable {}
#endif
