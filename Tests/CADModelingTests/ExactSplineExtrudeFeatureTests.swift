import Testing
import CADCore
import CADGeometry
import CADIR
import CADModeling
import CADTopology

@Suite("Exact spline extrude")
struct ExactSplineExtrudeFeatureTests {
    private let tolerance = ModelingTolerance(
        distance: 1.0e-8,
        angle: 1.0e-10
    )

    @Test(.timeLimit(.minutes(1)))
    func rationalSplineProducesExactObliqueRuledSurface() throws {
        let profileFeatureID = FeatureID()
        let extrudeFeatureID = FeatureID()
        let sourceCurve = BSplineCurve3D(
            degree: 3,
            knots: [0.0, 0.0, 0.0, 0.0, 1.0, 1.0, 1.0, 1.0],
            controlPoints: [
                Point3D(x: 0.0, y: 0.0, z: 0.0),
                Point3D(x: 0.02, y: 0.004, z: 0.0),
                Point3D(x: 0.018, y: 0.016, z: 0.0),
                Point3D(x: 0.0, y: 0.02, z: 0.0),
            ],
            weights: [1.0, 0.8, 1.2, 1.0]
        )
        try sourceCurve.validate(tolerance: tolerance)
        let samples = try (0...8).map { index in
            try sourceCurve.point(
                at: Double(index) / 8.0,
                tolerance: tolerance
            )
        }
        let profile = Profile(
            sourceFeatureID: profileFeatureID,
            plane: .xy,
            vertices: samples,
            boundarySegments: [
                .spline(ProfileSplineSegment(curve: sourceCurve)),
                .line(ProfileLineSegment(
                    start: try #require(samples.last),
                    end: try #require(samples.first)
                )),
            ]
        )
        let vector = Vector3D(x: 0.2, y: 0.1, z: 1.0)
        let distance = 0.03
        let feature = FeatureNode(
            id: extrudeFeatureID,
            operation: .extrude(ExtrudeFeature(
                profile: ProfileReference(featureID: profileFeatureID),
                distance: .constant(.length(distance, unit: .meter)),
                direction: .vector(vector)
            )),
            inputs: [FeatureInput(featureID: profileFeatureID, role: .profile)],
            outputs: [FeatureOutput(role: .body)]
        )
        let context = EvaluationContext(
            parameters: ResolvedParameterTable(),
            brep: BRepModel(),
            profiles: [profileFeatureID: [profile]],
            tolerance: tolerance
        )

        let result = try PlanarExtrudeFeatureEvaluator().evaluate(
            feature: feature,
            context: context
        )
        let repeated = try PlanarExtrudeFeatureEvaluator().evaluate(
            feature: feature,
            context: context
        )

        #expect(result.brep == repeated.brep)
        #expect(result.lineage == repeated.lineage)
        #expect(result.brep.faces.count == 4)
        #expect(result.brep.edges.count == 6)
        #expect(result.brep.vertices.count == 4)
        #expect(result.brep.loops.values.allSatisfy {
            $0.coedges.allSatisfy { $0.surfaceParameterCurve != nil }
        })
        try result.brep.validate(level: .exact, tolerance: tolerance)
        try result.brep.validate(level: .volumetric, tolerance: tolerance)
        let volume = try result.brep.volume(tolerance: tolerance)
        let repeatedVolume = try repeated.brep.volume(tolerance: tolerance)
        #expect(volume > tolerance.distance * tolerance.distance * tolerance.distance)
        #expect(volume == repeatedVolume)

        let exactSurface = try #require(result.brep.geometry.surfaces.values.first {
            guard case let .bSpline(surface) = $0 else { return false }
            return surface.uDegree == sourceCurve.degree && surface.vDegree == 1
        })
        guard case let .bSpline(surface) = exactSurface else {
            Issue.record("Expected an exact rational ruled B-spline surface.")
            return
        }
        #expect(surface.weights[0] == sourceCurve.weights)
        #expect(surface.weights[1] == sourceCurve.weights)
        let u = 0.37
        let v = 0.61
        let sourcePoint = try sourceCurve.point(at: u, tolerance: tolerance)
        let axis = try vector.normalized(tolerance: tolerance.distance)
        let expected = sourcePoint + axis * (distance * v)
        let actual = try surface.point(
            u: u,
            v: v,
            tolerance: tolerance
        )
        #expect(actual.isApproximatelyEqual(
            to: expected,
            tolerance: tolerance.distance
        ))

        for role in [
            GeneratedSubshapeRole.startFace,
            .endFace,
            .sideFace,
        ] {
            let id = SubshapeID(
                featureID: extrudeFeatureID,
                role: role.rawValue,
                ordinal: 0
            )
            #expect(result.subshapes[id] != nil)
            #expect(result.lineage[id]?.relation == .generated)
        }
    }
}
