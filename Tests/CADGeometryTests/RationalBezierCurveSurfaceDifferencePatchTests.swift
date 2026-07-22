import CADCore
@testable import CADGeometry
import Testing

@Suite("Rational Bezier Curve-Surface Difference Patch")
struct RationalBezierCurveSurfaceDifferencePatchTests {
    private let tolerance = ModelingTolerance.standard

    @Test
    func subdivisionCertifiesAFalsePositiveParentControlHull() throws {
        let curve = RationalBezierCurvePatch3D(
            controlPoints: [
                Point3D(x: -1.0, y: 0.0, z: 1.0),
                Point3D(x: 0.0, y: 0.0, z: -0.1),
                Point3D(x: 1.0, y: 0.0, z: 1.0),
            ],
            weights: [1.0, 1.0, 1.0],
            lower: 0.0,
            upper: 1.0
        )
        let surface = RationalBezierSurfacePatch3D(
            controlPoints: [
                [
                    Point3D(x: -2.0, y: -2.0, z: 0.0),
                    Point3D(x: 2.0, y: -2.0, z: 0.0),
                ],
                [
                    Point3D(x: -2.0, y: 2.0, z: 0.0),
                    Point3D(x: 2.0, y: 2.0, z: 0.0),
                ],
            ],
            weights: [[1.0, 1.0], [1.0, 1.0]],
            uLower: 0.0,
            uUpper: 1.0,
            vLower: 0.0,
            vUpper: 1.0
        )
        let parent = try RationalBezierCurveSurfaceDifferencePatch(
            curve: curve,
            surface: surface,
            tolerance: tolerance
        )
        #expect(parent.excludesZero() == false)
        #expect(parent.rootCertificate() == .unresolved)

        var leaves = [parent]
        for _ in 0..<4 {
            leaves = leaves.flatMap { $0.subdivided(direction: .curve) }
        }

        #expect(leaves.allSatisfy { $0.rootCertificate() == .excluded })
    }

    @Test
    func affineTransverseRootHasIntervalKrawczykUniquenessCertificate() throws {
        let curve = RationalBezierCurvePatch3D(
            controlPoints: [
                Point3D(x: 0.5, y: 0.5, z: -1.0),
                Point3D(x: 0.5, y: 0.5, z: 1.0),
            ],
            weights: [1.0, 1.0],
            lower: 0.0,
            upper: 1.0
        )
        let surface = RationalBezierSurfacePatch3D(
            controlPoints: [
                [
                    Point3D(x: 0.0, y: 0.0, z: 0.0),
                    Point3D(x: 1.0, y: 0.0, z: 0.0),
                ],
                [
                    Point3D(x: 0.0, y: 1.0, z: 0.0),
                    Point3D(x: 1.0, y: 1.0, z: 0.0),
                ],
            ],
            weights: [[1.0, 1.0], [1.0, 1.0]],
            uLower: 0.0,
            uUpper: 1.0,
            vLower: 0.0,
            vUpper: 1.0
        )
        let patch = try RationalBezierCurveSurfaceDifferencePatch(
            curve: curve,
            surface: surface,
            tolerance: tolerance
        )

        #expect(patch.rootCertificate() == .unique)
    }

    @Test
    func transverseRootRemainsInHomogeneousDifferenceCandidates() throws {
        let curve = RationalBezierCurvePatch3D(
            controlPoints: [
                Point3D(x: 0.5, y: 0.5, z: -1.0),
                Point3D(x: 0.5, y: 0.5, z: 1.0),
            ],
            weights: [1.0, 2.0],
            lower: 0.0,
            upper: 1.0
        )
        let surface = RationalBezierSurfacePatch3D(
            controlPoints: [
                [
                    Point3D(x: 0.0, y: 0.0, z: 0.0),
                    Point3D(x: 1.0, y: 0.0, z: 0.0),
                ],
                [
                    Point3D(x: 0.0, y: 1.0, z: 0.0),
                    Point3D(x: 1.0, y: 1.0, z: 0.0),
                ],
            ],
            weights: [[1.0, 1.5], [2.0, 1.0]],
            uLower: 0.0,
            uUpper: 1.0,
            vLower: 0.0,
            vUpper: 1.0
        )
        let parent = try RationalBezierCurveSurfaceDifferencePatch(
            curve: curve,
            surface: surface,
            tolerance: tolerance
        )

        var candidates = [parent]
        let directions: [RationalBezierCurveSurfaceDifferencePatch.SplitDirection] = [
            .curve, .surfaceU, .surfaceV,
        ]
        for depth in 0..<12 {
            candidates = candidates
                .flatMap { $0.subdivided(direction: directions[depth % 3]) }
                .filter { $0.excludesZero() == false }
        }

        #expect(candidates.isEmpty == false)
    }
}
