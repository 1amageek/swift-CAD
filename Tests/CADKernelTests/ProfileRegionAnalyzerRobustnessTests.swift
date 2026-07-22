import Testing
import CADCore
import CADIR
@testable import CADKernel

@Suite("Profile region robustness")
struct ProfileRegionAnalyzerRobustnessTests {
    @Test
    func rejectsScaleDependentDegenerateAreaWithTypedDiagnostic() throws {
        let profile = Profile(
            sourceFeatureID: FeatureID(),
            plane: .xy,
            vertices: [
                Point3D(x: 0.0, y: 0.0, z: 0.0),
                Point3D(x: 1_000.0, y: 0.0, z: 0.0),
                Point3D(x: 1_000.0, y: 1.0e-10, z: 0.0),
                Point3D(x: 0.0, y: 1.0e-10, z: 0.0),
            ]
        )

        do {
            _ = try ProfileRegionAnalyzer(tolerance: .standard).summary(for: profile)
            Issue.record("Expected the scale-dependent degenerate area to be rejected.")
        } catch SketchError.degenerateProfile {
            return
        }
    }
}
