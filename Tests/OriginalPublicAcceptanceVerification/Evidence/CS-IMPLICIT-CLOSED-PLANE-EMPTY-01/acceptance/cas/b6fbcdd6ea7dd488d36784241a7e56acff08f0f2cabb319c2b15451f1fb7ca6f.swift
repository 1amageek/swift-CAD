/// Concrete requirements keep the retained empty proof accessible on Embedded targets.
public protocol OriginalImplicitHostPlaneExclusionReading: Sendable {
    var original: OriginalImplicitHostPlaneExclusion { get }
    var isEmpty: Bool { get }
    var hasPositiveDimensionalSolutions: Bool { get }
    var hasPositiveDimensionalImage: Bool { get }
}

extension OriginalImplicitHostPlaneExclusion: OriginalImplicitHostPlaneExclusionReading {
    public var original: OriginalImplicitHostPlaneExclusion { self }
}
