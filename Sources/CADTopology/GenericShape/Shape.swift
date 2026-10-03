/// An immutable selection and its owned value snapshot.
///
/// Construction does not imply validity. Common operations validate the selected
/// closure and report malformed inputs before returning a result.
public struct Shape: ShapeRepresenting, Equatable, Sendable {
    public let root: ShapeReference
    public let model: BRepModel

    public init(root: ShapeReference, model: BRepModel) {
        self.root = root
        self.model = model
    }

    public func shapeSnapshot() -> Shape {
        self
    }
}
