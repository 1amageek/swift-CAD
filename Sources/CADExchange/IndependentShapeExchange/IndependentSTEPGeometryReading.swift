import CADCore
import CADGeometry
import CADTopology
import CADIR

/// Parent-owned primitive decoding without a manufactured topological body.
public protocol IndependentSTEPGeometryReading: Sendable {
    mutating func curve(entityID: Int, units: UnitSystem, originalAngularSource: IndependentShapeAngularSource?, originalLengthSource: OriginalSTEPLengthSource?, tolerance: ModelingTolerance,
                        usage: inout IndependentShapeExchangeUsage) throws -> IndependentExchangeReadCurve
    mutating func surface(entityID: Int, units: UnitSystem, originalAngularSource: IndependentShapeAngularSource?, originalLengthSource: OriginalSTEPLengthSource?, tolerance: ModelingTolerance,
                          usage: inout IndependentShapeExchangeUsage) throws -> IndependentExchangeReadSurface
    mutating func contextLengthSource(entityID: Int, usage: inout IndependentShapeExchangeUsage) throws -> OriginalSTEPLengthSource
    mutating func contextAngularSource(entityID: Int, usage: inout IndependentShapeExchangeUsage) throws -> IndependentShapeAngularSource
    mutating func contextUnits(entityID: Int, usage: inout IndependentShapeExchangeUsage) throws -> UnitSystem
    mutating func mappingSource(entityID: Int, units: UnitSystem, originalLengthSource: OriginalSTEPLengthSource?,
                                usage: inout IndependentShapeExchangeUsage) throws -> OriginalSTEPPlacementSource
    mutating func mappingOrigin(entityID: Int, units: UnitSystem, usage: inout IndependentShapeExchangeUsage) throws -> AffineTransform3D
    mutating func mappingTarget(entityID: Int, units: UnitSystem, usage: inout IndependentShapeExchangeUsage) throws -> AffineTransform3D
}
