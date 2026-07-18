import Foundation
import CADCore
import CADIR
import CADModeling
import CADKernel
import CADExchange

public struct CADPipeline: Sendable {
    private let evaluator: DocumentEvaluator
    private let snapQueryEvaluator: SnapQueryEvaluator
    private let curveQueryEvaluator: CurveQueryEvaluator
    private let edgeQueryEvaluator: EdgeQueryEvaluator
    private let surfaceQueryEvaluator: SurfaceQueryEvaluator
    private let selectionMeasurementEvaluator: SelectionMeasurementEvaluator
    private let selectionDimensionEvaluator: SelectionDimensionEvaluator
    private let stlExporter: STLExporter
    private let packageStore: NativePackageStore
    private let officialExchange: OfficialFormatExchange
    private let documentEditor: any DocumentEditing
    private let capabilityCatalog: KernelCapabilityCatalog

    public init(
        tolerance: ModelingTolerance,
        evaluator: DocumentEvaluator? = nil,
        snapQueryEvaluator: SnapQueryEvaluator? = nil,
        curveQueryEvaluator: CurveQueryEvaluator? = nil,
        edgeQueryEvaluator: EdgeQueryEvaluator? = nil,
        surfaceQueryEvaluator: SurfaceQueryEvaluator? = nil,
        selectionMeasurementEvaluator: SelectionMeasurementEvaluator? = nil,
        selectionDimensionEvaluator: SelectionDimensionEvaluator? = nil,
        stlExporter: STLExporter? = nil,
        packageStore: NativePackageStore? = nil,
        officialExchange: OfficialFormatExchange? = nil,
        documentEditor: any DocumentEditing = DocumentEditor(),
        capabilityCatalog: KernelCapabilityCatalog = KernelCapabilities.current
    ) {
        self.evaluator = evaluator ?? DocumentEvaluator(tolerance: tolerance)
        self.snapQueryEvaluator = snapQueryEvaluator ?? SnapQueryEvaluator(tolerance: tolerance)
        self.curveQueryEvaluator = curveQueryEvaluator ?? CurveQueryEvaluator(tolerance: tolerance)
        self.edgeQueryEvaluator = edgeQueryEvaluator ?? EdgeQueryEvaluator(tolerance: tolerance)
        self.surfaceQueryEvaluator = surfaceQueryEvaluator ?? SurfaceQueryEvaluator(tolerance: tolerance)
        self.selectionMeasurementEvaluator = selectionMeasurementEvaluator
            ?? SelectionMeasurementEvaluator(tolerance: tolerance)
        self.selectionDimensionEvaluator = selectionDimensionEvaluator
            ?? SelectionDimensionEvaluator(tolerance: tolerance)
        self.stlExporter = stlExporter ?? STLExporter(tolerance: tolerance)
        self.packageStore = packageStore ?? NativePackageStore(tolerance: tolerance)
        self.officialExchange = officialExchange ?? OfficialFormatExchange(tolerance: tolerance)
        self.documentEditor = documentEditor
        self.capabilityCatalog = capabilityCatalog
    }

    public func capabilities() -> KernelCapabilityCatalog {
        capabilityCatalog
    }

    public func apply(
        _ command: CADCommand,
        to document: CADDocument
    ) throws -> CADDocument {
        try documentEditor.apply(
            command,
            to: document,
            tolerance: evaluator.evaluationTolerance
        )
    }

    public func evaluate(_ document: CADDocument) throws -> EvaluatedDocument {
        do {
            return try evaluator.evaluate(document)
        } catch {
            throw KernelError.wrapping(
                error,
                phase: .evaluation,
                tolerance: evaluator.evaluationTolerance
            )
        }
    }

