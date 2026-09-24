import Testing
import CADCore
import CADGeometry
import CADIR
import CADTopology
import CADModeling

@Suite("Exact curve section Loft", .timeLimit(.minutes(1)))
struct CurveLoftFeatureTests {
    @Test(.timeLimit(.minutes(1)), arguments: [false, true])
    func nonincidentLoftSidesRequireSeparation(crosses: Bool) throws {
        let positions: [(Double, Double)] = crosses
            ? [(0, 0), (1, 1), (0, 1), (1, 0)]
            : [(0, 0), (1, 1), (2, 1), (3, 0)]
        let sections = try positions.map { x, z in
            try section(BSplineCurve3D(degree: 1, knots: [0, 0, 1, 1],
                controlPoints: [Point3D(x: x, y: 0, z: z), Point3D(x: x, y: 1, z: z)]))
        }
        if crosses {
            do {
                _ = try evaluate(sections, mode: .ruled)
                Issue.record("Individually regular strips must not admit an intersecting Loft.")
            } catch let error as KernelError {
                #expect(error.code == .resourceLimitExceeded)
            }
        } else {
            let result = try evaluate(sections, mode: .ruled)
            #expect(result.brep.faces.count == 3)
            try result.brep.validate(level: .exact, tolerance: .standard)
        }
    }

    @Test func transfiniteLoftDoesNotDiscardNearUnitBoundaryWeights() throws {
        let lower = BSplineCurve3D(degree: 2, knots: [0, 0, 0, 1, 1, 1],
            controlPoints: [.origin, Point3D(x: 1, y: 0, z: 1e9), Point3D(x: 2, y: 0, z: 0)],
            weights: [1, 1 + 5e-13, 1])
        let upper = BSplineCurve3D(degree: 1, knots: [0, 0, 1, 1],
            controlPoints: [Point3D(x: 0, y: 1, z: 0), Point3D(x: 2, y: 1, z: 0)])
        func connector(_ x: Double) -> BSplineCurve3D {
            BSplineCurve3D(degree: 2, knots: [0, 0, 0, 1, 1, 1],
                controlPoints: [Point3D(x: x, y: 0, z: 0), Point3D(x: x, y: 0.5, z: 0),
                    Point3D(x: x, y: 1, z: 0)])
        }
        let surface = try ExactLoftSideSurfaceBuilder().build(vMinimumBoundary: lower,
            vMaximumBoundary: upper, uMinimumBoundary: connector(0), uMaximumBoundary: connector(2),
            tolerance: .standard)
        let actual = try surface.point(u: 0.5, v: 0, tolerance: .standard)
        #expect(try (actual - lower.point(at: 0.5, tolerance: .standard)).length < 1e-6)
        #expect(abs(actual.z - 5e8) > 1e-5)
    }

    @Test func opposingOpenSectionsRejectTheInteriorCollapsedRow() throws {
        let first = try section(BSplineCurve3D(degree: 1, knots: [0, 0, 1, 1],
            controlPoints: [.origin, Point3D(x: 1, y: 0, z: 0)]))
        let second = try section(BSplineCurve3D(degree: 1, knots: [0, 0, 1, 1],
            controlPoints: [Point3D(x: 1, y: 0, z: 1), Point3D(x: 0, y: 0, z: 1)]))
        #expect(throws: KernelError.self) { try evaluate([first, second], mode: .ruled) }
    }

    @Test(arguments: [false, true])
    func isolatedGuideContactDoesNotDependOnParallelMidpointTangents(stationaryEndpoints: Bool) throws {
        let x = [0.0, 0.25, 0.0, 0.25]
        let y = [0.0, 4.0 / 3, 4.0 / 3, 0.0]
        let sections = try [0.0, 1.0, 2.0].map { z in
            try section(BSplineCurve3D(degree: 3, knots: [0, 0, 0, 0, 1, 1, 1, 1],
                controlPoints: x.indices.map { index in
                    let fraction = Double(index) / 3
                    return Point3D(x: x[index], y: (z - 1) * y[index], z: z + 0.1 * fraction)
                }))
        }
        let guide = try section(stationaryEndpoints
            ? BSplineCurve3D(degree: 3, knots: [0, 0, 0, 0, 1, 1, 1, 1],
                controlPoints: [.origin, .origin, Point3D(x: 0, y: 0, z: 2), Point3D(x: 0, y: 0, z: 2)])
            : BSplineCurve3D(degree: 1, knots: [0, 0, 1, 1],
                controlPoints: [.origin, Point3D(x: 0, y: 0, z: 2)]))
        let result = try evaluate(sections, mode: .ruled, guides: [guide])
        try result.brep.validate(level: .exact, tolerance: .standard)
        #expect(result.brep.faces.count == 2)
        #expect(result.brep.vertices.values.contains { ($0.point - Point3D(x: 0, y: 0, z: 1)).length < 1e-8 })
        for surface in result.brep.geometry.surfaces.values {
            let level = try surface.point(u: 0, v: 0, tolerance: .standard).z
            for u in [0.25, 0.5, 0.75] {
                for v in [0.25, 0.5, 0.75] {
                    let expected = Point3D(x: 0.75 * u * (1 - u) * (1 - u) + 0.25 * u * u * u,
                        y: (level + v - 1) * 4 * u * (1 - u), z: level + v + 0.1 * u)
                    #expect(try (surface.point(u: u, v: v, tolerance: .standard) - expected).length < 1e-8)
                }
            }
            for v in [0.0, 0.5, 1.0] {
                let point = try surface.point(u: 0, v: v, tolerance: .standard)
                #expect(abs(point.x) < 1e-8 && abs(point.y) < 1e-8)
            }
        }
    }

