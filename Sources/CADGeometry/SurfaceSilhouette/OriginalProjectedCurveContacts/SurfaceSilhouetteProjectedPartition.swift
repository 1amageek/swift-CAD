import CADCore

/// Complete original edge-native partition against one supplied original silhouette traversal.
public struct SurfaceSilhouetteProjectedPartition: Sendable {
    public struct Sector: Sendable {
        public let lower: SurfaceSilhouetteTrimEndpoint
        public let upper: SurfaceSilhouetteTrimEndpoint
        public let originalInteriorWitness: ExactRationalCoefficient
    }
    public var originalEdge: Curve3D { originalEquations.edge.originalCurve }
    public var originalSpanIndex: Int { originalEquations.edge.spanIndex }
    public var nativeRange: ScalarInterval { originalEquations.edgeRange }
    public var silhouette: OriginalSurfaceSilhouetteTrimmedCurve { originalEquations.silhouette }
    public var frame: OrthographicProjectionFrame { originalEquations.frame }
    public let contacts: [SurfaceSilhouetteProjectedContact]
    public let cuts: [SurfaceSilhouetteTrimEndpoint]
    public let eventFreeSectors: [Sector]
    public let hasWholeRangeProjectedOverlap: Bool
    private let originalEquations: OriginalProjectedNativePolynomialPair

    init(original: consuming OriginalProjectedNativePolynomialPair,
        contacts: consuming [SurfaceSilhouetteProjectedContact], cuts: consuming [SurfaceSilhouetteTrimEndpoint],
        sectors: consuming [Sector], wholeRange: Bool) {
        self.contacts = contacts
        self.cuts = cuts; eventFreeSectors = sectors; hasWholeRangeProjectedOverlap = wholeRange
        originalEquations = original
    }
}
