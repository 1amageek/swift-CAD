import Testing
import Foundation
import CADCore
import CADIR
@testable import CADKernel

@Suite("CADKernel")
struct CADKernelTests {
    @Test(.timeLimit(.minutes(1)))
    func parameterResolverResolvesNestedReferences() throws {
        let widthID = ParameterID()
        let heightID = ParameterID()
        let table = ParameterTable(parameters: [
            widthID: Parameter(
                id: widthID,
                name: "width",
                expression: .constant(.length(40.0, unit: .millimeter)),
                kind: .length
            ),
            heightID: Parameter(
                id: heightID,
                name: "height",
                expression: .divide(.reference(widthID), .constant(.scalar(2.0))),
                kind: .length
            )
        ])

        let resolved = try ParameterResolver().resolve(table)
        #expect(abs(try resolved.value(for: heightID).value - 0.02) < 1.0e-12)
    }

    @Test(.timeLimit(.minutes(1)))
    func parameterResolverRejectsInvalidUnitAddition() {
        let widthID = ParameterID()
        let table = ParameterTable(parameters: [
            widthID: Parameter(
                id: widthID,
                name: "bad",
                expression: .add(
                    .constant(.length(1.0, unit: .meter)),
                    .constant(.angle(90.0, unit: .degree))
                ),
                kind: .length
            )
        ])

        #expect(throws: UnitError.self) {
            _ = try ParameterResolver().resolve(table)
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func parameterResolverRejectsParameterTableKeyMismatch() {
        let tableKey = ParameterID()
        let embeddedID = ParameterID()
        let table = ParameterTable(parameters: [
            tableKey: Parameter(
                id: embeddedID,
                name: "width",
                expression: .constant(.length(1.0, unit: .meter)),
                kind: .length
            )
        ])

        #expect(throws: ParameterError.self) {
            _ = try ParameterResolver().resolve(table)
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func parameterResolverEvaluatesBoundVariables() throws {
        let value = try ParameterResolver().evaluate(
            .variable("offset", .length),
            parameters: ResolvedParameterTable(),
            variables: ["offset": .length(5.0, unit: .millimeter)]
        )

        #expect(value.kind == .length)
        #expect(abs(value.value - 0.005) < 1.0e-12)
    }

    @Test(.timeLimit(.minutes(1)))
    func curveBridgeSolverCreatesTangentContinuousCubicBridge() throws {
        let start = Curve3D.line(Line3D(origin: .origin, direction: .unitX))
        let end = Curve3D.line(Line3D(
            origin: Point3D(x: 1.0, y: 1.0, z: 0.0),
            direction: .unitY
        ))
        let result = try CurveBridgeSolver().solve(CurveBridgeRequest(
            start: CurveBridgeEndpointConstraint(
                target: CurveContinuityTarget(curve: start, parameter: 0.0),
                requiredLevel: .tangent
            ),
            end: CurveBridgeEndpointConstraint(
                target: CurveContinuityTarget(curve: end, parameter: 0.0),
                requiredLevel: .tangent
            )
        ))

        let startPoint = try result.curve.point(at: 0.0)
        let endPoint = try result.curve.point(at: 1.0)

        #expect(result.curve.degree == 3)
        #expect(result.startContinuity.achievedLevel == .tangent)
        #expect(result.endContinuity.achievedLevel == .tangent)
        #expect(result.startContinuity.isSatisfied)
        #expect(result.endContinuity.isSatisfied)
        #expect(abs(startPoint.x) <= 1.0e-12)
        #expect(abs(startPoint.y) <= 1.0e-12)
        #expect(abs(endPoint.x - 1.0) <= 1.0e-12)
        #expect(abs(endPoint.y - 1.0) <= 1.0e-12)
    }

    @Test(.timeLimit(.minutes(1)))
    func curveBridgeSolverCreatesCurvatureContinuousQuinticBridge() throws {
        let start = Curve3D.line(Line3D(origin: .origin, direction: .unitX))
        let end = Curve3D.line(Line3D(
            origin: Point3D(x: 1.0, y: 0.0, z: 0.0),
            direction: .unitX
        ))
        let result = try CurveBridgeSolver().solve(CurveBridgeRequest(
            start: CurveBridgeEndpointConstraint(
                target: CurveContinuityTarget(curve: start, parameter: 0.0),
                requiredLevel: .curvature
            ),
            end: CurveBridgeEndpointConstraint(
                target: CurveContinuityTarget(curve: end, parameter: 0.0),
                requiredLevel: .curvature
            )
        ))

        #expect(result.curve.degree == 5)
        #expect(result.startContinuity.achievedLevel == .curvature)
        #expect(result.endContinuity.achievedLevel == .curvature)
        #expect(result.startContinuity.isSatisfied)
        #expect(result.endContinuity.isSatisfied)
        #expect(abs(result.startContinuity.deviation.curvatureVectorDistance) <= 1.0e-12)
        #expect(abs(result.endContinuity.deviation.curvatureVectorDistance) <= 1.0e-12)
    }

    @Test(.timeLimit(.minutes(1)))
    func sketchCurveSamplerEvaluatesLineParameter() throws {
        let sampler = SketchCurveSampler(samplesPerSegment: 4)
        let sample = try #require(sampler.lineSample(
            start: Point2D(x: 0.0, y: 0.0),
            end: Point2D(x: 4.0, y: 3.0),
            parameter: 0.25
        ))

        #expect(abs(sample.parameter - 0.25) <= 1.0e-12)
        #expect(abs(sample.point.x - 1.0) <= 1.0e-12)
        #expect(abs(sample.point.y - 0.75) <= 1.0e-12)
        #expect(abs(sample.tangent.x - 0.8) <= 1.0e-12)
        #expect(abs(sample.tangent.y - 0.6) <= 1.0e-12)
        #expect(sample.curvature == 0.0)
        #expect(abs(sampler.approximateLength(of: sampler.lineSamples(
            start: Point2D(x: 0.0, y: 0.0),
            end: Point2D(x: 4.0, y: 3.0)
        )) - 5.0) <= 1.0e-12)
    }

    @Test(.timeLimit(.minutes(1)))
    func sketchCurveSamplerEvaluatesWrappedArcParameter() throws {
        let sampler = SketchCurveSampler(samplesPerSegment: 4)
        let sample = try #require(sampler.arcSample(
            center: Point2D(x: 0.0, y: 0.0),
            radius: 2.0,
            startAngle: Double.pi * 1.5,
            endAngle: 0.0,
            parameter: 1.0
        ))

        #expect(abs(sample.point.x - 2.0) <= 1.0e-12)
        #expect(abs(sample.point.y) <= 1.0e-12)
        #expect(abs(sample.tangent.x) <= 1.0e-12)
        #expect(abs(sample.tangent.y - 1.0) <= 1.0e-12)
        #expect(abs(sample.curvature - 0.5) <= 1.0e-12)
    }

    @Test(.timeLimit(.minutes(1)))
    func sketchCurveSamplerEvaluatesCubicSplineDifferentialGeometry() throws {
        let sampler = SketchCurveSampler(samplesPerSegment: 8)
        let controlPoints = [
            Point2D(x: 0.0, y: 0.0),
            Point2D(x: 0.0, y: 1.0),
            Point2D(x: 1.0, y: 1.0),
            Point2D(x: 1.0, y: 0.0),
        ]
        let sample = try #require(sampler.splineSample(for: controlPoints, parameter: 0.5))

        #expect(abs(sample.point.x - 0.5) <= 1.0e-12)
        #expect(abs(sample.point.y - 0.75) <= 1.0e-12)
        #expect(abs(sample.tangent.x - 1.0) <= 1.0e-12)
        #expect(abs(sample.tangent.y) <= 1.0e-12)
        #expect(abs(sample.normal.x) <= 1.0e-12)
        #expect(abs(sample.normal.y - 1.0) <= 1.0e-12)
        #expect(abs(sample.curvature + 8.0 / 3.0) <= 1.0e-12)
    }

    @Test(.timeLimit(.minutes(1)))
    func curveBridgeSolverRejectsDegenerateBridgeEndpoints() {
        let start = Curve3D.line(Line3D(origin: .origin, direction: .unitX))
        let end = Curve3D.line(Line3D(origin: .origin, direction: .unitY))

        #expect(throws: GeometryError.self) {
            _ = try CurveBridgeSolver().solve(CurveBridgeRequest(
                start: CurveBridgeEndpointConstraint(
                    target: CurveContinuityTarget(curve: start, parameter: 0.0),
                    requiredLevel: .positional
                ),
                end: CurveBridgeEndpointConstraint(
                    target: CurveContinuityTarget(curve: end, parameter: 0.0),
                    requiredLevel: .positional
                )
            ))
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func curveEditFeatureEvaluatorMutatesExactBSplineCurve() throws {
        let sourceID = FeatureID()
        let editID = FeatureID()
        let source = CurveOutputReference(featureID: sourceID)
        let baseCurve = makeEditableBSplineCurve()
        let sourceCurve = EvaluatedCurve(
            sourceFeatureID: sourceID,
            source: .generatedFeature,
            kind: .spline,
            points: [
                try baseCurve.point(at: 0.0),
                try baseCurve.point(at: 0.5),
                try baseCurve.point(at: 1.0),
            ],
            plane: .xy,
            exactCurve: .bSpline(baseCurve)
        )
        let feature = FeatureNode(
            id: editID,
            operation: .curveEdit(CurveEditFeature(
                source: source,
                edits: [
                    .setControlPoint(CurveControlPointEdit(
                        target: CurveControlPointReference(curve: source, controlPointIndex: 1),
                        point: Point3D(x: 0.25, y: 1.5, z: 0.0)
                    )),
                    .setKnot(CurveKnotEdit(
                        target: CurveKnotReference(curve: source, knotIndex: 3),
                        value: 0.25
                    )),
                    .setWeight(CurveWeightEdit(
                        target: CurveControlPointReference(curve: source, controlPointIndex: 2),
                        value: 0.5
                    )),
                ],
                sampleCount: 9
            )),
            inputs: [FeatureInput(featureID: sourceID, role: .curve)],
            outputs: [FeatureOutput(role: .curve)]
        )
        let context = EvaluationContext(
            parameters: ResolvedParameterTable(),
            brep: BRepModel(),
            profiles: [:],
            curves: [sourceID: [sourceCurve]],
            tolerance: .standard
        )

        let result = try CurveEditFeatureEvaluator().evaluate(feature: feature, context: context)

        #expect(result.generatedCurves.count == 1)
        let editedCurve = try #require(result.generatedCurves.first)
        #expect(editedCurve.sourceFeatureID == editID)
        #expect(editedCurve.points.count == 9)
        #expect(editedCurve.plane == .xy)
        guard case let .bSpline(curve) = editedCurve.exactCurve else {
            Issue.record("Expected curve edit to preserve an exact B-spline curve.")
            return
        }
        #expect(curve.controlPoints[1] == Point3D(x: 0.25, y: 1.5, z: 0.0))
        #expect(abs(curve.knots[3] - 0.25) <= 1.0e-12)
        #expect(abs(curve.weights[2] - 0.5) <= 1.0e-12)
    }

    @Test(.timeLimit(.minutes(1)))
    func curveOffsetFeatureEvaluatorPreservesSourcePlaneMetadata() throws {
        let sourceID = FeatureID()
        let offsetID = FeatureID()
        let sourceCurve = EvaluatedCurve(
            sourceFeatureID: sourceID,
            source: .sketchEntity(SketchEntityID()),
            kind: .line,
            points: [
                Point3D(x: 0.0, y: 0.0, z: 0.0),
                Point3D(x: 0.01, y: 0.0, z: 0.0),
            ],
            plane: .xy,
            exactCurve: .line(Line3D(origin: .origin, direction: .unitX)),
            exactParameterDomain: .closed(0.0, 0.01)
        )
        let feature = FeatureNode(
            id: offsetID,
            operation: .curveOffset(CurveOffsetFeature(
                source: CurveOutputReference(featureID: sourceID),
                distance: .constant(.length(1.0, unit: .millimeter)),
                planeNormal: .unitZ
            )),
            inputs: [FeatureInput(featureID: sourceID, role: .curve)],
            outputs: [FeatureOutput(role: .curve)]
        )
        let context = EvaluationContext(
            parameters: ResolvedParameterTable(),
            brep: BRepModel(),
            profiles: [:],
            curves: [sourceID: [sourceCurve]],
            tolerance: .standard
        )

        let result = try CurveOffsetFeatureEvaluator().evaluate(feature: feature, context: context)
        let offsetCurve = try #require(result.generatedCurves.first)

        #expect(result.generatedCurves.count == 1)
        #expect(offsetCurve.sourceFeatureID == offsetID)
        #expect(offsetCurve.plane == .xy)
        #expect(offsetCurve.exactParameterDomain == .closed(0.0, 0.01))
    }

    @Test(.timeLimit(.minutes(1)))
    func parameterResolverRejectsInvalidVariableNames() {
        #expect(throws: ParameterError.self) {
            _ = try ParameterResolver().evaluate(
                .variable("bad name", .length),
                parameters: ResolvedParameterTable(),
                variables: ["bad name": .length(5.0, unit: .millimeter)]
            )
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func rectangleExtrudeCreatesClosedBoxBRepAndDeterministicMesh() throws {
        let document = makeRectangleExtrudeDocument()
        let evaluated = try DocumentEvaluator().evaluate(document)

        #expect(evaluated.brep.bodies.count == 1)
        #expect(evaluated.brep.shells.count == 1)
        #expect(evaluated.brep.faces.count == 6)
        #expect(evaluated.brep.edges.count == 12)
        #expect(evaluated.brep.vertices.count == 8)
        try evaluated.brep.validate()
        #expect(evaluated.caches.brep?.parameterRevision == document.parameters.revision)
        #expect(evaluated.generatedNames.values.filter(\.isEdge).count == 12)

        let mesh = try #require(evaluated.meshes.values.first)
        #expect(mesh.indices.count == 36)
        #expect(mesh.positions.count == 24)
        #expect(mesh.normals[0].z < -0.9)
        let firstNormal = try firstTriangleNormal(in: mesh)
        #expect(firstNormal.dot(mesh.normals[0]) > 0.9)

        let evaluatedAgain = try DocumentEvaluator().evaluate(document)
        #expect(evaluatedAgain.meshes.values.first?.indices == mesh.indices)
    }

    @Test(.timeLimit(.minutes(1)))
    func rectangleRevolveCreatesExactCylindricalBRep() throws {
        let document = makeAxisAlignedRectangleRevolveDocument()
        let evaluated = try DocumentEvaluator().evaluate(document)

        #expect(evaluated.brep.bodies.count == 1)
        #expect(evaluated.brep.shells.count == 1)
        #expect(evaluated.brep.faces.count == 12)
        #expect(evaluated.brep.geometry.surfaces.values.contains { surface in
            if case .cylinder = surface {
                return true
            }
            return false
        })
        try evaluated.brep.validate()
        #expect(evaluated.generatedNames.values.filter(\.isEdge).isEmpty == false)

        let mesh = try #require(evaluated.meshes.values.first)
        #expect(mesh.positions.isEmpty == false)
        #expect(mesh.indices.count > 0)
        #expect(mesh.indices.count % 3 == 0)
    }

    @Test(.timeLimit(.minutes(1)))
    func partialRectangleRevolveCreatesEndCaps() throws {
        let document = makeAxisAlignedRectangleRevolveDocument(
            angle: .constant(.angle(180.0, unit: .degree))
        )
        let evaluated = try DocumentEvaluator().evaluate(document)

        #expect(evaluated.brep.bodies.count == 1)
        #expect(evaluated.brep.faces.count == 8)
        #expect(evaluated.generatedNames.keys.contains(PersistentName(components: [
            .feature(try #require(document.designGraph.order.last)),
            .generated(GeneratedSubshapeRole.startFace.rawValue),
        ])))
        #expect(evaluated.generatedNames.keys.contains(PersistentName(components: [
            .feature(try #require(document.designGraph.order.last)),
            .generated(GeneratedSubshapeRole.endFace.rawValue),
        ])))
        try evaluated.brep.validate()
    }

    @Test(.timeLimit(.minutes(1)))
    func quarterRectangleRevolvePreservesProfileSideAndCapNormals() throws {
        let document = makeAxisAlignedRectangleRevolveDocument(
            angle: .constant(.angle(90.0, unit: .degree))
        )
        let revolveFeatureID = try #require(document.designGraph.order.last)
        let evaluated = try DocumentEvaluator().evaluate(document)
        let points = evaluated.brep.vertices.values.map(\.point)
        let startFaceNormal = try normal(
            for: PersistentName(components: [
                .feature(revolveFeatureID),
                .generated(GeneratedSubshapeRole.startFace.rawValue),
            ]),
            in: evaluated
        )
        let endFaceNormal = try normal(
            for: PersistentName(components: [
                .feature(revolveFeatureID),
                .generated(GeneratedSubshapeRole.endFace.rawValue),
            ]),
            in: evaluated
        )

        #expect(abs((points.map(\.x).max() ?? 0.0) - 0.020) <= 1.0e-12)
        #expect(abs(points.map(\.z).max() ?? 0.0) <= 1.0e-12)
        #expect(abs((points.map(\.z).min() ?? 0.0) + 0.020) <= 1.0e-12)
        #expect(startFaceNormal.dot(.unitZ) > 0.999)
        #expect(endFaceNormal.dot(-Vector3D.unitX) > 0.999)
        try evaluated.brep.validate()
    }

    @Test(.timeLimit(.minutes(1)))
    func revolveRejectsAxisOutsideProfilePlane() throws {
        let document = makeAxisAlignedRectangleRevolveDocument(
            axis: RevolveAxis(origin: .origin, direction: .unitZ),
            angle: .constant(.angle(90.0, unit: .degree))
        )

        do {
            _ = try DocumentEvaluator().evaluate(document)
            Issue.record("Revolve must reject axes outside the profile plane.")
        } catch FeatureEvaluationError.unsupportedOperation(let message) {
            #expect(message.contains("profile plane"))
        } catch {
            Issue.record("Expected unsupportedOperation for axis outside profile plane, got \(error).")
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func revolveRejectsProfilesCrossingAxis() throws {
        let document = makeCrossAxisRevolveDocument()

        do {
            _ = try DocumentEvaluator().evaluate(document)
            Issue.record("Revolve must reject profiles crossing the rotation axis.")
        } catch FeatureEvaluationError.unsupportedOperation(let message) {
            #expect(message.contains("one side"))
        } catch {
            Issue.record("Expected unsupportedOperation for profile crossing axis, got \(error).")
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func revolveRejectsConicalProfileUntilConeSurfaceExists() throws {
        let document = makeConicalRevolveDocument()

        #expect(throws: FeatureEvaluationError.self) {
            _ = try DocumentEvaluator().evaluate(document)
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func faceLoopOffsetSplitsRectangularCapFaceWithPersistentOffsetEdges() throws {
        var document = makeRectangleExtrudeDocument(documentUnits: .meters)
        let extrudeFeatureID = try #require(document.designGraph.order.last)
        let offsetFeatureID = FeatureID()
        let targetFaceName = PersistentName(components: [
            .feature(extrudeFeatureID),
            .generated(GeneratedSubshapeRole.startFace.rawValue),
        ])
        let offsetFeature = FeatureNode(
            id: offsetFeatureID,
            operation: .faceLoopOffset(
                FaceLoopOffsetFeature(
                    target: FaceLoopOffsetTargetReference(featureID: extrudeFeatureID),
                    facePersistentName: targetFaceName,
                    distance: .constant(.length(2.0, unit: .millimeter))
                )
            ),
            inputs: [FeatureInput(featureID: extrudeFeatureID, role: .target)],
            outputs: [FeatureOutput(role: .body)]
        )
        document.designGraph.nodes[offsetFeatureID] = offsetFeature
        document.designGraph.order.append(offsetFeatureID)
        document.designGraph.dependencies.append(DependencyEdge(source: extrudeFeatureID, target: offsetFeatureID))
        document.designGraph.revision = document.designGraph.revision.advanced()

        let evaluated = try DocumentEvaluator().evaluate(document)
        let offsetEdgeNames = evaluated.generatedNames.filter { name, reference in
            reference.isEdge &&
                name.components.contains(.feature(offsetFeatureID)) &&
                name.components.contains(.generated("faceLoopOffset"))
        }
        let centerFaceName = PersistentName(components: [
            .feature(offsetFeatureID),
            .generated("faceLoopOffset"),
            .subshape("centerFace"),
        ])

        #expect(evaluated.brep.faces.count == 7)
        #expect(evaluated.brep.edges.count == 16)
        #expect(evaluated.brep.vertices.count == 12)
        #expect(offsetEdgeNames.count == 4)
        #expect(evaluated.generatedNames[centerFaceName] != nil)
        #expect(evaluated.generatedNames[targetFaceName] != nil)
        try evaluated.brep.validate()

        guard case let .face(centerFaceID) = try #require(evaluated.generatedNames[centerFaceName]) else {
            Issue.record("Expected face loop offset center face to be named.")
            return
        }
        let centerFace = try #require(evaluated.brep.faces[centerFaceID])
        let centerLoopID = try #require(centerFace.loops.first)
        let centerLoop = try #require(evaluated.brep.loops[centerLoopID])
        let storedParameterCurve = try #require(centerLoop.edges.first?.surfaceParameterCurve)
        let trim = try SurfaceQueryEvaluator().trimCurve(
            SurfaceTrimReference(
                surface: SurfaceReference(faceName: centerFaceName),
                loopIndex: 0,
                edgeIndex: 0
            ),
            in: evaluated
        )
        #expect(centerLoop.edges.allSatisfy { $0.surfaceParameterCurve != nil })
        #expect(trim.parameterCurve == storedParameterCurve)

        let mesh = try #require(evaluated.meshes.values.first)
        #expect(mesh.indices.count > 36)
        #expect(mesh.indices.count % 3 == 0)
    }

    @Test(.timeLimit(.minutes(1)))
    func faceKnifeSplitsPlanarFaceWithPersistentKnifeTopology() throws {
        var document = makeRectangleExtrudeDocument(documentUnits: .meters)
        let extrudeFeatureID = try #require(document.designGraph.order.last)
        let knifeFeatureID = FeatureID()
        let targetFaceName = PersistentName(components: [
            .feature(extrudeFeatureID),
            .generated(GeneratedSubshapeRole.startFace.rawValue),
        ])
        let knifeFeature = FeatureNode(
            id: knifeFeatureID,
            operation: .faceKnife(
                FaceKnifeFeature(
                    target: FaceKnifeTargetReference(featureID: extrudeFeatureID),
                    facePersistentName: targetFaceName,
                    loop: [
                        Point3D(x: -0.01, y: -0.005, z: 0.0),
                        Point3D(x: 0.01, y: -0.005, z: 0.0),
                        Point3D(x: 0.01, y: 0.005, z: 0.0),
                        Point3D(x: -0.01, y: 0.005, z: 0.0),
                    ]
                )
            ),
            inputs: [FeatureInput(featureID: extrudeFeatureID, role: .target)],
            outputs: [FeatureOutput(role: .body)]
        )
        document.designGraph.nodes[knifeFeatureID] = knifeFeature
        document.designGraph.order.append(knifeFeatureID)
        document.designGraph.dependencies.append(DependencyEdge(source: extrudeFeatureID, target: knifeFeatureID))
        document.designGraph.revision = document.designGraph.revision.advanced()

        let evaluated = try DocumentEvaluator().evaluate(document)
        let knifeEdgeNames = evaluated.generatedNames.filter { name, reference in
            reference.isEdge &&
                name.components.contains(.feature(knifeFeatureID)) &&
                name.components.contains(.generated("faceKnife")) &&
                name.components.contains(.subshape("knifeEdge"))
        }
        let faceKnifeFaceNames = evaluated.generatedNames.filter { name, reference in
            reference.isFace &&
                name.components.contains(.feature(knifeFeatureID)) &&
                name.components.contains(.generated("faceKnife"))
        }
        let centerFaceName = PersistentName(components: [
            .feature(knifeFeatureID),
            .generated("faceKnife"),
            .subshape("centerFace"),
        ])

        #expect(evaluated.brep.faces.count == 7)
        #expect(evaluated.brep.edges.count == 16)
        #expect(evaluated.brep.vertices.count == 12)
        #expect(knifeEdgeNames.count == 4)
        #expect(faceKnifeFaceNames.count == 7)
        #expect(evaluated.generatedNames[centerFaceName] != nil)
        #expect(evaluated.generatedNames[targetFaceName] != nil)
        try evaluated.brep.validate()

        guard case let .face(centerFaceID) = try #require(evaluated.generatedNames[centerFaceName]) else {
            Issue.record("Expected face knife center face to be named.")
            return
        }
        let centerFace = try #require(evaluated.brep.faces[centerFaceID])
        let centerLoopID = try #require(centerFace.loops.first)
        let centerLoop = try #require(evaluated.brep.loops[centerLoopID])
        let storedParameterCurve = try #require(centerLoop.edges.first?.surfaceParameterCurve)
        let trim = try SurfaceQueryEvaluator().trimCurve(
            SurfaceTrimReference(
                surface: SurfaceReference(faceName: centerFaceName),
                loopIndex: 0,
                edgeIndex: 0
            ),
            in: evaluated
        )
        #expect(centerLoop.edges.allSatisfy { $0.surfaceParameterCurve != nil })
        #expect(trim.parameterCurve == storedParameterCurve)

        let mesh = try #require(evaluated.meshes.values.first)
        #expect(mesh.indices.count > 36)
        #expect(mesh.indices.count % 3 == 0)
    }

    @Test(.timeLimit(.minutes(1)))
    func faceKnifeSplitsPlanarFaceWithConcaveLoop() throws {
        var document = makeRectangleExtrudeDocument(documentUnits: .meters)
        let extrudeFeatureID = try #require(document.designGraph.order.last)
        let knifeFeatureID = FeatureID()
        let targetFaceName = PersistentName(components: [
            .feature(extrudeFeatureID),
            .generated(GeneratedSubshapeRole.startFace.rawValue),
        ])
        let knifeFeature = FeatureNode(
            id: knifeFeatureID,
            operation: .faceKnife(
                FaceKnifeFeature(
                    target: FaceKnifeTargetReference(featureID: extrudeFeatureID),
                    facePersistentName: targetFaceName,
                    loop: [
                        Point3D(x: -0.012, y: -0.006, z: 0.0),
                        Point3D(x: 0.012, y: -0.006, z: 0.0),
                        Point3D(x: 0.004, y: 0.0, z: 0.0),
                        Point3D(x: 0.012, y: 0.006, z: 0.0),
                        Point3D(x: -0.012, y: 0.006, z: 0.0),
                    ]
                )
            ),
            inputs: [FeatureInput(featureID: extrudeFeatureID, role: .target)],
            outputs: [FeatureOutput(role: .body)]
        )
        document.designGraph.nodes[knifeFeatureID] = knifeFeature
        document.designGraph.order.append(knifeFeatureID)
        document.designGraph.dependencies.append(DependencyEdge(source: extrudeFeatureID, target: knifeFeatureID))
        document.designGraph.revision = document.designGraph.revision.advanced()

        let evaluated = try DocumentEvaluator().evaluate(document)
        let knifeEdgeNames = evaluated.generatedNames.filter { name, reference in
            reference.isEdge &&
                name.components.contains(.feature(knifeFeatureID)) &&
                name.components.contains(.generated("faceKnife")) &&
                name.components.contains(.subshape("knifeEdge"))
        }
        let faceKnifeFaceNames = evaluated.generatedNames.filter { name, reference in
            reference.isFace &&
                name.components.contains(.feature(knifeFeatureID)) &&
                name.components.contains(.generated("faceKnife"))
        }
        let centerFaceName = PersistentName(components: [
            .feature(knifeFeatureID),
            .generated("faceKnife"),
            .subshape("centerFace"),
        ])

        #expect(evaluated.brep.faces.count == 7)
        #expect(evaluated.brep.edges.count == 17)
        #expect(evaluated.brep.vertices.count == 13)
        #expect(knifeEdgeNames.count == 5)
        #expect(faceKnifeFaceNames.count == 7)
        #expect(evaluated.generatedNames[centerFaceName] != nil)
        try evaluated.brep.validate()

        let mesh = try #require(evaluated.meshes.values.first)
        #expect(mesh.indices.count > 36)
        #expect(mesh.indices.count % 3 == 0)
    }

    @Test(.timeLimit(.minutes(1)))
    func faceLoopOffsetRejectsNonRectangularFourEdgeFace() throws {
        var document = makeParallelogramExtrudeDocument(documentUnits: .meters)
        let extrudeFeatureID = try #require(document.designGraph.order.last)
        let offsetFeatureID = FeatureID()
        let targetFaceName = PersistentName(components: [
            .feature(extrudeFeatureID),
            .generated(GeneratedSubshapeRole.startFace.rawValue),
        ])
        let offsetFeature = FeatureNode(
            id: offsetFeatureID,
            operation: .faceLoopOffset(
                FaceLoopOffsetFeature(
                    target: FaceLoopOffsetTargetReference(featureID: extrudeFeatureID),
                    facePersistentName: targetFaceName,
                    distance: .constant(.length(2.0, unit: .millimeter))
                )
            ),
            inputs: [FeatureInput(featureID: extrudeFeatureID, role: .target)],
            outputs: [FeatureOutput(role: .body)]
        )
        document.designGraph.nodes[offsetFeatureID] = offsetFeature
        document.designGraph.order.append(offsetFeatureID)
        document.designGraph.dependencies.append(DependencyEdge(source: extrudeFeatureID, target: offsetFeatureID))
        document.designGraph.revision = document.designGraph.revision.advanced()

        #expect(throws: FeatureEvaluationError.self) {
            _ = try DocumentEvaluator().evaluate(document)
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func edgeOffsetSplitsRectangularSupportFaceAndBoundaryEdges() throws {
        var document = makeRectangleExtrudeDocument(documentUnits: .meters)
        let extrudeFeatureID = try #require(document.designGraph.order.last)
        let offsetFeatureID = FeatureID()
        let selectedEdgeName = PersistentName(components: [
            .feature(extrudeFeatureID),
            .generated(GeneratedSubshapeRole.edge.rawValue),
            .index(0),
        ])
        let removedNextEdgeName = PersistentName(components: [
            .feature(extrudeFeatureID),
            .generated(GeneratedSubshapeRole.edge.rawValue),
            .index(1),
        ])
        let removedPreviousEdgeName = PersistentName(components: [
            .feature(extrudeFeatureID),
            .generated(GeneratedSubshapeRole.edge.rawValue),
            .index(3),
        ])
        let supportFaceName = PersistentName(components: [
            .feature(extrudeFeatureID),
            .generated(GeneratedSubshapeRole.startFace.rawValue),
        ])
        let offsetFeature = FeatureNode(
            id: offsetFeatureID,
            operation: .edgeOffset(
                EdgeOffsetFeature(
                    target: EdgeOffsetTargetReference(featureID: extrudeFeatureID),
                    edgePersistentName: selectedEdgeName,
                    supportFacePersistentName: supportFaceName,
                    distance: .constant(.length(2.0, unit: .millimeter)),
                    gapFill: .linear
                )
            ),
            inputs: [FeatureInput(featureID: extrudeFeatureID, role: .target)],
            outputs: [FeatureOutput(role: .body)]
        )
        document.designGraph.nodes[offsetFeatureID] = offsetFeature
        document.designGraph.order.append(offsetFeatureID)
        document.designGraph.dependencies.append(DependencyEdge(source: extrudeFeatureID, target: offsetFeatureID))
        document.designGraph.revision = document.designGraph.revision.advanced()

        let evaluated = try DocumentEvaluator().evaluate(document)
        let offsetEdgeName = PersistentName(components: [
            .feature(offsetFeatureID),
            .generated("edgeOffset"),
            .subshape("offsetEdge"),
        ])
        let remainderFaceName = PersistentName(components: [
            .feature(offsetFeatureID),
            .generated("edgeOffset"),
            .subshape("remainderFace"),
        ])

        #expect(evaluated.brep.faces.count == 7)
        #expect(evaluated.brep.edges.count == 15)
        #expect(evaluated.brep.vertices.count == 10)
        #expect(evaluated.generatedNames[selectedEdgeName]?.isEdge == true)
        #expect(evaluated.generatedNames[removedNextEdgeName] == nil)
        #expect(evaluated.generatedNames[removedPreviousEdgeName] == nil)
        #expect(evaluated.generatedNames[offsetEdgeName]?.isEdge == true)
        #expect(evaluated.generatedNames[remainderFaceName]?.isFace == true)
        try evaluated.brep.validate()

        let mesh = try #require(evaluated.meshes.values.first)
        #expect(mesh.indices.count > 36)
        #expect(mesh.indices.count % 3 == 0)
    }

    @Test(.timeLimit(.minutes(1)))
    func symmetricEdgeOffsetSplitsBothAdjacentRectangularSupportFaces() throws {
        var document = makeRectangleExtrudeDocument(documentUnits: .meters)
        let extrudeFeatureID = try #require(document.designGraph.order.last)
        let offsetFeatureID = FeatureID()
        let selectedEdgeName = PersistentName(components: [
            .feature(extrudeFeatureID),
            .generated(GeneratedSubshapeRole.edge.rawValue),
            .index(0),
        ])
        let supportFaceName = PersistentName(components: [
            .feature(extrudeFeatureID),
            .generated(GeneratedSubshapeRole.startFace.rawValue),
        ])
        let offsetFeature = FeatureNode(
            id: offsetFeatureID,
            operation: .edgeOffset(
                EdgeOffsetFeature(
                    target: EdgeOffsetTargetReference(featureID: extrudeFeatureID),
                    edgePersistentName: selectedEdgeName,
                    supportFacePersistentName: supportFaceName,
                    distance: .constant(.length(2.0, unit: .millimeter)),
                    isSymmetric: true,
                    gapFill: .linear
                )
            ),
            inputs: [FeatureInput(featureID: extrudeFeatureID, role: .target)],
            outputs: [FeatureOutput(role: .body)]
        )
        document.designGraph.nodes[offsetFeatureID] = offsetFeature
        document.designGraph.order.append(offsetFeatureID)
        document.designGraph.dependencies.append(DependencyEdge(source: extrudeFeatureID, target: offsetFeatureID))
        document.designGraph.revision = document.designGraph.revision.advanced()

        let evaluated = try DocumentEvaluator().evaluate(document)
        let firstOffsetEdgeName = PersistentName(components: [
            .feature(offsetFeatureID),
            .generated("edgeOffset"),
            .subshape("offsetEdge"),
            .index(0),
        ])
        let secondOffsetEdgeName = PersistentName(components: [
            .feature(offsetFeatureID),
            .generated("edgeOffset"),
            .subshape("offsetEdge"),
            .index(1),
        ])
        let firstRemainderFaceName = PersistentName(components: [
            .feature(offsetFeatureID),
            .generated("edgeOffset"),
            .subshape("remainderFace"),
            .index(0),
        ])
        let secondRemainderFaceName = PersistentName(components: [
            .feature(offsetFeatureID),
            .generated("edgeOffset"),
            .subshape("remainderFace"),
            .index(1),
        ])

        #expect(evaluated.brep.faces.count == 8)
        #expect(evaluated.brep.edges.count == 18)
        #expect(evaluated.brep.vertices.count == 12)
        #expect(evaluated.generatedNames[selectedEdgeName]?.isEdge == true)
        #expect(evaluated.generatedNames[firstOffsetEdgeName]?.isEdge == true)
        #expect(evaluated.generatedNames[secondOffsetEdgeName]?.isEdge == true)
        #expect(evaluated.generatedNames[firstRemainderFaceName]?.isFace == true)
        #expect(evaluated.generatedNames[secondRemainderFaceName]?.isFace == true)
        try evaluated.brep.validate()

        let mesh = try #require(evaluated.meshes.values.first)
        #expect(mesh.indices.count > 36)
        #expect(mesh.indices.count % 3 == 0)
    }

    @Test(.timeLimit(.minutes(1)))
    func straightPathSweepCreatesClosedPrismaticBRep() throws {
        let document = makeStraightPathSweepDocument()
        let evaluated = try DocumentEvaluator().evaluate(document)

        #expect(evaluated.brep.bodies.count == 1)
        #expect(evaluated.brep.shells.count == 1)
        #expect(evaluated.brep.faces.count == 6)
        #expect(evaluated.brep.edges.count == 12)
        #expect(evaluated.brep.vertices.count == 8)
        try evaluated.brep.validate()
        #expect(evaluated.generatedNames.values.filter(\.isEdge).count == 12)

        let mesh = try #require(evaluated.meshes.values.first)
        #expect(mesh.indices.count == 36)
        #expect(mesh.positions.count == 24)
    }

    @Test(.timeLimit(.minutes(1)))
    func connectedLinePathSweepCreatesPolygonalBRep() throws {
        let document = makeStraightPathSweepDocument(
            width: 2.0,
            height: 1.0,
            pathSketch: connectedLinePathSketch(unit: .millimeter)
        )
        let evaluated = try DocumentEvaluator().evaluate(document)

        #expect(evaluated.brep.bodies.count == 1)
        #expect(evaluated.brep.shells.count == 1)
        #expect(evaluated.brep.vertices.count > 8)
        #expect(evaluated.brep.faces.count > 6)
        try evaluated.brep.validate()

        let mesh = try #require(evaluated.meshes.values.first)
        #expect(mesh.positions.count > 24)
        #expect(mesh.indices.count > 36)
        #expect(mesh.indices.count % 3 == 0)
    }

    @Test(.timeLimit(.minutes(1)))
    func disconnectedLinePathSweepRejectsPathBeforeTopologyBuild() throws {
        let document = makeStraightPathSweepDocument(
            width: 2.0,
            height: 1.0,
            pathSketch: disconnectedLinePathSketch(unit: .millimeter)
        )

        do {
            _ = try DocumentEvaluator().evaluate(document)
            Issue.record("Disconnected multi-curve sweep paths must be rejected.")
        } catch let error as SketchError {
            guard case .unsupportedEntity(let message) = error else {
                Issue.record("Expected unsupportedEntity for disconnected sweep path, got \(error).")
                return
            }
            #expect(message.contains("Sweep path requires connected open curve segments."))
        } catch {
            Issue.record("Expected SketchError for disconnected sweep path, got \(error).")
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func bridgeCurveFeatureEvaluatorProducesGeneratedCurve() throws {
        let bridgeFeatureID = FeatureID()
        let feature = FeatureNode(
            id: bridgeFeatureID,
            operation: .bridgeCurve(makeZAxisBridgeCurveFeature(sampleCount: 17)),
            outputs: [FeatureOutput(role: .curve)]
        )
        let result = try DefaultFeatureEvaluator().evaluate(
            feature: feature,
            context: EvaluationContext(
                parameters: ResolvedParameterTable(),
                brep: BRepModel(),
                profiles: [:],
                tolerance: .standard
            )
        )

        #expect(result.generatedCurves.count == 1)
        let curve = try #require(result.generatedCurves.first)
        #expect(curve.sourceFeatureID == bridgeFeatureID)
        #expect(curve.source == EvaluatedCurveSource.generatedFeature)
        #expect(curve.kind == EvaluatedCurveKind.spline)
        #expect(curve.points.count == 17)

        let exactRepresentation = try #require(curve.exactCurve)
        guard case let .bSpline(exactCurve) = exactRepresentation else {
            Issue.record("Bridge curve feature must preserve the exact B-spline representation.")
            return
        }
        #expect(exactCurve.degree == 3)
        #expect(abs(try exactCurve.point(at: 0.0).z) <= 1.0e-12)
        #expect(abs(try exactCurve.point(at: 1.0).z - 0.01) <= 1.0e-12)
    }

    @Test(.timeLimit(.minutes(1)))
    func bridgeCurveFeatureCanDriveSweepPath() throws {
        let document = makeBridgeCurveSweepDocument()
        let evaluated = try DocumentEvaluator().evaluate(document)

        #expect(evaluated.brep.bodies.count == 1)
        #expect(evaluated.brep.faces.count == 6)
        try evaluated.brep.validate()
        try expectBounds(
            evaluated.brep,
            minimum: Point3D(x: -0.020, y: -0.010, z: 0.0),
            maximum: Point3D(x: 0.020, y: 0.010, z: 0.010)
        )
    }

    @Test(.timeLimit(.minutes(1)))
    func evaluatedDocumentExposesCurveOutputsForSelection() throws {
        let document = makeStraightPathSweepDocument()
        let evaluated = try DocumentEvaluator().evaluate(document)
        let profileFeatureID = try #require(document.designGraph.order.first)
        let pathFeatureID = try #require(document.designGraph.order.dropFirst().first)

        let profileCurves = try #require(evaluated.curves[profileFeatureID])
        let pathCurves = try #require(evaluated.curves[pathFeatureID])
        #expect(profileCurves.count == 4)
        #expect(pathCurves.count == 1)

        let pathReference = CurveOutputReference(featureID: pathFeatureID)
        let midpoint = try CurveQueryEvaluator().midpoint(of: pathReference, in: evaluated)
        #expect(midpoint.isExact)
        #expect(abs((midpoint.tangent?.z ?? 0.0) - 1.0) <= 1.0e-12)
        #expect(abs(midpoint.point.z - 0.005) <= 1.0e-12)
    }

    @Test(.timeLimit(.minutes(1)))
    func edgeQueryEvaluatorResolvesExtrudeEdgeFramesAndProjection() throws {
        let document = makeRectangleExtrudeDocument()
        let evaluated = try DocumentEvaluator().evaluate(document)
        let extrudeFeatureID = try #require(document.designGraph.order.last)
        let edgeName = PersistentName(components: [
            .feature(extrudeFeatureID),
            .generated(GeneratedSubshapeRole.edge.rawValue),
            .index(0),
        ])
        let edgeReference = EdgeReference(edgeName: edgeName)
        let evaluator = EdgeQueryEvaluator()

        let resolved = try evaluator.resolve(edgeReference, in: evaluated)
        guard case .line = resolved.curve else {
            Issue.record("Expected the queried rectangle edge to resolve to a line curve.")
            return
        }

        let endpoints = try evaluator.endpoints(of: edgeReference, in: evaluated)
        let midpoint = try evaluator.midpoint(of: edgeReference, in: evaluated)
        let expectedMidpoint = endpoints.start + (endpoints.end - endpoints.start) * 0.5

        #expect(midpoint.point.isApproximatelyEqual(to: expectedMidpoint, tolerance: 1.0e-12))
        #expect(abs(midpoint.tangent.length - 1.0) <= 1.0e-12)
        #expect(abs(midpoint.curvature) <= 1.0e-12)

        let sourcePoint = midpoint.point + Vector3D.unitZ * 0.005
        let closest = try evaluator.closestPoint(to: sourcePoint, on: edgeReference, in: evaluated)
        #expect(closest.converged)
        #expect(closest.projectedPoint.isApproximatelyEqual(to: midpoint.point, tolerance: 1.0e-12))
        #expect(abs(closest.distance - 0.005) <= 1.0e-12)

        let projected = try evaluator.project(
            sourcePoint,
            along: -Vector3D.unitZ,
            onto: edgeReference,
            in: evaluated,
            options: EdgeDirectionalProjectionOptions(range: .ray)
        )
        #expect(projected.converged)
        #expect(projected.projectedPoint.isApproximatelyEqual(to: midpoint.point, tolerance: 1.0e-12))
        #expect(abs(projected.signedDistanceAlongDirection - 0.005) <= 1.0e-12)
        #expect(projected.lineDistance <= 1.0e-12)
    }

    @Test(.timeLimit(.minutes(1)))
    func snapQueryEvaluatorRanksEdgeCandidateForPointNearEdge() throws {
        let document = makeRectangleExtrudeDocument()
        let evaluated = try DocumentEvaluator().evaluate(document)
        let result = try SnapQueryEvaluator().candidates(
            near: Point3D(x: 0.0, y: -0.012, z: -0.002),
            in: evaluated,
            options: SnapQueryOptions(maximumDistance: 0.003, maximumCandidateCount: 4)
        )

        let first = try #require(result.candidates.first)
        #expect(first.kind == .edge)
        #expect(abs(first.distance - sqrt(8.0e-6)) <= 1.0e-12)
        #expect(first.point.isApproximatelyEqual(to: Point3D(x: 0.0, y: -0.010, z: 0.0), tolerance: 1.0e-12))
        guard case .edge(.parameter(let reference)) = first.selection else {
            Issue.record("Expected snap candidate to carry an edge parameter reference.")
            return
        }
        #expect(abs(reference.parameter - 0.020) <= 1.0e-12)
        #expect(result.candidates.contains { $0.kind == .face })
    }

    @Test(.timeLimit(.minutes(1)))
    func snapQueryEvaluatorPrioritizesVertexAtCoincidentPoint() throws {
        let document = makeRectangleExtrudeDocument()
        let evaluated = try DocumentEvaluator().evaluate(document)
        let result = try SnapQueryEvaluator().candidates(
            near: Point3D(x: -0.020, y: -0.010, z: 0.0),
            in: evaluated,
            options: SnapQueryOptions(maximumDistance: 0.0, maximumCandidateCount: 3)
        )

        let first = try #require(result.candidates.first)
        #expect(first.kind == .vertex)
        #expect(first.distance <= 1.0e-12)
        guard case .topology = first.selection else {
            Issue.record("Expected vertex snap candidate to carry a topology selection reference.")
            return
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func snapQueryEvaluatorFiltersCandidatesByFaceIntent() throws {
        let document = makeRectangleExtrudeDocument()
        let evaluated = try DocumentEvaluator().evaluate(document)
        let result = try SnapQueryEvaluator().candidates(
            near: Point3D(x: 0.0, y: -0.012, z: -0.002),
            in: evaluated,
            options: SnapQueryOptions(maximumDistance: 0.003, intent: .face)
        )

        let first = try #require(result.candidates.first)
        #expect(first.kind == .face)
        #expect(result.candidates.allSatisfy { $0.kind == .face })
        guard case .surface(.parameter) = first.selection else {
            Issue.record("Expected face snap intent to return surface parameter references.")
            return
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func snapQueryEvaluatorReturnsCurveParameterCandidateForGeneratedCurveIntent() throws {
        let document = makeStraightPathSweepDocument()
        let evaluated = try DocumentEvaluator().evaluate(document)
        let pathFeatureID = try #require(document.designGraph.order.dropFirst().first)
        let result = try SnapQueryEvaluator().candidates(
            near: Point3D(x: 0.002, y: 0.0, z: 0.005),
            in: evaluated,
            options: SnapQueryOptions(maximumDistance: 0.003, intent: .curve)
        )

        let first = try #require(result.candidates.first)
        #expect(first.kind == .curve)
        #expect(first.distance <= 0.002 + 1.0e-12)
        #expect(first.point.isApproximatelyEqual(to: Point3D(x: 0.0, y: 0.0, z: 0.005), tolerance: 1.0e-12))
        #expect(abs((first.tangent?.z ?? 0.0) - 1.0) <= 1.0e-12)
        guard case let .curve(.parameter(reference)) = first.selection else {
            Issue.record("Expected curve snap intent to return curve parameter references.")
            return
        }
        #expect(reference.curve.featureID == pathFeatureID)
        #expect(reference.curve.curveIndex == 0)
        #expect(abs(reference.parameter - 0.005) <= 1.0e-12)
    }

    @Test(.timeLimit(.minutes(1)))
    func snapQueryEvaluatorReturnsGeneratedCurveKeyPointCandidates() throws {
        let document = makeStraightPathSweepDocument()
        let evaluated = try DocumentEvaluator().evaluate(document)
        let pathFeatureID = try #require(document.designGraph.order.dropFirst().first)
        let evaluator = SnapQueryEvaluator()

        let curvePointResult = try evaluator.candidates(
            near: Point3D(x: 0.0015, y: 0.0, z: 0.005),
            in: evaluated,
            options: SnapQueryOptions(maximumDistance: 0.002, intent: .curvePoint)
        )
        let midpointCandidate = try #require(curvePointResult.candidates.first)
        #expect(midpointCandidate.kind == .curvePoint)
        #expect(midpointCandidate.role == .curveMidpoint)
        #expect(midpointCandidate.point.isApproximatelyEqual(to: Point3D(x: 0.0, y: 0.0, z: 0.005), tolerance: 1.0e-12))
        guard case let .curve(.parameter(midpointReference)) = midpointCandidate.selection else {
            Issue.record("Expected curve point snap to carry a curve parameter reference.")
            return
        }
        #expect(midpointReference.curve.featureID == pathFeatureID)
        #expect(abs(midpointReference.parameter - 0.005) <= 1.0e-12)

        let endpointResult = try evaluator.candidates(
            near: Point3D(x: 0.0015, y: 0.0, z: 0.0),
            in: evaluated,
            options: SnapQueryOptions(maximumDistance: 0.002, intent: .curvePoint)
        )
        let endpointCandidate = try #require(endpointResult.candidates.first)
        #expect(endpointCandidate.kind == .curvePoint)
        #expect(endpointCandidate.role == .curveStart)
        #expect(endpointCandidate.point.isApproximatelyEqual(to: Point3D(x: 0.0, y: 0.0, z: 0.0), tolerance: 1.0e-12))

        let preciseResult = try evaluator.candidates(
            near: Point3D(x: 0.0015, y: 0.0, z: 0.005),
            in: evaluated,
            options: SnapQueryOptions(maximumDistance: 0.002, intent: .precisePoint)
        )
        let preciseFirst = try #require(preciseResult.candidates.first)
        #expect(preciseFirst.kind == .curvePoint)
        #expect(preciseFirst.role == .curveMidpoint)
    }

    @Test(.timeLimit(.minutes(1)))
    func selectionMeasurementEvaluatorResolvesSnapSelections() throws {
        let document = makeStraightPathSweepDocument()
        let evaluated = try DocumentEvaluator().evaluate(document)
        let snapEvaluator = SnapQueryEvaluator()
        let measurementEvaluator = SelectionMeasurementEvaluator()

        let start = try #require(snapEvaluator.candidates(
            near: Point3D(x: 0.001, y: 0.0, z: 0.0),
            in: evaluated,
            options: SnapQueryOptions(maximumDistance: 0.002, intent: .curvePoint)
        ).candidates.first)
        let end = try #require(snapEvaluator.candidates(
            near: Point3D(x: 0.001, y: 0.0, z: 0.010),
            in: evaluated,
            options: SnapQueryOptions(maximumDistance: 0.002, intent: .curvePoint)
        ).candidates.first)
        let distance = try measurementEvaluator.distance(
            from: start.selection,
            to: end.selection,
            in: evaluated
        )

        #expect(start.kind == .curvePoint)
        #expect(end.kind == .curvePoint)
        #expect(abs(distance.distance - 0.010) <= 1.0e-12)
        #expect(abs(distance.vector.z - 0.010) <= 1.0e-12)

        let point = try measurementEvaluator.point(for: start.selection, in: evaluated)
        #expect(point.point.isApproximatelyEqual(to: Point3D(x: 0.0, y: 0.0, z: 0.0), tolerance: 1.0e-12))
        #expect(abs((point.tangent?.z ?? 0.0) - 1.0) <= 1.0e-12)
    }

    @Test(.timeLimit(.minutes(1)))
    func selectionDimensionEvaluatorMeasuresDocumentDimensions() throws {
        var document = makeStraightPathSweepDocument()
        let pathFeatureID = try #require(document.designGraph.order.dropFirst().first)
        document.selectionDimensions = [
            SelectionDimension(
                kind: .distance,
                first: .curve(.parameter(CurveParameterReference(
                    curve: CurveOutputReference(featureID: pathFeatureID),
                    parameter: 0.0
                ))),
                second: .curve(.parameter(CurveParameterReference(
                    curve: CurveOutputReference(featureID: pathFeatureID),
                    parameter: 0.010
                ))),
                target: .constant(.length(10.0, unit: .millimeter))
            )
        ]
        let evaluated = try DocumentEvaluator().evaluate(document)

        let evaluation = try SelectionDimensionEvaluator().evaluate(evaluated)
        let measurement = try #require(evaluation.measurements.first)

        #expect(evaluation.measurements.count == 1)
        #expect(measurement.measured == .length(0.010, unit: .meter))
        #expect(measurement.target == .length(0.010, unit: .meter))
        #expect(abs(measurement.residual.value) <= 1.0e-12)
        #expect(try measurement.isSatisfied())
    }

    @Test(.timeLimit(.minutes(1)))
    func snapQueryEvaluatorRejectsIntentKindMismatch() throws {
        let document = makeRectangleExtrudeDocument()
        let evaluated = try DocumentEvaluator().evaluate(document)
        #expect(throws: FeatureEvaluationError.self) {
            try SnapQueryEvaluator().candidates(
                near: Point3D(x: 0.0, y: -0.012, z: -0.002),
                in: evaluated,
                options: SnapQueryOptions(intent: .face, candidateKinds: [.edge])
            )
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func curveQueryEvaluatorResolvesExactBridgeCurveSubobjects() throws {
        let document = makeBridgeCurveSweepDocument()
        let evaluated = try DocumentEvaluator().evaluate(document)
        let bridgeFeatureID = try #require(document.designGraph.order.dropFirst().first)
        let curveReference = CurveOutputReference(featureID: bridgeFeatureID)
        let evaluator = CurveQueryEvaluator()

        let endpoints = try evaluator.endpoints(of: curveReference, in: evaluated)
        #expect(abs(endpoints.start.z) <= 1.0e-12)
        #expect(abs(endpoints.end.z - 0.01) <= 1.0e-12)

        let midpoint = try evaluator.point(
            at: CurveParameterReference(curve: curveReference, parameter: 0.5),
            in: evaluated
        )
        #expect(midpoint.isExact)
        #expect(abs((midpoint.tangent?.z ?? 0.0) - 1.0) <= 1.0e-12)
        #expect(abs(midpoint.point.z - 0.005) <= 1.0e-12)
        #expect(abs((midpoint.curvature ?? 1.0)) <= 1.0e-9)

        let startControlPoint = try evaluator.controlPoint(
            CurveControlPointReference(curve: curveReference, controlPointIndex: 0),
            in: evaluated
        )
        let endControlPoint = try evaluator.controlPoint(
            CurveControlPointReference(curve: curveReference, controlPointIndex: 3),
            in: evaluated
        )
        #expect(abs(startControlPoint.z) <= 1.0e-12)
        #expect(abs(endControlPoint.z - 0.01) <= 1.0e-12)

        #expect(try evaluator.knot(CurveKnotReference(curve: curveReference, knotIndex: 0), in: evaluated) == 0.0)
        #expect(try evaluator.knot(CurveKnotReference(curve: curveReference, knotIndex: 7), in: evaluated) == 1.0)

        let span = try evaluator.span(CurveSpanReference(curve: curveReference, spanIndex: 0), in: evaluated)
        #expect(span.lowerParameter == 0.0)
        #expect(span.upperParameter == 1.0)
    }

    @Test(.timeLimit(.minutes(1)))
    func straightPathSweepHonorsDistanceFractionThroughPathSampler() throws {
        let document = makeStraightPathSweepDocument(options: SweepOptions(
            distanceFraction: .constant(.scalar(0.5))
        ))
        let evaluated = try DocumentEvaluator().evaluate(document)
        let maxZ = evaluated.brep.vertices.values.map(\.point.z).max()

        #expect(abs((maxZ ?? 0.0) - 0.005) <= 1.0e-12)
        #expect(evaluated.brep.bodies.count == 1)
    }

    @Test(.timeLimit(.minutes(1)))
    func straightPathSweepUnionReplacesTargetBoxWithBooleanResult() throws {
        let setup = makeBoxBooleanSweepDocument(
            targetWidth: 60.0,
            targetHeight: 30.0,
            toolWidth: 40.0,
            toolHeight: 20.0,
            operation: .union
        )
        let evaluated = try DocumentEvaluator().evaluate(setup.document)

        #expect(evaluated.brep.bodies.count == 1)
        #expect(evaluated.brep.shells.count == 1)
        #expect(evaluated.brep.faces.count == 6)
        #expect(evaluated.brep.edges.count == 12)
        #expect(evaluated.brep.vertices.count == 8)
        #expect(evaluated.generatedNames.keys.contains {
            $0.components.contains(.feature(setup.targetFeatureID))
        } == false)
        #expect(evaluated.generatedNames.keys.contains {
            $0.components == [
                .feature(setup.sweepFeatureID),
                .generated(GeneratedSubshapeRole.body.rawValue),
            ]
        })
        try evaluated.brep.validate()
        try expectBounds(
            evaluated.brep,
            minimum: Point3D(x: -0.030, y: -0.015, z: 0.0),
            maximum: Point3D(x: 0.030, y: 0.015, z: 0.010)
        )
    }

    @Test(.timeLimit(.minutes(1)))
    func straightPathSweepUnionCanKeepTargetAndToolBodies() throws {
        let setup = makeBoxBooleanSweepDocument(
            targetWidth: 60.0,
            targetHeight: 30.0,
            toolWidth: 40.0,
            toolHeight: 20.0,
            operation: .union,
            keepTools: true
        )
        let evaluated = try DocumentEvaluator().evaluate(setup.document)

        #expect(evaluated.brep.bodies.count == 3)
        #expect(evaluated.generatedNames.keys.contains {
            $0.components.contains(.feature(setup.targetFeatureID))
        })
        #expect(evaluated.generatedNames.keys.contains {
            $0.components.contains(.feature(setup.sweepFeatureID))
                && $0.components.contains(.subshape("tool"))
        })
        #expect(evaluated.generatedNames.keys.contains {
            $0.components == [
                .feature(setup.sweepFeatureID),
                .generated(GeneratedSubshapeRole.body.rawValue),
            ]
        })
        try evaluated.brep.validate()
    }

    @Test(.timeLimit(.minutes(1)))
    func straightPathSweepBooleanResultPublishesSemanticBoxTopologyNames() throws {
        let setup = makeBoxBooleanSweepDocument(
            targetWidth: 60.0,
            targetHeight: 30.0,
            toolWidth: 40.0,
            toolHeight: 20.0,
            operation: .union
        )
        let evaluated = try DocumentEvaluator().evaluate(setup.document)
        let cornerName = PersistentName(components: [
            .feature(setup.sweepFeatureID),
            .generated(GeneratedSubshapeRole.vertex.rawValue),
            .subshape("box:0:corner:minX:minY:minZ"),
        ])
        let edgeName = PersistentName(components: [
            .feature(setup.sweepFeatureID),
            .generated(GeneratedSubshapeRole.edge.rawValue),
            .subshape("box:0:zEdge:x:maxX:y:maxY"),
        ])
        let faceName = PersistentName(components: [
            .feature(setup.sweepFeatureID),
            .generated(GeneratedSubshapeRole.sideFace.rawValue),
            .subshape("box:0:face:maxX"),
        ])

        #expect(evaluated.generatedNames[cornerName]?.isVertex == true)
        #expect(evaluated.generatedNames[edgeName]?.isEdge == true)
        #expect(evaluated.generatedNames[faceName]?.isFace == true)
        #expect(evaluated.generatedNames.keys.contains { name in
            name.components.contains(.feature(setup.sweepFeatureID))
                && name.components.contains { component in
                    if case .index = component {
                        return true
                    }
                    return false
                }
        } == false)
    }

    @Test(.timeLimit(.minutes(1)))
    func straightPathSweepDifferenceTrimsRectangularTargetSlab() throws {
        let setup = makeBoxBooleanSweepDocument(
            targetWidth: 40.0,
            targetHeight: 20.0,
            toolWidth: 20.0,
            toolHeight: 20.0,
            toolCenterX: 10.0,
            operation: .difference
        )
        let evaluated = try DocumentEvaluator().evaluate(setup.document)

        #expect(evaluated.brep.bodies.count == 1)
        #expect(evaluated.brep.shells.count == 1)
        #expect(evaluated.brep.faces.count == 6)
        #expect(evaluated.brep.edges.count == 12)
        #expect(evaluated.brep.vertices.count == 8)
        try evaluated.brep.validate()
        try expectBounds(
            evaluated.brep,
            minimum: Point3D(x: -0.020, y: -0.010, z: 0.0),
            maximum: Point3D(x: 0.0, y: 0.010, z: 0.010)
        )
    }

    @Test(.timeLimit(.minutes(1)))
    func straightPathSweepDifferenceSplitsTargetIntoSeparatedBoxShells() throws {
        let setup = makeBoxBooleanSweepDocument(
            targetWidth: 40.0,
            targetHeight: 20.0,
            toolWidth: 20.0,
            toolHeight: 20.0,
            operation: .difference
        )
        let evaluated = try DocumentEvaluator().evaluate(setup.document)
        let body = try #require(evaluated.brep.bodies.values.first)

        #expect(evaluated.brep.bodies.count == 1)
        #expect(body.shellIDs.count == 2)
        #expect(evaluated.brep.shells.count == 2)
        #expect(evaluated.brep.faces.count == 12)
        #expect(evaluated.brep.edges.count == 24)
        #expect(evaluated.brep.vertices.count == 16)
        #expect(evaluated.generatedNames.keys.contains {
            $0.components.contains(.feature(setup.targetFeatureID))
        } == false)
        #expect(evaluated.generatedNames.values.filter(\.isBody).count == 1)
        #expect(evaluated.generatedNames.values.filter(\.isFace).count == evaluated.brep.faces.count)
        #expect(evaluated.generatedNames.values.filter(\.isEdge).count == evaluated.brep.edges.count)
        #expect(evaluated.generatedNames.values.filter(\.isVertex).count == evaluated.brep.vertices.count)
        try evaluated.brep.validate()
        try expectBounds(
            evaluated.brep,
            minimum: Point3D(x: -0.020, y: -0.010, z: 0.0),
            maximum: Point3D(x: 0.020, y: 0.010, z: 0.010)
        )
    }

    @Test(.timeLimit(.minutes(1)))
    func straightPathSweepDifferenceCreatesRectangularThroughHoleFrame() throws {
        let setup = makeBoxBooleanSweepDocument(
            targetWidth: 40.0,
            targetHeight: 40.0,
            toolWidth: 20.0,
            toolHeight: 20.0,
            operation: .difference
        )
        let evaluated = try DocumentEvaluator().evaluate(setup.document)
        let body = try #require(evaluated.brep.bodies.values.first)

        #expect(evaluated.brep.bodies.count == 1)
        #expect(body.shellIDs.count == 1)
        #expect(evaluated.brep.shells.count == 1)
        #expect(evaluated.brep.faces.count == 10)
        #expect(evaluated.brep.loops.count == 12)
        #expect(evaluated.brep.edges.count == 24)
        #expect(evaluated.brep.vertices.count == 16)
        #expect(evaluated.generatedNames.keys.contains {
            $0.components.contains(.feature(setup.targetFeatureID))
        } == false)
        #expect(evaluated.generatedNames.values.filter(\.isBody).count == 1)
        #expect(evaluated.generatedNames.values.filter(\.isFace).count == evaluated.brep.faces.count)
        #expect(evaluated.generatedNames.values.filter(\.isEdge).count == evaluated.brep.edges.count)
        #expect(evaluated.generatedNames.values.filter(\.isVertex).count == evaluated.brep.vertices.count)
        try evaluated.brep.validate()
        try expectBounds(
            evaluated.brep,
            minimum: Point3D(x: -0.020, y: -0.020, z: 0.0),
            maximum: Point3D(x: 0.020, y: 0.020, z: 0.010)
        )
        let mesh = try #require(evaluated.meshes.values.first)
        #expect(mesh.positions.count >= evaluated.brep.vertices.count)
        #expect(mesh.indices.count == 96)
        try mesh.validate()
    }

    @Test(.timeLimit(.minutes(1)))
    func straightPathSweepBooleanFramePublishesSemanticTopologyNames() throws {
        let setup = makeBoxBooleanSweepDocument(
            targetWidth: 40.0,
            targetHeight: 40.0,
            toolWidth: 20.0,
            toolHeight: 20.0,
            operation: .difference
        )
        let evaluated = try DocumentEvaluator().evaluate(setup.document)
        let holeCornerName = PersistentName(components: [
            .feature(setup.sweepFeatureID),
            .generated(GeneratedSubshapeRole.vertex.rawValue),
            .subshape("frame:hole:corner:maxX:maxY:maxZ"),
        ])
        let holeEdgeName = PersistentName(components: [
            .feature(setup.sweepFeatureID),
            .generated(GeneratedSubshapeRole.edge.rawValue),
            .subshape("frame:hole:zEdge:x:maxX:y:maxY"),
        ])
        let holeFaceName = PersistentName(components: [
            .feature(setup.sweepFeatureID),
            .generated(GeneratedSubshapeRole.sideFace.rawValue),
            .subshape("frame:holeFace:maxX"),
        ])
        let capFaceName = PersistentName(components: [
            .feature(setup.sweepFeatureID),
            .generated(GeneratedSubshapeRole.sideFace.rawValue),
            .subshape("frame:face:minZ"),
        ])

        #expect(evaluated.generatedNames[holeCornerName]?.isVertex == true)
        #expect(evaluated.generatedNames[holeEdgeName]?.isEdge == true)
        #expect(evaluated.generatedNames[holeFaceName]?.isFace == true)
        #expect(evaluated.generatedNames[capFaceName]?.isFace == true)
        #expect(evaluated.generatedNames.keys.contains { name in
            name.components.contains(.feature(setup.sweepFeatureID))
                && name.components.contains { component in
                    if case .index = component {
                        return true
                    }
                    return false
                }
        } == false)
    }

    @Test(.timeLimit(.minutes(1)))
    func straightPathSweepDifferenceCreatesConnectedNonRectangularCellUnion() throws {
        let setup = makeBoxBooleanSweepDocument(
            targetWidth: 40.0,
            targetHeight: 40.0,
            toolWidth: 30.0,
            toolHeight: 30.0,
            toolCenterX: 10.0,
            toolCenterY: 10.0,
            operation: .difference
        )
        let evaluated = try DocumentEvaluator().evaluate(setup.document)
        let body = try #require(evaluated.brep.bodies.values.first)

        #expect(evaluated.brep.bodies.count == 1)
        #expect(body.shellIDs.count == 1)
        #expect(evaluated.brep.faces.count > 6)
        #expect(evaluated.brep.edges.count > 12)
        #expect(evaluated.brep.vertices.count > 8)
        #expect(evaluated.generatedNames.keys.contains {
            $0.components.contains(.feature(setup.targetFeatureID))
        } == false)
        #expect(evaluated.generatedNames.values.filter(\.isBody).count == 1)
        #expect(evaluated.generatedNames.values.filter(\.isFace).count == evaluated.brep.faces.count)
        #expect(evaluated.generatedNames.values.filter(\.isEdge).count == evaluated.brep.edges.count)
        #expect(evaluated.generatedNames.values.filter(\.isVertex).count == evaluated.brep.vertices.count)
        #expect(evaluated.generatedNames.keys.contains { name in
            name.components.contains(.feature(setup.sweepFeatureID))
                && name.components.contains(.subshape("cellUnion:component:0:face:maxX:x:maxX:y:minY-y1:z:minZ-maxZ"))
        })
        #expect(evaluated.generatedNames.keys.contains { name in
            name.components.contains(.feature(setup.sweepFeatureID))
                && name.components.contains(.subshape("cellUnion:component:0:zEdge:x:x1:y:y1:z:minZ-maxZ"))
        })
        #expect(evaluated.generatedNames.keys.contains { name in
            name.components.contains(.feature(setup.sweepFeatureID))
                && name.components.contains { component in
                    if case .index = component {
                        return true
                    }
                    return false
                }
        } == false)
        try evaluated.brep.validate()
        try expectBounds(
            evaluated.brep,
            minimum: Point3D(x: -0.020, y: -0.020, z: 0.0),
            maximum: Point3D(x: 0.020, y: 0.020, z: 0.010)
        )
    }

    @Test(.timeLimit(.minutes(1)))
    func straightPathSweepSliceSplitsRectangularTargetIntoBoxShells() throws {
        let setup = makeBoxBooleanSweepDocument(
            targetWidth: 40.0,
            targetHeight: 20.0,
            toolWidth: 20.0,
            toolHeight: 20.0,
            operation: .slice
        )
        let evaluated = try DocumentEvaluator().evaluate(setup.document)
        let body = try #require(evaluated.brep.bodies.values.first)

        #expect(evaluated.brep.bodies.count == 1)
        #expect(body.shellIDs.count == 3)
        #expect(evaluated.brep.shells.count == 3)
        #expect(evaluated.brep.faces.count == 18)
        #expect(evaluated.brep.edges.count == 36)
        #expect(evaluated.brep.vertices.count == 24)
        #expect(evaluated.generatedNames.keys.contains {
            $0.components.contains(.feature(setup.targetFeatureID))
        } == false)
        #expect(evaluated.generatedNames.values.filter(\.isBody).count == 1)
        #expect(evaluated.generatedNames.values.filter(\.isFace).count == evaluated.brep.faces.count)
        #expect(evaluated.generatedNames.values.filter(\.isEdge).count == evaluated.brep.edges.count)
        #expect(evaluated.generatedNames.values.filter(\.isVertex).count == evaluated.brep.vertices.count)
        try evaluated.brep.validate()
        try expectBounds(
            evaluated.brep,
            minimum: Point3D(x: -0.020, y: -0.010, z: 0.0),
            maximum: Point3D(x: 0.020, y: 0.010, z: 0.010)
        )
    }

    @Test(.timeLimit(.minutes(1)))
    func sweepPathSamplerBuildsMovingFramesForCurvedPath() throws {
        let points = [
            Point3D(x: 1.0, y: 0.0, z: 0.0),
            Point3D(x: 0.707_106_781_186_547_6, y: 0.707_106_781_186_547_5, z: 0.0),
            Point3D(x: 0.0, y: 1.0, z: 0.0),
        ]
        let curve = EvaluatedCurve(
            sourceFeatureID: FeatureID(),
            source: .sketchEntity(SketchEntityID()),
            kind: .arc,
            points: points
        )
        let sampler = SweepPathSampler(tolerance: ModelingTolerance(distance: 1.0e-9, angle: 1.0e-9))
        let frames = try sampler.frames(
            for: curve,
            distanceFraction: 1.0,
            preferredNormal: .unitZ
        )

        #expect(frames.count == 3)
        let straightPath = try sampler.straightPath(from: frames)
        #expect(straightPath == nil)
        for frame in frames {
            try frame.validate(tolerance: ModelingTolerance(distance: 1.0e-9, angle: 1.0e-9))
            #expect(abs(frame.tangent.dot(frame.normal)) <= 1.0e-9)
            #expect(abs(frame.tangent.dot(frame.binormal)) <= 1.0e-9)
            #expect(abs(frame.normal.dot(frame.binormal)) <= 1.0e-9)
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func curvePathEvaluatorUsesExactCircularArcLengthForSparseEvaluatedCurves() throws {
        let circle = Circle3D(center: .origin, normal: .unitZ, radius: 2.0)
        let start = try Curve3D.circle(circle).point(at: 0.0)
        let end = try Curve3D.circle(circle).point(at: Double.pi / 2.0)
        let curve = EvaluatedCurve(
            sourceFeatureID: FeatureID(),
            source: .generatedFeature,
            kind: .arc,
            points: [start, end],
            exactCurve: .circle(circle),
            exactParameterDomain: .closed(0.0, Double.pi / 2.0)
        )
        let tolerance = ModelingTolerance(distance: 1.0e-4, angle: 1.0e-6)
        let evaluator = EvaluatedCurvePathEvaluator(tolerance: tolerance)
        let length = try evaluator.length(of: curve)
        let samples = try evaluator.samples(for: curve)
        let finalSample = try #require(samples.last)
        let sampler = SweepPathSampler(tolerance: tolerance)
        let frames = try sampler.frames(
            for: curve,
            distanceFraction: 1.0,
            preferredNormal: .unitZ
        )
        let finalFrame = try #require(frames.last)
        let chordLength = (end - start).length
        let expectedLength = Double.pi

        #expect(samples.count > 2)
        #expect(frames.count == samples.count)
        #expect(abs(length - expectedLength) < 1.0e-12)
        #expect(abs(finalSample.distance - expectedLength) < 1.0e-12)
        #expect(abs(finalFrame.distance - expectedLength) < 1.0e-12)
        #expect(abs(chordLength - expectedLength) > 0.3)
        #expect(try sampler.straightPath(from: frames) == nil)
    }

    @Test(.timeLimit(.minutes(1)))
    func curvePathEvaluatorPreservesExactLengthsAcrossOrientedMultiCurveChains() throws {
        let circle = Circle3D(center: .origin, normal: .unitZ, radius: 2.0)
        let arcStart = try Curve3D.circle(circle).point(at: 0.0)
        let arcEnd = try Curve3D.circle(circle).point(at: Double.pi / 2.0)
        let lineEnd = Point3D(x: 0.0, y: 5.0, z: 0.0)
        let arc = EvaluatedCurve(
            sourceFeatureID: FeatureID(),
            source: .generatedFeature,
            kind: .arc,
            points: [arcStart, arcEnd],
            exactCurve: .circle(circle),
            exactParameterDomain: .closed(0.0, Double.pi / 2.0)
        )
        let line = EvaluatedCurve(
            sourceFeatureID: FeatureID(),
            source: .generatedFeature,
            kind: .line,
            points: [arcEnd, lineEnd],
            exactCurve: .line(Line3D(origin: arcEnd, direction: .unitY)),
            exactParameterDomain: .closed(0.0, 3.0)
        )
        let tolerance = ModelingTolerance(distance: 1.0e-4, angle: 1.0e-6)
        let segments = try EvaluatedCurveChainBuilder(tolerance: tolerance).openSegments(
            from: [line, arc],
            operationName: "Sweep path"
        )
        let evaluator = EvaluatedCurvePathEvaluator(tolerance: tolerance)
        let samples = try evaluator.samples(for: segments)
        let frames = try SweepPathSampler(tolerance: tolerance).frames(
            for: segments,
            distanceFraction: 1.0,
            preferredNormal: .unitZ
        )
        let firstSample = try #require(samples.first)
        let finalSample = try #require(samples.last)
        let finalFrame = try #require(frames.last)
        let expectedLength = 3.0 + Double.pi
        let sparsePolylineLength = 3.0 + (arcEnd - arcStart).length

        #expect(segments.count == 2)
        #expect(segments.allSatisfy { $0.curve.exactCurve != nil })
        #expect(segments.contains { $0.isReversed })
        #expect(firstSample.point.isApproximatelyEqual(to: lineEnd, tolerance: tolerance.distance))
        #expect(abs(try evaluator.length(of: segments) - expectedLength) < 1.0e-12)
        #expect(abs(finalSample.distance - expectedLength) < 1.0e-12)
        #expect(abs(finalFrame.distance - expectedLength) < 1.0e-12)
        #expect(abs(sparsePolylineLength - expectedLength) > 0.3)
        #expect(try SweepPathSampler(tolerance: tolerance).straightPath(from: frames) == nil)
    }

    @Test(.timeLimit(.minutes(1)))
    func curvePathEvaluatorPreservesExactBSplineWhenChainRequiresReversal() throws {
        let spline = makeEditableBSplineCurve()
        let splineStart = try spline.point(at: 0.0)
        let splineEnd = try spline.point(at: 1.0)
        let lineEnd = splineEnd + Vector3D(x: 0.0, y: 1.0, z: 0.0)
        let splineCurve = EvaluatedCurve(
            sourceFeatureID: FeatureID(),
            source: .generatedFeature,
            kind: .spline,
            points: [splineStart, splineEnd],
            exactCurve: .bSpline(spline),
            exactParameterDomain: .closed(0.0, 1.0)
        )
        let lineCurve = EvaluatedCurve(
            sourceFeatureID: FeatureID(),
            source: .generatedFeature,
            kind: .line,
            points: [splineEnd, lineEnd],
            exactCurve: .line(Line3D(origin: splineEnd, direction: .unitY)),
            exactParameterDomain: .closed(0.0, 1.0)
        )
        let tolerance = ModelingTolerance(distance: 1.0e-5, angle: 1.0e-6)
        let segments = try EvaluatedCurveChainBuilder(tolerance: tolerance).openSegments(
            from: [lineCurve, splineCurve],
            operationName: "Sweep path"
        )
        let evaluator = EvaluatedCurvePathEvaluator(tolerance: tolerance)
        let samples = try evaluator.samples(for: segments)
        let finalSample = try #require(samples.last)
        let chordLength = (splineEnd - splineStart).length
        let pathLength = try evaluator.length(of: segments)

        #expect(segments.count == 2)
        #expect(segments[1].isReversed)
        #expect(samples.count > 4)
        #expect(finalSample.point.isApproximatelyEqual(to: splineStart, tolerance: tolerance.distance))
        #expect(pathLength > 1.0 + chordLength + 0.01)
    }

    @Test(.timeLimit(.minutes(1)))
    func curvedPathSweepCreatesPolygonalSweptBRep() throws {
        let document = makeCurvedPathSweepDocument(radius: 60.0)
        let evaluated = try DocumentEvaluator().evaluate(document)
        let profileVertexCount = 4
        #expect(evaluated.brep.vertices.count % profileVertexCount == 0)
        let pathFrameCount = evaluated.brep.vertices.count / profileVertexCount
        let pathSpanCount = pathFrameCount - 1

        #expect(evaluated.brep.bodies.count == 1)
        #expect(evaluated.brep.shells.count == 1)
        #expect(pathFrameCount > 2)
        #expect(evaluated.brep.vertices.count == pathFrameCount * profileVertexCount)
        #expect(evaluated.brep.edges.count == (
            pathFrameCount * profileVertexCount
                + pathSpanCount * profileVertexCount
                + pathSpanCount * profileVertexCount
        ))
        #expect(evaluated.brep.faces.count == 2 + pathSpanCount * profileVertexCount * 2)
        try evaluated.brep.validate()
        #expect(evaluated.generatedNames.values.filter(\.isBody).count == evaluated.brep.bodies.count)
        #expect(evaluated.generatedNames.values.filter(\.isFace).count == evaluated.brep.faces.count)
        #expect(evaluated.generatedNames.values.filter(\.isEdge).count == evaluated.brep.edges.count)
        #expect(evaluated.generatedNames.values.filter(\.isVertex).count == evaluated.brep.vertices.count)

        let mesh = try #require(evaluated.meshes.values.first)
        #expect(mesh.positions.count > 0)
        #expect(mesh.indices.count > 0)
        #expect(mesh.indices.count % 3 == 0)
    }

    @Test(.timeLimit(.minutes(1)))
    func curvedPathSweepPublishesSemanticGeneratedTopologyNames() throws {
        let document = makeCurvedPathSweepDocument(radius: 60.0)
        let sweepFeatureID = try #require(document.designGraph.order.last)
        let evaluated = try DocumentEvaluator().evaluate(document)
        let ringVertexName = PersistentName(components: [
            .feature(sweepFeatureID),
            .generated(GeneratedSubshapeRole.vertex.rawValue),
            .subshape("ringVertex:frame:0:profile:0"),
        ])
        let ringEdgeName = PersistentName(components: [
            .feature(sweepFeatureID),
            .generated(GeneratedSubshapeRole.edge.rawValue),
            .subshape("ringEdge:frame:0:profile:0"),
        ])
        let railEdgeName = PersistentName(components: [
            .feature(sweepFeatureID),
            .generated(GeneratedSubshapeRole.edge.rawValue),
            .subshape("railEdge:span:0:profile:0"),
        ])
        let diagonalEdgeName = PersistentName(components: [
            .feature(sweepFeatureID),
            .generated(GeneratedSubshapeRole.edge.rawValue),
            .subshape("diagonalEdge:span:0:profile:0"),
        ])
        let firstSideTriangleName = PersistentName(components: [
            .feature(sweepFeatureID),
            .generated(GeneratedSubshapeRole.sideFace.rawValue),
            .subshape("sideTriangle:span:0:profile:0:triangle:0"),
        ])
        let secondSideTriangleName = PersistentName(components: [
            .feature(sweepFeatureID),
            .generated(GeneratedSubshapeRole.sideFace.rawValue),
            .subshape("sideTriangle:span:0:profile:0:triangle:1"),
        ])

        #expect(evaluated.generatedNames[ringVertexName]?.isVertex == true)
        #expect(evaluated.generatedNames[ringEdgeName]?.isEdge == true)
        #expect(evaluated.generatedNames[railEdgeName]?.isEdge == true)
        #expect(evaluated.generatedNames[diagonalEdgeName]?.isEdge == true)
        #expect(evaluated.generatedNames[firstSideTriangleName]?.isFace == true)
        #expect(evaluated.generatedNames[secondSideTriangleName]?.isFace == true)
        #expect(evaluated.generatedNames.keys.contains { name in
            name.components.contains(.feature(sweepFeatureID))
                && name.components.contains { component in
                    if case .index = component {
                        return true
                    }
                    return false
                }
                && name.components.contains { component in
                    switch component {
                    case .generated(let role):
                        return [
                            GeneratedSubshapeRole.vertex.rawValue,
                            GeneratedSubshapeRole.edge.rawValue,
                            GeneratedSubshapeRole.sideFace.rawValue,
                        ].contains(role)
                    default:
                        return false
                    }
                }
        } == false)
    }

    @Test(.timeLimit(.minutes(1)))
    func curvedPathSweepRejectsDegenerateInnerRadiusBeforeProducingBody() throws {
        let document = makeCurvedPathSweepDocument(radius: 10.0)

        do {
            _ = try DocumentEvaluator().evaluate(document)
            Issue.record("Expected degenerate curved sweep to be rejected.")
        } catch FeatureEvaluationError.unsupportedOperation(let message) {
            #expect(message.contains("degenerate swept topology"))
        } catch {
            Issue.record("Expected unsupportedOperation for degenerate curved sweep, got \(error).")
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func straightPathSweepAppliesEndScaleThroughPolygonalBRep() throws {
        let document = makeStraightPathSweepDocument(
            options: SweepOptions(endScale: .constant(.scalar(0.5)))
        )
        let evaluated = try DocumentEvaluator().evaluate(document)
        let endVertices = evaluated.brep.vertices.values.map(\.point).filter {
            abs($0.z - 0.010) <= 1.0e-12
        }
        let maxEndX = endVertices.map { abs($0.x) }.max() ?? 0.0
        let maxEndY = endVertices.map { abs($0.y) }.max() ?? 0.0

        #expect(evaluated.brep.bodies.count == 1)
        #expect(evaluated.brep.vertices.count == 8)
        #expect(evaluated.brep.faces.count == 10)
        #expect(endVertices.count == 4)
        #expect(abs(maxEndX - 0.010) <= 1.0e-12)
        #expect(abs(maxEndY - 0.005) <= 1.0e-12)
        try evaluated.brep.validate()
    }

    @Test(.timeLimit(.minutes(1)))
    func straightPathSweepAppliesTwistThroughPolygonalBRep() throws {
        let document = makeStraightPathSweepDocument(
            options: SweepOptions(twistAngle: .constant(.angle(90.0, unit: .degree)))
        )
        let evaluated = try DocumentEvaluator().evaluate(document)
        let endVertices = evaluated.brep.vertices.values.map(\.point).filter {
            abs($0.z - 0.010) <= 1.0e-12
        }
        let maxEndX = endVertices.map { abs($0.x) }.max() ?? 0.0
        let maxEndY = endVertices.map { abs($0.y) }.max() ?? 0.0

        #expect(evaluated.brep.bodies.count == 1)
        #expect(evaluated.brep.vertices.count == 8)
        #expect(evaluated.brep.faces.count == 10)
        #expect(endVertices.count == 4)
        #expect(abs(maxEndX - 0.010) <= 1.0e-12)
        #expect(abs(maxEndY - 0.020) <= 1.0e-12)
        try evaluated.brep.validate()
    }

    @Test(.timeLimit(.minutes(1)))
    func sweepEvaluationAcceptsRoundCornerStyleWhenPathHasNoCornerTransition() throws {
        let document = makeStraightPathSweepDocument(options: SweepOptions(cornerStyle: .round))
        let evaluated = try DocumentEvaluator().evaluate(document)

        #expect(evaluated.brep.bodies.count == 1)
        #expect(evaluated.brep.faces.count == 6)
        #expect(evaluated.brep.edges.count == 12)
        #expect(evaluated.brep.vertices.count == 8)
        try evaluated.brep.validate()
    }

    @Test(.timeLimit(.minutes(1)))
    func sweepEvaluationRejectsUnsupportedOptionSemantics() throws {
        let unsupportedCases: [(options: SweepOptions, expectedMessageFragment: String)] = [
            (SweepOptions(simplify: true), "simplify"),
        ]

        for unsupportedCase in unsupportedCases {
            let document = makeStraightPathSweepDocument(options: unsupportedCase.options)
            do {
                _ = try DocumentEvaluator().evaluate(document)
                Issue.record("Sweep evaluator must reject unsupported option semantics.")
            } catch FeatureEvaluationError.unsupportedOperation(let message) {
                #expect(message.contains(unsupportedCase.expectedMessageFragment))
            } catch {
                Issue.record("Expected unsupportedOperation for unsupported sweep options, got \(error).")
            }
        }

        do {
            try SweepEvaluationCapabilities().validateStaticOptions(
                SweepOptions(booleanOperation: .union, resultKind: .sheet)
            )
            Issue.record("Sweep capabilities must reject target booleans with sheet output.")
        } catch FeatureEvaluationError.unsupportedOperation(let message) {
            #expect(message.contains("solid sweep output"))
        } catch {
            Issue.record("Expected unsupportedOperation for boolean sheet output, got \(error).")
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func sweepEvaluationCapabilitiesClassifyGeometryDependentPlans() throws {
        let capabilities = SweepEvaluationCapabilities()
        let exactParallelPlan = try capabilities.supportedPlan(
            SweepOptions(alignment: .parallel),
            geometry: SweepEvaluationCapabilities.Geometry(
                pathShape: .straight(profileNormalComponent: 0.5),
                sectionState: .identity
            )
        )
        let normalProfilePlanePlan = try capabilities.supportedPlan(
            SweepOptions(alignment: .normal),
            geometry: SweepEvaluationCapabilities.Geometry(
                pathShape: .straight(profileNormalComponent: 0.0),
                sectionState: .identity
            )
        )
        let curvedParallelDecision = try capabilities.decision(
            for: SweepOptions(alignment: .parallel),
            geometry: SweepEvaluationCapabilities.Geometry(
                pathShape: .curved,
                sectionState: .identity
            )
        )
        let curvedParallelGuidedDecision = try capabilities.decision(
            for: SweepOptions(alignment: .parallel),
            geometry: SweepEvaluationCapabilities.Geometry(
                pathShape: .curved,
                sectionState: .guided,
                guideConstraintCount: 5
            )
        )
        let obliqueTransformedDecision = try capabilities.decision(
            for: SweepOptions(
                endScale: .constant(.scalar(1.5)),
                alignment: .parallel
            ),
            geometry: SweepEvaluationCapabilities.Geometry(
                pathShape: .straight(profileNormalComponent: 0.5),
                sectionState: .transformed
            )
        )
        let sheetDecision = try capabilities.decision(
            for: SweepOptions(resultKind: .sheet),
            geometry: SweepEvaluationCapabilities.Geometry(
                pathShape: .straight(profileNormalComponent: 1.0),
                sectionState: .identity
            )
        )
        let booleanDecision = try capabilities.decision(
            for: SweepOptions(booleanOperation: .difference),
            geometry: SweepEvaluationCapabilities.Geometry(
                pathShape: .straight(profileNormalComponent: 1.0),
                sectionState: .identity
            )
        )
        let chordGuideDecision = try capabilities.decision(
            for: SweepOptions(guideMethod: .chord),
            geometry: SweepEvaluationCapabilities.Geometry(
                pathShape: .curved,
                sectionState: .guided,
                guideConstraintCount: 2
            )
        )

        #expect(exactParallelPlan.kind == .exactStraightExtrude)
        #expect(exactParallelPlan.outputTopologyKind == .exactStraightSolid)
        #expect(exactParallelPlan.guideStrategies == [.none])
        #expect(normalProfilePlanePlan.kind == .pathNormalSectionSweep)
        #expect(normalProfilePlanePlan.outputTopologyKind == .polygonalSolid)
        #expect(curvedParallelDecision.supportedPlan?.kind == .profilePlaneParallelSweep)
        #expect(curvedParallelGuidedDecision.supportedPlan?.kind == .profilePlaneParallelSweep)
        #expect(curvedParallelGuidedDecision.supportedPlan?.guideStrategies.contains(.pointMeanValueCageRail) == true)
        #expect(obliqueTransformedDecision.supportedPlan?.kind == .profilePlaneParallelSweep)
        #expect(sheetDecision.supportedPlan?.outputTopologyKind == .exactStraightSheet)
        #expect(booleanDecision.supportedPlan?.booleanSupportKind == .targetBoolean)
        #expect(chordGuideDecision.supportedPlan?.guideStrategies == [.chordDirectional])
        #expect(SweepEvaluationCapabilities.currentOptionMatrix.guideStrategies.contains(.pointMeanValueCageRail))
        #expect(SweepEvaluationCapabilities.currentOptionMatrix.guideStrategies.contains(.pointRadialRail))
        #expect(SweepEvaluationCapabilities.currentOptionMatrix.unsupportedOptionCodes.contains(.booleanRequiresSolidOutput))
    }

    @Test(.timeLimit(.minutes(1)))
    func straightPathSweepSupportsParallelAlignment() throws {
        let document = makeStraightPathSweepDocument(
            options: SweepOptions(alignment: .parallel)
        )
        let evaluated = try DocumentEvaluator().evaluate(document)

        #expect(evaluated.brep.bodies.count == 1)
        #expect(evaluated.brep.vertices.count == 8)
        #expect(evaluated.brep.faces.count == 6)
        try evaluated.brep.validate()
    }

    @Test(.timeLimit(.minutes(1)))
    func straightPathNormalAlignmentRotatesSectionOntoPathNormalPlane() throws {
        let document = makeProfilePlaneStraightPathSweepDocument(
            options: SweepOptions(alignment: .normal)
        )
        let evaluated = try DocumentEvaluator().evaluate(document)
        let points = evaluated.brep.vertices.values.map(\.point)

        #expect(evaluated.brep.bodies.count == 1)
        #expect(evaluated.brep.vertices.count == 8)
        #expect(evaluated.brep.edges.count == 16)
        #expect(evaluated.brep.faces.count == 10)
        #expect(abs((points.map(\.x).min() ?? 0.0) - 0.0) <= 1.0e-12)
        #expect(abs((points.map(\.x).max() ?? 0.0) - 0.010) <= 1.0e-12)
        #expect(abs((points.map { abs($0.y) }.max() ?? 0.0) - 0.010) <= 1.0e-12)
        #expect(abs((points.map { abs($0.z) }.max() ?? 0.0) - 0.020) <= 1.0e-12)
        try evaluated.brep.validate()
    }

    @Test(.timeLimit(.minutes(1)))
    func straightPathParallelAlignmentRejectsProfilePlaneDegenerateSolidSweep() throws {
        let document = makeProfilePlaneStraightPathSweepDocument(
            options: SweepOptions(alignment: .parallel)
        )

        do {
            _ = try DocumentEvaluator().evaluate(document)
            Issue.record("Parallel alignment must reject solid sweeps that stay inside the profile plane.")
        } catch FeatureEvaluationError.unsupportedOperation(let message) {
            #expect(message.contains("nonzero profile-normal component"))
        } catch {
            Issue.record("Expected unsupportedOperation for profile-plane parallel alignment, got \(error).")
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func obliqueStraightPathParallelAlignmentAppliesEndScaleInProfilePlane() throws {
        let document = try makeObliqueStraightPathSweepDocument(
            pathEndOffset: 10.0,
            pathLength: 20.0,
            options: SweepOptions(
                endScale: .constant(.scalar(0.5)),
                alignment: .parallel
            )
        )
        let evaluated = try DocumentEvaluator().evaluate(document)
        let endVertices = evaluated.brep.vertices.values.map(\.point).filter {
            abs($0.z - 0.020) <= 1.0e-12
        }
        let minEndX = endVertices.map(\.x).min() ?? 0.0
        let maxEndX = endVertices.map(\.x).max() ?? 0.0
        let minEndY = endVertices.map(\.y).min() ?? 0.0
        let maxEndY = endVertices.map(\.y).max() ?? 0.0

        #expect(evaluated.brep.bodies.count == 1)
        #expect(evaluated.brep.vertices.count == 8)
        #expect(evaluated.brep.faces.count == 10)
        #expect(endVertices.count == 4)
        #expect(abs(minEndX + 0.010) <= 1.0e-12)
        #expect(abs(maxEndX - 0.010) <= 1.0e-12)
        #expect(abs(minEndY - 0.005) <= 1.0e-12)
        #expect(abs(maxEndY - 0.015) <= 1.0e-12)
        try evaluated.brep.validate()
    }

    @Test(.timeLimit(.minutes(1)))
    func curvedPathParallelAlignmentKeepsSectionsParallelToProfilePlane() throws {
        let document = makeCurvedPathSweepDocument(
            radius: 60.0,
            options: SweepOptions(alignment: .parallel)
        )
        let sweepFeatureID = try #require(document.designGraph.order.last)
        let evaluated = try DocumentEvaluator().evaluate(document)
        let profileVertexCount = 4
        #expect(evaluated.brep.vertices.count % profileVertexCount == 0)
        let pathFrameCount = evaluated.brep.vertices.count / profileVertexCount

        func ringVertexPoint(frameIndex: Int, profileIndex: Int) throws -> Point3D {
            let name = PersistentName(components: [
                .feature(sweepFeatureID),
                .generated(GeneratedSubshapeRole.vertex.rawValue),
                .subshape("ringVertex:frame:\(frameIndex):profile:\(profileIndex)"),
            ])
            guard case .vertex(let vertexID) = try #require(evaluated.generatedNames[name]) else {
                Issue.record("Expected generated ring vertex name.")
                throw FeatureEvaluationError.invalidGraph("Expected generated ring vertex name.")
            }
            return try #require(evaluated.brep.vertices[vertexID]?.point)
        }

        #expect(evaluated.brep.bodies.count == 1)
        #expect(pathFrameCount > 2)
        for frameIndex in 0..<pathFrameCount {
            let ringPoints = try (0..<profileVertexCount).map {
                try ringVertexPoint(frameIndex: frameIndex, profileIndex: $0)
            }
            let minX = try #require(ringPoints.map(\.x).min())
            let maxX = try #require(ringPoints.map(\.x).max())
            let minY = try #require(ringPoints.map(\.y).min())
            let maxY = try #require(ringPoints.map(\.y).max())
            let minZ = try #require(ringPoints.map(\.z).min())
            let maxZ = try #require(ringPoints.map(\.z).max())

            #expect(abs((maxX - minX) - 0.040) <= 1.0e-12)
            #expect(abs((maxY - minY) - 0.020) <= 1.0e-12)
            #expect(abs(maxZ - minZ) <= 1.0e-12)
        }
        try evaluated.brep.validate()
    }

    @Test(.timeLimit(.minutes(1)))
    func curvedPathParallelAlignmentSupportsPointGuideProjection() throws {
        let document = try makeGuidedCurvedPathParallelSweepDocument(radius: 60.0)
        let sweepFeatureID = try #require(document.designGraph.order.last)
        let evaluated = try DocumentEvaluator().evaluate(document)
        let profileVertexCount = 4
        #expect(evaluated.brep.vertices.count % profileVertexCount == 0)
        let pathFrameCount = evaluated.brep.vertices.count / profileVertexCount

        func ringVertexPoint(frameIndex: Int, profileIndex: Int) throws -> Point3D {
            let name = PersistentName(components: [
                .feature(sweepFeatureID),
                .generated(GeneratedSubshapeRole.vertex.rawValue),
                .subshape("ringVertex:frame:\(frameIndex):profile:\(profileIndex)"),
            ])
            guard case .vertex(let vertexID) = try #require(evaluated.generatedNames[name]) else {
                Issue.record("Expected generated ring vertex name.")
                throw FeatureEvaluationError.invalidGraph("Expected generated ring vertex name.")
            }
            return try #require(evaluated.brep.vertices[vertexID]?.point)
        }

        let endFrameIndex = pathFrameCount - 1
        let endPoints = try (0..<profileVertexCount).map {
            try ringVertexPoint(frameIndex: endFrameIndex, profileIndex: $0)
        }
        let minEndX = endPoints.map(\.x).min() ?? 0.0
        let maxEndX = endPoints.map(\.x).max() ?? 0.0
        let minEndY = endPoints.map(\.y).min() ?? 0.0
        let maxEndY = endPoints.map(\.y).max() ?? 0.0

        #expect(evaluated.brep.bodies.count == 1)
        #expect(pathFrameCount > 2)
        #expect(abs(minEndX + 0.040) <= 1.0e-10)
        #expect(abs(maxEndX - 0.040) <= 1.0e-10)
        #expect(abs(minEndY + 0.020) <= 1.0e-10)
        #expect(abs(maxEndY - 0.020) <= 1.0e-10)
        try evaluated.brep.validate()
    }

    @Test(.timeLimit(.minutes(1)))
    func straightPathSweepSheetCreatesOpenSheetBodyWithoutCaps() throws {
        let document = makeStraightPathSweepDocument(
            options: SweepOptions(resultKind: .sheet)
        )
        let evaluated = try DocumentEvaluator().evaluate(document)
        let body = try #require(evaluated.brep.bodies.values.first)

        #expect(body.kind == .sheet)
        #expect(evaluated.brep.bodies.count == 1)
        #expect(evaluated.brep.vertices.count == 8)
        #expect(evaluated.brep.edges.count == 12)
        #expect(evaluated.brep.faces.count == 4)
        #expect(evaluated.generatedNames.keys.contains {
            $0.components.contains(.generated(GeneratedSubshapeRole.startFace.rawValue))
        } == false)
        #expect(evaluated.generatedNames.keys.contains {
            $0.components.contains(.generated(GeneratedSubshapeRole.endFace.rawValue))
        } == false)
        #expect(evaluated.meshes.values.first?.positions.isEmpty == false)
        try evaluated.brep.validate()
    }

    @Test(.timeLimit(.minutes(1)))
    func straightPathCircleSweepSheetCreatesExactCylindricalSheetWithoutCaps() throws {
        let document = makeCircleProfileStraightPathSweepDocument(
            options: SweepOptions(resultKind: .sheet)
        )
        let evaluated = try DocumentEvaluator().evaluate(document)
        let body = try #require(evaluated.brep.bodies.values.first)
        let quarterSegmentCount = Int(ceil((Double.pi / 2.0) / TessellationOptions.standard.angularTolerance))
        let expectedMeshPositionCount = (quarterSegmentCount + 1) * 2 * 4
        let expectedMeshIndexCount = quarterSegmentCount * 2 * 3 * 4

        #expect(body.kind == .sheet)
        #expect(evaluated.brep.bodies.count == 1)
        #expect(evaluated.brep.shells.count == 1)
        #expect(evaluated.brep.faces.count == 4)
        #expect(evaluated.brep.edges.count == 12)
        #expect(evaluated.brep.vertices.count == 8)
        #expect(evaluated.brep.geometry.curves.values.filter(\.isCircle).count == 8)
        #expect(evaluated.brep.geometry.surfaces.values.filter(\.isCylinder).count == 4)
        #expect(evaluated.generatedNames.keys.contains {
            $0.components.contains(.generated(GeneratedSubshapeRole.startFace.rawValue))
        } == false)
        #expect(evaluated.generatedNames.keys.contains {
            $0.components.contains(.generated(GeneratedSubshapeRole.endFace.rawValue))
        } == false)
        try evaluated.brep.validate()

        let mesh = try #require(evaluated.meshes.values.first)
        #expect(mesh.positions.count == expectedMeshPositionCount)
        #expect(mesh.indices.count == expectedMeshIndexCount)
    }

    @Test(.timeLimit(.minutes(1)))
    func pointGuidedStraightPathSweepScalesSectionToGuide() throws {
        let document = makeGuidedStraightPathSweepDocument(
            guideEndOffset: 20.0,
            guideMethod: .point
        )
        let evaluated = try DocumentEvaluator().evaluate(document)
        let endVertices = evaluated.brep.vertices.values.map(\.point).filter {
            abs($0.z - 0.010) <= 1.0e-12
        }
        let maxEndX = endVertices.map { abs($0.x) }.max() ?? 0.0
        let maxEndY = endVertices.map { abs($0.y) }.max() ?? 0.0

        #expect(evaluated.brep.bodies.count == 1)
        #expect(evaluated.brep.vertices.count == 8)
        #expect(endVertices.count == 4)
        #expect(abs(maxEndX - 0.040) <= 1.0e-12)
        #expect(abs(maxEndY - 0.020) <= 1.0e-12)
        try evaluated.brep.validate()
    }

    @Test(.timeLimit(.minutes(1)))
    func pointGuidedStraightPathSweepAcceptsMillimeterScaleContact() throws {
        let document = makeGuidedStraightPathSweepDocument(
            width: 4.0,
            height: 2.0,
            pathLength: 20.0,
            guideStartOffset: 1.0,
            guideEndOffset: 2.0,
            guideMethod: .point
        )
        let evaluated = try DocumentEvaluator().evaluate(document)
        let endVertices = evaluated.brep.vertices.values.map(\.point).filter {
            abs($0.z - 0.020) <= 1.0e-12
        }
        let maxEndX = endVertices.map { abs($0.x) }.max() ?? 0.0
        let maxEndY = endVertices.map { abs($0.y) }.max() ?? 0.0

        #expect(evaluated.brep.bodies.count == 1)
        #expect(evaluated.brep.vertices.count == 8)
        #expect(endVertices.count == 4)
        #expect(abs(maxEndX - 0.004) <= 1.0e-12)
        #expect(abs(maxEndY - 0.002) <= 1.0e-12)
        try evaluated.brep.validate()
    }

    @Test(.timeLimit(.minutes(1)))
    func chordGuidedStraightPathSweepRotatesWithoutScalingSection() throws {
        let document = makeGuidedStraightPathSweepDocument(
            guideEndOffset: 20.0,
            guideMethod: .chord
        )
        let evaluated = try DocumentEvaluator().evaluate(document)
        let endVertices = evaluated.brep.vertices.values.map(\.point).filter {
            abs($0.z - 0.010) <= 1.0e-12
        }
        let maxEndX = endVertices.map { abs($0.x) }.max() ?? 0.0
        let maxEndY = endVertices.map { abs($0.y) }.max() ?? 0.0

        #expect(evaluated.brep.bodies.count == 1)
        #expect(evaluated.brep.vertices.count == 8)
        #expect(endVertices.count == 4)
        #expect(abs(maxEndX - 0.020) <= 1.0e-12)
        #expect(abs(maxEndY - 0.010) <= 1.0e-12)
        try evaluated.brep.validate()
    }

    @Test(.timeLimit(.minutes(1)))
    func multiplePointGuidedStraightPathSweepSolvesCompatibleSectionConstraints() throws {
        let document = makeMultiGuidedStraightPathSweepDocument(
            topGuideEndOffset: 20.0,
            rightGuideEndOffset: 40.0,
            guideMethod: .point
        )
        let evaluated = try DocumentEvaluator().evaluate(document)
        let endVertices = evaluated.brep.vertices.values.map(\.point).filter {
            abs($0.z - 0.010) <= 1.0e-12
        }
        let maxEndX = endVertices.map { abs($0.x) }.max() ?? 0.0
        let maxEndY = endVertices.map { abs($0.y) }.max() ?? 0.0

        #expect(evaluated.brep.bodies.count == 1)
        #expect(evaluated.brep.vertices.count == 8)
        #expect(endVertices.count == 4)
        #expect(abs(maxEndX - 0.040) <= 1.0e-12)
        #expect(abs(maxEndY - 0.020) <= 1.0e-12)
        try evaluated.brep.validate()
    }

    @Test(.timeLimit(.minutes(1)))
    func multiplePointGuidedStraightPathSweepAppliesNonUniformRailDeformation() throws {
        let document = makeMultiGuidedStraightPathSweepDocument(
            topGuideEndOffset: 20.0,
            rightGuideEndOffset: 30.0,
            guideMethod: .point
        )
        let evaluated = try DocumentEvaluator().evaluate(document)
        let endVertices = evaluated.brep.vertices.values.map(\.point).filter {
            abs($0.z - 0.010) <= 1.0e-12
        }
        let maxEndX = endVertices.map { abs($0.x) }.max() ?? 0.0
        let maxEndY = endVertices.map { abs($0.y) }.max() ?? 0.0

        #expect(evaluated.brep.bodies.count == 1)
        #expect(evaluated.brep.vertices.count == 8)
        #expect(endVertices.count == 4)
        #expect(abs(maxEndX - 0.030) <= 1.0e-12)
        #expect(abs(maxEndY - 0.020) <= 1.0e-12)
        try evaluated.brep.validate()
    }

    @Test(.timeLimit(.minutes(1)))
    func pointGuidedStraightPathSweepAppliesSignedAxisRailDeformation() throws {
        let document = makeSignedAxisRailGuidedStraightPathSweepDocument()
        let evaluated = try DocumentEvaluator().evaluate(document)
        let endVertices = evaluated.brep.vertices.values.map(\.point).filter {
            abs($0.z - 0.010) <= 1.0e-12
        }
        let minEndX = endVertices.map(\.x).min() ?? 0.0
        let maxEndX = endVertices.map(\.x).max() ?? 0.0
        let minEndY = endVertices.map(\.y).min() ?? 0.0
        let maxEndY = endVertices.map(\.y).max() ?? 0.0

        #expect(evaluated.brep.bodies.count == 1)
        #expect(evaluated.brep.vertices.count == 8)
        #expect(endVertices.count == 4)
        #expect(abs(minEndX + 0.020) <= 1.0e-12)
        #expect(abs(maxEndX - 0.030) <= 1.0e-12)
        #expect(abs(minEndY + 0.010) <= 1.0e-12)
        #expect(abs(maxEndY - 0.020) <= 1.0e-12)
        try evaluated.brep.validate()
    }

    @Test(.timeLimit(.minutes(1)))
    func pointGuidedStraightPathSweepAppliesBilinearCornerRailDeformation() throws {
        let document = try makeBilinearCornerRailGuidedStraightPathSweepDocument()
        let evaluated = try DocumentEvaluator().evaluate(document)
        let endVertices = evaluated.brep.vertices.values.map(\.point).filter {
            abs($0.z - 0.010) <= 1.0e-12
        }
        let expectedCorners = [
            Point3D(x: -0.030, y: -0.008, z: 0.010),
            Point3D(x: 0.028, y: -0.012, z: 0.010),
            Point3D(x: 0.034, y: 0.024, z: 0.010),
            Point3D(x: -0.018, y: 0.016, z: 0.010),
        ]

        #expect(evaluated.brep.bodies.count == 1)
        #expect(evaluated.brep.vertices.count == 8)
        #expect(endVertices.count == 4)
        for expectedCorner in expectedCorners {
            #expect(endVertices.contains {
                ($0 - expectedCorner).length <= 1.0e-12
            })
        }
        try evaluated.brep.validate()
    }

    @Test(.timeLimit(.minutes(1)))
    func pointGuidedStraightPathSweepAppliesBilinearQuadrilateralRailDeformation() throws {
        let document = try makeBilinearQuadrilateralRailGuidedStraightPathSweepDocument()
        let evaluated = try DocumentEvaluator().evaluate(document)
        let endVertices = evaluated.brep.vertices.values.map(\.point).filter {
            abs($0.z - 0.010) <= 1.0e-12
        }
        let expectedCorners = [
            Point3D(x: -0.030, y: -0.008, z: 0.010),
            Point3D(x: 0.028, y: -0.012, z: 0.010),
            Point3D(x: 0.036, y: 0.022, z: 0.010),
            Point3D(x: -0.014, y: 0.018, z: 0.010),
        ]

        #expect(evaluated.brep.bodies.count == 1)
        #expect(evaluated.brep.vertices.count == 8)
        #expect(endVertices.count == 4)
        for expectedCorner in expectedCorners {
            #expect(endVertices.contains {
                ($0 - expectedCorner).length <= 1.0e-12
            })
        }
        try evaluated.brep.validate()
    }

    @Test(.timeLimit(.minutes(1)))
    func pointGuidedStraightPathSweepAppliesMeanValueCageRailDeformation() throws {
        let document = try makeMeanValueCageRailGuidedStraightPathSweepDocument()
        let evaluated = try DocumentEvaluator().evaluate(document)
        let endVertices = evaluated.brep.vertices.values.map(\.point).filter {
            abs($0.z - 0.010) <= 1.0e-12
        }
        let expectedCorners = [
            Point3D(x: -0.024, y: -0.006, z: 0.010),
            Point3D(x: 0.002, y: -0.020, z: 0.010),
            Point3D(x: 0.030, y: -0.003, z: 0.010),
            Point3D(x: 0.016, y: 0.020, z: 0.010),
            Point3D(x: -0.018, y: 0.018, z: 0.010),
        ]

        #expect(evaluated.brep.bodies.count == 1)
        #expect(evaluated.brep.vertices.count == 10)
        #expect(endVertices.count == 5)
        for expectedCorner in expectedCorners {
            #expect(endVertices.contains {
                ($0 - expectedCorner).length <= 1.0e-12
            })
        }
        try evaluated.brep.validate()
    }

    @Test(.timeLimit(.minutes(1)))
    func pointGuidedStraightPathSweepAppliesRadialPointRailDeformation() throws {
        let document = try makeRadialPointRailGuidedStraightPathSweepDocument()
        let evaluated = try DocumentEvaluator().evaluate(document)
        let endVertices = evaluated.brep.vertices.values.map(\.point).filter {
            abs($0.z - 0.010) <= 1.0e-12
        }
        let expectedCorners = radialPointRailTargetPoints().map {
            Point3D(x: $0.x * 0.001, y: $0.y * 0.001, z: 0.010)
        }

        #expect(evaluated.brep.bodies.count == 1)
        #expect(evaluated.brep.vertices.count == 10)
        #expect(endVertices.count == 5)
        for expectedCorner in expectedCorners {
            #expect(endVertices.contains {
                ($0 - expectedCorner).length <= 1.0e-12
            })
        }
        try evaluated.brep.validate()
    }

    @Test(.timeLimit(.minutes(1)))
    func pointGuidedStraightPathSweepRejectsFlippedMeanValueCageRailDeformation() throws {
        let document = try makeMeanValueCageRailGuidedStraightPathSweepDocument(
            targetPoints: [
                Point2D(x: -24.0, y: -6.0),
                Point2D(x: 2.0, y: -20.0),
                Point2D(x: 16.0, y: 20.0),
                Point2D(x: 30.0, y: -3.0),
                Point2D(x: -18.0, y: 18.0),
            ]
        )

        do {
            _ = try DocumentEvaluator().evaluate(document)
            Issue.record("Expected flipped mean-value cage rail guide sweep to be rejected.")
        } catch FeatureEvaluationError.unsupportedOperation(let message) {
            #expect(message.contains("mean-value cage rail deformation"))
        } catch {
            Issue.record("Expected unsupportedOperation for flipped mean-value cage rail guide sweep, got \(error).")
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func pointGuidedStraightPathSweepRejectsFlippedBilinearCornerRailDeformation() throws {
        let document = try makeBilinearCornerRailGuidedStraightPathSweepDocument(
            targetBottomLeft: Point2D(x: -30.0, y: -8.0),
            targetBottomRight: Point2D(x: 28.0, y: -12.0),
            targetTopRight: Point2D(x: -18.0, y: 16.0),
            targetTopLeft: Point2D(x: 34.0, y: 24.0)
        )

        do {
            _ = try DocumentEvaluator().evaluate(document)
            Issue.record("Expected flipped bilinear corner rail guide sweep to be rejected.")
        } catch FeatureEvaluationError.unsupportedOperation(let message) {
            #expect(message.contains("bilinear quadrilateral rail deformation"))
        } catch {
            Issue.record("Expected unsupportedOperation for flipped bilinear corner rail guide sweep, got \(error).")
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func pointGuidedStraightPathSweepRejectsConflictingSignedAxisRailGuides() throws {
        let document = makeConflictingSignedAxisRailGuidedStraightPathSweepDocument()

        do {
            _ = try DocumentEvaluator().evaluate(document)
            Issue.record("Expected conflicting signed-axis rail guide sweep to be rejected.")
        } catch FeatureEvaluationError.unsupportedOperation(let message) {
            #expect(message.contains("signed-axis rail deformation") || message.contains("overconstrain"))
        } catch {
            Issue.record("Expected unsupportedOperation for conflicting signed-axis rail guide sweep, got \(error).")
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func curveGuidedStraightPathSweepAllowsSlidingProfileContact() throws {
        let document = makeCurveGuidedStraightPathSweepDocument(
            guideEndOffset: 10.0,
            guideMethod: .curve
        )
        let evaluated = try DocumentEvaluator().evaluate(document)
        let endVertices = evaluated.brep.vertices.values.map(\.point).filter {
            abs($0.z - 0.010) <= 1.0e-12
        }
        let minEndX = endVertices.map(\.x).min() ?? 0.0
        let maxEndX = endVertices.map(\.x).max() ?? 0.0
        let minEndY = endVertices.map(\.y).min() ?? 0.0
        let maxEndY = endVertices.map(\.y).max() ?? 0.0

        #expect(evaluated.brep.bodies.count == 1)
        #expect(evaluated.brep.vertices.count == 8)
        #expect(endVertices.count == 4)
        #expect(abs(minEndX) <= 1.0e-12)
        #expect(abs(maxEndX - 0.020) <= 1.0e-12)
        #expect(abs(minEndY) <= 1.0e-12)
        #expect(abs(maxEndY - 0.020) <= 1.0e-12)
        try evaluated.brep.validate()
    }

    @Test(.timeLimit(.minutes(1)))
    func circleProfileExtrudeCreatesExactCylindricalBRepAndDeterministicMesh() throws {
        let document = makeCircleExtrudeDocument()
        let evaluated = try DocumentEvaluator().evaluate(document)
        let quarterSegmentCount = Int(ceil((Double.pi / 2.0) / TessellationOptions.standard.angularTolerance))
        let fullSegmentCount = quarterSegmentCount * 4
        let expectedMeshPositionCount = (fullSegmentCount + 1) * 2 + (quarterSegmentCount + 1) * 2 * 4
        let expectedMeshIndexCount = fullSegmentCount * 3 * 2 + quarterSegmentCount * 2 * 3 * 4

        #expect(evaluated.brep.bodies.count == 1)
        #expect(evaluated.brep.shells.count == 1)
        #expect(evaluated.brep.faces.count == 6)
        #expect(evaluated.brep.edges.count == 12)
        #expect(evaluated.brep.vertices.count == 8)
        #expect(evaluated.brep.geometry.curves.values.filter(\.isCircle).count == 8)
        #expect(evaluated.brep.geometry.surfaces.values.filter(\.isCylinder).count == 4)
        try evaluated.brep.validate()
        try expectBalancedEdgeOrientations(in: evaluated.brep)

        let mesh = try #require(evaluated.meshes.values.first)
        #expect(mesh.indices.count == expectedMeshIndexCount)
        #expect(mesh.positions.count == expectedMeshPositionCount)

        let evaluatedAgain = try DocumentEvaluator().evaluate(document)
        #expect(evaluatedAgain.meshes.values.first?.indices == mesh.indices)
    }

    @Test(.timeLimit(.minutes(1)))
    func circleProfileExtractionReportsMultipleCirclesAsUnsupported() throws {
        var sketch = circleSketch(radius: .constant(.length(10.0, unit: .millimeter)))
        sketch.entities[SketchEntityID()] = .circle(SketchCircle(
            center: SketchPoint(
                x: .constant(.length(20.0, unit: .millimeter)),
                y: .constant(.length(0.0, unit: .millimeter))
            ),
            radius: .constant(.length(5.0, unit: .millimeter))
        ))

        do {
            _ = try SketchProfileExtractor().extractProfiles(
                from: sketch,
                sourceFeatureID: FeatureID(),
                parameters: ResolvedParameterTable()
            )
            Issue.record("Expected multiple circle profiles to be rejected.")
        } catch SketchError.unsupportedProfile(let message) {
            #expect(message.contains("Multiple circle"))
        } catch {
            Issue.record("Expected unsupportedProfile for multiple circles, got \(error).")
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func circleProfileExtractionRejectsUnstableTinyPolygonization() {
        let document = makeCircleExtrudeDocument(
            radius: 2.0e-6,
            unit: .meter,
            documentUnits: .meters
        )

        #expect(throws: SketchError.self) {
            _ = try DocumentEvaluator().evaluate(document)
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func profileExtractionAllowsCollinearSplitVertices() throws {
        func point(_ x: Double, _ y: Double) -> SketchPoint {
            SketchPoint(
                x: .constant(.length(x, unit: .meter)),
                y: .constant(.length(y, unit: .meter))
            )
        }

        let bottomOuterID = SketchEntityID()
        let bottomCornerID = SketchEntityID()
        let rightCornerID = SketchEntityID()
        let rightOuterID = SketchEntityID()
        let topID = SketchEntityID()
        let leftID = SketchEntityID()
        let bottomLeft = point(0.0, 0.0)
        let bottomSplit = point(0.008, 0.0)
        let bottomRight = point(0.010, 0.0)
        let rightSplit = point(0.010, 0.002)
        let topRight = point(0.010, 0.006)
        let topLeft = point(0.0, 0.006)
        let sketch = Sketch(
            plane: .xy,
            entities: [
                bottomOuterID: .line(SketchLine(start: bottomLeft, end: bottomSplit)),
                bottomCornerID: .line(SketchLine(start: bottomSplit, end: bottomRight)),
                rightCornerID: .line(SketchLine(start: bottomRight, end: rightSplit)),
                rightOuterID: .line(SketchLine(start: rightSplit, end: topRight)),
                topID: .line(SketchLine(start: topRight, end: topLeft)),
                leftID: .line(SketchLine(start: topLeft, end: bottomLeft)),
            ]
        )

        let profiles = try SketchProfileExtractor().extractProfiles(
            from: sketch,
            sourceFeatureID: FeatureID(),
            parameters: ResolvedParameterTable()
        )
        let profile = try #require(profiles.first)

        #expect(profiles.count == 1)
        #expect(profile.vertices.count == 6)
        #expect(profile.boundarySegments.count == 6)
        #expect(profile.boundarySegments.allSatisfy { segment in
            if case .line = segment {
                return true
            }
            return false
        })
        #expect(abs(polygonArea(profile.vertices) - 0.000_060) < 1.0e-12)

        let sketchFeatureID = FeatureID()
        let extrudeFeatureID = FeatureID()
        let document = CADDocument(
            units: .meters,
            parameters: ParameterTable(parameters: [:]),
            designGraph: DesignGraph(
                nodes: [
                    sketchFeatureID: FeatureNode(
                        id: sketchFeatureID,
                        operation: .sketch(sketch),
                        outputs: [FeatureOutput(role: .profile)]
                    ),
                    extrudeFeatureID: FeatureNode(
                        id: extrudeFeatureID,
                        operation: .extrude(ExtrudeFeature(
                            profile: ProfileReference(featureID: sketchFeatureID),
                            distance: .constant(.length(0.002, unit: .meter)),
                            direction: .normal
                        )),
                        inputs: [FeatureInput(featureID: sketchFeatureID, role: .profile)],
                        outputs: [FeatureOutput(role: .body)]
                    ),
                ],
                order: [sketchFeatureID, extrudeFeatureID],
                dependencies: [DependencyEdge(source: sketchFeatureID, target: extrudeFeatureID)],
                revision: DocumentRevision(2)
            )
        )
        let evaluated = try DocumentEvaluator().evaluate(document)
        let mesh = try #require(evaluated.meshes.values.first)

        #expect(evaluated.brep.faces.count == 8)
        #expect(mesh.indices.count > 0)
        #expect(mesh.indices.count % 3 == 0)
    }

    @Test(.timeLimit(.minutes(1)))
    func profileExtractionReturnsIndependentClosedLoops() throws {
        func point(_ x: Double, _ y: Double) -> SketchPoint {
            SketchPoint(
                x: .constant(.length(x, unit: .meter)),
                y: .constant(.length(y, unit: .meter))
            )
        }
        func line(_ start: SketchPoint, _ end: SketchPoint) -> SketchEntity {
            .line(SketchLine(start: start, end: end))
        }

        let firstBottomLeft = point(0.0, 0.0)
        let firstBottomRight = point(0.010, 0.0)
        let firstTopRight = point(0.010, 0.006)
        let firstTopLeft = point(0.0, 0.006)
        let secondBottomLeft = point(0.020, 0.0)
        let secondBottomRight = point(0.024, 0.0)
        let secondTopRight = point(0.024, 0.005)
        let secondTopLeft = point(0.020, 0.005)
        let sketch = Sketch(
            plane: .xy,
            entities: [
                SketchEntityID(): line(firstBottomLeft, firstBottomRight),
                SketchEntityID(): line(firstBottomRight, firstTopRight),
                SketchEntityID(): line(firstTopRight, firstTopLeft),
                SketchEntityID(): line(firstTopLeft, firstBottomLeft),
                SketchEntityID(): line(secondBottomLeft, secondBottomRight),
                SketchEntityID(): line(secondBottomRight, secondTopRight),
                SketchEntityID(): line(secondTopRight, secondTopLeft),
                SketchEntityID(): line(secondTopLeft, secondBottomLeft),
            ]
        )

        let profiles = try SketchProfileExtractor().extractProfiles(
            from: sketch,
            sourceFeatureID: FeatureID(),
            parameters: ResolvedParameterTable()
        )
        let areas = profiles.map { polygonArea($0.vertices) }.sorted()

        #expect(profiles.count == 2)
        #expect(profiles.allSatisfy { $0.boundarySegments.count == 4 })
        #expect(abs((areas.first ?? 0.0) - 0.000_020) < 1.0e-12)
        #expect(abs((areas.last ?? 0.0) - 0.000_060) < 1.0e-12)
    }

    @Test(.timeLimit(.minutes(1)))
    func profileRegionAnalyzerSummarizesPlanarProfile() throws {
        let profile = Profile(
            sourceFeatureID: FeatureID(),
            plane: .xy,
            vertices: [
                Point3D(x: 0.0, y: 0.0, z: 0.0),
                Point3D(x: 0.010, y: 0.0, z: 0.0),
                Point3D(x: 0.010, y: 0.006, z: 0.0),
                Point3D(x: 0.0, y: 0.006, z: 0.0),
            ]
        )

        let summary = try ProfileRegionAnalyzer().summary(for: profile)

        #expect(abs(summary.center.x - 0.005) < 1.0e-12)
        #expect(abs(summary.center.y - 0.003) < 1.0e-12)
        #expect(abs(summary.areaSquareMeters - 0.000_060) < 1.0e-12)
        #expect(summary.points.count == 4)
    }

    @Test(.timeLimit(.minutes(1)))
    func profileRegionAnalyzerUsesExactCircularBoundary() throws {
        let sketch = circleSketch(radius: .constant(.length(1.0, unit: .meter)), unit: .meter)
        let profiles = try SketchProfileExtractor().extractProfiles(
            from: sketch,
            sourceFeatureID: FeatureID(),
            parameters: ResolvedParameterTable()
        )
        let profile = try #require(profiles.first)

        let summary = try ProfileRegionAnalyzer().summary(for: profile)

        #expect(abs(summary.center.x) < 1.0e-12)
        #expect(abs(summary.center.y) < 1.0e-12)
        #expect(abs(summary.areaSquareMeters - Double.pi) < 1.0e-12)
        #expect(summary.points.count >= 32)
    }

    @Test(.timeLimit(.minutes(1)))
    func profileExtractionRejectsNestedClosedLoops() throws {
        func point(_ x: Double, _ y: Double) -> SketchPoint {
            SketchPoint(
                x: .constant(.length(x, unit: .meter)),
                y: .constant(.length(y, unit: .meter))
            )
        }
        func line(_ start: SketchPoint, _ end: SketchPoint) -> SketchEntity {
            .line(SketchLine(start: start, end: end))
        }

        let outerBottomLeft = point(0.0, 0.0)
        let outerBottomRight = point(0.010, 0.0)
        let outerTopRight = point(0.010, 0.010)
        let outerTopLeft = point(0.0, 0.010)
        let innerBottomLeft = point(0.003, 0.003)
        let innerBottomRight = point(0.007, 0.003)
        let innerTopRight = point(0.007, 0.007)
        let innerTopLeft = point(0.003, 0.007)
        let sketch = Sketch(
            plane: .xy,
            entities: [
                SketchEntityID(): line(outerBottomLeft, outerBottomRight),
                SketchEntityID(): line(outerBottomRight, outerTopRight),
                SketchEntityID(): line(outerTopRight, outerTopLeft),
                SketchEntityID(): line(outerTopLeft, outerBottomLeft),
                SketchEntityID(): line(innerBottomLeft, innerBottomRight),
                SketchEntityID(): line(innerBottomRight, innerTopRight),
                SketchEntityID(): line(innerTopRight, innerTopLeft),
                SketchEntityID(): line(innerTopLeft, innerBottomLeft),
            ]
        )

        do {
            _ = try SketchProfileExtractor().extractProfiles(
                from: sketch,
                sourceFeatureID: FeatureID(),
                parameters: ResolvedParameterTable()
            )
            Issue.record("Nested profile loops must be rejected until hole-aware extraction is available.")
        } catch SketchError.unsupportedProfile(let message) {
            #expect(message.contains("Nested profile loops"))
        } catch {
            Issue.record("Expected unsupportedProfile for nested loops, got \(error).")
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func arcProfileExtractionPreservesClosedCurveLoopArea() throws {
        let sketch = roundedCornerSketch()
        let profiles = try SketchProfileExtractor(
            tolerance: ModelingTolerance(distance: 1.0e-3, angle: 1.0e-9)
        ).extractProfiles(
            from: sketch,
            sourceFeatureID: FeatureID(),
            parameters: ResolvedParameterTable()
        )
        let profile = try #require(profiles.first)
        let area = polygonArea(profile.vertices)

        #expect(profiles.count == 1)
        #expect(profile.vertices.count > 4)
        #expect(profile.boundarySegments.count == 5)
        #expect(profile.boundarySegments.contains { segment in
            if case .circularArc(let arc) = segment {
                return abs(arc.center.x - 1.0) <= 1.0e-12
                    && abs(arc.center.y - 1.0) <= 1.0e-12
                    && abs(arc.radius - 1.0) <= 1.0e-12
                    && abs(arc.sweepAngle - Double.pi / 2.0) <= 1.0e-12
            }
            return false
        })
        #expect(abs(area - (3.0 + Double.pi / 4.0)) < 0.01)
    }

    @Test(.timeLimit(.minutes(1)))
    func closedSplineProfileExtractionTessellatesCurveLoop() throws {
        let sketch = closedBezierCircleSplineSketch(radius: 10.0, unit: .millimeter)
        let profiles = try SketchProfileExtractor(
            tolerance: ModelingTolerance(distance: 1.0e-5, angle: 1.0e-9)
        ).extractProfiles(
            from: sketch,
            sourceFeatureID: FeatureID(),
            parameters: ResolvedParameterTable()
        )
        let profile = try #require(profiles.first)
        let area = polygonArea(profile.vertices)
        let expectedArea = Double.pi * 0.01 * 0.01

        #expect(profiles.count == 1)
        #expect(profile.vertices.count > 16)
        #expect(profile.boundarySegments.count == profile.vertices.count)
        #expect(profile.boundarySegments.allSatisfy { segment in
            if case .line = segment {
                return true
            }
            return false
        })
        #expect(abs(area - expectedArea) < 1.0e-6)
    }

    @Test(.timeLimit(.minutes(1)))
    func closedSplineProfileExtrudeCreatesTessellatedBRep() throws {
        let document = makeClosedSplineExtrudeDocument(
            radius: 10.0,
            depth: 5.0,
            unit: .millimeter,
            documentUnits: .millimeters
        )
        let evaluated = try DocumentEvaluator().evaluate(document)

        #expect(evaluated.brep.bodies.count == 1)
        #expect(evaluated.brep.shells.count == 1)
        #expect(evaluated.brep.faces.count > 6)
        #expect(evaluated.brep.geometry.surfaces.values.allSatisfy { surface in
            if case .plane = surface {
                return true
            }
            return false
        })
        try evaluated.brep.validate()
        let mesh = try #require(evaluated.meshes.values.first)
        #expect(mesh.positions.count > 24)
        #expect(mesh.indices.count > 36)
    }

    @Test(.timeLimit(.minutes(1)))
    func obliqueVectorExtrudeKeepsCapFacesParallelToSketchPlane() throws {
        let document = makeRectangleExtrudeDocument(
            direction: .vector(Vector3D(x: 0.25, y: 0.5, z: 1.0))
        )
        let evaluated = try DocumentEvaluator().evaluate(document)
        let extrudeFeatureID = try #require(document.designGraph.order.last)
        let startFaceID = try #require(generatedFaceID(
            .startFace,
            featureID: extrudeFeatureID,
            in: evaluated
        ))
        let endFaceID = try #require(generatedFaceID(
            .endFace,
            featureID: extrudeFeatureID,
            in: evaluated
        ))
        let startNormal = try planeNormal(for: startFaceID, in: evaluated.brep)
        let endNormal = try planeNormal(for: endFaceID, in: evaluated.brep)

        try evaluated.brep.validate()
        #expect(startNormal.z < -0.9)
        #expect(endNormal.z > 0.9)
    }

    @Test(.timeLimit(.minutes(1)))
    func vectorExtrudeRejectsDirectionParallelToSketchPlane() {
        let document = makeRectangleExtrudeDocument(
            direction: .vector(Vector3D(x: 1.0, y: 1.0, z: 0.0))
        )

        #expect(throws: FeatureEvaluationError.self) {
            _ = try DocumentEvaluator().evaluate(document)
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func clockwiseProfileExtrudeNormalizesOutwardNormalsAndBalancedEdgeUses() throws {
        let document = makeRectangleExtrudeDocument(clockwiseProfile: true)
        let evaluated = try DocumentEvaluator().evaluate(document)

        try evaluated.brep.validate()
        try expectBalancedEdgeOrientations(in: evaluated.brep)
        let mesh = try #require(evaluated.meshes.values.first)
        #expect(mesh.normals[0].z < -0.9)
        let firstNormal = try firstTriangleNormal(in: mesh)
        #expect(firstNormal.dot(mesh.normals[0]) > 0.9)
    }

    @Test(.timeLimit(.minutes(1)))
    func meshTessellatorAppliesShellAndFaceOrientationToNormals() throws {
        let evaluated = try DocumentEvaluator().evaluate(makeRectangleExtrudeDocument())
        let bodyID = try #require(evaluated.meshes.keys.first)
        let originalMesh = try #require(evaluated.meshes[bodyID])
        let originalNormal = try #require(originalMesh.normals.first)

        var shellReversedModel = evaluated.brep
        let shellID = try #require(shellReversedModel.shells.keys.first)
        shellReversedModel.shells[shellID]?.orientation = .reversed
        let shellReversedMesh = try #require(MeshTessellator().tessellate(model: shellReversedModel)[bodyID])
        let shellReversedNormal = try #require(shellReversedMesh.normals.first)
        let shellReversedTriangleNormal = try firstTriangleNormal(in: shellReversedMesh)

        var faceReversedModel = evaluated.brep
        let faceID = try #require(faceReversedModel.shells[shellID]?.faceIDs.first)
        faceReversedModel.faces[faceID]?.orientation = .reversed
        let faceReversedMesh = try #require(MeshTessellator().tessellate(model: faceReversedModel)[bodyID])
        let faceReversedNormal = try #require(faceReversedMesh.normals.first)
        let faceReversedTriangleNormal = try firstTriangleNormal(in: faceReversedMesh)

        #expect(shellReversedNormal.dot(originalNormal) < -0.9)
        #expect(shellReversedTriangleNormal.dot(shellReversedNormal) > 0.9)
        #expect(faceReversedNormal.dot(originalNormal) < -0.9)
        #expect(faceReversedTriangleNormal.dot(faceReversedNormal) > 0.9)
    }

    @Test(.timeLimit(.minutes(1)))
    func concaveProfileExtrudesAndTessellatesPlanarCaps() throws {
        let document = makeConcaveExtrudeDocument()
        let evaluated = try DocumentEvaluator().evaluate(document)
        let mesh = try #require(evaluated.meshes.values.first)
        let firstNormal = try #require(mesh.normals.first)
        let firstTriangleNormal = try firstTriangleNormal(in: mesh)

        try evaluated.validate()
        try expectBalancedEdgeOrientations(in: evaluated.brep)
        #expect(evaluated.brep.vertices.count == 10)
        #expect(evaluated.brep.edges.count == 15)
        #expect(evaluated.brep.faces.count == 7)
        #expect(mesh.indices.count == 48)
        #expect(mesh.indices.count % 3 == 0)
        #expect(firstTriangleNormal.dot(firstNormal) > 0.9)
    }

    @Test(.timeLimit(.minutes(1)))
    func profileExtractionRejectsUnsupportedEntitiesInsteadOfIgnoringThem() throws {
        var document = makeRectangleExtrudeDocument()
        let sketchFeatureID = try #require(document.designGraph.order.first)
        var sketchFeature = try #require(document.designGraph.nodes[sketchFeatureID])
        guard case var .sketch(sketch) = sketchFeature.operation else {
            Issue.record("Expected first feature to be a sketch.")
            return
        }
        let circleID = SketchEntityID()
        sketch.entities[circleID] = .circle(SketchCircle(
            center: SketchPoint(
                x: .constant(.length(0.0, unit: .millimeter)),
                y: .constant(.length(0.0, unit: .millimeter))
            ),
            radius: .constant(.length(1.0, unit: .millimeter))
        ))
        sketchFeature.operation = .sketch(sketch)
        document.designGraph.nodes[sketchFeatureID] = sketchFeature

        #expect(throws: SketchError.self) {
            _ = try DocumentEvaluator().evaluate(document)
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func brepValidationRejectsMissingCurveReference() throws {
        let evaluated = try DocumentEvaluator().evaluate(makeRectangleExtrudeDocument())
        var model = evaluated.brep
        let edge = try #require(model.edges.values.first)
        model.geometry.curves.removeValue(forKey: edge.curveID)

        #expect(throws: TopologyError.self) {
            try model.validate()
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func evaluatedCachesValidateFreshnessAgainstSourceDocument() throws {
        let document = makeRectangleExtrudeDocument()
        let evaluated = try DocumentEvaluator().evaluate(document)

        try evaluated.caches.validateFreshness(for: document)
        try evaluated.validate()
    }

    @Test(.timeLimit(.minutes(1)))
    func cacheFreshnessRejectsEmptyCachesForBodyProducingDocument() throws {
        let document = makeRectangleExtrudeDocument()

        #expect(throws: CacheValidationError.self) {
            try DocumentCaches().validateFreshness(for: document)
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func evaluatedDocumentValidationRejectsTopLevelMeshesThatDoNotMatchBRep() throws {
        var evaluated = try DocumentEvaluator().evaluate(makeRectangleExtrudeDocument())
        let bodyID = try #require(evaluated.meshes.keys.first)
        evaluated.meshes[bodyID]?.positions[0].x += 0.25

        #expect(throws: CacheValidationError.self) {
            try evaluated.validate()
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func evaluatedDocumentValidationRejectsTopLevelBRepThatDoesNotMatchCache() throws {
        var evaluated = try DocumentEvaluator().evaluate(makeRectangleExtrudeDocument())
        let bodyID = try #require(evaluated.brep.bodies.keys.first)
        evaluated.brep.bodies[bodyID]?.name = "stale-body"

        #expect(throws: CacheValidationError.self) {
            try evaluated.validate()
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func evaluatedDocumentValidationRejectsPersistentNameCacheMismatch() throws {
        var evaluated = try DocumentEvaluator().evaluate(makeRectangleExtrudeDocument())
        evaluated.caches.brep?.persistentNames = PersistentNameMap()

        #expect(throws: CacheValidationError.self) {
            try evaluated.validate()
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func cacheFreshnessRejectsBRepCacheContentNotEqualToSourceEvaluationEvenWhenMeshesMatch() throws {
        let document = makeRectangleExtrudeDocument()
        var staleCaches = try DocumentEvaluator().evaluate(document).caches
        let bodyID = try #require(staleCaches.brep?.model.bodies.keys.first)
        staleCaches.brep?.model.bodies[bodyID]?.name = "stale-body"

        #expect(throws: CacheValidationError.self) {
            try staleCaches.validateFreshness(for: document)
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func evaluatedDocumentValidationRejectsInvalidGeneratedNames() throws {
        var invalidNameEvaluated = try DocumentEvaluator().evaluate(makeRectangleExtrudeDocument())
        let bodyID = try #require(invalidNameEvaluated.brep.bodies.keys.first)
        invalidNameEvaluated.generatedNames[PersistentName(components: [])] = .body(bodyID)
        invalidNameEvaluated.caches.brep?.persistentNames = PersistentNameMap(invalidNameEvaluated.generatedNames)

        var danglingReferenceEvaluated = try DocumentEvaluator().evaluate(makeRectangleExtrudeDocument())
        let extrudeFeatureID = try #require(danglingReferenceEvaluated.document.designGraph.order.last)
        let danglingName = PersistentName(components: [
            .feature(extrudeFeatureID),
            .generated(GeneratedSubshapeRole.body.rawValue)
        ])
        danglingReferenceEvaluated.generatedNames[danglingName] = .body(BodyID())
        danglingReferenceEvaluated.caches.brep?.persistentNames = PersistentNameMap(
            danglingReferenceEvaluated.generatedNames
        )

        #expect(throws: FeatureEvaluationError.self) {
            try invalidNameEvaluated.validate()
        }
        #expect(throws: FeatureEvaluationError.self) {
            try danglingReferenceEvaluated.validate()
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func evaluatedDocumentValidationRequiresGeneratedNamesToCoverTopology() throws {
        var evaluated = try DocumentEvaluator().evaluate(makeRectangleExtrudeDocument())
        let edgeName = try #require(evaluated.generatedNames.first { _, reference in
            reference.isEdge
        }?.key)
        evaluated.generatedNames.removeValue(forKey: edgeName)
        evaluated.caches.brep?.persistentNames = PersistentNameMap(evaluated.generatedNames)

        #expect(throws: FeatureEvaluationError.self) {
            try evaluated.validate()
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func evaluationReportRecordsFailedAndBlockedFeatures() throws {
        let sketchID = FeatureID()
        let extrudeID = FeatureID()
        let lineID = SketchEntityID()
        let openSketch = Sketch(
            plane: .xy,
            entities: [
                lineID: .line(SketchLine(
                    start: SketchPoint(
                        x: .constant(.length(0.0, unit: .meter)),
                        y: .constant(.length(0.0, unit: .meter))
                    ),
                    end: SketchPoint(
                        x: .constant(.length(1.0, unit: .meter)),
                        y: .constant(.length(0.0, unit: .meter))
                    )
                ))
            ]
        )
        let document = CADDocument(
            units: .meters,
            designGraph: DesignGraph(
                nodes: [
                    sketchID: FeatureNode(
                        id: sketchID,
                        operation: .sketch(openSketch),
                        outputs: [FeatureOutput(role: .profile)]
                    ),
                    extrudeID: FeatureNode(
                        id: extrudeID,
                        operation: .extrude(ExtrudeFeature(
                            profile: ProfileReference(featureID: sketchID),
                            distance: .constant(.length(1.0, unit: .meter))
                        )),
                        inputs: [FeatureInput(featureID: sketchID, role: .profile)],
                        outputs: [FeatureOutput(role: .body)]
                    )
                ],
                order: [sketchID, extrudeID],
                dependencies: [DependencyEdge(source: sketchID, target: extrudeID)]
            )
        )

        let report = DocumentEvaluator().evaluateReport(document)

        #expect(report.evaluatedDocument == nil)
        guard case let .failed(failure) = report.featureStates[sketchID] else {
            Issue.record("Sketch feature should be marked as failed.")
            return
        }
        #expect(failure.featureID == sketchID)
        #expect(failure.invalidatedFeatureIDs == [extrudeID])
        #expect(report.featureStates[extrudeID] == .blocked(upstreamFeatureID: sketchID))
        #expect(report.failure != nil)
        try report.failure?.validate()
    }

    @Test(.timeLimit(.minutes(1)))
    func evaluationReportRecordsDocumentLevelFailureAfterFeatureEvaluation() throws {
        let report = DocumentEvaluator(tessellator: EmptyTessellator()).evaluateReport(makeRectangleExtrudeDocument())

        #expect(report.evaluatedDocument == nil)
        #expect(report.isComplete == false)
        #expect(report.featureStates.values.allSatisfy { $0 == .evaluated })
        #expect(report.failure != nil)
        try report.failure?.validate()
    }

    @Test(.timeLimit(.minutes(1)))
    func evaluationReportReturnsFailureForDuplicateFeatureOrder() throws {
        let featureID = FeatureID()
        let document = CADDocument(
            units: .meters,
            designGraph: DesignGraph(
                nodes: [
                    featureID: FeatureNode(
                        id: featureID,
                        operation: .sketch(Sketch(plane: .xy)),
                        outputs: [FeatureOutput(role: .profile)]
                    )
                ],
                order: [featureID, featureID]
            )
        )

        let report = DocumentEvaluator().evaluateReport(document)

        #expect(report.evaluatedDocument == nil)
        #expect(report.isComplete == false)
        #expect(report.featureStates[featureID] == .unevaluated)
        #expect(report.failure != nil)
        try report.failure?.validate()
    }

    @Test(.timeLimit(.minutes(1)))
    func cacheFreshnessRejectsStaleBRepAndMeshMetadata() throws {
        let document = makeRectangleExtrudeDocument()
        let evaluated = try DocumentEvaluator().evaluate(document)

        var staleBRepCaches = evaluated.caches
        staleBRepCaches.brep?.parameterRevision = document.parameters.revision.advanced()

        var staleMeshCaches = evaluated.caches
        let bodyID = try #require(staleMeshCaches.meshes.keys.first)
        staleMeshCaches.meshes[bodyID]?.tessellationOptions = TessellationOptions(
            linearTolerance: 1.0e-3,
            angularTolerance: 1.0e-3
        )

        #expect(throws: CacheValidationError.self) {
            try staleBRepCaches.validateFreshness(for: document)
        }
        #expect(throws: CacheValidationError.self) {
            try staleMeshCaches.validateFreshness(for: document)
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func cacheFreshnessRejectsInvalidSourceDocumentAndKernelVersion() throws {
        let document = makeRectangleExtrudeDocument()
        let evaluated = try DocumentEvaluator().evaluate(document)
        var invalidDocument = document
        invalidDocument.schemaVersion = SchemaVersion(major: 1, minor: 0, patch: -1)
        let invalidKernelVersion = SchemaVersion(major: 1, minor: 0, patch: -1)
        var invalidKernelCaches = evaluated.caches
        invalidKernelCaches.brep?.kernelVersion = invalidKernelVersion
        for bodyID in invalidKernelCaches.meshes.keys {
            invalidKernelCaches.meshes[bodyID]?.kernelVersion = invalidKernelVersion
        }

        #expect(throws: SchemaError.self) {
            try evaluated.caches.validateFreshness(for: invalidDocument)
        }
        #expect(throws: SchemaError.self) {
            try invalidKernelCaches.validateFreshness(
                for: document,
                kernelVersion: invalidKernelVersion
            )
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func cacheFreshnessRejectsMeshContentThatDoesNotMatchBRep() throws {
        let document = makeRectangleExtrudeDocument()
        let evaluated = try DocumentEvaluator().evaluate(document)
        var staleCaches = evaluated.caches
        let bodyID = try #require(staleCaches.meshes.keys.first)
        var staleMeshCache = try #require(staleCaches.meshes[bodyID])
        for index in staleMeshCache.mesh.positions.indices {
            staleMeshCache.mesh.positions[index].x += 0.25
        }
        staleCaches.meshes[bodyID] = staleMeshCache

        #expect(throws: CacheValidationError.self) {
            try staleCaches.validateFreshness(for: document)
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func cacheFreshnessRejectsBRepContentFromDifferentSourceEvenWhenMetadataMatches() throws {
        let document = makeRectangleExtrudeDocument(width: 40.0)
        let otherDocument = makeRectangleExtrudeDocument(width: 80.0)
        var staleCaches = try DocumentEvaluator().evaluate(otherDocument).caches
        let sourceFingerprint = try document.sourceFingerprint()
        staleCaches.brep?.designRevision = document.designGraph.revision
        staleCaches.brep?.parameterRevision = document.parameters.revision
        staleCaches.brep?.sourceFingerprint = sourceFingerprint
        for bodyID in staleCaches.meshes.keys {
            staleCaches.meshes[bodyID]?.designRevision = document.designGraph.revision
            staleCaches.meshes[bodyID]?.parameterRevision = document.parameters.revision
            staleCaches.meshes[bodyID]?.sourceFingerprint = sourceFingerprint
        }

        #expect(throws: CacheValidationError.self) {
            try staleCaches.validateFreshness(for: document)
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func cacheFreshnessRejectsSourceGraphMutationWithoutRevisionAdvance() throws {
        let document = makeRectangleExtrudeDocument()
        let evaluated = try DocumentEvaluator().evaluate(document)
        var mutatedDocument = document
        let extrudeFeatureID = try #require(mutatedDocument.designGraph.order.last)
        mutatedDocument.designGraph.nodes[extrudeFeatureID]?.isSuppressed = true
        try mutatedDocument.validate()

        #expect(throws: CacheValidationError.self) {
            try evaluated.caches.validateFreshness(for: mutatedDocument)
        }

        var staleEvaluated = evaluated
        staleEvaluated.document = mutatedDocument
        #expect(throws: CacheValidationError.self) {
            try staleEvaluated.validate()
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func cacheFreshnessRejectsParameterMutationWithoutRevisionAdvance() throws {
        let document = makeRectangleExtrudeDocument()
        let evaluated = try DocumentEvaluator().evaluate(document)
        var mutatedDocument = document
        let widthID = try #require(mutatedDocument.parameters.parameters.values.first { $0.name == "width" }?.id)
        mutatedDocument.parameters.parameters[widthID]?.expression = .constant(.length(80.0, unit: .millimeter))
        try mutatedDocument.validate()

        #expect(throws: CacheValidationError.self) {
            try evaluated.caches.validateFreshness(for: mutatedDocument)
        }

        var staleEvaluated = evaluated
        staleEvaluated.document = mutatedDocument
        #expect(throws: CacheValidationError.self) {
            try staleEvaluated.validate()
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func cacheFreshnessRejectsMeshCacheTableKeyMismatch() throws {
        let document = makeRectangleExtrudeDocument()
        let evaluated = try DocumentEvaluator().evaluate(document)
        var staleCaches = evaluated.caches
        let bodyID = try #require(staleCaches.meshes.keys.first)
        staleCaches.meshes[bodyID]?.bodyID = BodyID()

        #expect(throws: CacheValidationError.self) {
            try staleCaches.validateFreshness(for: document)
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func sourceFingerprintIsIndependentOfDictionaryInsertionOrder() throws {
        var document = makeDocumentWithManyIndependentParameters(reverseInsertionOrder: false)
        var reorderedDocument = makeDocumentWithManyIndependentParameters(reverseInsertionOrder: true)
        document.id = fixedDocumentID()
        reorderedDocument.id = document.id

        #expect(try document.sourceFingerprint() == reorderedDocument.sourceFingerprint())
    }

    @Test(.timeLimit(.minutes(1)))
    func documentEvaluatorRejectsInvalidModelingTolerance() {
        let evaluator = DocumentEvaluator(tolerance: ModelingTolerance(distance: .nan, angle: 1.0e-9))

        #expect(throws: GeometryError.self) {
            _ = try evaluator.evaluate(makeRectangleExtrudeDocument())
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func documentEvaluatorRejectsEmptyEvaluationResults() {
        let emptyDocument = CADDocument(units: .meters)
        let suppressedSketchID = FeatureID()
        let suppressedDocument = CADDocument(
            units: .meters,
            designGraph: DesignGraph(
                nodes: [
                    suppressedSketchID: FeatureNode(
                        id: suppressedSketchID,
                        operation: .sketch(Sketch(plane: .xy)),
                        outputs: [FeatureOutput(role: .profile)],
                        isSuppressed: true
                    )
                ],
                order: [suppressedSketchID]
            )
        )

        #expect(throws: FeatureEvaluationError.self) {
            _ = try DocumentEvaluator().evaluate(emptyDocument)
        }
        #expect(throws: FeatureEvaluationError.self) {
            _ = try DocumentEvaluator().evaluate(suppressedDocument)
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func documentEvaluatorEvaluatesCurveOnlySketchWithoutBodyMeshes() throws {
        let featureID = FeatureID()
        let entityID = SketchEntityID()
        let sketch = Sketch(
            plane: .xy,
            entities: [
                entityID: .line(SketchLine(
                    start: SketchPoint(
                        x: .constant(.length(0.0, unit: .meter)),
                        y: .constant(.length(0.0, unit: .meter))
                    ),
                    end: SketchPoint(
                        x: .constant(.length(1.0, unit: .meter)),
                        y: .constant(.length(0.0, unit: .meter))
                    )
                ))
            ]
        )
        let document = CADDocument(
            units: .meters,
            designGraph: DesignGraph(
                nodes: [
                    featureID: FeatureNode(
                        id: featureID,
                        operation: .sketch(sketch),
                        outputs: [FeatureOutput(role: .curve)]
                    )
                ],
                order: [featureID]
            )
        )

        let evaluated = try DocumentEvaluator().evaluate(document)
        let curves = try #require(evaluated.curves[featureID])

        #expect(evaluated.brep.bodies.isEmpty)
        #expect(evaluated.meshes.isEmpty)
        #expect(curves.count == 1)
        #expect(curves.first?.source == .sketchEntity(entityID))
        try evaluated.validate()
    }

    @Test(.timeLimit(.minutes(1)))
    func documentEvaluatorRejectsIncompleteGeneratedPersistentNames() {
        let evaluator = DocumentEvaluator(featureEvaluator: IncompleteGeneratedNameFeatureEvaluator())

        #expect(throws: FeatureEvaluationError.self) {
            _ = try evaluator.evaluate(makeRectangleExtrudeDocument())
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func documentEvaluatorPropagatesCustomToleranceToDefaultKernelStages() throws {
        let tolerance = ModelingTolerance(distance: 1.0e-9, angle: 1.0e-9)
        let document = makeRectangleExtrudeDocument(
            width: 1.0e-7,
            height: 1.0e-7,
            depth: 1.0e-7,
            unit: .meter,
            documentUnits: .meters
        )

        let evaluated = try DocumentEvaluator(tolerance: tolerance).evaluate(document)
        let mesh = try #require(evaluated.meshes.values.first)

        try evaluated.brep.validate(tolerance: tolerance)
        try mesh.validate(tolerance: tolerance)
    }

    @Test(.timeLimit(.minutes(1)))
    func documentEvaluatorPropagatesCustomToleranceToSourceValidation() throws {
        let tolerance = ModelingTolerance(distance: 1.0e-3, angle: 1.0e-3)
        let document = makeRectangleExtrudeDocument(
            width: 4.0,
            height: 2.0,
            depth: 1.0,
            unit: .meter,
            documentUnits: .meters,
            sketchPlane: .plane(Plane3D(
                origin: Point3D(x: 0.0, y: 0.0, z: 0.0),
                normal: Vector3D(x: 0.0, y: 0.0, z: 1.0001)
            ))
        )

        #expect(throws: GeometryError.self) {
            try document.validate()
        }
        let evaluated = try DocumentEvaluator(tolerance: tolerance).evaluate(document)

        try evaluated.validate()
        try evaluated.caches.validateFreshness(for: document, tolerance: tolerance)
    }

    @Test(.timeLimit(.minutes(1)))
    func meshTessellatorRejectsNonFiniteTessellationOptions() throws {
        let evaluated = try DocumentEvaluator().evaluate(makeRectangleExtrudeDocument())
        let options = TessellationOptions(linearTolerance: .infinity, angularTolerance: 1.0e-3)

        #expect(throws: TessellationError.self) {
            _ = try MeshTessellator().tessellate(model: evaluated.brep, options: options)
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func brepValidationRejectsEdgeTrimEndpointMismatch() throws {
        let evaluated = try DocumentEvaluator().evaluate(makeRectangleExtrudeDocument())
        var model = evaluated.brep
        let edgeID = try #require(model.edges.keys.first)
        model.edges[edgeID]?.trim = CurveTrim(startParameter: 0.0, endParameter: 0.5)

        #expect(throws: TopologyError.self) {
            try model.validate()
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func brepValidationRejectsDegenerateEdgeGeometry() throws {
        let evaluated = try DocumentEvaluator().evaluate(makeRectangleExtrudeDocument())
        var model = evaluated.brep
        let edge = try #require(model.edges.values.first)
        let startPoint = try #require(model.vertices[edge.startVertexID]?.point)
        model.vertices[edge.endVertexID]?.point = startPoint

        #expect(throws: TopologyError.self) {
            try model.validate()
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func brepValidationRejectsFullPeriodCircleTrimAsSingleEdge() throws {
        let evaluated = try DocumentEvaluator().evaluate(makeRectangleExtrudeDocument())
        var model = evaluated.brep
        let edge = try #require(model.edges.values.first)
        let curveID = edge.curveID
        let circlePoint = Point3D(x: 1.0, y: 0.0, z: 0.0)
        model.geometry.curves[curveID] = .circle(Circle3D(center: .origin, normal: .unitZ, radius: 1.0))
        model.vertices[edge.startVertexID]?.point = circlePoint
        model.vertices[edge.endVertexID]?.point = circlePoint
        model.edges[edge.id]?.trim = CurveTrim(startParameter: 0.0, endParameter: Double.pi * 2.0)

        #expect(throws: TopologyError.self) {
            try model.validate()
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func brepValidationRejectsCircleTrimSpanningMoreThanOnePeriod() throws {
        let evaluated = try DocumentEvaluator().evaluate(makeRectangleExtrudeDocument())
        var model = evaluated.brep
        let edge = try #require(model.edges.values.first)
        let curveID = edge.curveID
        let endParameter = Double.pi * 4.0 + 0.25
        model.geometry.curves[curveID] = .circle(Circle3D(center: .origin, normal: .unitZ, radius: 1.0))
        model.vertices[edge.startVertexID]?.point = Point3D(x: 1.0, y: 0.0, z: 0.0)
        model.vertices[edge.endVertexID]?.point = Point3D(x: cos(0.25), y: sin(0.25), z: 0.0)
        model.edges[edge.id]?.trim = CurveTrim(startParameter: 0.0, endParameter: endParameter)

        #expect(throws: TopologyError.self) {
            try model.validate()
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func brepValidationRejectsMismatchedSurfaceParameterCurve() throws {
        let evaluated = try DocumentEvaluator().evaluate(makePolySplineQuadDocument())
        var model = evaluated.brep
        let face = try #require(model.faces.values.first)
        let loopID = try #require(face.loops.first)
        var loop = try #require(model.loops[loopID])
        loop.edges[0].surfaceParameterCurve = .constantV(v: 1.0, uStart: 0.0, uEnd: 1.0)
        model.loops[loopID] = loop

        #expect(throws: TopologyError.self) {
            try model.validate()
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func polySplineQuadMeshCreatesBSplineSheetTopology() throws {
        let document = makePolySplineQuadDocument()
        let evaluated = try DocumentEvaluator().evaluate(document)

        #expect(evaluated.brep.bodies.count == 1)
        let body = try #require(evaluated.brep.bodies.values.first)
        #expect(body.kind == .sheet)
        #expect(evaluated.brep.faces.count == 1)
        #expect(evaluated.brep.edges.count == 4)
        #expect(evaluated.brep.vertices.count == 4)
        let face = try #require(evaluated.brep.faces.values.first)
        let loopID = try #require(face.loops.first)
        let loop = try #require(evaluated.brep.loops[loopID])
        let surface = try #require(evaluated.brep.geometry.surfaces[face.surfaceID])
        guard case let .bSpline(bSpline) = surface else {
            Issue.record("Expected PolySpline to create a B-spline surface.")
            return
        }
        #expect(bSpline.uDegree == 3)
        #expect(bSpline.vDegree == 3)
        #expect(bSpline.uControlPointCount == 4)
        #expect(bSpline.vControlPointCount == 4)
        #expect(loop.edges.allSatisfy { $0.surfaceParameterCurve != nil })
        let mesh = try #require(evaluated.meshes.values.first)
        #expect(mesh.positions.count > 4)
        #expect(mesh.indices.count > 6)
        let generatedReferences = Array(evaluated.generatedNames.values)
        #expect(generatedReferences.contains { $0.isBody })
        #expect(generatedReferences.contains { $0.isFace })
        #expect(generatedReferences.filter { $0.isEdge }.count == 4)
        #expect(generatedReferences.filter { $0.isVertex }.count == 4)
        let generatedNameStrings = evaluated.generatedNames.keys.map(persistentNameString)
        #expect(generatedNameStrings.contains { $0.contains("generated:polySpline/subshape:patch:0:face") })
        #expect(generatedNameStrings.contains { $0.contains("subshape:patch:0:edge:uMax") })
        #expect(generatedNameStrings.contains { $0.contains("subshape:patch:0:vertex:uMax:vMax") })
    }

    @Test(.timeLimit(.minutes(1)))
    func polySplinePlanarPatchNetworkCreatesMultiPatchBSplineSheetTopology() throws {
        let document = makePolySplinePatchNetworkDocument(
            centerZ: 0.0,
            options: PolySplineOptions(mergePatches: false)
        )
        let evaluated = try DocumentEvaluator().evaluate(document)

        #expect(evaluated.brep.bodies.count == 1)
        let body = try #require(evaluated.brep.bodies.values.first)
        #expect(body.kind == .sheet)
        #expect(evaluated.brep.faces.count == 2)
        #expect(evaluated.brep.edges.count == 7)
        #expect(evaluated.brep.vertices.count == 6)
        #expect(evaluated.brep.geometry.surfaces.count == 2)
        #expect(evaluated.meshes.values.first?.positions.count ?? 0 > 18)
        let generatedReferences = Array(evaluated.generatedNames.values)
        #expect(generatedReferences.contains { $0.isBody })
        #expect(generatedReferences.filter { $0.isFace }.count == 2)
        #expect(generatedReferences.filter { $0.isEdge }.count == 8)
        #expect(generatedReferences.filter { $0.isVertex }.count == 8)
        let generatedNameStrings = evaluated.generatedNames.keys.map(persistentNameString)
        #expect(generatedNameStrings.contains { $0.contains("generated:polySpline/subshape:patch:0:face") })
        #expect(generatedNameStrings.contains { $0.contains("generated:polySpline/subshape:patch:2:face") })
        #expect(generatedNameStrings.contains { $0.contains("subshape:patch:0:edge:uMax") })
        #expect(generatedNameStrings.contains { $0.contains("subshape:patch:2:edge:uMin") })
        let patch0RightEdge = try #require(evaluated.generatedNames.first { name, _ in
            persistentNameString(name).contains("subshape:patch:0:edge:uMax")
        }?.value)
        let patch2LeftEdge = try #require(evaluated.generatedNames.first { name, _ in
            persistentNameString(name).contains("subshape:patch:2:edge:uMin")
        }?.value)
        #expect(patch0RightEdge == patch2LeftEdge)
    }

    @Test(.timeLimit(.minutes(1)))
    func polySplineQuadMeshPreservesMeshBoundaryWinding() throws {
        let forward = try DocumentEvaluator().evaluate(makePolySplineQuadDocument())
        let reversed = try DocumentEvaluator().evaluate(makePolySplineQuadDocument(indices: [0, 2, 1, 0, 3, 2]))
        let forwardSurface = try polySplineSurface(from: forward)
        let reversedSurface = try polySplineSurface(from: reversed)

        let forwardNormal = try forwardSurface.normal(u: 0.5, v: 0.5)
        let reversedNormal = try reversedSurface.normal(u: 0.5, v: 0.5)

        #expect(forwardNormal.z > 0.0)
        #expect(reversedNormal.z < 0.0)
    }

    @Test(.timeLimit(.minutes(1)))
    func surfaceQueryEvaluatorResolvesPolySplineFaceSubobjects() throws {
        let evaluated = try DocumentEvaluator().evaluate(makePolySplineQuadDocument())
        let faceName = try #require(evaluated.generatedNames.first { name, reference in
            reference.isFace && persistentNameString(name).contains("generated:polySpline/subshape:patch:0:face")
        }?.key)
        let surfaceReference = SurfaceReference(faceName: faceName)
        let evaluator = SurfaceQueryEvaluator()

        let resolved = try evaluator.resolve(surfaceReference, in: evaluated)
        guard case .bSpline = resolved.surface else {
            Issue.record("Expected the queried face to resolve to a B-spline surface.")
            return
        }

        let frame = try evaluator.frame(
            at: SurfaceParameterReference(surface: surfaceReference, u: 0.5, v: 0.5),
            in: evaluated
        )
        #expect(abs(frame.point.x - 1.0) <= 1.0e-12)
        #expect(abs(frame.point.y - 0.75) <= 1.0e-12)
        #expect(abs(frame.point.z - 0.125) <= 1.0e-12)
        #expect(frame.normal.z > 0.0)
        #expect(frame.gaussianCurvature.isFinite)
        #expect(frame.meanCurvature.isFinite)

        let bottomLeft = try evaluator.controlPoint(
            SurfaceControlPointReference(surface: surfaceReference, uIndex: 0, vIndex: 0),
            in: evaluated
        )
        let topRight = try evaluator.controlPoint(
            SurfaceControlPointReference(surface: surfaceReference, uIndex: 3, vIndex: 3),
            in: evaluated
        )
        #expect(bottomLeft.isApproximatelyEqual(to: Point3D(x: 0.0, y: 0.0, z: 0.0), tolerance: 1.0e-12))
        #expect(topRight.isApproximatelyEqual(to: Point3D(x: 2.0, y: 1.5, z: 0.4), tolerance: 1.0e-12))

        #expect(try evaluator.knot(SurfaceKnotReference(surface: surfaceReference, direction: .u, knotIndex: 0), in: evaluated) == 0.0)
        #expect(try evaluator.knot(SurfaceKnotReference(surface: surfaceReference, direction: .v, knotIndex: 7), in: evaluated) == 1.0)

        let uSpan = try evaluator.span(SurfaceSpanReference(surface: surfaceReference, direction: .u, spanIndex: 0), in: evaluated)
        let vSpan = try evaluator.span(SurfaceSpanReference(surface: surfaceReference, direction: .v, spanIndex: 0), in: evaluated)
        #expect(uSpan.lowerParameter == 0.0)
        #expect(uSpan.upperParameter == 1.0)
        #expect(vSpan.lowerParameter == 0.0)
        #expect(vSpan.upperParameter == 1.0)
    }

    @Test(.timeLimit(.minutes(1)))
    func surfaceQueryEvaluatorResolvesPolySplineTrimCurve() throws {
        let evaluated = try DocumentEvaluator().evaluate(makePolySplineQuadDocument())
        let faceName = try #require(evaluated.generatedNames.first { name, reference in
            reference.isFace && persistentNameString(name).contains("generated:polySpline/subshape:patch:0:face")
        }?.key)
        let surfaceReference = SurfaceReference(faceName: faceName)
        let evaluator = SurfaceQueryEvaluator()
        let resolved = try evaluator.resolve(surfaceReference, in: evaluated)
        let face = try #require(evaluated.brep.faces[resolved.faceID])
        let loopID = try #require(face.loops.first)
        let loop = try #require(evaluated.brep.loops[loopID])
        let storedParameterCurve = try #require(loop.edges.first?.surfaceParameterCurve)

        let trim = try evaluator.trimCurve(
            SurfaceTrimReference(surface: surfaceReference, loopIndex: 0, edgeIndex: 0),
            in: evaluated
        )

        #expect(trim.parameterCurve == storedParameterCurve)
        switch trim.parameterCurve {
        case .constantU, .constantV:
            break
        case .polyline, .bSpline:
            Issue.record("Expected a boundary B-spline trim to collapse to a constant parameter curve.")
            return
        }
        let startFrame = try evaluator.frame(
            at: SurfaceParameterReference(
                surface: surfaceReference,
                u: trim.startParameter.u,
                v: trim.startParameter.v
            ),
            in: evaluated
        )
        let endFrame = try evaluator.frame(
            at: SurfaceParameterReference(
                surface: surfaceReference,
                u: trim.endParameter.u,
                v: trim.endParameter.v
            ),
            in: evaluated
        )
        let edge = try #require(evaluated.brep.edges[trim.edgeID])
        let startVertexID = trim.orientation == .forward ? edge.startVertexID : edge.endVertexID
        let endVertexID = trim.orientation == .forward ? edge.endVertexID : edge.startVertexID
        let startPoint = try #require(evaluated.brep.vertices[startVertexID]?.point)
        let endPoint = try #require(evaluated.brep.vertices[endVertexID]?.point)

        #expect(startFrame.point.isApproximatelyEqual(to: startPoint, tolerance: 1.0e-9))
        #expect(endFrame.point.isApproximatelyEqual(to: endPoint, tolerance: 1.0e-9))
    }

    @Test(.timeLimit(.minutes(1)))
    func selectionMeasurementEvaluatorResolvesSurfaceAndTrimSelections() throws {
        let evaluated = try DocumentEvaluator().evaluate(makePolySplineQuadDocument())
        let faceName = try #require(evaluated.generatedNames.first { name, reference in
            reference.isFace && persistentNameString(name).contains("generated:polySpline/subshape:patch:0:face")
        }?.key)
        let surfaceReference = SurfaceReference(faceName: faceName)
        let evaluator = SelectionMeasurementEvaluator()

        let surfacePoint = try evaluator.point(
            for: .surface(.parameter(SurfaceParameterReference(
                surface: surfaceReference,
                u: 0.5,
                v: 0.5
            ))),
            in: evaluated
        )
        #expect(surfacePoint.point.isApproximatelyEqual(
            to: Point3D(x: 1.0, y: 0.75, z: 0.125),
            tolerance: 1.0e-12
        ))
        #expect((surfacePoint.normal?.z ?? 0.0) > 0.0)

        let trimPoint = try evaluator.point(
            for: .surface(.trim(SurfaceTrimReference(
                surface: surfaceReference,
                loopIndex: 0,
                edgeIndex: 0
            ))),
            in: evaluated
        )
        #expect(trimPoint.tangent != nil)
        #expect((trimPoint.normal?.z ?? 0.0) > 0.0)

        let angle = try evaluator.angle(
            between: .surface(.parameter(SurfaceParameterReference(
                surface: surfaceReference,
                u: 0.5,
                v: 0.5
            ))),
            and: .surface(.trim(SurfaceTrimReference(
                surface: surfaceReference,
                loopIndex: 0,
                edgeIndex: 0
            ))),
            in: evaluated
        )
        #expect(angle.angleRadians.isFinite)
        #expect(angle.firstDirection.length > 0.0)
        #expect(angle.secondDirection.length > 0.0)
    }

    @Test(.timeLimit(.minutes(1)))
    func surfaceQueryEvaluatorPreservesStoredRationalSurfaceParameterTrimCurve() throws {
        let fixture = makeRationalSurfaceParameterTrimEvaluatedDocument()
        let evaluator = SurfaceQueryEvaluator()
        try fixture.document.brep.validate()

        let trim = try evaluator.trimCurve(
            SurfaceTrimReference(
                surface: SurfaceReference(faceName: fixture.faceName),
                loopIndex: 0,
                edgeIndex: 0
            ),
            in: fixture.document
        )

        guard case let .bSpline(curve) = trim.parameterCurve else {
            Issue.record("Expected the stored rational surface parameter curve to be preserved.")
            return
        }
        let middleWeight = sqrt(0.5)
        let middle = try trim.parameterCurve.parameter(atNormalizedFraction: 0.5)

        #expect(curve.isRational)
        #expect(abs(middle.u - middleWeight) <= 1.0e-12)
        #expect(abs(middle.v - middleWeight) <= 1.0e-12)
        #expect(abs(trim.startParameter.u - 1.0) <= 1.0e-12)
        #expect(abs(trim.startParameter.v) <= 1.0e-12)
        #expect(abs(trim.endParameter.u) <= 1.0e-12)
        #expect(abs(trim.endParameter.v - 1.0) <= 1.0e-12)
    }

    @Test(.timeLimit(.minutes(1)))
    func surfaceQueryEvaluatorProjectsPointToPolySplineUVFrame() throws {
        let evaluated = try DocumentEvaluator().evaluate(makePolySplineQuadDocument())
        let faceName = try #require(evaluated.generatedNames.first { name, reference in
            reference.isFace && persistentNameString(name).contains("generated:polySpline/subshape:patch:0:face")
        }?.key)
        let surfaceReference = SurfaceReference(faceName: faceName)
        let evaluator = SurfaceQueryEvaluator()
        let sourceFrame = try evaluator.frame(
            at: SurfaceParameterReference(surface: surfaceReference, u: 0.5, v: 0.5),
            in: evaluated
        )
        let sourcePoint = sourceFrame.point + sourceFrame.normal * 0.025

        let projection = try evaluator.closestPoint(
            to: sourcePoint,
            on: surfaceReference,
            in: evaluated
        )

        #expect(projection.converged)
        #expect(abs(projection.parameterReference.u - 0.5) <= 1.0e-6)
        #expect(abs(projection.parameterReference.v - 0.5) <= 1.0e-6)
        #expect(projection.projectedPoint.isApproximatelyEqual(to: sourceFrame.point, tolerance: 1.0e-6))
        #expect(abs(projection.distance - 0.025) <= 1.0e-6)
        #expect(projection.frame.normal.dot(sourceFrame.normal) > 0.999)
    }

    @Test(.timeLimit(.minutes(1)))
    func surfaceQueryEvaluatorProjectsAlongDirectionToPolySplineUVFrame() throws {
        let evaluated = try DocumentEvaluator().evaluate(makePolySplineQuadDocument())
        let faceName = try #require(evaluated.generatedNames.first { name, reference in
            reference.isFace && persistentNameString(name).contains("generated:polySpline/subshape:patch:0:face")
        }?.key)
        let surfaceReference = SurfaceReference(faceName: faceName)
        let evaluator = SurfaceQueryEvaluator()
        let targetFrame = try evaluator.frame(
            at: SurfaceParameterReference(surface: surfaceReference, u: 0.5, v: 0.5),
            in: evaluated
        )
        let sourcePoint = targetFrame.point + Vector3D.unitZ * 0.2

        let projection = try evaluator.project(
            sourcePoint,
            along: -Vector3D.unitZ,
            onto: surfaceReference,
            in: evaluated,
            options: SurfaceDirectionalProjectionOptions(range: .ray)
        )

        #expect(projection.converged)
        #expect(abs(projection.parameterReference.u - 0.5) <= 1.0e-6)
        #expect(abs(projection.parameterReference.v - 0.5) <= 1.0e-6)
        #expect(abs(projection.signedDistanceAlongDirection - 0.2) <= 1.0e-6)
        #expect(projection.lineDistance <= 1.0e-6)
        #expect(projection.projectedPoint.isApproximatelyEqual(to: targetFrame.point, tolerance: 1.0e-6))
    }

    @Test(.timeLimit(.minutes(1)))
    func surfaceQueryEvaluatorProjectsPointToCylindricalSurface() throws {
        let evaluated = try DocumentEvaluator().evaluate(makeCircleExtrudeDocument())
        let faceName = try #require(evaluated.generatedNames.first { _, reference in
            guard case let .face(faceID) = reference,
                  let face = evaluated.brep.faces[faceID],
                  let surface = evaluated.brep.geometry.surfaces[face.surfaceID],
                  case .cylinder = surface else {
                return false
            }
            return true
        }?.key)
        let surfaceReference = SurfaceReference(faceName: faceName)
        let evaluator = SurfaceQueryEvaluator()

        let projection = try evaluator.closestPoint(
            to: Point3D(x: 0.015, y: 0.0, z: 0.010),
            on: surfaceReference,
            in: evaluated
        )

        #expect(projection.converged)
        #expect(abs(projection.projectedPoint.x - 0.012) <= 1.0e-12)
        #expect(abs(projection.projectedPoint.y) <= 1.0e-12)
        #expect(abs(projection.projectedPoint.z - 0.010) <= 1.0e-12)
        #expect(abs(projection.distance - 0.003) <= 1.0e-12)
    }

    @Test(.timeLimit(.minutes(1)))
    func surfaceQueryEvaluatorProjectsAlongDirectionToCylindricalSurface() throws {
        let evaluated = try DocumentEvaluator().evaluate(makeCircleExtrudeDocument())
        let faceName = try #require(evaluated.generatedNames.first { _, reference in
            guard case let .face(faceID) = reference,
                  let face = evaluated.brep.faces[faceID],
                  let surface = evaluated.brep.geometry.surfaces[face.surfaceID],
                  case .cylinder = surface else {
                return false
            }
            return true
        }?.key)
        let surfaceReference = SurfaceReference(faceName: faceName)
        let evaluator = SurfaceQueryEvaluator()

        let projection = try evaluator.project(
            Point3D(x: 0.015, y: 0.0, z: 0.010),
            along: -Vector3D.unitX,
            onto: surfaceReference,
            in: evaluated,
            options: SurfaceDirectionalProjectionOptions(range: .ray)
        )

        #expect(projection.converged)
        #expect(abs(projection.signedDistanceAlongDirection - 0.003) <= 1.0e-12)
        #expect(projection.lineDistance <= 1.0e-12)
        #expect(abs(projection.projectedPoint.x - 0.012) <= 1.0e-12)
        #expect(abs(projection.projectedPoint.y) <= 1.0e-12)
        #expect(abs(projection.projectedPoint.z - 0.010) <= 1.0e-12)
    }

    @Test(.timeLimit(.minutes(1)))
    func surfaceQueryEvaluatorRespectsPlanarFaceTrimBounds() throws {
        var document = makeRectangleExtrudeDocument(documentUnits: .meters)
        let extrudeFeatureID = try #require(document.designGraph.order.last)
        let offsetFeatureID = FeatureID()
        let targetFaceName = PersistentName(components: [
            .feature(extrudeFeatureID),
            .generated(GeneratedSubshapeRole.startFace.rawValue),
        ])
        let offsetFeature = FeatureNode(
            id: offsetFeatureID,
            operation: .faceLoopOffset(
                FaceLoopOffsetFeature(
                    target: FaceLoopOffsetTargetReference(featureID: extrudeFeatureID),
                    facePersistentName: targetFaceName,
                    distance: .constant(.length(2.0, unit: .millimeter))
                )
            ),
            inputs: [FeatureInput(featureID: extrudeFeatureID, role: .target)],
            outputs: [FeatureOutput(role: .body)]
        )
        document.designGraph.nodes[offsetFeatureID] = offsetFeature
        document.designGraph.order.append(offsetFeatureID)
        document.designGraph.dependencies.append(DependencyEdge(source: extrudeFeatureID, target: offsetFeatureID))
        document.designGraph.revision = document.designGraph.revision.advanced()

        let evaluated = try DocumentEvaluator().evaluate(document)
        let centerFaceName = PersistentName(components: [
            .feature(offsetFeatureID),
            .generated("faceLoopOffset"),
            .subshape("centerFace"),
        ])
        let surfaceReference = SurfaceReference(faceName: centerFaceName)
        let evaluator = SurfaceQueryEvaluator()

        let closest = try evaluator.closestPoint(
            to: Point3D(x: 0.019, y: 0.0, z: 0.005),
            on: surfaceReference,
            in: evaluated
        )
        #expect(abs(closest.projectedPoint.x - 0.018) <= 1.0e-12)
        #expect(abs(closest.projectedPoint.y) <= 1.0e-12)
        #expect(abs(closest.projectedPoint.z) <= 1.0e-12)

        let insideProjection = try evaluator.project(
            Point3D(x: 0.017, y: 0.0, z: 0.005),
            along: -Vector3D.unitZ,
            onto: surfaceReference,
            in: evaluated,
            options: SurfaceDirectionalProjectionOptions(range: .ray)
        )
        #expect(insideProjection.converged)
        #expect(abs(insideProjection.projectedPoint.x - 0.017) <= 1.0e-12)

        #expect(throws: FeatureEvaluationError.self) {
            _ = try evaluator.project(
                Point3D(x: 0.019, y: 0.0, z: 0.005),
                along: -Vector3D.unitZ,
                onto: surfaceReference,
                in: evaluated,
                options: SurfaceDirectionalProjectionOptions(range: .ray)
            )
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func surfaceQueryEvaluatorResolvesPlanarFaceTrimCurve() throws {
        let evaluated = try DocumentEvaluator().evaluate(makeRectangleExtrudeDocument(documentUnits: .meters))
        let faceName = PersistentName(components: [
            .feature(try #require(evaluated.document.designGraph.order.last)),
            .generated(GeneratedSubshapeRole.startFace.rawValue),
        ])
        let surfaceReference = SurfaceReference(faceName: faceName)
        let evaluator = SurfaceQueryEvaluator()

        let trim = try evaluator.trimCurve(
            SurfaceTrimReference(surface: surfaceReference, loopIndex: 0, edgeIndex: 0),
            in: evaluated
        )
        let startFrame = try evaluator.frame(
            at: SurfaceParameterReference(
                surface: surfaceReference,
                u: trim.startParameter.u,
                v: trim.startParameter.v
            ),
            in: evaluated
        )
        let endFrame = try evaluator.frame(
            at: SurfaceParameterReference(
                surface: surfaceReference,
                u: trim.endParameter.u,
                v: trim.endParameter.v
            ),
            in: evaluated
        )
        let edge = try #require(evaluated.brep.edges[trim.edgeID])
        let startVertexID = trim.orientation == .forward ? edge.startVertexID : edge.endVertexID
        let endVertexID = trim.orientation == .forward ? edge.endVertexID : edge.startVertexID
        let startPoint = try #require(evaluated.brep.vertices[startVertexID]?.point)
        let endPoint = try #require(evaluated.brep.vertices[endVertexID]?.point)

        #expect(startFrame.point.isApproximatelyEqual(to: startPoint, tolerance: 1.0e-12))
        #expect(endFrame.point.isApproximatelyEqual(to: endPoint, tolerance: 1.0e-12))
    }

    @Test(.timeLimit(.minutes(1)))
    func polySplineMeshAnalysisReportsSingleQuadSupport() throws {
        let analysis = PolySplineMeshAnalyzer().analyze(mesh: makePolySplineQuadMesh())

        #expect(analysis.result.isSupported)
        #expect(analysis.result.candidateKind == .singleQuad)
        #expect(analysis.result.vertexCount == 4)
        #expect(analysis.result.usedVertexCount == 4)
        #expect(analysis.result.triangleCount == 2)
        #expect(analysis.result.boundaryEdgeCount == 4)
        #expect(analysis.result.internalEdgeCount == 1)
        #expect(analysis.result.connectedComponentCount == 1)
        #expect(analysis.result.supportedPatchCount == 1)
        #expect(analysis.result.candidatePatchCount == 1)
        #expect(analysis.orderedBoundaryPoints?.count == 4)
        #expect(analysis.result.diagnostics.contains { $0.code == .singleQuadPatchSupported })
        let patchGraph = try #require(analysis.result.patchGraph)
        #expect(patchGraph.triangleCount == 2)
        #expect(patchGraph.candidates.count == 1)
        #expect(patchGraph.selectedAdjacencies.isEmpty)
        #expect(patchGraph.unpairedTriangleIndices.isEmpty)
        #expect(patchGraph.ambiguousTriangleIndices.isEmpty)
        let partition = try #require(patchGraph.partition)
        #expect(partition.isComplete)
        #expect(partition.selectedCandidateIDs == [0])
        #expect(partition.rejectedCandidateIDs.isEmpty)
        #expect(partition.coveredTriangleIndices == [0, 1])
        #expect(partition.uncoveredTriangleIndices.isEmpty)
        let candidate = try #require(patchGraph.candidates.first)
        #expect(candidate.id == 0)
        #expect(candidate.triangleIndices == [0, 1])
        #expect(candidate.boundaryVertexIndices.count == 4)
        #expect(candidate.splitEdge == PolySplinePatchGraph.VertexPair(firstVertexIndex: 0, secondVertexIndex: 2))
    }

    @Test(.timeLimit(.minutes(1)))
    func polySplineMeshAnalysisRejectsRoundedCornerOptionWithoutLosingPatchCandidate() throws {
        let analysis = PolySplineMeshAnalyzer().analyze(
            mesh: makePolySplineQuadMesh(),
            options: PolySplineOptions(roundedCorners: true)
        )

        #expect(!analysis.result.isSupported)
        #expect(analysis.result.candidateKind == .singleQuad)
        #expect(analysis.result.supportedPatchCount == 1)
        #expect(analysis.result.candidatePatchCount == 1)
        #expect(analysis.result.patchGraph?.candidates.count == 1)
        #expect(analysis.result.patchGraph?.partition?.selectedCandidateIDs == [0])
        #expect(analysis.orderedBoundaryPoints?.count == 4)
        #expect(analysis.result.errors.contains { $0.code == .unsupportedRoundedCorners })
    }

    @Test(.timeLimit(.minutes(1)))
    func polySplineMeshAnalysisReportsPatchGraphBeforeMultiPatchEvaluation() throws {
        let analysis = PolySplineMeshAnalyzer().analyze(mesh: makePolySplinePatchNetworkMesh())

        #expect(!analysis.result.isSupported)
        #expect(analysis.result.candidateKind == .quadPatchGraph)
        #expect(analysis.result.vertexCount == 6)
        #expect(analysis.result.usedVertexCount == 6)
        #expect(analysis.result.triangleCount == 4)
        #expect(analysis.result.boundaryEdgeCount == 6)
        #expect(analysis.result.internalEdgeCount == 3)
        #expect(analysis.result.connectedComponentCount == 1)
        #expect(analysis.result.supportedPatchCount == 0)
        #expect(analysis.result.candidatePatchCount == 3)
        #expect(analysis.result.diagnostics.contains { $0.code == .patchGraphIdentified })
        #expect(analysis.result.diagnostics.contains { $0.code == .patchGraphPartitioned })
        #expect(analysis.result.diagnostics.contains { $0.code == .patchAdjacencyIdentified })
        #expect(analysis.result.diagnostics.contains { $0.code == .patchTangentPlaneDiscontinuity })
        #expect(analysis.result.diagnostics.contains { $0.code == .patchCurvatureContinuityUnresolved })
        #expect(analysis.result.errors.contains { $0.code == .unsupportedPatchNetwork })
        #expect(analysis.orderedBoundaryPoints == nil)
        let patchGraph = try #require(analysis.result.patchGraph)
        #expect(patchGraph.triangleCount == 4)
        #expect(patchGraph.candidates.count == 3)
        let adjacency = try #require(patchGraph.selectedAdjacencies.first)
        #expect(patchGraph.selectedAdjacencies.count == 1)
        #expect(adjacency.firstCandidateID == 0)
        #expect(adjacency.secondCandidateID == 2)
        #expect(adjacency.sharedEdge == PolySplinePatchGraph.VertexPair(firstVertexIndex: 1, secondVertexIndex: 4))
        #expect(adjacency.sharedVertexIndices == [1, 4])
        #expect(adjacency.continuityLevel == .positional)
        #expect(adjacency.normalAngleRadians > ModelingTolerance.standard.angle)
        #expect(adjacency.requiresCurvatureContinuitySolve)
        #expect(patchGraph.unpairedTriangleIndices.isEmpty)
        #expect(patchGraph.ambiguousTriangleIndices == [0, 3])
        let partition = try #require(patchGraph.partition)
        #expect(partition.isComplete)
        #expect(partition.selectedCandidateIDs == [0, 2])
        #expect(partition.rejectedCandidateIDs == [1])
        #expect(partition.coveredTriangleIndices == [0, 1, 2, 3])
        #expect(partition.uncoveredTriangleIndices.isEmpty)
        #expect(patchGraph.relationships.contains {
            $0.kind == .competesForTriangle && $0.triangleIndices == [0]
        })
        #expect(patchGraph.relationships.contains {
            $0.kind == .competesForTriangle && $0.triangleIndices == [3]
        })
        #expect(patchGraph.relationships.contains {
            $0.kind == .sharesBoundaryEdge && $0.vertexIndices == [1, 4]
        })
    }

    @Test(.timeLimit(.minutes(1)))
    func polySplineMeshAnalysisClassifiesCoplanarSelectedPatchAdjacencyAsTangentPlane() throws {
        let analysis = PolySplineMeshAnalyzer().analyze(
            mesh: makePolySplinePatchNetworkMesh(centerZ: 0.0),
            options: PolySplineOptions(mergePatches: false)
        )

        #expect(analysis.result.isSupported)
        #expect(analysis.result.supportedPatchCount == 2)
        #expect(analysis.supportedPatches.map(\.candidateID) == [0, 2])
        #expect(analysis.result.diagnostics.contains { $0.code == .patchAdjacencyIdentified })
        #expect(!analysis.result.diagnostics.contains { $0.code == .patchTangentPlaneDiscontinuity })
        #expect(!analysis.result.diagnostics.contains { $0.code == .patchCurvatureContinuityUnresolved })
        #expect(analysis.result.diagnostics.contains { $0.code == .planarPatchNetworkSupported })
        #expect(!analysis.result.errors.contains { $0.code == .unsupportedPatchNetwork })
        let adjacency = try #require(analysis.result.patchGraph?.selectedAdjacencies.first)
        #expect(analysis.result.patchGraph?.selectedAdjacencies.count == 1)
        #expect(adjacency.continuityLevel == .tangentPlane)
        #expect(adjacency.normalAngleRadians <= ModelingTolerance.standard.angle)
        #expect(!adjacency.requiresCurvatureContinuitySolve)
    }
}

