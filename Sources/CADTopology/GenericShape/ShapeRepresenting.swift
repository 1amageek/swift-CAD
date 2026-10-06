/// The common input contract for every topological dimension and aggregate.
public protocol ShapeRepresenting: Sendable {
    /// Atomically captures a root and its model as one immutable owned value.
    /// Common operations acquire once; live providers own source synchronization.
    func shapeSnapshot() -> Shape
}
