import Foundation
import CADCore
import CADIR
import CADGeometry

/// Parent-owned IGES entity table and original primitive/domain writer.
public protocol IndependentIGESGeometryWriting: Sendable {
    mutating func curve(_ item: IndependentShapeItem, source: IndependentShapeSource, units: UnitSystem,
                        usage: inout IndependentShapeExchangeUsage) throws -> Int
    mutating func surface(_ item: IndependentShapeItem, source: IndependentShapeSource, units: UnitSystem,
                          usage: inout IndependentShapeExchangeUsage) throws -> Int
    mutating func frame(_ frame: IndependentShapeFrame, units: UnitSystem,
                        usage: inout IndependentShapeExchangeUsage) throws -> Int
    mutating func instancePlacement(_ instance: IndependentShapeInstance, definitionPointer: Int, units: UnitSystem,
                                    usage: inout IndependentShapeExchangeUsage) throws -> Int
    mutating func appendEntity(type: Int, form: Int, label: String, transformationPointer: Int,
                               parameters: [String], usage: inout IndependentShapeExchangeUsage) throws -> Int
    mutating func appendGroupBackPointer(groupPointer: Int, memberPointer: Int,
                                        usage: inout IndependentShapeExchangeUsage) throws
    mutating func string(_ value: String, usage: inout IndependentShapeExchangeUsage) throws -> String
    mutating func finish(units: UnitSystem, usage: inout IndependentShapeExchangeUsage) throws -> Data
}
