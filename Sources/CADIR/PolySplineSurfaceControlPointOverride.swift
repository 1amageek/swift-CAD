import CADCore
import CADGeometry

public struct PolySplineSurfaceControlPointOverride: Sendable, Hashable {
    public var patchID: Int
    public var uIndex: Int
    public var vIndex: Int
    public var point: Point3D
    public var weight: Double

    public init(
        patchID: Int,
        uIndex: Int,
        vIndex: Int,
        point: Point3D,
        weight: Double = 1.0
    ) {
        self.patchID = patchID
        self.uIndex = uIndex
        self.vIndex = vIndex
        self.point = point
        self.weight = weight
    }

    public var address: PolySplineSurfaceControlPointAddress {
        PolySplineSurfaceControlPointAddress(
            patchID: patchID,
            uIndex: uIndex,
            vIndex: vIndex
        )
    }

    public func validate() throws {
        var execution = try OriginalQueryExecution.independentGeometry()
        try validate(using: &execution)
    }

    public func validate(using execution: inout OriginalQueryExecution) throws {
        try execution.consumeWork(1)
        try address.validate()
        try point.validate()
        guard weight.isFinite else {
            throw GeometryError.invalidCoordinate(weight)
        }
        guard weight > 0.0 else {
            throw GeometryError.invalidDistance(weight)
        }
    }
}

#if !hasFeature(Embedded)
extension PolySplineSurfaceControlPointOverride: Codable {}
#endif