    @Test func transverseGuideContactDoesNotAuthorizeASingularRuledPatch() throws {
        let x = [0.0, 0.25, 0.0, 0.25]
        let sections = try [0.0, 1.0, 2.0].map { z in
            try section(BSplineCurve3D(degree: 3, knots: [0, 0, 0, 0, 1, 1, 1, 1],
                controlPoints: x.indices.map { index in
                    let fraction = Double(index) / 3
                    return Point3D(x: x[index], y: (z - 1) * fraction, z: z + 0.1 * fraction)
                }))
        }
        let guide = try section(BSplineCurve3D(degree: 1, knots: [0, 0, 1, 1],
            controlPoints: [.origin, Point3D(x: 0, y: 0, z: 2)]))
        // The second patch loses rank at u=0.5, v=0.05, away from the guide.
        #expect(throws: KernelError.self) { try evaluate(sections, mode: .ruled, guides: [guide]) }
    }

    @Test func guideMayLieInTheIntermediateSectionSupportPlane() throws {
        var sections = try [0.0, 1.0, 2.0].map { z in
            try section(BSplineCurve3D(degree: 1, knots: [0, 0, 1, 1],
                controlPoints: [Point3D(x: 0, y: 0, z: z), Point3D(x: 1, y: 0, z: z)]))
        }
        sections[1].plane = .zx
        let guide = try section(BSplineCurve3D(degree: 1, knots: [0, 0, 1, 1],
            controlPoints: [.origin, Point3D(x: 0, y: 0, z: 2)]))
        let result = try evaluate(sections, mode: .ruled, guides: [guide])
        try result.brep.validate(level: .exact, tolerance: .standard)
        #expect(result.brep.faces.count == 2)
        #expect(result.brep.vertices.values.contains { ($0.point - Point3D(x: 0, y: 0, z: 1)).length < 1e-8 })
    }

    @Test(arguments: [false, true])
    func spatialIntermediateGuideContactsRequireThreeDimensionalAgreement(separated: Bool) throws {
        let sections = try [0.0, 1.0, 2.0].map { z in
            let offset = separated && z == 1 ? 0.1 : 0.0
            return try section(BSplineCurve3D(degree: 3, knots: [0, 0, 0, 0, 1, 1, 1, 1],
                controlPoints: [Point3D(x: 0, y: offset, z: z), Point3D(x: 1, y: 1 + offset, z: z + 0.2),
                    Point3D(x: 2, y: -1 + offset, z: z - 0.2), Point3D(x: 3, y: offset, z: z)]))
        }
        let guide = try section(BSplineCurve3D(degree: 1, knots: [0, 0, 1, 1],
            controlPoints: [.origin, Point3D(x: 0, y: 0, z: 2)]))
        if separated {
            do {
                _ = try evaluate(sections, mode: .ruled, guides: [guide])
                Issue.record("A projected crossing separated in 3D must not be admitted.")
            } catch let error as KernelError {
                #expect(error.code == .intersectionFailure)
            }
        } else {
            let result = try evaluate(sections, mode: .ruled, guides: [guide])
            try result.brep.validate(level: .exact, tolerance: .standard)
            #expect(result.brep.faces.count == 2)
            #expect(result.brep.vertices.values.contains { ($0.point - Point3D(x: 0, y: 0, z: 1)).length < 1e-8 })
            let repeated = try section(BSplineCurve3D(degree: 1, knots: [0, 0, 0.25, 0.5, 0.75, 1, 1],
                controlPoints: [0.0, 1.2, 0.8, 1.2, 2.0].map { Point3D(x: 0, y: 0, z: $0) }))
            do {
                _ = try evaluate(sections, mode: .ruled, guides: [repeated])
                Issue.record("Repeated visits to the same section point are distinct guide contacts.")
            } catch let error as KernelError {
                #expect(error.code == .ambiguousSelection)
            }
        }
    }

