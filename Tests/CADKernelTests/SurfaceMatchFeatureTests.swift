import Testing
import CADCore
import CADGeometry
import CADIR
import CADModeling
import CADTopology
@testable import CADKernel

@Suite("Exact surface match")
struct SurfaceMatchFeatureTests {
    @Test(
        .timeLimit(.minutes(1)),
        arguments: exactSurfaceCases
    )
    func matchesEveryExactSurfaceRepresentationWithMeasuredG2(
        surfaceCase: ExactSurfaceMatchCase
    ) throws {
        let sourceID = FeatureID()
        let targetID = FeatureID()
        let featureID = FeatureID()
        let source = try exactSurfaceSheet(
            featureID: sourceID,
            surface: surfaceCase.surface,
            bounds: surfaceCase.bounds
        )
        let target = try exactSurfaceSheet(
            featureID: targetID,
            surface: translated(
                surfaceCase.surface,
                by: Vector3D(x: 1.7, y: -0.4, z: 2.3)
            ),
            bounds: surfaceCase.bounds
        )
        let fixture = try EvaluationFixtureCombiner.combine([
            (source.brep, source.subshapes, source.lineage),
            (target.brep, target.subshapes, target.lineage),
        ])
        let anchor = SurfaceParameter(
            u: (surfaceCase.bounds.lowerU + surfaceCase.bounds.upperU) * 0.5,
            v: (surfaceCase.bounds.lowerV + surfaceCase.bounds.upperV) * 0.5
        )
        let result = try SurfaceMatchFeatureEvaluator().evaluate(
            feature: FeatureNode(
                id: featureID,
                operation: .surfaceMatch(SurfaceMatchFeature(
                    source: SurfaceOperationTargetReference(featureID: sourceID),
                    target: SurfaceOperationTargetReference(featureID: targetID),
                    sourceParameter: anchor,
                    targetParameter: anchor,
                    continuity: .curvature
                )),
                inputs: [
                    FeatureInput(featureID: sourceID, role: .sheet),
                    FeatureInput(featureID: targetID, role: .target),
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

        try result.brep.validate(level: .exact, tolerance: .standard)
        #expect(result.brep.bodies.count == 1)
        let face = try #require(result.brep.faces.values.first)
        guard case .bSpline = result.brep.geometry.surfaces[face.surfaceID] else {
            Issue.record("Surface match must emit an exact rational B-spline patch.")
            return
        }
        #expect(result.brep.edges.values.allSatisfy { edge in
            guard case .surfaceLift = result.brep.geometry.curves[edge.curveID] else {
                return false
            }
            return edge.trim == CurveTrim(startParameter: 0.0, endParameter: 1.0)
        })
        let faceLineage = try #require(
            result.lineage.values.first { $0.output.role == "face" }
        )
        #expect(faceLineage.relation == .merged)
        #expect(faceLineage.parents.count == 2)
    }

