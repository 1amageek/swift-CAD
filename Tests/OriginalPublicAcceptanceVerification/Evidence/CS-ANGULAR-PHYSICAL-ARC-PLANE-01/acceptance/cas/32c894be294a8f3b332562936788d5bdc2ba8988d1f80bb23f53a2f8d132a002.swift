import CADCore
#if ORIGINAL_SOURCE_GEOMETRY_ADAPTER_VERIFICATION
import enum CADGeometry.Curve3D
import enum CADGeometry.Surface3D
import SourceIssuer
#endif

/// The actual authored curve/surface remains retained beside its coordinate law.
public struct OriginalAnalyticCoordinateSnapshot: OriginalAnalyticCoordinateReading {
    public enum Authored: Sendable { case curve(Curve3D),surface(Surface3D) }
    public let authored: Authored
    public let coordinateKind: OriginalAnalyticCoordinateKind
    public let origin: Point3D
    public let first: Vector3D
    public let second: Vector3D
    public let third: Vector3D
    public let firstMagnitude: Double
    public let secondMagnitude: Double
    public let coneHalfAngle: Double
    let uMap: OriginalSourceAngularMap
    let vMap: OriginalSourceAngularMap
    let lower: Double?
    let upper: Double?
    public func center(in axis: Int) -> Double { axis == 0 ? origin.x : axis == 1 ? origin.y : origin.z }
    public func frame(row: Int,column: Int) -> Double {
        let vector = column == 0 ? first : column == 1 ? second : third
        return row == 0 ? vector.x : row == 1 ? vector.y : vector.z
    }
    public func angularMap(axis: Int) -> OriginalSourceAngularMap { axis == 0 ? uMap : vMap }
    public func finiteLowerBound(axis: Int) -> Double? { coordinateKind.arity == 1 && axis == 0 ? lower : nil }
    public func finiteUpperBound(axis: Int) -> Double? { coordinateKind.arity == 1 && axis == 0 ? upper : nil }
}
