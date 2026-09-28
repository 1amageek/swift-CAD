import CADCore
import CADGeometry
import CADIR
import Foundation
import Testing
@testable import CADKernel

/// A line meets a sphere twice; a directional projection onto one octant face of a sphere body
/// takes only the meeting inside that face's trim, and none when both lie outside it.
@Suite("Directional projection trim")
struct DirectionalProjectionTrimTests {
    @Test(.timeLimit(.minutes(1)))
    func aSphereOctantTakesOnlyTheMeetingInsideItsTrim() throws {
        var document = CADDocument(units: .meters)
        try document.appendFeatures([
            FeatureNode(
                id: FeatureID(),
                operation: .primitive(PrimitiveFeature(definition: .sphere(SpherePrimitive(
                    placement: PrimitivePlacement(origin: .origin, axis: .unitZ, referenceDirection: .unitX),
                    radius: .constant(.length(2.0, unit: .meter))
                )))),
                outputs: [FeatureOutput(role: .body)]
            ),
        ], tolerance: .standard)
        let evaluated = try DocumentEvaluator(tolerance: .standard).evaluate(document)
        let evaluator = SurfaceQueryEvaluator(tolerance: .standard)
        var upper: SurfaceReference?
        for (subshapeID, topology) in evaluated.subshapes.entries {
            guard case .face = topology else { continue }
            let reference = SurfaceReference(subshape: try evaluated.stableSubshapeReference(for: subshapeID))
            // A face whose point nearest the probe is a pole has no frame there; it is not the
            // octant sought.
            let probe: SurfaceOutwardFrame
            do {
                probe = try evaluator.outwardFrame(nearestTo: Point3D(x: 1, y: 1, z: 1), on: reference, in: evaluated)
            } catch {
                continue
            }
            if probe.point.x > 0.1, probe.point.y > 0.1, probe.point.z > 0.1 { upper = reference }
        }
        let face = try #require(upper)
        // Below the octant, looking down: the line meets the sphere at z = ±√(4 − 1 − 0.25); the
        // upper meeting is behind the ray and the lower one is outside the octant.
        let source = Point3D(x: 1.0, y: 0.5, z: 0.0)
        #expect(throws: (any Error).self) {
            try evaluator.project(source, along: Vector3D(x: 0, y: 0, z: -1), onto: face, in: evaluated,
                                  options: SurfaceDirectionalProjectionOptions(range: .ray))
        }
        // Both ways: the upper meeting, the only one inside the face.
        let both = try evaluator.project(source, along: Vector3D(x: 0, y: 0, z: -1), onto: face, in: evaluated,
                                         options: SurfaceDirectionalProjectionOptions(range: .line))
        #expect(abs(both.projectedPoint.z - (4.0 - 1.0 - 0.25).squareRoot()) < 1.0e-9)
        // Ignoring the trim, the nearer meeting is either one: the support sphere is met both ways.
        let support = try evaluator.project(source, along: Vector3D(x: 0, y: 0, z: -1), onto: face, in: evaluated,
                                            options: SurfaceDirectionalProjectionOptions(range: .ray, respectsTrimBounds: false))
        #expect(support.projectedPoint.z < 0)
    }
}