    public func execute(
        _ query: KernelQuery,
        on document: CADDocument
    ) throws -> KernelQueryResult {
        do {
            try query.validate(tolerance: evaluator.evaluationTolerance)
        } catch {
            throw KernelError.wrapping(
                error,
                phase: .validation,
                tolerance: evaluator.evaluationTolerance
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
        case let .snap(query):
            let evaluated = try evaluate(document)
            return .snap(try snapCandidates(
                near: query.point,
                in: evaluated,
                options: query.options
            ))
        case let .measurement(query):
            return .measurement(try executeMeasurementQuery(
                query,
                in: evaluate(document)
            ))
        case let .selectionDimensionEvaluation(query):
            let evaluated = try evaluate(document)
            if let dimensionID = query.dimensionID {
                return .selectionDimensionEvaluation(try evaluateSelectionDimension(
                    dimensionID,
                    in: evaluated
                ))
            }
            return .selectionDimensionEvaluation(try evaluateSelectionDimensions(
                in: evaluated
            ))
        case let .projection(query):
            return .projection(try executeProjectionQuery(
                query,
                in: evaluate(document)
            ))
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
            throw KernelError.wrapping(
                error,
                phase: .evaluation,
                tolerance: evaluator.evaluationTolerance
            )
        }
    }

    public func measurementPoint(
        for selection: SelectionReference,
        in evaluatedDocument: EvaluatedDocument
    ) throws -> SelectionMeasurementPoint {
        do {
            return try selectionMeasurementEvaluator.point(for: selection, in: evaluatedDocument)
        } catch {
            throw KernelError.wrapping(
                error,
                phase: .evaluation,
                tolerance: evaluator.evaluationTolerance
            )
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
            throw KernelError.wrapping(
                error,
                phase: .evaluation,
                tolerance: evaluator.evaluationTolerance
            )
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
            throw KernelError.wrapping(
                error,
                phase: .evaluation,
                tolerance: evaluator.evaluationTolerance
            )
        }
    }

    public func evaluateSelectionDimensions(
        in evaluatedDocument: EvaluatedDocument
    ) throws -> SelectionDimensionEvaluation {
        do {
            return try selectionDimensionEvaluator.evaluate(evaluatedDocument)
        } catch {
            throw KernelError.wrapping(
                error,
                phase: .evaluation,
                tolerance: evaluator.evaluationTolerance
            )
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
                tolerance: evaluator.evaluationTolerance,
                message: "Selection dimension ID could not be resolved."
            )
        }
        do {
            return SelectionDimensionEvaluation(measurements: [
                try selectionDimensionEvaluator.measure(dimension, in: evaluatedDocument)
            ])
        } catch {
            throw KernelError.wrapping(
                error,
                phase: .evaluation,
                tolerance: evaluator.evaluationTolerance
            )
        }
    }

