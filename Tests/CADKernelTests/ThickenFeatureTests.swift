import Testing
import CADCore
import CADGeometry
import CADIR
import CADModeling
import CADTopology
@testable import CADKernel

@Suite("Thicken feature")
struct ThickenFeatureTests {
    @Test(.timeLimit(.minutes(1)))
    func thickensFoldedPlanarSheetByIntersectingOffsetFacePlanes() throws {
        let tolerance = ModelingTolerance.standard
        let sourceFeatureID = FeatureID()
        let length = 0.04
        let width = 0.03
        let height = 0.02
        let thickness = 0.004
        let horizontal = Surface3D.plane(Plane3D(
            origin: .origin,
            normal: .unitZ
        ))
        let vertical = Surface3D.plane(Plane3D(
            origin: .origin,
            normal: .unitX
        ))
        let horizontalLoop = try planarLineLoop(
            stableID: "folded:horizontal",
            surface: horizontal,
            parameterCurves: [
                .constantV(v: 0.0, uStart: 0.0, uEnd: length),
                .constantU(u: length, vStart: 0.0, vEnd: width),
                .constantV(v: width, uStart: length, uEnd: 0.0),
                .constantU(u: 0.0, vStart: width, vEnd: 0.0),
            ],
            tolerance: tolerance
        )
        let verticalLoop = try planarLineLoop(
            stableID: "folded:vertical",
            surface: vertical,
            parameterCurves: [
                .constantV(v: 0.0, uStart: 0.0, uEnd: width),
                .constantU(u: width, vStart: 0.0, vEnd: height),
                .constantV(v: height, uStart: width, uEnd: 0.0),
                .constantU(u: 0.0, vStart: height, vEnd: 0.0),
            ],
            tolerance: tolerance
        )
        let source = try DefaultBRepSewer().sew(
            BRepSewingRequest(
                featureID: sourceFeatureID,
                bodyKind: .sheet,
                shells: [BRepSewingShell(
                    stableID: "folded:shell",
                    patches: [
                        BRepSewingFacePatch(
                            stableID: "folded:horizontal:face",
                            surface: horizontal,
                            orientation: .forward,
                            loops: [horizontalLoop]
                        ),
                        BRepSewingFacePatch(
                            stableID: "folded:vertical:face",
                            surface: vertical,
                            orientation: .forward,
                            loops: [verticalLoop]
                        ),
                    ]
                )]
            ),
            tolerance: tolerance
        )

        #expect(source.brep.faces.count == 2)
        #expect(source.brep.edges.count == 7)
        #expect(source.brep.vertices.count == 6)
        for side in [ThickenSide.positive, .negative, .symmetric] {
            let result = try evaluateThicken(
                source: source,
                sourceFeatureID: sourceFeatureID,
                thickness: thickness,
                side: side,
                tolerance: tolerance
            )

            try result.brep.validate(level: .volumetric, tolerance: tolerance)
            #expect(result.brep.faces.count == 10)
            #expect(result.brep.edges.count == 20)
            #expect(result.brep.vertices.count == 12)
            #expect(try result.brep.volume(tolerance: tolerance) > 0.0)
            let internalSeamDescendants = result.lineage.values.filter {
                $0.output.role == GeneratedSubshapeRole.edge.rawValue
                    && $0.parents.count == 1
                    && $0.relation == .split
            }
            #expect(internalSeamDescendants.isEmpty == false)
        }
        let positive = try evaluateThicken(
            source: source,
            sourceFeatureID: sourceFeatureID,
            thickness: thickness,
            side: .positive,
            tolerance: tolerance
        )
        let expectedPositiveVolume = width * (
            length * thickness
                + height * thickness
                - thickness * thickness
        )
        #expect(abs(
            try positive.brep.volume(tolerance: tolerance)
                - expectedPositiveVolume
        ) <= 1.0e-12)
    }

    @Test(.timeLimit(.minutes(1)))
    func thickensPlanarSheetWithInnerLoopAndExactInnerWalls() throws {
        let tolerance = ModelingTolerance.standard
        let sourceFeatureID = FeatureID()
        let surface = Surface3D.plane(Plane3D(
            origin: .origin,
            normal: .unitZ
        ))
        let source = try sewSheet(
            featureID: sourceFeatureID,
            surface: surface,
            loops: [
                (
                    .outer,
                    [
                        .constantV(v: 0.0, uStart: 0.0, uEnd: 0.04),
                        .constantU(u: 0.04, vStart: 0.0, vEnd: 0.03),
                        .constantV(v: 0.03, uStart: 0.04, uEnd: 0.0),
                        .constantU(u: 0.0, vStart: 0.03, vEnd: 0.0),
                    ]
                ),
                (
                    .inner,
                    [
                        .constantU(u: 0.01, vStart: 0.01, vEnd: 0.02),
                        .constantV(v: 0.02, uStart: 0.01, uEnd: 0.02),
                        .constantU(u: 0.02, vStart: 0.02, vEnd: 0.01),
                        .constantV(v: 0.01, uStart: 0.02, uEnd: 0.01),
                    ]
                ),
            ],
            tolerance: tolerance
        )
        let result = try evaluateThicken(
            source: source,
            sourceFeatureID: sourceFeatureID,
            thickness: 0.004,
            side: .positive,
            tolerance: tolerance
        )

        try result.brep.validate(level: .volumetric, tolerance: tolerance)
        #expect(result.brep.faces.count == 10)
        #expect(result.brep.edges.count == 24)
        #expect(result.brep.vertices.count == 16)
        let expectedVolume = (0.04 * 0.03 - 0.01 * 0.01) * 0.004
        #expect(abs(try result.brep.volume(tolerance: tolerance) - expectedVolume) <= 1.0e-12)
    }

    @Test(.timeLimit(.minutes(1)))
    func thickensRegularCurvedBSplineSheetWithExactOffsetCapsAndRuledWalls() throws {
        let tolerance = ModelingTolerance.standard
        let sourceFeatureID = FeatureID()
        let surface = Surface3D.bSpline(BSplineSurface3D(
            uDegree: 2,
            vDegree: 1,
            uKnots: [-1.0, -1.0, -1.0, 1.0, 1.0, 1.0],
            vKnots: [0.0, 0.0, 1.0, 1.0],
            controlPoints: [
                [
                    Point3D(x: -0.02, y: 0.0, z: 0.004),
                    Point3D(x: 0.0, y: 0.0, z: -0.004),
                    Point3D(x: 0.02, y: 0.0, z: 0.004),
                ],
                [
                    Point3D(x: -0.02, y: 0.03, z: 0.004),
                    Point3D(x: 0.0, y: 0.03, z: -0.004),
                    Point3D(x: 0.02, y: 0.03, z: 0.004),
                ],
            ]
        ))
        let parameters = [
            SurfaceParameter(u: -0.8, v: 0.1),
            SurfaceParameter(u: 0.8, v: 0.1),
            SurfaceParameter(u: 0.8, v: 0.9),
            SurfaceParameter(u: -0.8, v: 0.9),
        ]
        let parameterCurves: [SurfaceParameterCurve] = [
            .constantV(v: 0.1, uStart: -0.8, uEnd: 0.8),
            .constantU(u: 0.8, vStart: 0.1, vEnd: 0.9),
            .constantV(v: 0.9, uStart: 0.8, uEnd: -0.8),
            .constantU(u: -0.8, vStart: 0.9, vEnd: 0.1),
        ]
        let edges = try parameterCurves.indices.map { index in
            let curve = Curve3D.surfaceLift(SurfaceLiftCurve3D(
                surface: surface,
                parameterCurve: parameterCurves[index]
            ))
            return BRepSewingEdge(
                stableID: "curved-thicken:edge:\(index)",
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
                surfaceParameterCurve: parameterCurves[index]
            )
        }
        let source = try DefaultBRepSewer().sew(
            BRepSewingRequest(
                featureID: sourceFeatureID,
                bodyKind: .sheet,
                shells: [BRepSewingShell(
                    stableID: "curved-thicken:shell",
                    patches: [BRepSewingFacePatch(
                        stableID: "curved-thicken:face",
                        surface: surface,
                        orientation: .forward,
                        loops: [BRepSewingLoop(
                            stableID: "curved-thicken:outer",
                            role: .outer,
                            edges: edges
                        )]
                    )]
                )]
            ),
            tolerance: tolerance
        )
        let featureID = FeatureID()
        let result = try ThickenFeatureEvaluator(
            sewer: DefaultBRepSewer()
        ).evaluate(
            feature: FeatureNode(
                id: featureID,
                operation: .thicken(ThickenFeature(
                    target: ThickenTargetReference(featureID: sourceFeatureID),
                    thickness: .constant(.length(0.001, unit: .meter)),
                    side: .symmetric
                ))
            ),
            context: EvaluationContext(
                parameters: ResolvedParameterTable(),
                brep: source.brep,
                profiles: [:],
                subshapes: SubshapeIndex(source.subshapes),
                lineage: source.lineage,
                tolerance: tolerance
            )
        )

        try result.brep.validate(level: .volumetric, tolerance: tolerance)
        #expect(result.brep.faces.count == 6)
        #expect(result.brep.edges.count == 12)
        #expect(result.brep.vertices.count == 8)
        #expect(try result.brep.volume(tolerance: tolerance) > 0.0)
        let surfaces = result.brep.geometry.surfaces.values
        #expect(surfaces.filter {
            if case .procedural(.offset) = $0 { return true }
            return false
        }.count == 2)
        #expect(surfaces.filter {
            if case .procedural(.ruled) = $0 { return true }
            return false
        }.count == 4)
    }

    @Test(.timeLimit(.minutes(1)))
    func thickensPlanarSheetOnEveryDeclaredSide() throws {
        let fixture = try planarSheetFixture()
        let sheetFaceID = SubshapeID(
            featureID: fixture.sheetFeatureID,
            role: GeneratedSubshapeRole.face.rawValue,
            ordinal: 0
        )
        let sheetFace = try fixture.evaluated.stableSubshapeReference(for: sheetFaceID)
        let sourceFaceID = try #require(fixture.evaluated.subshapes[sheetFaceID]?.faceID)
        let sourceFace = try #require(fixture.evaluated.brep.faces[sourceFaceID])
        guard case let .plane(plane) = fixture.evaluated.brep.geometry.surfaces[sourceFace.surfaceID] else {
            Issue.record("Thicken fixture source must be planar.")
            return
        }
        let normal = sourceFace.orientation == .forward ? plane.normal : -plane.normal
        let sourceCoordinate = Vector3D(
            x: plane.origin.x,
            y: plane.origin.y,
            z: plane.origin.z
        ).dot(normal)
        let thickness = 0.004
        for side in [ThickenSide.positive, .negative, .symmetric] {
            var document = fixture.document
            let featureID = FeatureID()
            let operation = FeatureOperation.thicken(ThickenFeature(
                target: ThickenTargetReference(featureID: fixture.sheetFeatureID),
                thickness: .constant(.length(thickness, unit: .meter)),
                side: side
            ))
            let node = try FeatureNodeFactory.make(operation: operation, id: featureID, in: document, tolerance: .standard)
            document.designGraph.nodes[featureID] = node
            document.designGraph.order.append(featureID)
            document.designGraph.dependencies.append(DependencyEdge(source: fixture.sheetFeatureID, target: featureID))
            document.designGraph.revision = document.designGraph.revision.advanced()

            let evaluated = try DocumentEvaluator(tolerance: .standard, artifactPolicy: .deferred).evaluate(document)

            try evaluated.brep.validate(level: .volumetric, tolerance: .standard)
            #expect(evaluated.brep.faces.count == 6)
            #expect(evaluated.brep.edges.count == 12)
            #expect(evaluated.brep.vertices.count == 8)
            #expect(abs(try evaluated.brep.volume(tolerance: .standard) - 0.040 * 0.020 * thickness) <= 1.0e-12)
            let coordinates = evaluated.brep.vertices.values.map { vertex in
                Vector3D(x: vertex.point.x, y: vertex.point.y, z: vertex.point.z).dot(normal)
            }
            let lower = try #require(coordinates.min()) - sourceCoordinate
            let upper = try #require(coordinates.max()) - sourceCoordinate
            switch side {
            case .positive:
                #expect(abs(lower) <= 1.0e-12)
                #expect(abs(upper - thickness) <= 1.0e-12)
            case .negative:
                #expect(abs(lower + thickness) <= 1.0e-12)
                #expect(abs(upper) <= 1.0e-12)
            case .symmetric:
                #expect(abs(lower + 0.5 * thickness) <= 1.0e-12)
                #expect(abs(upper - 0.5 * thickness) <= 1.0e-12)
            }
            let faceDescendants = evaluated.lineage.values.filter {
                $0.output.featureID == featureID
                    && $0.output.role == GeneratedSubshapeRole.face.rawValue
                    && $0.parents.contains(sheetFace.subshapeID)
            }
            #expect(faceDescendants.count == 2)
            #expect(faceDescendants.allSatisfy { $0.relation == .split })
        }
    }

    private func planarSheetFixture() throws -> (
        document: CADDocument,
        sheetFeatureID: FeatureID,
        evaluated: EvaluatedDocument
    ) {
        var document = makeRectangleExtrudeDocument(documentUnits: .meters)
        let solidFeatureID = try #require(document.designGraph.order.last)
        let solid = try DocumentEvaluator(tolerance: .standard, artifactPolicy: .deferred).evaluate(document)
        let retainedID = SubshapeID(
            featureID: solidFeatureID,
            role: GeneratedSubshapeRole.startFace.rawValue,
            ordinal: 0
        )
        let removedFaces = try solid.subshapes.entries.keys.filter { subshapeID in
            guard subshapeID != retainedID,
                  case .face = solid.subshapes[subshapeID] else { return false }
            return true
        }.map { try solid.stableSubshapeReference(for: $0) }
        #expect(removedFaces.count == 5)
        let sheetFeatureID = FeatureID()
        let operation = FeatureOperation.faceDelete(FaceDeleteFeature(
            target: FaceDeleteTargetReference(featureID: solidFeatureID),
            faces: removedFaces
        ))
        let node = try FeatureNodeFactory.make(operation: operation, id: sheetFeatureID, in: document, tolerance: .standard)
        document.designGraph.nodes[sheetFeatureID] = node
        document.designGraph.order.append(sheetFeatureID)
        document.designGraph.dependencies.append(DependencyEdge(source: solidFeatureID, target: sheetFeatureID))
        document.designGraph.revision = document.designGraph.revision.advanced()
        let evaluated = try DocumentEvaluator(tolerance: .standard, artifactPolicy: .deferred).evaluate(document)
        #expect(evaluated.brep.bodies.values.first?.kind == .sheet)
        #expect(evaluated.brep.faces.count == 1)
        return (document, sheetFeatureID, evaluated)
    }

    private func sewSheet(
        featureID: FeatureID,
        surface: Surface3D,
        loops: [(role: LoopRole, curves: [SurfaceParameterCurve])],
        tolerance: ModelingTolerance
    ) throws -> BRepSewingResult {
        let sewingLoops = try loops.enumerated().map { loopIndex, loop in
            BRepSewingLoop(
                stableID: "thicken-sheet:loop:\(loopIndex)",
                role: loop.role,
                edges: try loop.curves.enumerated().map { edgeIndex, parameterCurve in
                    let curve = Curve3D.surfaceLift(SurfaceLiftCurve3D(
                        surface: surface,
                        parameterCurve: parameterCurve
                    ))
                    return BRepSewingEdge(
                        stableID: "thicken-sheet:loop:\(loopIndex):edge:\(edgeIndex)",
                        curve: curve,
                        startParameter: 0.0,
                        endParameter: 1.0,
                        startPoint: try curve.point(at: 0.0, tolerance: tolerance),
                        endPoint: try curve.point(at: 1.0, tolerance: tolerance),
                        surfaceParameterCurve: parameterCurve
                    )
                }
            )
        }
        return try DefaultBRepSewer().sew(
            BRepSewingRequest(
                featureID: featureID,
                bodyKind: .sheet,
                shells: [BRepSewingShell(
                    stableID: "thicken-sheet:shell",
                    patches: [BRepSewingFacePatch(
                        stableID: "thicken-sheet:face",
                        surface: surface,
                        orientation: .forward,
                        loops: sewingLoops
                    )]
                )]
            ),
            tolerance: tolerance
        )
    }

    private func planarLineLoop(
        stableID: String,
        surface: Surface3D,
        parameterCurves: [SurfaceParameterCurve],
        tolerance: ModelingTolerance
    ) throws -> BRepSewingLoop {
        BRepSewingLoop(
            stableID: "\(stableID):loop",
            role: .outer,
            edges: try parameterCurves.enumerated().map { index, parameterCurve in
                let startParameter = try parameterCurve.startParameter(
                    tolerance: tolerance
                )
                let endParameter = try parameterCurve.endParameter(
                    tolerance: tolerance
                )
                let start = try surface.point(
                    u: startParameter.u,
                    v: startParameter.v,
                    tolerance: tolerance
                )
                let end = try surface.point(
                    u: endParameter.u,
                    v: endParameter.v,
                    tolerance: tolerance
                )
                let delta = end - start
                return BRepSewingEdge(
                    stableID: "\(stableID):edge:\(index)",
                    curve: .line(Line3D(
                        origin: start,
                        direction: try delta.normalized(
                            tolerance: tolerance.distance
                        )
                    )),
                    startParameter: 0.0,
                    endParameter: delta.length,
                    startPoint: start,
                    endPoint: end,
                    surfaceParameterCurve: parameterCurve
                )
            }
        )
    }

    private func evaluateThicken(
        source: BRepSewingResult,
        sourceFeatureID: FeatureID,
        thickness: Double,
        side: ThickenSide,
        tolerance: ModelingTolerance
    ) throws -> EvaluationResult {
        try ThickenFeatureEvaluator(sewer: DefaultBRepSewer()).evaluate(
            feature: FeatureNode(
                operation: .thicken(ThickenFeature(
                    target: ThickenTargetReference(featureID: sourceFeatureID),
                    thickness: .constant(.length(thickness, unit: .meter)),
                    side: side
                ))
            ),
            context: EvaluationContext(
                parameters: ResolvedParameterTable(),
                brep: source.brep,
                profiles: [:],
                subshapes: SubshapeIndex(source.subshapes),
                lineage: source.lineage,
                tolerance: tolerance
            )
        )
    }
}

private extension TopologyReference {
    var faceID: FaceID? {
        if case let .face(faceID) = self { return faceID }
        return nil
    }
}
