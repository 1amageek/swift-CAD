import CADCore
import CADIR

public protocol InvoluteGearProfileBuilding: Sendable {
    func profile(sourceFeatureID: FeatureID, toothCount: Int,
        baseRadius: Double, pitchRadius: Double, tipRadius: Double, rootRadius: Double,
        pitchToothAngle: Double, filletRadius: Double, maximumError: Double,
        maximumSegments: Int, tolerance: ModelingTolerance, origin: Point3D) throws -> Profile
}
