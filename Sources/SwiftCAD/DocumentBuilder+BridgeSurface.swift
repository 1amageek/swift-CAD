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
        startContinuity: SurfaceContinuityLevel = .positional,
        endContinuity: SurfaceContinuityLevel = .positional,
        startTension: Double = 1,
        endTension: Double = 1,
        width: Double? = nil,
        startWall: StableSubshapeReference? = nil,
        endWall: StableSubshapeReference? = nil,
        named name: String? = nil
    ) throws -> FeatureID {
        let bridge = BridgeSurfaceFeature(
            startBoundary: startBoundary,
            endBoundary: endBoundary,
            endOrientation: endOrientation,
            startTransform: startTransform,
            endTransform: endTransform,
            startContinuity: startContinuity,
            endContinuity: endContinuity,
            startTension: startTension,
            endTension: endTension,
            width: width,
            startWall: startWall,
            endWall: endWall
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
