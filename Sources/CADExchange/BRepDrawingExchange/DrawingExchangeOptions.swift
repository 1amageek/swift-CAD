import CADCore

public struct DrawingExchangeOptions: Sendable {
    public var styles: DrawingExchangeStyles
    public var outputUnit: LengthUnit
    public var paperScale: Double
    public var maximumCurveDeviation: Double
    public var translation: Point2D
    public var pageWidth: Double
    public var pageHeight: Double
    public init(outputUnit: LengthUnit = .millimeter, paperScale: Double = 1,
                maximumCurveDeviation: Double = ModelingTolerance.standard.distance,
                translation: Point2D = Point2D(x:0,y:0), pageWidth: Double = 210, pageHeight: Double = 297,
                styles: DrawingExchangeStyles = .init()) {
        self.styles = styles
        self.outputUnit = outputUnit; self.paperScale = paperScale; self.maximumCurveDeviation = maximumCurveDeviation
        self.translation = translation; self.pageWidth = pageWidth; self.pageHeight = pageHeight
    }
    public func validate() throws {
        try styles.validate()
        guard paperScale.isFinite, paperScale > 0, maximumCurveDeviation.isFinite, maximumCurveDeviation > 0,
              translation.x.isFinite, translation.y.isFinite, pageWidth.isFinite, pageHeight.isFinite,
              pageWidth > 0, pageHeight > 0 else { throw ExportError.invalidMesh("Invalid drawing conversion or paper options.") }
    }
    func outputLength(paperPoints: Double) throws -> Double {
        let result = outputUnit.fromInternal(paperPoints * (0.0254 / 72))
        guard result.isFinite, result > 0 else { throw ExportError.invalidMesh("Drawing physical style length overflows.") }
        return result
    }
    func transform(_ point: Point2D) throws -> Point2D {
        let result = Point2D(x: outputUnit.fromInternal(point.x) * paperScale + translation.x,
            y: outputUnit.fromInternal(point.y) * paperScale + translation.y)
        guard result.x.isFinite, result.y.isFinite else { throw ExportError.invalidMesh("Drawing output coordinate overflow.") }
        return result
    }
}
