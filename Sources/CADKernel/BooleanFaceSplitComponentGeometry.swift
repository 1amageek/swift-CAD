public enum BooleanFaceSplitComponentGeometry: Codable, Hashable, Sendable {
    case transverseSegment(start: BooleanUVPoint, end: BooleanUVPoint)
    case closedCurve(BooleanClosedFaceIntersection)
    case trimmedCurve(BooleanTrimmedFaceIntersectionChain)
    case tangent(BooleanUVPoint)
    case coincident
}
