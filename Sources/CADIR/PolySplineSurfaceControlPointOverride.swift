import CADCore

public struct PolySplineSurfaceControlPointOverride: Codable, Sendable, Hashable {
    public var patchID: Int
    public var uIndex: Int
    public var vIndex: Int
    public var point: Point3D

    public init(
        patchID: Int,
        uIndex: Int,
        vIndex: Int,
        point: Point3D
    ) {
        self.patchID = patchID
        self.uIndex = uIndex
        self.vIndex = vIndex
        self.point = point
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
    }
}
