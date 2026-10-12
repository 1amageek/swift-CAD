import CADCore
import CADGeometry

public struct BRepVolumeMoments: Sendable {
    /// V, X, Y, Z, XX, YY, ZZ, XY, XZ, YZ, in model length units.
    public let enclosures: [ScalarInterval]
    public let consumedWork: Int
    public init(enclosures: [ScalarInterval], consumedWork: Int) throws {
        guard enclosures.count == 10, enclosures[0].lower > 0,
            enclosures.allSatisfy({ $0.lower.isFinite && $0.upper.isFinite }),
            consumedWork > 0, consumedWork <= 262_144 else {
            throw GeometryError.invalidDistance(enclosures.first?.lower ?? 0)
        }
        self.enclosures = enclosures; self.consumedWork = consumedWork
    }
    public func centroidEnclosures() throws -> [ScalarInterval] {
        let volume = TrimmedAnalyticSurfaceVolumeEvaluator.Interval(lower: enclosures[0].lower,
            upper: enclosures[0].upper)
        return try enclosures[1...3].map { value in
            let quotient = TrimmedAnalyticSurfaceVolumeEvaluator.Interval(lower: value.lower,
                upper: value.upper) / volume
            return try ScalarInterval(lower: quotient.lower, upper: quotient.upper)
        }
    }
    public var volume: Double { enclosures[0].midpoint }
    public var firstMoment: Vector3D { Vector3D(x: enclosures[1].midpoint, y: enclosures[2].midpoint, z: enclosures[3].midpoint) }
    public var centroid: Point3D { Point3D(x: firstMoment.x / volume, y: firstMoment.y / volume, z: firstMoment.z / volume) }
}
