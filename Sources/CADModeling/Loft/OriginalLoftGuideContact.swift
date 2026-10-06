import CADCore
import CADGeometry

/// A section event retains the authored segment and original parameter enclosure.
package struct OriginalLoftGuideContact: Sendable {
    package let segmentIndex: Int
    package let parameters: ScalarInterval
    package let point: Point3D
    package let boundaryLoopIndex: Int
    package let parameterAuthority: OriginalCurveContactParameterAuthority?
    package let nativeEndpoint: OriginalCurveRootEndpoint?
    package init(segmentIndex: Int, parameters: ScalarInterval, point: Point3D,
        boundaryLoopIndex: Int, parameterAuthority: OriginalCurveContactParameterAuthority? = nil,
        nativeEndpoint: OriginalCurveRootEndpoint? = nil) {
        self.segmentIndex = segmentIndex; self.parameters = parameters; self.point = point
        self.boundaryLoopIndex = boundaryLoopIndex; self.parameterAuthority = parameterAuthority
        self.nativeEndpoint = nativeEndpoint
    }
}
