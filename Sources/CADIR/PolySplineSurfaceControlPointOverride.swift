import CADCore

public struct PolySplineSurfaceControlPointOverride: Codable, Sendable, Hashable {
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
