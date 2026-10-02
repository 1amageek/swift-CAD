import Foundation
import CADCore

/// One point of Align Surface's Analysis along the reference edge, in the aligned sheet's frame:
/// the edge's point, the sheet's nearest point to it, both surfaces' unit normals there (the
/// reference's turned to agree with the sheet's), the direction across the edge on the sheet,
/// and both surfaces' normal curvatures along it — what the G0 gap, G1 normal turn and G2
/// curvature combs are drawn from.
public struct SurfaceAlignSample: Sendable, Hashable {
    public let edgePoint: Point3D
    public let sheetPoint: Point3D
    public let sheetNormal: Vector3D
    public let referenceNormal: Vector3D
    public let across: Vector3D
    public let sheetCurvature: Double
    public let referenceCurvature: Double

    public init(edgePoint: Point3D, sheetPoint: Point3D, sheetNormal: Vector3D, referenceNormal: Vector3D, across: Vector3D,
                sheetCurvature: Double, referenceCurvature: Double) {
        self.edgePoint = edgePoint
        self.sheetPoint = sheetPoint
        self.sheetNormal = sheetNormal
        self.referenceNormal = referenceNormal
        self.across = across
        self.sheetCurvature = sheetCurvature
        self.referenceCurvature = referenceCurvature
    }

    /// The angle between the two normals.
    public var angle: Double { acos(min(1, abs(sheetNormal.dot(referenceNormal)))) }
}
