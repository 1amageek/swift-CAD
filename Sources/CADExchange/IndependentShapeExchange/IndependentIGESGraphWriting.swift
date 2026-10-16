import CADGeometry
import Foundation
import CADCore
import CADIR

public protocol IndependentIGESGraphWriting: Sendable {
    func write(_ source: IndependentShapeSource, units: UnitSystem, tolerance: ModelingTolerance,
               producer: inout any IndependentIGESGeometryWriting, usage: IndependentShapeExchangeOwner, using execution: inout OriginalQueryExecution) throws -> Data
}