    private func executeMeasurementQuery(
        _ query: MeasurementQuery,
        in evaluatedDocument: EvaluatedDocument
    ) throws -> MeasurementQueryResult {
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

    private func executeProjectionQuery(
        _ query: ProjectionQuery,
        in evaluatedDocument: EvaluatedDocument
    ) throws -> ProjectionQueryResult {
        switch (query.target, query.mode) {
        case let (.curve(reference), .closest):
            return .curveClosest(try curveQueryEvaluator.closestPoint(
                to: query.point,
                on: reference,
                in: evaluatedDocument,
                options: CurveProjectionOptions(
                    sampleCount: query.sampleCount,
                    maximumIterations: query.maximumIterations
                )
            ))
        case let (.curve(reference), .directional(direction, range)):
            return .curveDirectional(try curveQueryEvaluator.project(
                query.point,
                along: direction,
                onto: reference,
                in: evaluatedDocument,
                options: CurveDirectionalProjectionOptions(
                    sampleCount: query.sampleCount,
                    maximumIterations: query.maximumIterations,
                    range: curveProjectionRange(range)
                )
            ))
        case let (.edge(reference), .closest):
            return .edgeClosest(try edgeQueryEvaluator.closestPoint(
                to: query.point,
                on: reference,
                in: evaluatedDocument,
                options: EdgeProjectionOptions(
                    sampleCount: query.sampleCount,
                    maximumIterations: query.maximumIterations
                )
            ))
        case let (.edge(reference), .directional(direction, range)):
            return .edgeDirectional(try edgeQueryEvaluator.project(
                query.point,
                along: direction,
                onto: reference,
                in: evaluatedDocument,
                options: EdgeDirectionalProjectionOptions(
                    sampleCount: query.sampleCount,
                    maximumIterations: query.maximumIterations,
                    range: edgeProjectionRange(range)
                )
            ))
        case let (.surface(reference), .closest):
            return .surfaceClosest(try surfaceQueryEvaluator.closestPoint(
                to: query.point,
                on: reference,
                in: evaluatedDocument,
                options: SurfaceProjectionOptions(
                    sampleCount: query.sampleCount,
                    maximumIterations: query.maximumIterations
                )
            ))
        case let (.surface(reference), .directional(direction, range)):
            return .surfaceDirectional(try surfaceQueryEvaluator.project(
                query.point,
                along: direction,
                onto: reference,
                in: evaluatedDocument,
                options: SurfaceDirectionalProjectionOptions(
                    sampleCount: query.sampleCount,
                    maximumIterations: query.maximumIterations,
                    range: surfaceProjectionRange(range)
                )
            ))
        }
    }

    private func curveProjectionRange(
        _ range: ProjectionQuery.DirectionRange
    ) -> CurveDirectionalProjectionRange {
        switch range {
        case .line: .line
        case .ray: .ray
        }
    }

    private func edgeProjectionRange(
        _ range: ProjectionQuery.DirectionRange
    ) -> EdgeDirectionalProjectionRange {
        switch range {
        case .line: .line
        case .ray: .ray
        }
    }

    private func surfaceProjectionRange(
        _ range: ProjectionQuery.DirectionRange
    ) -> SurfaceDirectionalProjectionRange {
        switch range {
        case .line: .line
        case .ray: .ray
        }
    }

    public func solveSketchConstraints(
        in document: CADDocument,
        featureID: FeatureID
    ) throws -> CADDocumentSketchConstraintSolveResult {
        let tolerance = evaluator.evaluationTolerance
        try document.validate(tolerance: tolerance)
        guard var feature = document.designGraph.nodes[featureID] else {
            throw KernelError(
                phase: .validation,
                code: .missingReference,
                featureID: featureID,
                tolerance: tolerance,
                message: "Sketch constraint solve target feature is missing."
            )
        }
        guard case let .sketch(sketch) = feature.operation else {
            throw KernelError(
                phase: .validation,
                code: .invalidInput,
                featureID: featureID,
                tolerance: tolerance,
                message: "Sketch constraint solve requires a sketch feature."
            )
        }

        let parameters = try ParameterResolver().resolve(document.parameters)
        let constraintResult = try LevenbergMarquardtSketchConstraintSolver().solve(
            sketch,
            parameters: parameters,
            tolerance: tolerance
        )
        switch constraintResult.status {
        case .conflicting:
            throw KernelError(
                phase: .evaluation,
                code: .conflictingConstraints,
                featureID: featureID,
                residual: constraintResult.maximumNormalizedResidual,
                tolerance: tolerance,
                message: "Sketch constraints could not be satisfied simultaneously."
            )
        case .singular:
            throw KernelError(
                phase: .evaluation,
                code: .singularSystem,
                featureID: featureID,
                residual: constraintResult.maximumNormalizedResidual,
                tolerance: tolerance,
                message: "Sketch constraint Jacobian is singular."
            )
        case .fullyConstrained, .underConstrained, .overConstrained:
            break
        }

        var updatedDocument = document
        var invalidatedFeatureIDs: [FeatureID] = []
        if constraintResult.sketch != sketch {
            feature.operation = .sketch(constraintResult.sketch)
            try updatedDocument.replaceFeature(feature, tolerance: tolerance)
            invalidatedFeatureIDs = try updatedDocument.designGraph.invalidatedFeatureIDsInValidatedGraph(
                after: featureID
            )
        }

        return CADDocumentSketchConstraintSolveResult(
            document: updatedDocument,
            featureID: featureID,
            invalidatedFeatureIDs: invalidatedFeatureIDs,
            constraintResult: constraintResult
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
