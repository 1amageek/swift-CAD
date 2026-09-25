import CADCore
import CADIR

public extension DocumentBuilder {
    @discardableResult
    mutating func bridgeSurface(
        startBoundary: StableSubshapeReference,
        endBoundary: StableSubshapeReference,
        endOrientation: BridgeSurfaceFeature.EndOrientation = .forward,
        named name: String? = nil
    ) throws -> FeatureID {
        let bridge = BridgeSurfaceFeature(
            startBoundary: startBoundary,
            endBoundary: endBoundary,
            endOrientation: endOrientation
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
