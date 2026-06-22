import Foundation
import CADCore
import CADIR
import CADKernel
import CADExchange

public struct CADPipeline: Sendable {
    private let evaluator: DocumentEvaluator
    private let stlExporter: STLExporter
    private let packageStore: NativePackageStore
    private let officialExchange: OfficialFormatExchange

    public init(
        evaluator: DocumentEvaluator = DocumentEvaluator(),
        stlExporter: STLExporter = STLExporter(),
        packageStore: NativePackageStore = NativePackageStore(),
        officialExchange: OfficialFormatExchange = OfficialFormatExchange()
    ) {
        self.evaluator = evaluator
        self.stlExporter = stlExporter
        self.packageStore = packageStore
        self.officialExchange = officialExchange
    }

    public func evaluate(_ document: CADDocument) throws -> EvaluatedDocument {
        try evaluator.evaluate(document)
    }

    public func writeBinarySTL(
        from evaluatedDocument: EvaluatedDocument,
        lengthUnit: LengthUnit = .meter,
        to sink: any ByteSink
    ) throws {
        try evaluatedDocument.validate()
        try stlExporter.writeBinary(
            meshes: evaluatedDocument.meshes,
            options: STLExportOptions(lengthUnit: lengthUnit),
            to: sink
        )
    }

    public func writePackage(for document: CADDocument, to sink: any ByteSink) throws {
        try packageStore.writePackage(for: document, to: sink)
    }

    public func loadDocument(from source: any ByteSource) throws -> CADDocument {
        try packageStore.loadDocument(from: source)
    }

    public func save(_ document: CADDocument, to url: URL) throws {
        try packageStore.save(document, to: url)
    }

    public func load(from url: URL) throws -> CADDocument {
        try packageStore.load(from: url)
    }

    public func write(
        _ evaluatedDocument: EvaluatedDocument,
        as format: ExchangeFileFormat,
        units overrideUnits: UnitSystem? = nil,
        to sink: any ByteSink
    ) throws {
        try officialExchange.write(evaluatedDocument, as: format, units: overrideUnits, to: sink)
    }

    public func importExchange(_ source: any ByteSource, as format: ExchangeFileFormat) throws -> ImportedExchangeModel {
        try officialExchange.import(source, as: format)
    }
}
