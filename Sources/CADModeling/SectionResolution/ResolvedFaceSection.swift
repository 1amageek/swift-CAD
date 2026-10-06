import CADCore
import CADIR
import CADTopology

/// Invocation-owned original planar face section and its compatibility facade.
package struct ResolvedFaceSection: Sendable {
    package let faceID: FaceID
    package let profile: Profile
    /// Outer first, followed by the original holes in source order.
    package let loops: [OriginalFaceSectionLoop]
    package var plane: SketchPlane { profile.plane }
}
