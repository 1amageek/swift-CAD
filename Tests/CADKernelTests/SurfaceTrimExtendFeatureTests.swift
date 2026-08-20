import Testing
import CADCore
import CADGeometry
import CADIR
import CADModeling
import CADTopology
@testable import CADKernel

@Suite("Exact surface trim and extend")
struct SurfaceTrimExtendFeatureTests {
    @Test(
        .timeLimit(.minutes(1)),
        arguments: exactSurfaceCases
    )
    func trimsEveryExactSurfaceRepresentation(
        surfaceCase: ExactSurfaceTrimCase
    ) throws {
        let sourceID = FeatureID()
        let featureID = FeatureID()
        let source = try exactSurfaceSheet(
            featureID: sourceID,
            surface: surfaceCase.surface,
            bounds: surfaceCase.sourceBounds
        )
        let result = try SurfaceTrimFeatureEvaluator(sewer: DefaultBRepSewer()).evaluate(
            feature: FeatureNode(
                id: featureID,
                operation: .surfaceTrim(trimFeature(
                    target: try surfaceOperationTarget(
                        featureID: sourceID,
                        fixture: source
                    ),
                    bounds: surfaceCase.trimmedBounds
                )),
                inputs: [FeatureInput(featureID: sourceID, role: .target)],
                outputs: [FeatureOutput(role: .sheet)]
            ),
            context: context(source)
        )

        try result.brep.validate(level: .exact, tolerance: .standard)
        let face = try #require(result.brep.faces.values.first)
        #expect(result.brep.geometry.surfaces[face.surfaceID] == surfaceCase.surface)
        #expect(result.brep.edges.values.allSatisfy { edge in
            guard case let .surfaceLift(lift) = result.brep.geometry.curves[edge.curveID] else {
                return false
            }
            return lift.surface == surfaceCase.surface
                && edge.trim == CurveTrim(startParameter: 0.0, endParameter: 1.0)
        })
        #expect(result.brep.loops.values.allSatisfy { loop in
            loop.coedges.allSatisfy { coedge in
                switch coedge.surfaceParameterCurve {
                case .constantU, .constantV:
                    true
                case .none,
                     .affine,
                     .harmonic,
                     .sphericalGreatCircle,
                     .polyline,
                     .bSpline,
                     .certifiedImplicit,
                     .certifiedAnalyticImplicit,
                     .certifiedAnalyticPair,
                     .projectedAnalytic,
                     .periodicTranslation:
                    false
                }
            }
        })
        let expectedCorners = try corners(
            on: surfaceCase.surface,
            bounds: surfaceCase.trimmedBounds
        )
        let actualCorners = Array(result.brep.vertices.values.map(\.point))
        #expect(actualCorners.count == expectedCorners.count)
        #expect(expectedCorners.allSatisfy { expected in
            actualCorners.contains { actual in
                actual.isApproximatelyEqual(to: expected, tolerance: 1.0e-12)
            }
        })
        #expect(result.lineage.values.filter { $0.relation == .preserved }.count == 2)
        #expect(result.lineage.values.filter { $0.relation == .generated }.count
            == result.brep.edges.count + result.brep.vertices.count)
        #expect(result.removedSubshapeIDs == Set(source.subshapes.entries.keys))
    }

    @Test(
        .timeLimit(.minutes(1)),
        arguments: exactSurfaceCases
    )
    func extendsEveryExactSurfaceRepresentationWithinItsCanonicalDomain(
        surfaceCase: ExactSurfaceTrimCase
    ) throws {
        let sourceID = FeatureID()
        let source = try exactSurfaceSheet(
            featureID: sourceID,
            surface: surfaceCase.surface,
            bounds: surfaceCase.trimmedBounds
        )
        let result = try SurfaceExtendFeatureEvaluator(sewer: DefaultBRepSewer()).evaluate(
            feature: FeatureNode(
                operation: .surfaceExtend(SurfaceExtendFeature(
                    target: try surfaceOperationTarget(
                        featureID: sourceID,
                        fixture: source
                    ),
                    uDomain: .closed(
                        surfaceCase.sourceBounds.lowerU,
                        surfaceCase.sourceBounds.upperU
                    ),
                    vDomain: .closed(
                        surfaceCase.sourceBounds.lowerV,
                        surfaceCase.sourceBounds.upperV
                    )
                )),
                inputs: [FeatureInput(featureID: sourceID, role: .target)],
                outputs: [FeatureOutput(role: .sheet)]
            ),
            context: context(source)
        )

        try result.brep.validate(level: .exact, tolerance: .standard)
        let face = try #require(result.brep.faces.values.first)
        #expect(result.brep.geometry.surfaces[face.surfaceID] == surfaceCase.surface)
        #expect(result.brep.edges.values.allSatisfy { edge in
            guard case let .surfaceLift(lift) = result.brep.geometry.curves[edge.curveID] else {
                return false
            }
            return lift.surface == surfaceCase.surface
                && edge.trim == CurveTrim(startParameter: 0.0, endParameter: 1.0)
        })
        let expectedCorners = try corners(
            on: surfaceCase.surface,
            bounds: surfaceCase.sourceBounds
        )
        let actualCorners = Array(result.brep.vertices.values.map(\.point))
        #expect(actualCorners.count == expectedCorners.count)
        #expect(expectedCorners.allSatisfy { expected in
            actualCorners.contains { actual in
                actual.isApproximatelyEqual(
                    to: expected,
                    tolerance: 1.0e-12
                )
            }
        })
        #expect(result.lineage.values.filter { $0.relation == .preserved }.count == 2)
        #expect(result.lineage.values.filter { $0.relation == .generated }.count == 8)
        #expect(result.removedSubshapeIDs == Set(source.subshapes.entries.keys))
    }

    @Test(.timeLimit(.minutes(1)))
    func trimsAReversedCanonicalBoundaryWithoutChangingLoopOrientation() throws {
        let sourceID = FeatureID()
        let surface = Surface3D.analytic(.torus(
            center: .origin,
            axis: .unitZ,
            majorRadius: 3.0,
            minorRadius: 0.5
        ))
        var source = try exactSurfaceSheet(
            featureID: sourceID,
            surface: surface,
            bounds: SurfaceBounds(lowerU: 0.2, upperU: 1.2, lowerV: -0.6, upperV: 0.6)
        )
        let canonicalSource = source
        let loopID = try #require(source.brep.loops.keys.first)
        var loop = try #require(source.brep.loops[loopID])
        let pcurve = try #require(loop.coedges[0].surfaceParameterCurve)
        let edgeID = loop.coedges[0].edgeID
        var edge = try #require(source.brep.edges[edgeID])
        let reversedPcurve = try pcurve.reversed(tolerance: .standard)
        source.brep.geometry.curves[edge.curveID] = .surfaceLift(SurfaceLiftCurve3D(
            surface: surface,
            parameterCurve: reversedPcurve
        ))
        swap(&edge.startVertexID, &edge.endVertexID)
        edge.trim = CurveTrim(startParameter: 0.0, endParameter: 1.0)
        source.brep.edges[edgeID] = edge
        loop.coedges[0].orientation = .reversed
        source.brep.loops[loopID] = loop
        try source.brep.validate(level: .exact, tolerance: .standard)

        let trimNode = FeatureNode(
            id: FeatureID(),
            operation: .surfaceTrim(trimFeature(
                target: try surfaceOperationTarget(
                    featureID: sourceID,
                    fixture: source
                ),
                    bounds: SurfaceBounds(
                        lowerU: 0.4,
                        upperU: 1.0,
                        lowerV: -0.3,
                        upperV: 0.3
                    )
                )),
            inputs: [FeatureInput(featureID: sourceID, role: .target)],
            outputs: [FeatureOutput(role: .sheet)]
        )
        let result = try SurfaceTrimFeatureEvaluator(sewer: DefaultBRepSewer()).evaluate(
            feature: trimNode,
            context: context(source)
        )
        let canonicalResult = try SurfaceTrimFeatureEvaluator(sewer: DefaultBRepSewer()).evaluate(
            feature: trimNode,
            context: context(canonicalSource)
        )

        try result.brep.validate(level: .exact, tolerance: .standard)
        #expect(result.brep == canonicalResult.brep)
        #expect(result.lineage == canonicalResult.lineage)
        #expect(result.brep.loops[loopID] == nil)
        #expect(result.brep.edges[edgeID] == nil)
    }

    @Test(.timeLimit(.minutes(1)))
    func rejectsTrimThatDoesNotRemoveAParameterRegion() throws {
        let sourceID = FeatureID()
        let source = try PlanarSheetTestFixture.make(
            featureID: sourceID,
            tolerance: .standard
        )

        do {
            _ = try SurfaceTrimFeatureEvaluator(sewer: DefaultBRepSewer()).evaluate(
                feature: FeatureNode(
                    operation: .surfaceTrim(trimFeature(
                        target: try surfaceOperationTarget(
                            featureID: sourceID,
                            fixture: source
                        ),
                        bounds: SurfaceBounds(
                            lowerU: -0.020,
                            upperU: 0.020,
                            lowerV: -0.010,
                            upperV: 0.010
                        )
                    )),
                    inputs: [FeatureInput(featureID: sourceID, role: .target)],
                    outputs: [FeatureOutput(role: .sheet)]
                ),
                context: context(source)
            )
            Issue.record("A no-op surface trim must not evaluate successfully.")
        } catch let error as KernelError {
            #expect(error.code == .invalidInput)
            #expect(error.phase == .classification)
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func trimsRectangularPlanarSheetToContainedUVDomains() throws {
        let sourceID = FeatureID()
        let featureID = FeatureID()
        let source = try PlanarSheetTestFixture.make(featureID: sourceID, tolerance: .standard)
        let result = try SurfaceTrimFeatureEvaluator(sewer: DefaultBRepSewer()).evaluate(
            feature: FeatureNode(
                id: featureID,
                operation: .surfaceTrim(trimFeature(
                    target: try surfaceOperationTarget(
                        featureID: sourceID,
                        fixture: source
                    ),
                    bounds: SurfaceBounds(
                        lowerU: -0.010,
                        upperU: 0.010,
                        lowerV: -0.005,
                        upperV: 0.005
                    )
                )),
                inputs: [FeatureInput(featureID: sourceID, role: .target)],
                outputs: [FeatureOutput(role: .sheet)]
            ),
            context: context(source)
        )

        try result.brep.validate(level: .exact, tolerance: .standard)
        let points = result.brep.vertices.values.map(\.point)
        #expect(abs((try #require(points.map(\.x).max())) - 0.010) <= 1.0e-12)
        #expect(abs((try #require(points.map(\.x).min())) + 0.010) <= 1.0e-12)
        #expect(abs((try #require(points.map(\.y).max())) - 0.005) <= 1.0e-12)
        #expect(abs((try #require(points.map(\.y).min())) + 0.005) <= 1.0e-12)
        #expect(result.lineage.values.filter { $0.relation == .preserved }.count == 2)
        #expect(result.lineage.values.filter { $0.relation == .generated }.count == 8)
    }

    @Test(.timeLimit(.minutes(1)))
    func preservesUnrelatedSheetAcrossTrimAndExtend() throws {
        let sourceID = FeatureID()
        let unrelatedID = FeatureID()
        let source = try PlanarSheetTestFixture.make(featureID: sourceID, tolerance: .standard)
        let unrelated = try PlanarSheetTestFixture.make(featureID: unrelatedID, tolerance: .standard)
        let fixture = try EvaluationFixtureCombiner.combine([
            (source.brep, source.subshapes, source.lineage),
            (unrelated.brep, unrelated.subshapes, unrelated.lineage),
        ])
        let evaluationContext = EvaluationContext(
            parameters: ResolvedParameterTable(),
            brep: fixture.brep,
            profiles: [:],
            subshapes: fixture.subshapes,
            lineage: fixture.lineage,
            tolerance: .standard
        )
        let trimResult = try SurfaceTrimFeatureEvaluator(sewer: DefaultBRepSewer()).evaluate(
            feature: FeatureNode(
                id: FeatureID(),
                operation: .surfaceTrim(trimFeature(
                    target: try surfaceOperationTarget(
                        featureID: sourceID,
                        model: fixture.brep,
                        subshapes: fixture.subshapes
                    ),
                    bounds: SurfaceBounds(
                        lowerU: -0.010,
                        upperU: 0.010,
                        lowerV: -0.005,
                        upperV: 0.005
                    )
                )),
                inputs: [FeatureInput(featureID: sourceID, role: .target)],
                outputs: [FeatureOutput(role: .sheet)]
            ),
            context: evaluationContext
        )
        let extendResult = try SurfaceExtendFeatureEvaluator(sewer: DefaultBRepSewer()).evaluate(
            feature: FeatureNode(
                id: FeatureID(),
                operation: .surfaceExtend(SurfaceExtendFeature(
                    target: try surfaceOperationTarget(
                        featureID: sourceID,
                        model: fixture.brep,
                        subshapes: fixture.subshapes
                    ),
                    uDomain: .closed(-0.025, 0.025),
                    vDomain: .closed(-0.015, 0.015)
                )),
                inputs: [FeatureInput(featureID: sourceID, role: .target)],
                outputs: [FeatureOutput(role: .sheet)]
            ),
            context: evaluationContext
        )

        for result in [trimResult, extendResult] {
            try result.brep.validate(level: .exact, tolerance: .standard)
            #expect(result.brep.bodies.count == 2)
            #expect(result.removedSubshapeIDs.isDisjoint(with: unrelated.subshapes.entries.keys))
            #expect(unrelated.brep.bodies.keys.allSatisfy { result.brep.bodies[$0] == unrelated.brep.bodies[$0] })
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func trimsExactHarmonicOuterBoundaryWithAnInnerHole() throws {
        let sourceID = FeatureID()
        let featureID = FeatureID()
        let source = try PlanarSheetTestFixture.make(
            featureID: sourceID,
            tolerance: .standard
        )
        let requestedLoops = [
            harmonicLoop(
                role: .outer,
                center: Point2D(x: 0.0, y: 0.0),
                radiusU: 0.015,
                radiusV: 0.008
            ),
            harmonicLoop(
                role: .inner,
                center: Point2D(x: 0.0, y: 0.0),
                radiusU: 0.004,
                radiusV: 0.002
            ),
        ]

        let result = try SurfaceTrimFeatureEvaluator(sewer: DefaultBRepSewer()).evaluate(
            feature: FeatureNode(
                id: featureID,
                operation: .surfaceTrim(SurfaceTrimFeature(
                    target: try surfaceOperationTarget(
                        featureID: sourceID,
                        fixture: source
                    ),
                    loops: requestedLoops
                )),
                inputs: [FeatureInput(featureID: sourceID, role: .target)],
                outputs: [FeatureOutput(role: .sheet)]
            ),
            context: context(source)
        )

        try result.brep.validate(level: .exact, tolerance: .standard)
        #expect(result.brep.loops.count == 2)
        #expect(result.brep.loops.values.filter { $0.role == .outer }.count == 1)
        #expect(result.brep.loops.values.filter { $0.role == .inner }.count == 1)
        #expect(result.brep.edges.count == 8)
        #expect(result.brep.loops.values.allSatisfy { loop in
            loop.coedges.allSatisfy { coedge in
                guard case .harmonic = coedge.surfaceParameterCurve else {
                    return false
                }
                return true
            }
        })
        #expect(result.lineage.values.filter { $0.relation == .preserved }.count == 2)
        #expect(result.lineage.values.filter { $0.relation == .generated }.count == 16)
    }

    @Test(.timeLimit(.minutes(1)))
    func trimsWithExactRationalBSplineOuterBoundary() throws {
        let sourceID = FeatureID()
        let source = try PlanarSheetTestFixture.make(
            featureID: sourceID,
            tolerance: .standard
        )
        let harmonic = harmonicLoop(
            role: .outer,
            center: Point2D(x: 0.0, y: 0.0),
            radiusU: 0.014,
            radiusV: 0.007
        )
        let rationalCurves = try harmonic.parameterCurves.map { curve in
            guard case let .harmonic(center, cosine, sine, start, end) = curve else {
                throw KernelError(
                    phase: .validation,
                    code: .invalidInput,
                    tolerance: .standard,
                    message: "The rational trim fixture requires harmonic quarters."
                )
            }
            return SurfaceParameterCurve.bSpline(
                try ExactHarmonicBSplineCurve2DBuilder().build(
                    center: center,
                    cosine: cosine,
                    sine: sine,
                    startParameter: start,
                    endParameter: end,
                    tolerance: .standard
                )
            )
        }

        let result = try SurfaceTrimFeatureEvaluator(sewer: DefaultBRepSewer()).evaluate(
            feature: FeatureNode(
                operation: .surfaceTrim(SurfaceTrimFeature(
                    target: try surfaceOperationTarget(
                        featureID: sourceID,
                        fixture: source
                    ),
                    loops: [SurfaceTrimLoop(
                        role: .outer,
                        parameterCurves: rationalCurves
                    )]
                )),
                inputs: [FeatureInput(featureID: sourceID, role: .target)],
                outputs: [FeatureOutput(role: .sheet)]
            ),
            context: context(source)
        )

        try result.brep.validate(level: .exact, tolerance: .standard)
        #expect(result.brep.edges.count == 4)
        #expect(result.brep.loops.values.allSatisfy { loop in
            loop.coedges.allSatisfy { coedge in
                guard case .bSpline = coedge.surfaceParameterCurve else {
                    return false
                }
                return true
            }
        })
    }

    @Test(.timeLimit(.minutes(1)))
    func rejectsSelfIntersectingExactTrimLoop() throws {
        let sourceID = FeatureID()
        let featureID = FeatureID()
        let source = try PlanarSheetTestFixture.make(
            featureID: sourceID,
            tolerance: .standard
        )
        let bowTie = linearLoop(
            role: .outer,
            points: [
                Point2D(x: -0.015, y: -0.008),
                Point2D(x: 0.015, y: 0.008),
                Point2D(x: -0.015, y: 0.008),
                Point2D(x: 0.015, y: -0.008),
            ]
        )

        do {
            _ = try SurfaceTrimFeatureEvaluator(sewer: DefaultBRepSewer()).evaluate(
                feature: FeatureNode(
                    id: featureID,
                    operation: .surfaceTrim(SurfaceTrimFeature(
                        target: try surfaceOperationTarget(
                            featureID: sourceID,
                            fixture: source
                        ),
                        loops: [bowTie]
                    )),
                    inputs: [FeatureInput(featureID: sourceID, role: .target)],
                    outputs: [FeatureOutput(role: .sheet)]
                ),
                context: context(source)
            )
            Issue.record("A self-intersecting exact trim loop must fail.")
        } catch let error as KernelError {
            #expect(error.code == .classificationFailure)
            #expect(error.featureID == featureID)
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func rejectsExactTrimBoundaryOutsideTheSourceFace() throws {
        let sourceID = FeatureID()
        let featureID = FeatureID()
        let source = try PlanarSheetTestFixture.make(
            featureID: sourceID,
            tolerance: .standard
        )
        let outside = harmonicLoop(
            role: .outer,
            center: Point2D(x: 0.018, y: 0.0),
            radiusU: 0.008,
            radiusV: 0.006
        )

        do {
            _ = try SurfaceTrimFeatureEvaluator(sewer: DefaultBRepSewer()).evaluate(
                feature: FeatureNode(
                    id: featureID,
                    operation: .surfaceTrim(SurfaceTrimFeature(
                        target: try surfaceOperationTarget(
                            featureID: sourceID,
                            fixture: source
                        ),
                        loops: [outside]
                    )),
                    inputs: [FeatureInput(featureID: sourceID, role: .target)],
                    outputs: [FeatureOutput(role: .sheet)]
                ),
                context: context(source)
            )
            Issue.record("A trim boundary outside its source face must fail.")
        } catch let error as KernelError {
            #expect(error.code == .invalidInput)
            #expect(error.featureID == featureID)
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func extendsEveryPlanarSheetSideToAnExplicitParameterDomain() throws {
        let sourceID = FeatureID()
        let featureID = FeatureID()
        let source = try PlanarSheetTestFixture.make(featureID: sourceID, tolerance: .standard)
        let result = try SurfaceExtendFeatureEvaluator(sewer: DefaultBRepSewer()).evaluate(
            feature: FeatureNode(
                id: featureID,
                operation: .surfaceExtend(SurfaceExtendFeature(
                    target: try surfaceOperationTarget(
                        featureID: sourceID,
                        fixture: source
                    ),
                    uDomain: .closed(-0.025, 0.025),
                    vDomain: .closed(-0.015, 0.015)
                )),
                inputs: [FeatureInput(featureID: sourceID, role: .target)],
                outputs: [FeatureOutput(role: .sheet)]
            ),
            context: context(source)
        )

        try result.brep.validate(level: .exact, tolerance: .standard)
        let points = result.brep.vertices.values.map(\.point)
        #expect(abs((try #require(points.map(\.x).max())) - 0.025) <= 1.0e-12)
        #expect(abs((try #require(points.map(\.x).min())) + 0.025) <= 1.0e-12)
        #expect(abs((try #require(points.map(\.y).max())) - 0.015) <= 1.0e-12)
        #expect(abs((try #require(points.map(\.y).min())) + 0.015) <= 1.0e-12)
        #expect(result.lineage.values.filter { $0.relation == .preserved }.count == 2)
        #expect(result.lineage.values.filter { $0.relation == .generated }.count == 8)
    }

    @Test(.timeLimit(.minutes(1)))
    func extendsANonrectangularExactTrimWhilePreservingItsInnerHole() throws {
        let sourceID = FeatureID()
        let trimID = FeatureID()
        let extendID = FeatureID()
        let surface = Surface3D.plane(Plane3D(origin: .origin, normal: .unitZ))
        let source = try exactSurfaceSheet(
            featureID: sourceID,
            surface: surface,
            bounds: SurfaceBounds(
                lowerU: 0.0,
                upperU: 1.0,
                lowerV: 0.0,
                upperV: 1.0
            )
        )
        let trimResult = try SurfaceTrimFeatureEvaluator(sewer: DefaultBRepSewer()).evaluate(
            feature: FeatureNode(
                id: trimID,
                operation: .surfaceTrim(SurfaceTrimFeature(
                    target: try surfaceOperationTarget(
                        featureID: sourceID,
                        fixture: source
                    ),
                    loops: [
                        harmonicLoop(
                            role: .outer,
                            center: Point2D(x: 0.5, y: 0.5),
                            radiusU: 0.25,
                            radiusV: 0.20
                        ),
                        harmonicLoop(
                            role: .inner,
                            center: Point2D(x: 0.5, y: 0.5),
                            radiusU: 0.08,
                            radiusV: 0.05
                        ),
                    ]
                )),
                inputs: [FeatureInput(featureID: sourceID, role: .target)],
                outputs: [FeatureOutput(role: .sheet)]
            ),
            context: context(source)
        )
        let extendResult = try SurfaceExtendFeatureEvaluator(sewer: DefaultBRepSewer()).evaluate(
            feature: FeatureNode(
                id: extendID,
                operation: .surfaceExtend(SurfaceExtendFeature(
                    target: try surfaceOperationTarget(
                        featureID: trimID,
                        model: trimResult.brep,
                        subshapes: SubshapeIndex(trimResult.subshapes)
                    ),
                    uDomain: .closed(0.1, 0.9),
                    vDomain: .closed(0.1, 0.9)
                )),
                inputs: [FeatureInput(featureID: trimID, role: .target)],
                outputs: [FeatureOutput(role: .sheet)]
            ),
            context: EvaluationContext(
                parameters: ResolvedParameterTable(),
                brep: trimResult.brep,
                profiles: [:],
                subshapes: SubshapeIndex(trimResult.subshapes),
                lineage: trimResult.lineage,
                tolerance: .standard
            )
        )

        try extendResult.brep.validate(level: .exact, tolerance: .standard)
        #expect(extendResult.brep.loops.count == 2)
        let outer = try #require(extendResult.brep.loops.values.first {
            $0.role == .outer
        })
        let inner = try #require(extendResult.brep.loops.values.first {
            $0.role == .inner
        })
        #expect(outer.coedges.allSatisfy { coedge in
            switch coedge.surfaceParameterCurve {
            case .constantU, .constantV:
                true
            case .none,
                 .affine,
                 .harmonic,
                 .sphericalGreatCircle,
                 .polyline,
                 .bSpline,
                 .certifiedImplicit,
                 .certifiedAnalyticImplicit,
                 .certifiedAnalyticPair,
                 .projectedAnalytic,
                 .periodicTranslation:
                false
            }
        })
        #expect(inner.coedges.allSatisfy { coedge in
            guard case .harmonic = coedge.surfaceParameterCurve else {
                return false
            }
            return true
        })
        #expect(extendResult.lineage.values.filter {
            $0.relation == .preserved
        }.count == 10)
        #expect(extendResult.lineage.values.filter {
            $0.relation == .generated
        }.count == 8)
        #expect(
            extendResult.removedSubshapeIDs
                == Set(trimResult.subshapes.keys)
        )
    }

    @Test(.timeLimit(.minutes(1)))
    func rejectsOuterDomainNoOpEvenWhenTheSourceHasAnInnerHole() throws {
        let sourceID = FeatureID()
        let trimID = FeatureID()
        let sourceBounds = SurfaceBounds(
            lowerU: 0.0,
            upperU: 1.0,
            lowerV: 0.0,
            upperV: 1.0
        )
        let source = try exactSurfaceSheet(
            featureID: sourceID,
            surface: .plane(Plane3D(origin: .origin, normal: .unitZ)),
            bounds: sourceBounds
        )
        let rectangle = trimFeature(
            target: try surfaceOperationTarget(
                featureID: sourceID,
                fixture: source
            ),
            bounds: sourceBounds
        )
        let trimResult = try SurfaceTrimFeatureEvaluator(sewer: DefaultBRepSewer()).evaluate(
            feature: FeatureNode(
                id: trimID,
                operation: .surfaceTrim(SurfaceTrimFeature(
                    target: rectangle.target,
                    loops: rectangle.loops + [harmonicLoop(
                        role: .inner,
                        center: Point2D(x: 0.5, y: 0.5),
                        radiusU: 0.08,
                        radiusV: 0.05
                    )]
                )),
                inputs: [FeatureInput(featureID: sourceID, role: .target)],
                outputs: [FeatureOutput(role: .sheet)]
            ),
            context: context(source)
        )

        do {
            _ = try SurfaceExtendFeatureEvaluator(sewer: DefaultBRepSewer()).evaluate(
                feature: FeatureNode(
                    operation: .surfaceExtend(SurfaceExtendFeature(
                        target: try surfaceOperationTarget(
                            featureID: trimID,
                            model: trimResult.brep,
                            subshapes: SubshapeIndex(trimResult.subshapes)
                        ),
                        uDomain: .closed(0.0, 1.0),
                        vDomain: .closed(0.0, 1.0)
                    )),
                    inputs: [FeatureInput(featureID: trimID, role: .target)],
                    outputs: [FeatureOutput(role: .sheet)]
                ),
                context: EvaluationContext(
                    parameters: ResolvedParameterTable(),
                    brep: trimResult.brep,
                    profiles: [:],
                    subshapes: SubshapeIndex(trimResult.subshapes),
                    lineage: trimResult.lineage,
                    tolerance: .standard
                )
            )
            Issue.record("Surface extend must reject an unchanged outer domain.")
        } catch let error as KernelError {
            #expect(error.code == .invalidInput)
            #expect(error.phase == .classification)
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func rejectsSurfaceExtendThatShrinksOrPreservesTheCurrentDomain() throws {
        let sourceID = FeatureID()
        let source = try PlanarSheetTestFixture.make(
            featureID: sourceID,
            tolerance: .standard
        )
        let invalidDomains: [(ParameterDomain, ParameterDomain)] = [
            (.closed(-0.015, 0.025), .closed(-0.015, 0.015)),
            (.closed(-0.020, 0.020), .closed(-0.010, 0.010)),
        ]

        for (uDomain, vDomain) in invalidDomains {
            do {
                _ = try SurfaceExtendFeatureEvaluator(sewer: DefaultBRepSewer()).evaluate(
                    feature: FeatureNode(
                        operation: .surfaceExtend(SurfaceExtendFeature(
                            target: try surfaceOperationTarget(
                                featureID: sourceID,
                                fixture: source
                            ),
                            uDomain: uDomain,
                            vDomain: vDomain
                        )),
                        inputs: [FeatureInput(
                            featureID: sourceID,
                            role: .target
                        )],
                        outputs: [FeatureOutput(role: .sheet)]
                    ),
                    context: context(source)
                )
                Issue.record(
                    "Surface extend must reject shrink and no-op target domains."
                )
            } catch let error as KernelError {
                #expect(error.phase == .classification)
                #expect(error.code == .invalidInput)
            }
        }
    }

    private func context(_ fixture: PlanarSheetTestFixture) -> EvaluationContext {
        EvaluationContext(
            parameters: ResolvedParameterTable(),
            brep: fixture.brep,
            profiles: [:],
            subshapes: fixture.subshapes,
            lineage: fixture.lineage,
            tolerance: .standard
        )
    }

    private func exactSurfaceSheet(
        featureID: FeatureID,
        surface: Surface3D,
        bounds: SurfaceBounds
    ) throws -> PlanarSheetTestFixture {
        let pcurves: [SurfaceParameterCurve] = [
            .constantV(v: bounds.lowerV, uStart: bounds.lowerU, uEnd: bounds.upperU),
            .constantU(u: bounds.upperU, vStart: bounds.lowerV, vEnd: bounds.upperV),
            .constantV(v: bounds.upperV, uStart: bounds.upperU, uEnd: bounds.lowerU),
            .constantU(u: bounds.lowerU, vStart: bounds.upperV, vEnd: bounds.lowerV),
        ]
        let edges = try pcurves.enumerated().map { index, pcurve in
            let start = try pcurve.startParameter(tolerance: .standard)
            let end = try pcurve.endParameter(tolerance: .standard)
            return BRepSewingEdge(
                stableID: "exactSurface:edge:\(index)",
                curve: .surfaceLift(SurfaceLiftCurve3D(
                    surface: surface,
                    parameterCurve: pcurve
                )),
                startParameter: 0.0,
                endParameter: 1.0,
                startPoint: try surface.point(
                    u: start.u,
                    v: start.v,
                    tolerance: .standard
                ),
                endPoint: try surface.point(
                    u: end.u,
                    v: end.v,
                    tolerance: .standard
                ),
                surfaceParameterCurve: pcurve
            )
        }
        let sewn = try DefaultBRepSewer().sew(BRepSewingRequest(
            featureID: featureID,
            bodyKind: .sheet,
            shells: [BRepSewingShell(
                stableID: "exactSurface:shell",
                patches: [BRepSewingFacePatch(
                    stableID: "exactSurface:face",
                    surface: surface,
                    orientation: .forward,
                    loops: [BRepSewingLoop(
                        stableID: "exactSurface:outer",
                        role: .outer,
                        edges: edges
                    )]
                )]
            )]
        ), tolerance: .standard)
        try sewn.brep.validate(level: .exact, tolerance: .standard)
        return PlanarSheetTestFixture(
            brep: sewn.brep,
            subshapes: SubshapeIndex(sewn.subshapes),
            lineage: sewn.lineage
        )
    }

    private func corners(
        on surface: Surface3D,
        bounds: SurfaceBounds
    ) throws -> [Point3D] {
        try [
            (bounds.lowerU, bounds.lowerV),
            (bounds.upperU, bounds.lowerV),
            (bounds.upperU, bounds.upperV),
            (bounds.lowerU, bounds.upperV),
        ].map { u, v in
            try surface.point(u: u, v: v, tolerance: .standard)
        }
    }

    private func trimFeature(
        target: SurfaceOperationTargetReference,
        bounds: SurfaceBounds
    ) -> SurfaceTrimFeature {
        SurfaceTrimFeature(
            target: target,
            loops: [SurfaceTrimLoop(
                role: .outer,
                parameterCurves: [
                    .constantV(
                        v: bounds.lowerV,
                        uStart: bounds.lowerU,
                        uEnd: bounds.upperU
                    ),
                    .constantU(
                        u: bounds.upperU,
                        vStart: bounds.lowerV,
                        vEnd: bounds.upperV
                    ),
                    .constantV(
                        v: bounds.upperV,
                        uStart: bounds.upperU,
                        uEnd: bounds.lowerU
                    ),
                    .constantU(
                        u: bounds.lowerU,
                        vStart: bounds.upperV,
                        vEnd: bounds.lowerV
                    ),
                ]
            )]
        )
    }

    private func harmonicLoop(
        role: SurfaceTrimLoopRole,
        center: Point2D,
        radiusU: Double,
        radiusV: Double
    ) -> SurfaceTrimLoop {
        let cosine = Point2D(x: radiusU, y: 0.0)
        let sine = Point2D(x: 0.0, y: radiusV)
        return SurfaceTrimLoop(
            role: role,
            parameterCurves: (0..<4).map { index in
                let start = Double(index) * Double.pi * 0.5
                return .harmonic(
                    center: center,
                    cosine: cosine,
                    sine: sine,
                    startParameter: start,
                    endParameter: start + Double.pi * 0.5
                )
            }
        )
    }

    private func linearLoop(
        role: SurfaceTrimLoopRole,
        points: [Point2D]
    ) -> SurfaceTrimLoop {
        SurfaceTrimLoop(
            role: role,
            parameterCurves: points.indices.map { index in
                let start = points[index]
                let end = points[(index + 1) % points.count]
                return .affine(
                    origin: start,
                    direction: Point2D(
                        x: end.x - start.x,
                        y: end.y - start.y
                    ),
                    startParameter: 0.0,
                    endParameter: 1.0
                )
            }
        )
    }

    private static let exactSurfaceCases: [ExactSurfaceTrimCase] = {
        let source = SurfaceBounds(
            lowerU: 0.2,
            upperU: 1.2,
            lowerV: -0.6,
            upperV: 0.6
        )
        let trimmed = SurfaceBounds(
            lowerU: 0.4,
            upperU: 1.0,
            lowerV: -0.3,
            upperV: 0.3
        )
        return [
            ExactSurfaceTrimCase(
                name: "plane",
                surface: .plane(Plane3D(origin: .origin, normal: .unitZ)),
                sourceBounds: source,
                trimmedBounds: trimmed
            ),
            ExactSurfaceTrimCase(
                name: "cylinder",
                surface: .cylinder(Cylinder3D(
                    origin: .origin,
                    axis: .unitZ,
                    radius: 2.0
                )),
                sourceBounds: source,
                trimmedBounds: trimmed
            ),
            ExactSurfaceTrimCase(
                name: "analyticPlane",
                surface: .analytic(.plane(origin: .origin, normal: .unitZ)),
                sourceBounds: source,
                trimmedBounds: trimmed
            ),
            ExactSurfaceTrimCase(
                name: "analyticCylinder",
                surface: .analytic(.cylinder(
                    origin: .origin,
                    axis: .unitZ,
                    radius: 2.0
                )),
                sourceBounds: source,
                trimmedBounds: trimmed
            ),
            ExactSurfaceTrimCase(
                name: "cone",
                surface: .analytic(.cone(
                    apex: .origin,
                    axis: .unitZ,
                    halfAngle: 0.4
                )),
                sourceBounds: SurfaceBounds(
                    lowerU: source.lowerU,
                    upperU: source.upperU,
                    lowerV: 1.0,
                    upperV: 2.0
                ),
                trimmedBounds: SurfaceBounds(
                    lowerU: trimmed.lowerU,
                    upperU: trimmed.upperU,
                    lowerV: 1.2,
                    upperV: 1.8
                )
            ),
            ExactSurfaceTrimCase(
                name: "sphere",
                surface: .analytic(.sphere(center: .origin, radius: 2.0)),
                sourceBounds: source,
                trimmedBounds: trimmed
            ),
            ExactSurfaceTrimCase(
                name: "torus",
                surface: .analytic(.torus(
                    center: .origin,
                    axis: .unitZ,
                    majorRadius: 3.0,
                    minorRadius: 0.5
                )),
                sourceBounds: source,
                trimmedBounds: trimmed
            ),
            ExactSurfaceTrimCase(
                name: "rationalBSpline",
                surface: .bSpline(BSplineSurface3D(
                    uDegree: 1,
                    vDegree: 1,
                    uKnots: [0.0, 0.0, 1.0, 1.0],
                    vKnots: [0.0, 0.0, 1.0, 1.0],
                    controlPoints: [
                        [
                            Point3D(x: 0.0, y: 0.0, z: 0.0),
                            Point3D(x: 1.0, y: 0.0, z: 0.2),
                        ],
                        [
                            Point3D(x: 0.0, y: 1.0, z: 0.1),
                            Point3D(x: 1.0, y: 1.0, z: 0.4),
                        ],
                    ],
                    weights: [
                        [1.0, 0.8],
                        [1.2, 1.0],
                    ]
                )),
                sourceBounds: SurfaceBounds(
                    lowerU: 0.0,
                    upperU: 1.0,
                    lowerV: 0.0,
                    upperV: 1.0
                ),
                trimmedBounds: SurfaceBounds(
                    lowerU: 0.2,
                    upperU: 0.8,
                    lowerV: 0.25,
                    upperV: 0.75
                )
            ),
        ]
    }()
}

struct SurfaceBounds: Sendable {
    let lowerU: Double
    let upperU: Double
    let lowerV: Double
    let upperV: Double
}

struct ExactSurfaceTrimCase: CustomTestStringConvertible, Sendable {
    let name: String
    let surface: Surface3D
    let sourceBounds: SurfaceBounds
    let trimmedBounds: SurfaceBounds

    var testDescription: String { name }
}
