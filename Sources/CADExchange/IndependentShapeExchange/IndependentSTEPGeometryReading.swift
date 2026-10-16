import CADCore
import CADGeometry
import CADTopology
import CADIR

/// Parent-owned primitive decoding without a manufactured topological body.
public protocol IndependentSTEPGeometryReading: Sendable {
    mutating func curve(entityID: Int, units: UnitSystem, originalAngularSource: IndependentShapeAngularSource?, originalLengthSource: OriginalSTEPLengthSource?, tolerance: ModelingTolerance,
                        usage: IndependentShapeExchangeOwner, using execution: inout OriginalQueryExecution) throws -> IndependentExchangeReadCurve
    mutating func surface(entityID: Int, units: UnitSystem, originalAngularSource: IndependentShapeAngularSource?, originalLengthSource: OriginalSTEPLengthSource?, tolerance: ModelingTolerance,
                          usage: IndependentShapeExchangeOwner, using execution: inout OriginalQueryExecution) throws -> IndependentExchangeReadSurface
    mutating func contextLengthSource(entityID: Int, usage: IndependentShapeExchangeOwner, using execution: inout OriginalQueryExecution) throws -> OriginalSTEPLengthSource
    mutating func contextAngularSource(entityID: Int, usage: IndependentShapeExchangeOwner, using execution: inout OriginalQueryExecution) throws -> IndependentShapeAngularSource
    mutating func contextUnits(entityID: Int, usage: IndependentShapeExchangeOwner, using execution: inout OriginalQueryExecution) throws -> UnitSystem
    mutating func mappingSource(entityID: Int, units: UnitSystem, originalLengthSource: OriginalSTEPLengthSource?,
                                usage: IndependentShapeExchangeOwner, using execution: inout OriginalQueryExecution) throws -> OriginalSTEPPlacementSource
    mutating func mappingOrigin(entityID: Int, units: UnitSystem, usage: IndependentShapeExchangeOwner, using execution: inout OriginalQueryExecution) throws -> AffineTransform3D
    mutating func mappingTarget(entityID: Int, units: UnitSystem, usage: IndependentShapeExchangeOwner, using execution: inout OriginalQueryExecution) throws -> AffineTransform3D
}
