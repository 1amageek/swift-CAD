import CADCore

/// A run shaped by the page owner's explicit Native font producer.
public struct DrawingGlyphOutline: Sendable {
    public let text: String
    public let fontPostScriptName: String
    public let fontSize: Double
    public let identity: String
    public let fillRule: DrawingGlyphFillRule
    public let commands: [DrawingGlyphPathCommand]
    public init(text: String, fontPostScriptName: String, fontSize: Double,
                identity: String, commands: [DrawingGlyphPathCommand], fillRule: DrawingGlyphFillRule = .nonzero) {
        self.text = text; self.fontPostScriptName = fontPostScriptName
        self.fontSize = fontSize; self.identity = identity; self.commands = commands; self.fillRule = fillRule
    }
}
