import CADGeometry
import CADCore
import CADIR

public protocol IndependentIGESGraphReading: Sendable {
    func read(entityPointers: [Int], standaloneItemPointers: [Int], fields: any IndependentIGESFieldReading,
              units: UnitSystem, tolerance: ModelingTolerance, producer: inout any IndependentIGESGeometryReading,
              usage: IndependentShapeExchangeOwner, using execution: inout OriginalQueryExecution) throws -> IndependentShapeSource?
}
