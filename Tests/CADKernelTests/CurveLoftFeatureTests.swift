import Testing
import CADCore
import CADGeometry
import CADIR
import CADTopology
import CADModeling

@Suite("Exact curve section Loft", .timeLimit(.minutes(1)))
struct CurveLoftFeatureTests {
    @Test(arguments: [LoftSurfaceMode.ruled, .smooth], [false, true])
    func openSpatialSectionsPreserveBothBoundaries(mode: LoftSurfaceMode, rational: Bool) throws {
        let source = BSplineCurve3D(degree: rational ? 3 : 1,
            knots: rational ? [0, 0, 0, 0, 1, 1, 1, 1] : [0, 0, 1, 1],
            controlPoints: rational
                ? [.origin, Point3D(x: 0.2, y: 0.1, z: 0.1),
                    Point3D(x: 0.8, y: 0.2, z: -0.1), Point3D(x: 1, y: 0, z: 0)]
                : [.origin, Point3D(x: 1, y: 0, z: 0)],
            weights: rational ? [1, 0.8, 1.2, 1] : nil)
        let translated = BSplineCurve3D(degree: source.degree, knots: source.knots,
            controlPoints: source.controlPoints.map { $0 + Vector3D(x: 0, y: 0, z: 2) },
            weights: source.weights)
        let sections = try [source, translated].map(section)
        let result = try evaluate(sections, mode: mode)
        try result.brep.validate(level: .exact, tolerance: .standard)
        #expect(result.brep.bodies.count == 1)
        #expect(result.brep.bodies.values.allSatisfy { $0.kind == .sheet })
        #expect(result.brep.faces.count == 1)
        #expect(result.brep.edges.count == 4)
        #expect(result.brep.vertices.count == 4)
        let surface = try #require(result.brep.geometry.surfaces.values.first)
        for u in [0.0, 0.17, 0.5, 0.83, 1.0] {
            for v in [0.0, 0.5, 1.0] {
                let expected = try source.point(at: u, tolerance: .standard) + Vector3D(x: 0, y: 0, z: 2 * v)
                let actual = try surface.point(u: u, v: v, tolerance: .standard)
                #expect((actual - expected).length < 1e-8)
            }
        }
    }

    @Test func unequalSpanCountsRetainAnOpenStrip() throws {
        let first = BSplineCurve3D(degree: 1, knots: [0, 0, 1, 1],
            controlPoints: [.origin, Point3D(x: 1, y: 0, z: 0)])
        let second = BSplineCurve3D(degree: 1, knots: [0, 0, 0.3, 1, 1],
            controlPoints: [Point3D(x: 0, y: 0, z: 1), Point3D(x: 0.3, y: 0, z: 1),
                Point3D(x: 1, y: 0, z: 1)])
        let result = try evaluate([section(first), section(second)], mode: .ruled)
        try result.brep.validate(level: .exact, tolerance: .standard)
        #expect(result.brep.faces.count == 2)
        #expect(result.brep.edges.count == 7)
        #expect(result.brep.vertices.count == 6)
    }

    @Test func solidCurveInputFailsBeforeConstruction() throws {
        let operation = LoftFeature(sections: [FeatureID(), FeatureID()].map {
            LoftSectionReference(section: .curve(CurveSectionReference(featureID: $0)))
        })
        #expect(throws: FeatureEvaluationError.self) { try operation.validate() }
    }

    @Test func closedCurveSectionsWrapOnlyTheirOwnBoundary() throws {
        let sections = try [0.0, 2.0].map { z in
            let curve = Curve3D.circle(Circle3D(center: Point3D(x: 0, y: 0, z: z), normal: .unitZ, radius: 1))
            let parameters = [0.0, Double.pi, 2 * Double.pi]
            return EvaluatedCurve(sourceFeatureID: FeatureID(), source: .generatedFeature, kind: .spline,
                points: try parameters.map { try curve.point(at: $0, tolerance: .standard) },
                isClosed: true, exactCurve: curve, exactParameterDomain: .closed(0, 2 * Double.pi),
                exactPointParameters: parameters)
        }
        let result = try evaluate(sections, mode: .ruled)
        try result.brep.validate(level: .exact, tolerance: .standard)
        #expect(result.brep.faces.count == 4)
        #expect(result.brep.edges.count == 12)
        #expect(result.brep.vertices.count == 8)
        #expect(result.brep.bodies.values.allSatisfy { $0.kind == .sheet })
    }

