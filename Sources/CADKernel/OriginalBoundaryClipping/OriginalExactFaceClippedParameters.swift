import CADCore
#if NATIVE_DOMAIN_ISOLATED_VERIFICATION
import L0
import L1
import L2
import L3
import L4
import L5
import DI0
import DI
import SourceIssuer
import NativeDomainAdapters
import struct CADGeometry.BSplineSurface3D
import enum CADGeometry.SurfaceParameterCurve
@testable import class CADGeometry.OriginalNativeBoundaryDomain
@testable import struct CADKernel.DefaultOriginalFaceBoundaryClipper
#else
import CADGeometry
#endif
import CADTopology

/// Retains immutable face/coedge authority beside complete L5 boundary refinement.
public struct OriginalExactFaceClippedParameters: Sendable {
    public let original: ValidatedBRepModel
    public let faceID: FaceID
    public let loops: [Loop]
    public let parameters: OriginalExactClippedNativeParameters
    init(original: ValidatedBRepModel,faceID: FaceID,loops: [Loop],parameters: OriginalExactClippedNativeParameters) {
        self.original = original;self.faceID = faceID;self.loops = loops;self.parameters = parameters
    }
}
