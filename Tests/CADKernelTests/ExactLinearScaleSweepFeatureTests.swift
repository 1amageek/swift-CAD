import Testing
import CADKernel
import CADCore
import CADGeometry
import CADIR
import CADModeling
import CADTopology

@Suite("Exact linear-scale Sweep")
struct ExactLinearScaleSweepFeatureTests {
    private let tolerance = ModelingTolerance(
        distance: 1.0e-8,
        angle: 1.0e-10,
        relative: 1.0e-10
    )

    @Test(.timeLimit(.minutes(1)))
    func rationalSectionAndStraightPathProduceExactScaledTensorProductSolid() throws {
        let profileFeatureID = FeatureID()
        let pathFeatureID = FeatureID()
        let sweepFeatureID = FeatureID()
        let profileCurve = try rationalProfileCurve()
        let pathCurve = try rationalStraightPathCurve()
        let profile = try profile(
            featureID: profileFeatureID,
            curve: profileCurve
        )
        let path = try evaluatedCurve(
            featureID: pathFeatureID,
            curve: pathCurve,
            plane: .yz
        )
        let feature = FeatureNode(
            id: sweepFeatureID,
            operation: .sweep(SweepFeature(
                sections: [.profile(ProfileReference(
                    featureID: profileFeatureID
                ))],
                path: SweepPathReference(featureID: pathFeatureID),
                options: SweepOptions(
                    endScale: .constant(.scalar(0.4)),
                    alignment: .parallel
                )
            )),
            inputs: [
                FeatureInput(featureID: profileFeatureID, role: .profile),
                FeatureInput(featureID: pathFeatureID, role: .curve),
            ],
            outputs: [FeatureOutput(role: .body)]
        )
        let context = EvaluationContext(
            parameters: ResolvedParameterTable(),
            brep: BRepModel(),
            profiles: [profileFeatureID: [profile]],
            curves: [pathFeatureID: [path]],
            tolerance: tolerance
        )

        let evaluator = PlanarSweepFeatureEvaluator(sewer: DefaultBRepSewer())
        let result = try evaluator.evaluate(
            feature: feature,
            context: context
        )
        let repeated = try evaluator.evaluate(
            feature: feature,
            context: context
        )

        #expect(result.brep == repeated.brep)
        #expect(result.subshapes == repeated.subshapes)
        #expect(result.lineage == repeated.lineage)
        #expect(result.brep.bodies.count == 1)
        #expect(result.brep.shells.count == 1)
        #expect(result.brep.faces.count == 4)
        #expect(result.brep.edges.count == 6)
        #expect(result.brep.vertices.count == 4)
        #expect(result.brep.loops.values.allSatisfy {
            $0.coedges.allSatisfy { $0.surfaceParameterCurve != nil }
        })
        try result.brep.validate(level: .exact, tolerance: tolerance)

        let exactSurface = try #require(
            result.brep.geometry.surfaces.values.first {
                guard case let .bSpline(surface) = $0 else {
                    return false
                }
                return surface.uDegree == profileCurve.degree
                    && surface.vDegree == pathCurve.degree
            }
        )
        guard case let .bSpline(surface) = exactSurface else {
            Issue.record("Expected an exact linear-scale tensor-product surface.")
            return
        }
        for pathIndex in pathCurve.weights.indices {
            let expectedWeights = profileCurve.weights.map {
                $0 * pathCurve.weights[pathIndex]
            }
            #expect(surface.weights[pathIndex] == expectedWeights)
        }

        let u = 0.37
        let v = 0.61
        let profilePoint = try profileCurve.point(
            at: u,
            tolerance: tolerance
        )
        let pathPoint = try pathCurve.point(
            at: v,
            tolerance: tolerance
        )
        let scale = 1.0 - 0.6 * (pathPoint.z / 0.05)
        let expected = pathPoint + Vector3D(
            x: profilePoint.x,
            y: profilePoint.y,
            z: profilePoint.z
        ) * scale
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
            let subshapeID = SubshapeID(
                featureID: sweepFeatureID,
                role: role.rawValue,
                ordinal: 0
            )
            #expect(result.subshapes[subshapeID] != nil)
            #expect(result.lineage[subshapeID]?.relation == .generated)
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func openCurveSectionProducesExactScaledSheetWithoutCaps() throws {
        let sectionFeatureID = FeatureID()
        let pathFeatureID = FeatureID()
        let sweepFeatureID = FeatureID()
        let sectionCurve = BSplineCurve3D(
            degree: 2,
            knots: [0.0, 0.0, 0.0, 1.0, 1.0, 1.0],
            controlPoints: [
                Point3D(x: -0.01, y: 0.0, z: 0.0),
                Point3D(x: 0.0, y: 0.008, z: 0.0),
                Point3D(x: 0.01, y: 0.0, z: 0.0),
            ],
            weights: [1.0, 0.75, 1.0]
        )
        try sectionCurve.validate(tolerance: tolerance)
        let pathCurve = try rationalStraightPathCurve()
        let section = try evaluatedCurve(
            featureID: sectionFeatureID,
            curve: sectionCurve,
            plane: .xy
        )
        let path = try evaluatedCurve(
            featureID: pathFeatureID,
            curve: pathCurve,
            plane: .yz
        )
        let feature = FeatureNode(
            id: sweepFeatureID,
            operation: .sweep(SweepFeature(
                sections: [.curve(SweepCurveSectionReference(
                    featureID: sectionFeatureID
                ))],
                path: SweepPathReference(featureID: pathFeatureID),
                options: SweepOptions(
                    endScale: .constant(.scalar(1.5)),
                    alignment: .parallel,
                    resultKind: .sheet
                )
            )),
            inputs: [
                FeatureInput(featureID: sectionFeatureID, role: .curve),
                FeatureInput(featureID: pathFeatureID, role: .curve),
            ],
            outputs: [FeatureOutput(role: .sheet)]
        )
        let result = try PlanarSweepFeatureEvaluator(sewer: DefaultBRepSewer()).evaluate(
            feature: feature,
            context: EvaluationContext(
                parameters: ResolvedParameterTable(),
                brep: BRepModel(),
                profiles: [:],
                curves: [
                    sectionFeatureID: [section],
                    pathFeatureID: [path],
                ],
                tolerance: tolerance
            )
        )

        #expect(result.brep.bodies.count == 1)
        #expect(result.brep.bodies.values.first?.kind == .sheet)
        #expect(result.brep.faces.count == 1)
        #expect(result.brep.edges.count == 4)
        #expect(result.brep.vertices.count == 4)
        #expect(result.subshapes[SubshapeID(
            featureID: sweepFeatureID,
            role: GeneratedSubshapeRole.startFace.rawValue,
            ordinal: 0
        )] == nil)
        #expect(result.brep.loops.values.allSatisfy {
            $0.coedges.allSatisfy { $0.surfaceParameterCurve != nil }
        })
        let surfaceGeometry = try #require(
            result.brep.geometry.surfaces.values.first
        )
        guard case let .bSpline(surface) = surfaceGeometry else {
            Issue.record("Expected an exact scaled sheet B-spline surface.")
            return
        }
        let u = 0.41
        let v = 0.72
        let sectionPoint = try sectionCurve.point(
            at: u,
            tolerance: tolerance
        )
        let pathPoint = try pathCurve.point(
            at: v,
            tolerance: tolerance
        )
        let scale = 1.0 + 0.5 * (pathPoint.z / 0.05)
        let expected = pathPoint + Vector3D(
            x: sectionPoint.x,
            y: sectionPoint.y,
            z: sectionPoint.z
        ) * scale
        let actual = try surface.point(
            u: u,
            v: v,
            tolerance: tolerance
        )
        #expect(actual.isApproximatelyEqual(
            to: expected,
            tolerance: tolerance.distance
        ))
        try result.brep.validate(level: .exact, tolerance: tolerance)
    }

    private func rationalProfileCurve() throws -> BSplineCurve3D {
        let curve = BSplineCurve3D(
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
        try curve.validate(tolerance: tolerance)
        return curve
    }

    private func rationalStraightPathCurve() throws -> BSplineCurve3D {
        let curve = BSplineCurve3D(
            degree: 2,
            knots: [0.0, 0.0, 0.0, 1.0, 1.0, 1.0],
            controlPoints: [
                Point3D(x: 0.0, y: 0.0, z: 0.0),
                Point3D(x: 0.0, y: 0.0, z: 0.03),
                Point3D(x: 0.0, y: 0.0, z: 0.05),
            ],
            weights: [1.0, 0.75, 1.0]
        )
        try curve.validate(tolerance: tolerance)
        return curve
    }

    private func profile(
        featureID: FeatureID,
        curve: BSplineCurve3D
    ) throws -> Profile {
        let samples = try (0...8).map { index in
            try curve.point(
                at: Double(index) / 8.0,
                tolerance: tolerance
            )
        }
        return Profile(
            sourceFeatureID: featureID,
            plane: .xy,
            vertices: samples,
            boundarySegments: [
                .spline(ProfileSplineSegment(curve: curve)),
                .line(ProfileLineSegment(
                    start: try #require(samples.last),
                    end: try #require(samples.first)
                )),
            ]
        )
    }

    private func evaluatedCurve(
        featureID: FeatureID,
        curve: BSplineCurve3D,
        plane: SketchPlane
    ) throws -> EvaluatedCurve {
        let points = try [0.0, 0.5, 1.0].map {
            try curve.point(at: $0, tolerance: tolerance)
        }
        return EvaluatedCurve(
            sourceFeatureID: featureID,
            source: .generatedFeature,
            kind: .spline,
            points: points,
            plane: plane,
            exactCurve: .bSpline(curve),
            exactParameterDomain: curve.domain
        )
    }
}
