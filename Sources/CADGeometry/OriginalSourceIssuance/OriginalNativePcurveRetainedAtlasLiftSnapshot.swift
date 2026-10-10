import CADCore

public struct OriginalNativePcurveRetainedAtlasLiftSnapshot<H: OriginalRetainedSurfaceSourceReading>: OriginalNativePcurveRetainedAtlasLiftSourceReading
    where H.Field == OriginalExactScalarDomain {
    public let original: SurfaceLiftCurve3D
    public let originalSurface: OriginalSourceBinding<H>
    public let originalPcurve: OriginalSourceBinding<BSplineCurve2D>
    init(original: SurfaceLiftCurve3D,surface: OriginalSourceBinding<H>,pcurve: OriginalSourceBinding<BSplineCurve2D>) {
        self.original=original;originalSurface=surface;originalPcurve=pcurve
    }
}
