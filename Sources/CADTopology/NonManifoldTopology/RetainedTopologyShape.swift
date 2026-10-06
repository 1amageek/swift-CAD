/// An immutable raw snapshot. Retention grants no permission to model.
public struct RetainedTopologyShape: Sendable, Equatable {
    let snapshot: Shape

    public var root: ShapeReference { snapshot.root }
    public var model: BRepModel { snapshot.model }
}
