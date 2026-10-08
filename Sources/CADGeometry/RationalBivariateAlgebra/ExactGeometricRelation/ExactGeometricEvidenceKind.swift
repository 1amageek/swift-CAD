#if L6_ISOLATED_VERIFICATION
import L0
import L1
import L2
import L3
import L4
import L5
#endif

public enum ExactGeometricEvidenceKind: Sendable {
    case empty, originalCurveImage, isolatedParameters, constantImage, affineInjection, finiteFiberMaps, firstParameterCurve, originalGraph
}
