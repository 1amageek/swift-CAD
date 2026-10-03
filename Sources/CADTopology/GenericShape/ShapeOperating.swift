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
}
