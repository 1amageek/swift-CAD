import CADCore
import Foundation
import Testing
@testable import CADModeling

@Suite("Planar draft constraint solver")
struct DefaultPlanarDraftConstraintSolverTests {
    @Test(.timeLimit(.minutes(1)))
    func solvesNonOrthogonalSharedVertexConstraintsWithinTolerance() throws {
        let vertexID = VertexID()
        let firstDirection = Vector3D.unitX
        let secondDirection = try Vector3D(
            x: 0.5,
            y: sqrt(3.0) / 2.0,
            z: 0.0
        ).normalized(tolerance: 1.0e-12)
        let value = 0.01
        let displacements = try DefaultPlanarDraftConstraintSolver().displacements(
            for: [
                vertexID: [
                    PlanarDraftConstraint(direction: firstDirection, value: value),
                    PlanarDraftConstraint(direction: secondDirection, value: value),
                ],
            ],
            neutralNormal: .unitZ,
            featureID: FeatureID(),
            tolerance: .standard
        )
        let displacement = try #require(displacements[vertexID])

        #expect(abs(displacement.dot(firstDirection) - value) <= 1.0e-12)
        #expect(abs(displacement.dot(secondDirection) - value) <= 1.0e-12)
        #expect(abs(displacement.z) <= 1.0e-12)
    }
}
