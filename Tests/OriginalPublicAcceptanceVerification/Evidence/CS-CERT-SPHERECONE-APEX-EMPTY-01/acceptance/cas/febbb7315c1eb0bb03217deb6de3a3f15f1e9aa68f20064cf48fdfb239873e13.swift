/// Concrete requirements keep the retained empty proof accessible on Embedded targets.
public protocol OriginalCertifiedApexPlaneExclusionReading: Sendable {
    var original: OriginalCertifiedApexPlaneExclusion { get }
    var isEmpty: Bool { get }
    var hasPositiveDimensionalSolutions: Bool { get }
    var hasPositiveDimensionalImage: Bool { get }
}

extension OriginalCertifiedApexPlaneExclusion: OriginalCertifiedApexPlaneExclusionReading {
    public var original: OriginalCertifiedApexPlaneExclusion { self }
}
