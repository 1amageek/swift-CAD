#if ISSUED_GEOMETRY_ISOLATED_VERIFICATION
import L0
import L1
import L2
import L3
import L4
import L5
import L6
import DI0
import DI
import SourceIssuer
import IssuedGraphs
#endif

/// Requirements remain callable through the retained public existential on Embedded.
public protocol OriginalIssuedGeometricRelationReading: Sendable {
    var kind: ExactParametricRelationKind { get }
    var pairs: [OriginalIssuedGeometricRelationPair] { get }
    var exactPoints: [OriginalIssuedExactIntersectionPoint] { get }
    var hasPositiveDimensionalSolutions: Bool { get }
    var hasPositiveDimensionalImage: Bool { get }
    var isEmpty: Bool { get }
    /// Parameterized sections complement the cell-backed pairs without replacing original UV.
    var surfacePlaneSections: [OriginalSurfacePlaneSection] { get }
    /// Complete independent integer-cycle geometric contacts retain all original UV.
    var periodicOffsetContacts: [OriginalPeriodicOffsetContactTemplate] { get }
}

public extension OriginalIssuedGeometricRelationReading {
    var surfacePlaneSections: [OriginalSurfacePlaneSection] { [] }
    var periodicOffsetContacts: [OriginalPeriodicOffsetContactTemplate] { [] }
}
