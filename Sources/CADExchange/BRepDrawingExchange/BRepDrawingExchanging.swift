import CADKernel
import CADCore
import CADGeometry

public protocol BRepDrawingExchanging: Sendable {
    func write(_ page: DrawingExchangePage, as format: ExchangeFileFormat, outputUnit: CADCore.LengthUnit,
               usage: DrawingExchangeOwner, using execution: inout OriginalQueryExecution, to sink: any ByteSink) throws
    func write(_ section: BRepDrawingSection, in evaluated: EvaluatedDocument,
               hatchSegments: [BRepDrawingHatchSegment], regions: [BRepDrawingMaterialRegion], as format: ExchangeFileFormat,
               options: DrawingExchangeOptions, to sink: any ByteSink) throws
    func write(_ projection: BRepDrawingPlacedProjection, in evaluated: EvaluatedDocument, as format: ExchangeFileFormat,
               options: DrawingExchangeOptions, to sink: any ByteSink) throws
    func write(_ projection: BRepDrawingProjection, in evaluated: EvaluatedDocument, as format: ExchangeFileFormat,
               options: DrawingExchangeOptions, to sink: any ByteSink) throws
    func write(_ projection: BRepDrawingProjection, as format: ExchangeFileFormat,
               options: DrawingExchangeOptions, to sink: any ByteSink) throws
}
