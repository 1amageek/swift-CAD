import CADCore
import CADGeometry
import CADIR
import CADModeling
import CADTopology
import Testing
@testable import CADKernel

@Suite("Procedural surface kernel integration")
struct ProceduralSurfaceKernelIntegrationTests {
    private let tolerance = ModelingTolerance(
        distance: 1.0e-6,
        angle: 1.0e-8,
        relative: 1.0e-9
    )

    @Test(.timeLimit(.minutes(1)))
    func certifiedIntersectionPcurveSewsAgainstItsOriginalRuledSurface() throws {
        let ruled = Surface3D.procedural(.ruled(RuledSurface3D(
            startBoundary: .line(Line3D(
                origin: .origin,
                direction: .unitX
            )),
            endBoundary: .line(Line3D(
                origin: Point3D(x: 0.0, y: 1.0, z: 1.0),
                direction: .unitX
            ))
        )))
        let plane = Surface3D.plane(Plane3D(
            origin: Point3D(x: 0.5, y: 0.0, z: 0.0),
            normal: .unitX
        ))
        let intersections = try DefaultSurfaceSurfaceIntersector().intersections(
            first: ruled,
            second: plane,
            tolerance: tolerance
        )
        guard case let .curve(section) = try #require(intersections.first) else {
            Issue.record("A ruled-surface section must produce a certified curve.")
            return
        }

        func liftedEdge(
            stableID: String,
            parameterCurve: SurfaceParameterCurve
        ) throws -> BRepSewingEdge {
            let lift = SurfaceLiftCurve3D(
                surface: ruled,
                parameterCurve: parameterCurve
            )
            return BRepSewingEdge(
                stableID: stableID,
                curve: .surfaceLift(lift),
                startParameter: 0.0,
                endParameter: 1.0,
                startPoint: try lift.point(
                    atNormalizedFraction: 0.0,
                    tolerance: tolerance
                ),
                endPoint: try lift.point(
                    atNormalizedFraction: 1.0,
                    tolerance: tolerance
                ),
                surfaceParameterCurve: parameterCurve
            )
        }

        let sectionStart = try section.surfaceParameter(
            on: .first,
            atNormalizedFraction: 0.0,
            tolerance: tolerance
        )
        let sectionEnd = try section.surfaceParameter(
            on: .first,
            atNormalizedFraction: 1.0,
            tolerance: tolerance
        )
        let sectionRunsDownward = sectionStart.v > sectionEnd.v
        let sectionPcurve = sectionRunsDownward
            ? section.firstSurfaceParameterCurve
            : try section.firstSurfaceParameterCurve.reversed(
                tolerance: tolerance
            )
        let sectionStartParameter = sectionRunsDownward ? 0.0 : 1.0
        let sectionEndParameter = sectionRunsDownward ? 1.0 : 0.0
        let sectionEdge = BRepSewingEdge(
            stableID: "ruled-section:intersection",
            curve: section.curve,
            startParameter: sectionStartParameter,
            endParameter: sectionEndParameter,
            startPoint: try section.curve.point(
                at: sectionStartParameter,
                tolerance: tolerance
            ),
            endPoint: try section.curve.point(
                at: sectionEndParameter,
                tolerance: tolerance
            ),
            surfaceParameterCurve: sectionPcurve
        )
        let sewn = try DefaultBRepSewer().sew(
            BRepSewingRequest(
                featureID: FeatureID(),
                bodyKind: .sheet,
                shells: [BRepSewingShell(
                    stableID: "ruled-section:shell",
                    patches: [BRepSewingFacePatch(
                        stableID: "ruled-section:face",
                        surface: ruled,
                        orientation: .forward,
                        loops: [BRepSewingLoop(
                            stableID: "ruled-section:outer",
                            role: .outer,
                            edges: [
                                try liftedEdge(
                                    stableID: "ruled-section:bottom",
                                    parameterCurve: .constantV(
                                        v: 0.0,
                                        uStart: 0.5,
                                        uEnd: 1.0
                                    )
                                ),
                                try liftedEdge(
                                    stableID: "ruled-section:right",
                                    parameterCurve: .constantU(
                                        u: 1.0,
                                        vStart: 0.0,
                                        vEnd: 1.0
                                    )
                                ),
                                try liftedEdge(
                                    stableID: "ruled-section:top",
                                    parameterCurve: .constantV(
                                        v: 1.0,
                                        uStart: 1.0,
                                        uEnd: 0.5
                                    )
                                ),
                                sectionEdge,
                            ]
                        )]
                    )]
                )]
            ),
            tolerance: tolerance
        )

