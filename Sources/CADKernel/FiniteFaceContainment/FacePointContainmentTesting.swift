import CADCore
import CADGeometry
import CADIR
import CADTopology

public protocol FacePointContainmentTesting: Sendable {
    func contains(
        _ point: Point3D,
        on faceID: FaceID,
        in model: BRepModel,
        tolerance: ModelingTolerance
    ) throws -> Bool

    /// Returns immutable preparation bound to the requested original faces, when supported.
    func preparedContainmentSession(
        for faceIDs: [FaceID],
        in model: BRepModel,
        tolerance: ModelingTolerance
    ) throws -> (any FacePointContainmentSession)?

    func preparedContainmentSession(for faceIDs: [FaceID], in model: BRepModel,
        tolerance: ModelingTolerance, maximumSubdivisionDepth: Int,
        consumeWork: @escaping @Sendable (Int) throws -> Void
    ) throws -> any FacePointContainmentSession

    func preparedContainmentSession(for faceIDs: [FaceID], in model: BRepModel,
        tolerance: ModelingTolerance, maximumSubdivisionDepth: Int,
        remainingSourceDepth: Int, maximumAlgebraicDepth: Int,
        consumeWork: @escaping @Sendable (Int) throws -> Void,
        consumeStorage: (@Sendable (Int) throws -> Void)?
    ) throws -> any FacePointContainmentSession
}

public extension FacePointContainmentTesting {
    func preparedContainmentSession(for faceIDs: [FaceID], in model: BRepModel,
        tolerance: ModelingTolerance, maximumSubdivisionDepth: Int,
        remainingSourceDepth: Int, maximumAlgebraicDepth: Int,
        consumeWork: @escaping @Sendable (Int) throws -> Void,
        consumeStorage: (@Sendable (Int) throws -> Void)?
    ) throws -> any FacePointContainmentSession {
        // FIXME(INCOMPLETE_IMPLEMENTATION): An injected provider must forward
        // independent original source/algebra limits and selected byte admission
        // through its actual finite-face preparation, not the legacy witness.
        throw KernelError(phase: .classification, code: .unsupportedCapability,
            tolerance: tolerance,
            message: "The injected finite-face provider lacks original source and byte admission.")
    }

    func preparedContainmentSession(for faceIDs: [FaceID], in model: BRepModel,
        tolerance: ModelingTolerance, maximumSubdivisionDepth: Int,
        consumeWork: @escaping @Sendable (Int) throws -> Void
    ) throws -> any FacePointContainmentSession {
        // FIXME(INCOMPLETE_IMPLEMENTATION): Legacy injected containment providers
        // lack same-ledger original preparation. Bounded callers require an actual
        // provider implementation instead of resetting its legacy allowance.
        throw KernelError(phase: .classification, code: .unsupportedCapability,
            tolerance: tolerance,
            message: "The injected containment provider does not expose bounded original preparation.")
    }

    func preparedContainmentSession(
        for faceIDs: [FaceID],
        in model: BRepModel,
        tolerance: ModelingTolerance
    ) throws -> (any FacePointContainmentSession)? { nil }
}

public protocol FacePointContainmentSession: Sendable {
    func contains(_ point: Point3D, on faceID: FaceID) throws -> Bool

    /// Nil indicates that this session provides only model-space containment.
    func containsParameter(_ parameter: SurfaceParameter, on faceID: FaceID) throws -> Bool?
}

public extension FacePointContainmentSession {
    func containsParameter(_ parameter: SurfaceParameter, on faceID: FaceID) throws -> Bool? { nil }
}

protocol FaceParameterContainmentSession: Sendable {
    func contains(_ parameter: SurfaceParameter, on faceID: FaceID) throws -> Bool
}

protocol FaceParameterContainmentSessionPreparing: Sendable {
    func makeParameterContainmentSession(
        for faceIDs: [FaceID],
        in model: BRepModel,
        tolerance: ModelingTolerance
    ) throws -> any FaceParameterContainmentSession
}

protocol FacePointContainmentSessionPreparing: Sendable {
    func makeContainmentSession(
        for faceIDs: [FaceID],
        in model: BRepModel,
        tolerance: ModelingTolerance
    ) throws -> any FacePointContainmentSession
}

protocol FacePointContainmentPreparationCaching: FacePointContainmentTesting {
    func contains(
        _ point: Point3D,
        on faceID: FaceID,
        in model: BRepModel,
        preparationCache: inout FacePointContainmentPreparationCache,
        tolerance: ModelingTolerance
    ) throws -> Bool
}

protocol FaceParameterContainmentPreparationCaching: Sendable {
    func contains(
        _ parameter: SurfaceParameter,
        on faceID: FaceID,
        in model: BRepModel,
        preparationCache: inout FacePointContainmentPreparationCache,
        tolerance: ModelingTolerance
    ) throws -> Bool
}
