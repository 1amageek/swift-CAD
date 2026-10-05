import Foundation
import CADCore
import CADGeometry
import CADIR

/// Parent-owned shared primitive/entity producer; each operation charges the supplied ledger.
public protocol IndependentSTEPGeometryWriting: Sendable {
    mutating func standaloneUnits(_ units: UnitSystem, originalAngularSource: IndependentShapeAngularSource?, originalLengthSource: OriginalSTEPLengthSource?, usage: inout IndependentShapeExchangeUsage) throws -> Int
    mutating func context(_ context: IndependentShapeContext, usage: inout IndependentShapeExchangeUsage) throws -> Int
    mutating func curve(_ item: IndependentShapeItem, source: IndependentShapeSource, units: UnitSystem, originalAngularSource: IndependentShapeAngularSource?, originalLengthSource: OriginalSTEPLengthSource?, positionEntityID: Int?,
                        usage: inout IndependentShapeExchangeUsage) throws -> Int
    mutating func surface(_ item: IndependentShapeItem, source: IndependentShapeSource, units: UnitSystem, originalAngularSource: IndependentShapeAngularSource?, originalLengthSource: OriginalSTEPLengthSource?, positionEntityID: Int?,
                          usage: inout IndependentShapeExchangeUsage) throws -> Int
    mutating func mappingOrigin(_ frame: AffineTransform3D, originalSource: OriginalSTEPPlacementSource?, name: String, units: UnitSystem,
                                usage: inout IndependentShapeExchangeUsage) throws -> Int
    mutating func mappingTarget(_ frame: AffineTransform3D, originalSource: OriginalSTEPPlacementSource?, name: String, units: UnitSystem,
                                usage: inout IndependentShapeExchangeUsage) throws -> Int
    mutating func quotedString(_ value: String, usage: inout IndependentShapeExchangeUsage) throws -> String
    mutating func appendEntity(_ expression: String, usage: inout IndependentShapeExchangeUsage) throws -> Int
    mutating func finish(usage: inout IndependentShapeExchangeUsage) throws -> Data
}
