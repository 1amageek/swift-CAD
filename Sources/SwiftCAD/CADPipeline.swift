import Foundation
import CADCore
import CADIR
import CADKernel
import CADExchange

public struct CADPipeline: Sendable {
    private let evaluator: DocumentEvaluator
    private let snapQueryEvaluator: SnapQueryEvaluator
    private let selectionMeasurementEvaluator: SelectionMeasurementEvaluator
    private let selectionDimensionEvaluator: SelectionDimensionEvaluator
    private let stlExporter: STLExporter
    private let packageStore: NativePackageStore
    private let officialExchange: OfficialFormatExchange
    private let commandApplier: CADCommandApplier
    private let capabilityCatalog: KernelCapabilityCatalog

    public init(
        evaluator: DocumentEvaluator = DocumentEvaluator(),
        snapQueryEvaluator: SnapQueryEvaluator = SnapQueryEvaluator(),
        selectionMeasurementEvaluator: SelectionMeasurementEvaluator = SelectionMeasurementEvaluator(),
        selectionDimensionEvaluator: SelectionDimensionEvaluator = SelectionDimensionEvaluator(),
        stlExporter: STLExporter = STLExporter(),
        packageStore: NativePackageStore = NativePackageStore(),
        officialExchange: OfficialFormatExchange = OfficialFormatExchange(),
        commandApplier: CADCommandApplier = CADCommandApplier(),
        capabilityCatalog: KernelCapabilityCatalog = KernelCapabilities.current
    ) {
        self.evaluator = evaluator
        self.snapQueryEvaluator = snapQueryEvaluator
        self.selectionMeasurementEvaluator = selectionMeasurementEvaluator
        self.selectionDimensionEvaluator = selectionDimensionEvaluator
        self.stlExporter = stlExporter
        self.packageStore = packageStore
        self.officialExchange = officialExchange
        self.commandApplier = commandApplier
        self.capabilityCatalog = capabilityCatalog
    }

    public func capabilities() -> KernelCapabilityCatalog {
        capabilityCatalog
    }

    public func apply(
        _ command: CADCommand,
        to document: CADDocument,
        tolerance: ModelingTolerance = .standard
    ) throws -> CADDocument {
        try commandApplier.apply(command, to: document, tolerance: tolerance)
    }

    public func evaluate(_ document: CADDocument) throws -> EvaluatedDocument {
        do {
            return try evaluator.evaluate(document)
        } catch {
            throw KernelError.wrapping(error, phase: .evaluation)
        }
    }

    public func execute(
        _ query: KernelQuery,
        on document: CADDocument,
        tolerance: ModelingTolerance = .standard
    ) throws -> KernelQueryResult {
        try tolerance.validate()
        try query.validate()
        guard tolerance == evaluator.evaluationTolerance else {
            throw KernelError(
                phase: .validation,
                code: .invalidInput,
                tolerance: tolerance,
                message: "Query tolerance must match the configured document evaluator tolerance."
            )
        }
        switch query {
        case .evaluatedDocument:
            return .evaluatedDocument(try evaluate(document))
        case let .lineage(subshapeID):
            let evaluated = try evaluate(document)
            return .lineage(evaluated.lineage[subshapeID])
        case .diagnostics:
            return .diagnostics(evaluator.evaluateReport(document))
        }
    }

    public func snapCandidates(
        near point: Point3D,
        in evaluatedDocument: EvaluatedDocument,
        options: SnapQueryOptions = SnapQueryOptions()
    ) throws -> SnapQueryResult {
        do {
            return try snapQueryEvaluator.candidates(near: point, in: evaluatedDocument, options: options)
        } catch {
            throw KernelError.wrapping(error, phase: .evaluation, tolerance: .standard)
        }
    }

    public func measurementPoint(
        for selection: SelectionReference,
        in evaluatedDocument: EvaluatedDocument
    ) throws -> SelectionMeasurementPoint {
        do {
            return try selectionMeasurementEvaluator.point(for: selection, in: evaluatedDocument)
        } catch {
            throw KernelError.wrapping(error, phase: .evaluation)
        }
    }

    public func distance(
        from first: SelectionReference,
        to second: SelectionReference,
        in evaluatedDocument: EvaluatedDocument
    ) throws -> SelectionDistanceMeasurement {
        do {
            return try selectionMeasurementEvaluator.distance(from: first, to: second, in: evaluatedDocument)
        } catch {
            throw KernelError.wrapping(error, phase: .evaluation)
        }
    }

    public func angle(
        between first: SelectionReference,
        and second: SelectionReference,
        in evaluatedDocument: EvaluatedDocument
    ) throws -> SelectionAngleMeasurement {
        do {
            return try selectionMeasurementEvaluator.angle(between: first, and: second, in: evaluatedDocument)
        } catch {
            throw KernelError.wrapping(error, phase: .evaluation)
        }
    }

    public func evaluateSelectionDimensions(
        in evaluatedDocument: EvaluatedDocument
    ) throws -> SelectionDimensionEvaluation {
        do {
            return try selectionDimensionEvaluator.evaluate(evaluatedDocument)
        } catch {
            throw KernelError.wrapping(error, phase: .evaluation)
        }
    }

    public func evaluateSelectionDimension(
        _ dimensionID: SelectionDimensionID,
        in evaluatedDocument: EvaluatedDocument
    ) throws -> SelectionDimensionEvaluation {
        guard let dimension = evaluatedDocument.document.selectionDimensions.first(where: { $0.id == dimensionID }) else {
            throw KernelError(
                phase: .evaluation,
                code: .missingReference,
                message: "Selection dimension ID could not be resolved."
            )
        }
        do {
            return SelectionDimensionEvaluation(measurements: [
                try selectionDimensionEvaluator.measure(dimension, in: evaluatedDocument)
            ])
        } catch {
            throw KernelError.wrapping(error, phase: .evaluation)
        }
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
        case let .measurement(measurement):
            return .measurement(try executeMeasurementQuery(measurement, in: evaluatedDocument))
        case let .selectionDimensionEvaluation(query):
            if let dimensionID = query.dimensionID {
                return .selectionDimensionEvaluation(try evaluateSelectionDimension(
                    dimensionID,
                    in: evaluatedDocument
                ))
            }
            return .selectionDimensionEvaluation(try evaluateSelectionDimensions(in: evaluatedDocument))
        }
    }

    private func executeMeasurementQuery(
        _ query: CADAgentMeasurementQuery,
        in evaluatedDocument: EvaluatedDocument
    ) throws -> CADAgentMeasurementQueryResult {
        try query.validate()
        switch query.kind {
        case .point:
            return .point(try measurementPoint(for: query.first, in: evaluatedDocument))
        case .distance:
            guard let second = query.second else {
                throw FeatureEvaluationError.invalidGraph(
                    "Distance measurement query requires a second selection."
                )
            }
            return .distance(try distance(from: query.first, to: second, in: evaluatedDocument))
        case .angle:
            guard let second = query.second else {
                throw FeatureEvaluationError.invalidGraph(
                    "Angle measurement query requires a second selection."
                )
            }
            return .angle(try angle(between: query.first, and: second, in: evaluatedDocument))
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
        var invalidatedFeatureIDs: [FeatureID] = []
        if hasAppliedStep {
            feature.operation = .sketch(sketchResult.sketch)
            try updatedDocument.replaceFeature(feature, tolerance: tolerance)
            invalidatedFeatureIDs = try updatedDocument.designGraph.invalidatedFeatureIDsInValidatedGraph(
                after: featureID
            )
        }

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
            meshes: evaluatedDocument.meshes.materializedDictionary(),
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
