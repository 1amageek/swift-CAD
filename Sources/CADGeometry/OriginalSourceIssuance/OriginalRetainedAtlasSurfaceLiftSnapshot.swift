import CADCore

public struct OriginalRetainedAtlasSurfaceLiftSnapshot<H: OriginalRetainedSurfaceSourceReading>: OriginalRetainedAtlasLiftSourceReading
    where H.Field == OriginalExactScalarDomain {
    public let original: SurfaceLiftCurve3D
    public let originalSurface: OriginalSourceBinding<H>
    public let originalPcurve: OriginalSourceBinding<OriginalAffinePcurveSnapshot>
    init(original: SurfaceLiftCurve3D,surface: OriginalSourceBinding<H>,pcurve: OriginalSourceBinding<OriginalAffinePcurveSnapshot>) {
        self.original=original;originalSurface=surface;originalPcurve=pcurve
    }
}
