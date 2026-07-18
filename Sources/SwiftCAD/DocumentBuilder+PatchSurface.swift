import CADCore
import CADIR

public extension DocumentBuilder {
    @discardableResult
    mutating func patchSurface(
        vMinimumBoundary: BSplineCurve3D,
        vMaximumBoundary: BSplineCurve3D,
        uMinimumBoundary: BSplineCurve3D,
        uMaximumBoundary: BSplineCurve3D,
        vMinimumOrientation: PatchSurfaceFeature.BoundaryOrientation = .forward,
        vMaximumOrientation: PatchSurfaceFeature.BoundaryOrientation = .forward,
        uMinimumOrientation: PatchSurfaceFeature.BoundaryOrientation = .forward,
        uMaximumOrientation: PatchSurfaceFeature.BoundaryOrientation = .forward,
        material: MaterialID? = nil,
        named name: String? = nil
    ) throws -> FeatureID {
        let patch = PatchSurfaceFeature(
            vMinimumBoundary: vMinimumBoundary,
            vMaximumBoundary: vMaximumBoundary,
            uMinimumBoundary: uMinimumBoundary,
            uMaximumBoundary: uMaximumBoundary,
            vMinimumOrientation: vMinimumOrientation,
            vMaximumOrientation: vMaximumOrientation,
            uMinimumOrientation: uMinimumOrientation,
            uMaximumOrientation: uMaximumOrientation,
            material: material
        )
        let featureID = FeatureID()
        try append(
            id: featureID,
            name: name,
            operation: .patchSurface(patch)
        )
        return featureID
    }
}
