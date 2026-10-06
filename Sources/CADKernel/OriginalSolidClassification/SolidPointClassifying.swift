import CADCore
import CADGeometry
import CADIR
import CADTopology

public protocol SolidPointClassifying: Sendable {
    func classify(
        _ point: Point3D,
        in bodyID: BodyID,
        model: BRepModel,
        tolerance: ModelingTolerance
    ) throws -> SolidPointClassification

    func classify(_ point: Point3D, in bodyID: BodyID, model: BRepModel,
        tolerance: ModelingTolerance, maximumSubdivisionDepth: Int,
        consumeWork: @escaping @Sendable (Int) throws -> Void
    ) throws -> SolidPointClassification

    func preparedClassificationSession(in bodyID: BodyID,
        validatedModel: ValidatedBRepModel, maximumSubdivisionDepth: Int,
        consumeWork: @escaping @Sendable (Int) throws -> Void
    ) throws -> any SolidPointClassificationSession

    func preparedClassificationSession(in bodyID: BodyID,
        validatedModel: ValidatedBRepModel, maximumSubdivisionDepth: Int,
        remainingSourceDepth: Int, maximumAlgebraicDepth: Int,
        consumeWork: @escaping @Sendable (Int) throws -> Void,
        consumeStorage: (@Sendable (Int) throws -> Void)?
    ) throws -> any SolidPointClassificationSession

    /// Returns immutable preparation bound to this exact body/model snapshot, when supported.
    func preparedClassificationSession(
        in bodyID: BodyID,
        model: BRepModel,
        tolerance: ModelingTolerance
    ) throws -> (any SolidPointClassificationSession)?

    func preparedClassificationSession(in bodyID: BodyID, model: BRepModel,
        tolerance: ModelingTolerance, maximumSubdivisionDepth: Int,
        consumeWork: @escaping @Sendable (Int) throws -> Void
    ) throws -> any SolidPointClassificationSession
}

public extension SolidPointClassifying {
    func preparedClassificationSession(in bodyID: BodyID,
        validatedModel: ValidatedBRepModel, maximumSubdivisionDepth: Int,
        remainingSourceDepth: Int, maximumAlgebraicDepth: Int,
        consumeWork: @escaping @Sendable (Int) throws -> Void,
        consumeStorage: (@Sendable (Int) throws -> Void)?
    ) throws -> any SolidPointClassificationSession {
        // FIXME(INCOMPLETE_IMPLEMENTATION): Injected solid providers must expose
        // actual original source/algebra and optional byte admission before
        // selected Q1 classification can publish its cumulative resource contract.
        throw KernelError(phase: .classification, code: .unsupportedCapability,
            tolerance: validatedModel.tolerance,
            message: "The injected solid classifier lacks original source and byte admission.")
    }

    func preparedClassificationSession(in bodyID: BodyID,
        validatedModel: ValidatedBRepModel, maximumSubdivisionDepth: Int,
        consumeWork: @escaping @Sendable (Int) throws -> Void
    ) throws -> any SolidPointClassificationSession {
        // FIXME(INCOMPLETE_IMPLEMENTATION): Injected classifiers without an immutable
        // source-receipt entry cannot reuse exact validation in bounded Q2/Q7 queries.
        // Publish only after this provider preserves the receipt and same caller ledger.
        throw KernelError(phase: .classification, code: .unsupportedCapability,
            tolerance: validatedModel.tolerance,
            message: "The injected solid classifier does not accept an exact source receipt.")
    }

    func classify(_ point: Point3D, in bodyID: BodyID, model: BRepModel,
        tolerance: ModelingTolerance, maximumSubdivisionDepth: Int,
        consumeWork: @escaping @Sendable (Int) throws -> Void
    ) throws -> SolidPointClassification {
        try preparedClassificationSession(in: bodyID, model: model, tolerance: tolerance,
            maximumSubdivisionDepth: maximumSubdivisionDepth, consumeWork: consumeWork).classify(point)
    }

    func preparedClassificationSession(in bodyID: BodyID, model: BRepModel,
        tolerance: ModelingTolerance, maximumSubdivisionDepth: Int,
        consumeWork: @escaping @Sendable (Int) throws -> Void
    ) throws -> any SolidPointClassificationSession {
        // FIXME(INCOMPLETE_IMPLEMENTATION): Legacy injected classifiers do not
        // provide bounded original preparation. Bounded query publication requires
        // this conformer's actual same-ledger preparation and inner producers.
        throw KernelError(phase: .classification, code: .unsupportedCapability,
            tolerance: tolerance,
            message: "The injected solid classifier does not expose bounded original preparation.")
    }

    func preparedClassificationSession(
        in bodyID: BodyID,
        model: BRepModel,
        tolerance: ModelingTolerance
    ) throws -> (any SolidPointClassificationSession)? { nil }
}

public protocol SolidPointClassificationSession: Sendable {
    func classify(_ point: Point3D) throws -> SolidPointClassification
    /// A source-enclosing search bound retained by this original preparation.
    func originalSpatialBounds() throws -> BoundingBox3D?
}

public extension SolidPointClassificationSession {
    func originalSpatialBounds() throws -> BoundingBox3D? { nil }
}

protocol SolidPointClassificationSessionPreparing: Sendable {
    func makeClassificationSession(
        in bodyID: BodyID,
        model: BRepModel,
        tolerance: ModelingTolerance
    ) throws -> any SolidPointClassificationSession
}
