import CADCore
import CADGeometry

public protocol ShapeOperating: Sendable {
    func validate(_ shape: any ShapeRepresenting, tolerance: ModelingTolerance) throws
    func extract(_ shape: any ShapeRepresenting, tolerance: ModelingTolerance) throws -> Shape
    /// Returns distinct dimensional subshapes, ordered by dimension and stable ID.
    /// Compound containers are flattened; explicit wires retain their selection order.
    func subshapes(of shape: any ShapeRepresenting, tolerance: ModelingTolerance) throws -> [ShapeReference]
    func transformed(
        _ shape: any ShapeRepresenting,
        by transform: RigidTransform3D,
        tolerance: ModelingTolerance
    ) throws -> Shape
    /// Builds an ordered original affine model image; the caller validates its output.
    func transformed(
        validatedModel: ValidatedBRepModel,
        by transforms: [AffineTransform3D],
        maximumSubdivisionDepth: Int,
        remainingSourceDepth: Int,
        consumeWork: @escaping @Sendable (Int) throws -> Void
    ) throws -> BRepModel

    /// Retains a flat exact forward/inverse word and unchanged native UV topology.
    func transformed(
        validatedModel: ValidatedBRepModel,
        by operationWord: OriginalAffineOperationWord,
        maximumSubdivisionDepth: Int,
        remainingSourceDepth: Int,
        consumeWork: @escaping @Sendable (Int) throws -> Void,
        consumeStorage: (@Sendable (Int) throws -> Void)?
    ) throws -> BRepModel

}