private extension TopologyReference {
    var isBody: Bool {
        if case .body = self {
            return true
        }
        return false
    }

    var isFace: Bool {
        if case .face = self {
            return true
        }
        return false
    }

    var isEdge: Bool {
        if case .edge = self {
            return true
        }
        return false
    }

    var isVertex: Bool {
        if case .vertex = self {
            return true
        }
        return false
    }
}

private func persistentNameString(_ name: PersistentName) -> String {
    name.components.map { component in
        switch component {
        case .feature(let featureID):
            return "feature:\(featureID.description)"
        case .generated(let value):
            return "generated:\(value)"
        case .subshape(let value):
            return "subshape:\(value)"
        case .index(let index):
            return "index:\(index)"
        }
    }
    .joined(separator: "/")
}

private func lengthInMeters(_ value: Double, unit: LengthUnit) -> Double {
    unit.toInternal(value)
}

private struct IncompleteGeneratedNameFeatureEvaluator: FeatureEvaluating {
    func evaluate(feature: FeatureNode, context: EvaluationContext) throws -> EvaluationResult {
        var result = try PlanarExtrudeFeatureEvaluator().evaluate(feature: feature, context: context)
        if let name = result.generatedNames.first?.key {
            result.generatedNames.removeValue(forKey: name)
        }
        return result
    }
}

