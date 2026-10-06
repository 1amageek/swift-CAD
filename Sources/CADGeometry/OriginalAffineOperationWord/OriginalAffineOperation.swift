import CADCore

/// One original coefficient or normalized-direction law and its application direction.
public enum OriginalAffineOperation: Hashable, Sendable {
    case forward(AffineTransform3D)
    case inverse(AffineTransform3D)
    case rationalForward(OriginalRationalAffineSource)
    case rationalInverse(OriginalRationalAffineSource)
    case normalizedForward(OriginalNormalizedAffineSource)
    case normalizedInverse(OriginalNormalizedAffineSource)
}
