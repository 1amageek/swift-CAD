/// Final paper-point page. Source freshness and placement belong to its producer.
public struct DrawingExchangePage: Sendable {
    public let width: Double
    public let height: Double
    public let paths: [DrawingPagePath]
    public let regions: [DrawingPageRegion]
    public let glyphs: [DrawingGlyphOutline]
    public let resolvedGlyphBoundaries: [DrawingResolvedGlyphBoundary]
    public let styles: DrawingExchangeStyles
    public let maximumGlyphDeviation: Double
    public init(width: Double, height: Double, paths: [DrawingPagePath], glyphs: [DrawingGlyphOutline],
                styles: DrawingExchangeStyles, maximumGlyphDeviation: Double, regions: [DrawingPageRegion] = [], resolvedGlyphBoundaries: [DrawingResolvedGlyphBoundary] = []) {
        self.width = width; self.height = height; self.paths = paths; self.glyphs = glyphs
        self.styles = styles; self.maximumGlyphDeviation = maximumGlyphDeviation; self.regions = regions
        self.resolvedGlyphBoundaries = resolvedGlyphBoundaries
    }
}