private struct EmptyTessellator: Tessellating {
    func tessellate(model: BRepModel, options: TessellationOptions) throws -> [BodyID: Mesh] {
        [:]
    }
}

private func makePolySplineQuadDocument(indices: [UInt32] = [0, 1, 2, 0, 2, 3]) -> CADDocument {
    let featureID = FeatureID()
    let feature = FeatureNode(
        id: featureID,
        name: "Quad PolySpline",
        operation: .polySpline(PolySplineFeature(sourceMesh: makePolySplineQuadMesh(indices: indices))),
        outputs: [FeatureOutput(role: .sheet)]
    )
    return CADDocument(
        units: .meters,
        designGraph: DesignGraph(
            nodes: [featureID: feature],
            order: [featureID],
            revision: DocumentRevision(1)
        )
    )
}

private func makeRationalSurfaceParameterTrimEvaluatedDocument() -> (
    document: EvaluatedDocument,
    faceName: PersistentName
) {
    let bodyID = BodyID()
    let shellID = ShellID()
    let faceID = FaceID()
    let loopID = LoopID()
    let surfaceID = SurfaceID()
    let curvedEdgeID = EdgeID()
    let leftEdgeID = EdgeID()
    let bottomEdgeID = EdgeID()
    let curvedCurveID = CurveID()
    let leftCurveID = CurveID()
    let bottomCurveID = CurveID()
    let bottomRightVertexID = VertexID()
    let topLeftVertexID = VertexID()
    let bottomLeftVertexID = VertexID()
    let middleWeight = sqrt(0.5)
    let surface = Surface3D.bSpline(BSplineSurface3D.cubicBezierPatch(
        bottomLeft: Point3D(x: 0.0, y: 0.0, z: 0.0),
        bottomRight: Point3D(x: 1.0, y: 0.0, z: 0.0),
        topRight: Point3D(x: 1.0, y: 1.0, z: 0.0),
        topLeft: Point3D(x: 0.0, y: 1.0, z: 0.0)
    ))
    let uvTrimCurve = SurfaceParameterCurve.bSpline(BSplineCurve2D(
        degree: 2,
        knots: [0.0, 0.0, 0.0, 1.0, 1.0, 1.0],
        controlPoints: [
            Point2D(x: 1.0, y: 0.0),
            Point2D(x: 1.0, y: 1.0),
            Point2D(x: 0.0, y: 1.0),
        ],
        weights: [1.0, middleWeight, 1.0]
    ))
    let curvedEdge = Edge(
        id: curvedEdgeID,
        curveID: curvedCurveID,
        startVertexID: bottomRightVertexID,
        endVertexID: topLeftVertexID,
        trim: CurveTrim(startParameter: 0.0, endParameter: 1.0)
    )
    let leftEdge = Edge(
        id: leftEdgeID,
        curveID: leftCurveID,
        startVertexID: topLeftVertexID,
        endVertexID: bottomLeftVertexID
    )
    let bottomEdge = Edge(
        id: bottomEdgeID,
        curveID: bottomCurveID,
        startVertexID: bottomLeftVertexID,
        endVertexID: bottomRightVertexID
    )
    let loop = Loop(
        id: loopID,
        role: .outer,
        edges: [
            OrientedEdge(edgeID: curvedEdgeID, orientation: .forward, surfaceParameterCurve: uvTrimCurve),
            OrientedEdge(edgeID: leftEdgeID, orientation: .forward),
            OrientedEdge(edgeID: bottomEdgeID, orientation: .forward),
        ]
    )
    let brep = BRepModel(
        geometry: GeometryStore(
            curves: [
                curvedCurveID: .bSpline(BSplineCurve3D(
                    degree: 2,
                    knots: [0.0, 0.0, 0.0, 1.0, 1.0, 1.0],
                    controlPoints: [
                        Point3D(x: 1.0, y: 0.0, z: 0.0),
                        Point3D(x: 1.0, y: 1.0, z: 0.0),
                        Point3D(x: 0.0, y: 1.0, z: 0.0),
                    ],
                    weights: [1.0, middleWeight, 1.0]
                )),
                leftCurveID: .line(Line3D(
                    origin: Point3D(x: 0.0, y: 1.0, z: 0.0),
                    direction: Vector3D(x: 0.0, y: -1.0, z: 0.0)
                )),
                bottomCurveID: .line(Line3D(
                    origin: Point3D(x: 0.0, y: 0.0, z: 0.0),
                    direction: .unitX
                )),
            ],
            surfaces: [surfaceID: surface]
        ),
        bodies: [bodyID: Body(id: bodyID, shellIDs: [shellID], kind: .sheet)],
        shells: [shellID: Shell(id: shellID, faceIDs: [faceID])],
        faces: [faceID: Face(id: faceID, surfaceID: surfaceID, loops: [loopID])],
        loops: [loopID: loop],
        edges: [
            curvedEdgeID: curvedEdge,
            leftEdgeID: leftEdge,
            bottomEdgeID: bottomEdge,
        ],
        vertices: [
            bottomRightVertexID: Vertex(id: bottomRightVertexID, point: Point3D(x: 1.0, y: 0.0, z: 0.0)),
            topLeftVertexID: Vertex(id: topLeftVertexID, point: Point3D(x: 0.0, y: 1.0, z: 0.0)),
            bottomLeftVertexID: Vertex(id: bottomLeftVertexID, point: Point3D(x: 0.0, y: 0.0, z: 0.0)),
        ]
    )
    let faceName = PersistentName(components: [
        .generated("rationalSurfaceParameterTrim"),
        .subshape("face"),
    ])
    return (
        EvaluatedDocument(
            document: CADDocument(units: .meters),
            parameters: ResolvedParameterTable(),
            brep: brep,
            meshes: [:],
            caches: DocumentCaches(),
            generatedNames: [faceName: .face(faceID)]
        ),
        faceName
    )
}

