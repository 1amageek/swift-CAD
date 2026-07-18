import CADCore
import CADIR

public extension DocumentBuilder {
    @discardableResult
    mutating func bridgeSurface(
        startBoundary: BSplineCurve3D,
        endBoundary: BSplineCurve3D,
        endOrientation: BridgeSurfaceFeature.EndOrientation = .forward,
        material: MaterialID? = nil,
        named name: String? = nil
    ) throws -> FeatureID {
        let bridge = BridgeSurfaceFeature(
            startBoundary: startBoundary,
            endBoundary: endBoundary,
            endOrientation: endOrientation,
            material: material
        )
        let featureID = FeatureID()
        try append(
            id: featureID,
            name: name,
            operation: .bridgeSurface(bridge)
        )
        return featureID
    }
}