    @Test(.timeLimit(.minutes(1)))
    func rejectsG2WhenOnlyG1CanBeSatisfied() throws {
        let sourceID = FeatureID()
        let targetID = FeatureID()
        let bounds = SurfaceMatchBounds(
            lowerU: 0.2,
            upperU: 1.2,
            lowerV: -0.6,
            upperV: 0.6
        )
        let source = try exactSurfaceSheet(
            featureID: sourceID,
            surface: .analytic(.cylinder(
                origin: .origin,
                axis: .unitZ,
                radius: 2.0
            )),
            bounds: bounds
        )
        let target = try exactSurfaceSheet(
            featureID: targetID,
            surface: .analytic(.cylinder(
                origin: Point3D(x: 3.0, y: 0.0, z: 0.0),
                axis: .unitZ,
                radius: 3.0
            )),
            bounds: bounds
        )
        let fixture = try EvaluationFixtureCombiner.combine([
            (source.brep, source.subshapes, source.lineage),
            (target.brep, target.subshapes, target.lineage),
        ])
        let anchor = SurfaceParameter(u: 0.7, v: 0.0)
        let context = EvaluationContext(
            parameters: ResolvedParameterTable(),
            brep: fixture.brep,
            profiles: [:],
            subshapes: fixture.subshapes,
            lineage: fixture.lineage,
            tolerance: .standard
        )

        let tangentResult = try SurfaceMatchFeatureEvaluator().evaluate(
            feature: matchFeature(
                sourceID: sourceID,
                targetID: targetID,
                sourceParameter: anchor,
                targetParameter: anchor,
                continuity: .tangentPlane
            ),
            context: context
        )
        try tangentResult.brep.validate(level: .exact, tolerance: .standard)

        do {
            _ = try SurfaceMatchFeatureEvaluator().evaluate(
                feature: matchFeature(
                    sourceID: sourceID,
                    targetID: targetID,
                    sourceParameter: anchor,
                    targetParameter: anchor,
                    continuity: .curvature
                ),
                context: context
            )
            Issue.record("Surface match must reject an unsatisfied G2 request.")
        } catch let error as KernelError {
            #expect(error.phase == .geometry)
            #expect(error.code == .conflictingConstraints)
            #expect((error.residual ?? 0.0) > 0.1)
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func matchesPlanarSheetFramesWithVerifiedG2AndMergedFaceLineage() throws {
        let sourceID = FeatureID()
        let targetID = FeatureID()
        let featureID = FeatureID()
        let source = try PlanarSheetTestFixture.make(featureID: sourceID, tolerance: .standard)
        var target = try PlanarSheetTestFixture.make(featureID: targetID, tolerance: .standard)
        let targetBodyID = try bodyID(featureID: targetID, subshapes: target.subshapes)
        for vertexID in target.brep.vertices.keys {
            guard var vertex = target.brep.vertices[vertexID] else {
                throw TopologyError.missingReference("Surface match target fixture vertex is missing.")
            }
            vertex.point = vertex.point + .unitZ * 0.100
            target.brep.vertices[vertexID] = vertex
        }
        try DefaultPlanarBodyGeometryRebuilder().rebuild(
            featureID: targetID,
            bodyID: targetBodyID,
            in: &target.brep,
            tolerance: .standard
        )
        try ExactFacePcurveBuilder().populateMissingPcurves(in: &target.brep, tolerance: .standard)
        let combined = merged(source.brep, target.brep)
        var subshapes = source.subshapes.entries
        subshapes.merge(target.subshapes.entries) { _, target in target }
        var lineage = source.lineage
        lineage.merge(target.lineage) { _, target in target }
        let feature = FeatureNode(
            id: featureID,
            operation: .surfaceMatch(SurfaceMatchFeature(
                source: SurfaceOperationTargetReference(featureID: sourceID),
                target: SurfaceOperationTargetReference(featureID: targetID),
                sourceParameter: SurfaceParameter(u: 0.0, v: 0.0),
                targetParameter: SurfaceParameter(u: 0.0, v: 0.0),
                continuity: .curvature
            )),
            inputs: [
                FeatureInput(featureID: sourceID, role: .sheet),
                FeatureInput(featureID: targetID, role: .target),
            ],
            outputs: [FeatureOutput(role: .sheet)]
        )
        let result = try SurfaceMatchFeatureEvaluator().evaluate(
            feature: feature,
            context: EvaluationContext(
                parameters: ResolvedParameterTable(),
                brep: combined,
                profiles: [:],
                subshapes: SubshapeIndex(subshapes),
                lineage: lineage,
                tolerance: .standard
            )
        )

        try result.brep.validate(level: .exact, tolerance: .standard)
        #expect(result.brep.bodies.count == 1)
        #expect(result.brep.vertices.values.allSatisfy { abs($0.point.z - 0.100) <= 1.0e-12 })
        let faceLineage = try #require(result.lineage.values.first { $0.output.role == "face" })
        #expect(faceLineage.relation == .merged)
        #expect(faceLineage.parents.count == 2)
    }

    @Test(.timeLimit(.minutes(1)))
    func consumesSourceAndTargetWhilePreservingUnrelatedSheetIdentity() throws {
        let sourceID = FeatureID()
        let targetID = FeatureID()
        let unrelatedID = FeatureID()
        let source = try PlanarSheetTestFixture.make(featureID: sourceID, tolerance: .standard)
        var target = try PlanarSheetTestFixture.make(featureID: targetID, tolerance: .standard)
        let unrelated = try PlanarSheetTestFixture.make(featureID: unrelatedID, tolerance: .standard)
        let targetBodyID = try bodyID(featureID: targetID, subshapes: target.subshapes)
        for vertexID in target.brep.vertices.keys {
            guard var vertex = target.brep.vertices[vertexID] else {
                throw TopologyError.missingReference("Surface match target fixture vertex is missing.")
            }
            vertex.point = vertex.point + .unitZ * 0.100
            target.brep.vertices[vertexID] = vertex
        }
        try DefaultPlanarBodyGeometryRebuilder().rebuild(
            featureID: targetID,
            bodyID: targetBodyID,
            in: &target.brep,
            tolerance: .standard
        )
        try ExactFacePcurveBuilder().populateMissingPcurves(in: &target.brep, tolerance: .standard)
        let fixture = try EvaluationFixtureCombiner.combine([
            (source.brep, source.subshapes, source.lineage),
            (target.brep, target.subshapes, target.lineage),
            (unrelated.brep, unrelated.subshapes, unrelated.lineage),
        ])
        let result = try SurfaceMatchFeatureEvaluator().evaluate(
            feature: FeatureNode(
                id: FeatureID(),
                operation: .surfaceMatch(SurfaceMatchFeature(
                    source: SurfaceOperationTargetReference(featureID: sourceID),
                    target: SurfaceOperationTargetReference(featureID: targetID),
                    sourceParameter: SurfaceParameter(u: 0.0, v: 0.0),
                    targetParameter: SurfaceParameter(u: 0.0, v: 0.0),
                    continuity: .curvature
                )),
                inputs: [
                    FeatureInput(featureID: sourceID, role: .sheet),
                    FeatureInput(featureID: targetID, role: .target),
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

        try result.brep.validate(level: .exact, tolerance: .standard)
        #expect(result.brep.bodies.count == 2)
        #expect(result.removedSubshapeIDs.isDisjoint(with: unrelated.subshapes.entries.keys))
        #expect(unrelated.brep.bodies.keys.allSatisfy { result.brep.bodies[$0] == unrelated.brep.bodies[$0] })
    }

    private func bodyID(
        featureID: FeatureID,
        subshapes: SubshapeIndex
    ) throws -> BodyID {
        let subshapeID = SubshapeID(
            featureID: featureID,
            role: GeneratedSubshapeRole.body.rawValue,
            ordinal: 0
        )
        guard case let .body(bodyID) = subshapes[subshapeID] else {
            throw TopologyError.missingReference("Surface match fixture body is missing.")
        }
        return bodyID
    }

    private func merged(_ first: BRepModel, _ second: BRepModel) -> BRepModel {
        var result = first
        result.geometry.curves.merge(second.geometry.curves) { _, value in value }
        result.geometry.surfaces.merge(second.geometry.surfaces) { _, value in value }
        result.bodies.merge(second.bodies) { _, value in value }
        result.shells.merge(second.shells) { _, value in value }
        result.faces.merge(second.faces) { _, value in value }
        result.loops.merge(second.loops) { _, value in value }
        result.edges.merge(second.edges) { _, value in value }
        result.vertices.merge(second.vertices) { _, value in value }
        return result
    }

    private func matchFeature(
        sourceID: FeatureID,
        targetID: FeatureID,
        sourceParameter: SurfaceParameter,
        targetParameter: SurfaceParameter,
        continuity: SurfaceContinuityLevel
    ) -> FeatureNode {
        FeatureNode(
            operation: .surfaceMatch(SurfaceMatchFeature(
                source: SurfaceOperationTargetReference(featureID: sourceID),
                target: SurfaceOperationTargetReference(featureID: targetID),
                sourceParameter: sourceParameter,
                targetParameter: targetParameter,
                continuity: continuity
            )),
            inputs: [
                FeatureInput(featureID: sourceID, role: .sheet),
                FeatureInput(featureID: targetID, role: .target),
            ],
            outputs: [FeatureOutput(role: .sheet)]
        )
    }

    private func exactSurfaceSheet(
        featureID: FeatureID,
        surface: Surface3D,
        bounds: SurfaceMatchBounds
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
                stableID: "surfaceMatch:edge:\(index)",
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
                stableID: "surfaceMatch:shell",
                patches: [BRepSewingFacePatch(
                    stableID: "surfaceMatch:face",
                    surface: surface,
                    orientation: .forward,
                    loops: [BRepSewingLoop(
                        stableID: "surfaceMatch:outer",
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

    private func translated(
        _ surface: Surface3D,
        by offset: Vector3D
    ) -> Surface3D {
        switch surface {
        case let .plane(plane):
            return .plane(Plane3D(
                origin: plane.origin + offset,
                normal: plane.normal
            ))
        case let .cylinder(cylinder):
            return .cylinder(Cylinder3D(
                origin: cylinder.origin + offset,
                axis: cylinder.axis,
                radius: cylinder.radius
            ))
        case let .analytic(.plane(origin, normal)):
            return .analytic(.plane(origin: origin + offset, normal: normal))
        case let .analytic(.cylinder(origin, axis, radius)):
            return .analytic(.cylinder(
                origin: origin + offset,
                axis: axis,
                radius: radius
            ))
        case let .analytic(.cone(apex, axis, halfAngle)):
            return .analytic(.cone(
                apex: apex + offset,
                axis: axis,
                halfAngle: halfAngle
            ))
        case let .analytic(.sphere(center, radius)):
            return .analytic(.sphere(center: center + offset, radius: radius))
        case let .analytic(.torus(center, axis, majorRadius, minorRadius)):
            return .analytic(.torus(
                center: center + offset,
                axis: axis,
                majorRadius: majorRadius,
                minorRadius: minorRadius
            ))
        case let .bSpline(surface):
            return .bSpline(BSplineSurface3D(
                uDegree: surface.uDegree,
                vDegree: surface.vDegree,
                uKnots: surface.uKnots,
                vKnots: surface.vKnots,
                controlPoints: surface.controlPoints.map { row in
                    row.map { $0 + offset }
                },
                weights: surface.weights
            ))
        }
    }

    private static let exactSurfaceCases: [ExactSurfaceMatchCase] = {
        let bounds = SurfaceMatchBounds(
            lowerU: 0.2,
            upperU: 1.2,
            lowerV: -0.6,
            upperV: 0.6
        )
        return [
            ExactSurfaceMatchCase(
                name: "plane",
                surface: .plane(Plane3D(origin: .origin, normal: .unitZ)),
                bounds: bounds
            ),
            ExactSurfaceMatchCase(
                name: "cylinder",
                surface: .cylinder(Cylinder3D(
                    origin: .origin,
                    axis: .unitZ,
                    radius: 2.0
                )),
                bounds: bounds
            ),
            ExactSurfaceMatchCase(
                name: "analyticPlane",
                surface: .analytic(.plane(origin: .origin, normal: .unitZ)),
                bounds: bounds
            ),
            ExactSurfaceMatchCase(
                name: "analyticCylinder",
                surface: .analytic(.cylinder(
                    origin: .origin,
                    axis: .unitZ,
                    radius: 2.0
                )),
                bounds: bounds
            ),
            ExactSurfaceMatchCase(
                name: "cone",
                surface: .analytic(.cone(
                    apex: .origin,
                    axis: .unitZ,
                    halfAngle: 0.4
                )),
                bounds: SurfaceMatchBounds(
                    lowerU: bounds.lowerU,
                    upperU: bounds.upperU,
                    lowerV: 1.0,
                    upperV: 2.0
                )
            ),
            ExactSurfaceMatchCase(
                name: "sphere",
                surface: .analytic(.sphere(center: .origin, radius: 2.0)),
                bounds: bounds
            ),
            ExactSurfaceMatchCase(
                name: "torus",
                surface: .analytic(.torus(
                    center: .origin,
                    axis: .unitZ,
                    majorRadius: 3.0,
                    minorRadius: 0.5
                )),
                bounds: bounds
            ),
            ExactSurfaceMatchCase(
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
                bounds: SurfaceMatchBounds(
                    lowerU: 0.0,
                    upperU: 1.0,
                    lowerV: 0.0,
                    upperV: 1.0
                )
            ),
        ]
    }()
}

struct SurfaceMatchBounds: Sendable {
    let lowerU: Double
    let upperU: Double
    let lowerV: Double
    let upperV: Double
}

struct ExactSurfaceMatchCase: CustomTestStringConvertible, Sendable {
    let name: String
    let surface: Surface3D
    let bounds: SurfaceMatchBounds

    var testDescription: String { name }
}
