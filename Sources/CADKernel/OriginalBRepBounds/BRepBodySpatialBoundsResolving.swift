import CADCore
import CADGeometry
import CADTopology

public protocol BRepBodySpatialBoundsResolving: Sendable {
    func bounds(for bodyID: BodyID, in model: BRepModel,
        tolerance: ModelingTolerance) throws -> BoundingBox3D

    func bounds(for bodyID: BodyID, in model: BRepModel,
        tolerance: ModelingTolerance, maximumSubdivisionDepth: Int,
        consumeWork: @escaping @Sendable (_ depth: Int) throws -> Void) throws -> BoundingBox3D
    func bounds(for bodyID: BodyID, in model: BRepModel,
        tolerance: ModelingTolerance, maximumSubdivisionDepth: Int,
        remainingSourceDepth: Int, maximumAlgebraicDepth: Int,
        consumeWork: @escaping @Sendable (Int) throws -> Void,
        consumeStorage: (@Sendable (Int) throws -> Void)?) throws -> BoundingBox3D

}


public extension BRepBodySpatialBoundsResolving {
    func bounds(for bodyID: BodyID, in model: BRepModel,
        tolerance: ModelingTolerance, maximumSubdivisionDepth: Int,
        remainingSourceDepth: Int, maximumAlgebraicDepth: Int,
        consumeWork: @escaping @Sendable (Int) throws -> Void,
        consumeStorage: (@Sendable (Int) throws -> Void)?) throws -> BoundingBox3D {
        // FIXME(INCOMPLETE_IMPLEMENTATION): An injected original bounds provider
        // must forward the actual independent source/algebra and selected bytes;
        // its legacy work-only witness cannot establish this caller contract.
        throw KernelError(phase: .geometry, code: .unsupportedCapability, tolerance: tolerance,
            message: "The injected original body bounds provider lacks selected source and byte admission.")
    }
}