private func makePolySplinePatchNetworkDocument(
    centerZ: Double = 0.1,
    options: PolySplineOptions = PolySplineOptions()
) -> CADDocument {
    let featureID = FeatureID()
    let feature = FeatureNode(
        id: featureID,
        name: "Patch Network PolySpline",
        operation: .polySpline(
            PolySplineFeature(
                sourceMesh: makePolySplinePatchNetworkMesh(centerZ: centerZ),
                options: options
            )
        ),
        outputs: [FeatureOutput(role: .sheet)]
    )
    return CADDocument(
        units: .meters,
        designGraph: DesignGraph(
            nodes: [featureID: feature],
            order: [featureID],
            revision: DocumentRevision(1)
        )
    )
}

private func makePolySplineQuadMesh(indices: [UInt32] = [0, 1, 2, 0, 2, 3]) -> Mesh {
    Mesh(
        positions: [
            Point3D(x: 0.0, y: 0.0, z: 0.0),
            Point3D(x: 2.0, y: 0.0, z: 0.1),
            Point3D(x: 2.0, y: 1.5, z: 0.4),
            Point3D(x: 0.0, y: 1.5, z: 0.0),
        ],
        indices: indices
    )
}

private func makePolySplinePatchNetworkMesh(centerZ: Double = 0.1) -> Mesh {
    Mesh(
        positions: [
            Point3D(x: 0.0, y: 0.0, z: 0.0),
            Point3D(x: 1.0, y: 0.0, z: 0.0),
            Point3D(x: 2.0, y: 0.0, z: 0.0),
            Point3D(x: 0.0, y: 1.0, z: 0.0),
            Point3D(x: 1.0, y: 1.0, z: centerZ),
            Point3D(x: 2.0, y: 1.0, z: 0.0),
        ],
        indices: [
            0, 1, 4,
            0, 4, 3,
            1, 2, 5,
            1, 5, 4,
        ]
    )
}

