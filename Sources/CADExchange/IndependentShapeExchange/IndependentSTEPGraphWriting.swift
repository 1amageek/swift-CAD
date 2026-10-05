import Foundation
import CADCore
import CADIR

public protocol IndependentSTEPGraphWriting: Sendable {
    /// Authors every original association into the supplied producer; publication remains with the parent.
    func append<Producer: IndependentSTEPGeometryWriting>(_ source: IndependentShapeSource,
               standaloneUnits: UnitSystem, tolerance: ModelingTolerance, productDefinitions: [AssemblyDefinitionID: Int], bodyBindings: [SubshapeID: IndependentSTEPBodyBinding], bodySourceGraph: DesignGraph?,
               producer: inout Producer, usage: inout IndependentShapeExchangeUsage) throws
    func write(_ source: IndependentShapeSource, standaloneUnits: UnitSystem, tolerance: ModelingTolerance,
               producer: inout any IndependentSTEPGeometryWriting,
               usage: inout IndependentShapeExchangeUsage) throws -> Data
}
