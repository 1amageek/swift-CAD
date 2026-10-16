import Foundation
import CADCore
import CADIR
import CADGeometry

/// Parent-owned IGES entity table and original primitive/domain writer.
public protocol IndependentIGESGeometryWriting: Sendable {
    mutating func curve(_ item: IndependentShapeItem, source: IndependentShapeSource, units: UnitSystem,
                        usage: IndependentShapeExchangeOwner, using execution: inout OriginalQueryExecution) throws -> Int
    mutating func surface(_ item: IndependentShapeItem, source: IndependentShapeSource, units: UnitSystem,
                          usage: IndependentShapeExchangeOwner, using execution: inout OriginalQueryExecution) throws -> Int
    mutating func frame(_ frame: IndependentShapeFrame, units: UnitSystem,
                        usage: IndependentShapeExchangeOwner, using execution: inout OriginalQueryExecution) throws -> Int
    mutating func instancePlacement(_ instance: IndependentShapeInstance, definitionPointer: Int, units: UnitSystem,
                                    usage: IndependentShapeExchangeOwner, using execution: inout OriginalQueryExecution) throws -> Int
    mutating func appendEntity(type: Int, form: Int, label: String, transformationPointer: Int,
                               parameters: [String], usage: IndependentShapeExchangeOwner, using execution: inout OriginalQueryExecution) throws -> Int
    mutating func appendGroupBackPointer(groupPointer: Int, memberPointer: Int,
                                        usage: IndependentShapeExchangeOwner, using execution: inout OriginalQueryExecution) throws
    mutating func string(_ value: String, usage: IndependentShapeExchangeOwner, using execution: inout OriginalQueryExecution) throws -> String
    mutating func finish(units: UnitSystem, usage: IndependentShapeExchangeOwner, using execution: inout OriginalQueryExecution) throws -> Data
}
