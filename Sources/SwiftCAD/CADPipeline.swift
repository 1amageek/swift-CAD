import Foundation
import CADCore
import CADIR
import CADKernel
import CADExchange

public struct CADPipeline: Sendable {
    private let evaluator: DocumentEvaluator
    private let snapQueryEvaluator: SnapQueryEvaluator
    private let stlExporter: STLExporter
    private let packageStore: NativePackageStore
    private let officialExchange: OfficialFormatExchange

    public init(
        evaluator: DocumentEvaluator = DocumentEvaluator(),
        snapQueryEvaluator: SnapQueryEvaluator = SnapQueryEvaluator(),
        stlExporter: STLExporter = STLExporter(),
        packageStore: NativePackageStore = NativePackageStore(),
        officialExchange: OfficialFormatExchange = OfficialFormatExchange()
    ) {
        self.evaluator = evaluator
        self.snapQueryEvaluator = snapQueryEvaluator
        self.stlExporter = stlExporter
        self.packageStore = packageStore
        self.officialExchange = officialExchange
    }

    public func evaluate(_ document: CADDocument) throws -> EvaluatedDocument {
        try evaluator.evaluate(document)
    }

    public func snapCandidates(
        near point: Point3D,
        in evaluatedDocument: EvaluatedDocument,
        options: SnapQueryOptions = SnapQueryOptions()
    ) throws -> SnapQueryResult {
        try snapQueryEvaluator.candidates(near: point, in: evaluatedDocument, options: options)
    }

    public func executeAgentQuery(
        _ query: CADAgentQuery,
        in document: CADDocument
    ) throws -> CADAgentQueryResult {
        let evaluatedDocument = try evaluate(document)
        switch query {
        case let .snap(snap):
            return .snap(try snapCandidates(
                near: snap.point,
                in: evaluatedDocument,
                options: snap.options
            ))
        }
    }

    public func solveSketchDimensions(
        in document: CADDocument,
        featureID: FeatureID,
        tolerance: ModelingTolerance = .standard
    ) throws -> CADDocumentSketchDimensionSolveResult {
        try document.validate(tolerance: tolerance)
        guard var feature = document.designGraph.nodes[featureID] else {
            throw FeatureEvaluationError.invalidGraph("Sketch dimension solve target feature is missing.")
        }
        guard case let .sketch(sketch) = feature.operation else {
            throw FeatureEvaluationError.unsupportedOperation("Sketch dimension solve requires a sketch feature.")
        }

        let solver = SketchDimensionSolver(parameters: document.parameters)
        let sketchResult = try solver.solve(sketch, tolerance: tolerance)
        let hasAppliedStep = sketchResult.steps.contains { $0.status == .applied }

        var updatedDocument = document
        let invalidatedFeatureIDs: [FeatureID]
        if hasAppliedStep {
            feature.operation = .sketch(sketchResult.sketch)
            updatedDocument.designGraph.nodes[featureID] = feature
            updatedDocument.designGraph.revision = updatedDocument.designGraph.revision.advanced()
            invalidatedFeatureIDs = try updatedDocument.designGraph.invalidatedFeatureIDs(after: featureID)
        } else {
            invalidatedFeatureIDs = []
        }

        try updatedDocument.validate(tolerance: tolerance)
        return CADDocumentSketchDimensionSolveResult(
            document: updatedDocument,
            featureID: featureID,
            invalidatedFeatureIDs: invalidatedFeatureIDs,
            sketchResult: sketchResult
        )
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