private func polySplineSurface(from document: EvaluatedDocument) throws -> BSplineSurface3D {
    let face = try #require(document.brep.faces.values.first)
    let surface = try #require(document.brep.geometry.surfaces[face.surfaceID])
    guard case let .bSpline(bSpline) = surface else {
        Issue.record("Expected a B-spline surface.")
        throw FeatureEvaluationError.unsupportedOperation("Expected a B-spline surface.")
    }
    return bSpline
}

private func makeRectangleExtrudeDocument(
    width: Double = 40.0,
    height: Double = 20.0,
    depth: Double = 10.0,
    unit: LengthUnit = .millimeter,
    documentUnits: UnitSystem = .millimeters,
    clockwiseProfile: Bool = false,
    sketchPlane: SketchPlane = .xy,
    direction: ExtrudeDirection = .normal
) -> CADDocument {
    let widthID = ParameterID()
    let heightID = ParameterID()
    let depthID = ParameterID()
    let parameters = ParameterTable(parameters: [
        widthID: Parameter(
            id: widthID,
            name: "width",
            expression: .constant(.length(width, unit: unit)),
            kind: .length
        ),
        heightID: Parameter(
            id: heightID,
            name: "height",
            expression: .constant(.length(height, unit: unit)),
            kind: .length
        ),
        depthID: Parameter(
            id: depthID,
            name: "depth",
            expression: .constant(.length(depth, unit: unit)),
            kind: .length
        )
    ])

    let sketch = rectangleSketch(
        widthID: widthID,
        heightID: heightID,
        plane: sketchPlane,
        clockwise: clockwiseProfile
    )
    let sketchFeatureID = FeatureID()
    let extrudeFeatureID = FeatureID()
    let sketchFeature = FeatureNode(
        id: sketchFeatureID,
        operation: .sketch(sketch),
        outputs: [FeatureOutput(role: .profile)]
    )
    let extrudeFeature = FeatureNode(
        id: extrudeFeatureID,
        operation: .extrude(
            ExtrudeFeature(
                profile: ProfileReference(featureID: sketchFeatureID),
                distance: .reference(depthID),
                direction: direction
            )
        ),
        inputs: [FeatureInput(featureID: sketchFeatureID, role: .profile)],
        outputs: [FeatureOutput(role: .body)]
    )
    let designGraph = DesignGraph(
        nodes: [
            sketchFeatureID: sketchFeature,
            extrudeFeatureID: extrudeFeature
        ],
        order: [sketchFeatureID, extrudeFeatureID],
        dependencies: [DependencyEdge(source: sketchFeatureID, target: extrudeFeatureID)],
        revision: DocumentRevision(2)
    )
    return CADDocument(units: documentUnits, parameters: parameters, designGraph: designGraph)
}

