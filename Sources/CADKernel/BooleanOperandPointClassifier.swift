import CADCore
import CADGeometry
import CADIR
import CADTopology

/// Classifies points against a Boolean operand's material: a solid's volume or its complement
/// by the point-in-solid ray cast, a sheet's sides by the sheet-side ray cast, nothing for an
/// empty operand. Every classification of a Boolean pass goes through it, so the operand
/// Materials hold in every phase.
struct BooleanOperandPointClassifier: SolidPointClassifying, SolidPointClassificationSessionPreparing {
    private let solidity: [BodyID: BooleanOperandSolidity]
    private let solidClassifier: DefaultBRepSolidPointClassifier
    private let sheetClassifier: BRepSheetSidePointClassifier

    init(
        solidity: [BodyID: BooleanOperandSolidity],
        solidClassifier: DefaultBRepSolidPointClassifier = DefaultBRepSolidPointClassifier(),
        sheetClassifier: BRepSheetSidePointClassifier = BRepSheetSidePointClassifier()
    ) {
        self.solidity = solidity
        self.solidClassifier = solidClassifier
        self.sheetClassifier = sheetClassifier
    }

    /// The classifier of one pass's operands.
    init(targetBodyIDs: [BodyID], toolBodyID: BodyID, solidities: BooleanOperandSolidities) {
        var solidity = Dictionary(uniqueKeysWithValues: targetBodyIDs.map { ($0, solidities.target) })
        solidity[toolBodyID] = solidities.tool
        self.init(solidity: solidity)
    }

    func solidity(of bodyID: BodyID, tolerance: ModelingTolerance) throws -> BooleanOperandSolidity {
        guard let value = solidity[bodyID] else {
            throw KernelError(
                phase: .classification,
                code: .missingReference,
                tolerance: tolerance,
                message: "Boolean classification asked about a body that is not an operand of the pass."
            )
        }
        return value
    }

    func classify(_ point: Point3D, in bodyID: BodyID, model: BRepModel,
        tolerance: ModelingTolerance) throws -> SolidPointClassification {
        var execution = try OriginalQueryExecution.kernelOriginal()
        return try classify(point, in: bodyID, model: model, tolerance: tolerance, using: &execution)
    }

    func preparedClassificationSession(in bodyID: BodyID, model: BRepModel,
        tolerance: ModelingTolerance) throws -> (any SolidPointClassificationSession)? {
        var execution = try OriginalQueryExecution.kernelOriginal()
        return try makeClassificationSession(in: bodyID, model: model, tolerance: tolerance, using: &execution)
    }

    func classify(
        _ point: Point3D,
        in bodyID: BodyID,
        model: BRepModel,
        tolerance: ModelingTolerance
    ,
        using execution: inout OriginalQueryExecution
    ) throws -> SolidPointClassification {
        try makeClassificationSession(in: bodyID, model: model, tolerance: tolerance, using: &execution).classify(point, using: &execution)
    }

    func preparedClassificationSession(
        in bodyID: BodyID,
        model: BRepModel,
        tolerance: ModelingTolerance
    ,
        using execution: inout OriginalQueryExecution
    ) throws -> any SolidPointClassificationSession {
        try makeClassificationSession(in: bodyID, model: model, tolerance: tolerance, using: &execution)
    }

    func makeClassificationSession(
        in bodyID: BodyID,
        model: BRepModel,
        tolerance: ModelingTolerance
    ,
        using execution: inout OriginalQueryExecution
    ) throws -> any SolidPointClassificationSession {
        try execution.consumeWork(1)
        switch try solidity(of: bodyID, tolerance: tolerance) {
        case .volume:
            return try solidClassifier.makeClassificationSession(in: bodyID, model: model, tolerance: tolerance, using: &execution)
        case .complement:
            return Inverted(base: try solidClassifier.makeClassificationSession(in: bodyID, model: model, tolerance: tolerance, using: &execution))
        case .behindSheet:
            return try sheetClassifier.makeClassificationSession(in: bodyID, model: model, tolerance: tolerance, using: &execution)
        case .inFrontOfSheet:
            return Inverted(base: try sheetClassifier.makeClassificationSession(in: bodyID, model: model, tolerance: tolerance, using: &execution))
        case .none:
            return Empty()
        }
    }

    private struct Inverted: SolidPointClassificationSession {
        let base: any SolidPointClassificationSession

        func classify(_ point: Point3D) throws -> SolidPointClassification {
            switch try base.classify(point) {
            case .inside: .outside
            case .outside: .inside
            case .boundary: .boundary
            }
        }

        func classify(_ point: Point3D, using execution: inout OriginalQueryExecution)
            throws -> SolidPointClassification {
            switch try base.classify(point, using: &execution) {
            case .inside: .outside
            case .outside: .inside
            case .boundary: .boundary
            }
        }
    }

    /// An empty operand has no material anywhere.
    private struct Empty: SolidPointClassificationSession {
        func classify(_ point: Point3D) throws -> SolidPointClassification {
            try CurrentTaskCancellationChecker().checkCancellation()
            return .outside
        }
        func classify(_ point: Point3D, using execution: inout OriginalQueryExecution)
            throws -> SolidPointClassification {
            try execution.consumeWork(1)
            try execution.checkpoint()
            return .outside
        }
    }
}
