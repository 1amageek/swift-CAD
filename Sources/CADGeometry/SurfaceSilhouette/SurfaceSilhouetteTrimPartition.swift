import CADCore

/// Complete original parameter partition for one retained curve/boundary pair.
public struct SurfaceSilhouetteTrimPartition: Sendable {
    public struct Event: Sendable {
        public let parameter: SurfaceSilhouetteTrimEndpoint
        public let boundaryFraction: SurfaceSilhouetteTrimEndpoint
        public let originalBoundarySpan: Int
    }
    public struct Overlap: Sendable {
        public let lower: SurfaceSilhouetteTrimEndpoint
        public let upper: SurfaceSilhouetteTrimEndpoint
        public let boundaryLowerFraction: SurfaceSilhouetteTrimEndpoint
        public let boundaryUpperFraction: SurfaceSilhouetteTrimEndpoint
        public let originalBoundarySpan: Int
    }
    public struct Sector: Sendable {
        public enum Kind: Sendable { case eventFree, coincident }
        public let lower: SurfaceSilhouetteTrimEndpoint
        public let upper: SurfaceSilhouetteTrimEndpoint
        public let kind: Kind
    }
    public let originalCurve: OriginalSurfaceSilhouetteCurve
    public let originalBoundary: OriginalSurfaceSilhouetteBoundary
    public let events: [Event]
    public let overlaps: [Overlap]
    public let sectors: [Sector]
}