private func makeAxisAlignedRectangleRevolveDocument(
    radius: Double = 20.0,
    height: Double = 40.0,
    unit: LengthUnit = .millimeter,
    documentUnits: UnitSystem = .millimeters,
    axis: RevolveAxis = RevolveAxis(origin: .origin, direction: .unitY),
    angle: CADExpression = .constant(.angle(360.0, unit: .degree))
) -> CADDocument {
    let radiusID = ParameterID()
    let heightID = ParameterID()
    let parameters = ParameterTable(parameters: [
        radiusID: Parameter(
            id: radiusID,
            name: "radius",
            expression: .constant(.length(radius, unit: unit)),
            kind: .length
        ),
        heightID: Parameter(
            id: heightID,
            name: "height",
            expression: .constant(.length(height, unit: unit)),
            kind: .length
        ),
    ])

    let sketchFeatureID = FeatureID()
    let revolveFeatureID = FeatureID()
    let sketchFeature = FeatureNode(
        id: sketchFeatureID,
        operation: .sketch(axisAlignedRectangleSketch(radiusID: radiusID, heightID: heightID)),
        outputs: [FeatureOutput(role: .profile)]
    )
    let revolveFeature = FeatureNode(
        id: revolveFeatureID,
        operation: .revolve(RevolveFeature(
            profile: ProfileReference(featureID: sketchFeatureID),
            axis: axis,
            angle: angle
        )),
        inputs: [FeatureInput(featureID: sketchFeatureID, role: .profile)],
        outputs: [FeatureOutput(role: .body)]
    )
    return CADDocument(
        units: documentUnits,
        parameters: parameters,
        designGraph: DesignGraph(
            nodes: [
                sketchFeatureID: sketchFeature,
                revolveFeatureID: revolveFeature,
            ],
            order: [sketchFeatureID, revolveFeatureID],
            dependencies: [DependencyEdge(source: sketchFeatureID, target: revolveFeatureID)],
            revision: DocumentRevision(2)
        )
    )
}

private func makeCrossAxisRevolveDocument() -> CADDocument {
    let sketchFeatureID = FeatureID()
    let revolveFeatureID = FeatureID()
    let sketchFeature = FeatureNode(
        id: sketchFeatureID,
        operation: .sketch(crossAxisRevolveSketch()),
        outputs: [FeatureOutput(role: .profile)]
    )
    let revolveFeature = FeatureNode(
        id: revolveFeatureID,
        operation: .revolve(RevolveFeature(
            profile: ProfileReference(featureID: sketchFeatureID),
            axis: RevolveAxis(origin: .origin, direction: .unitY)
        )),
        inputs: [FeatureInput(featureID: sketchFeatureID, role: .profile)],
        outputs: [FeatureOutput(role: .body)]
    )
    return CADDocument(
        units: .meters,
        designGraph: DesignGraph(
            nodes: [
                sketchFeatureID: sketchFeature,
                revolveFeatureID: revolveFeature,
            ],
            order: [sketchFeatureID, revolveFeatureID],
            dependencies: [DependencyEdge(source: sketchFeatureID, target: revolveFeatureID)],
            revision: DocumentRevision(2)
        )
    )
}

private func makeConicalRevolveDocument() -> CADDocument {
    let sketchFeatureID = FeatureID()
    let revolveFeatureID = FeatureID()
    let sketchFeature = FeatureNode(
        id: sketchFeatureID,
        operation: .sketch(conicalRevolveSketch()),
        outputs: [FeatureOutput(role: .profile)]
    )
    let revolveFeature = FeatureNode(
        id: revolveFeatureID,
        operation: .revolve(RevolveFeature(
            profile: ProfileReference(featureID: sketchFeatureID),
            axis: RevolveAxis(origin: .origin, direction: .unitY)
        )),
        inputs: [FeatureInput(featureID: sketchFeatureID, role: .profile)],
        outputs: [FeatureOutput(role: .body)]
    )
    return CADDocument(
        units: .meters,
        designGraph: DesignGraph(
            nodes: [
                sketchFeatureID: sketchFeature,
                revolveFeatureID: revolveFeature,
            ],
            order: [sketchFeatureID, revolveFeatureID],
            dependencies: [DependencyEdge(source: sketchFeatureID, target: revolveFeatureID)],
            revision: DocumentRevision(2)
        )
    )
}

private func makeParallelogramExtrudeDocument(
    depth: Double = 10.0,
    unit: LengthUnit = .millimeter,
    documentUnits: UnitSystem = .millimeters
) -> CADDocument {
    let depthID = ParameterID()
    let parameters = ParameterTable(parameters: [
        depthID: Parameter(
            id: depthID,
            name: "depth",
            expression: .constant(.length(depth, unit: unit)),
            kind: .length
        )
    ])
    let sketchFeatureID = FeatureID()
    let extrudeFeatureID = FeatureID()
    let sketchFeature = FeatureNode(
        id: sketchFeatureID,
        operation: .sketch(parallelogramSketch(unit: unit)),
        outputs: [FeatureOutput(role: .profile)]
    )
    let extrudeFeature = FeatureNode(
        id: extrudeFeatureID,
        operation: .extrude(
            ExtrudeFeature(
                profile: ProfileReference(featureID: sketchFeatureID),
                distance: .reference(depthID),
                direction: .normal
            )
        ),
        inputs: [FeatureInput(featureID: sketchFeatureID, role: .profile)],
        outputs: [FeatureOutput(role: .body)]
    )
    let designGraph = DesignGraph(
        nodes: [
            sketchFeatureID: sketchFeature,
            extrudeFeatureID: extrudeFeature,
        ],
        order: [sketchFeatureID, extrudeFeatureID],
        dependencies: [DependencyEdge(source: sketchFeatureID, target: extrudeFeatureID)],
        revision: DocumentRevision(2)
    )
    return CADDocument(units: documentUnits, parameters: parameters, designGraph: designGraph)
}

private func makeStraightPathSweepDocument(
    width: Double = 40.0,
    height: Double = 20.0,
    pathLength: Double = 10.0,
    unit: LengthUnit = .millimeter,
    documentUnits: UnitSystem = .millimeters,
    options: SweepOptions = SweepOptions(),
    pathSketch: Sketch? = nil
) -> CADDocument {
    let widthID = ParameterID()
    let heightID = ParameterID()
    let parameters = ParameterTable(parameters: [
        widthID: Parameter(
            id: widthID,
            name: "width",
            expression: .constant(.length(width, unit: unit)),
            kind: .length
        ),
        heightID: Parameter(
            id: heightID,
            name: "height",
            expression: .constant(.length(height, unit: unit)),
            kind: .length
        )
    ])

    let profileFeatureID = FeatureID()
    let pathFeatureID = FeatureID()
    let sweepFeatureID = FeatureID()
    let profileFeature = FeatureNode(
        id: profileFeatureID,
        operation: .sketch(rectangleSketch(widthID: widthID, heightID: heightID, plane: .xy)),
        outputs: [
            FeatureOutput(role: .profile),
            FeatureOutput(role: .curve),
        ]
    )
    let pathFeature = FeatureNode(
        id: pathFeatureID,
        operation: .sketch(pathSketch ?? straightLinePathSketch(length: pathLength, unit: unit)),
        outputs: [FeatureOutput(role: .curve)]
    )
    let sweepFeature = FeatureNode(
        id: sweepFeatureID,
        operation: .sweep(SweepFeature(
            sections: [.profile(ProfileReference(featureID: profileFeatureID))],
            path: SweepPathReference(featureID: pathFeatureID),
            options: options
        )),
        inputs: [
            FeatureInput(featureID: profileFeatureID, role: .profile),
            FeatureInput(featureID: pathFeatureID, role: .path),
        ],
        outputs: [FeatureOutput(role: sweepOutputRole(for: options.resultKind))]
    )
    let designGraph = DesignGraph(
        nodes: [
            profileFeatureID: profileFeature,
            pathFeatureID: pathFeature,
            sweepFeatureID: sweepFeature,
        ],
        order: [profileFeatureID, pathFeatureID, sweepFeatureID],
        dependencies: [
            DependencyEdge(source: profileFeatureID, target: sweepFeatureID),
            DependencyEdge(source: pathFeatureID, target: sweepFeatureID),
        ],
        revision: DocumentRevision(3)
    )
    return CADDocument(units: documentUnits, parameters: parameters, designGraph: designGraph)
}

private func makeBridgeCurveSweepDocument(
    width: Double = 40.0,
    height: Double = 20.0,
    pathLength: Double = 10.0,
    unit: LengthUnit = .millimeter,
    documentUnits: UnitSystem = .millimeters,
    options: SweepOptions = SweepOptions()
) -> CADDocument {
    let widthID = ParameterID()
    let heightID = ParameterID()
    let parameters = ParameterTable(parameters: [
        widthID: Parameter(
            id: widthID,
            name: "width",
            expression: .constant(.length(width, unit: unit)),
            kind: .length
        ),
        heightID: Parameter(
            id: heightID,
            name: "height",
            expression: .constant(.length(height, unit: unit)),
            kind: .length
        )
    ])

    let profileFeatureID = FeatureID()
    let bridgeFeatureID = FeatureID()
    let sweepFeatureID = FeatureID()
    let profileFeature = FeatureNode(
        id: profileFeatureID,
        operation: .sketch(rectangleSketch(widthID: widthID, heightID: heightID, plane: .xy)),
        outputs: [FeatureOutput(role: .profile)]
    )
    let bridgeFeature = FeatureNode(
        id: bridgeFeatureID,
        operation: .bridgeCurve(makeZAxisBridgeCurveFeature(pathLength: pathLength, unit: unit)),
        outputs: [FeatureOutput(role: .curve)]
    )
    let sweepFeature = FeatureNode(
        id: sweepFeatureID,
        operation: .sweep(SweepFeature(
            sections: [.profile(ProfileReference(featureID: profileFeatureID))],
            path: SweepPathReference(featureID: bridgeFeatureID),
            options: options
        )),
        inputs: [
            FeatureInput(featureID: profileFeatureID, role: .profile),
            FeatureInput(featureID: bridgeFeatureID, role: .path),
        ],
        outputs: [FeatureOutput(role: sweepOutputRole(for: options.resultKind))]
    )
    let designGraph = DesignGraph(
        nodes: [
            profileFeatureID: profileFeature,
            bridgeFeatureID: bridgeFeature,
            sweepFeatureID: sweepFeature,
        ],
        order: [profileFeatureID, bridgeFeatureID, sweepFeatureID],
        dependencies: [
            DependencyEdge(source: profileFeatureID, target: sweepFeatureID),
            DependencyEdge(source: bridgeFeatureID, target: sweepFeatureID),
        ],
        revision: DocumentRevision(3)
    )
    return CADDocument(units: documentUnits, parameters: parameters, designGraph: designGraph)
}

private func makeProfilePlaneStraightPathSweepDocument(
    width: Double = 40.0,
    height: Double = 20.0,
    pathLength: Double = 10.0,
    unit: LengthUnit = .millimeter,
    documentUnits: UnitSystem = .millimeters,
    options: SweepOptions = SweepOptions()
) -> CADDocument {
    let widthID = ParameterID()
    let heightID = ParameterID()
    let parameters = ParameterTable(parameters: [
        widthID: Parameter(
            id: widthID,
            name: "width",
            expression: .constant(.length(width, unit: unit)),
            kind: .length
        ),
        heightID: Parameter(
            id: heightID,
            name: "height",
            expression: .constant(.length(height, unit: unit)),
            kind: .length
        )
    ])

    let profileFeatureID = FeatureID()
    let pathFeatureID = FeatureID()
    let sweepFeatureID = FeatureID()
    let profileFeature = FeatureNode(
        id: profileFeatureID,
        operation: .sketch(rectangleSketch(widthID: widthID, heightID: heightID, plane: .xy)),
        outputs: [
            FeatureOutput(role: .profile),
            FeatureOutput(role: .curve),
        ]
    )
    let pathFeature = FeatureNode(
        id: pathFeatureID,
        operation: .sketch(profilePlaneStraightLinePathSketch(length: pathLength, unit: unit)),
        outputs: [FeatureOutput(role: .curve)]
    )
    let sweepFeature = FeatureNode(
        id: sweepFeatureID,
        operation: .sweep(SweepFeature(
            sections: [.profile(ProfileReference(featureID: profileFeatureID))],
            path: SweepPathReference(featureID: pathFeatureID),
            options: options
        )),
        inputs: [
            FeatureInput(featureID: profileFeatureID, role: .profile),
            FeatureInput(featureID: pathFeatureID, role: .path),
        ],
        outputs: [FeatureOutput(role: sweepOutputRole(for: options.resultKind))]
    )
    let designGraph = DesignGraph(
        nodes: [
            profileFeatureID: profileFeature,
            pathFeatureID: pathFeature,
            sweepFeatureID: sweepFeature,
        ],
        order: [profileFeatureID, pathFeatureID, sweepFeatureID],
        dependencies: [
            DependencyEdge(source: profileFeatureID, target: sweepFeatureID),
            DependencyEdge(source: pathFeatureID, target: sweepFeatureID),
        ],
        revision: DocumentRevision(3)
    )
    return CADDocument(units: documentUnits, parameters: parameters, designGraph: designGraph)
}

private func makeObliqueStraightPathSweepDocument(
    width: Double = 40.0,
    height: Double = 20.0,
    pathEndOffset: Double,
    pathLength: Double,
    unit: LengthUnit = .millimeter,
    documentUnits: UnitSystem = .millimeters,
    options: SweepOptions = SweepOptions()
) throws -> CADDocument {
    let widthID = ParameterID()
    let heightID = ParameterID()
    let parameters = ParameterTable(parameters: [
        widthID: Parameter(
            id: widthID,
            name: "width",
            expression: .constant(.length(width, unit: unit)),
            kind: .length
        ),
        heightID: Parameter(
            id: heightID,
            name: "height",
            expression: .constant(.length(height, unit: unit)),
            kind: .length
        )
    ])

    let profileFeatureID = FeatureID()
    let pathFeatureID = FeatureID()
    let sweepFeatureID = FeatureID()
    let profileFeature = FeatureNode(
        id: profileFeatureID,
        operation: .sketch(rectangleSketch(widthID: widthID, heightID: heightID, plane: .xy)),
        outputs: [
            FeatureOutput(role: .profile),
            FeatureOutput(role: .curve),
        ]
    )
    let pathFeature = FeatureNode(
        id: pathFeatureID,
        operation: .sketch(try linePathSketch(
            start: .origin,
            end: Point3D(
                x: 0.0,
                y: lengthInMeters(pathEndOffset, unit: unit),
                z: lengthInMeters(pathLength, unit: unit)
            )
        )),
        outputs: [FeatureOutput(role: .curve)]
    )
    let sweepFeature = FeatureNode(
        id: sweepFeatureID,
        operation: .sweep(SweepFeature(
            sections: [.profile(ProfileReference(featureID: profileFeatureID))],
            path: SweepPathReference(featureID: pathFeatureID),
            options: options
        )),
        inputs: [
            FeatureInput(featureID: profileFeatureID, role: .profile),
            FeatureInput(featureID: pathFeatureID, role: .path),
        ],
        outputs: [FeatureOutput(role: sweepOutputRole(for: options.resultKind))]
    )
    let designGraph = DesignGraph(
        nodes: [
            profileFeatureID: profileFeature,
            pathFeatureID: pathFeature,
            sweepFeatureID: sweepFeature,
        ],
        order: [profileFeatureID, pathFeatureID, sweepFeatureID],
        dependencies: [
            DependencyEdge(source: profileFeatureID, target: sweepFeatureID),
            DependencyEdge(source: pathFeatureID, target: sweepFeatureID),
        ],
        revision: DocumentRevision(3)
    )
    return CADDocument(units: documentUnits, parameters: parameters, designGraph: designGraph)
}

private func makeBoxBooleanSweepDocument(
    targetWidth: Double,
    targetHeight: Double,
    toolWidth: Double,
    toolHeight: Double,
    toolCenterX: Double = 0.0,
    toolCenterY: Double = 0.0,
    depth: Double = 10.0,
    operation: SweepBooleanOperation,
    keepTools: Bool = false,
    unit: LengthUnit = .millimeter
) -> (document: CADDocument, targetFeatureID: FeatureID, sweepFeatureID: FeatureID) {
    let targetProfileFeatureID = FeatureID()
    let targetFeatureID = FeatureID()
    let toolProfileFeatureID = FeatureID()
    let pathFeatureID = FeatureID()
    let sweepFeatureID = FeatureID()
    let targetProfileFeature = FeatureNode(
        id: targetProfileFeatureID,
        operation: .sketch(offsetRectangleSketch(
            width: targetWidth,
            height: targetHeight,
            centerX: 0.0,
            centerY: 0.0,
            unit: unit
        )),
        outputs: [FeatureOutput(role: .profile)]
    )
    let targetFeature = FeatureNode(
        id: targetFeatureID,
        operation: .extrude(ExtrudeFeature(
            profile: ProfileReference(featureID: targetProfileFeatureID),
            distance: .constant(.length(depth, unit: unit))
        )),
        inputs: [FeatureInput(featureID: targetProfileFeatureID, role: .profile)],
        outputs: [FeatureOutput(role: .body)]
    )
    let toolProfileFeature = FeatureNode(
        id: toolProfileFeatureID,
        operation: .sketch(offsetRectangleSketch(
            width: toolWidth,
            height: toolHeight,
            centerX: toolCenterX,
            centerY: toolCenterY,
            unit: unit
        )),
        outputs: [
            FeatureOutput(role: .profile),
            FeatureOutput(role: .curve),
        ]
    )
    let pathFeature = FeatureNode(
        id: pathFeatureID,
        operation: .sketch(straightLinePathSketch(length: depth, unit: unit)),
        outputs: [FeatureOutput(role: .curve)]
    )
    let sweepFeature = FeatureNode(
        id: sweepFeatureID,
        operation: .sweep(SweepFeature(
            sections: [.profile(ProfileReference(featureID: toolProfileFeatureID))],
            path: SweepPathReference(featureID: pathFeatureID),
            targets: [SweepTargetReference(featureID: targetFeatureID)],
            options: SweepOptions(booleanOperation: operation, keepTools: keepTools)
        )),
        inputs: [
            FeatureInput(featureID: toolProfileFeatureID, role: .profile),
            FeatureInput(featureID: pathFeatureID, role: .path),
            FeatureInput(featureID: targetFeatureID, role: .target),
        ],
        outputs: [FeatureOutput(role: .body)]
    )
    let designGraph = DesignGraph(
        nodes: [
            targetProfileFeatureID: targetProfileFeature,
            targetFeatureID: targetFeature,
            toolProfileFeatureID: toolProfileFeature,
            pathFeatureID: pathFeature,
            sweepFeatureID: sweepFeature,
        ],
        order: [
            targetProfileFeatureID,
            targetFeatureID,
            toolProfileFeatureID,
            pathFeatureID,
            sweepFeatureID,
        ],
        dependencies: [
            DependencyEdge(source: targetProfileFeatureID, target: targetFeatureID),
            DependencyEdge(source: toolProfileFeatureID, target: sweepFeatureID),
            DependencyEdge(source: pathFeatureID, target: sweepFeatureID),
            DependencyEdge(source: targetFeatureID, target: sweepFeatureID),
        ],
        revision: DocumentRevision(5)
    )
    return (
        document: CADDocument(units: .millimeters, designGraph: designGraph),
        targetFeatureID: targetFeatureID,
        sweepFeatureID: sweepFeatureID
    )
}

private func makeCircleProfileStraightPathSweepDocument(
    radius: Double = 12.0,
    pathLength: Double = 20.0,
    unit: LengthUnit = .millimeter,
    documentUnits: UnitSystem = .millimeters,
    options: SweepOptions = SweepOptions()
) -> CADDocument {
    let radiusID = ParameterID()
    let parameters = ParameterTable(parameters: [
        radiusID: Parameter(
            id: radiusID,
            name: "radius",
            expression: .constant(.length(radius, unit: unit)),
            kind: .length
        )
    ])

    let profileFeatureID = FeatureID()
    let pathFeatureID = FeatureID()
    let sweepFeatureID = FeatureID()
    let profileFeature = FeatureNode(
        id: profileFeatureID,
        operation: .sketch(circleSketch(radius: .reference(radiusID), unit: unit, plane: .xy)),
        outputs: [
            FeatureOutput(role: .profile),
            FeatureOutput(role: .curve),
        ]
    )
    let pathFeature = FeatureNode(
        id: pathFeatureID,
        operation: .sketch(straightLinePathSketch(length: pathLength, unit: unit)),
        outputs: [FeatureOutput(role: .curve)]
    )
    let sweepFeature = FeatureNode(
        id: sweepFeatureID,
        operation: .sweep(SweepFeature(
            sections: [.profile(ProfileReference(featureID: profileFeatureID))],
            path: SweepPathReference(featureID: pathFeatureID),
            options: options
        )),
        inputs: [
            FeatureInput(featureID: profileFeatureID, role: .profile),
            FeatureInput(featureID: pathFeatureID, role: .path),
        ],
        outputs: [FeatureOutput(role: sweepOutputRole(for: options.resultKind))]
    )
    let designGraph = DesignGraph(
        nodes: [
            profileFeatureID: profileFeature,
            pathFeatureID: pathFeature,
            sweepFeatureID: sweepFeature,
        ],
        order: [profileFeatureID, pathFeatureID, sweepFeatureID],
        dependencies: [
            DependencyEdge(source: profileFeatureID, target: sweepFeatureID),
            DependencyEdge(source: pathFeatureID, target: sweepFeatureID),
        ],
        revision: DocumentRevision(3)
    )
    return CADDocument(units: documentUnits, parameters: parameters, designGraph: designGraph)
}

private func makeGuidedStraightPathSweepDocument(
    width: Double = 40.0,
    height: Double = 20.0,
    pathLength: Double = 10.0,
    guideStartOffset: Double = 10.0,
    guideEndOffset: Double = 20.0,
    guideMethod: SweepGuideMethod,
    unit: LengthUnit = .millimeter,
    documentUnits: UnitSystem = .millimeters
) -> CADDocument {
    let widthID = ParameterID()
    let heightID = ParameterID()
    let parameters = ParameterTable(parameters: [
        widthID: Parameter(
            id: widthID,
            name: "width",
            expression: .constant(.length(width, unit: unit)),
            kind: .length
        ),
        heightID: Parameter(
            id: heightID,
            name: "height",
            expression: .constant(.length(height, unit: unit)),
            kind: .length
        )
    ])

    let profileFeatureID = FeatureID()
    let pathFeatureID = FeatureID()
    let guideFeatureID = FeatureID()
    let sweepFeatureID = FeatureID()
    let profileFeature = FeatureNode(
        id: profileFeatureID,
        operation: .sketch(rectangleSketch(widthID: widthID, heightID: heightID, plane: .xy)),
        outputs: [
            FeatureOutput(role: .profile),
            FeatureOutput(role: .curve),
        ]
    )
    let pathFeature = FeatureNode(
        id: pathFeatureID,
        operation: .sketch(straightLinePathSketch(length: pathLength, unit: unit)),
        outputs: [FeatureOutput(role: .curve)]
    )
    let guideFeature = FeatureNode(
        id: guideFeatureID,
        operation: .sketch(straightLinePathSketch(
            startOffset: guideStartOffset,
            endOffset: guideEndOffset,
            length: pathLength,
            unit: unit
        )),
        outputs: [FeatureOutput(role: .curve)]
    )
    let sweepFeature = FeatureNode(
        id: sweepFeatureID,
        operation: .sweep(SweepFeature(
            sections: [.profile(ProfileReference(featureID: profileFeatureID))],
            path: SweepPathReference(featureID: pathFeatureID),
            guides: [SweepGuideReference(featureID: guideFeatureID)],
            options: SweepOptions(guideMethod: guideMethod)
        )),
        inputs: [
            FeatureInput(featureID: profileFeatureID, role: .profile),
            FeatureInput(featureID: pathFeatureID, role: .path),
            FeatureInput(featureID: guideFeatureID, role: .guide),
        ],
        outputs: [FeatureOutput(role: .body)]
    )
    let designGraph = DesignGraph(
        nodes: [
            profileFeatureID: profileFeature,
            pathFeatureID: pathFeature,
            guideFeatureID: guideFeature,
            sweepFeatureID: sweepFeature,
        ],
        order: [profileFeatureID, pathFeatureID, guideFeatureID, sweepFeatureID],
        dependencies: [
            DependencyEdge(source: profileFeatureID, target: sweepFeatureID),
            DependencyEdge(source: pathFeatureID, target: sweepFeatureID),
            DependencyEdge(source: guideFeatureID, target: sweepFeatureID),
        ],
        revision: DocumentRevision(4)
    )
    return CADDocument(units: documentUnits, parameters: parameters, designGraph: designGraph)
}