    private func section(_ curve: BSplineCurve3D) throws -> EvaluatedCurve {
        EvaluatedCurve(sourceFeatureID: FeatureID(), source: .generatedFeature, kind: .spline,
            points: [try curve.point(at: 0, tolerance: .standard), try curve.point(at: 1, tolerance: .standard)],
            exactCurve: .bSpline(curve), exactParameterDomain: .closed(0, 1), exactPointParameters: [0, 1])
    }

    @Test(arguments: [LoftSurfaceMode.ruled, .smooth], [false, true])
    func mixedProfileAndClosedCurveUseExactBoundaries(mode: LoftSurfaceMode, reversedOrder: Bool) throws {
        let profileID = FeatureID()
        let curveID = FeatureID()
        let base = Curve3D.circle(Circle3D(center: .origin, normal: .unitZ, radius: 1))
        let start = try base.point(at: 0, tolerance: .standard)
        let profile = Profile(sourceFeatureID: profileID, plane: .xy,
            vertices: try [0.0, .pi / 2, .pi, .pi * 1.5].map { try base.point(at: $0, tolerance: .standard) },
            boundarySegments: [.circularArc(ProfileCircularArcSegment(center: .origin, normal: .unitZ,
                radius: 1, start: start, end: start, sweepAngle: 2 * .pi))])
        let exact = Curve3D.circle(Circle3D(center: Point3D(x: 0, y: 0, z: 2), normal: .unitZ, radius: 1))
        let parameters = [0.0, Double.pi, 2 * .pi]
        var curve = EvaluatedCurve(sourceFeatureID: curveID, source: .generatedFeature, kind: .spline,
            points: try parameters.map { try exact.point(at: $0, tolerance: .standard) }, isClosed: true,
            exactCurve: exact, exactParameterDomain: .closed(0, 2 * .pi), exactPointParameters: parameters)
        var sections = [LoftSectionReference(section: .profile(ProfileReference(featureID: profileID)),
            profileDirection: reversedOrder ? .reversed : .forward),
            LoftSectionReference(section: .curve(CurveSectionReference(featureID: curveID, isReversed: reversedOrder)))]
        if reversedOrder { sections.reverse() }
        let feature = FeatureNode(operation: .loft(LoftFeature(sections: sections,
            options: LoftOptions(resultKind: .sheet, surfaceMode: mode))),
            inputs: sections.map { FeatureInput(featureID: $0.featureID, role: $0.section.inputRole) },
            outputs: [FeatureOutput(role: .sheet)])
        func evaluate(_ curve: EvaluatedCurve) throws -> EvaluationResult {
            try LoftFeatureEvaluator().evaluate(feature: feature,
                context: EvaluationContext(parameters: ResolvedParameterTable(), brep: BRepModel(),
                    profiles: [profileID: [profile]], curves: [curveID: [curve]], tolerance: .standard))
        }
        let result = try evaluate(curve)
        try result.brep.validate(level: .exact, tolerance: .standard)
        #expect(result.brep.faces.count == 4)
        #expect(result.brep.bodies.values.allSatisfy { $0.kind == .sheet })
        for surface in result.brep.geometry.surfaces.values {
            for u in [0.17, 0.5, 0.83] {
                for v in [0.0, 0.5, 1.0] {
                    let point = try surface.point(u: u, v: v, tolerance: .standard)
                    #expect(abs(point.x * point.x + point.y * point.y - 1) < 1e-8)
                    #expect(abs(point.z - (reversedOrder ? 2 * (1 - v) : 2 * v)) < 1e-8)
                }
            }
        }
        curve.isClosed = false
        #expect(throws: FeatureEvaluationError.self) { try evaluate(curve) }
    }

    private func evaluate(_ sections: [EvaluatedCurve], mode: LoftSurfaceMode) throws -> EvaluationResult {
        let operation = LoftFeature(sections: sections.map {
            LoftSectionReference(section: .curve(CurveSectionReference(featureID: $0.sourceFeatureID)))
        }, options: LoftOptions(resultKind: .sheet, surfaceMode: mode))
        let feature = FeatureNode(operation: .loft(operation),
            inputs: sections.map { FeatureInput(featureID: $0.sourceFeatureID, role: .curve) },
            outputs: [FeatureOutput(role: .sheet)])
        let context = EvaluationContext(parameters: ResolvedParameterTable(), brep: BRepModel(),
            profiles: [:], curves: Dictionary(uniqueKeysWithValues: sections.map { ($0.sourceFeatureID, [$0]) }),
            tolerance: .standard)
        return try LoftFeatureEvaluator().evaluate(feature: feature, context: context)
    }
}
