import CADCore

public struct OriginalAffineSurfaceLiftSnapshot: OriginalRetainedSurfaceLiftSourceReading {
    public let original: SurfaceLiftCurve3D
    public let originalSurface: OriginalSourceBinding<BSplineSurface3D>
    public let originalPcurve: OriginalSourceBinding<OriginalAffinePcurveSnapshot>
    init(original: SurfaceLiftCurve3D, surface: OriginalSourceBinding<BSplineSurface3D>,
        pcurve: OriginalSourceBinding<OriginalAffinePcurveSnapshot>) {
        self.original=original;originalSurface=surface;originalPcurve=pcurve
    }
}