private func makeMultiGuidedStraightPathSweepDocument(
    width: Double = 40.0,
    height: Double = 20.0,
    pathLength: Double = 10.0,
    topGuideStartOffset: Double = 10.0,
    topGuideEndOffset: Double,
    rightGuideStartOffset: Double = 20.0,
    rightGuideEndOffset: Double,
    guideMethod: SweepGuideMethod,
    unit: LengthUnit = .millimeter,
    documentUnits: UnitSystem = .millimeters
) -> CADDocument {
    let widthID = ParameterID()
    let heightID = ParameterID()
    let parameters = ParameterTable(parameters: [
        widthID: Parameter(
            id: widthID,
            name: "width",
            expression: .constant(.length(width, unit: unit)),
            kind: .length
        ),
        heightID: Parameter(
            id: heightID,
            name: "height",
            expression: .constant(.length(height, unit: unit)),
            kind: .length
        )
    ])

    let profileFeatureID = FeatureID()
    let pathFeatureID = FeatureID()
    let topGuideFeatureID = FeatureID()
    let rightGuideFeatureID = FeatureID()
    let sweepFeatureID = FeatureID()
    let profileFeature = FeatureNode(
        id: profileFeatureID,
        operation: .sketch(rectangleSketch(widthID: widthID, heightID: heightID, plane: .xy)),
        outputs: [
            FeatureOutput(role: .profile),
            FeatureOutput(role: .curve),
        ]
    )
    let pathFeature = FeatureNode(
        id: pathFeatureID,
        operation: .sketch(straightLinePathSketch(length: pathLength, unit: unit)),
        outputs: [FeatureOutput(role: .curve)]
    )
    let topGuideFeature = FeatureNode(
        id: topGuideFeatureID,
        operation: .sketch(straightLinePathSketch(
            startOffset: topGuideStartOffset,
            endOffset: topGuideEndOffset,
            length: pathLength,
            unit: unit
        )),
        outputs: [FeatureOutput(role: .curve)]
    )
    let rightGuideFeature = FeatureNode(
        id: rightGuideFeatureID,
        operation: .sketch(straightLineXOffsetPathSketch(
            startOffset: rightGuideStartOffset,
            endOffset: rightGuideEndOffset,
            length: pathLength,
            unit: unit
        )),
        outputs: [FeatureOutput(role: .curve)]
    )
    let sweepFeature = FeatureNode(
        id: sweepFeatureID,
        operation: .sweep(SweepFeature(
            sections: [.profile(ProfileReference(featureID: profileFeatureID))],
            path: SweepPathReference(featureID: pathFeatureID),
            guides: [
                SweepGuideReference(featureID: topGuideFeatureID),
                SweepGuideReference(featureID: rightGuideFeatureID),
            ],
            options: SweepOptions(guideMethod: guideMethod)
        )),
        inputs: [
            FeatureInput(featureID: profileFeatureID, role: .profile),
            FeatureInput(featureID: pathFeatureID, role: .path),
            FeatureInput(featureID: topGuideFeatureID, role: .guide),
            FeatureInput(featureID: rightGuideFeatureID, role: .guide),
        ],
        outputs: [FeatureOutput(role: .body)]
    )
    let designGraph = DesignGraph(
        nodes: [
            profileFeatureID: profileFeature,
            pathFeatureID: pathFeature,
            topGuideFeatureID: topGuideFeature,
            rightGuideFeatureID: rightGuideFeature,
            sweepFeatureID: sweepFeature,
        ],
        order: [
            profileFeatureID,
            pathFeatureID,
            topGuideFeatureID,
            rightGuideFeatureID,
            sweepFeatureID,
        ],
        dependencies: [
            DependencyEdge(source: profileFeatureID, target: sweepFeatureID),
            DependencyEdge(source: pathFeatureID, target: sweepFeatureID),
            DependencyEdge(source: topGuideFeatureID, target: sweepFeatureID),
            DependencyEdge(source: rightGuideFeatureID, target: sweepFeatureID),
        ],
        revision: DocumentRevision(5)
    )
    return CADDocument(units: documentUnits, parameters: parameters, designGraph: designGraph)
}

private func makeSignedAxisRailGuidedStraightPathSweepDocument(
    width: Double = 40.0,
    height: Double = 20.0,
    pathLength: Double = 10.0,
    unit: LengthUnit = .millimeter,
    documentUnits: UnitSystem = .millimeters
) -> CADDocument {
    let widthID = ParameterID()
    let heightID = ParameterID()
    let parameters = ParameterTable(parameters: [
        widthID: Parameter(
            id: widthID,
            name: "width",
            expression: .constant(.length(width, unit: unit)),
            kind: .length
        ),
        heightID: Parameter(
            id: heightID,
            name: "height",
            expression: .constant(.length(height, unit: unit)),
            kind: .length
        )
    ])

    let profileFeatureID = FeatureID()
    let pathFeatureID = FeatureID()
    let topGuideFeatureID = FeatureID()
    let rightGuideFeatureID = FeatureID()
    let bottomGuideFeatureID = FeatureID()
    let sweepFeatureID = FeatureID()
    let profileFeature = FeatureNode(
        id: profileFeatureID,
        operation: .sketch(rectangleSketch(widthID: widthID, heightID: heightID, plane: .xy)),
        outputs: [
            FeatureOutput(role: .profile),
            FeatureOutput(role: .curve),
        ]
    )
    let pathFeature = FeatureNode(
        id: pathFeatureID,
        operation: .sketch(straightLinePathSketch(length: pathLength, unit: unit)),
        outputs: [FeatureOutput(role: .curve)]
    )
    let topGuideFeature = FeatureNode(
        id: topGuideFeatureID,
        operation: .sketch(straightLinePathSketch(
            startOffset: height / 2.0,
            endOffset: height,
            length: pathLength,
            unit: unit
        )),
        outputs: [FeatureOutput(role: .curve)]
    )
    let rightGuideFeature = FeatureNode(
        id: rightGuideFeatureID,
        operation: .sketch(straightLineXOffsetPathSketch(
            startOffset: width / 2.0,
            endOffset: width * 0.75,
            length: pathLength,
            unit: unit
        )),
        outputs: [FeatureOutput(role: .curve)]
    )
    let bottomGuideFeature = FeatureNode(
        id: bottomGuideFeatureID,
        operation: .sketch(straightLinePathSketch(
            startOffset: -height / 2.0,
            endOffset: -height / 2.0,
            length: pathLength,
            unit: unit
        )),
        outputs: [FeatureOutput(role: .curve)]
    )
    let sweepFeature = FeatureNode(
        id: sweepFeatureID,
        operation: .sweep(SweepFeature(
            sections: [.profile(ProfileReference(featureID: profileFeatureID))],
            path: SweepPathReference(featureID: pathFeatureID),
            guides: [
                SweepGuideReference(featureID: topGuideFeatureID),
                SweepGuideReference(featureID: rightGuideFeatureID),
                SweepGuideReference(featureID: bottomGuideFeatureID),
            ],
            options: SweepOptions(guideMethod: .point)
        )),
        inputs: [
            FeatureInput(featureID: profileFeatureID, role: .profile),
            FeatureInput(featureID: pathFeatureID, role: .path),
            FeatureInput(featureID: topGuideFeatureID, role: .guide),
            FeatureInput(featureID: rightGuideFeatureID, role: .guide),
            FeatureInput(featureID: bottomGuideFeatureID, role: .guide),
        ],
        outputs: [FeatureOutput(role: .body)]
    )
    let designGraph = DesignGraph(
        nodes: [
            profileFeatureID: profileFeature,
            pathFeatureID: pathFeature,
            topGuideFeatureID: topGuideFeature,
            rightGuideFeatureID: rightGuideFeature,
            bottomGuideFeatureID: bottomGuideFeature,
            sweepFeatureID: sweepFeature,
        ],
        order: [
            profileFeatureID,
            pathFeatureID,
            topGuideFeatureID,
            rightGuideFeatureID,
            bottomGuideFeatureID,
            sweepFeatureID,
        ],
        dependencies: [
            DependencyEdge(source: profileFeatureID, target: sweepFeatureID),
            DependencyEdge(source: pathFeatureID, target: sweepFeatureID),
            DependencyEdge(source: topGuideFeatureID, target: sweepFeatureID),
            DependencyEdge(source: rightGuideFeatureID, target: sweepFeatureID),
            DependencyEdge(source: bottomGuideFeatureID, target: sweepFeatureID),
        ],
        revision: DocumentRevision(6)
    )
    return CADDocument(units: documentUnits, parameters: parameters, designGraph: designGraph)
}

private func makeBilinearCornerRailGuidedStraightPathSweepDocument(
    width: Double = 40.0,
    height: Double = 20.0,
    pathLength: Double = 10.0,
    targetBottomLeft: Point2D = Point2D(x: -30.0, y: -8.0),
    targetBottomRight: Point2D = Point2D(x: 28.0, y: -12.0),
    targetTopRight: Point2D = Point2D(x: 34.0, y: 24.0),
    targetTopLeft: Point2D = Point2D(x: -18.0, y: 16.0),
    unit: LengthUnit = .millimeter,
    documentUnits: UnitSystem = .millimeters
) throws -> CADDocument {
    let widthID = ParameterID()
    let heightID = ParameterID()
    let parameters = ParameterTable(parameters: [
        widthID: Parameter(
            id: widthID,
            name: "width",
            expression: .constant(.length(width, unit: unit)),
            kind: .length
        ),
        heightID: Parameter(
            id: heightID,
            name: "height",
            expression: .constant(.length(height, unit: unit)),
            kind: .length
        )
    ])

    let profileFeatureID = FeatureID()
    let pathFeatureID = FeatureID()
    let bottomLeftGuideFeatureID = FeatureID()
    let bottomRightGuideFeatureID = FeatureID()
    let topRightGuideFeatureID = FeatureID()
    let topLeftGuideFeatureID = FeatureID()
    let sweepFeatureID = FeatureID()
    let halfWidth = width / 2.0
    let halfHeight = height / 2.0
    let pathLengthMeters = unit.toInternal(pathLength)
    func point(_ x: Double, _ y: Double, _ z: Double) -> Point3D {
        Point3D(
            x: unit.toInternal(x),
            y: unit.toInternal(y),
            z: unit.toInternal(z)
        )
    }
    func guideFeature(id: FeatureID, start: Point3D, end: Point3D) throws -> FeatureNode {
        FeatureNode(
            id: id,
            operation: .sketch(try linePathSketch(start: start, end: end)),
            outputs: [FeatureOutput(role: .curve)]
        )
    }

    let profileFeature = FeatureNode(
        id: profileFeatureID,
        operation: .sketch(rectangleSketch(widthID: widthID, heightID: heightID, plane: .xy)),
        outputs: [
            FeatureOutput(role: .profile),
            FeatureOutput(role: .curve),
        ]
    )
    let pathFeature = FeatureNode(
        id: pathFeatureID,
        operation: .sketch(straightLinePathSketch(length: pathLength, unit: unit)),
        outputs: [FeatureOutput(role: .curve)]
    )
    let bottomLeftGuideFeature = try guideFeature(
        id: bottomLeftGuideFeatureID,
        start: point(-halfWidth, -halfHeight, 0.0),
        end: Point3D(
            x: unit.toInternal(targetBottomLeft.x),
            y: unit.toInternal(targetBottomLeft.y),
            z: pathLengthMeters
        )
    )
    let bottomRightGuideFeature = try guideFeature(
        id: bottomRightGuideFeatureID,
        start: point(halfWidth, -halfHeight, 0.0),
        end: Point3D(
            x: unit.toInternal(targetBottomRight.x),
            y: unit.toInternal(targetBottomRight.y),
            z: pathLengthMeters
        )
    )
    let topRightGuideFeature = try guideFeature(
        id: topRightGuideFeatureID,
        start: point(halfWidth, halfHeight, 0.0),
        end: Point3D(
            x: unit.toInternal(targetTopRight.x),
            y: unit.toInternal(targetTopRight.y),
            z: pathLengthMeters
        )
    )
    let topLeftGuideFeature = try guideFeature(
        id: topLeftGuideFeatureID,
        start: point(-halfWidth, halfHeight, 0.0),
        end: Point3D(
            x: unit.toInternal(targetTopLeft.x),
            y: unit.toInternal(targetTopLeft.y),
            z: pathLengthMeters
        )
    )
    let sweepFeature = FeatureNode(
        id: sweepFeatureID,
        operation: .sweep(SweepFeature(
            sections: [.profile(ProfileReference(featureID: profileFeatureID))],
            path: SweepPathReference(featureID: pathFeatureID),
            guides: [
                SweepGuideReference(featureID: bottomLeftGuideFeatureID),
                SweepGuideReference(featureID: bottomRightGuideFeatureID),
                SweepGuideReference(featureID: topRightGuideFeatureID),
                SweepGuideReference(featureID: topLeftGuideFeatureID),
            ],
            options: SweepOptions(guideMethod: .point)
        )),
        inputs: [
            FeatureInput(featureID: profileFeatureID, role: .profile),
            FeatureInput(featureID: pathFeatureID, role: .path),
            FeatureInput(featureID: bottomLeftGuideFeatureID, role: .guide),
            FeatureInput(featureID: bottomRightGuideFeatureID, role: .guide),
            FeatureInput(featureID: topRightGuideFeatureID, role: .guide),
            FeatureInput(featureID: topLeftGuideFeatureID, role: .guide),
        ],
        outputs: [FeatureOutput(role: .body)]
    )
    let designGraph = DesignGraph(
        nodes: [
            profileFeatureID: profileFeature,
            pathFeatureID: pathFeature,
            bottomLeftGuideFeatureID: bottomLeftGuideFeature,
            bottomRightGuideFeatureID: bottomRightGuideFeature,
            topRightGuideFeatureID: topRightGuideFeature,
            topLeftGuideFeatureID: topLeftGuideFeature,
            sweepFeatureID: sweepFeature,
        ],
        order: [
            profileFeatureID,
            pathFeatureID,
            bottomLeftGuideFeatureID,
            bottomRightGuideFeatureID,
            topRightGuideFeatureID,
            topLeftGuideFeatureID,
            sweepFeatureID,
        ],
        dependencies: [
            DependencyEdge(source: profileFeatureID, target: sweepFeatureID),
            DependencyEdge(source: pathFeatureID, target: sweepFeatureID),
            DependencyEdge(source: bottomLeftGuideFeatureID, target: sweepFeatureID),
            DependencyEdge(source: bottomRightGuideFeatureID, target: sweepFeatureID),
            DependencyEdge(source: topRightGuideFeatureID, target: sweepFeatureID),
            DependencyEdge(source: topLeftGuideFeatureID, target: sweepFeatureID),
        ],
        revision: DocumentRevision(7)
    )
    return CADDocument(units: documentUnits, parameters: parameters, designGraph: designGraph)
}

private func makeBilinearQuadrilateralRailGuidedStraightPathSweepDocument(
    pathLength: Double = 10.0,
    unit: LengthUnit = .millimeter,
    documentUnits: UnitSystem = .millimeters
) throws -> CADDocument {
    let profileFeatureID = FeatureID()
    let pathFeatureID = FeatureID()
    let bottomLeftGuideFeatureID = FeatureID()
    let bottomRightGuideFeatureID = FeatureID()
    let topRightGuideFeatureID = FeatureID()
    let topLeftGuideFeatureID = FeatureID()
    let sweepFeatureID = FeatureID()
    let pathLengthMeters = unit.toInternal(pathLength)

    func point(_ x: Double, _ y: Double, _ z: Double) -> Point3D {
        Point3D(
            x: unit.toInternal(x),
            y: unit.toInternal(y),
            z: unit.toInternal(z)
        )
    }
    func guideFeature(id: FeatureID, start: Point3D, end: Point3D) throws -> FeatureNode {
        FeatureNode(
            id: id,
            operation: .sketch(try linePathSketch(start: start, end: end)),
            outputs: [FeatureOutput(role: .curve)]
        )
    }

    let profileFeature = FeatureNode(
        id: profileFeatureID,
        operation: .sketch(parallelogramSketch(unit: unit)),
        outputs: [
            FeatureOutput(role: .profile),
            FeatureOutput(role: .curve),
        ]
    )
    let pathFeature = FeatureNode(
        id: pathFeatureID,
        operation: .sketch(straightLinePathSketch(length: pathLength, unit: unit)),
        outputs: [FeatureOutput(role: .curve)]
    )
    let bottomLeftGuideFeature = try guideFeature(
        id: bottomLeftGuideFeatureID,
        start: point(-20.0, -10.0, 0.0),
        end: point(-30.0, -8.0, pathLength)
    )
    let bottomRightGuideFeature = try guideFeature(
        id: bottomRightGuideFeatureID,
        start: point(20.0, -10.0, 0.0),
        end: point(28.0, -12.0, pathLength)
    )
    let topRightGuideFeature = try guideFeature(
        id: topRightGuideFeatureID,
        start: point(25.0, 10.0, 0.0),
        end: Point3D(x: unit.toInternal(36.0), y: unit.toInternal(22.0), z: pathLengthMeters)
    )
    let topLeftGuideFeature = try guideFeature(
        id: topLeftGuideFeatureID,
        start: point(-15.0, 10.0, 0.0),
        end: Point3D(x: unit.toInternal(-14.0), y: unit.toInternal(18.0), z: pathLengthMeters)
    )
    let sweepFeature = FeatureNode(
        id: sweepFeatureID,
        operation: .sweep(SweepFeature(
            sections: [.profile(ProfileReference(featureID: profileFeatureID))],
            path: SweepPathReference(featureID: pathFeatureID),
            guides: [
                SweepGuideReference(featureID: bottomLeftGuideFeatureID),
                SweepGuideReference(featureID: bottomRightGuideFeatureID),
                SweepGuideReference(featureID: topRightGuideFeatureID),
                SweepGuideReference(featureID: topLeftGuideFeatureID),
            ],
            options: SweepOptions(guideMethod: .point)
        )),
        inputs: [
            FeatureInput(featureID: profileFeatureID, role: .profile),
            FeatureInput(featureID: pathFeatureID, role: .path),
            FeatureInput(featureID: bottomLeftGuideFeatureID, role: .guide),
            FeatureInput(featureID: bottomRightGuideFeatureID, role: .guide),
            FeatureInput(featureID: topRightGuideFeatureID, role: .guide),
            FeatureInput(featureID: topLeftGuideFeatureID, role: .guide),
        ],
        outputs: [FeatureOutput(role: .body)]
    )
    let designGraph = DesignGraph(
        nodes: [
            profileFeatureID: profileFeature,
            pathFeatureID: pathFeature,
            bottomLeftGuideFeatureID: bottomLeftGuideFeature,
            bottomRightGuideFeatureID: bottomRightGuideFeature,
            topRightGuideFeatureID: topRightGuideFeature,
            topLeftGuideFeatureID: topLeftGuideFeature,
            sweepFeatureID: sweepFeature,
        ],
        order: [
            profileFeatureID,
            pathFeatureID,
            bottomLeftGuideFeatureID,
            bottomRightGuideFeatureID,
            topRightGuideFeatureID,
            topLeftGuideFeatureID,
            sweepFeatureID,
        ],
        dependencies: [
            DependencyEdge(source: profileFeatureID, target: sweepFeatureID),
            DependencyEdge(source: pathFeatureID, target: sweepFeatureID),
            DependencyEdge(source: bottomLeftGuideFeatureID, target: sweepFeatureID),
            DependencyEdge(source: bottomRightGuideFeatureID, target: sweepFeatureID),
            DependencyEdge(source: topRightGuideFeatureID, target: sweepFeatureID),
            DependencyEdge(source: topLeftGuideFeatureID, target: sweepFeatureID),
        ],
        revision: DocumentRevision(7)
    )
    return CADDocument(units: documentUnits, designGraph: designGraph)
}

private func makeMeanValueCageRailGuidedStraightPathSweepDocument(
    pathLength: Double = 10.0,
    unit: LengthUnit = .millimeter,
    documentUnits: UnitSystem = .millimeters,
    targetPoints: [Point2D] = [
        Point2D(x: -24.0, y: -6.0),
        Point2D(x: 2.0, y: -20.0),
        Point2D(x: 30.0, y: -3.0),
        Point2D(x: 16.0, y: 20.0),
        Point2D(x: -18.0, y: 18.0),
    ]
) throws -> CADDocument {
    let profileFeatureID = FeatureID()
    let pathFeatureID = FeatureID()
    let sweepFeatureID = FeatureID()
    let sourcePoints = meanValueCageRailSourcePoints()
    guard targetPoints.count == sourcePoints.count else {
        throw FeatureEvaluationError.invalidGraph("Mean-value cage rail test targets must match source points.")
    }
    let guideFeatureIDs = sourcePoints.map { _ in FeatureID() }

    func point(_ point: Point2D, _ z: Double) -> Point3D {
        Point3D(
            x: unit.toInternal(point.x),
            y: unit.toInternal(point.y),
            z: unit.toInternal(z)
        )
    }
    func guideFeature(id: FeatureID, start: Point3D, end: Point3D) throws -> FeatureNode {
        FeatureNode(
            id: id,
            operation: .sketch(try linePathSketch(start: start, end: end)),
            outputs: [FeatureOutput(role: .curve)]
        )
    }

    let profileFeature = FeatureNode(
        id: profileFeatureID,
        operation: .sketch(meanValueCageRailProfileSketch(unit: unit)),
        outputs: [
            FeatureOutput(role: .profile),
            FeatureOutput(role: .curve),
        ]
    )
    let pathFeature = FeatureNode(
        id: pathFeatureID,
        operation: .sketch(straightLinePathSketch(length: pathLength, unit: unit)),
        outputs: [FeatureOutput(role: .curve)]
    )

    var nodes: [FeatureID: FeatureNode] = [
        profileFeatureID: profileFeature,
        pathFeatureID: pathFeature,
    ]
    var order = [profileFeatureID, pathFeatureID]
    var dependencies = [
        DependencyEdge(source: profileFeatureID, target: sweepFeatureID),
        DependencyEdge(source: pathFeatureID, target: sweepFeatureID),
    ]
    for index in sourcePoints.indices {
        let guideID = guideFeatureIDs[index]
        nodes[guideID] = try guideFeature(
            id: guideID,
            start: point(sourcePoints[index], 0.0),
            end: point(targetPoints[index], pathLength)
        )
        order.append(guideID)
        dependencies.append(DependencyEdge(source: guideID, target: sweepFeatureID))
    }

    let sweepFeature = FeatureNode(
        id: sweepFeatureID,
        operation: .sweep(SweepFeature(
            sections: [.profile(ProfileReference(featureID: profileFeatureID))],
            path: SweepPathReference(featureID: pathFeatureID),
            guides: guideFeatureIDs.map { SweepGuideReference(featureID: $0) },
            options: SweepOptions(guideMethod: .point)
        )),
        inputs: [
            FeatureInput(featureID: profileFeatureID, role: .profile),
            FeatureInput(featureID: pathFeatureID, role: .path),
        ] + guideFeatureIDs.map { FeatureInput(featureID: $0, role: .guide) },
        outputs: [FeatureOutput(role: .body)]
    )
    nodes[sweepFeatureID] = sweepFeature
    order.append(sweepFeatureID)

    let designGraph = DesignGraph(
        nodes: nodes,
        order: order,
        dependencies: dependencies,
        revision: DocumentRevision(8)
    )
    return CADDocument(units: documentUnits, designGraph: designGraph)
}

private func makeRadialPointRailGuidedStraightPathSweepDocument(
    pathLength: Double = 10.0,
    unit: LengthUnit = .millimeter,
    documentUnits: UnitSystem = .millimeters,
    targetPoints: [Point2D] = radialPointRailTargetPoints()
) throws -> CADDocument {
    let profileFeatureID = FeatureID()
    let pathFeatureID = FeatureID()
    let sweepFeatureID = FeatureID()
    let sourcePoints = radialPointRailSourcePoints()
    guard targetPoints.count == sourcePoints.count else {
        throw FeatureEvaluationError.invalidGraph("Radial point rail test targets must match source points.")
    }
    let guideFeatureIDs = sourcePoints.map { _ in FeatureID() }

    func point(_ point: Point2D, _ z: Double) -> Point3D {
        Point3D(
            x: unit.toInternal(point.x),
            y: unit.toInternal(point.y),
            z: unit.toInternal(z)
        )
    }
    func guideFeature(id: FeatureID, start: Point3D, end: Point3D) throws -> FeatureNode {
        FeatureNode(
            id: id,
            operation: .sketch(try linePathSketch(start: start, end: end)),
            outputs: [FeatureOutput(role: .curve)]
        )
    }

    let profileFeature = FeatureNode(
        id: profileFeatureID,
        operation: .sketch(radialPointRailProfileSketch(unit: unit)),
        outputs: [
            FeatureOutput(role: .profile),
            FeatureOutput(role: .curve),
        ]
    )
    let pathFeature = FeatureNode(
        id: pathFeatureID,
        operation: .sketch(straightLinePathSketch(length: pathLength, unit: unit)),
        outputs: [FeatureOutput(role: .curve)]
    )

    var nodes: [FeatureID: FeatureNode] = [
        profileFeatureID: profileFeature,
        pathFeatureID: pathFeature,
    ]
    var order = [profileFeatureID, pathFeatureID]
    var dependencies = [
        DependencyEdge(source: profileFeatureID, target: sweepFeatureID),
        DependencyEdge(source: pathFeatureID, target: sweepFeatureID),
    ]
    for index in sourcePoints.indices {
        let guideID = guideFeatureIDs[index]
        nodes[guideID] = try guideFeature(
            id: guideID,
            start: point(sourcePoints[index], 0.0),
            end: point(targetPoints[index], pathLength)
        )
        order.append(guideID)
        dependencies.append(DependencyEdge(source: guideID, target: sweepFeatureID))
    }

    let sweepFeature = FeatureNode(
        id: sweepFeatureID,
        operation: .sweep(SweepFeature(
            sections: [.profile(ProfileReference(featureID: profileFeatureID))],
            path: SweepPathReference(featureID: pathFeatureID),
            guides: guideFeatureIDs.map { SweepGuideReference(featureID: $0) },
            options: SweepOptions(guideMethod: .point)
        )),
        inputs: [
            FeatureInput(featureID: profileFeatureID, role: .profile),
            FeatureInput(featureID: pathFeatureID, role: .path),
        ] + guideFeatureIDs.map { FeatureInput(featureID: $0, role: .guide) },
        outputs: [FeatureOutput(role: .body)]
    )
    nodes[sweepFeatureID] = sweepFeature
    order.append(sweepFeatureID)

    let designGraph = DesignGraph(
        nodes: nodes,
        order: order,
        dependencies: dependencies,
        revision: DocumentRevision(8)
    )
    return CADDocument(units: documentUnits, designGraph: designGraph)
}

private func makeConflictingSignedAxisRailGuidedStraightPathSweepDocument(
    width: Double = 40.0,
    height: Double = 20.0,
    pathLength: Double = 10.0,
    unit: LengthUnit = .millimeter,
    documentUnits: UnitSystem = .millimeters
) -> CADDocument {
    let widthID = ParameterID()
    let heightID = ParameterID()
    let parameters = ParameterTable(parameters: [
        widthID: Parameter(
            id: widthID,
            name: "width",
            expression: .constant(.length(width, unit: unit)),
            kind: .length
        ),
        heightID: Parameter(
            id: heightID,
            name: "height",
            expression: .constant(.length(height, unit: unit)),
            kind: .length
        )
    ])

    let profileFeatureID = FeatureID()
    let pathFeatureID = FeatureID()
    let firstTopGuideFeatureID = FeatureID()
    let secondTopGuideFeatureID = FeatureID()
    let sweepFeatureID = FeatureID()
    let profileFeature = FeatureNode(
        id: profileFeatureID,
        operation: .sketch(rectangleSketch(widthID: widthID, heightID: heightID, plane: .xy)),
        outputs: [
            FeatureOutput(role: .profile),
            FeatureOutput(role: .curve),
        ]
    )
    let pathFeature = FeatureNode(
        id: pathFeatureID,
        operation: .sketch(straightLinePathSketch(length: pathLength, unit: unit)),
        outputs: [FeatureOutput(role: .curve)]
    )
    let firstTopGuideFeature = FeatureNode(
        id: firstTopGuideFeatureID,
        operation: .sketch(straightLinePathSketch(
            startOffset: height / 2.0,
            endOffset: height,
            length: pathLength,
            unit: unit
        )),
        outputs: [FeatureOutput(role: .curve)]
    )
    let secondTopGuideFeature = FeatureNode(
        id: secondTopGuideFeatureID,
        operation: .sketch(straightLinePathSketch(
            startOffset: height / 2.0,
            endOffset: height * 0.75,
            length: pathLength,
            unit: unit
        )),
        outputs: [FeatureOutput(role: .curve)]
    )
    let sweepFeature = FeatureNode(
        id: sweepFeatureID,
        operation: .sweep(SweepFeature(
            sections: [.profile(ProfileReference(featureID: profileFeatureID))],
            path: SweepPathReference(featureID: pathFeatureID),
            guides: [
                SweepGuideReference(featureID: firstTopGuideFeatureID),
                SweepGuideReference(featureID: secondTopGuideFeatureID),
            ],
            options: SweepOptions(guideMethod: .point)
        )),
        inputs: [
            FeatureInput(featureID: profileFeatureID, role: .profile),
            FeatureInput(featureID: pathFeatureID, role: .path),
            FeatureInput(featureID: firstTopGuideFeatureID, role: .guide),
            FeatureInput(featureID: secondTopGuideFeatureID, role: .guide),
        ],
        outputs: [FeatureOutput(role: .body)]
    )
    let designGraph = DesignGraph(
        nodes: [
            profileFeatureID: profileFeature,
            pathFeatureID: pathFeature,
            firstTopGuideFeatureID: firstTopGuideFeature,
            secondTopGuideFeatureID: secondTopGuideFeature,
            sweepFeatureID: sweepFeature,
        ],
        order: [
            profileFeatureID,
            pathFeatureID,
            firstTopGuideFeatureID,
            secondTopGuideFeatureID,
            sweepFeatureID,
        ],
        dependencies: [
            DependencyEdge(source: profileFeatureID, target: sweepFeatureID),
            DependencyEdge(source: pathFeatureID, target: sweepFeatureID),
            DependencyEdge(source: firstTopGuideFeatureID, target: sweepFeatureID),
            DependencyEdge(source: secondTopGuideFeatureID, target: sweepFeatureID),
        ],
        revision: DocumentRevision(5)
    )
    return CADDocument(units: documentUnits, parameters: parameters, designGraph: designGraph)
}

private func makeCurveGuidedStraightPathSweepDocument(
    width: Double = 20.0,
    height: Double = 20.0,
    pathLength: Double = 10.0,
    guideStartOffset: Double = 20.0,
    guideEndOffset: Double,
    guideMethod: SweepGuideMethod,
    unit: LengthUnit = .millimeter,
    documentUnits: UnitSystem = .millimeters
) -> CADDocument {
    let profileFeatureID = FeatureID()
    let pathFeatureID = FeatureID()
    let guideFeatureID = FeatureID()
    let sweepFeatureID = FeatureID()
    let profileFeature = FeatureNode(
        id: profileFeatureID,
        operation: .sketch(originCornerRectangleSketch(width: width, height: height, unit: unit)),
        outputs: [
            FeatureOutput(role: .profile),
            FeatureOutput(role: .curve),
        ]
    )
    let pathFeature = FeatureNode(
        id: pathFeatureID,
        operation: .sketch(straightLinePathSketch(length: pathLength, unit: unit)),
        outputs: [FeatureOutput(role: .curve)]
    )
    let guideFeature = FeatureNode(
        id: guideFeatureID,
        operation: .sketch(straightLineXOffsetPathSketch(
            startOffset: guideStartOffset,
            endOffset: guideEndOffset,
            length: pathLength,
            unit: unit
        )),
        outputs: [FeatureOutput(role: .curve)]
    )
    let sweepFeature = FeatureNode(
        id: sweepFeatureID,
        operation: .sweep(SweepFeature(
            sections: [.profile(ProfileReference(featureID: profileFeatureID))],
            path: SweepPathReference(featureID: pathFeatureID),
            guides: [SweepGuideReference(featureID: guideFeatureID)],
            options: SweepOptions(guideMethod: guideMethod)
        )),
        inputs: [
            FeatureInput(featureID: profileFeatureID, role: .profile),
            FeatureInput(featureID: pathFeatureID, role: .path),
            FeatureInput(featureID: guideFeatureID, role: .guide),
        ],
        outputs: [FeatureOutput(role: .body)]
    )
    let designGraph = DesignGraph(
        nodes: [
            profileFeatureID: profileFeature,
            pathFeatureID: pathFeature,
            guideFeatureID: guideFeature,
            sweepFeatureID: sweepFeature,
        ],
        order: [profileFeatureID, pathFeatureID, guideFeatureID, sweepFeatureID],
        dependencies: [
            DependencyEdge(source: profileFeatureID, target: sweepFeatureID),
            DependencyEdge(source: pathFeatureID, target: sweepFeatureID),
            DependencyEdge(source: guideFeatureID, target: sweepFeatureID),
        ],
        revision: DocumentRevision(4)
    )
    return CADDocument(units: documentUnits, designGraph: designGraph)
}

private func makeCurvedPathSweepDocument(
    width: Double = 40.0,
    height: Double = 20.0,
    radius: Double = 10.0,
    unit: LengthUnit = .millimeter,
    documentUnits: UnitSystem = .millimeters,
    options: SweepOptions = SweepOptions()
) -> CADDocument {
    let widthID = ParameterID()
    let heightID = ParameterID()
    let parameters = ParameterTable(parameters: [
        widthID: Parameter(
            id: widthID,
            name: "width",
            expression: .constant(.length(width, unit: unit)),
            kind: .length
        ),
        heightID: Parameter(
            id: heightID,
            name: "height",
            expression: .constant(.length(height, unit: unit)),
            kind: .length
        )
    ])

    let profileFeatureID = FeatureID()
    let pathFeatureID = FeatureID()
    let sweepFeatureID = FeatureID()
    let profileFeature = FeatureNode(
        id: profileFeatureID,
        operation: .sketch(rectangleSketch(widthID: widthID, heightID: heightID, plane: .xy)),
        outputs: [
            FeatureOutput(role: .profile),
            FeatureOutput(role: .curve),
        ]
    )
    let pathFeature = FeatureNode(
        id: pathFeatureID,
        operation: .sketch(curvedArcPathSketch(radius: radius, unit: unit)),
        outputs: [FeatureOutput(role: .curve)]
    )
    let sweepFeature = FeatureNode(
        id: sweepFeatureID,
        operation: .sweep(SweepFeature(
            sections: [.profile(ProfileReference(featureID: profileFeatureID))],
            path: SweepPathReference(featureID: pathFeatureID),
            options: options
        )),
        inputs: [
            FeatureInput(featureID: profileFeatureID, role: .profile),
            FeatureInput(featureID: pathFeatureID, role: .path),
        ],
        outputs: [FeatureOutput(role: sweepOutputRole(for: options.resultKind))]
    )
    let designGraph = DesignGraph(
        nodes: [
            profileFeatureID: profileFeature,
            pathFeatureID: pathFeature,
            sweepFeatureID: sweepFeature,
        ],
        order: [profileFeatureID, pathFeatureID, sweepFeatureID],
        dependencies: [
            DependencyEdge(source: profileFeatureID, target: sweepFeatureID),
            DependencyEdge(source: pathFeatureID, target: sweepFeatureID),
        ],
        revision: DocumentRevision(3)
    )
    return CADDocument(units: documentUnits, parameters: parameters, designGraph: designGraph)
}

