#if L4_ISOLATED_VERIFICATION
import L0
import L1
import L2
import L3
#endif

public enum ExactRealClosureProof: Sendable { case point, affine, boundedSectionGraph, polynomialGraph, quantified }
