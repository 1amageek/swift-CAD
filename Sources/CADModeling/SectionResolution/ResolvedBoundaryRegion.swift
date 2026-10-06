import CADCore
import CADGeometry
import CADIR

/// Original placed closed region, independent of its display Profile facade.
package struct ResolvedBoundaryRegion: Sendable {
    package enum Source: Sendable {
        case profile(Profile, ProfileReference)
        case face(ResolvedFaceSection, FaceSectionReference)
    }
    package let source: Source
    package let profile: Profile
    /// Outer first; each chart retains its original directed fraction expression.
    package let loops: [[OriginalCurveSpanParameterChart]]
    package let placement: [RigidTransform3D]
    package var plane: SketchPlane { profile.plane }
    package var sectionReference: SectionReference {
        switch source {
        case .profile(_, let reference): .profile(reference)
        case .face(_, let reference): .face(reference)
        }
    }
}