private func makeGuidedCurvedPathParallelSweepDocument(
    width: Double = 40.0,
    height: Double = 20.0,
    radius: Double = 10.0,
    unit: LengthUnit = .millimeter,
    documentUnits: UnitSystem = .millimeters
) throws -> CADDocument {
    let widthID = ParameterID()
    let heightID = ParameterID()
    let parameters = ParameterTable(parameters: [
        widthID: Parameter(
            id: widthID,
            name: "width",
            expression: .constant(.length(width, unit: unit)),
            kind: .length
        ),
        heightID: Parameter(
            id: heightID,
            name: "height",
            expression: .constant(.length(height, unit: unit)),
            kind: .length
        )
    ])

    let profileFeatureID = FeatureID()
    let pathFeatureID = FeatureID()
    let guideFeatureID = FeatureID()
    let sweepFeatureID = FeatureID()
    let radiusMeters = unit.toInternal(radius)
    let halfWidthMeters = unit.toInternal(width / 2.0)
    let widthMeters = unit.toInternal(width)
    let guideSketch = try linePathSketch(
        start: Point3D(x: halfWidthMeters, y: radiusMeters, z: 0.0),
        end: Point3D(x: widthMeters, y: 0.0, z: radiusMeters)
    )
    let profileFeature = FeatureNode(
        id: profileFeatureID,
        operation: .sketch(rectangleSketch(widthID: widthID, heightID: heightID, plane: .xy)),
        outputs: [
            FeatureOutput(role: .profile),
            FeatureOutput(role: .curve),
        ]
    )
    let pathFeature = FeatureNode(
        id: pathFeatureID,
        operation: .sketch(curvedArcPathSketch(radius: radius, unit: unit)),
        outputs: [FeatureOutput(role: .curve)]
    )
    let guideFeature = FeatureNode(
        id: guideFeatureID,
        operation: .sketch(guideSketch),
        outputs: [FeatureOutput(role: .curve)]
    )
    let sweepFeature = FeatureNode(
        id: sweepFeatureID,
        operation: .sweep(SweepFeature(
            sections: [.profile(ProfileReference(featureID: profileFeatureID))],
            path: SweepPathReference(featureID: pathFeatureID),
            guides: [SweepGuideReference(featureID: guideFeatureID)],
            options: SweepOptions(alignment: .parallel, guideMethod: .point)
        )),
        inputs: [
            FeatureInput(featureID: profileFeatureID, role: .profile),
            FeatureInput(featureID: pathFeatureID, role: .path),
            FeatureInput(featureID: guideFeatureID, role: .guide),
        ],
        outputs: [FeatureOutput(role: .body)]
    )
    let designGraph = DesignGraph(
        nodes: [
            profileFeatureID: profileFeature,
            pathFeatureID: pathFeature,
            guideFeatureID: guideFeature,
            sweepFeatureID: sweepFeature,
        ],
        order: [profileFeatureID, pathFeatureID, guideFeatureID, sweepFeatureID],
        dependencies: [
            DependencyEdge(source: profileFeatureID, target: sweepFeatureID),
            DependencyEdge(source: pathFeatureID, target: sweepFeatureID),
            DependencyEdge(source: guideFeatureID, target: sweepFeatureID),
        ],
        revision: DocumentRevision(4)
    )
    return CADDocument(units: documentUnits, parameters: parameters, designGraph: designGraph)
}

private func straightLinePathSketch(
    startOffset: Double = 0.0,
    endOffset: Double = 0.0,
    length: Double,
    unit: LengthUnit
) -> Sketch {
    Sketch(
        plane: .yz,
        entities: [
            SketchEntityID(): .line(SketchLine(
                start: SketchPoint(
                    x: .constant(.length(startOffset, unit: unit)),
                    y: .constant(.length(0.0, unit: unit))
                ),
                end: SketchPoint(
                    x: .constant(.length(endOffset, unit: unit)),
                    y: .constant(.length(length, unit: unit))
                )
            ))
        ]
    )
}

private func connectedLinePathSketch(unit: LengthUnit) -> Sketch {
    let firstLineID = SketchEntityID()
    let secondLineID = SketchEntityID()
    return Sketch(
        plane: .yz,
        entities: [
            firstLineID: .line(SketchLine(
                start: SketchPoint(
                    x: .constant(.length(0.0, unit: unit)),
                    y: .constant(.length(0.0, unit: unit))
                ),
                end: SketchPoint(
                    x: .constant(.length(0.0, unit: unit)),
                    y: .constant(.length(15.0, unit: unit))
                )
            )),
            secondLineID: .line(SketchLine(
                start: SketchPoint(
                    x: .constant(.length(0.0, unit: unit)),
                    y: .constant(.length(15.0, unit: unit))
                ),
                end: SketchPoint(
                    x: .constant(.length(8.0, unit: unit)),
                    y: .constant(.length(25.0, unit: unit))
                )
            )),
        ]
    )
}

private func disconnectedLinePathSketch(unit: LengthUnit) -> Sketch {
    let firstLineID = SketchEntityID()
    let secondLineID = SketchEntityID()
    return Sketch(
        plane: .yz,
        entities: [
            firstLineID: .line(SketchLine(
                start: SketchPoint(
                    x: .constant(.length(0.0, unit: unit)),
                    y: .constant(.length(0.0, unit: unit))
                ),
                end: SketchPoint(
                    x: .constant(.length(0.0, unit: unit)),
                    y: .constant(.length(15.0, unit: unit))
                )
            )),
            secondLineID: .line(SketchLine(
                start: SketchPoint(
                    x: .constant(.length(8.0, unit: unit)),
                    y: .constant(.length(15.0, unit: unit))
                ),
                end: SketchPoint(
                    x: .constant(.length(8.0, unit: unit)),
                    y: .constant(.length(25.0, unit: unit))
                )
            )),
        ]
    )
}

private func makeZAxisBridgeCurveFeature(
    pathLength: Double = 10.0,
    unit: LengthUnit = .millimeter,
    sampleCount: Int = 33
) -> BridgeCurveFeature {
    let distance = unit.toInternal(pathLength)
    return BridgeCurveFeature(
        start: BridgeCurveEndpointTarget(
            curve: .line(Line3D(origin: .origin, direction: .unitZ)),
            parameter: 0.0,
            requiredLevel: .tangent
        ),
        end: BridgeCurveEndpointTarget(
            curve: .line(Line3D(
                origin: Point3D(x: 0.0, y: 0.0, z: distance),
                direction: .unitZ
            )),
            parameter: 0.0,
            requiredLevel: .tangent
        ),
        sampleCount: sampleCount
    )
}

private func profilePlaneStraightLinePathSketch(
    length: Double,
    unit: LengthUnit
) -> Sketch {
    Sketch(
        plane: .xy,
        entities: [
            SketchEntityID(): .line(SketchLine(
                start: SketchPoint(
                    x: .constant(.length(0.0, unit: unit)),
                    y: .constant(.length(0.0, unit: unit))
                ),
                end: SketchPoint(
                    x: .constant(.length(length, unit: unit)),
                    y: .constant(.length(0.0, unit: unit))
                )
            ))
        ]
    )
}

private func straightLineXOffsetPathSketch(
    startOffset: Double,
    endOffset: Double,
    length: Double,
    unit: LengthUnit
) -> Sketch {
    Sketch(
        plane: .zx,
        entities: [
            SketchEntityID(): .line(SketchLine(
                start: SketchPoint(
                    x: .constant(.length(0.0, unit: unit)),
                    y: .constant(.length(startOffset, unit: unit))
                ),
                end: SketchPoint(
                    x: .constant(.length(length, unit: unit)),
                    y: .constant(.length(endOffset, unit: unit))
                )
            ))
        ]
    )
}

private func curvedArcPathSketch(radius: Double, unit: LengthUnit) -> Sketch {
    Sketch(
        plane: .yz,
        entities: [
            SketchEntityID(): .arc(SketchArc(
                center: SketchPoint(
                    x: .constant(.length(0.0, unit: unit)),
                    y: .constant(.length(0.0, unit: unit))
                ),
                radius: .constant(.length(radius, unit: unit)),
                startAngle: .constant(.angle(0.0, unit: .degree)),
                endAngle: .constant(.angle(90.0, unit: .degree))
            ))
        ]
    )
}

private func linePathSketch(start: Point3D, end: Point3D) throws -> Sketch {
    let tolerance = ModelingTolerance.standard
    let delta = end - start
    let direction = try delta.normalized(tolerance: tolerance.distance)
    let helper = abs(direction.z) < 0.9 ? Vector3D.unitZ : Vector3D.unitY
    let normal = try direction.cross(helper).normalized(tolerance: tolerance.distance)
    let basis = try sketchPlaneBasis(for: normal, tolerance: tolerance)
    let localEnd = Point2D(
        x: delta.dot(basis.u),
        y: delta.dot(basis.v)
    )
    return Sketch(
        plane: .plane(Plane3D(origin: start, normal: normal)),
        entities: [
            SketchEntityID(): .line(SketchLine(
                start: SketchPoint(
                    x: .constant(.length(0.0, unit: .meter)),
                    y: .constant(.length(0.0, unit: .meter))
                ),
                end: SketchPoint(
                    x: .constant(.length(localEnd.x, unit: .meter)),
                    y: .constant(.length(localEnd.y, unit: .meter))
                )
            ))
        ]
    )
}

private func sketchPlaneBasis(
    for planeNormal: Vector3D,
    tolerance: ModelingTolerance
) throws -> (u: Vector3D, v: Vector3D) {
    let normal = try planeNormal.normalized(tolerance: tolerance.distance)
    let helper = abs(normal.z) < 0.9 ? Vector3D.unitZ : Vector3D.unitY
    let u = try helper.cross(normal).normalized(tolerance: tolerance.distance)
    let v = normal.cross(u)
    return (u, v)
}

private func makeCircleExtrudeDocument(
    radius: Double = 12.0,
    depth: Double = 20.0,
    unit: LengthUnit = .millimeter,
    documentUnits: UnitSystem = .millimeters,
    sketchPlane: SketchPlane = .xy,
    direction: ExtrudeDirection = .normal
) -> CADDocument {
    let radiusID = ParameterID()
    let depthID = ParameterID()
    let parameters = ParameterTable(parameters: [
        radiusID: Parameter(
            id: radiusID,
            name: "radius",
            expression: .constant(.length(radius, unit: unit)),
            kind: .length
        ),
        depthID: Parameter(
            id: depthID,
            name: "depth",
            expression: .constant(.length(depth, unit: unit)),
            kind: .length
        )
    ])

    let sketchFeatureID = FeatureID()
    let extrudeFeatureID = FeatureID()
    let sketch = circleSketch(
        radius: .reference(radiusID),
        unit: unit,
        plane: sketchPlane
    )
    let sketchFeature = FeatureNode(
        id: sketchFeatureID,
        operation: .sketch(sketch),
        outputs: [FeatureOutput(role: .profile)]
    )
    let extrudeFeature = FeatureNode(
        id: extrudeFeatureID,
        operation: .extrude(
            ExtrudeFeature(
                profile: ProfileReference(featureID: sketchFeatureID),
                distance: .reference(depthID),
                direction: direction
            )
        ),
        inputs: [FeatureInput(featureID: sketchFeatureID, role: .profile)],
        outputs: [FeatureOutput(role: .body)]
    )
    let designGraph = DesignGraph(
        nodes: [
            sketchFeatureID: sketchFeature,
            extrudeFeatureID: extrudeFeature
        ],
        order: [sketchFeatureID, extrudeFeatureID],
        dependencies: [DependencyEdge(source: sketchFeatureID, target: extrudeFeatureID)],
        revision: DocumentRevision(2)
    )
    return CADDocument(units: documentUnits, parameters: parameters, designGraph: designGraph)
}

private func circleSketch(
    radius: CADExpression,
    unit: LengthUnit = .millimeter,
    plane: SketchPlane = .xy
) -> Sketch {
    Sketch(
        plane: plane,
        entities: [
            SketchEntityID(): .circle(SketchCircle(
                center: SketchPoint(
                    x: .constant(.length(0.0, unit: unit)),
                    y: .constant(.length(0.0, unit: unit))
                ),
                radius: radius
            ))
        ]
    )
}

private func closedBezierCircleSplineSketch(
    radius: Double,
    unit: LengthUnit,
    plane: SketchPlane = .xy
) -> Sketch {
    let kappa = 0.552_284_749_830_793_6
    func point(_ x: Double, _ y: Double) -> SketchPoint {
        SketchPoint(
            x: .constant(.length(x * radius, unit: unit)),
            y: .constant(.length(y * radius, unit: unit))
        )
    }
    return Sketch(
        plane: plane,
        entities: [
            SketchEntityID(): .spline(SketchSpline(
                controlPoints: [
                    point(1.0, 0.0),
                    point(1.0, kappa),
                    point(kappa, 1.0),
                    point(0.0, 1.0),
                    point(-kappa, 1.0),
                    point(-1.0, kappa),
                    point(-1.0, 0.0),
                    point(-1.0, -kappa),
                    point(-kappa, -1.0),
                    point(0.0, -1.0),
                    point(kappa, -1.0),
                    point(1.0, -kappa),
                    point(1.0, 0.0),
                ],
                isClosed: true
            ))
        ]
    )
}

private func makeClosedSplineExtrudeDocument(
    radius: Double,
    depth: Double,
    unit: LengthUnit,
    documentUnits: UnitSystem
) -> CADDocument {
    let sketchFeatureID = FeatureID()
    let extrudeFeatureID = FeatureID()
    let sketchFeature = FeatureNode(
        id: sketchFeatureID,
        operation: .sketch(closedBezierCircleSplineSketch(radius: radius, unit: unit)),
        outputs: [FeatureOutput(role: .profile)]
    )
    let extrudeFeature = FeatureNode(
        id: extrudeFeatureID,
        operation: .extrude(ExtrudeFeature(
            profile: ProfileReference(featureID: sketchFeatureID),
            distance: .constant(.length(depth, unit: unit))
        )),
        inputs: [FeatureInput(featureID: sketchFeatureID, role: .profile)],
        outputs: [FeatureOutput(role: .body)]
    )
    return CADDocument(
        units: documentUnits,
        designGraph: DesignGraph(
            nodes: [
                sketchFeatureID: sketchFeature,
                extrudeFeatureID: extrudeFeature,
            ],
            order: [sketchFeatureID, extrudeFeatureID],
            dependencies: [DependencyEdge(source: sketchFeatureID, target: extrudeFeatureID)]
        )
    )
}

private func roundedCornerSketch() -> Sketch {
    let bottomID = SketchEntityID()
    let arcID = SketchEntityID()
    let rightID = SketchEntityID()
    let topID = SketchEntityID()
    let leftID = SketchEntityID()

    let bottomLeft = SketchPoint(x: .constant(.length(0.0, unit: .meter)), y: .constant(.length(0.0, unit: .meter)))
    let arcStart = SketchPoint(x: .constant(.length(1.0, unit: .meter)), y: .constant(.length(0.0, unit: .meter)))
    let arcEnd = SketchPoint(x: .constant(.length(2.0, unit: .meter)), y: .constant(.length(1.0, unit: .meter)))
    let topRight = SketchPoint(x: .constant(.length(2.0, unit: .meter)), y: .constant(.length(2.0, unit: .meter)))
    let topLeft = SketchPoint(x: .constant(.length(0.0, unit: .meter)), y: .constant(.length(2.0, unit: .meter)))

    return Sketch(
        plane: .xy,
        entities: [
            bottomID: .line(SketchLine(start: bottomLeft, end: arcStart)),
            arcID: .arc(SketchArc(
                center: SketchPoint(
                    x: .constant(.length(1.0, unit: .meter)),
                    y: .constant(.length(1.0, unit: .meter))
                ),
                radius: .constant(.length(1.0, unit: .meter)),
                startAngle: .constant(.angle(-90.0, unit: .degree)),
                endAngle: .constant(.angle(0.0, unit: .degree))
            )),
            rightID: .line(SketchLine(start: arcEnd, end: topRight)),
            topID: .line(SketchLine(start: topRight, end: topLeft)),
            leftID: .line(SketchLine(start: topLeft, end: bottomLeft)),
        ],
        constraints: [
            .coincident(.lineEnd(bottomID), .arcStart(arcID)),
            .coincident(.arcEnd(arcID), .lineStart(rightID)),
            .coincident(.lineEnd(rightID), .lineStart(topID)),
            .coincident(.lineEnd(topID), .lineStart(leftID)),
            .coincident(.lineEnd(leftID), .lineStart(bottomID)),
        ]
    )
}

private func polygonArea(_ points: [Point3D]) -> Double {
    var twiceArea = 0.0
    for index in points.indices {
        let current = points[index]
        let next = points[(index + 1) % points.count]
        twiceArea += current.x * next.y - next.x * current.y
    }
    return abs(twiceArea / 2.0)
}

private extension Curve3D {
    var isCircle: Bool {
        if case .circle = self {
            return true
        }
        return false
    }
}

private extension Surface3D {
    var isCylinder: Bool {
        if case .cylinder = self {
            return true
        }
        return false
    }
}

private func makeDocumentWithManyIndependentParameters(reverseInsertionOrder: Bool) -> CADDocument {
    let parameterIDs = (0..<32).map { index in
        fixedParameterID(index + 1)
    }
    let pairs = parameterIDs.enumerated().map { index, parameterID in
        return (
            parameterID,
            Parameter(
                id: parameterID,
                name: "p\(index)",
                expression: .constant(.length(Double(index + 1), unit: .millimeter)),
                kind: .length
            )
        )
    }
    let orderedPairs = reverseInsertionOrder ? Array(pairs.reversed()) : pairs
    return CADDocument(
        id: fixedDocumentID(),
        units: .millimeters,
        parameters: ParameterTable(parameters: Dictionary(uniqueKeysWithValues: orderedPairs)),
        designGraph: DesignGraph()
    )
}

private func fixedDocumentID() -> DocumentID {
    DocumentID(UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1)))
}

private func fixedParameterID(_ index: Int) -> ParameterID {
    ParameterID(UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1, UInt8(index))))
}

private func sweepOutputRole(for resultKind: SweepResultKind) -> FeaturePort {
    switch resultKind {
    case .solid:
        .body
    case .sheet:
        .sheet
    }
}

private func rectangleSketch(
    widthID: ParameterID,
    heightID: ParameterID,
    plane: SketchPlane = .xy,
    clockwise: Bool = false
) -> Sketch {
    let two = CADExpression.constant(.scalar(2.0))
    let minusOne = CADExpression.constant(.scalar(-1.0))
    let halfWidth = CADExpression.divide(.reference(widthID), two)
    let halfHeight = CADExpression.divide(.reference(heightID), two)
    let negativeHalfWidth = CADExpression.multiply(minusOne, halfWidth)
    let negativeHalfHeight = CADExpression.multiply(minusOne, halfHeight)
    let bottomLeft = SketchPoint(x: negativeHalfWidth, y: negativeHalfHeight)
    let bottomRight = SketchPoint(x: halfWidth, y: negativeHalfHeight)
    let topRight = SketchPoint(x: halfWidth, y: halfHeight)
    let topLeft = SketchPoint(x: negativeHalfWidth, y: halfHeight)
    let bottomID = SketchEntityID()
    let rightID = SketchEntityID()
    let topID = SketchEntityID()
    let leftID = SketchEntityID()

    let entities: [SketchEntityID: SketchEntity]
    let constraints: [SketchConstraint]
    if clockwise {
        entities = [
            leftID: .line(SketchLine(start: bottomLeft, end: topLeft)),
            topID: .line(SketchLine(start: topLeft, end: topRight)),
            rightID: .line(SketchLine(start: topRight, end: bottomRight)),
            bottomID: .line(SketchLine(start: bottomRight, end: bottomLeft))
        ]
        constraints = [
            .coincident(.lineEnd(leftID), .lineStart(topID)),
            .coincident(.lineEnd(topID), .lineStart(rightID)),
            .coincident(.lineEnd(rightID), .lineStart(bottomID)),
            .coincident(.lineEnd(bottomID), .lineStart(leftID))
        ]
    } else {
        entities = [
            bottomID: .line(SketchLine(start: bottomLeft, end: bottomRight)),
            rightID: .line(SketchLine(start: bottomRight, end: topRight)),
            topID: .line(SketchLine(start: topRight, end: topLeft)),
            leftID: .line(SketchLine(start: topLeft, end: bottomLeft))
        ]
        constraints = [
            .coincident(.lineEnd(bottomID), .lineStart(rightID)),
            .coincident(.lineEnd(rightID), .lineStart(topID)),
            .coincident(.lineEnd(topID), .lineStart(leftID)),
            .coincident(.lineEnd(leftID), .lineStart(bottomID))
        ]
    }
    return Sketch(plane: plane, entities: entities, constraints: constraints, dimensions: [])
}

private func axisAlignedRectangleSketch(radiusID: ParameterID, heightID: ParameterID) -> Sketch {
    let axisBottom = SketchPoint(
        x: .constant(.length(0.0, unit: .meter)),
        y: .constant(.length(0.0, unit: .meter))
    )
    let rimBottom = SketchPoint(
        x: .reference(radiusID),
        y: .constant(.length(0.0, unit: .meter))
    )
    let rimTop = SketchPoint(
        x: .reference(radiusID),
        y: .reference(heightID)
    )
    let axisTop = SketchPoint(
        x: .constant(.length(0.0, unit: .meter)),
        y: .reference(heightID)
    )
    let bottomID = SketchEntityID()
    let outerID = SketchEntityID()
    let topID = SketchEntityID()
    let axisID = SketchEntityID()
    return Sketch(
        plane: .xy,
        entities: [
            bottomID: .line(SketchLine(start: axisBottom, end: rimBottom)),
            outerID: .line(SketchLine(start: rimBottom, end: rimTop)),
            topID: .line(SketchLine(start: rimTop, end: axisTop)),
            axisID: .line(SketchLine(start: axisTop, end: axisBottom)),
        ],
        constraints: [
            .coincident(.lineEnd(bottomID), .lineStart(outerID)),
            .coincident(.lineEnd(outerID), .lineStart(topID)),
            .coincident(.lineEnd(topID), .lineStart(axisID)),
            .coincident(.lineEnd(axisID), .lineStart(bottomID)),
        ],
        dimensions: []
    )
}

private func conicalRevolveSketch() -> Sketch {
    func point(_ x: Double, _ y: Double) -> SketchPoint {
        SketchPoint(
            x: .constant(.length(x, unit: .meter)),
            y: .constant(.length(y, unit: .meter))
        )
    }
    let axisBottom = point(0.0, 0.0)
    let lowerRim = point(0.02, 0.0)
    let upperRim = point(0.01, 0.04)
    let axisTop = point(0.0, 0.04)
    let bottomID = SketchEntityID()
    let slopedID = SketchEntityID()
    let topID = SketchEntityID()
    let axisID = SketchEntityID()
    return Sketch(
        plane: .xy,
        entities: [
            bottomID: .line(SketchLine(start: axisBottom, end: lowerRim)),
            slopedID: .line(SketchLine(start: lowerRim, end: upperRim)),
            topID: .line(SketchLine(start: upperRim, end: axisTop)),
            axisID: .line(SketchLine(start: axisTop, end: axisBottom)),
        ],
        constraints: [
            .coincident(.lineEnd(bottomID), .lineStart(slopedID)),
            .coincident(.lineEnd(slopedID), .lineStart(topID)),
            .coincident(.lineEnd(topID), .lineStart(axisID)),
            .coincident(.lineEnd(axisID), .lineStart(bottomID)),
        ],
        dimensions: []
    )
}

private func crossAxisRevolveSketch() -> Sketch {
    func point(_ x: Double, _ y: Double) -> SketchPoint {
        SketchPoint(
            x: .constant(.length(x, unit: .meter)),
            y: .constant(.length(y, unit: .meter))
        )
    }
    let bottomLeft = point(-0.01, 0.0)
    let bottomRight = point(0.01, 0.0)
    let topRight = point(0.01, 0.02)
    let topLeft = point(-0.01, 0.02)
    let bottomID = SketchEntityID()
    let rightID = SketchEntityID()
    let topID = SketchEntityID()
    let leftID = SketchEntityID()
    return Sketch(
        plane: .xy,
        entities: [
            bottomID: .line(SketchLine(start: bottomLeft, end: bottomRight)),
            rightID: .line(SketchLine(start: bottomRight, end: topRight)),
            topID: .line(SketchLine(start: topRight, end: topLeft)),
            leftID: .line(SketchLine(start: topLeft, end: bottomLeft)),
        ],
        constraints: [
            .coincident(.lineEnd(bottomID), .lineStart(rightID)),
            .coincident(.lineEnd(rightID), .lineStart(topID)),
            .coincident(.lineEnd(topID), .lineStart(leftID)),
            .coincident(.lineEnd(leftID), .lineStart(bottomID)),
        ],
        dimensions: []
    )
}

private func parallelogramSketch(unit: LengthUnit) -> Sketch {
    func point(_ x: Double, _ y: Double) -> SketchPoint {
        SketchPoint(
            x: .constant(.length(x, unit: unit)),
            y: .constant(.length(y, unit: unit))
        )
    }
    let bottomLeft = point(-20.0, -10.0)
    let bottomRight = point(20.0, -10.0)
    let topRight = point(25.0, 10.0)
    let topLeft = point(-15.0, 10.0)
    let bottomID = SketchEntityID()
    let rightID = SketchEntityID()
    let topID = SketchEntityID()
    let leftID = SketchEntityID()
    return Sketch(
        plane: .xy,
        entities: [
            bottomID: .line(SketchLine(start: bottomLeft, end: bottomRight)),
            rightID: .line(SketchLine(start: bottomRight, end: topRight)),
            topID: .line(SketchLine(start: topRight, end: topLeft)),
            leftID: .line(SketchLine(start: topLeft, end: bottomLeft)),
        ],
        constraints: [
            .coincident(.lineEnd(bottomID), .lineStart(rightID)),
            .coincident(.lineEnd(rightID), .lineStart(topID)),
            .coincident(.lineEnd(topID), .lineStart(leftID)),
            .coincident(.lineEnd(leftID), .lineStart(bottomID)),
        ],
        dimensions: []
    )
}

private func meanValueCageRailSourcePoints() -> [Point2D] {
    [
        Point2D(x: -18.0, y: -8.0),
        Point2D(x: 4.0, y: -16.0),
        Point2D(x: 22.0, y: -2.0),
        Point2D(x: 12.0, y: 16.0),
        Point2D(x: -16.0, y: 12.0),
    ]
}

private func meanValueCageRailProfileSketch(unit: LengthUnit) -> Sketch {
    func point(_ point: Point2D) -> SketchPoint {
        SketchPoint(
            x: .constant(.length(point.x, unit: unit)),
            y: .constant(.length(point.y, unit: unit))
        )
    }
    let sourcePoints = meanValueCageRailSourcePoints()
    let entityIDs = sourcePoints.map { _ in SketchEntityID() }
    var entities: [SketchEntityID: SketchEntity] = [:]
    var constraints: [SketchConstraint] = []
    for index in sourcePoints.indices {
        let nextIndex = (index + 1) % sourcePoints.count
        entities[entityIDs[index]] = .line(SketchLine(
            start: point(sourcePoints[index]),
            end: point(sourcePoints[nextIndex])
        ))
        constraints.append(.coincident(
            .lineEnd(entityIDs[index]),
            .lineStart(entityIDs[nextIndex])
        ))
    }
    return Sketch(
        plane: .xy,
        entities: entities,
        constraints: constraints,
        dimensions: []
    )
}

private func radialPointRailSourcePoints() -> [Point2D] {
    [
        Point2D(x: -20.0, y: -10.0),
        Point2D(x: 22.0, y: -10.0),
        Point2D(x: 6.0, y: 0.0),
        Point2D(x: 22.0, y: 12.0),
        Point2D(x: -18.0, y: 12.0),
    ]
}

private func radialPointRailTargetPoints() -> [Point2D] {
    [
        Point2D(x: -24.0, y: -8.0),
        Point2D(x: 26.0, y: -12.0),
        Point2D(x: 10.0, y: 2.0),
        Point2D(x: 18.0, y: 16.0),
        Point2D(x: -20.0, y: 14.0),
    ]
}

private func radialPointRailProfileSketch(unit: LengthUnit) -> Sketch {
    func point(_ point: Point2D) -> SketchPoint {
        SketchPoint(
            x: .constant(.length(point.x, unit: unit)),
            y: .constant(.length(point.y, unit: unit))
        )
    }
    let sourcePoints = radialPointRailSourcePoints()
    let entityIDs = sourcePoints.map { _ in SketchEntityID() }
    var entities: [SketchEntityID: SketchEntity] = [:]
    var constraints: [SketchConstraint] = []
    for index in sourcePoints.indices {
        let nextIndex = (index + 1) % sourcePoints.count
        entities[entityIDs[index]] = .line(SketchLine(
            start: point(sourcePoints[index]),
            end: point(sourcePoints[nextIndex])
        ))
        constraints.append(.coincident(
            .lineEnd(entityIDs[index]),
            .lineStart(entityIDs[nextIndex])
        ))
    }
    return Sketch(
        plane: .xy,
        entities: entities,
        constraints: constraints,
        dimensions: []
    )
}

private func offsetRectangleSketch(
    width: Double,
    height: Double,
    centerX: Double,
    centerY: Double,
    unit: LengthUnit
) -> Sketch {
    let halfWidth = width / 2.0
    let halfHeight = height / 2.0
    let bottomLeft = SketchPoint(
        x: .constant(.length(centerX - halfWidth, unit: unit)),
        y: .constant(.length(centerY - halfHeight, unit: unit))
    )
    let bottomRight = SketchPoint(
        x: .constant(.length(centerX + halfWidth, unit: unit)),
        y: .constant(.length(centerY - halfHeight, unit: unit))
    )
    let topRight = SketchPoint(
        x: .constant(.length(centerX + halfWidth, unit: unit)),
        y: .constant(.length(centerY + halfHeight, unit: unit))
    )
    let topLeft = SketchPoint(
        x: .constant(.length(centerX - halfWidth, unit: unit)),
        y: .constant(.length(centerY + halfHeight, unit: unit))
    )
    let bottomID = SketchEntityID()
    let rightID = SketchEntityID()
    let topID = SketchEntityID()
    let leftID = SketchEntityID()
    return Sketch(
        plane: .xy,
        entities: [
            bottomID: .line(SketchLine(start: bottomLeft, end: bottomRight)),
            rightID: .line(SketchLine(start: bottomRight, end: topRight)),
            topID: .line(SketchLine(start: topRight, end: topLeft)),
            leftID: .line(SketchLine(start: topLeft, end: bottomLeft)),
        ],
        constraints: [
            .coincident(.lineEnd(bottomID), .lineStart(rightID)),
            .coincident(.lineEnd(rightID), .lineStart(topID)),
            .coincident(.lineEnd(topID), .lineStart(leftID)),
            .coincident(.lineEnd(leftID), .lineStart(bottomID)),
        ],
        dimensions: []
    )
}

private func originCornerRectangleSketch(
    width: Double,
    height: Double,
    unit: LengthUnit
) -> Sketch {
    let bottomLeft = SketchPoint(
        x: .constant(.length(0.0, unit: unit)),
        y: .constant(.length(0.0, unit: unit))
    )
    let bottomRight = SketchPoint(
        x: .constant(.length(width, unit: unit)),
        y: .constant(.length(0.0, unit: unit))
    )
    let topRight = SketchPoint(
        x: .constant(.length(width, unit: unit)),
        y: .constant(.length(height, unit: unit))
    )
    let topLeft = SketchPoint(
        x: .constant(.length(0.0, unit: unit)),
        y: .constant(.length(height, unit: unit))
    )
    let bottomID = SketchEntityID()
    let rightID = SketchEntityID()
    let topID = SketchEntityID()
    let leftID = SketchEntityID()
    return Sketch(
        plane: .xy,
        entities: [
            bottomID: .line(SketchLine(start: bottomLeft, end: bottomRight)),
            rightID: .line(SketchLine(start: bottomRight, end: topRight)),
            topID: .line(SketchLine(start: topRight, end: topLeft)),
            leftID: .line(SketchLine(start: topLeft, end: bottomLeft)),
        ],
        constraints: [
            .coincident(.lineEnd(bottomID), .lineStart(rightID)),
            .coincident(.lineEnd(rightID), .lineStart(topID)),
            .coincident(.lineEnd(topID), .lineStart(leftID)),
            .coincident(.lineEnd(leftID), .lineStart(bottomID)),
        ],
        dimensions: []
    )
}

private func firstTriangleNormal(in mesh: Mesh) throws -> Vector3D {
    let first = mesh.positions[Int(mesh.indices[0])]
    let second = mesh.positions[Int(mesh.indices[1])]
    let third = mesh.positions[Int(mesh.indices[2])]
    return try (second - first).cross(third - first).normalized(tolerance: ModelingTolerance.standard.distance)
}

private func normal(
    for persistentName: PersistentName,
    in evaluated: EvaluatedDocument
) throws -> Vector3D {
    guard case .face(let faceID) = try #require(evaluated.generatedNames[persistentName]) else {
        Issue.record("Expected generated face reference.")
        throw FeatureEvaluationError.invalidGraph("Expected generated face reference.")
    }
    let face = try #require(evaluated.brep.faces[faceID])
    let surface = try #require(evaluated.brep.geometry.surfaces[face.surfaceID])
    guard case .plane(let plane) = surface else {
        Issue.record("Expected generated plane face.")
        throw FeatureEvaluationError.invalidGraph("Expected generated plane face.")
    }
    return try plane.normal.normalized(tolerance: ModelingTolerance.standard.distance)
}

private func makeEditableBSplineCurve() -> BSplineCurve3D {
    BSplineCurve3D(
        degree: 2,
        knots: [0.0, 0.0, 0.0, 0.5, 1.0, 1.0, 1.0],
        controlPoints: [
            Point3D(x: 0.0, y: 0.0, z: 0.0),
            Point3D(x: 0.25, y: 0.5, z: 0.0),
            Point3D(x: 0.75, y: 0.5, z: 0.0),
            Point3D(x: 1.0, y: 0.0, z: 0.0),
        ]
    )
}

private func expectBounds(
    _ model: BRepModel,
    minimum: Point3D,
    maximum: Point3D,
    tolerance: Double = 1.0e-12
) throws {
    let points = model.vertices.values.map(\.point)
    let actualMinimum = Point3D(
        x: try #require(points.map(\.x).min()),
        y: try #require(points.map(\.y).min()),
        z: try #require(points.map(\.z).min())
    )
    let actualMaximum = Point3D(
        x: try #require(points.map(\.x).max()),
        y: try #require(points.map(\.y).max()),
        z: try #require(points.map(\.z).max())
    )
    #expect(actualMinimum.isApproximatelyEqual(to: minimum, tolerance: tolerance))
    #expect(actualMaximum.isApproximatelyEqual(to: maximum, tolerance: tolerance))
}

private func generatedFaceID(
    _ role: GeneratedSubshapeRole,
    featureID: FeatureID,
    in evaluated: EvaluatedDocument
) -> FaceID? {
    let name = PersistentName(components: [
        .feature(featureID),
        .generated(role.rawValue)
    ])
    guard case let .face(faceID) = evaluated.generatedNames[name] else {
        return nil
    }
    return faceID
}

private func planeNormal(for faceID: FaceID, in model: BRepModel) throws -> Vector3D {
    let face = try #require(model.faces[faceID])
    let surface = try #require(model.geometry.surfaces[face.surfaceID])
    guard case let .plane(plane) = surface else {
        Issue.record("Expected a planar generated face.")
        return .zero
    }
    return try plane.normal.normalized(tolerance: ModelingTolerance.standard.distance)
}

private func makeConcaveExtrudeDocument() -> CADDocument {
    let sketchFeatureID = FeatureID()
    let extrudeFeatureID = FeatureID()
    let points = [
        SketchPoint(x: .constant(.length(0.0, unit: .meter)), y: .constant(.length(0.0, unit: .meter))),
        SketchPoint(x: .constant(.length(2.0, unit: .meter)), y: .constant(.length(0.0, unit: .meter))),
        SketchPoint(x: .constant(.length(1.0, unit: .meter)), y: .constant(.length(1.0, unit: .meter))),
        SketchPoint(x: .constant(.length(2.0, unit: .meter)), y: .constant(.length(2.0, unit: .meter))),
        SketchPoint(x: .constant(.length(0.0, unit: .meter)), y: .constant(.length(2.0, unit: .meter)))
    ]
    var entities: [SketchEntityID: SketchEntity] = [:]
    for index in points.indices {
        entities[SketchEntityID()] = .line(SketchLine(
            start: points[index],
            end: points[(index + 1) % points.count]
        ))
    }
    let sketch = Sketch(plane: .xy, entities: entities)
    let sketchFeature = FeatureNode(
        id: sketchFeatureID,
        operation: .sketch(sketch),
        outputs: [FeatureOutput(role: .profile)]
    )
    let extrudeFeature = FeatureNode(
        id: extrudeFeatureID,
        operation: .extrude(
            ExtrudeFeature(
                profile: ProfileReference(featureID: sketchFeatureID),
                distance: .constant(.length(1.0, unit: .meter))
            )
        ),
        inputs: [FeatureInput(featureID: sketchFeatureID, role: .profile)],
        outputs: [FeatureOutput(role: .body)]
    )
    return CADDocument(
        units: .meters,
        designGraph: DesignGraph(
            nodes: [
                sketchFeatureID: sketchFeature,
                extrudeFeatureID: extrudeFeature
            ],
            order: [sketchFeatureID, extrudeFeatureID],
            dependencies: [DependencyEdge(source: sketchFeatureID, target: extrudeFeatureID)]
        )
    )
}

private func expectBalancedEdgeOrientations(in model: BRepModel) throws {
    for edgeID in model.edges.keys {
        var forward = 0
        var reversed = 0
        for loop in model.loops.values {
            for orientedEdge in loop.edges where orientedEdge.edgeID == edgeID {
                switch orientedEdge.orientation {
                case .forward:
                    forward += 1
                case .reversed:
                    reversed += 1
                }
            }
        }
        #expect(forward == 1)
        #expect(reversed == 1)
    }
}
