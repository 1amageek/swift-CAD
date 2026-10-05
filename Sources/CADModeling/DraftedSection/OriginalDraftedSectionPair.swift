import CADCore
import CADGeometry

/// Separate original wall authority and certified endpoint-section images.
package struct OriginalDraftedSectionPair: Sendable {
    package let lowerImage: BSplineCurve3D
    package let upperImage: BSplineCurve3D
    package let lowerSource: OriginalDraftedCurve3D
    package let upperSource: OriginalDraftedCurve3D
    package let wall: OriginalDraftedRuledSurface3D
}
