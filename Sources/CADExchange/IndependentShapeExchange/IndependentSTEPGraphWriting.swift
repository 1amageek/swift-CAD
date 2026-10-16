import CADGeometry
import Foundation
import CADCore
import CADIR

public protocol IndependentSTEPGraphWriting: Sendable {
    /// Authors every original association into the supplied producer; publication remains with the parent.
    func append<Producer: IndependentSTEPGeometryWriting>(_ source: IndependentShapeSource,
               standaloneUnits: UnitSystem, tolerance: ModelingTolerance, productDefinitions: [AssemblyDefinitionID: Int], bodyBindings: [SubshapeID: IndependentSTEPBodyBinding], bodySourceGraph: DesignGraph?,
               producer: inout Producer, usage: IndependentShapeExchangeOwner, using execution: inout OriginalQueryExecution) throws
    func write(_ source: IndependentShapeSource, standaloneUnits: UnitSystem, tolerance: ModelingTolerance,
               producer: inout any IndependentSTEPGeometryWriting,
               usage: IndependentShapeExchangeOwner, using execution: inout OriginalQueryExecution) throws -> Data
}
