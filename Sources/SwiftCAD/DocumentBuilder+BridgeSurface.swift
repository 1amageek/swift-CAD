import CADCore
import CADIR
import CADGeometry

public extension DocumentBuilder {
    @discardableResult
    mutating func bridgeSurface(
        startBoundary: StableSubshapeReference,
        endBoundary: StableSubshapeReference,
        endOrientation: BridgeSurfaceFeature.EndOrientation = .forward,
        startTransform: AffineTransform3D? = nil,
        endTransform: AffineTransform3D? = nil,
        named name: String? = nil
    ) throws -> FeatureID {
        let bridge = BridgeSurfaceFeature(
            startBoundary: startBoundary,
            endBoundary: endBoundary,
            endOrientation: endOrientation,
            startTransform: startTransform,
            endTransform: endTransform
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
