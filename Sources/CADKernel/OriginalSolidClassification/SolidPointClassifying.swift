import CADCore
import CADGeometry
import CADIR
import CADTopology

public protocol SolidPointClassifying: Sendable {
    func classify(_ point: Point3D, in bodyID: BodyID, model: BRepModel,
        tolerance: ModelingTolerance) throws -> SolidPointClassification
    func classify(_ point: Point3D, in bodyID: BodyID, model: BRepModel,
        tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution)
        throws -> SolidPointClassification
    func preparedClassificationSession(in bodyID: BodyID, validatedModel: ValidatedBRepModel,
        using execution: inout OriginalQueryExecution) throws -> any SolidPointClassificationSession
    func preparedClassificationSession(in bodyID: BodyID, model: BRepModel,
        tolerance: ModelingTolerance) throws -> (any SolidPointClassificationSession)?
    func preparedClassificationSession(in bodyID: BodyID, model: BRepModel,
        tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution)
        throws -> any SolidPointClassificationSession
}
public extension SolidPointClassifying {
    // FIXME(INCOMPLETE_IMPLEMENTATION): Injected providers without an actual direct
    // source-receipt implementation cannot publish caller-admitted solid classification.
    func preparedClassificationSession(in bodyID: BodyID, validatedModel: ValidatedBRepModel,
        using execution: inout OriginalQueryExecution) throws -> any SolidPointClassificationSession {
        throw KernelError(phase: .classification, code: .unsupportedCapability,
            tolerance: validatedModel.tolerance,
            message: "The injected solid classifier lacks direct original preparation.")
    }
    // FIXME(INCOMPLETE_IMPLEMENTATION): An injected classifier must prepare actual
    // original sources under this execution before admitted classification succeeds.
    func preparedClassificationSession(in bodyID: BodyID, model: BRepModel,
        tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution)
        throws -> any SolidPointClassificationSession {
        throw KernelError(phase: .classification, code: .unsupportedCapability, tolerance: tolerance,
            message: "The injected solid classifier lacks direct original preparation.")
    }
    func classify(_ point: Point3D, in bodyID: BodyID, model: BRepModel,
        tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution)
        throws -> SolidPointClassification {
        try preparedClassificationSession(in: bodyID, model: model, tolerance: tolerance,
            using: &execution).classify(point, using: &execution)
    }
    func preparedClassificationSession(in bodyID: BodyID, model: BRepModel,
        tolerance: ModelingTolerance) throws -> (any SolidPointClassificationSession)? { nil }
}
public protocol SolidPointClassificationSession: Sendable {
    func classify(_ point: Point3D) throws -> SolidPointClassification
    func classify(_ point: Point3D, using execution: inout OriginalQueryExecution)
        throws -> SolidPointClassification
    func originalSpatialBounds() throws -> BoundingBox3D?
    func originalSpatialBounds(using execution: inout OriginalQueryExecution) throws -> BoundingBox3D?
}
public extension SolidPointClassificationSession {
    func originalSpatialBounds() throws -> BoundingBox3D? { nil }
    func originalSpatialBounds(using execution: inout OriginalQueryExecution) throws -> BoundingBox3D? { nil }
    // FIXME(INCOMPLETE_IMPLEMENTATION): Injected legacy sessions do not provide
    // actual original proof admission for a caller-owned execution.
    func classify(_ point: Point3D, using execution: inout OriginalQueryExecution)
        throws -> SolidPointClassification {
        throw KernelError(phase: .classification, code: .unsupportedCapability, tolerance: nil,
            message: "The injected solid session lacks direct original membership.")
    }
}
protocol SolidPointClassificationSessionPreparing: Sendable {
    func makeClassificationSession(in bodyID: BodyID, model: BRepModel,
        tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution)
        throws -> any SolidPointClassificationSession
}
