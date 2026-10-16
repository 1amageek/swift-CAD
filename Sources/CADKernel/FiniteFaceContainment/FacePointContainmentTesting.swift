import CADCore
import CADGeometry
import CADIR
import CADTopology

public protocol FacePointContainmentTesting: Sendable {
    func contains(_ point: Point3D, on faceID: FaceID, in model: BRepModel,
        tolerance: ModelingTolerance) throws -> Bool
    func contains(_ point: Point3D, on faceID: FaceID, in model: BRepModel,
        tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution) throws -> Bool
    func preparedContainmentSession(for faceIDs: [FaceID], in model: BRepModel,
        tolerance: ModelingTolerance) throws -> (any FacePointContainmentSession)?
    func preparedContainmentSession(for faceIDs: [FaceID], in model: BRepModel,
        tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution)
        throws -> any FacePointContainmentSession
}

public extension FacePointContainmentTesting {
    func preparedContainmentSession(for faceIDs: [FaceID], in model: BRepModel,
        tolerance: ModelingTolerance) throws -> (any FacePointContainmentSession)? { nil }
    // FIXME(INCOMPLETE_IMPLEMENTATION): Injected providers without an actual direct
    // source-owning implementation cannot participate in caller-admitted containment.
    func preparedContainmentSession(for faceIDs: [FaceID], in model: BRepModel,
        tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution)
        throws -> any FacePointContainmentSession {
        throw KernelError(phase: .classification, code: .unsupportedCapability, tolerance: tolerance,
            message: "The injected containment provider lacks direct original preparation.")
    }
    // FIXME(INCOMPLETE_IMPLEMENTATION): An injected provider must evaluate its
    // actual source under this execution before admitted containment can succeed.
    func contains(_ point: Point3D, on faceID: FaceID, in model: BRepModel,
        tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution) throws -> Bool {
        throw KernelError(phase: .classification, code: .unsupportedCapability, tolerance: tolerance,
            message: "The injected containment provider lacks direct original membership.")
    }
}

public protocol FacePointContainmentSession: Sendable {
    func contains(_ point: Point3D, on faceID: FaceID) throws -> Bool
    func contains(_ point: Point3D, on faceID: FaceID,
        using execution: inout OriginalQueryExecution) throws -> Bool
    func containsParameter(_ parameter: SurfaceParameter, on faceID: FaceID) throws -> Bool?
    func containsParameter(_ parameter: SurfaceParameter, on faceID: FaceID,
        using execution: inout OriginalQueryExecution) throws -> Bool?
}

public extension FacePointContainmentSession {
    func containsParameter(_ parameter: SurfaceParameter, on faceID: FaceID) throws -> Bool? { nil }
    // FIXME(INCOMPLETE_IMPLEMENTATION): An injected legacy session has no direct
    // source/proof admission. Its retained original membership must be implemented.
    func contains(_ point: Point3D, on faceID: FaceID,
        using execution: inout OriginalQueryExecution) throws -> Bool {
        throw KernelError(phase: .classification, code: .unsupportedCapability, tolerance: nil,
            message: "The injected containment session lacks direct original membership.")
    }
    func containsParameter(_ parameter: SurfaceParameter, on faceID: FaceID,
        using execution: inout OriginalQueryExecution) throws -> Bool? { nil }
}

protocol FaceParameterContainmentSession: Sendable {
    func contains(_ parameter: SurfaceParameter, on faceID: FaceID) throws -> Bool
    func contains(_ parameter: SurfaceParameter, on faceID: FaceID,
        using execution: inout OriginalQueryExecution) throws -> Bool
}
protocol FaceParameterContainmentSessionPreparing: Sendable {
    func makeParameterContainmentSession(for faceIDs: [FaceID], in model: BRepModel,
        tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution)
        throws -> any FaceParameterContainmentSession
}
protocol FacePointContainmentSessionPreparing: Sendable {
    func makeContainmentSession(for faceIDs: [FaceID], in model: BRepModel,
        tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution)
        throws -> any FacePointContainmentSession
}
protocol FacePointContainmentPreparationCaching: FacePointContainmentTesting {
    func contains(_ point: Point3D, on faceID: FaceID, in model: BRepModel,
        preparationCache: inout FacePointContainmentPreparationCache, tolerance: ModelingTolerance,
        using execution: inout OriginalQueryExecution) throws -> Bool
}
protocol FaceParameterContainmentPreparationCaching: Sendable {
    func contains(_ parameter: SurfaceParameter, on faceID: FaceID, in model: BRepModel,
        preparationCache: inout FacePointContainmentPreparationCache, tolerance: ModelingTolerance,
        using execution: inout OriginalQueryExecution) throws -> Bool
}
