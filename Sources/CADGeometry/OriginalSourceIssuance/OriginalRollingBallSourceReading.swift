#if ORIGINAL_SOURCE_ISOLATED_VERIFICATION
import L0
import L1
#endif

/// Original normalized-U child bindings and the retained feasibility policy.
public protocol OriginalRollingBallSourceReading: Sendable {
    associatedtype Child: OriginalBSplineSourceReading
    var originalCenter: OriginalSourceBinding<Child> { get }
    var originalFirstContact: OriginalSourceBinding<Child> { get }
    var originalSecondContact: OriginalSourceBinding<Child> { get }
    var originalRadius: Double { get }
    var originalDistanceTolerance: Double { get }
    var originalRadialCrossThreshold: Double { get }
}
