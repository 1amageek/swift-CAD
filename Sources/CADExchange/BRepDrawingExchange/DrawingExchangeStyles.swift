public struct DrawingExchangeStyles: Sendable {
    public var geometry: DrawingStrokeStyle
    public var visible: DrawingStrokeStyle
    public var hidden: DrawingStrokeStyle
    public var partiallyHidden: DrawingStrokeStyle
    public var sectionContour: DrawingStrokeStyle
    public var sectionHatch: DrawingStrokeStyle
    public var annotation: DrawingStrokeStyle
    public var material: DrawingFillStyle
    public init(geometry: DrawingStrokeStyle = .init(), visible: DrawingStrokeStyle = .init(),
                hidden: DrawingStrokeStyle = .init(dashPattern: [3, 2]),
                partiallyHidden: DrawingStrokeStyle = .init(dashPattern: [3, 2]),
                sectionContour: DrawingStrokeStyle = .init(width: 0.7),
                sectionHatch: DrawingStrokeStyle = .init(width: 0.25),
                annotation: DrawingStrokeStyle = .init(), material: DrawingFillStyle = .init()) {
        self.geometry = geometry; self.visible = visible; self.hidden = hidden
        self.partiallyHidden = partiallyHidden; self.sectionContour = sectionContour
        self.sectionHatch = sectionHatch; self.annotation = annotation; self.material = material
    }
    public func validate() throws {
        for style in strokes { try style.validate() }
        try material.validate()
    }
    var strokes: [DrawingStrokeStyle] { [geometry, visible, hidden, partiallyHidden, sectionContour, sectionHatch, annotation] }
    func stroke(for layer: String) -> DrawingStrokeStyle {
        switch layer {
        case "Visible": visible
        case "Hidden": hidden
        case "PartiallyHidden": partiallyHidden
        case "Section", "SectionContact", "SectionCoplanarBoundary", "SectionContour": sectionContour
        case "SectionHatch": sectionHatch
        case "Annotation": annotation
        default: geometry
        }
    }
}
