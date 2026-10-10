import CADCore

/// A Native lift retaining the already-certified original polyline station owner.
public struct OriginalPolylineSurfaceLiftSnapshot: OriginalRetainedSurfaceLiftSourceReading {
    public let original: SurfaceLiftCurve3D
    public let originalSurface: OriginalSourceBinding<BSplineSurface3D>
    public let originalPcurve: OriginalSourceBinding<OriginalPolylinePcurveSnapshot>
    init(original: SurfaceLiftCurve3D, surface: OriginalSourceBinding<BSplineSurface3D>,
        pcurve: OriginalSourceBinding<OriginalPolylinePcurveSnapshot>) {
        self.original=original; originalSurface=surface; originalPcurve=pcurve
    }
}
