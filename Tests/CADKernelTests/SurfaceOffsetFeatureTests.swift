import Testing
import Foundation
import CADCore
import CADGeometry
import CADIR
import CADModeling
import CADTopology
@testable import CADKernel

@Suite("Exact surface offset")
struct SurfaceOffsetFeatureTests {
    @Test(
        .timeLimit(.minutes(1)),
        arguments: [0.005, -0.005]
    )
    func offsetsPlanarSheetInBothNormalDirectionsAndPreservesTopologyLineage(
        distance: Double
    ) throws {
        let sourceID = FeatureID()
        let featureID = FeatureID()
        let source = try planarSheet(featureID: sourceID)
        let feature = FeatureNode(
            id: featureID,
            operation: .surfaceOffset(SurfaceOffsetFeature(
                target: try surfaceOperationTarget(
                    featureID: sourceID,
                    model: source.brep,
                    subshapes: source.subshapes
                ),
                distance: .constant(.length(distance, unit: .meter))
            )),
            inputs: [FeatureInput(featureID: sourceID, role: .target)],
            outputs: [FeatureOutput(role: .sheet)]
        )
        let result = try SurfaceOffsetFeatureEvaluator().evaluate(
            feature: feature,
            context: EvaluationContext(
                parameters: ResolvedParameterTable(),
                brep: source.brep,
                profiles: [:],
                subshapes: source.subshapes,
                lineage: source.lineage,
                tolerance: .standard
            )
        )

        try result.brep.validate(level: .exact, tolerance: .standard)
        #expect(result.brep.bodies.count == 1)
        #expect(result.brep.faces.count == 1)
        #expect(result.brep.edges.count == 4)
        #expect(result.brep.vertices.count == 4)
        #expect(result.brep.vertices.values.allSatisfy {
            abs($0.point.z - distance) <= 1.0e-12
        })
        let outputLineage = result.lineage.values.filter { $0.output.featureID == featureID }
        #expect(outputLineage.count == 10)
        #expect(outputLineage.allSatisfy { $0.relation == .preserved })
    }

    @Test(
        .timeLimit(.minutes(1)),
        arguments: exactSurfaceCases
    )
    func offsetsEveryExactSurfaceRepresentationInItsOwnParameterChart(
        surfaceCase: ExactSurfaceOffsetCase
    ) throws {
        let sourceID = FeatureID()
        let featureID = FeatureID()
        let distance = 0.005
        let source = try exactSurfaceSheet(
            featureID: sourceID,
            surface: surfaceCase.surface,
            outerBounds: surfaceCase.bounds
        )
        let result = try evaluateOffset(
            source: source,
            sourceID: sourceID,
            featureID: featureID,
            distance: distance
        )

        try result.brep.validate(level: .exact, tolerance: .standard)
        let face = try #require(result.brep.faces.values.first)
        let targetSurface = try #require(
            result.brep.geometry.surfaces[face.surfaceID]
        )
        for (u, v) in surfaceCase.sampleParameters {
            let sourcePoint = try surfaceCase.surface.point(
                u: u,
                v: v,
                tolerance: .standard
            )
            let derivatives = try surfaceCase.surface.parameterDerivatives(
                atU: u,
                v: v,
                tolerance: .standard
            )
            let normal = try derivatives.tangentU.cross(
                derivatives.tangentV
            ).normalized(tolerance: 1.0e-9)
            let expected = sourcePoint + normal * distance
            let actual = try targetSurface.point(
                u: u,
                v: v,
                tolerance: .standard
            )
            #expect(actual.isApproximatelyEqual(
                to: expected,
                tolerance: 1.0e-8
            ))
        }
        #expect(result.brep.loops.values.allSatisfy { loop in
            loop.coedges.allSatisfy { coedge in
                guard case let .sameParameterImage(image) = coedge.surfaceParameterCurve else {
                    return false
                }
                return image.sourceSurface == surfaceCase.surface
                    && image.targetSurface == targetSurface
            }
        })
        #expect(result.brep.edges.values.allSatisfy { edge in
            guard case let .surfaceLift(lift) = result.brep.geometry.curves[edge.curveID],
                  case let .sameParameterImage(image) = lift.parameterCurve else {
                return false
            }
            return lift.surface == targetSurface
                && image.sourceSurface == surfaceCase.surface
                && image.targetSurface == targetSurface
        })
    }

    @Test(.timeLimit(.minutes(1)))
    func preservesInnerLoopsOnACurvedSurface() throws {
        let sourceID = FeatureID()
        let featureID = FeatureID()
        let surface = Surface3D.cylinder(Cylinder3D(
            origin: .origin,
            axis: .unitZ,
            radius: 2.0
        ))
        let outer = SurfaceOffsetBounds(
            lowerU: 0.2,
            upperU: 1.4,
            lowerV: -0.8,
            upperV: 0.8
        )
        let inner = SurfaceOffsetBounds(
            lowerU: 0.6,
            upperU: 1.0,
            lowerV: -0.3,
            upperV: 0.3
        )
        let source = try exactSurfaceSheet(
            featureID: sourceID,
            surface: surface,
            outerBounds: outer,
            innerBounds: inner
        )
        let result = try evaluateOffset(
            source: source,
            sourceID: sourceID,
            featureID: featureID,
            distance: 0.1
        )

        try result.brep.validate(level: .exact, tolerance: .standard)
        #expect(result.brep.loops.count == 2)
        #expect(result.brep.loops.values.filter { $0.role == .outer }.count == 1)
        #expect(result.brep.loops.values.filter { $0.role == .inner }.count == 1)
        #expect(result.brep.edges.count == 8)
        #expect(result.brep.vertices.count == 8)
        let face = try #require(result.brep.faces.values.first)
        let targetSurface = try #require(result.brep.geometry.surfaces[face.surfaceID])
        let sample = try targetSurface.point(
            u: inner.lowerU,
            v: inner.lowerV,
            tolerance: .standard
        )
        let radialDistance = sqrt(sample.x * sample.x + sample.y * sample.y)
        #expect(abs(radialDistance - 2.1) <= 1.0e-10)
    }

    @Test(.timeLimit(.minutes(1)))
    func appliesSignedDistanceRelativeToReversedFaceOrientation() throws {
        let sourceID = FeatureID()
        let featureID = FeatureID()
        let surface = Surface3D.plane(Plane3D(
            origin: .origin,
            normal: .unitZ
        ))
        let source = try exactSurfaceSheet(
            featureID: sourceID,
            surface: surface,
            outerBounds: SurfaceOffsetBounds(
                lowerU: -1.0,
                upperU: 1.0,
                lowerV: -1.0,
                upperV: 1.0
            ),
            orientation: .reversed
        )
        let result = try evaluateOffset(
            source: source,
            sourceID: sourceID,
            featureID: featureID,
            distance: 0.25
        )

        try result.brep.validate(level: .exact, tolerance: .standard)
        #expect(result.brep.vertices.values.allSatisfy {
            abs($0.point.z + 0.25) <= 1.0e-12
        })
        #expect(result.brep.faces.values.allSatisfy {
            $0.orientation == .reversed
        })
    }

    @Test(.timeLimit(.minutes(1)))
    func rejectsZeroDistanceWithTypedDiagnostic() throws {
        let sourceID = FeatureID()
        let featureID = FeatureID()
        let source = try planarSheet(featureID: sourceID)

        do {
            _ = try SurfaceOffsetFeatureEvaluator().evaluate(
                feature: FeatureNode(
                    id: featureID,
                    operation: .surfaceOffset(SurfaceOffsetFeature(
                        target: try surfaceOperationTarget(
                            featureID: sourceID,
                            model: source.brep,
                            subshapes: source.subshapes
                        ),
                        distance: .constant(.length(0.0, unit: .meter))
                    )),
                    inputs: [FeatureInput(featureID: sourceID, role: .target)],
                    outputs: [FeatureOutput(role: .sheet)]
                ),
                context: EvaluationContext(
                    parameters: ResolvedParameterTable(),
                    brep: source.brep,
                    profiles: [:],
                    subshapes: source.subshapes,
                    lineage: source.lineage,
                    tolerance: .standard
                )
            )
            Issue.record("A zero surface offset must not succeed.")
        } catch let error as KernelError {
            #expect(error.phase == .evaluation)
            #expect(error.code == .invalidInput)
            #expect(error.featureID == featureID)
            #expect(error.tolerance == .standard)
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func preservesUnrelatedSheetAndSelectionIdentity() throws {
        let sourceID = FeatureID()
        let unrelatedID = FeatureID()
        let source = try PlanarSheetTestFixture.make(featureID: sourceID, tolerance: .standard)
        let unrelated = try PlanarSheetTestFixture.make(featureID: unrelatedID, tolerance: .standard)
        let fixture = try EvaluationFixtureCombiner.combine([
            (source.brep, source.subshapes, source.lineage),
            (unrelated.brep, unrelated.subshapes, unrelated.lineage),
        ])
        let result = try SurfaceOffsetFeatureEvaluator().evaluate(
            feature: FeatureNode(
                id: FeatureID(),
                operation: .surfaceOffset(SurfaceOffsetFeature(
                    target: try surfaceOperationTarget(
                        featureID: sourceID,
                        model: fixture.brep,
                        subshapes: fixture.subshapes
                    ),
                    distance: .constant(.length(0.005, unit: .meter))
                )),
                inputs: [FeatureInput(featureID: sourceID, role: .target)],
                outputs: [FeatureOutput(role: .sheet)]
            ),
            context: EvaluationContext(
                parameters: ResolvedParameterTable(),
                brep: fixture.brep,
                profiles: [:],
                subshapes: fixture.subshapes,
                lineage: fixture.lineage,
                tolerance: .standard
            )
        )

        try result.brep.validate(level: .exact, tolerance: .standard)
        #expect(result.brep.bodies.count == 2)
        #expect(result.removedSubshapeIDs.isDisjoint(with: unrelated.subshapes.entries.keys))
        #expect(unrelated.brep.bodies.keys.allSatisfy { result.brep.bodies[$0] == unrelated.brep.bodies[$0] })
    }

    @Test(.timeLimit(.minutes(1)))
    func doesNotMutateASurfaceSharedByAnUnrelatedBody() throws {
        let sourceID = FeatureID()
        let unrelatedID = FeatureID()
        let featureID = FeatureID()
        let surface = Surface3D.plane(Plane3D(
            origin: .origin,
            normal: .unitZ
        ))
        let bounds = SurfaceOffsetBounds(
            lowerU: -0.02,
            upperU: 0.02,
            lowerV: -0.01,
            upperV: 0.01
        )
        let source = try exactSurfaceSheet(
            featureID: sourceID,
            surface: surface,
            outerBounds: bounds
        )
        let unrelated = try exactSurfaceSheet(
            featureID: unrelatedID,
            surface: surface,
            outerBounds: bounds
        )
        var fixture = try EvaluationFixtureCombiner.combine([
            (source.brep, source.subshapes, source.lineage),
            (unrelated.brep, unrelated.subshapes, unrelated.lineage),
        ])
        let sourceFaceID = try #require(source.brep.faces.keys.first)
        let unrelatedFaceID = try #require(unrelated.brep.faces.keys.first)
        let sharedSurfaceID = try #require(source.brep.faces[sourceFaceID]?.surfaceID)
        let unrelatedSurfaceID = try #require(
            unrelated.brep.faces[unrelatedFaceID]?.surfaceID
        )
        var unrelatedFace = try #require(fixture.brep.faces[unrelatedFaceID])
        unrelatedFace.surfaceID = sharedSurfaceID
        fixture.brep.faces[unrelatedFaceID] = unrelatedFace
        fixture.brep.geometry.surfaces.removeValue(forKey: unrelatedSurfaceID)
        try fixture.brep.validate(level: .exact, tolerance: .standard)

        let result = try SurfaceOffsetFeatureEvaluator().evaluate(
            feature: FeatureNode(
                id: featureID,
                operation: .surfaceOffset(SurfaceOffsetFeature(
                    target: try surfaceOperationTarget(
                        featureID: sourceID,
                        model: fixture.brep,
                        subshapes: fixture.subshapes
                    ),
                    distance: .constant(.length(0.005, unit: .meter))
                )),
                inputs: [FeatureInput(featureID: sourceID, role: .target)],
                outputs: [FeatureOutput(role: .sheet)]
            ),
            context: EvaluationContext(
                parameters: ResolvedParameterTable(),
                brep: fixture.brep,
                profiles: [:],
                subshapes: fixture.subshapes,
                lineage: fixture.lineage,
                tolerance: .standard
            )
        )

        try result.brep.validate(level: .exact, tolerance: .standard)
        #expect(result.brep.faces[unrelatedFaceID]?.surfaceID == sharedSurfaceID)
        #expect(result.brep.geometry.surfaces[sharedSurfaceID] == surface)
        #expect(result.brep.faces[sourceFaceID]?.surfaceID != sharedSurfaceID)
    }

    @Test(.timeLimit(.minutes(1)))
    func rejectsSelectedFaceOwnedByAnotherBody() throws {
        let sourceID = FeatureID()
        let unrelatedID = FeatureID()
        let featureID = FeatureID()
        let source = try PlanarSheetTestFixture.make(
            featureID: sourceID,
            tolerance: .standard
        )
        let unrelated = try PlanarSheetTestFixture.make(
            featureID: unrelatedID,
            tolerance: .standard
        )
        let fixture = try EvaluationFixtureCombiner.combine([
            (source.brep, source.subshapes, source.lineage),
            (unrelated.brep, unrelated.subshapes, unrelated.lineage),
        ])
        let unrelatedTarget = try surfaceOperationTarget(
            featureID: unrelatedID,
            model: fixture.brep,
            subshapes: fixture.subshapes
        )
        let mismatchedTarget = SurfaceOperationTargetReference(
            featureID: sourceID,
            face: unrelatedTarget.face
        )

        do {
            _ = try SurfaceOffsetFeatureEvaluator().evaluate(
                feature: FeatureNode(
                    id: featureID,
                    operation: .surfaceOffset(SurfaceOffsetFeature(
                        target: mismatchedTarget,
                        distance: .constant(.length(0.005, unit: .meter))
                    )),
                    inputs: [
                        FeatureInput(featureID: sourceID, role: .target),
                    ],
                    outputs: [FeatureOutput(role: .sheet)]
                ),
                context: EvaluationContext(
                    parameters: ResolvedParameterTable(),
                    brep: fixture.brep,
                    profiles: [:],
                    subshapes: fixture.subshapes,
                    lineage: fixture.lineage,
                    tolerance: .standard
                )
            )
            Issue.record(
                "A selected face owned by another body must not be accepted."
            )
        } catch let error as KernelError {
            #expect(error.code == .missingReference)
            #expect(error.featureID == featureID)
        }
    }

    private func planarSheet(
        featureID: FeatureID
    ) throws -> (brep: BRepModel, subshapes: SubshapeIndex, lineage: [SubshapeID: TopologyLineage]) {
        let points = [
            Point3D(x: -0.020, y: -0.010, z: 0.0),
            Point3D(x: 0.020, y: -0.010, z: 0.0),
            Point3D(x: 0.020, y: 0.010, z: 0.0),
            Point3D(x: -0.020, y: 0.010, z: 0.0),
        ]
        let surface = Surface3D.plane(Plane3D(origin: points[0], normal: .unitZ))
        let edges = try points.indices.map { index in
            let start = points[index]
            let end = points[(index + 1) % points.count]
            let delta = end - start
            let startUV = try surface.parameterProjection(of: start, tolerance: .standard)
            let endUV = try surface.parameterProjection(of: end, tolerance: .standard)
            return BRepSewingEdge(
                stableID: "surfaceOffsetSource:edge:\(index)",
                curve: .line(Line3D(origin: start, direction: try delta.normalized(tolerance: 1.0e-9))),
                startParameter: 0.0,
                endParameter: delta.length,
                startPoint: start,
                endPoint: end,
                surfaceParameterCurve: .polyline([
                    SurfaceParameter(u: startUV.u, v: startUV.v),
                    SurfaceParameter(u: endUV.u, v: endUV.v),
                ])
            )
        }
        let sewn = try DefaultBRepSewer().sew(BRepSewingRequest(
            featureID: featureID,
            bodyKind: .sheet,
            shells: [BRepSewingShell(
                stableID: "surfaceOffsetSource:shell",
                patches: [BRepSewingFacePatch(
                    stableID: "surfaceOffsetSource:face",
                    surface: surface,
                    orientation: .forward,
                    loops: [BRepSewingLoop(
                        stableID: "surfaceOffsetSource:outer",
                        role: .outer,
                        edges: edges
                    )]
                )]
            )]
        ), tolerance: .standard)
        return (sewn.brep, SubshapeIndex(sewn.subshapes), sewn.lineage)
    }

    private func evaluateOffset(
        source: PlanarSheetTestFixture,
        sourceID: FeatureID,
        featureID: FeatureID,
        distance: Double
    ) throws -> EvaluationResult {
        try SurfaceOffsetFeatureEvaluator().evaluate(
            feature: FeatureNode(
                id: featureID,
                operation: .surfaceOffset(SurfaceOffsetFeature(
                    target: try surfaceOperationTarget(
                        featureID: sourceID,
                        fixture: source
                    ),
                    distance: .constant(.length(distance, unit: .meter))
                )),
                inputs: [FeatureInput(featureID: sourceID, role: .target)],
                outputs: [FeatureOutput(role: .sheet)]
            ),
            context: EvaluationContext(
                parameters: ResolvedParameterTable(),
                brep: source.brep,
                profiles: [:],
                subshapes: source.subshapes,
                lineage: source.lineage,
                tolerance: .standard
            )
        )
    }

    private func exactSurfaceSheet(
        featureID: FeatureID,
        surface: Surface3D,
        outerBounds: SurfaceOffsetBounds,
        innerBounds: SurfaceOffsetBounds? = nil,
        orientation: Orientation = .forward
    ) throws -> PlanarSheetTestFixture {
        var loops = [try sewingLoop(
            stableID: "surfaceOffsetExact:outer",
            role: .outer,
            surface: surface,
            parameterCurves: try rectangularParameterCurves(
                bounds: outerBounds,
                reversed: false
            )
        )]
        if let innerBounds {
            loops.append(try sewingLoop(
                stableID: "surfaceOffsetExact:inner",
                role: .inner,
                surface: surface,
                parameterCurves: try rectangularParameterCurves(
                    bounds: innerBounds,
                    reversed: true
                )
            ))
        }
        let sewn = try DefaultBRepSewer().sew(
            BRepSewingRequest(
                featureID: featureID,
                bodyKind: .sheet,
                shells: [BRepSewingShell(
                    stableID: "surfaceOffsetExact:shell",
                    patches: [BRepSewingFacePatch(
                        stableID: "surfaceOffsetExact:face",
                        surface: surface,
                        orientation: orientation,
                        loops: loops
                    )]
                )]
            ),
            tolerance: .standard
        )
        try sewn.brep.validate(level: .exact, tolerance: .standard)
        return PlanarSheetTestFixture(
            brep: sewn.brep,
            subshapes: SubshapeIndex(sewn.subshapes),
            lineage: sewn.lineage
        )
    }

    private func sewingLoop(
        stableID: String,
        role: LoopRole,
        surface: Surface3D,
        parameterCurves: [SurfaceParameterCurve]
    ) throws -> BRepSewingLoop {
        BRepSewingLoop(
            stableID: stableID,
            role: role,
            edges: try parameterCurves.enumerated().map { index, pcurve in
                let lift = SurfaceLiftCurve3D(
                    surface: surface,
                    parameterCurve: pcurve
                )
                let curve = Curve3D.surfaceLift(lift)
                return BRepSewingEdge(
                    stableID: "\(stableID):edge:\(index)",
                    curve: curve,
                    startParameter: 0.0,
                    endParameter: 1.0,
                    startPoint: try curve.point(
                        at: 0.0,
                        tolerance: .standard
                    ),
                    endPoint: try curve.point(
                        at: 1.0,
                        tolerance: .standard
                    ),
                    surfaceParameterCurve: pcurve
                )
            }
        )
    }

    private func rectangularParameterCurves(
        bounds: SurfaceOffsetBounds,
        reversed: Bool
    ) throws -> [SurfaceParameterCurve] {
        let forward: [SurfaceParameterCurve] = [
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
        guard reversed else { return forward }
        return try forward.reversed().map { curve in
            try curve.reversed(tolerance: .standard)
        }
    }

    private static let exactSurfaceCases: [ExactSurfaceOffsetCase] = [
        ExactSurfaceOffsetCase(
            name: "plane",
            surface: .plane(Plane3D(origin: .origin, normal: .unitZ)),
            bounds: .standard
        ),
        ExactSurfaceOffsetCase(
            name: "cylinder",
            surface: .cylinder(Cylinder3D(
                origin: .origin,
                axis: .unitZ,
                radius: 2.0
            )),
            bounds: .standard
        ),
        ExactSurfaceOffsetCase(
            name: "analyticPlane",
            surface: .analytic(.plane(origin: .origin, normal: .unitZ)),
            bounds: .standard
        ),
        ExactSurfaceOffsetCase(
            name: "analyticCylinder",
            surface: .analytic(.cylinder(
                origin: .origin,
                axis: .unitZ,
                radius: 2.0
            )),
            bounds: .standard
        ),
        ExactSurfaceOffsetCase(
            name: "cone",
            surface: .analytic(.cone(
                apex: .origin,
                axis: .unitZ,
                halfAngle: 0.4
            )),
            bounds: SurfaceOffsetBounds(
                lowerU: 0.2,
                upperU: 1.2,
                lowerV: 1.0,
                upperV: 2.0
            )
        ),
        ExactSurfaceOffsetCase(
            name: "sphere",
            surface: .analytic(.sphere(center: .origin, radius: 2.0)),
            bounds: .standard
        ),
        ExactSurfaceOffsetCase(
            name: "torus",
            surface: .analytic(.torus(
                center: .origin,
                axis: .unitZ,
                majorRadius: 3.0,
                minorRadius: 0.5
            )),
            bounds: .standard
        ),
        ExactSurfaceOffsetCase(
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
            bounds: SurfaceOffsetBounds(
                lowerU: 0.0,
                upperU: 1.0,
                lowerV: 0.0,
                upperV: 1.0
            )
        ),
    ]
}

struct SurfaceOffsetBounds: Sendable {
    let lowerU: Double
    let upperU: Double
    let lowerV: Double
    let upperV: Double

    static let standard = SurfaceOffsetBounds(
        lowerU: 0.2,
        upperU: 1.2,
        lowerV: -0.6,
        upperV: 0.6
    )
}

struct ExactSurfaceOffsetCase: CustomTestStringConvertible, Sendable {
    let name: String
    let surface: Surface3D
    let bounds: SurfaceOffsetBounds

    var testDescription: String { name }

    var sampleParameters: [(Double, Double)] {
        let uMid = (bounds.lowerU + bounds.upperU) * 0.5
        let vMid = (bounds.lowerV + bounds.upperV) * 0.5
        return [
            (bounds.lowerU, bounds.lowerV),
            (bounds.upperU, bounds.lowerV),
            (uMid, vMid),
            (bounds.lowerU, bounds.upperV),
            (bounds.upperU, bounds.upperV),
        ]
    }
}
