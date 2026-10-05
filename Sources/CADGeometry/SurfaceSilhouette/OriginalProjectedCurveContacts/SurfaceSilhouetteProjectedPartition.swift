import CADCore

/// Complete original edge-native partition against one supplied original silhouette traversal.
public struct SurfaceSilhouetteProjectedPartition: Sendable {
    public struct Sector: Sendable {
        public let lower: SurfaceSilhouetteTrimEndpoint
        public let upper: SurfaceSilhouetteTrimEndpoint
        public let originalInteriorWitness: ExactRationalCoefficient
    }
    public let originalEdge: Curve3D
    public let originalSpanIndex: Int
    public let nativeRange: ScalarInterval
    public let silhouette: OriginalSurfaceSilhouetteTrimmedCurve
    public let frame: OrthographicProjectionFrame
    public let contacts: [SurfaceSilhouetteProjectedContact]
    public let cuts: [SurfaceSilhouetteTrimEndpoint]
    public let eventFreeSectors: [Sector]
    public let hasWholeRangeProjectedOverlap: Bool
    private let originalEquations: OriginalProjectedNativePolynomialPair

    init(edge: Curve3D, spanIndex: Int, original: OriginalProjectedNativePolynomialPair,
        contacts: [SurfaceSilhouetteProjectedContact], cuts: [SurfaceSilhouetteTrimEndpoint],
        sectors: [Sector], wholeRange: Bool) {
        originalEdge = edge; originalSpanIndex = spanIndex; nativeRange = original.edgeRange
        silhouette = original.silhouette; frame = original.frame; self.contacts = contacts
        self.cuts = cuts; eventFreeSectors = sectors; hasWholeRangeProjectedOverlap = wholeRange
        originalEquations = original
    }
}
