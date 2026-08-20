import Testing
import CADKernel
import CADCore
import CADGeometry
import CADIR
import CADModeling
import CADTopology

@Suite("Exact translational sweep")
struct ExactTranslationalSweepFeatureTests {
    private let tolerance = ModelingTolerance(
        distance: 1.0e-8,
        angle: 1.0e-10
    )

    @Test(.timeLimit(.minutes(1)))
    func rationalSectionAndPathProduceExactTensorProductSolid() throws {
        let profileFeatureID = FeatureID()
        let pathFeatureID = FeatureID()
        let sweepFeatureID = FeatureID()
        let profileCurve = try rationalProfileCurve()
        let profile = try profile(
            featureID: profileFeatureID,
            curve: profileCurve
        )
        let pathCurve = try rationalPathCurve(isReversedInSpace: false)
        let path = try evaluatedCurve(
            featureID: pathFeatureID,
            curve: pathCurve,
            plane: .zx
        )
        let feature = sweepFeature(
            id: sweepFeatureID,
            section: .profile(ProfileReference(featureID: profileFeatureID)),
            pathFeatureID: pathFeatureID,
            resultKind: .solid
        )
        let context = EvaluationContext(
            parameters: ResolvedParameterTable(),
            brep: BRepModel(),
            profiles: [profileFeatureID: [profile]],
            curves: [pathFeatureID: [path]],
            tolerance: tolerance
        )

        let result = try PlanarSweepFeatureEvaluator(sewer: DefaultBRepSewer()).evaluate(
            feature: feature,
            context: context
        )
        let repeated = try PlanarSweepFeatureEvaluator(sewer: DefaultBRepSewer()).evaluate(
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

        let exactSurface = try #require(result.brep.geometry.surfaces.values.first {
            guard case let .bSpline(surface) = $0 else { return false }
            return surface.uDegree == profileCurve.degree
                && surface.vDegree == pathCurve.degree
        })
        guard case let .bSpline(surface) = exactSurface else {
            Issue.record("Expected an exact tensor-product B-spline surface.")
            return
        }
        #expect(surface.weights.count == pathCurve.weights.count)
        for pathIndex in pathCurve.weights.indices {
            let expectedWeights = profileCurve.weights.map {
                $0 * pathCurve.weights[pathIndex]
            }
            #expect(surface.weights[pathIndex] == expectedWeights)
        }
        let u = 0.37
        let v = 0.61
        let profilePoint = try profileCurve.point(at: u, tolerance: tolerance)
        let pathPoint = try pathCurve.point(at: v, tolerance: tolerance)
        let expected = profilePoint + (pathPoint - Point3D.origin)
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
                featureID: sweepFeatureID,
                role: role.rawValue,
                ordinal: 0
            )
            #expect(result.subshapes[id] != nil)
            #expect(result.lineage[id]?.relation == .generated)
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func negativeNormalAdvancePreservesOutwardCapOrientation() throws {
        let profileFeatureID = FeatureID()
        let pathFeatureID = FeatureID()
        let sweepFeatureID = FeatureID()
        let profileCurve = try rationalProfileCurve()
        let profile = try profile(
            featureID: profileFeatureID,
            curve: profileCurve
        )
        let pathCurve = try rationalPathCurve(isReversedInSpace: true)
        let path = try evaluatedCurve(
            featureID: pathFeatureID,
            curve: pathCurve,
            plane: .zx
        )
        let result = try PlanarSweepFeatureEvaluator(sewer: DefaultBRepSewer()).evaluate(
            feature: sweepFeature(
                id: sweepFeatureID,
                section: .profile(ProfileReference(featureID: profileFeatureID)),
                pathFeatureID: pathFeatureID,
                resultKind: .solid
            ),
            context: EvaluationContext(
                parameters: ResolvedParameterTable(),
                brep: BRepModel(),
                profiles: [profileFeatureID: [profile]],
                curves: [pathFeatureID: [path]],
                tolerance: tolerance
            )
        )

        let startFace = try face(
            role: .startFace,
            featureID: sweepFeatureID,
            result: result
        )
        let endFace = try face(
            role: .endFace,
            featureID: sweepFeatureID,
            result: result
        )
        let startPlane = try plane(for: startFace, in: result.brep)
        let endPlane = try plane(for: endFace, in: result.brep)
        let startNormal = startFace.orientation == .forward
            ? startPlane.normal
            : -startPlane.normal
        let endNormal = endFace.orientation == .forward
            ? endPlane.normal
            : -endPlane.normal
        #expect(startNormal.dot(.unitZ) >= 1.0 - tolerance.angle)
        #expect(endNormal.dot(.unitZ) <= -1.0 + tolerance.angle)
        try result.brep.validate(level: .exact, tolerance: tolerance)
    }

    @Test(.timeLimit(.minutes(1)))
    func exactOpenCurveSectionProducesUncappedSheet() throws {
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
        let section = try evaluatedCurve(
            featureID: sectionFeatureID,
            curve: sectionCurve,
            plane: .xy
        )
        let pathCurve = try rationalPathCurve(isReversedInSpace: false)
        let path = try evaluatedCurve(
            featureID: pathFeatureID,
            curve: pathCurve,
            plane: .zx
        )
        let result = try PlanarSweepFeatureEvaluator(sewer: DefaultBRepSewer()).evaluate(
            feature: sweepFeature(
                id: sweepFeatureID,
                section: .curve(SweepCurveSectionReference(
                    featureID: sectionFeatureID
                )),
                pathFeatureID: pathFeatureID,
                resultKind: .sheet
            ),
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
        #expect(result.subshapes[SubshapeID(
            featureID: sweepFeatureID,
            role: GeneratedSubshapeRole.startFace.rawValue,
            ordinal: 0
        )] == nil)
        #expect(result.brep.geometry.surfaces.values.allSatisfy {
            if case .bSpline = $0 { return true }
            return false
        })
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

    private func rationalPathCurve(
        isReversedInSpace: Bool
    ) throws -> BSplineCurve3D {
        let forward = [
            Point3D(x: 0.0, y: 0.0, z: 0.0),
            Point3D(x: 0.02, y: 0.0, z: 0.03),
            Point3D(x: 0.03, y: 0.0, z: 0.05),
        ]
        let curve = BSplineCurve3D(
            degree: 2,
            knots: [0.0, 0.0, 0.0, 1.0, 1.0, 1.0],
            controlPoints: isReversedInSpace
                ? Array(forward.reversed())
                : forward,
            weights: isReversedInSpace
                ? Array([1.0, 0.75, 1.0].reversed())
                : [1.0, 0.75, 1.0]
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

    private func sweepFeature(
        id: FeatureID,
        section: SweepSectionReference,
        pathFeatureID: FeatureID,
        resultKind: SweepResultKind
    ) -> FeatureNode {
        FeatureNode(
            id: id,
            operation: .sweep(SweepFeature(
                sections: [section],
                path: SweepPathReference(featureID: pathFeatureID),
                options: SweepOptions(
                    alignment: .parallel,
                    resultKind: resultKind
                )
            )),
            inputs: [
                FeatureInput(featureID: section.featureID, role: section.inputRole),
                FeatureInput(featureID: pathFeatureID, role: .curve),
            ],
            outputs: [FeatureOutput(
                role: resultKind == .solid ? .body : .sheet
            )]
        )
    }

    private func face(
        role: GeneratedSubshapeRole,
        featureID: FeatureID,
        result: EvaluationResult
    ) throws -> Face {
        let subshapeID = SubshapeID(
            featureID: featureID,
            role: role.rawValue,
            ordinal: 0
        )
        guard case let .face(faceID) = result.subshapes[subshapeID] else {
            throw TopologyError.missingReference(
                "Missing semantic exact sweep face \(subshapeID)."
            )
        }
        return try #require(result.brep.faces[faceID])
    }

    private func plane(
        for face: Face,
        in brep: BRepModel
    ) throws -> Plane3D {
        guard case let .plane(plane) = brep.geometry.surfaces[face.surfaceID] else {
            throw TopologyError.invalidFaceSurface(face.id)
        }
        return plane
    }
}
