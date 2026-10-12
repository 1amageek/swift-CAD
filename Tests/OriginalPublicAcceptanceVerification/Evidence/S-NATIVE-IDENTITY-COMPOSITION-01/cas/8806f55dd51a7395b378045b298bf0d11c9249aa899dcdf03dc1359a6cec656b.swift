#if ORIGINAL_SOURCE_ISOLATED_VERIFICATION
import L0
import L1
#endif

/// Retained authored phase, before mathematical harmonic evaluation.
public enum OriginalSourceAngularMap: Sendable {
    case intrinsic
    case physicalRadians(gain: ExactRationalCoefficient,offset: ExactRationalCoefficient)
    case physicalRadianArc(start: ExactRationalCoefficient,end: ExactRationalCoefficient,additionalTurns: Int)
    public var meaning: OriginalSourceParameterMeaning {
        switch self { case .intrinsic: return .intrinsicAngularLabel; case .physicalRadians: return .physicalRadian; case .physicalRadianArc: return .normalizedPhysicalRadianArc }
    }
}
