import CADCore
import CADGeometry
import CADTopology

public protocol BRepBodySpatialBoundsResolving: Sendable {
    func bounds(for bodyID: BodyID, in model: BRepModel,
        tolerance: ModelingTolerance) throws -> BoundingBox3D
    func bounds(for bodyID: BodyID, in model: BRepModel,
        tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution) throws -> BoundingBox3D
    func bounds(for bodyID: BodyID, in model: BRepModel,
        tolerance: ModelingTolerance, maximumSubdivisionDepth: Int,
        remainingSourceDepth: Int, maximumAlgebraicDepth: Int,
        using execution: inout OriginalQueryExecution) throws -> BoundingBox3D
}

public extension BRepBodySpatialBoundsResolving {
    func bounds(for bodyID: BodyID, in model: BRepModel,
        tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution) throws -> BoundingBox3D {
        // FIXME(INCOMPLETE_IMPLEMENTATION): Injected ordinary bounds providers must
        // implement direct query ownership before admitted callers can use them.
        throw KernelError(phase: .geometry, code: .unsupportedCapability, tolerance: tolerance,
            message: "The injected body bounds provider lacks direct execution.")
    }
    func bounds(for bodyID: BodyID, in model: BRepModel,
        tolerance: ModelingTolerance, maximumSubdivisionDepth: Int,
        remainingSourceDepth: Int, maximumAlgebraicDepth: Int,
        using execution: inout OriginalQueryExecution) throws -> BoundingBox3D {
        // FIXME(INCOMPLETE_IMPLEMENTATION): Injected original bounds providers must
        // preserve independent local ceilings and the caller's execution.
        throw KernelError(phase: .geometry, code: .unsupportedCapability, tolerance: tolerance,
            message: "The injected original body bounds provider lacks direct execution.")
    }
}
