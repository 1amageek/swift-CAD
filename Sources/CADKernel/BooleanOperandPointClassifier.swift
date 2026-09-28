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

    func classify(
        _ point: Point3D,
        in bodyID: BodyID,
        model: BRepModel,
        tolerance: ModelingTolerance
    ) throws -> SolidPointClassification {
        try makeClassificationSession(in: bodyID, model: model, tolerance: tolerance).classify(point)
    }

    func makeClassificationSession(
        in bodyID: BodyID,
        model: BRepModel,
        tolerance: ModelingTolerance
    ) throws -> any SolidPointClassificationSession {
        switch try solidity(of: bodyID, tolerance: tolerance) {
        case .volume:
            return try solidClassifier.makeClassificationSession(in: bodyID, model: model, tolerance: tolerance)
        case .complement:
            return Inverted(base: try solidClassifier.makeClassificationSession(in: bodyID, model: model, tolerance: tolerance))
        case .behindSheet:
            return try sheetClassifier.makeClassificationSession(in: bodyID, model: model, tolerance: tolerance)
        case .inFrontOfSheet:
            return Inverted(base: try sheetClassifier.makeClassificationSession(in: bodyID, model: model, tolerance: tolerance))
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
    }

    /// An empty operand has no material anywhere.
    private struct Empty: SolidPointClassificationSession {
        func classify(_ point: Point3D) throws -> SolidPointClassification { .outside }
    }
}