        try sewn.brep.validate(level: .exact, tolerance: tolerance)
        #expect(sewn.brep.faces.count == 1)
        #expect(sewn.brep.edges.count == 4)
        #expect(sewn.brep.vertices.count == 4)
    }

    @Test(.timeLimit(.minutes(1)))
    func closestPointFallsBackToTheExactTrimBoundary() throws {
        let fixture = try makeFixture()
        let evaluator = SurfaceQueryEvaluator(tolerance: tolerance)
        let outsidePoint = try fixture.surface.point(
            u: 0.8,
            v: 0.5,
            tolerance: tolerance
        )
        let outsideNormal = try fixture.surface.normal(
            u: 0.8,
            v: 0.5,
            tolerance: tolerance
        )
        let query = outsidePoint + outsideNormal * 0.05

        let unrestricted = try evaluator.closestPoint(
            to: query,
            on: fixture.reference,
            in: fixture.document,
            options: SurfaceProjectionOptions(respectsTrimBounds: false)
        )
        #expect(abs(unrestricted.parameterReference.u - 0.8) <= 2.0e-5)
        #expect(abs(unrestricted.parameterReference.v - 0.5) <= 2.0e-5)

        let trimmed = try evaluator.closestPoint(
            to: query,
            on: fixture.reference,
            in: fixture.document
        )
        let expectedBoundaryPoint = try fixture.surface.point(
            u: 0.4,
            v: 0.5,
            tolerance: tolerance
        )
        #expect(abs(trimmed.parameterReference.u - 0.4) <= 2.0e-5)
        #expect(abs(trimmed.parameterReference.v - 0.5) <= 2.0e-5)
        #expect(trimmed.projectedPoint.isApproximatelyEqual(
            to: expectedBoundaryPoint,
            tolerance: 2.0e-5
        ))
    }

    @Test(.timeLimit(.minutes(1)))
    func closestPointCertifiesARectangularTrimCorner() throws {
        let fixture = try makeFixture()
        let evaluator = SurfaceQueryEvaluator(tolerance: tolerance)
        let outsidePoint = try fixture.surface.point(
            u: 0.6,
            v: 0.9,
            tolerance: tolerance
        )
        let outsideNormal = try fixture.surface.normal(
            u: 0.6,
            v: 0.9,
            tolerance: tolerance
        )
        let query = outsidePoint + outsideNormal * 0.05

        let projection = try evaluator.closestPoint(
            to: query,
            on: fixture.reference,
            in: fixture.document
        )
        let expectedCorner = try fixture.surface.point(
            u: 0.4,
            v: 0.8,
            tolerance: tolerance
        )

        #expect(abs(projection.parameterReference.u - 0.4) <= 2.0e-5)
        #expect(abs(projection.parameterReference.v - 0.8) <= 2.0e-5)
        #expect(projection.projectedPoint.isApproximatelyEqual(
            to: expectedCorner,
            tolerance: 2.0e-5
        ))
    }

    @Test(.timeLimit(.minutes(1)))
    func closestPointUsesExactEdgesForANonRectangularTrim() throws {
        let fixture = try makeTriangularFixture()
        let evaluator = SurfaceQueryEvaluator(tolerance: tolerance)
        let outsidePoint = try fixture.surface.point(
            u: 0.0,
            v: 0.1,
            tolerance: tolerance
        )
        let outsideNormal = try fixture.surface.normal(
            u: 0.0,
            v: 0.1,
            tolerance: tolerance
        )
        let query = outsidePoint + outsideNormal * 0.05

        let projection = try evaluator.closestPoint(
            to: query,
            on: fixture.reference,
            in: fixture.document
        )
        let expectedBoundaryPoint = try fixture.surface.point(
            u: 0.0,
            v: 0.2,
            tolerance: tolerance
        )

        #expect(abs(projection.parameterReference.u) <= 2.0e-5)
        #expect(abs(projection.parameterReference.v - 0.2) <= 2.0e-5)
        #expect(projection.projectedPoint.isApproximatelyEqual(
            to: expectedBoundaryPoint,
            tolerance: 2.0e-5
        ))
    }

    @Test(.timeLimit(.minutes(1)))
    func directionalProjectionIntersectsTheProceduralFace() throws {
        let fixture = try makeFixture()
        let evaluator = SurfaceQueryEvaluator(tolerance: tolerance)
        let target = try fixture.surface.point(
            u: 0.0,
            v: 0.5,
            tolerance: tolerance
        )
        let normal = try fixture.surface.normal(
            u: 0.0,
            v: 0.5,
            tolerance: tolerance
        )
        let source = target + normal * 0.1

        let projection = try evaluator.project(
            source,
            along: -normal,
            onto: fixture.reference,
            in: fixture.document,
            options: SurfaceDirectionalProjectionOptions(range: .ray)
        )

        #expect(projection.converged)
        #expect(abs(projection.parameterReference.u) <= 2.0e-5)
        #expect(abs(projection.parameterReference.v - 0.5) <= 2.0e-5)
        #expect(projection.projectedPoint.isApproximatelyEqual(
            to: target,
            tolerance: 2.0e-5
        ))
        #expect(abs(projection.signedDistanceAlongDirection - 0.1) <= 2.0e-5)
    }

    @Test(.timeLimit(.minutes(1)))
    func certifiedFaceBoundsContainTheTrimmedProceduralSurface() throws {
        let fixture = try makeFixture()
        let bounds = try BRepFaceBoundingBoxBuilder().bounds(
            for: fixture.faceID,
            in: fixture.document.brep,
            tolerance: tolerance
        )

        for vIndex in 0...8 {
            let v = 0.2 + 0.6 * Double(vIndex) / 8.0
            for uIndex in 0...8 {
                let u = -0.4 + 0.8 * Double(uIndex) / 8.0
                let point = try fixture.surface.point(
                    u: u,
                    v: v,
                    tolerance: tolerance
                )
                #expect(bounds.contains(point, tolerance: tolerance.distance))
            }
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func tessellationConsumesTheProceduralSurfaceWithFiniteNormals() throws {
        let fixture = try makeFixture()
        let meshes = try MeshTessellator(tolerance: tolerance).tessellate(
            model: fixture.document.brep,
            options: TessellationOptions(
                linearTolerance: 2.0e-3,
                angularTolerance: 2.0e-2,
                maxEdgeLength: 0.1
            )
        )
        let mesh = try #require(meshes.values.first)

        #expect(mesh.positions.count > 4)
        #expect(mesh.indices.count > 6)
        #expect(mesh.normals.count == mesh.positions.count)
        #expect(mesh.normals.allSatisfy { normal in
            normal.x.isFinite
                && normal.y.isFinite
                && normal.z.isFinite
                && abs(normal.length - 1.0) <= 1.0e-5
        })
    }

    private func makeFixture() throws -> Fixture {
        try makeFixture(
            stablePrefix: "procedural",
            parameters: [
                SurfaceParameter(u: -0.4, v: 0.2),
                SurfaceParameter(u: 0.4, v: 0.2),
                SurfaceParameter(u: 0.4, v: 0.8),
                SurfaceParameter(u: -0.4, v: 0.8),
            ],
            pcurves: [
                .constantV(v: 0.2, uStart: -0.4, uEnd: 0.4),
                .constantU(u: 0.4, vStart: 0.2, vEnd: 0.8),
                .constantV(v: 0.8, uStart: 0.4, uEnd: -0.4),
                .constantU(u: -0.4, vStart: 0.8, vEnd: 0.2),
            ]
        )
    }

    private func makeTriangularFixture() throws -> Fixture {
        try makeFixture(
            stablePrefix: "procedural-triangle",
            parameters: [
                SurfaceParameter(u: -0.4, v: 0.2),
                SurfaceParameter(u: 0.4, v: 0.2),
                SurfaceParameter(u: -0.4, v: 0.8),
            ],
            pcurves: [
                .constantV(v: 0.2, uStart: -0.4, uEnd: 0.4),
                .affine(
                    origin: Point2D(x: 0.4, y: 0.2),
                    direction: Point2D(x: -0.8, y: 0.6),
                    startParameter: 0.0,
                    endParameter: 1.0
                ),
                .constantU(u: -0.4, vStart: 0.8, vEnd: 0.2),
            ]
        )
    }

    private func makeFixture(
        stablePrefix: String,
        parameters: [SurfaceParameter],
        pcurves: [SurfaceParameterCurve]
    ) throws -> Fixture {
        let featureID = FeatureID()
        let surface = Surface3D.procedural(.offset(OffsetSurface3D(
            source: .bSpline(makeParabolicCylinder()),
            distance: 0.2
        )))
        let edges = try pcurves.indices.map { index in
            let curve = Curve3D.surfaceLift(SurfaceLiftCurve3D(
                surface: surface,
                parameterCurve: pcurves[index]
            ))
            return BRepSewingEdge(
                stableID: "\(stablePrefix):edge:\(index)",
                curve: curve,
                startParameter: 0.0,
                endParameter: 1.0,
                startPoint: try surface.point(
                    u: parameters[index].u,
                    v: parameters[index].v,
                    tolerance: tolerance
                ),
                endPoint: try surface.point(
                    u: parameters[(index + 1) % parameters.count].u,
                    v: parameters[(index + 1) % parameters.count].v,
                    tolerance: tolerance
                ),
                surfaceParameterCurve: pcurves[index]
            )
        }
        let sewn = try DefaultBRepSewer().sew(
            BRepSewingRequest(
                featureID: featureID,
                bodyKind: .sheet,
                shells: [BRepSewingShell(
                    stableID: "\(stablePrefix):shell",
                    patches: [BRepSewingFacePatch(
                        stableID: "\(stablePrefix):face",
                        surface: surface,
                        orientation: .forward,
                        loops: [BRepSewingLoop(
                            stableID: "\(stablePrefix):outer",
                            role: .outer,
                            edges: edges
                        )]
                    )]
                )]
            ),
            tolerance: tolerance
        )
        guard let faceEntry = sewn.subshapes.first(where: { _, reference in
            if case .face = reference { return true }
            return false
        }), case let .face(faceID) = faceEntry.value else {
            throw FeatureEvaluationError.missingInput(
                "Procedural surface fixture did not publish its face."
            )
        }
        let document = EvaluatedDocument(
            document: CADDocument(units: .meters),
            parameters: ResolvedParameterTable(),
            brep: sewn.brep,
            meshes: [:],
            caches: DocumentCaches(),
            subshapes: SubshapeIndex(sewn.subshapes),
            lineage: sewn.lineage,
            configuration: DocumentEvaluationConfiguration(
                tolerance: tolerance,
                tessellationOptions: .standard
            )
        )
        let reference = SurfaceReference(
            subshape: try document.stableSubshapeReference(
                for: faceEntry.key
            )
        )
        return Fixture(
            document: document,
            reference: reference,
            faceID: faceID,
            surface: surface
        )
    }

    private func makeParabolicCylinder() -> BSplineSurface3D {
        BSplineSurface3D(
            uDegree: 2,
            vDegree: 1,
            uKnots: [-1.0, -1.0, -1.0, 1.0, 1.0, 1.0],
            vKnots: [0.0, 0.0, 1.0, 1.0],
            controlPoints: [
                [
                    Point3D(x: -1.0, y: 0.0, z: 1.0),
                    Point3D(x: 0.0, y: 0.0, z: -1.0),
                    Point3D(x: 1.0, y: 0.0, z: 1.0),
                ],
                [
                    Point3D(x: -1.0, y: 1.0, z: 1.0),
                    Point3D(x: 0.0, y: 1.0, z: -1.0),
                    Point3D(x: 1.0, y: 1.0, z: 1.0),
                ],
            ]
        )
    }
}

private struct Fixture {
    let document: EvaluatedDocument
    let reference: SurfaceReference
    let faceID: FaceID
    let surface: Surface3D
}
