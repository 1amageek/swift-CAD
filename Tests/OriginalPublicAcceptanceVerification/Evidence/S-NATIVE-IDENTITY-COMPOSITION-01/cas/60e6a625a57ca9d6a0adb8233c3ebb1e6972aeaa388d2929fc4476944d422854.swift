/// Original spatial coefficients retain their own field authority.
public protocol OriginalSpatialSourceReading: Sendable {
    associatedtype Child: Sendable
    associatedtype Coefficient: Sendable
    var originalChild: OriginalSourceBinding<Child> { get }
    func spatialCoefficient(row: Int, column: Int) -> Coefficient
}
