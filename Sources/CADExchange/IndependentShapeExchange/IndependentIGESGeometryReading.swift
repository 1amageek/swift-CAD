import CADCore
import CADGeometry

/// Original IGES laws and ordered local transformations, with caller-paid primitive work.
public protocol IndependentIGESGeometryReading: Sendable {
    mutating func curve(entityPointer: Int, units: UnitSystem, tolerance: ModelingTolerance,
                        usage: inout IndependentShapeExchangeUsage) throws -> IndependentExchangeReadCurve
    mutating func surface(entityPointer: Int, units: UnitSystem, tolerance: ModelingTolerance,
                          usage: inout IndependentShapeExchangeUsage) throws -> IndependentExchangeReadSurface
    mutating func transformation(entityPointer: Int, units: UnitSystem,
                                 usage: inout IndependentShapeExchangeUsage) throws -> AffineTransform3D
    mutating func instancePlacement(entityPointer: Int, units: UnitSystem,
                                    usage: inout IndependentShapeExchangeUsage) throws -> AffineTransform3D
}
