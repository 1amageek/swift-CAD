/// The dimension of an independent Boolean operand or result root.
public enum BooleanTopologicalDimension: Int, Sendable, Hashable {
    case point = 0
    case curve = 1
    case surface = 2
    case volume = 3
}