    @Test(arguments: [false, true])
    func closedCurveSeamUsesOriginalSampleBeforeReversal(reversed: Bool) throws {
        let parameters = [0.0, Double.pi / 4, Double.pi, 2 * Double.pi]
        let sections = try [0.0, 2.0].map { z in
            let exact = Curve3D.circle(Circle3D(center: Point3D(x: 0, y: 0, z: z), normal: .unitZ, radius: 1))
            return EvaluatedCurve(sourceFeatureID: FeatureID(), source: .generatedFeature, kind: .spline,
                points: try parameters.map { try exact.point(at: $0, tolerance: .standard) },
                isClosed: true, exactCurve: exact, exactParameterDomain: .closed(0, 2 * Double.pi),
                exactPointParameters: parameters)
        }
        let result = try evaluate(sections, mode: .ruled, startSampleIndex: 1, reversed: reversed)
        try result.brep.validate(level: .exact, tolerance: .standard)
        let expected = sections[0].points[1]
        let surface = try #require(result.brep.geometry.surfaces.values.first {
            try $0.point(u: 0, v: 0, tolerance: .standard).isApproximatelyEqual(to: expected, tolerance: 1e-8)
        })
        for v in [0.0, 0.3, 0.7, 1.0] {
            #expect(try (surface.point(u: 0, v: v, tolerance: .standard)
                - (expected + Vector3D(x: 0, y: 0, z: 2 * v))).length < 1e-8)
        }
        #expect(throws: FeatureEvaluationError.self) {
            try evaluate(sections, mode: .ruled, startSampleIndex: Int.max)
        }
        var invalid = sections
        invalid[0].points[1] = Point3D(x: 100, y: 100, z: 100)
        #expect(throws: KernelError.self) { try evaluate(invalid, mode: .ruled, startSampleIndex: 1) }
    }

    @Test func openCurveSeamCannotWrapTheBoundary() throws {
        let sections = try [0.0, 2.0].map { z in
            try section(BSplineCurve3D(degree: 1, knots: [0, 0, 1, 1],
                controlPoints: [Point3D(x: 0, y: 0, z: z), Point3D(x: 1, y: 0, z: z)]))
        }
        _ = try evaluate(sections, mode: .ruled, startSampleIndex: 0)
        _ = try evaluate(sections, mode: .ruled, startSampleIndex: 1, reversed: true)
        #expect(throws: KernelError.self) { try evaluate(sections, mode: .ruled, startSampleIndex: 1) }
        #expect(throws: KernelError.self) { try evaluate(sections, mode: .ruled, startSampleIndex: 0, reversed: true) }
        #expect(throws: KernelError.self) {
            try evaluate(sections, mode: .ruled, startSampleIndex: 0, parameterDomain: .closed(0.2, 0.8))
        }
    }

    @Test(arguments: [false, true])
    func curveLoftUsesExactGuideAtInteriorOrEnd(endpoint: Bool) throws {
        let sections = try [0.0, 2.0].map { z in
            try section(BSplineCurve3D(degree: 1, knots: [0, 0, 1, 1],
                controlPoints: [Point3D(x: 0, y: 0, z: z), Point3D(x: 1, y: 0, z: z)]))
        }
        let exactGuide = BSplineCurve3D(degree: 2, knots: [0, 0, 0, 1, 1, 1],
            controlPoints: [Point3D(x: endpoint ? 1 : 0.25, y: 0, z: 0),
                Point3D(x: endpoint ? 1 : 0.4, y: 0.3, z: 1),
                Point3D(x: endpoint ? 1 : 0.7, y: 0, z: 2)])
        let guide = try section(exactGuide)
        let result = try evaluate(sections, mode: .ruled, guides: [guide])
        try result.brep.validate(level: .exact, tolerance: .standard)
        #expect(result.brep.faces.count == (endpoint ? 1 : 2))
        let surfaces = Array(result.brep.geometry.surfaces.values)
        for t in [0.0, 0.2, 0.5, 0.8, 1.0] {
            let expected = try exactGuide.point(at: t, tolerance: .standard)
            let contacts = try surfaces.flatMap { surface in
                try [0.0, 1.0].map { try surface.point(u: $0, v: t, tolerance: .standard) }
            }
            #expect(contacts.filter { ($0 - expected).length < 1e-8 }.count == (endpoint ? 1 : 2))
        }
    }

    @Test(arguments: [false, true])
    func curveLoftRejectsInconsistentGuideCorrespondence(endpointMismatch: Bool) throws {
        let sections = try [0.0, 2.0].map { z in
            try section(BSplineCurve3D(degree: 1, knots: [0, 0, 1, 1],
                controlPoints: [Point3D(x: 0, y: 0, z: z), Point3D(x: 1, y: 0, z: z)]))
        }
        let pairs: [(Double, Double)] = endpointMismatch ? [(1, 0.7)] : [(0.25, 0.7), (0.7, 0.25)]
        let guides = try pairs.map { start, end in
            try section(BSplineCurve3D(degree: 1, knots: [0, 0, 1, 1],
                controlPoints: [Point3D(x: start, y: 0, z: 0), Point3D(x: end, y: 0, z: 2)]))
        }
        do {
            _ = try evaluate(sections, mode: .ruled, guides: guides)
            Issue.record("Inconsistent guide correspondence must not publish a Loft.")
        } catch let error as KernelError {
            #expect(error.message.contains(endpointMismatch ? "endpoint or interior" : "consistently ordered"))
        }
    }

    @Test func guideContactsUseExactSpatialBoundariesAndRejectAmbiguity() throws {
        let first = BSplineCurve3D(degree: 3, knots: [0, 0, 0, 0, 1, 1, 1, 1],
            controlPoints: [Point3D(x: 0, y: 0, z: 0), Point3D(x: 1, y: 0, z: 0.5),
                Point3D(x: 1, y: 1, z: -0.5), Point3D(x: 2, y: 1, z: 0)])
        let second = BSplineCurve3D(degree: first.degree, knots: first.knots,
            controlPoints: first.controlPoints.map { $0 + Vector3D(x: 0, y: 0, z: 2) })
        let boundaries = try [first, second].map {
            ExactLoftGuideSection(loops: [[try ExactBSplineCurveSpan(curve: $0, tolerance: .standard)]])
        }
        let guide = try section(BSplineCurve3D(degree: 2, knots: [0, 0, 0, 1, 1, 1],
            controlPoints: [Point3D(x: 0, y: 0, z: 2), Point3D(x: -0.5, y: 0, z: 1), .origin]))
        let context = EvaluationContext(parameters: ResolvedParameterTable(), brep: BRepModel(),
            profiles: [:], curves: [guide.sourceFeatureID: [guide]], tolerance: .standard)
        let references = [LoftGuideReference(featureID: guide.sourceFeatureID)]
        let resolver = ExactLoftGuideCurveResolver()
        let resolved = try resolver.resolve(guides: references, sections: boundaries, context: context)
        let result = try #require(resolved.first)
        #expect(result.sectionPoints == [.origin, Point3D(x: 0, y: 0, z: 2)])
        #expect(try #require(result.sectionParameters.first) < #require(result.sectionParameters.last))
        #expect(try result.curve.point(at: 0.5, tolerance: .standard).x < 0)
        let ambiguous = boundaries.map { ExactLoftGuideSection(loops: $0.loops + $0.loops) }
        do {
            _ = try resolver.resolve(guides: references, sections: ambiguous, context: context)
            Issue.record("Guide contact on multiple boundary loops must be rejected.")
        } catch let error as KernelError {
            #expect(error.code == .ambiguousSelection)
        }
        let coincidentGuide = try section(first)
        let coincidentContext = EvaluationContext(parameters: ResolvedParameterTable(), brep: BRepModel(),
            profiles: [:], curves: [coincidentGuide.sourceFeatureID: [coincidentGuide]], tolerance: .standard)
        do {
            _ = try resolver.resolve(guides: [LoftGuideReference(featureID: coincidentGuide.sourceFeatureID)],
                sections: [boundaries[0], boundaries[0]], context: coincidentContext)
            Issue.record("A guide with both valid traversal directions must be rejected.")
        } catch let error as KernelError {
            #expect(error.code == .ambiguousSelection)
        }
    }

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

    private func evaluate(_ sections: [EvaluatedCurve], mode: LoftSurfaceMode,
        guides: [EvaluatedCurve] = [], startSampleIndex: Int? = nil, reversed: Bool = false,
        parameterDomain: ParameterDomain? = nil) throws -> EvaluationResult {
        let operation = LoftFeature(sections: sections.map {
            LoftSectionReference(section: .curve(CurveSectionReference(featureID: $0.sourceFeatureID,
                parameterDomain: parameterDomain, isReversed: reversed)),
                startSampleIndex: startSampleIndex)
        }, guides: guides.map { LoftGuideReference(featureID: $0.sourceFeatureID) },
            options: LoftOptions(resultKind: .sheet, surfaceMode: mode))
        let inputs = sections + guides
        let feature = FeatureNode(operation: .loft(operation),
            inputs: inputs.map { FeatureInput(featureID: $0.sourceFeatureID, role: .curve) },
            outputs: [FeatureOutput(role: .sheet)])
        let context = EvaluationContext(parameters: ResolvedParameterTable(), brep: BRepModel(),
            profiles: [:], curves: Dictionary(uniqueKeysWithValues: inputs.map { ($0.sourceFeatureID, [$0]) }),
            tolerance: .standard)
        return try LoftFeatureEvaluator().evaluate(feature: feature, context: context)
    }
}
