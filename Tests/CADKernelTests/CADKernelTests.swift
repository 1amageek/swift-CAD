import Testing
import Foundation
import CADCore
import CADIR
import CADModeling
import CADTopology
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
        let result = try CurveBridgeSolver(modelingTolerance: .standard).solve(CurveBridgeRequest(
            start: CurveBridgeEndpointConstraint(
                target: CurveContinuityTarget(curve: start, parameter: 0.0),
                requiredLevel: .tangent
            ),
            end: CurveBridgeEndpointConstraint(
                target: CurveContinuityTarget(curve: end, parameter: 0.0),
                requiredLevel: .tangent
            ),
            continuityTolerances: .standard(modelingTolerance: .standard)
        ))

        let startPoint = try result.curve.point(at: 0.0, tolerance: .standard)
        let endPoint = try result.curve.point(at: 1.0, tolerance: .standard)

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
        let result = try CurveBridgeSolver(modelingTolerance: .standard).solve(CurveBridgeRequest(
            start: CurveBridgeEndpointConstraint(
                target: CurveContinuityTarget(curve: start, parameter: 0.0),
                requiredLevel: .curvature
            ),
            end: CurveBridgeEndpointConstraint(
                target: CurveContinuityTarget(curve: end, parameter: 0.0),
                requiredLevel: .curvature
            ),
            continuityTolerances: .standard(modelingTolerance: .standard)
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
            _ = try CurveBridgeSolver(modelingTolerance: .standard).solve(CurveBridgeRequest(
                start: CurveBridgeEndpointConstraint(
                    target: CurveContinuityTarget(curve: start, parameter: 0.0),
                    requiredLevel: .positional
                ),
                end: CurveBridgeEndpointConstraint(
                    target: CurveContinuityTarget(curve: end, parameter: 0.0),
                    requiredLevel: .positional
                ),
                continuityTolerances: .standard(modelingTolerance: .standard)
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
                try baseCurve.point(at: 0.0, tolerance: .standard),
                try baseCurve.point(at: 0.5, tolerance: .standard),
                try baseCurve.point(at: 1.0, tolerance: .standard),
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
                ]
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
        #expect(editedCurve.points.count == 33)
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
        let evaluated = try DocumentEvaluator(tolerance: .standard).evaluate(document)

        #expect(evaluated.brep.bodies.count == 1)
        #expect(evaluated.brep.shells.count == 1)
        #expect(evaluated.brep.faces.count == 6)
        #expect(evaluated.brep.edges.count == 12)
        #expect(evaluated.brep.vertices.count == 8)
        try evaluated.brep.validate(level: .exact, tolerance: .standard)
        #expect(evaluated.caches.brep?.parameterRevision == document.parameters.revision)
        #expect(evaluated.subshapes.entries.values.filter(\.isEdge).count == 12)

        let mesh = try #require(evaluated.meshes.values.first)
        #expect(mesh.indices.count == 36)
        #expect(mesh.positions.count == 24)
        #expect(mesh.normals[0].z < -0.9)
        let firstNormal = try firstTriangleNormal(in: mesh)
        #expect(firstNormal.dot(mesh.normals[0]) > 0.9)

        let evaluatedAgain = try DocumentEvaluator(tolerance: .standard).evaluate(document)
        #expect(evaluatedAgain.meshes.values.first?.indices == mesh.indices)
    }

    @Test(.timeLimit(.minutes(1)))
    func ringRevolveMeshVolumeMatchesAnnulus() throws {
        let document = makeRingRectangleRevolveDocument()
        let evaluated = try DocumentEvaluator(
            tolerance: ModelingTolerance(distance: 1.0e-8, angle: 1.0e-9)
        ).evaluate(document)
        let mesh = try #require(evaluated.meshes.values.first)

        // Inner wall faces must be reversed so the divergence volume of the
        // hollow revolve equals pi * (R^2 - r^2) * h instead of silently
        // inflating by (4/3) * pi * r^2 * h.
        let expected = Double.pi * (0.025 * 0.025 - 0.015 * 0.015) * 0.03
        #expect(abs(abs(signedMeshVolume(mesh)) - expected) <= 1.0e-9)
        try evaluated.brep.validate(tolerance: .standard)
    }

    @Test(.timeLimit(.minutes(1)))
    func ringRevolveTessellatesAtStandardTolerance() throws {
        // Regression: at ModelingTolerance.standard the quarter-annulus cap
        // faces were misclassified as convex (reflex arc turns fall below the
        // absolute distance^2 gate) and fan-triangulated with flipped
        // winding, failing Mesh.validate.
        let document = makeRingRectangleRevolveDocument()
        let evaluated = try DocumentEvaluator(tolerance: .standard).evaluate(document)
        let mesh = try #require(evaluated.meshes.values.first)

        // Walls sample arcs at the angular tolerance; caps are
        // sagitta-simplified to the distance tolerance. Both chord-error
        // budgets stay well inside the 1e-9 band used by the sibling tests.
        let expected = Double.pi * (0.025 * 0.025 - 0.015 * 0.015) * 0.03
        #expect(abs(abs(signedMeshVolume(mesh)) - expected) <= 1.0e-9)
        try mesh.validate(tolerance: .standard)
        try evaluated.brep.validate(tolerance: .standard)
    }

    @Test(.timeLimit(.minutes(1)))
    func notchedRectangleExtrudeMeshVolumeMatchesRectangleMinusHalfDisk() throws {
        let document = makeNotchedRectangleExtrudeDocument()
        let evaluated = try DocumentEvaluator(
            tolerance: ModelingTolerance(distance: 1.0e-8, angle: 1.0e-9)
        ).evaluate(document)
        let mesh = try #require(evaluated.meshes.values.first)

        // The concave notch wall must be reversed so the divergence volume of
        // the notched prism equals (w * h - pi * r^2 / 2) * depth instead of
        // silently drifting by the flipped wall flux.
        let expected = (0.040 * 0.020 - Double.pi * 0.005 * 0.005 / 2.0) * 0.010
        #expect(abs(abs(signedMeshVolume(mesh)) - expected) <= 1.0e-9)
        try evaluated.brep.validate(tolerance: .standard)
    }

    @Test(.timeLimit(.minutes(1)))
    func partialRingRevolveMeshVolumeMatchesHalfAnnulus() throws {
        let document = makeRingRectangleRevolveDocument(
            angle: .constant(.angle(180.0, unit: .degree))
        )
        let evaluated = try DocumentEvaluator(
            tolerance: ModelingTolerance(distance: 1.0e-8, angle: 1.0e-9)
        ).evaluate(document)
        let mesh = try #require(evaluated.meshes.values.first)

        let expected = Double.pi * (0.025 * 0.025 - 0.015 * 0.015) * 0.03 / 2.0
        #expect(abs(abs(signedMeshVolume(mesh)) - expected) <= 1.0e-9)
    }

    @Test(.timeLimit(.minutes(1)))
    func diskRevolveMeshVolumeMatchesCylinder() throws {
        let document = makeAxisAlignedRectangleRevolveDocument()
        let evaluated = try DocumentEvaluator(
            tolerance: ModelingTolerance(distance: 1.0e-8, angle: 1.0e-9)
        ).evaluate(document)
        let mesh = try #require(evaluated.meshes.values.first)

        let expected = Double.pi * 0.02 * 0.02 * 0.04
        #expect(abs(abs(signedMeshVolume(mesh)) - expected) <= 1.0e-9)
    }

    @Test(.timeLimit(.minutes(1)))
    func rectangleRevolveCreatesExactCylindricalBRep() throws {
        let document = makeAxisAlignedRectangleRevolveDocument()
        let evaluated = try DocumentEvaluator(tolerance: .standard).evaluate(document)

        #expect(evaluated.brep.bodies.count == 1)
        #expect(evaluated.brep.shells.count == 1)
        #expect(evaluated.brep.faces.count == 12)
        #expect(evaluated.brep.geometry.surfaces.values.contains { surface in
            if case .cylinder = surface {
                return true
            }
            return false
        })
        try evaluated.brep.validate(level: .exact, tolerance: .standard)
        #expect(evaluated.subshapes.entries.values.filter(\.isEdge).isEmpty == false)

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
        let evaluated = try DocumentEvaluator(tolerance: .standard).evaluate(document)

        #expect(evaluated.brep.bodies.count == 1)
        #expect(evaluated.brep.faces.count == 8)
        let revolveID = try #require(document.designGraph.order.last)
        #expect(evaluated.subshapes[testSubshapeID(revolveID, .startFace)] != nil)
        #expect(evaluated.subshapes[testSubshapeID(revolveID, .endFace)] != nil)
        try evaluated.brep.validate(tolerance: .standard)
    }

    @Test(.timeLimit(.minutes(1)))
    func quarterRectangleRevolvePreservesProfileSideAndCapNormals() throws {
        let document = makeAxisAlignedRectangleRevolveDocument(
            angle: .constant(.angle(90.0, unit: .degree))
        )
        let revolveFeatureID = try #require(document.designGraph.order.last)
        let evaluated = try DocumentEvaluator(tolerance: .standard).evaluate(document)
        let points = evaluated.brep.vertices.values.map(\.point)
        let startFaceNormal = try normal(
            for: testSubshapeID(revolveFeatureID, .startFace),
            in: evaluated
        )
        let endFaceNormal = try normal(
            for: testSubshapeID(revolveFeatureID, .endFace),
            in: evaluated
        )

        #expect(abs((points.map(\.x).max() ?? 0.0) - 0.020) <= 1.0e-12)
        #expect(abs(points.map(\.z).max() ?? 0.0) <= 1.0e-12)
        #expect(abs((points.map(\.z).min() ?? 0.0) + 0.020) <= 1.0e-12)
        #expect(startFaceNormal.dot(.unitZ) > 0.999)
        #expect(endFaceNormal.dot(-Vector3D.unitX) > 0.999)
        try evaluated.brep.validate(tolerance: .standard)
    }

    @Test(.timeLimit(.minutes(1)))
    func revolveRejectsAxisOutsideProfilePlane() throws {
        let document = makeAxisAlignedRectangleRevolveDocument(
            axis: RevolveAxis(origin: .origin, direction: .unitZ),
            angle: .constant(.angle(90.0, unit: .degree))
        )

        do {
            _ = try DocumentEvaluator(tolerance: .standard).evaluate(document)
            Issue.record("Revolve must reject axes outside the profile plane.")
        } catch let error as KernelError where error.code == .unsupportedCapability {
            #expect(error.message.contains("profile plane"))
        } catch {
            Issue.record("Expected unsupportedCapability for axis outside profile plane, got \(error).")
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func revolveRejectsProfilesCrossingAxis() throws {
        let document = makeCrossAxisRevolveDocument()

        do {
            _ = try DocumentEvaluator(tolerance: .standard).evaluate(document)
            Issue.record("Revolve must reject profiles crossing the rotation axis.")
        } catch let error as KernelError where error.code == .unsupportedCapability {
            #expect(error.message.contains("one side"))
        } catch {
            Issue.record("Expected unsupportedCapability for profile crossing axis, got \(error).")
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func revolveBuildsValidatedConicalFrustum() throws {
        let document = makeConicalRevolveDocument()
        let evaluated = try DocumentEvaluator(tolerance: .standard).evaluate(document)
        let repeated = try DocumentEvaluator(tolerance: .standard).evaluate(document)
        let conicalFaces = evaluated.brep.faces.values.filter { face in
            guard case .analytic(.cone) = evaluated.brep.geometry.surfaces[face.surfaceID] else {
                return false
            }
            return true
        }

        #expect(conicalFaces.count == 4)
        #expect(evaluated.brep == repeated.brep)
        #expect(evaluated.lineage == repeated.lineage)
        try evaluated.brep.validate(level: .exact, tolerance: .standard)
        try evaluated.brep.validate(level: .volumetric, tolerance: .standard)
        let expectedVolume = Double.pi * 0.04 * (0.02 * 0.02 + 0.02 * 0.01 + 0.01 * 0.01) / 3.0
        #expect(abs(try evaluated.brep.volume(tolerance: .standard) - expectedVolume) <= 1.0e-12)
    }

    @Test(.timeLimit(.minutes(1)))
    func faceLoopOffsetSplitsRectangularCapFaceWithStableOffsetEdges() throws {
        var document = makeRectangleExtrudeDocument(documentUnits: .meters)
        let extrudeFeatureID = try #require(document.designGraph.order.last)
        let offsetFeatureID = FeatureID()
        let targetFaceName = testSubshapeID(extrudeFeatureID, .startFace)
        let source = try DocumentEvaluator(tolerance: .standard).evaluate(document)
        let offsetFeature = FeatureNode(
            id: offsetFeatureID,
            operation: .faceLoopOffset(
                FaceLoopOffsetFeature(
                    target: FaceLoopOffsetTargetReference(featureID: extrudeFeatureID),
                    face: try stableSubshapeReference(targetFaceName, in: source),
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

        let evaluated = try DocumentEvaluator(tolerance: .standard).evaluate(document)
        let offsetEdgeNames = evaluated.subshapes.entries.filter { subshapeID, reference in
            reference.isEdge &&
                subshapeID.featureID == offsetFeatureID &&
                subshapeID.role == "faceLoopOffset.offsetEdge"
        }
        let centerFaceName = semanticSubshapeID(
            offsetFeatureID,
            generatedRole: "faceLoopOffset",
            semanticRole: "centerFace"
        )

        #expect(evaluated.brep.faces.count == 7)
        #expect(evaluated.brep.edges.count == 16)
        #expect(evaluated.brep.vertices.count == 12)
        #expect(offsetEdgeNames.count == 4)
        #expect(evaluated.subshapes.entries[centerFaceName] != nil)
        #expect(evaluated.subshapes.entries[targetFaceName] != nil)
        try evaluated.brep.validate(tolerance: .standard)

        guard case let .face(centerFaceID) = try #require(evaluated.subshapes.entries[centerFaceName]) else {
            Issue.record("Expected face loop offset center face to be named.")
            return
        }
        let centerFace = try #require(evaluated.brep.faces[centerFaceID])
        let centerLoopID = try #require(centerFace.loops.first)
        let centerLoop = try #require(evaluated.brep.loops[centerLoopID])
        let storedParameterCurve = try #require(centerLoop.edges.first?.surfaceParameterCurve)
        let trim = try SurfaceQueryEvaluator(tolerance: .standard).trimCurve(
            SurfaceTrimReference(
                surface: try stableSurfaceReference(centerFaceName, in: evaluated),
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
    func faceKnifeSplitsPlanarFaceWithStableKnifeTopology() throws {
        var document = makeRectangleExtrudeDocument(documentUnits: .meters)
        let extrudeFeatureID = try #require(document.designGraph.order.last)
        let knifeFeatureID = FeatureID()
        let targetFaceName = testSubshapeID(extrudeFeatureID, .startFace)
        let source = try DocumentEvaluator(tolerance: .standard).evaluate(document)
        let knifeFeature = FeatureNode(
            id: knifeFeatureID,
            operation: .faceKnife(
                FaceKnifeFeature(
                    target: FaceKnifeTargetReference(featureID: extrudeFeatureID),
                    face: try stableSubshapeReference(targetFaceName, in: source),
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

        let evaluated = try DocumentEvaluator(tolerance: .standard).evaluate(document)
        let knifeEdgeNames = evaluated.subshapes.entries.filter { subshapeID, reference in
            reference.isEdge &&
                subshapeID.featureID == knifeFeatureID &&
                subshapeID.role == "faceKnife.knifeEdge"
        }
        let faceKnifeFaceNames = evaluated.subshapes.entries.filter { subshapeID, reference in
            reference.isFace &&
                subshapeID.featureID == knifeFeatureID &&
                subshapeID.role.hasPrefix("faceKnife.")
        }
        let centerFaceName = semanticSubshapeID(
            knifeFeatureID,
            generatedRole: "faceKnife",
            semanticRole: "centerFace"
        )

        #expect(evaluated.brep.faces.count == 7)
        #expect(evaluated.brep.edges.count == 16)
        #expect(evaluated.brep.vertices.count == 12)
        #expect(knifeEdgeNames.count == 4)
        #expect(faceKnifeFaceNames.count == 2)
        #expect(evaluated.subshapes.entries[centerFaceName] != nil)
        #expect(evaluated.subshapes.entries[targetFaceName] == nil)
        try evaluated.brep.validate(tolerance: .standard)

        guard case let .face(centerFaceID) = try #require(evaluated.subshapes.entries[centerFaceName]) else {
            Issue.record("Expected face knife center face to be named.")
            return
        }
        let centerFace = try #require(evaluated.brep.faces[centerFaceID])
        let centerLoopID = try #require(centerFace.loops.first)
        let centerLoop = try #require(evaluated.brep.loops[centerLoopID])
        let storedParameterCurve = try #require(centerLoop.edges.first?.surfaceParameterCurve)
        let trim = try SurfaceQueryEvaluator(tolerance: .standard).trimCurve(
            SurfaceTrimReference(
                surface: try stableSurfaceReference(centerFaceName, in: evaluated),
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
    func faceDeleteRemovesGeneratedSolidFaceAndProducesSheetBody() throws {
        var document = makeRectangleExtrudeDocument(documentUnits: .meters)
        let extrudeFeatureID = try #require(document.designGraph.order.last)
        let deleteFeatureID = FeatureID()
        let targetFaceName = testSubshapeID(extrudeFeatureID, .startFace)
        let source = try DocumentEvaluator(tolerance: .standard).evaluate(document)
        let deleteFeature = FeatureNode(
            id: deleteFeatureID,
            operation: .faceDelete(
                FaceDeleteFeature(
                    target: FaceDeleteTargetReference(featureID: extrudeFeatureID),
                    faces: [try stableSubshapeReference(targetFaceName, in: source)]
                )
            ),
            inputs: [FeatureInput(featureID: extrudeFeatureID, role: .target)],
            outputs: [FeatureOutput(role: .sheet)]
        )
        document.designGraph.nodes[deleteFeatureID] = deleteFeature
        document.designGraph.order.append(deleteFeatureID)
        document.designGraph.dependencies.append(DependencyEdge(source: extrudeFeatureID, target: deleteFeatureID))
        document.designGraph.revision = document.designGraph.revision.advanced()

        let evaluated = try DocumentEvaluator(tolerance: .standard).evaluate(document)
        let body = try #require(evaluated.brep.bodies.values.first)
        let carriedFaceNames = evaluated.subshapes.entries.filter { subshapeID, reference in
            reference.isFace &&
                subshapeID.featureID == deleteFeatureID &&
                subshapeID.role == GeneratedSubshapeRole.face.rawValue
        }
        let carriedEdgeNames = evaluated.subshapes.entries.filter { subshapeID, reference in
            reference.isEdge &&
                subshapeID.featureID == deleteFeatureID &&
                subshapeID.role == GeneratedSubshapeRole.edge.rawValue
        }
        let carriedVertexNames = evaluated.subshapes.entries.filter { subshapeID, reference in
            reference.isVertex &&
                subshapeID.featureID == deleteFeatureID &&
                subshapeID.role == GeneratedSubshapeRole.vertex.rawValue
        }

        #expect(body.kind == .sheet)
        #expect(evaluated.brep.faces.count == 5)
        #expect(evaluated.brep.edges.count == 12)
        #expect(evaluated.brep.vertices.count == 8)
        #expect(evaluated.subshapes.entries[targetFaceName] == nil)
        #expect(carriedFaceNames.count == 5)
        #expect(carriedEdgeNames.count == 12)
        #expect(carriedVertexNames.count == 8)
        try evaluated.brep.validate(tolerance: .standard)

        let mesh = try #require(evaluated.meshes.values.first)
        #expect(mesh.indices.count > 0)
        #expect(mesh.indices.count % 3 == 0)
    }

    @Test(.timeLimit(.minutes(1)))
    func faceDeleteRejectsUnresolvableFaceBeforeMutation() throws {
        let document = makeRectangleExtrudeDocument(documentUnits: .meters)
        let extrudeFeatureID = try #require(document.designGraph.order.last)
        let evaluated = try DocumentEvaluator(tolerance: .standard).evaluate(document)
        let targetFaceName = testSubshapeID(extrudeFeatureID, .startFace)
        let targetReference = try stableSubshapeReference(targetFaceName, in: evaluated)
        let unresolvedReference = StableSubshapeReference(
            subshapeID: SubshapeID(featureID: FeatureID(), role: "face", ordinal: 0),
            geometrySignature: .face(
                kind: .plane,
                boundaryPoints: [Point3D(x: 1_000.0, y: 1_000.0, z: 1_000.0)]
            )
        )
        let deleteFeatureID = FeatureID()
        let deleteFeature = FeatureNode(
            id: deleteFeatureID,
            operation: .faceDelete(
                FaceDeleteFeature(
                    target: FaceDeleteTargetReference(featureID: extrudeFeatureID),
                    faces: [targetReference, unresolvedReference]
                )
            ),
            inputs: [FeatureInput(featureID: extrudeFeatureID, role: .target)],
            outputs: [FeatureOutput(role: .sheet)]
        )
        let context = EvaluationContext(
            parameters: evaluated.parameters,
            brep: evaluated.brep,
            profiles: [:],
            curves: evaluated.curves,
            subshapes: evaluated.subshapes,
            lineage: evaluated.lineage,
            tolerance: .standard
        )

        do {
            _ = try FaceDeleteFeatureEvaluator().evaluate(feature: deleteFeature, context: context)
            Issue.record("Face Delete must reject an unresolvable stable reference.")
        } catch let error as KernelError {
            #expect(error.phase == .evaluation)
            #expect(error.code == .missingReference)
            #expect(error.subshapeID == unresolvedReference.subshapeID)
        } catch {
            Issue.record("Expected a typed KernelError, got \(error).")
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func faceDraftTiltsGeneratedPlanarFaceAndPreservesSolidBody() throws {
        var document = makeRectangleExtrudeDocument(documentUnits: .meters)
        let extrudeFeatureID = try #require(document.designGraph.order.last)
        let draftFeatureID = FeatureID()
        let targetFaceName = testSubshapeID(extrudeFeatureID, .sideFace, ordinal: 0)
        let neutralFaceName = testSubshapeID(extrudeFeatureID, .startFace)
        let source = try DocumentEvaluator(tolerance: .standard).evaluate(document)
        let targetReference = try stableSubshapeReference(targetFaceName, in: source)
        let neutralReference = try stableSubshapeReference(neutralFaceName, in: source)
        let draftFeature = FeatureNode(
            id: draftFeatureID,
            operation: .faceDraft(
                FaceDraftFeature(
                    target: FaceDraftTargetReference(featureID: extrudeFeatureID),
                    faces: [targetReference],
                    neutralFace: neutralReference,
                    angle: .constant(.angle(10.0, unit: .degree))
                )
            ),
            inputs: [FeatureInput(featureID: extrudeFeatureID, role: .target)],
            outputs: [FeatureOutput(role: .body)]
        )
        document.designGraph.nodes[draftFeatureID] = draftFeature
        document.designGraph.order.append(draftFeatureID)
        document.designGraph.dependencies.append(DependencyEdge(source: extrudeFeatureID, target: draftFeatureID))
        document.designGraph.revision = document.designGraph.revision.advanced()

        let evaluated = try DocumentEvaluator(tolerance: .standard).evaluate(document)
        let body = try #require(evaluated.brep.bodies.values.first)
        let targetPlane = try plane(resolving: targetReference, in: evaluated)
        let neutralPlane = try plane(resolving: neutralReference, in: evaluated)
        let carriedFaceNames = evaluated.subshapes.entries.filter { subshapeID, reference in
            reference.isFace &&
                subshapeID.featureID == draftFeatureID &&
                subshapeID.role == GeneratedSubshapeRole.face.rawValue
        }
        let carriedEdgeNames = evaluated.subshapes.entries.filter { subshapeID, reference in
            reference.isEdge &&
                subshapeID.featureID == draftFeatureID &&
                subshapeID.role == GeneratedSubshapeRole.edge.rawValue
        }
        let carriedVertexNames = evaluated.subshapes.entries.filter { subshapeID, reference in
            reference.isVertex &&
                subshapeID.featureID == draftFeatureID &&
                subshapeID.role == GeneratedSubshapeRole.vertex.rawValue
        }
        let draftLineage = evaluated.lineage.values.filter { $0.output.featureID == draftFeatureID }

        #expect(body.kind == .solid)
        #expect(evaluated.brep.faces.count == 6)
        #expect(evaluated.brep.edges.count == 12)
        #expect(evaluated.brep.vertices.count == 8)
        #expect(abs(targetPlane.normal.dot(neutralPlane.normal)) > 0.01)
        #expect(carriedFaceNames.count == 6)
        #expect(carriedEdgeNames.count == 12)
        #expect(carriedVertexNames.count == 8)
        #expect(draftLineage.count == 27)
        #expect(draftLineage.allSatisfy { $0.relation == .preserved && $0.parents.count == 1 })
        #expect(evaluated.subshapes.entries[targetFaceName] == nil)
        try evaluated.brep.validate(level: .volumetric, tolerance: .standard)

        let mesh = try #require(evaluated.meshes.values.first)
        #expect(mesh.indices.count > 0)
        #expect(mesh.indices.count % 3 == 0)
    }

    @Test(.timeLimit(.minutes(1)))
    func faceDraftTiltsMultipleGeneratedPlanarFacesAndPreservesSolidBody() throws {
        var document = makeRectangleExtrudeDocument(documentUnits: .meters)
        let extrudeFeatureID = try #require(document.designGraph.order.last)
        let draftFeatureID = FeatureID()
        let firstTargetFaceName = testSubshapeID(extrudeFeatureID, .sideFace, ordinal: 0)
        let secondTargetFaceName = testSubshapeID(extrudeFeatureID, .sideFace, ordinal: 1)
        let neutralFaceName = testSubshapeID(extrudeFeatureID, .startFace)
        let source = try DocumentEvaluator(tolerance: .standard).evaluate(document)
        let firstTargetReference = try stableSubshapeReference(firstTargetFaceName, in: source)
        let secondTargetReference = try stableSubshapeReference(secondTargetFaceName, in: source)
        let neutralReference = try stableSubshapeReference(neutralFaceName, in: source)
        let draftFeature = FeatureNode(
            id: draftFeatureID,
            operation: .faceDraft(
                FaceDraftFeature(
                    target: FaceDraftTargetReference(featureID: extrudeFeatureID),
                    faces: [
                        firstTargetReference,
                        secondTargetReference,
                    ],
                    neutralFace: neutralReference,
                    angle: .constant(.angle(10.0, unit: .degree))
                )
            ),
            inputs: [FeatureInput(featureID: extrudeFeatureID, role: .target)],
            outputs: [FeatureOutput(role: .body)]
        )
        document.designGraph.nodes[draftFeatureID] = draftFeature
        document.designGraph.order.append(draftFeatureID)
        document.designGraph.dependencies.append(DependencyEdge(source: extrudeFeatureID, target: draftFeatureID))
        document.designGraph.revision = document.designGraph.revision.advanced()

        let evaluated = try DocumentEvaluator(tolerance: .standard).evaluate(document)
        let body = try #require(evaluated.brep.bodies.values.first)
        let firstTargetPlane = try plane(resolving: firstTargetReference, in: evaluated)
        let secondTargetPlane = try plane(resolving: secondTargetReference, in: evaluated)
        let neutralPlane = try plane(resolving: neutralReference, in: evaluated)
        let carriedFaceNames = evaluated.subshapes.entries.filter { subshapeID, reference in
            reference.isFace &&
                subshapeID.featureID == draftFeatureID &&
                subshapeID.role == GeneratedSubshapeRole.face.rawValue
        }
        let carriedEdgeNames = evaluated.subshapes.entries.filter { subshapeID, reference in
            reference.isEdge &&
                subshapeID.featureID == draftFeatureID &&
                subshapeID.role == GeneratedSubshapeRole.edge.rawValue
        }
        let carriedVertexNames = evaluated.subshapes.entries.filter { subshapeID, reference in
            reference.isVertex &&
                subshapeID.featureID == draftFeatureID &&
                subshapeID.role == GeneratedSubshapeRole.vertex.rawValue
        }

        #expect(body.kind == .solid)
        #expect(evaluated.brep.faces.count == 6)
        #expect(evaluated.brep.edges.count == 12)
        #expect(evaluated.brep.vertices.count == 8)
        #expect(abs(firstTargetPlane.normal.dot(neutralPlane.normal)) > 0.01)
        #expect(abs(secondTargetPlane.normal.dot(neutralPlane.normal)) > 0.01)
        #expect(carriedFaceNames.count == 6)
        #expect(carriedEdgeNames.count == 12)
        #expect(carriedVertexNames.count == 8)
        try evaluated.brep.validate(level: .volumetric, tolerance: .standard)

        let mesh = try #require(evaluated.meshes.values.first)
        #expect(mesh.indices.count > 0)
        #expect(mesh.indices.count % 3 == 0)
    }

    @Test(.timeLimit(.minutes(1)))
    func faceDraftRejectsDuplicateGeneratedFaceTargetsBeforeMutation() throws {
        var document = makeRectangleExtrudeDocument(documentUnits: .meters)
        let extrudeFeatureID = try #require(document.designGraph.order.last)
        let draftFeatureID = FeatureID()
        let targetFaceName = testSubshapeID(extrudeFeatureID, .sideFace, ordinal: 0)
        let neutralFaceName = testSubshapeID(extrudeFeatureID, .startFace)
        let source = try DocumentEvaluator(tolerance: .standard).evaluate(document)
        let targetReference = try stableSubshapeReference(targetFaceName, in: source)
        let draftFeature = FeatureNode(
            id: draftFeatureID,
            operation: .faceDraft(
                FaceDraftFeature(
                    target: FaceDraftTargetReference(featureID: extrudeFeatureID),
                    faces: [targetReference, targetReference],
                    neutralFace: try stableSubshapeReference(neutralFaceName, in: source),
                    angle: .constant(.angle(10.0, unit: .degree))
                )
            ),
            inputs: [FeatureInput(featureID: extrudeFeatureID, role: .target)],
            outputs: [FeatureOutput(role: .body)]
        )
        document.designGraph.nodes[draftFeatureID] = draftFeature
        document.designGraph.order.append(draftFeatureID)
        document.designGraph.dependencies.append(DependencyEdge(source: extrudeFeatureID, target: draftFeatureID))
        document.designGraph.revision = document.designGraph.revision.advanced()

        #expect(throws: FeatureEvaluationError.self) {
            _ = try DocumentEvaluator(tolerance: .standard).evaluate(document)
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func faceKnifeSplitsPlanarFaceWithConcaveLoop() throws {
        var document = makeRectangleExtrudeDocument(documentUnits: .meters)
        let extrudeFeatureID = try #require(document.designGraph.order.last)
        let knifeFeatureID = FeatureID()
        let targetFaceName = testSubshapeID(extrudeFeatureID, .startFace)
        let source = try DocumentEvaluator(tolerance: .standard).evaluate(document)
        let knifeFeature = FeatureNode(
            id: knifeFeatureID,
            operation: .faceKnife(
                FaceKnifeFeature(
                    target: FaceKnifeTargetReference(featureID: extrudeFeatureID),
                    face: try stableSubshapeReference(targetFaceName, in: source),
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

        let evaluated = try DocumentEvaluator(tolerance: .standard).evaluate(document)
        let knifeEdgeNames = evaluated.subshapes.entries.filter { subshapeID, reference in
            reference.isEdge &&
                subshapeID.featureID == knifeFeatureID &&
                subshapeID.role == "faceKnife.knifeEdge"
        }
        let faceKnifeFaceNames = evaluated.subshapes.entries.filter { subshapeID, reference in
            reference.isFace &&
                subshapeID.featureID == knifeFeatureID &&
                subshapeID.role.hasPrefix("faceKnife.")
        }
        let centerFaceName = semanticSubshapeID(
            knifeFeatureID,
            generatedRole: "faceKnife",
            semanticRole: "centerFace"
        )

        #expect(evaluated.brep.faces.count == 7)
        #expect(evaluated.brep.edges.count == 17)
        #expect(evaluated.brep.vertices.count == 13)
        #expect(knifeEdgeNames.count == 5)
        #expect(faceKnifeFaceNames.count == 2)
        #expect(evaluated.subshapes.entries[centerFaceName] != nil)
        try evaluated.brep.validate(tolerance: .standard)

        let mesh = try #require(evaluated.meshes.values.first)
        #expect(mesh.indices.count > 36)
        #expect(mesh.indices.count % 3 == 0)
    }

    @Test(.timeLimit(.minutes(1)))
    func faceLoopOffsetSplitsNonRectangularConvexFace() throws {
        var document = makeParallelogramExtrudeDocument(documentUnits: .meters)
        let extrudeFeatureID = try #require(document.designGraph.order.last)
        let offsetFeatureID = FeatureID()
        let targetFaceName = testSubshapeID(extrudeFeatureID, .startFace)
        let source = try DocumentEvaluator(tolerance: .standard).evaluate(document)
        let offsetFeature = FeatureNode(
            id: offsetFeatureID,
            operation: .faceLoopOffset(
                FaceLoopOffsetFeature(
                    target: FaceLoopOffsetTargetReference(featureID: extrudeFeatureID),
                    face: try stableSubshapeReference(targetFaceName, in: source),
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

        let evaluated = try DocumentEvaluator(tolerance: .standard).evaluate(document)
        let offsetEdges = evaluated.subshapes.entries.filter { subshapeID, reference in
            reference.isEdge &&
                subshapeID.featureID == offsetFeatureID &&
                subshapeID.role == "faceLoopOffset.offsetEdge"
        }

        #expect(evaluated.brep.faces.count == 7)
        #expect(evaluated.brep.edges.count == 16)
        #expect(evaluated.brep.vertices.count == 12)
        #expect(offsetEdges.count == 4)
        #expect(abs(try evaluated.brep.volume(tolerance: .standard) - source.brep.volume(tolerance: .standard)) <= 1.0e-12)
        try evaluated.brep.validate(level: .exact, tolerance: .standard)
        try evaluated.brep.validate(level: .volumetric, tolerance: .standard)
    }

    @Test(.timeLimit(.minutes(1)))
    func edgeOffsetSplitsRectangularSupportFaceAndBoundaryEdges() throws {
        var document = makeRectangleExtrudeDocument(documentUnits: .meters)
        let extrudeFeatureID = try #require(document.designGraph.order.last)
        let offsetFeatureID = FeatureID()
        let selectedEdgeName = testSubshapeID(extrudeFeatureID, .edge, ordinal: 0)
        let removedNextEdgeName = testSubshapeID(extrudeFeatureID, .edge, ordinal: 1)
        let removedPreviousEdgeName = testSubshapeID(extrudeFeatureID, .edge, ordinal: 3)
        let supportFaceName = testSubshapeID(extrudeFeatureID, .startFace)
        let source = try DocumentEvaluator(tolerance: .standard).evaluate(document)
        let offsetFeature = FeatureNode(
            id: offsetFeatureID,
            operation: .edgeOffset(
                EdgeOffsetFeature(
                    target: EdgeOffsetTargetReference(featureID: extrudeFeatureID),
                    edge: try stableSubshapeReference(selectedEdgeName, in: source),
                    supportFace: try stableSubshapeReference(supportFaceName, in: source),
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

        let evaluated = try DocumentEvaluator(tolerance: .standard).evaluate(document)
        let offsetEdgeName = semanticSubshapeID(
            offsetFeatureID,
            generatedRole: "edgeOffset",
            semanticRole: "offsetEdge"
        )
        let remainderFaceName = semanticSubshapeID(
            offsetFeatureID,
            generatedRole: "edgeOffset",
            semanticRole: "remainderFace"
        )

        #expect(evaluated.brep.faces.count == 7)
        #expect(evaluated.brep.edges.count == 15)
        #expect(evaluated.brep.vertices.count == 10)
        #expect(evaluated.subshapes.entries[selectedEdgeName]?.isEdge == true)
        #expect(evaluated.subshapes.entries[removedNextEdgeName] == nil)
        #expect(evaluated.subshapes.entries[removedPreviousEdgeName] == nil)
        #expect(evaluated.subshapes.entries[offsetEdgeName]?.isEdge == true)
        #expect(evaluated.subshapes.entries[remainderFaceName]?.isFace == true)
        try evaluated.brep.validate(tolerance: .standard)

        let mesh = try #require(evaluated.meshes.values.first)
        #expect(mesh.indices.count > 36)
        #expect(mesh.indices.count % 3 == 0)
    }

    @Test(.timeLimit(.minutes(1)))
    func symmetricEdgeOffsetSplitsBothAdjacentRectangularSupportFaces() throws {
        var document = makeRectangleExtrudeDocument(documentUnits: .meters)
        let extrudeFeatureID = try #require(document.designGraph.order.last)
        let offsetFeatureID = FeatureID()
        let selectedEdgeName = testSubshapeID(extrudeFeatureID, .edge, ordinal: 0)
        let supportFaceName = testSubshapeID(extrudeFeatureID, .startFace)
        let source = try DocumentEvaluator(tolerance: .standard).evaluate(document)
        let offsetFeature = FeatureNode(
            id: offsetFeatureID,
            operation: .edgeOffset(
                EdgeOffsetFeature(
                    target: EdgeOffsetTargetReference(featureID: extrudeFeatureID),
                    edge: try stableSubshapeReference(selectedEdgeName, in: source),
                    supportFace: try stableSubshapeReference(supportFaceName, in: source),
                    distance: .constant(.length(2.0, unit: .millimeter)),
                    isSymmetric: true
                )
            ),
            inputs: [FeatureInput(featureID: extrudeFeatureID, role: .target)],
            outputs: [FeatureOutput(role: .body)]
        )
        document.designGraph.nodes[offsetFeatureID] = offsetFeature
        document.designGraph.order.append(offsetFeatureID)
        document.designGraph.dependencies.append(DependencyEdge(source: extrudeFeatureID, target: offsetFeatureID))
        document.designGraph.revision = document.designGraph.revision.advanced()

        let evaluated = try DocumentEvaluator(tolerance: .standard).evaluate(document)
        let firstOffsetEdgeName = semanticSubshapeID(
            offsetFeatureID,
            generatedRole: "edgeOffset",
            semanticRole: "offsetEdge",
            ordinal: 0
        )
        let secondOffsetEdgeName = semanticSubshapeID(
            offsetFeatureID,
            generatedRole: "edgeOffset",
            semanticRole: "offsetEdge",
            ordinal: 1
        )
        let firstRemainderFaceName = semanticSubshapeID(
            offsetFeatureID,
            generatedRole: "edgeOffset",
            semanticRole: "remainderFace",
            ordinal: 0
        )
        let secondRemainderFaceName = semanticSubshapeID(
            offsetFeatureID,
            generatedRole: "edgeOffset",
            semanticRole: "remainderFace",
            ordinal: 1
        )

        #expect(evaluated.brep.faces.count == 8)
        #expect(evaluated.brep.edges.count == 18)
        #expect(evaluated.brep.vertices.count == 12)
        #expect(evaluated.subshapes.entries[selectedEdgeName]?.isEdge == true)
        #expect(evaluated.subshapes.entries[firstOffsetEdgeName]?.isEdge == true)
        #expect(evaluated.subshapes.entries[secondOffsetEdgeName]?.isEdge == true)
        #expect(evaluated.subshapes.entries[firstRemainderFaceName]?.isFace == true)
        #expect(evaluated.subshapes.entries[secondRemainderFaceName]?.isFace == true)
        try evaluated.brep.validate(tolerance: .standard)

        let mesh = try #require(evaluated.meshes.values.first)
        #expect(mesh.indices.count > 36)
        #expect(mesh.indices.count % 3 == 0)
    }

    @Test(.timeLimit(.minutes(1)))
    func straightPathSweepCreatesClosedPrismaticBRep() throws {
        let document = makeStraightPathSweepDocument()
        let evaluated = try DocumentEvaluator(tolerance: .standard).evaluate(document)

        #expect(evaluated.brep.bodies.count == 1)
        #expect(evaluated.brep.shells.count == 1)
        #expect(evaluated.brep.faces.count == 6)
        #expect(evaluated.brep.edges.count == 12)
        #expect(evaluated.brep.vertices.count == 8)
        try evaluated.brep.validate(level: .exact, tolerance: .standard)
        #expect(evaluated.subshapes.entries.values.filter(\.isEdge).count == 12)

        let mesh = try #require(evaluated.meshes.values.first)
        #expect(mesh.indices.count == 36)
        #expect(mesh.positions.count == 24)
    }

    @Test(.timeLimit(.minutes(1)))
    func connectedLinePathSweepCreatesExactMultiSpanBRep() throws {
        let document = makeStraightPathSweepDocument(
            width: 2.0,
            height: 1.0,
            pathSketch: connectedLinePathSketch(unit: .millimeter)
        )
        let evaluated = try DocumentEvaluator(tolerance: .standard).evaluate(document)

        #expect(evaluated.brep.bodies.count == 1)
        #expect(evaluated.brep.shells.count == 1)
        #expect(evaluated.brep.vertices.count == 12)
        #expect(evaluated.brep.edges.count == 20)
        #expect(evaluated.brep.faces.count == 10)
        #expect(evaluated.brep.geometry.surfaces.values.filter {
            if case .bSpline = $0 { return true }
            return false
        }.count == 8)
        #expect(evaluated.brep.loops.values.allSatisfy {
            $0.coedges.allSatisfy { $0.surfaceParameterCurve != nil }
        })
        try evaluated.brep.validate(level: .exact, tolerance: .standard)

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
            _ = try DocumentEvaluator(tolerance: .standard).evaluate(document)
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
            operation: .bridgeCurve(makeZAxisBridgeCurveFeature()),
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
        #expect(curve.points.count == 33)

        let exactRepresentation = try #require(curve.exactCurve)
        guard case let .bSpline(exactCurve) = exactRepresentation else {
            Issue.record("Bridge curve feature must preserve the exact B-spline representation.")
            return
        }
        #expect(exactCurve.degree == 3)
        #expect(abs(try exactCurve.point(at: 0.0, tolerance: .standard).z) <= 1.0e-12)
        #expect(abs(try exactCurve.point(at: 1.0, tolerance: .standard).z - 0.01) <= 1.0e-12)
    }

    @Test(.timeLimit(.minutes(1)))
    func bridgeCurveFeatureCanDriveSweepPath() throws {
        let document = makeBridgeCurveSweepDocument()
        let evaluated = try DocumentEvaluator(tolerance: .standard).evaluate(document)

        #expect(evaluated.brep.bodies.count == 1)
        #expect(evaluated.brep.faces.count == 6)
        try evaluated.brep.validate(tolerance: .standard)
        try expectBounds(
            evaluated.brep,
            minimum: Point3D(x: -0.020, y: -0.010, z: 0.0),
            maximum: Point3D(x: 0.020, y: 0.010, z: 0.010)
        )
    }

    @Test(.timeLimit(.minutes(1)))
    func evaluatedDocumentExposesCurveOutputsForSelection() throws {
        let document = makeStraightPathSweepDocument()
        let evaluated = try DocumentEvaluator(tolerance: .standard).evaluate(document)
        let profileFeatureID = try #require(document.designGraph.order.first)
        let pathFeatureID = try #require(document.designGraph.order.dropFirst().first)

        let profileCurves = try #require(evaluated.curves[profileFeatureID])
        let pathCurves = try #require(evaluated.curves[pathFeatureID])
        #expect(profileCurves.count == 4)
        #expect(pathCurves.count == 1)

        let pathReference = CurveOutputReference(featureID: pathFeatureID)
        let midpoint = try CurveQueryEvaluator(tolerance: .standard).midpoint(of: pathReference, in: evaluated)
        #expect(midpoint.isExact)
        #expect(abs((midpoint.tangent?.z ?? 0.0) - 1.0) <= 1.0e-12)
        #expect(abs(midpoint.point.z - 0.005) <= 1.0e-12)
    }

    @Test(.timeLimit(.minutes(1)))
    func edgeQueryEvaluatorResolvesExtrudeEdgeFramesAndProjection() throws {
        let document = makeRectangleExtrudeDocument()
        let evaluated = try DocumentEvaluator(tolerance: .standard).evaluate(document)
        let extrudeFeatureID = try #require(document.designGraph.order.last)
        let edgeName = testSubshapeID(extrudeFeatureID, .edge, ordinal: 0)
        let edgeReference = try stableEdgeReference(edgeName, in: evaluated)
        let evaluator = EdgeQueryEvaluator(tolerance: .standard)

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
        let evaluated = try DocumentEvaluator(tolerance: .standard).evaluate(document)
        let result = try SnapQueryEvaluator(tolerance: .standard).candidates(
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
        let evaluated = try DocumentEvaluator(tolerance: .standard).evaluate(document)
        let result = try SnapQueryEvaluator(tolerance: .standard).candidates(
            near: Point3D(x: -0.020, y: -0.010, z: 0.0),
            in: evaluated,
            options: SnapQueryOptions(maximumDistance: 0.0, maximumCandidateCount: 3)
        )

        let first = try #require(result.candidates.first)
        #expect(first.kind == .vertex)
        #expect(first.distance <= 1.0e-12)
        guard case .subshape = first.selection else {
            Issue.record("Expected vertex snap candidate to carry a stable subshape reference.")
            return
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func snapQueryEvaluatorFiltersCandidatesByFaceIntent() throws {
        let document = makeRectangleExtrudeDocument()
        let evaluated = try DocumentEvaluator(tolerance: .standard).evaluate(document)
        let result = try SnapQueryEvaluator(tolerance: .standard).candidates(
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
        let evaluated = try DocumentEvaluator(tolerance: .standard).evaluate(document)
        let pathFeatureID = try #require(document.designGraph.order.dropFirst().first)
        let result = try SnapQueryEvaluator(tolerance: .standard).candidates(
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
        let evaluated = try DocumentEvaluator(tolerance: .standard).evaluate(document)
        let pathFeatureID = try #require(document.designGraph.order.dropFirst().first)
        let evaluator = SnapQueryEvaluator(tolerance: .standard)

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
        let evaluated = try DocumentEvaluator(tolerance: .standard).evaluate(document)
        let snapEvaluator = SnapQueryEvaluator(tolerance: .standard)
        let measurementEvaluator = SelectionMeasurementEvaluator(tolerance: .standard)

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
    func selectionMeasurementEvaluatorResolvesSketchPointReferences() throws {
        let sketchID = FeatureID()
        let lineID = SketchEntityID()
        let pointID = SketchEntityID()
        let document = CADDocument(
            units: .millimeters,
            designGraph: DesignGraph(
                nodes: [
                    sketchID: FeatureNode(
                        id: sketchID,
                        operation: .sketch(Sketch(
                            plane: .zx,
                            entities: [
                                lineID: .line(SketchLine(
                                    start: SketchPoint(
                                        x: .constant(.length(0.0, unit: .millimeter)),
                                        y: .constant(.length(0.0, unit: .millimeter))
                                    ),
                                    end: SketchPoint(
                                        x: .constant(.length(1.0, unit: .millimeter)),
                                        y: .constant(.length(0.0, unit: .millimeter))
                                    )
                                )),
                                pointID: .point(SketchPoint(
                                    x: .constant(.length(0.5, unit: .millimeter)),
                                    y: .constant(.length(3.0, unit: .millimeter))
                                )),
                            ]
                        )),
                        outputs: [FeatureOutput(role: .curve)]
                    )
                ],
                order: [sketchID]
            )
        )
        let evaluated = try DocumentEvaluator(tolerance: .standard).evaluate(document)
        let reference = SelectionReference.sketchPoint(SketchPointSelectionReference(
            featureID: sketchID,
            entityID: pointID
        ))
        let point = try SelectionMeasurementEvaluator(tolerance: .standard).point(for: reference, in: evaluated)

        #expect(point.selection == reference)
        #expect(point.point.isApproximatelyEqual(
            to: Point3D(x: 0.003, y: 0.0, z: 0.0005),
            tolerance: 1.0e-12
        ))

        let lineReference = SelectionReference.curve(.whole(CurveOutputReference(featureID: sketchID)))
        let lineToPoint = try SelectionMeasurementEvaluator(tolerance: .standard).distance(
            from: lineReference,
            to: reference,
            in: evaluated
        )
        let pointToLine = try SelectionMeasurementEvaluator(tolerance: .standard).distance(
            from: reference,
            to: lineReference,
            in: evaluated
        )

        #expect(abs(lineToPoint.distance - 0.003) <= 1.0e-12)
        #expect(abs(lineToPoint.vector.x - 0.003) <= 1.0e-12)
        #expect(abs(lineToPoint.vector.z) <= 1.0e-12)
        #expect(abs(pointToLine.distance - 0.003) <= 1.0e-12)
        #expect(abs(pointToLine.vector.x + 0.003) <= 1.0e-12)
        #expect(abs(pointToLine.vector.z) <= 1.0e-12)
        #expect(lineToPoint.first.selection == lineReference)
        #expect(lineToPoint.second.selection == reference)
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
        let evaluated = try DocumentEvaluator(tolerance: .standard).evaluate(document)

        let evaluation = try SelectionDimensionEvaluator(tolerance: .standard).evaluate(evaluated)
        let measurement = try #require(evaluation.measurements.first)

        #expect(evaluation.measurements.count == 1)
        #expect(measurement.measured == .length(0.010, unit: .meter))
        #expect(measurement.target == .length(0.010, unit: .meter))
        #expect(abs(measurement.residual.value) <= 1.0e-12)
        #expect(try measurement.isSatisfied(tolerance: .standard))
    }

    @Test(.timeLimit(.minutes(1)))
    func snapQueryEvaluatorRejectsIntentKindMismatch() throws {
        let document = makeRectangleExtrudeDocument()
        let evaluated = try DocumentEvaluator(tolerance: .standard).evaluate(document)
        #expect(throws: FeatureEvaluationError.self) {
            try SnapQueryEvaluator(tolerance: .standard).candidates(
                near: Point3D(x: 0.0, y: -0.012, z: -0.002),
                in: evaluated,
                options: SnapQueryOptions(intent: .face, candidateKinds: [.edge])
            )
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func curveQueryEvaluatorResolvesExactBridgeCurveSubobjects() throws {
        let document = makeBridgeCurveSweepDocument()
        let evaluated = try DocumentEvaluator(tolerance: .standard).evaluate(document)
        let bridgeFeatureID = try #require(document.designGraph.order.dropFirst().first)
        let curveReference = CurveOutputReference(featureID: bridgeFeatureID)
        let evaluator = CurveQueryEvaluator(tolerance: .standard)

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
    func curveQueryEvaluatorResolvesSketchSplineControlPoints() throws {
        let sketchFeatureID = FeatureID()
        let splineID = SketchEntityID()
        let sketch = Sketch(
            plane: .xy,
            entities: [
                splineID: .spline(SketchSpline(controlPoints: [
                    SketchPoint(
                        x: .constant(.length(0.0, unit: .meter)),
                        y: .constant(.length(0.0, unit: .meter))
                    ),
                    SketchPoint(
                        x: .constant(.length(0.002, unit: .meter)),
                        y: .constant(.length(0.004, unit: .meter))
                    ),
                    SketchPoint(
                        x: .constant(.length(0.006, unit: .meter)),
                        y: .constant(.length(0.004, unit: .meter))
                    ),
                    SketchPoint(
                        x: .constant(.length(0.008, unit: .meter)),
                        y: .constant(.length(0.0, unit: .meter))
                    ),
                ]))
            ]
        )
        let document = CADDocument(
            units: .meters,
            designGraph: DesignGraph(
                nodes: [
                    sketchFeatureID: FeatureNode(
                        id: sketchFeatureID,
                        operation: .sketch(sketch),
                        outputs: [FeatureOutput(role: .curve)]
                    )
                ],
                order: [sketchFeatureID]
            )
        )
        let evaluated = try DocumentEvaluator(tolerance: .standard).evaluate(document)
        let controlPoint = try CurveQueryEvaluator(tolerance: .standard).controlPoint(
            CurveControlPointReference(
                curve: CurveOutputReference(featureID: sketchFeatureID),
                controlPointIndex: 2
            ),
            in: evaluated
        )

        #expect(abs(controlPoint.x - 0.006) <= 1.0e-12)
        #expect(abs(controlPoint.y - 0.004) <= 1.0e-12)
        #expect(abs(controlPoint.z) <= 1.0e-12)
    }

    @Test(.timeLimit(.minutes(1)))
    func straightPathSweepHonorsDistanceFractionThroughPathSampler() throws {
        let document = makeStraightPathSweepDocument(options: SweepOptions(
            distanceFraction: .constant(.scalar(0.5))
        ))
        let evaluated = try DocumentEvaluator(tolerance: .standard).evaluate(document)
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
        let evaluated = try DocumentEvaluator(tolerance: .standard).evaluate(setup.document)

        #expect(evaluated.brep.bodies.count == 1)
        #expect(evaluated.brep.shells.count == 1)
        #expect(evaluated.brep.faces.count == 6)
        #expect(evaluated.brep.edges.count == 12)
        #expect(evaluated.brep.vertices.count == 8)
        #expect(evaluated.subshapes.entries.keys.contains {
            $0.featureID == setup.targetFeatureID
        } == false)
        #expect(evaluated.subshapes[testSubshapeID(setup.sweepFeatureID, .body)] != nil)
        try evaluated.brep.validate(tolerance: .standard)
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
        let evaluated = try DocumentEvaluator(tolerance: .standard).evaluate(setup.document)

        #expect(evaluated.brep.bodies.count == 3)
        #expect(evaluated.subshapes.entries.keys.contains {
            $0.featureID == setup.targetFeatureID
        })
        #expect(evaluated.subshapes.entries.keys.contains {
            $0.featureID == setup.sweepFeatureID && $0.role == "body.tool"
        })
        #expect(evaluated.subshapes[testSubshapeID(setup.sweepFeatureID, .body)] != nil)
        try evaluated.brep.validate(tolerance: .standard)
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
        let evaluated = try DocumentEvaluator(tolerance: .standard).evaluate(setup.document)
        #expect(evaluated.subshapes.entries.values.filter(\.isVertex).count == evaluated.brep.vertices.count)
        #expect(evaluated.subshapes.entries.values.filter(\.isEdge).count == evaluated.brep.edges.count)
        #expect(evaluated.subshapes.entries.values.filter(\.isFace).count == evaluated.brep.faces.count)
        #expect(evaluated.subshapes.entries.keys.filter { subshapeID in
            subshapeID.featureID == setup.sweepFeatureID
        }.allSatisfy { subshapeID in
            subshapeID.role.contains("orthogonal:")
                || subshapeID.role == GeneratedSubshapeRole.body.rawValue
        })
        #expect(evaluated.subshapes.entries.keys.contains { subshapeID in
            subshapeID.featureID == setup.sweepFeatureID && subshapeID.ordinal != 0
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
        let evaluated = try DocumentEvaluator(tolerance: .standard).evaluate(setup.document)

        #expect(evaluated.brep.bodies.count == 1)
        #expect(evaluated.brep.shells.count == 1)
        #expect(evaluated.brep.faces.count == 6)
        #expect(evaluated.brep.edges.count == 12)
        #expect(evaluated.brep.vertices.count == 8)
        try evaluated.brep.validate(tolerance: .standard)
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
        let evaluated = try DocumentEvaluator(tolerance: .standard).evaluate(setup.document)
        let body = try #require(evaluated.brep.bodies.values.first)

        #expect(evaluated.brep.bodies.count == 1)
        #expect(body.shellIDs.count == 2)
        #expect(evaluated.brep.shells.count == 2)
        #expect(evaluated.brep.faces.count == 12)
        #expect(evaluated.brep.edges.count == 24)
        #expect(evaluated.brep.vertices.count == 16)
        #expect(evaluated.subshapes.entries.keys.contains {
            $0.featureID == setup.targetFeatureID
        } == false)
        #expect(evaluated.subshapes.entries.values.filter(\.isBody).count == 1)
        #expect(evaluated.subshapes.entries.values.filter(\.isFace).count == evaluated.brep.faces.count)
        #expect(evaluated.subshapes.entries.values.filter(\.isEdge).count == evaluated.brep.edges.count)
        #expect(evaluated.subshapes.entries.values.filter(\.isVertex).count == evaluated.brep.vertices.count)
        try evaluated.brep.validate(tolerance: .standard)
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
        let evaluated = try DocumentEvaluator(tolerance: .standard).evaluate(setup.document)
        let body = try #require(evaluated.brep.bodies.values.first)

        #expect(evaluated.brep.bodies.count == 1)
        #expect(body.shellIDs.count == 1)
        #expect(evaluated.brep.shells.count == 1)
        #expect(evaluated.brep.faces.count == 10)
        #expect(evaluated.brep.loops.count == 12)
        #expect(evaluated.brep.edges.count == 24)
        #expect(evaluated.brep.vertices.count == 16)
        #expect(evaluated.subshapes.entries.keys.contains {
            $0.featureID == setup.targetFeatureID
        } == false)
        #expect(evaluated.subshapes.entries.values.filter(\.isBody).count == 1)
        #expect(evaluated.subshapes.entries.values.filter(\.isFace).count == evaluated.brep.faces.count)
        #expect(evaluated.subshapes.entries.values.filter(\.isEdge).count == evaluated.brep.edges.count)
        #expect(evaluated.subshapes.entries.values.filter(\.isVertex).count == evaluated.brep.vertices.count)
        try evaluated.brep.validate(tolerance: .standard)
        try expectBounds(
            evaluated.brep,
            minimum: Point3D(x: -0.020, y: -0.020, z: 0.0),
            maximum: Point3D(x: 0.020, y: 0.020, z: 0.010)
        )
        let mesh = try #require(evaluated.meshes.values.first)
        #expect(mesh.positions.count >= evaluated.brep.vertices.count)
        #expect(mesh.indices.count == 96)
        try mesh.validate(tolerance: .standard)
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
        let evaluated = try DocumentEvaluator(tolerance: .standard).evaluate(setup.document)
        #expect(evaluated.subshapes.entries.values.filter(\.isVertex).count == evaluated.brep.vertices.count)
        #expect(evaluated.subshapes.entries.values.filter(\.isEdge).count == evaluated.brep.edges.count)
        #expect(evaluated.subshapes.entries.values.filter(\.isFace).count == evaluated.brep.faces.count)
        #expect(evaluated.subshapes.entries.keys.contains { subshapeID in
            subshapeID.featureID == setup.sweepFeatureID
                && subshapeID.role.contains(":face:minimumZ:")
        })
        #expect(evaluated.subshapes.entries.keys.contains { subshapeID in
            subshapeID.featureID == setup.sweepFeatureID && subshapeID.ordinal != 0
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
        let evaluated = try DocumentEvaluator(tolerance: .standard).evaluate(setup.document)
        let body = try #require(evaluated.brep.bodies.values.first)

        #expect(evaluated.brep.bodies.count == 1)
        #expect(body.shellIDs.count == 1)
        #expect(evaluated.brep.faces.count > 6)
        #expect(evaluated.brep.edges.count > 12)
        #expect(evaluated.brep.vertices.count > 8)
        #expect(evaluated.subshapes.entries.keys.contains {
            $0.featureID == setup.targetFeatureID
        } == false)
        #expect(evaluated.subshapes.entries.values.filter(\.isBody).count == 1)
        #expect(evaluated.subshapes.entries.values.filter(\.isFace).count == evaluated.brep.faces.count)
        #expect(evaluated.subshapes.entries.values.filter(\.isEdge).count == evaluated.brep.edges.count)
        #expect(evaluated.subshapes.entries.values.filter(\.isVertex).count == evaluated.brep.vertices.count)
        #expect(evaluated.subshapes.entries.keys.filter { subshapeID in
            subshapeID.featureID == setup.sweepFeatureID
        }.allSatisfy { subshapeID in
            subshapeID.role.contains("orthogonal:")
                || subshapeID.role == GeneratedSubshapeRole.body.rawValue
        })
        #expect(evaluated.subshapes.entries.keys.contains { subshapeID in
            subshapeID.featureID == setup.sweepFeatureID && subshapeID.ordinal != 0
        } == false)
        try evaluated.brep.validate(tolerance: .standard)
        try expectBounds(
            evaluated.brep,
            minimum: Point3D(x: -0.020, y: -0.020, z: 0.0),
            maximum: Point3D(x: 0.020, y: 0.020, z: 0.010)
        )
    }

    @Test(.timeLimit(.minutes(1)))
    func standaloneBooleanCanReusePreviousCellUnionResultAsTarget() throws {
        let setup = makeChainedOrthogonalBooleanDocument()
        let evaluated = try DocumentEvaluator(tolerance: .standard).evaluate(setup.document)
        let body = try #require(evaluated.brep.bodies.values.first)
        let outputLineage = evaluated.lineage.values.filter {
            $0.output.featureID == setup.secondBooleanID
        }

        #expect(evaluated.brep.bodies.count == 1)
        #expect(body.shellIDs.isEmpty == false)
        #expect(evaluated.brep.faces.count > 6)
        #expect(evaluated.subshapes.entries.keys.contains {
            $0.featureID == setup.firstBooleanID
        } == false)
        #expect(evaluated.subshapes[testSubshapeID(setup.secondBooleanID, .body)] != nil)
        #expect(evaluated.subshapes.entries.values.filter(\.isBody).count == 1)
        #expect(evaluated.subshapes.entries.values.filter(\.isFace).count == evaluated.brep.faces.count)
        #expect(evaluated.subshapes.entries.values.filter(\.isEdge).count == evaluated.brep.edges.count)
        #expect(evaluated.subshapes.entries.values.filter(\.isVertex).count == evaluated.brep.vertices.count)
        #expect(outputLineage.contains {
            $0.output.role == "body" && $0.relation == .merged && $0.parents.count == 2
        })
        #expect(outputLineage.contains { $0.relation == .split })
        #expect(outputLineage.allSatisfy { $0.isStructurallyValid })
        #expect(outputLineage.flatMap(\.parents).allSatisfy { evaluated.lineage[$0] != nil })
        try evaluated.brep.validate(tolerance: .standard)
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
        let evaluated = try DocumentEvaluator(tolerance: .standard).evaluate(setup.document)
        let body = try #require(evaluated.brep.bodies.values.first)

        #expect(evaluated.brep.bodies.count == 1)
        #expect(body.shellIDs.count == 3, "Actual shell references: \(body.shellIDs.count)")
        #expect(evaluated.brep.shells.count == 3, "Actual shells: \(evaluated.brep.shells.count)")
        #expect(evaluated.brep.faces.count == 18, "Actual faces: \(evaluated.brep.faces.count)")
        #expect(evaluated.brep.edges.count == 36, "Actual edges: \(evaluated.brep.edges.count)")
        #expect(evaluated.brep.vertices.count == 24, "Actual vertices: \(evaluated.brep.vertices.count)")
        #expect(evaluated.subshapes.entries.keys.contains {
            $0.featureID == setup.targetFeatureID
        } == false)
        #expect(evaluated.subshapes.entries.values.filter(\.isBody).count == 1)
        #expect(evaluated.subshapes.entries.values.filter(\.isFace).count == evaluated.brep.faces.count)
        #expect(evaluated.subshapes.entries.values.filter(\.isEdge).count == evaluated.brep.edges.count)
        #expect(evaluated.subshapes.entries.values.filter(\.isVertex).count == evaluated.brep.vertices.count)
        try evaluated.brep.validate(tolerance: .standard)
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
        let start = try Curve3D.circle(circle).point(at: 0.0, tolerance: .standard)
        let end = try Curve3D.circle(circle).point(
            at: Double.pi / 2.0,
            tolerance: .standard
        )
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
        let arcStart = try Curve3D.circle(circle).point(at: 0.0, tolerance: .standard)
        let arcEnd = try Curve3D.circle(circle).point(
            at: Double.pi / 2.0,
            tolerance: .standard
        )
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
        let splineStart = try spline.point(at: 0.0, tolerance: .standard)
        let splineEnd = try spline.point(at: 1.0, tolerance: .standard)
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
    func curvedParallelPathSweepCreatesExactTranslationalBRep() throws {
        let document = makeCurvedPathSweepDocument(
            radius: 60.0,
            options: SweepOptions(alignment: .parallel)
        )
        let evaluated = try DocumentEvaluator(tolerance: .standard).evaluate(document)
        let repeated = try DocumentEvaluator(tolerance: .standard).evaluate(document)

        #expect(evaluated.brep.bodies.count == 1)
        #expect(evaluated.brep.shells.count == 1)
        #expect(evaluated.brep.vertices.count == 8)
        #expect(evaluated.brep.edges.count == 12)
        #expect(evaluated.brep.faces.count == 6)
        #expect(evaluated.brep.geometry.surfaces.values.filter {
            if case .bSpline = $0 { return true }
            return false
        }.count == 4)
        #expect(evaluated.brep.geometry.surfaces.values.filter {
            if case .plane = $0 { return true }
            return false
        }.count == 2)
        #expect(evaluated.brep.loops.values.allSatisfy {
            $0.coedges.allSatisfy { $0.surfaceParameterCurve != nil }
        })
        #expect(evaluated.brep == repeated.brep)
        #expect(evaluated.lineage == repeated.lineage)
        try evaluated.brep.validate(level: .exact, tolerance: .standard)
        #expect(evaluated.subshapes.entries.values.filter(\.isBody).count == evaluated.brep.bodies.count)
        #expect(evaluated.subshapes.entries.values.filter(\.isFace).count == evaluated.brep.faces.count)
        #expect(evaluated.subshapes.entries.values.filter(\.isEdge).count == evaluated.brep.edges.count)
        #expect(evaluated.subshapes.entries.values.filter(\.isVertex).count == evaluated.brep.vertices.count)

        let mesh = try #require(evaluated.meshes.values.first)
        #expect(mesh.positions.count > 0)
        #expect(mesh.indices.count > 0)
        #expect(mesh.indices.count % 3 == 0)
    }

    @Test(.timeLimit(.minutes(1)))
    func curvedParallelPathSweepPublishesDeterministicSemanticTopology() throws {
        let document = makeCurvedPathSweepDocument(
            radius: 60.0,
            options: SweepOptions(alignment: .parallel)
        )
        let sweepFeatureID = try #require(document.designGraph.order.last)
        let evaluated = try DocumentEvaluator(tolerance: .standard).evaluate(document)
        let startFaceID = SubshapeID(
            featureID: sweepFeatureID,
            role: GeneratedSubshapeRole.startFace.rawValue,
            ordinal: 0
        )
        let endFaceID = SubshapeID(
            featureID: sweepFeatureID,
            role: GeneratedSubshapeRole.endFace.rawValue,
            ordinal: 0
        )
        let sideFaceIDs = (0..<4).map {
            SubshapeID(
                featureID: sweepFeatureID,
                role: GeneratedSubshapeRole.sideFace.rawValue,
                ordinal: $0
            )
        }

        #expect(evaluated.subshapes.entries[startFaceID]?.isFace == true)
        #expect(evaluated.subshapes.entries[endFaceID]?.isFace == true)
        #expect(sideFaceIDs.allSatisfy {
            evaluated.subshapes.entries[$0]?.isFace == true
                && evaluated.lineage[$0]?.relation == .generated
        })
        #expect(evaluated.subshapes.entries.keys.filter {
            $0.featureID == sweepFeatureID
                && $0.role == GeneratedSubshapeRole.edge.rawValue
        }.count == 12)
        #expect(evaluated.subshapes.entries.keys.filter {
            $0.featureID == sweepFeatureID
                && $0.role == GeneratedSubshapeRole.vertex.rawValue
        }.count == 8)
    }

    @Test(.timeLimit(.minutes(1)))
    func narrowRadiusParallelSweepRemainsAnExactTranslation() throws {
        let document = makeCurvedPathSweepDocument(
            radius: 10.0,
            options: SweepOptions(alignment: .parallel)
        )
        let evaluated = try DocumentEvaluator(tolerance: .standard).evaluate(document)

        #expect(evaluated.brep.bodies.count == 1)
        #expect(evaluated.brep.faces.count == 6)
        #expect(evaluated.brep.geometry.surfaces.values.filter {
            if case .bSpline = $0 { return true }
            return false
        }.count == 4)
        try evaluated.brep.validate(level: .exact, tolerance: .standard)
    }

    @Test(.timeLimit(.minutes(1)))
    func circularPathNormalSweepProducesExactRevolvedBRep() throws {
        let document = makeCurvedPathSweepDocument(radius: 60.0)
        let evaluated = try DocumentEvaluator(tolerance: .standard).evaluate(document)
        let repeated = try DocumentEvaluator(tolerance: .standard).evaluate(document)

        #expect(evaluated.brep.bodies.count == 1)
        #expect(evaluated.brep.shells.count == 1)
        #expect(evaluated.brep.faces.count == 6)
        #expect(evaluated.brep.edges.count == 12)
        #expect(evaluated.brep.vertices.count == 8)
        #expect(evaluated.brep.geometry.surfaces.values.filter(\.isCylinder).count == 2)
        #expect(evaluated.brep.geometry.surfaces.values.filter {
            if case .plane = $0 { return true }
            return false
        }.count == 4)
        #expect(evaluated.brep.loops.values.allSatisfy {
            $0.coedges.allSatisfy { $0.surfaceParameterCurve != nil }
        })
        #expect(evaluated.brep == repeated.brep)
        #expect(evaluated.subshapes == repeated.subshapes)
        #expect(evaluated.lineage == repeated.lineage)
        try evaluated.brep.validate(level: .exact, tolerance: .standard)
    }

    @Test(.timeLimit(.minutes(1)))
    func straightPathSweepProducesExactLinearScaleBRep() throws {
        let document = makeStraightPathSweepDocument(
            options: SweepOptions(endScale: .constant(.scalar(0.5)))
        )
        let evaluated = try DocumentEvaluator(tolerance: .standard).evaluate(document)
        let repeated = try DocumentEvaluator(tolerance: .standard).evaluate(document)

        #expect(evaluated.brep.bodies.count == 1)
        #expect(evaluated.brep.faces.count == 6)
        #expect(evaluated.brep.edges.count == 12)
        #expect(evaluated.brep.vertices.count == 8)
        #expect(evaluated.brep.geometry.surfaces.values.filter {
            if case .bSpline = $0 { return true }
            return false
        }.count == 4)
        #expect(evaluated.brep.loops.values.allSatisfy {
            $0.coedges.allSatisfy { $0.surfaceParameterCurve != nil }
        })
        #expect(evaluated.brep == repeated.brep)
        #expect(evaluated.subshapes == repeated.subshapes)
        #expect(evaluated.lineage == repeated.lineage)
        let endVertices = evaluated.brep.vertices.values.map(\.point).filter {
            abs($0.z - 0.010) <= 1.0e-9
        }
        #expect(endVertices.count == 4)
        #expect(abs((endVertices.map(\.x).min() ?? 0.0) + 0.010) <= 1.0e-9)
        #expect(abs((endVertices.map(\.x).max() ?? 0.0) - 0.010) <= 1.0e-9)
        #expect(abs((endVertices.map(\.y).min() ?? 0.0) + 0.005) <= 1.0e-9)
        #expect(abs((endVertices.map(\.y).max() ?? 0.0) - 0.005) <= 1.0e-9)
        try evaluated.brep.validate(level: .exact, tolerance: .standard)
    }

    @Test(.timeLimit(.minutes(1)))
    func straightPathSweepRejectsTwistWithoutExactTransformedSurface() throws {
        let document = makeStraightPathSweepDocument(
            options: SweepOptions(twistAngle: .constant(.angle(90.0, unit: .degree)))
        )

        do {
            _ = try DocumentEvaluator(tolerance: .standard).evaluate(document)
            Issue.record("Twisted sweep must not produce a chordal topology.")
        } catch let error as KernelError {
            #expect(error.phase == .evaluation)
            #expect(error.code == .sweepTwistUnavailable)
            #expect(error.featureID == document.designGraph.order.last)
            #expect(error.tolerance == .standard)
        } catch {
            Issue.record("Expected typed KernelError for twisted sweep, got \(error).")
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func curvedPathSweepRejectsLinearScaleWithTypedDiagnostic() throws {
        let document = makeCurvedPathSweepDocument(
            radius: 60.0,
            options: SweepOptions(
                endScale: .constant(.scalar(0.5)),
                alignment: .parallel
            )
        )

        do {
            _ = try DocumentEvaluator(tolerance: .standard).evaluate(document)
            Issue.record("Curved linear-scale Sweep must not use a sampled fallback.")
        } catch let error as KernelError {
            #expect(error.phase == .evaluation)
            #expect(error.code == .sweepScalePathUnavailable)
            #expect(error.featureID == document.designGraph.order.last)
            #expect(error.tolerance == .standard)
        } catch {
            Issue.record("Expected typed KernelError for curved linear scale, got \(error).")
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func sweepRejectsCollapsingScaleWithTypedDiagnostic() throws {
        let document = makeStraightPathSweepDocument(
            options: SweepOptions(endScale: .constant(.scalar(0.0)))
        )

        do {
            _ = try DocumentEvaluator(tolerance: .standard).evaluate(document)
            Issue.record("Collapsing Sweep scale must not produce degenerate topology.")
        } catch let error as KernelError {
            #expect(error.phase == .validation)
            #expect(error.code == .sweepScaleCollapse)
            #expect(error.tolerance == .standard)
        } catch {
            Issue.record("Expected typed KernelError for collapsing scale, got \(error).")
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func sweepEvaluationAcceptsRoundCornerStyleWhenPathHasNoCornerTransition() throws {
        let document = makeStraightPathSweepDocument(options: SweepOptions(cornerStyle: .round))
        let evaluated = try DocumentEvaluator(tolerance: .standard).evaluate(document)

        #expect(evaluated.brep.bodies.count == 1)
        #expect(evaluated.brep.faces.count == 6)
        #expect(evaluated.brep.edges.count == 12)
        #expect(evaluated.brep.vertices.count == 8)
        try evaluated.brep.validate(tolerance: .standard)
    }

    @Test(.timeLimit(.minutes(1)))
    func sweepEvaluationRejectsUnsupportedOptionSemantics() throws {
        let unsupportedCases: [(options: SweepOptions, code: KernelErrorCode)] = [
            (SweepOptions(simplify: true), .sweepSimplifyUnavailable),
        ]

        for unsupportedCase in unsupportedCases {
            let document = makeStraightPathSweepDocument(options: unsupportedCase.options)
            do {
                _ = try DocumentEvaluator(tolerance: .standard).evaluate(document)
                Issue.record("Sweep evaluator must reject unsupported option semantics.")
            } catch let error as KernelError {
                #expect(error.code == unsupportedCase.code)
                #expect(error.featureID == document.designGraph.order.last)
            } catch {
                Issue.record("Expected typed KernelError for unsupported sweep options, got \(error).")
            }
        }

        do {
            try SweepEvaluationCapabilities().validateStaticOptions(
                SweepOptions(booleanOperation: .union, resultKind: .sheet),
                tolerance: .standard
            )
            Issue.record("Sweep capabilities must reject target booleans with sheet output.")
        } catch let error as KernelError where error.code == .sweepBooleanRequiresSolid {
            #expect(error.message.contains("solid sweep output"))
        } catch {
            Issue.record("Expected sweepBooleanRequiresSolid for boolean sheet output, got \(error).")
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func sweepEvaluationCapabilitiesClassifyGeometryDependentPlans() throws {
        let capabilities = SweepEvaluationCapabilities()
        let exactParallelPlan = try capabilities.supportedPlan(
            SweepOptions(alignment: .parallel),
            geometry: SweepEvaluationCapabilities.Geometry(
                pathShape: .straight(profileNormalComponent: 0.5),
                sectionState: .identity,
                tolerance: .standard
            ),
            tolerance: .standard
        )
        let normalProfilePlaneDecision = try capabilities.decision(
            for: SweepOptions(alignment: .normal),
            geometry: SweepEvaluationCapabilities.Geometry(
                pathShape: .straight(profileNormalComponent: 0.0),
                sectionState: .identity,
                tolerance: .standard
            )
        )
        let curvedParallelDecision = try capabilities.decision(
            for: SweepOptions(alignment: .parallel),
            geometry: SweepEvaluationCapabilities.Geometry(
                pathShape: .curved,
                sectionState: .identity,
                tolerance: .standard
            )
        )
        let circularNormalDecision = try capabilities.decision(
            for: SweepOptions(alignment: .normal),
            geometry: SweepEvaluationCapabilities.Geometry(
                pathShape: .circularArc,
                sectionState: .identity,
                tolerance: .standard
            )
        )
        let curvedParallelGuidedDecision = try capabilities.decision(
            for: SweepOptions(alignment: .parallel),
            geometry: SweepEvaluationCapabilities.Geometry(
                pathShape: .curved,
                sectionState: .guided,
                guideConstraintCount: 5,
                tolerance: .standard
            )
        )
        let obliqueLinearScaleDecision = try capabilities.decision(
            for: SweepOptions(
                endScale: .constant(.scalar(1.5)),
                alignment: .parallel
            ),
            geometry: SweepEvaluationCapabilities.Geometry(
                pathShape: .straight(profileNormalComponent: 0.5),
                sectionState: .linearScale,
                tolerance: .standard
            )
        )
        let sheetDecision = try capabilities.decision(
            for: SweepOptions(resultKind: .sheet),
            geometry: SweepEvaluationCapabilities.Geometry(
                pathShape: .straight(profileNormalComponent: 1.0),
                sectionState: .identity,
                tolerance: .standard
            )
        )
        let booleanDecision = try capabilities.decision(
            for: SweepOptions(booleanOperation: .difference),
            geometry: SweepEvaluationCapabilities.Geometry(
                pathShape: .straight(profileNormalComponent: 1.0),
                sectionState: .identity,
                tolerance: .standard
            )
        )
        let chordGuideDecision = try capabilities.decision(
            for: SweepOptions(guideMethod: .chord),
            geometry: SweepEvaluationCapabilities.Geometry(
                pathShape: .curved,
                sectionState: .guided,
                guideConstraintCount: 2,
                tolerance: .standard
            )
        )
        let exactPointGuideDecision = try capabilities.decision(
            for: SweepOptions(guideMethod: .point),
            geometry: SweepEvaluationCapabilities.Geometry(
                pathShape: .straight(profileNormalComponent: 1.0),
                sectionState: .pointGuide,
                guideConstraintCount: 1,
                tolerance: .standard
            )
        )

        #expect(exactParallelPlan.kind == .exactStraightExtrude)
        #expect(exactParallelPlan.outputTopologyKind == .exactStraightSolid)
        #expect(normalProfilePlaneDecision.unsupportedCase?.code == .sweepPathNormalUnavailable)
        #expect(curvedParallelDecision.supportedPlan?.kind == .exactTranslationalSweep)
        #expect(curvedParallelDecision.supportedPlan?.outputTopologyKind == .exactTranslationalSolid)
        #expect(circularNormalDecision.supportedPlan?.kind == .exactCircularPathRevolve)
        #expect(circularNormalDecision.supportedPlan?.outputTopologyKind == .exactCircularRevolveSolid)
        #expect(curvedParallelGuidedDecision.unsupportedCase?.code == .sweepGuideConstraintUnavailable)
        #expect(obliqueLinearScaleDecision.supportedPlan?.kind == .exactLinearScaleSweep)
        #expect(obliqueLinearScaleDecision.supportedPlan?.outputTopologyKind == .exactLinearScaleSolid)
        #expect(sheetDecision.supportedPlan?.outputTopologyKind == .exactStraightSheet)
        #expect(booleanDecision.supportedPlan?.booleanSupportKind == .targetBoolean)
        #expect(chordGuideDecision.unsupportedCase?.code == .sweepGuideConstraintUnavailable)
        #expect(exactPointGuideDecision.supportedPlan?.kind == .exactPointGuideSweep)
        #expect(exactPointGuideDecision.supportedPlan?.outputTopologyKind == .exactPointGuideSolid)
        #expect(SweepEvaluationCapabilities.currentOptionMatrix.guideMethods == [.point])
        #expect(SweepEvaluationCapabilities.currentOptionMatrix.unsupportedOptionCodes.contains(.sweepBooleanRequiresSolid))
        #expect(SweepEvaluationCapabilities.currentOptionMatrix.unsupportedOptionCodes.contains(.sweepPathNormalUnavailable))
        #expect(SweepEvaluationCapabilities.currentOptionMatrix.unsupportedOptionCodes.contains(.sweepScaleCollapse))
        #expect(SweepEvaluationCapabilities.currentOptionMatrix.unsupportedOptionCodes.contains(.sweepScalePathUnavailable))
        #expect(SweepEvaluationCapabilities.currentOptionMatrix.unsupportedOptionCodes.contains(.sweepTwistUnavailable))
        #expect(SweepEvaluationCapabilities.currentOptionMatrix.unsupportedOptionCodes.contains(.sweepGuideConstraintUnavailable))
    }

    @Test(.timeLimit(.minutes(1)))
    func straightPathSweepSupportsParallelAlignment() throws {
        let document = makeStraightPathSweepDocument(
            options: SweepOptions(alignment: .parallel)
        )
        let evaluated = try DocumentEvaluator(tolerance: .standard).evaluate(document)

        #expect(evaluated.brep.bodies.count == 1)
        #expect(evaluated.brep.vertices.count == 8)
        #expect(evaluated.brep.faces.count == 6)
        try evaluated.brep.validate(tolerance: .standard)
    }

    @Test(.timeLimit(.minutes(1)))
    func straightPathNormalAlignmentRequiresExactMovingFrameSurface() throws {
        let document = makeProfilePlaneStraightPathSweepDocument(
            options: SweepOptions(alignment: .normal)
        )

        do {
            _ = try DocumentEvaluator(tolerance: .standard).evaluate(document)
            Issue.record("Path-normal sweep must not return sampled section topology.")
        } catch let error as KernelError {
            #expect(error.code == .sweepPathNormalUnavailable)
            #expect(error.featureID == document.designGraph.order.last)
        } catch {
            Issue.record("Expected typed KernelError for path-normal sweep, got \(error).")
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func straightPathParallelAlignmentRejectsProfilePlaneDegenerateSolidSweep() throws {
        let document = makeProfilePlaneStraightPathSweepDocument(
            options: SweepOptions(alignment: .parallel)
        )

        do {
            _ = try DocumentEvaluator(tolerance: .standard).evaluate(document)
            Issue.record("Parallel alignment must reject solid sweeps that stay inside the profile plane.")
        } catch let error as KernelError where error.code == .sweepProfilePlaneDegenerate {
            #expect(error.message.contains("nonzero profile-normal component"))
        } catch {
            Issue.record("Expected sweepProfilePlaneDegenerate for profile-plane parallel alignment, got \(error).")
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func obliqueStraightPathParallelAlignmentProducesExactLinearScaleBRep() throws {
        let document = try makeObliqueStraightPathSweepDocument(
            pathEndOffset: 10.0,
            pathLength: 20.0,
            options: SweepOptions(
                endScale: .constant(.scalar(0.5)),
                alignment: .parallel
            )
        )

        let evaluated = try DocumentEvaluator(tolerance: .standard).evaluate(document)

        #expect(evaluated.brep.bodies.count == 1)
        #expect(evaluated.brep.faces.count == 6)
        #expect(evaluated.brep.edges.count == 12)
        #expect(evaluated.brep.vertices.count == 8)
        #expect(evaluated.brep.geometry.surfaces.values.filter {
            if case .bSpline = $0 { return true }
            return false
        }.count == 4)
        let endVertices = evaluated.brep.vertices.values.map(\.point).filter {
            abs($0.z - 0.020) <= 1.0e-9
        }
        #expect(endVertices.count == 4)
        #expect(abs((endVertices.map(\.x).min() ?? 0.0) + 0.010) <= 1.0e-9)
        #expect(abs((endVertices.map(\.x).max() ?? 0.0) - 0.010) <= 1.0e-9)
        #expect(abs((endVertices.map(\.y).min() ?? 0.0) - 0.005) <= 1.0e-9)
        #expect(abs((endVertices.map(\.y).max() ?? 0.0) - 0.015) <= 1.0e-9)
        try evaluated.brep.validate(level: .exact, tolerance: .standard)
    }

    @Test(.timeLimit(.minutes(1)))
    func curvedPathSweepKeepsOffCenterProfileAnchoredToPathStart() throws {
        // The exact straight plan extrudes the drawn profile in place; a
        // 30-degree bend of the same path must not teleport the profile by
        // its sketch-plane offset re-expressed in the moving frame.
        let curvedDocument = makeOffCenterPathSweepDocument(isCurved: true)
        let straightDocument = makeOffCenterPathSweepDocument(isCurved: false)
        let curved = try DocumentEvaluator(tolerance: .standard).evaluate(curvedDocument)
        let straight = try DocumentEvaluator(tolerance: .standard).evaluate(straightDocument)

        // Both plans start on the profile plane (z = 0), so the base ring is
        // every vertex at z = 0. Drawn profile: x in [10, 50] mm, y in
        // [-10, 10] mm.
        let curvedBase = curved.brep.vertices.values.map(\.point).filter {
            abs($0.z) <= 1.0e-9
        }
        let straightBase = straight.brep.vertices.values.map(\.point).filter {
            abs($0.z) <= 1.0e-9
        }
        #expect(curvedBase.count == 4)
        #expect(straightBase.count == 4)
        #expect(abs((curvedBase.map(\.x).min() ?? 0.0) - 0.010) <= 1.0e-9)
        #expect(abs((curvedBase.map(\.x).max() ?? 0.0) - 0.050) <= 1.0e-9)
        #expect(abs((curvedBase.map(\.y).min() ?? 0.0) + 0.010) <= 1.0e-9)
        #expect(abs((curvedBase.map(\.y).max() ?? 0.0) - 0.010) <= 1.0e-9)
        #expect(abs((straightBase.map(\.x).min() ?? 0.0) - 0.010) <= 1.0e-9)
        #expect(abs((straightBase.map(\.x).max() ?? 0.0) - 0.050) <= 1.0e-9)
        try curved.brep.validate(tolerance: .standard)
        try straight.brep.validate(tolerance: .standard)
    }

    @Test(.timeLimit(.minutes(1)))
    func curvedPathParallelAlignmentDescendingPathBuildsOutwardOrientedSolid() throws {
        let document = makeCurvedPathSweepDocument(
            radius: 60.0,
            options: SweepOptions(alignment: .parallel),
            pathSketch: descendingCurvedArcPathSketch(radius: 60.0, unit: .millimeter)
        )
        let evaluated = try DocumentEvaluator(tolerance: .standard).evaluate(document)
        let mesh = try #require(evaluated.meshes.values.first)

        // Parallel alignment translates the 40 x 20 mm section rigidly to each
        // frame origin, so the slab volumes telescope to section area times net
        // normal advance (800 mm^2 x 60 mm) for any frame sampling density. The
        // SIGNED volume is the regression: the descending path used to build
        // every facet and cap inward, which abs(volume) hides.
        let expected = 800.0e-6 * 0.060
        let signedVolume = signedMeshVolume(mesh)
        #expect(signedVolume > 0.0)
        #expect(abs(signedVolume - expected) <= 1.0e-9)
        try evaluated.brep.validate(tolerance: .standard)
    }

    @Test(.timeLimit(.minutes(1)))
    func curvedPathParallelAlignmentRejectsMixedProfileNormalAdvance() throws {
        let document = makeCurvedPathSweepDocument(
            radius: 60.0,
            options: SweepOptions(alignment: .parallel),
            pathSketch: risingAndFallingArcPathSketch(radius: 60.0, unit: .millimeter)
        )

        do {
            _ = try DocumentEvaluator(tolerance: .standard).evaluate(document)
            Issue.record("Parallel alignment must reject a path whose profile-normal advance changes sign.")
        } catch let error as KernelError where error.code == .sweepMixedNormalAdvance {
            #expect(error.message.contains("monotonically"))
        } catch {
            Issue.record("Expected sweepMixedNormalAdvance for mixed profile-normal advance, got \(error).")
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func curvedPathParallelAlignmentKeepsExactSectionDirectionsInvariant() throws {
        let document = makeCurvedPathSweepDocument(
            radius: 60.0,
            options: SweepOptions(alignment: .parallel)
        )
        let sweepFeatureID = try #require(document.designGraph.order.last)
        let evaluated = try DocumentEvaluator(tolerance: .standard).evaluate(document)

        #expect(evaluated.brep.bodies.count == 1)
        for ordinal in 0..<4 {
            let subshapeID = SubshapeID(
                featureID: sweepFeatureID,
                role: GeneratedSubshapeRole.sideFace.rawValue,
                ordinal: ordinal
            )
            guard case let .face(faceID) = try #require(
                evaluated.subshapes.entries[subshapeID]
            ) else {
                Issue.record("Expected exact Sweep side face.")
                continue
            }
            let face = try #require(evaluated.brep.faces[faceID])
            guard case let .bSpline(surface) = try #require(
                evaluated.brep.geometry.surfaces[face.surfaceID]
            ) else {
                Issue.record("Expected rational tensor-product side surface.")
                continue
            }
            #expect(surface.uDegree == 1)
            #expect(surface.vDegree == 2)
            let firstRow = try #require(surface.controlPoints.first)
            let sectionEnd = try #require(firstRow.last)
            let sectionStart = try #require(firstRow.first)
            let sectionDirection = sectionEnd - sectionStart
            for row in surface.controlPoints {
                let rowEnd = try #require(row.last)
                let rowStart = try #require(row.first)
                let rowDirection = rowEnd - rowStart
                #expect((rowDirection - sectionDirection).length <= 1.0e-12)
            }
        }
        try evaluated.brep.validate(level: .exact, tolerance: .standard)
    }

    @Test(.timeLimit(.minutes(1)))
    func curvedPathParallelAlignmentRejectsGuidesWithoutExactGuideSurface() throws {
        let document = try makeGuidedCurvedPathParallelSweepDocument(radius: 60.0)

        do {
            _ = try DocumentEvaluator(tolerance: .standard).evaluate(document)
            Issue.record("Guided Sweep must not return sampled guide deformation.")
        } catch let error as KernelError {
            #expect(error.code == .sweepGuideConstraintUnavailable)
            #expect(error.featureID == document.designGraph.order.last)
        } catch {
            Issue.record("Expected typed KernelError for guided Sweep, got \(error).")
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func straightPathSweepSheetCreatesOpenSheetBodyWithoutCaps() throws {
        let document = makeStraightPathSweepDocument(
            options: SweepOptions(resultKind: .sheet)
        )
        let evaluated = try DocumentEvaluator(tolerance: .standard).evaluate(document)
        let body = try #require(evaluated.brep.bodies.values.first)

        #expect(body.kind == .sheet)
        #expect(evaluated.brep.bodies.count == 1)
        #expect(evaluated.brep.vertices.count == 8)
        #expect(evaluated.brep.edges.count == 12)
        #expect(evaluated.brep.faces.count == 4)
        #expect(evaluated.subshapes.entries.keys.contains {
            $0.role == GeneratedSubshapeRole.startFace.rawValue
        } == false)
        #expect(evaluated.subshapes.entries.keys.contains {
            $0.role == GeneratedSubshapeRole.endFace.rawValue
        } == false)
        #expect(evaluated.meshes.values.first?.positions.isEmpty == false)
        try evaluated.brep.validate(tolerance: .standard)
    }

    @Test(.timeLimit(.minutes(1)))
    func straightPathCircleSweepSheetCreatesExactCylindricalSheetWithoutCaps() throws {
        let document = makeCircleProfileStraightPathSweepDocument(
            options: SweepOptions(resultKind: .sheet)
        )
        let evaluated = try DocumentEvaluator(tolerance: .standard).evaluate(document)
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
        #expect(evaluated.subshapes.entries.keys.contains {
            $0.role == GeneratedSubshapeRole.startFace.rawValue
        } == false)
        #expect(evaluated.subshapes.entries.keys.contains {
            $0.role == GeneratedSubshapeRole.endFace.rawValue
        } == false)
        try evaluated.brep.validate(tolerance: .standard)

        let mesh = try #require(evaluated.meshes.values.first)
        #expect(mesh.positions.count == expectedMeshPositionCount)
        #expect(mesh.indices.count == expectedMeshIndexCount)
    }

    @Test(.timeLimit(.minutes(1)))
    func pointGuidedStraightPathSweepProducesExactLinearSectionBRep() throws {
        let document = makeGuidedStraightPathSweepDocument(
            guideEndOffset: 20.0,
            guideMethod: .point
        )
        let evaluated = try DocumentEvaluator(tolerance: .standard).evaluate(document)
        let repeated = try DocumentEvaluator(tolerance: .standard).evaluate(document)
        let endVertices = evaluated.brep.vertices.values.map(\.point).filter {
            abs($0.z - 0.010) <= 1.0e-9
        }

        #expect(evaluated.brep.bodies.count == 1)
        #expect(evaluated.brep.faces.count == 6)
        #expect(evaluated.brep.edges.count == 12)
        #expect(evaluated.brep.vertices.count == 8)
        #expect(endVertices.count == 4)
        #expect(abs((endVertices.map(\.x).min() ?? 0.0) + 0.040) <= 1.0e-9)
        #expect(abs((endVertices.map(\.x).max() ?? 0.0) - 0.040) <= 1.0e-9)
        #expect(abs((endVertices.map(\.y).min() ?? 0.0) + 0.020) <= 1.0e-9)
        #expect(abs((endVertices.map(\.y).max() ?? 0.0) - 0.020) <= 1.0e-9)
        #expect(evaluated.brep.geometry.surfaces.values.filter {
            if case .bSpline = $0 { return true }
            return false
        }.count == 4)
        #expect(evaluated.brep.loops.values.allSatisfy {
            $0.coedges.allSatisfy { $0.surfaceParameterCurve != nil }
        })
        #expect(evaluated.brep == repeated.brep)
        #expect(evaluated.subshapes == repeated.subshapes)
        #expect(evaluated.lineage == repeated.lineage)
        try evaluated.brep.validate(level: .exact, tolerance: .standard)
    }

    @Test(.timeLimit(.minutes(1)))
    func pointGuidedStraightPathSweepProducesExactRotatingSimilarityBRep() throws {
        let guideSketch = try linePathSketch(
            start: Point3D(x: 0.0, y: 0.010, z: 0.0),
            end: Point3D(x: 0.020, y: 0.0, z: 0.010)
        )
        let document = makeGuidedStraightPathSweepDocument(
            guideMethod: .point,
            guideSketch: guideSketch,
            unit: .meter,
            documentUnits: .meters
        )
        let evaluated = try DocumentEvaluator(tolerance: .standard).evaluate(document)
        let endVertices = evaluated.brep.vertices.values.map(\.point).filter {
            abs($0.z - 0.010) <= 1.0e-9
        }

        #expect(evaluated.brep.faces.count == 6)
        #expect(evaluated.brep.edges.count == 12)
        #expect(evaluated.brep.vertices.count == 8)
        #expect(endVertices.count == 4)
        #expect(abs((endVertices.map(\.x).min() ?? 0.0) + 0.020) <= 1.0e-9)
        #expect(abs((endVertices.map(\.x).max() ?? 0.0) - 0.020) <= 1.0e-9)
        #expect(abs((endVertices.map(\.y).min() ?? 0.0) + 0.040) <= 1.0e-9)
        #expect(abs((endVertices.map(\.y).max() ?? 0.0) - 0.040) <= 1.0e-9)
        #expect(evaluated.brep.geometry.surfaces.values.filter {
            if case .bSpline = $0 { return true }
            return false
        }.count == 4)
        try evaluated.brep.validate(level: .exact, tolerance: .standard)
    }

    @Test(.timeLimit(.minutes(1)))
    func pointGuidedStraightPathSweepRejectsMissingSectionContact() throws {
        let document = makeGuidedStraightPathSweepDocument(
            guideStartOffset: 5.0,
            guideEndOffset: 20.0,
            guideMethod: .point
        )

        do {
            _ = try DocumentEvaluator(tolerance: .standard).evaluate(document)
            Issue.record("Point-guide Sweep must verify its initial section contact.")
        } catch let error as KernelError {
            #expect(error.phase == .geometry)
            #expect(error.code == .sweepGuideContactUnavailable)
            #expect(error.featureID == document.designGraph.order.last)
            #expect(error.tolerance == .standard)
        } catch {
            Issue.record("Expected typed KernelError for a missing guide contact, got \(error).")
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func guidedSweepRejectsNonExactGuideMethodsBeforeTopologyMutation() throws {
        let guideMethods: [SweepGuideMethod] = [.chord, .curve]

        for guideMethod in guideMethods {
            let document = makeGuidedStraightPathSweepDocument(
                guideEndOffset: 20.0,
                guideMethod: guideMethod
            )
            do {
                _ = try DocumentEvaluator(tolerance: .standard).evaluate(document)
                Issue.record("Guided Sweep must not publish sampled guide topology.")
            } catch let error as KernelError {
                #expect(error.phase == .evaluation)
                #expect(error.code == .sweepGuideConstraintUnavailable)
                #expect(error.featureID == document.designGraph.order.last)
                #expect(error.tolerance == .standard)
            } catch {
                Issue.record("Expected typed KernelError for guided Sweep, got \(error).")
            }
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func circleProfileExtrudeCreatesExactCylindricalBRepAndDeterministicMesh() throws {
        let document = makeCircleExtrudeDocument()
        let evaluated = try DocumentEvaluator(tolerance: .standard).evaluate(document)
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
        try evaluated.brep.validate(level: .exact, tolerance: .standard)
        try expectBalancedEdgeOrientations(in: evaluated.brep)
        let bodyID = try #require(evaluated.brep.bodies.keys.first)
        let classifier = DefaultBRepSolidPointClassifier()
        #expect(try classifier.classify(
            Point3D(x: 0.0, y: 0.0, z: 0.010),
            in: bodyID,
            model: evaluated.brep,
            tolerance: .standard
        ) == .inside)
        #expect(try classifier.classify(
            Point3D(x: 0.012, y: 0.0, z: 0.010),
            in: bodyID,
            model: evaluated.brep,
            tolerance: .standard
        ) == .boundary)
        #expect(try classifier.classify(
            Point3D(x: 0.020, y: 0.0, z: 0.010),
            in: bodyID,
            model: evaluated.brep,
            tolerance: .standard
        ) == .outside)

        let mesh = try #require(evaluated.meshes.values.first)
        #expect(mesh.indices.count == expectedMeshIndexCount)
        #expect(mesh.positions.count == expectedMeshPositionCount)

        let evaluatedAgain = try DocumentEvaluator(tolerance: .standard).evaluate(document)
        #expect(evaluatedAgain.meshes.values.first?.indices == mesh.indices)
    }

    @Test(.timeLimit(.minutes(1)))
    func regionalScaleCircleExtrudeCreatesValidExactCylinderMesh() throws {
        let document = makeCircleExtrudeDocument(
            radius: 25.0,
            depth: 2.0,
            unit: .kilometer,
            documentUnits: .meters
        )

        let evaluated = try DocumentEvaluator(tolerance: .standard).evaluate(document)
        let mesh = try #require(evaluated.meshes.values.first)

        #expect(evaluated.brep.bodies.count == 1)
        #expect(evaluated.brep.geometry.surfaces.values.filter(\.isCylinder).count == 4)
        try evaluated.brep.validate(tolerance: .standard)
        try mesh.validate(tolerance: .standard)
    }

    @Test(.timeLimit(.minutes(1)))
    func microScaleCircleExtrudeCreatesValidExactCylinderMesh() throws {
        let document = makeCircleExtrudeDocument(
            radius: 20.0,
            depth: 50.0,
            unit: .micrometer,
            documentUnits: .meters
        )

        let evaluated = try DocumentEvaluator(tolerance: .standard).evaluate(document)
        let mesh = try #require(evaluated.meshes.values.first)

        #expect(evaluated.brep.bodies.count == 1)
        #expect(evaluated.brep.geometry.surfaces.values.filter(\.isCylinder).count == 4)
        try evaluated.brep.validate(tolerance: .standard)
        try mesh.validate(tolerance: .standard)
    }

    @Test(.timeLimit(.minutes(1)))
    func negativeCircleExtrudePreservesExactPcurveOrientation() throws {
        let document = makeCircleExtrudeDocument(
            direction: .vector(-Vector3D.unitZ)
        )
        let evaluated = try DocumentEvaluator(
            tolerance: .standard
        ).evaluate(document)

        #expect(evaluated.brep.faces.count == 6)
        #expect(evaluated.brep.geometry.surfaces.values.filter(\.isCylinder).count == 4)
        #expect(evaluated.brep.loops.values.allSatisfy { loop in
            loop.coedges.allSatisfy { $0.surfaceParameterCurve != nil }
        })
        try evaluated.brep.validate(level: .exact, tolerance: .standard)
        try expectBalancedEdgeOrientations(in: evaluated.brep)
        let bodyID = try #require(evaluated.brep.bodies.keys.first)
        #expect(try DefaultBRepSolidPointClassifier().classify(
            Point3D(x: 0.0, y: 0.0, z: -0.010),
            in: bodyID,
            model: evaluated.brep,
            tolerance: .standard
        ) == .inside)
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
            _ = try SketchProfileExtractor(tolerance: .standard).extractProfiles(
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
    func circleProfileExtractionKeepsExactBoundaryWithBoundedSamples() throws {
        let tolerance = ModelingTolerance(distance: 1.0e-6, angle: 1.0e-9)
        let sketch = circleSketch(
            radius: .constant(.length(0.010, unit: .meter)),
            unit: .meter
        )

        let profiles = try SketchProfileExtractor(tolerance: tolerance).extractProfiles(
            from: sketch,
            sourceFeatureID: FeatureID(),
            parameters: ResolvedParameterTable()
        )
        let profile = try #require(profiles.first)

        #expect(profiles.count == 1)
        #expect(profile.vertices.count > CircularCurveSamplingPolicy.standard.minimumSegmentCount)
        #expect(profile.vertices.count < CircularCurveSamplingPolicy.standard.maximumSegmentCount)
        #expect(profile.boundarySegments.count == 1)
        guard case .circularArc(let arc) = profile.boundarySegments[0] else {
            Issue.record("Expected exact circular profile boundary.")
            return
        }
        #expect(abs(arc.center.x) <= tolerance.distance)
        #expect(abs(arc.center.y) <= tolerance.distance)
        #expect(abs(arc.radius - 0.010) <= tolerance.distance)
        #expect(abs(arc.sweepAngle - Double.pi * 2.0) <= tolerance.angle)
    }

    @Test(.timeLimit(.minutes(1)))
    func circleCurveExtractionKeepsExactCircleWhenSamplingWithinTolerance() throws {
        let tolerance = ModelingTolerance(distance: 1.0e-6, angle: 1.0e-9)
        let sketch = circleSketch(
            radius: .constant(.length(0.010, unit: .meter)),
            unit: .meter
        )

        let curves = try SketchCurveExtractor(tolerance: tolerance).extractCurves(
            from: sketch,
            sourceFeatureID: FeatureID(),
            parameters: ResolvedParameterTable()
        )
        let curve = try #require(curves.first)

        #expect(curves.count == 1)
        #expect(curve.points.count > CircularCurveSamplingPolicy.standard.minimumSegmentCount)
        #expect(curve.points.count < CircularCurveSamplingPolicy.standard.maximumSegmentCount)
        #expect(curve.isClosed)
        guard case .circle(let circle) = curve.exactCurve else {
            Issue.record("Expected exact circle curve.")
            return
        }
        #expect(abs(circle.center.x) <= tolerance.distance)
        #expect(abs(circle.center.y) <= tolerance.distance)
        #expect(abs(circle.radius - 0.010) <= tolerance.distance)
    }

    @Test(.timeLimit(.minutes(1)))
    func circleProfileExtractionAcceptsLargeExactCircleWithBoundedSamples() throws {
        let sketch = circleSketch(
            radius: .constant(.length(1_000.0, unit: .meter)),
            unit: .meter
        )

        let profiles = try SketchProfileExtractor(tolerance: .standard).extractProfiles(
            from: sketch,
            sourceFeatureID: FeatureID(),
            parameters: ResolvedParameterTable()
        )
        let profile = try #require(profiles.first)

        #expect(profiles.count == 1)
        #expect(profile.vertices.count == CircularCurveSamplingPolicy.standard.maximumSegmentCount)
        guard case .circularArc(let arc) = profile.boundarySegments.first else {
            Issue.record("Expected exact circular profile boundary.")
            return
        }
        #expect(abs(arc.radius - 1_000.0) <= ModelingTolerance.standard.distance)
        #expect(abs(arc.sweepAngle - Double.pi * 2.0) <= ModelingTolerance.standard.angle)
    }

    @Test(.timeLimit(.minutes(1)))
    func circleCurveExtractionCapsLargeExactCircleDisplaySamples() throws {
        let sketch = circleSketch(
            radius: .constant(.length(1_000.0, unit: .meter)),
            unit: .meter
        )

        let curves = try SketchCurveExtractor(tolerance: .standard).extractCurves(
            from: sketch,
            sourceFeatureID: FeatureID(),
            parameters: ResolvedParameterTable()
        )
        let curve = try #require(curves.first)

        #expect(curves.count == 1)
        #expect(curve.points.count == CircularCurveSamplingPolicy.standard.maximumSegmentCount + 1)
        #expect(curve.isClosed)
        guard case .circle(let circle) = curve.exactCurve else {
            Issue.record("Expected exact circle curve.")
            return
        }
        #expect(abs(circle.radius - 1_000.0) <= ModelingTolerance.standard.distance)
    }

    @Test(.timeLimit(.minutes(1)))
    func circleProfileExtractionRejectsUnstableTinyPolygonization() {
        let document = makeCircleExtrudeDocument(
            radius: 2.0e-6,
            unit: .meter,
            documentUnits: .meters
        )

        #expect(throws: SketchError.self) {
            _ = try DocumentEvaluator(tolerance: .standard).evaluate(document)
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

        let profiles = try SketchProfileExtractor(tolerance: .standard).extractProfiles(
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
        let evaluated = try DocumentEvaluator(tolerance: .standard).evaluate(document)
        let mesh = try #require(evaluated.meshes.values.first)

        #expect(evaluated.brep.faces.count == 8)
        #expect(mesh.indices.count > 0)
        #expect(mesh.indices.count % 3 == 0)
    }

    @Test(.timeLimit(.minutes(1)))
    func profileExtractionUsesLocalAreaForFarOriginLoops() throws {
        func point(_ x: Double, _ y: Double) -> SketchPoint {
            SketchPoint(
                x: .constant(.length(x, unit: .meter)),
                y: .constant(.length(y, unit: .meter))
            )
        }

        let origin = 1.0e12
        let sketch = Sketch(
            plane: .xy,
            entities: [
                SketchEntityID(): .line(SketchLine(start: point(origin, origin), end: point(origin + 10.0, origin))),
                SketchEntityID(): .line(SketchLine(start: point(origin + 10.0, origin), end: point(origin + 10.0, origin + 10.0))),
                SketchEntityID(): .line(SketchLine(start: point(origin + 10.0, origin + 10.0), end: point(origin, origin + 10.0))),
                SketchEntityID(): .line(SketchLine(start: point(origin, origin + 10.0), end: point(origin, origin))),
            ]
        )

        let profiles = try SketchProfileExtractor(
            tolerance: ModelingTolerance(distance: 1.0e-4, angle: ModelingTolerance.standard.angle)
        ).extractProfiles(
            from: sketch,
            sourceFeatureID: FeatureID(),
            parameters: ResolvedParameterTable()
        )
        let profile = try #require(profiles.first)

        #expect(profiles.count == 1)
        #expect(profile.vertices.count == 4)
        let xValues = profile.vertices.map(\.x)
        let yValues = profile.vertices.map(\.y)
        let maxX = try #require(xValues.max())
        let minX = try #require(xValues.min())
        let maxY = try #require(yValues.max())
        let minY = try #require(yValues.min())
        let width = maxX - minX
        let height = maxY - minY
        #expect(abs(width - 10.0) < 1.0e-6)
        #expect(abs(height - 10.0) < 1.0e-6)
    }

    @Test(.timeLimit(.minutes(1)))
    func profileExtractionAllowsSubMicronRectangleWithMicroTolerance() throws {
        func point(_ x: Double, _ y: Double) -> SketchPoint {
            SketchPoint(
                x: .constant(.length(x, unit: .meter)),
                y: .constant(.length(y, unit: .meter))
            )
        }

        let side = 5.0e-7
        let sketch = Sketch(
            plane: .xy,
            entities: [
                SketchEntityID(): .line(SketchLine(start: point(0.0, 0.0), end: point(side, 0.0))),
                SketchEntityID(): .line(SketchLine(start: point(side, 0.0), end: point(side, side))),
                SketchEntityID(): .line(SketchLine(start: point(side, side), end: point(0.0, side))),
                SketchEntityID(): .line(SketchLine(start: point(0.0, side), end: point(0.0, 0.0))),
            ]
        )

        let profiles = try SketchProfileExtractor(
            tolerance: ModelingTolerance(distance: 1.0e-8, angle: ModelingTolerance.standard.angle)
        ).extractProfiles(
            from: sketch,
            sourceFeatureID: FeatureID(),
            parameters: ResolvedParameterTable()
        )
        let profile = try #require(profiles.first)

        #expect(profiles.count == 1)
        #expect(profile.vertices.count == 4)
        #expect(abs(polygonArea(profile.vertices) - side * side) < 1.0e-18)
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

        let profiles = try SketchProfileExtractor(tolerance: .standard).extractProfiles(
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

        let summary = try ProfileRegionAnalyzer(tolerance: .standard).summary(for: profile)

        #expect(abs(summary.center.x - 0.005) < 1.0e-12)
        #expect(abs(summary.center.y - 0.003) < 1.0e-12)
        #expect(abs(summary.areaSquareMeters - 0.000_060) < 1.0e-12)
        #expect(summary.points.count == 4)
    }

    @Test(.timeLimit(.minutes(1)))
    func profileRegionAnalyzerSummarizesFarFromOriginProfile() throws {
        // A 10 m x 10 m profile at site-planning coordinates (~1e12). A raw shoelace
        // on absolute coordinates collapses the area to noise there (or throws
        // degenerateProfile); the origin-rebased moments keep the area exact and the
        // centroid at the true location.
        let base = 1.0e12
        let profile = Profile(
            sourceFeatureID: FeatureID(),
            plane: .xy,
            vertices: [
                Point3D(x: base, y: base, z: 0.0),
                Point3D(x: base + 10.0, y: base, z: 0.0),
                Point3D(x: base + 10.0, y: base + 10.0, z: 0.0),
                Point3D(x: base, y: base + 10.0, z: 0.0),
            ]
        )

        let summary = try ProfileRegionAnalyzer(tolerance: .standard).summary(for: profile)

        #expect(abs(summary.areaSquareMeters - 100.0) < 1.0e-3)
        #expect(abs(summary.center.x - (base + 5.0)) < 1.0e-3)
        #expect(abs(summary.center.y - (base + 5.0)) < 1.0e-3)
        #expect(summary.points.count == 4)
    }

    @Test(.timeLimit(.minutes(1)))
    func profileRegionAnalyzerUsesExactCircularBoundary() throws {
        let sketch = circleSketch(radius: .constant(.length(1.0, unit: .meter)), unit: .meter)
        let profiles = try SketchProfileExtractor(tolerance: .standard).extractProfiles(
            from: sketch,
            sourceFeatureID: FeatureID(),
            parameters: ResolvedParameterTable()
        )
        let profile = try #require(profiles.first)

        let summary = try ProfileRegionAnalyzer(tolerance: .standard).summary(for: profile)

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
            _ = try SketchProfileExtractor(tolerance: .standard).extractProfiles(
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
    func profileExtractionRejectsAdjacentOverlappingLoopSegments() throws {
        let sketch = lineLoopSketch([
            Point2D(x: 0.0, y: 0.0),
            Point2D(x: 2.0, y: 0.0),
            Point2D(x: 1.0, y: 0.0),
            Point2D(x: 1.0, y: 1.0),
        ])

        do {
            _ = try SketchProfileExtractor(tolerance: .standard).extractProfiles(
                from: sketch,
                sourceFeatureID: FeatureID(),
                parameters: ResolvedParameterTable()
            )
            Issue.record("Adjacent overlapping profile segments must be rejected.")
        } catch SketchError.unsupportedProfile(let message) {
            #expect(message.contains("Self-intersecting profiles"))
        } catch {
            Issue.record("Expected unsupportedProfile for overlapping adjacent segments, got \(error).")
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func profileExtractionRejectsIntersectingClosedLoops() throws {
        let sketch = lineLoopSketches([
            [
                Point2D(x: 0.0, y: 0.0),
                Point2D(x: 3.0, y: 0.0),
                Point2D(x: 3.0, y: 1.0),
                Point2D(x: 0.0, y: 1.0),
            ],
            [
                Point2D(x: 1.0, y: -1.0),
                Point2D(x: 2.0, y: -1.0),
                Point2D(x: 2.0, y: 2.0),
                Point2D(x: 1.0, y: 2.0),
            ],
        ])

        do {
            _ = try SketchProfileExtractor(tolerance: .standard).extractProfiles(
                from: sketch,
                sourceFeatureID: FeatureID(),
                parameters: ResolvedParameterTable()
            )
            Issue.record("Intersecting profile loops must be rejected until region-union extraction is available.")
        } catch SketchError.unsupportedProfile(let message) {
            #expect(message.contains("Intersecting or touching profile loops"))
        } catch {
            Issue.record("Expected unsupportedProfile for intersecting loops, got \(error).")
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
    func largeArcProfileExtractionKeepsExactBoundaryWithBoundedSamples() throws {
        let radius = 1_000.0
        let sketch = roundedCornerSketch(radius: radius)

        let profiles = try SketchProfileExtractor(tolerance: .standard).extractProfiles(
            from: sketch,
            sourceFeatureID: FeatureID(),
            parameters: ResolvedParameterTable()
        )
        let profile = try #require(profiles.first)
        let summary = try ProfileRegionAnalyzer(tolerance: .standard).summary(for: profile)
        let expectedArea = (3.0 + Double.pi / 4.0) * radius * radius

        #expect(profiles.count == 1)
        #expect(profile.boundarySegments.count == 5)
        #expect(profile.vertices.count == CircularCurveSamplingPolicy.standard.maximumSegmentCount + 4)
        #expect(profile.vertices.count <= CircularCurveSamplingPolicy.standard.maximumSegmentCount + profile.boundarySegments.count)
        #expect(abs(summary.areaSquareMeters - expectedArea) <= 1.0e-6)
        #expect(profile.boundarySegments.contains { segment in
            if case .circularArc(let arc) = segment {
                return abs(arc.radius - radius) <= ModelingTolerance.standard.distance
                    && abs(arc.sweepAngle - Double.pi / 2.0) <= ModelingTolerance.standard.angle
            }
            return false
        })
    }

    @Test(.timeLimit(.minutes(1)))
    func largeArcProfileExtrudeCreatesExactCylindricalSideFace() throws {
        let radius = 1_000.0
        let document = makeRoundedCornerExtrudeDocument(radius: radius, depth: 50.0)

        let evaluated = try DocumentEvaluator(tolerance: .standard).evaluate(document)

        #expect(evaluated.brep.bodies.count == 1)
        #expect(evaluated.brep.faces.count == 7)
        #expect(evaluated.brep.geometry.surfaces.values.filter {
            if case .cylinder = $0 {
                return true
            }
            return false
        }.count == 1)
        try evaluated.brep.validate(tolerance: .standard)
    }

    @Test(.timeLimit(.minutes(1)))
    func closedSplineProfileExtractionRetainsExactCurveLoop() throws {
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
        #expect(profile.boundarySegments.count == 1)
        guard case let .spline(spline) = profile.boundarySegments[0] else {
            Issue.record("Expected one exact closed cubic spline boundary.")
            return
        }
        #expect(spline.curve.degree == 3)
        #expect(spline.curve.controlPoints.count == 13)
        #expect(spline.curve.knots.count == 17)
        #expect(abs(area - expectedArea) < 1.0e-6)
    }

    @Test(.timeLimit(.minutes(1)))
    func closedSplineProfileExtrudeCreatesExactRuledBRep() throws {
        let document = makeClosedSplineExtrudeDocument(
            radius: 10.0,
            depth: 5.0,
            unit: .millimeter,
            documentUnits: .millimeters
        )
        let evaluated = try DocumentEvaluator(tolerance: .standard).evaluate(document)

        #expect(evaluated.brep.bodies.count == 1)
        #expect(evaluated.brep.shells.count == 1)
        #expect(evaluated.brep.faces.count == 6)
        #expect(evaluated.brep.edges.count == 12)
        #expect(evaluated.brep.vertices.count == 8)
        #expect(evaluated.brep.geometry.surfaces.values.filter { surface in
            if case .bSpline = surface { return true }
            return false
        }.count == 4)
        #expect(evaluated.brep.loops.values.allSatisfy { loop in
            loop.coedges.allSatisfy { $0.surfaceParameterCurve != nil }
        })
        try evaluated.brep.validate(level: .exact, tolerance: .standard)
        let mesh = try #require(evaluated.meshes.values.first)
        #expect(mesh.positions.count > 24)
        #expect(mesh.indices.count > 36)
    }

    @Test(.timeLimit(.minutes(1)))
    func obliqueVectorExtrudeKeepsCapFacesParallelToSketchPlane() throws {
        let document = makeRectangleExtrudeDocument(
            direction: .vector(Vector3D(x: 0.25, y: 0.5, z: 1.0))
        )
        let evaluated = try DocumentEvaluator(tolerance: .standard).evaluate(document)
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

        try evaluated.brep.validate(tolerance: .standard)
        #expect(startNormal.z < -0.9)
        #expect(endNormal.z > 0.9)
    }

    @Test(.timeLimit(.minutes(1)))
    func vectorExtrudeRejectsDirectionParallelToSketchPlane() {
        let document = makeRectangleExtrudeDocument(
            direction: .vector(Vector3D(x: 1.0, y: 1.0, z: 0.0))
        )

        #expect(throws: FeatureEvaluationError.self) {
            _ = try DocumentEvaluator(tolerance: .standard).evaluate(document)
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func clockwiseProfileExtrudeNormalizesOutwardNormalsAndBalancedEdgeUses() throws {
        let document = makeRectangleExtrudeDocument(clockwiseProfile: true)
        let evaluated = try DocumentEvaluator(tolerance: .standard).evaluate(document)

        try evaluated.brep.validate(tolerance: .standard)
        try expectBalancedEdgeOrientations(in: evaluated.brep)
        let mesh = try #require(evaluated.meshes.values.first)
        #expect(mesh.normals[0].z < -0.9)
        let firstNormal = try firstTriangleNormal(in: mesh)
        #expect(firstNormal.dot(mesh.normals[0]) > 0.9)
    }

    @Test(.timeLimit(.minutes(1)))
    func meshTessellatorAppliesShellAndFaceOrientationToNormals() throws {
        let evaluated = try DocumentEvaluator(tolerance: .standard).evaluate(makeRectangleExtrudeDocument())
        let bodyID = try #require(evaluated.meshes.keys.first)
        let originalMesh = try #require(evaluated.meshes[bodyID])
        let originalNormal = try #require(originalMesh.normals.first)

        var shellReversedModel = evaluated.brep
        let shellID = try #require(shellReversedModel.shells.keys.first)
        shellReversedModel.shells[shellID]?.orientation = .reversed
        let shellReversedMesh = try #require(MeshTessellator(tolerance: .standard).tessellate(model: shellReversedModel)[bodyID])
        let shellReversedNormal = try #require(shellReversedMesh.normals.first)
        let shellReversedTriangleNormal = try firstTriangleNormal(in: shellReversedMesh)

        var faceReversedModel = evaluated.brep
        let faceID = try #require(faceReversedModel.shells[shellID]?.faceIDs.first)
        faceReversedModel.faces[faceID]?.orientation = .reversed
        let faceReversedMesh = try #require(MeshTessellator(tolerance: .standard).tessellate(model: faceReversedModel)[bodyID])
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
        let evaluated = try DocumentEvaluator(tolerance: .standard).evaluate(document)
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
            _ = try DocumentEvaluator(tolerance: .standard).evaluate(document)
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func brepValidationRejectsMissingCurveReference() throws {
        let evaluated = try DocumentEvaluator(tolerance: .standard).evaluate(makeRectangleExtrudeDocument())
        var model = evaluated.brep
        let edge = try #require(model.edges.values.first)
        model.geometry.curves.removeValue(forKey: edge.curveID)

        #expect(throws: TopologyError.self) {
            try model.validate(tolerance: .standard)
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func evaluatedCachesValidateFreshnessAgainstSourceDocument() throws {
        let document = makeRectangleExtrudeDocument()
        let evaluated = try DocumentEvaluator(tolerance: .standard).evaluate(document)

        try evaluated.caches.validateFreshness(for: document, tolerance: .standard)
        try evaluated.validate()
    }

    @Test(.timeLimit(.minutes(1)))
    func cacheFreshnessRejectsEmptyCachesForBodyProducingDocument() throws {
        let document = makeRectangleExtrudeDocument()

        #expect(throws: CacheValidationError.self) {
            try DocumentCaches().validateFreshness(for: document, tolerance: .standard)
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func evaluatedDocumentValidationRejectsTopLevelMeshesThatDoNotMatchBRep() throws {
        let evaluated = try DocumentEvaluator(tolerance: .standard).evaluate(makeRectangleExtrudeDocument())
        let bodyID = try #require(evaluated.meshes.keys.first)
        var staleMeshes = evaluated.meshes
        staleMeshes[bodyID]?.positions[0].x += 0.25
        let staleEvaluated = replacing(evaluated, meshes: staleMeshes)

        #expect(throws: CacheValidationError.self) {
            try staleEvaluated.validate()
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func evaluatedDocumentValidationRejectsTopLevelBRepThatDoesNotMatchCache() throws {
        let evaluated = try DocumentEvaluator(tolerance: .standard).evaluate(makeRectangleExtrudeDocument())
        let bodyID = try #require(evaluated.brep.bodies.keys.first)
        var staleBRep = evaluated.brep
        staleBRep.bodies[bodyID]?.name = "stale-body"
        let staleEvaluated = replacing(evaluated, brep: staleBRep)

        #expect(throws: CacheValidationError.self) {
            try staleEvaluated.validate()
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func evaluatedDocumentValidationRejectsSubshapeIndexCacheMismatch() throws {
        let evaluated = try DocumentEvaluator(tolerance: .standard).evaluate(makeRectangleExtrudeDocument())
        var staleCaches = evaluated.caches
        staleCaches.brep?.subshapes = SubshapeIndex()
        let staleEvaluated = replacing(evaluated, caches: staleCaches)

        #expect(throws: CacheValidationError.self) {
            try staleEvaluated.validate()
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func cacheFreshnessRejectsBRepCacheContentNotEqualToSourceEvaluationEvenWhenMeshesMatch() throws {
        let document = makeRectangleExtrudeDocument()
        var staleCaches = try DocumentEvaluator(tolerance: .standard).evaluate(document).caches
        let bodyID = try #require(staleCaches.brep?.model.bodies.keys.first)
        staleCaches.brep?.model.bodies[bodyID]?.name = "stale-body"

        #expect(throws: CacheValidationError.self) {
            try staleCaches.validateFreshness(for: document, tolerance: .standard)
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func subshapeIndexValidationRejectsInvalidIdentitiesAndDanglingReferences() throws {
        let evaluated = try DocumentEvaluator(tolerance: .standard).evaluate(makeRectangleExtrudeDocument())
        let bodyID = try #require(evaluated.brep.bodies.keys.first)
        var invalidSubshapes = evaluated.subshapes.entries
        let invalidID = SubshapeID(featureID: FeatureID(), role: "", ordinal: 0)
        invalidSubshapes[invalidID] = .body(bodyID)

        let extrudeFeatureID = try #require(evaluated.document.designGraph.order.last)
        let danglingID = SubshapeID(featureID: extrudeFeatureID, role: "dangling", ordinal: 0)
        var danglingSubshapes = evaluated.subshapes.entries
        danglingSubshapes[danglingID] = .body(BodyID())

        #expect(throws: KernelError.self) {
            try SubshapeIndex(invalidSubshapes).validate(
                against: evaluated.brep,
                lineage: evaluated.lineage
            )
        }
        #expect(throws: KernelError.self) {
            try SubshapeIndex(danglingSubshapes).validate(
                against: evaluated.brep,
                lineage: evaluated.lineage
            )
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func subshapeIndexValidationRequiresExactTopologyCoverage() throws {
        let evaluated = try DocumentEvaluator(tolerance: .standard).evaluate(makeRectangleExtrudeDocument())
        let edgeID = try #require(evaluated.subshapes.entries.first { _, reference in
            reference.isEdge
        }?.key)
        var incompleteSubshapes = evaluated.subshapes.entries
        incompleteSubshapes.removeValue(forKey: edgeID)

        #expect(throws: KernelError.self) {
            try SubshapeIndex(incompleteSubshapes).validate(
                against: evaluated.brep,
                lineage: evaluated.lineage
            )
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

        let report = DocumentEvaluator(tolerance: .standard).evaluateReport(document)

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
        let report = DocumentEvaluator(
            tessellator: EmptyTessellator(),
            tolerance: .standard
        ).evaluateReport(makeRectangleExtrudeDocument())

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

        let report = DocumentEvaluator(tolerance: .standard).evaluateReport(document)

        #expect(report.evaluatedDocument == nil)
        #expect(report.isComplete == false)
        #expect(report.featureStates[featureID] == .unevaluated)
        #expect(report.failure != nil)
        try report.failure?.validate()
    }

    @Test(.timeLimit(.minutes(1)))
    func cacheFreshnessRejectsStaleBRepAndMeshMetadata() throws {
        let document = makeRectangleExtrudeDocument()
        let evaluated = try DocumentEvaluator(tolerance: .standard).evaluate(document)

        var staleBRepCaches = evaluated.caches
        staleBRepCaches.brep?.parameterRevision = document.parameters.revision.advanced()

        var staleMeshCaches = evaluated.caches
        let bodyID = try #require(staleMeshCaches.meshes.keys.first)
        staleMeshCaches.meshes[bodyID]?.tessellationOptions = TessellationOptions(
            linearTolerance: 1.0e-3,
            angularTolerance: 1.0e-3
        )

        #expect(throws: CacheValidationError.self) {
            try staleBRepCaches.validateFreshness(for: document, tolerance: .standard)
        }
        #expect(throws: CacheValidationError.self) {
            try staleMeshCaches.validateFreshness(for: document, tolerance: .standard)
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func cacheFreshnessRejectsInvalidSourceDocumentAndKernelVersion() throws {
        let document = makeRectangleExtrudeDocument()
        let evaluated = try DocumentEvaluator(tolerance: .standard).evaluate(document)
        var invalidDocument = document
        invalidDocument.schemaVersion = SchemaVersion(major: 1, minor: 0, patch: -1)
        let invalidKernelVersion = SchemaVersion(major: 1, minor: 0, patch: -1)
        var invalidKernelCaches = evaluated.caches
        invalidKernelCaches.brep?.kernelVersion = invalidKernelVersion
        for bodyID in invalidKernelCaches.meshes.keys {
            invalidKernelCaches.meshes[bodyID]?.kernelVersion = invalidKernelVersion
        }

        #expect(throws: SchemaError.self) {
            try evaluated.caches.validateFreshness(for: invalidDocument, tolerance: .standard)
        }
        #expect(throws: SchemaError.self) {
            try invalidKernelCaches.validateFreshness(
                for: document,
                tolerance: .standard,
                kernelVersion: invalidKernelVersion
            )
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func cacheFreshnessRejectsMeshContentThatDoesNotMatchBRep() throws {
        let document = makeRectangleExtrudeDocument()
        let evaluated = try DocumentEvaluator(tolerance: .standard).evaluate(document)
        var staleCaches = evaluated.caches
        let bodyID = try #require(staleCaches.meshes.keys.first)
        var staleMeshCache = try #require(staleCaches.meshes[bodyID])
        for index in staleMeshCache.mesh.positions.indices {
            staleMeshCache.mesh.positions[index].x += 0.25
        }
        staleCaches.meshes[bodyID] = staleMeshCache

        #expect(throws: CacheValidationError.self) {
            try staleCaches.validateFreshness(for: document, tolerance: .standard)
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func cacheFreshnessRejectsBRepContentFromDifferentSourceEvenWhenMetadataMatches() throws {
        let document = makeRectangleExtrudeDocument(width: 40.0)
        let otherDocument = makeRectangleExtrudeDocument(width: 80.0)
        var staleCaches = try DocumentEvaluator(tolerance: .standard).evaluate(otherDocument).caches
        let sourceFingerprint = try document.sourceFingerprint(tolerance: .standard)
        staleCaches.brep?.designRevision = document.designGraph.revision
        staleCaches.brep?.parameterRevision = document.parameters.revision
        staleCaches.brep?.sourceFingerprint = sourceFingerprint
        for bodyID in staleCaches.meshes.keys {
            staleCaches.meshes[bodyID]?.designRevision = document.designGraph.revision
            staleCaches.meshes[bodyID]?.parameterRevision = document.parameters.revision
            staleCaches.meshes[bodyID]?.sourceFingerprint = sourceFingerprint
        }

        #expect(throws: CacheValidationError.self) {
            try staleCaches.validateFreshness(for: document, tolerance: .standard)
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func cacheFreshnessRejectsSourceGraphMutationWithoutRevisionAdvance() throws {
        let document = makeRectangleExtrudeDocument()
        let evaluated = try DocumentEvaluator(tolerance: .standard).evaluate(document)
        var mutatedDocument = document
        let extrudeFeatureID = try #require(mutatedDocument.designGraph.order.last)
        mutatedDocument.designGraph.nodes[extrudeFeatureID]?.isSuppressed = true
        try mutatedDocument.validate(tolerance: .standard)

        #expect(throws: CacheValidationError.self) {
            try evaluated.caches.validateFreshness(for: mutatedDocument, tolerance: .standard)
        }

        let staleEvaluated = EvaluatedDocument(
            document: mutatedDocument,
            parameters: evaluated.parameters,
            brep: evaluated.brep,
            meshes: evaluated.meshes,
            curves: evaluated.curves,
            caches: evaluated.caches,
            subshapes: evaluated.subshapes,
            lineage: evaluated.lineage,
            configuration: evaluated.configuration,
            evaluationMetrics: evaluated.evaluationMetrics
        )
        #expect(throws: CacheValidationError.self) {
            try staleEvaluated.validate()
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func cacheFreshnessRejectsParameterMutationWithoutRevisionAdvance() throws {
        let document = makeRectangleExtrudeDocument()
        let evaluated = try DocumentEvaluator(tolerance: .standard).evaluate(document)
        var mutatedDocument = document
        let widthID = try #require(mutatedDocument.parameters.parameters.values.first { $0.name == "width" }?.id)
        mutatedDocument.parameters.parameters[widthID]?.expression = .constant(.length(80.0, unit: .millimeter))
        try mutatedDocument.validate(tolerance: .standard)

        #expect(throws: CacheValidationError.self) {
            try evaluated.caches.validateFreshness(for: mutatedDocument, tolerance: .standard)
        }

        let staleEvaluated = EvaluatedDocument(
            document: mutatedDocument,
            parameters: evaluated.parameters,
            brep: evaluated.brep,
            meshes: evaluated.meshes,
            curves: evaluated.curves,
            caches: evaluated.caches,
            subshapes: evaluated.subshapes,
            lineage: evaluated.lineage,
            configuration: evaluated.configuration,
            evaluationMetrics: evaluated.evaluationMetrics
        )
        #expect(throws: CacheValidationError.self) {
            try staleEvaluated.validate()
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func cacheFreshnessRejectsMeshCacheTableKeyMismatch() throws {
        let document = makeRectangleExtrudeDocument()
        let evaluated = try DocumentEvaluator(tolerance: .standard).evaluate(document)
        var staleCaches = evaluated.caches
        let bodyID = try #require(staleCaches.meshes.keys.first)
        staleCaches.meshes[bodyID]?.bodyID = BodyID()

        #expect(throws: CacheValidationError.self) {
            try staleCaches.validateFreshness(for: document, tolerance: .standard)
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func sourceFingerprintIsIndependentOfDictionaryInsertionOrder() throws {
        var document = makeDocumentWithManyIndependentParameters(reverseInsertionOrder: false)
        var reorderedDocument = makeDocumentWithManyIndependentParameters(reverseInsertionOrder: true)
        document.id = fixedDocumentID()
        reorderedDocument.id = document.id

        #expect(try document.sourceFingerprint(tolerance: .standard) == reorderedDocument.sourceFingerprint(tolerance: .standard))
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
            _ = try DocumentEvaluator(tolerance: .standard).evaluate(emptyDocument)
        }
        #expect(throws: FeatureEvaluationError.self) {
            _ = try DocumentEvaluator(tolerance: .standard).evaluate(suppressedDocument)
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

        let evaluated = try DocumentEvaluator(tolerance: .standard).evaluate(document)
        let curves = try #require(evaluated.curves[featureID])

        #expect(evaluated.brep.bodies.isEmpty)
        #expect(evaluated.meshes.isEmpty)
        #expect(curves.count == 1)
        #expect(curves.first?.source == .sketchEntity(entityID))
        try evaluated.validate()
    }

    @Test(.timeLimit(.minutes(1)))
    func documentEvaluatorRejectsIncompleteSubshapeOutput() {
        let evaluator = DocumentEvaluator(
            featureEvaluator: IncompleteSubshapeFeatureEvaluator(),
            tolerance: .standard
        )

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
            try document.validate(tolerance: .standard)
        }
        let evaluated = try DocumentEvaluator(tolerance: tolerance).evaluate(document)

        try evaluated.validate()
        try evaluated.caches.validateFreshness(for: document, tolerance: tolerance)
    }

    @Test(.timeLimit(.minutes(1)))
    func meshTessellatorRejectsNonFiniteTessellationOptions() throws {
        let evaluated = try DocumentEvaluator(tolerance: .standard).evaluate(makeRectangleExtrudeDocument())
        let options = TessellationOptions(linearTolerance: .infinity, angularTolerance: 1.0e-3)

        #expect(throws: TessellationError.self) {
            _ = try MeshTessellator(tolerance: .standard).tessellate(model: evaluated.brep, options: options)
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func brepValidationRejectsEdgeTrimEndpointMismatch() throws {
        let evaluated = try DocumentEvaluator(tolerance: .standard).evaluate(makeRectangleExtrudeDocument())
        var model = evaluated.brep
        let edgeID = try #require(model.edges.keys.first)
        model.edges[edgeID]?.trim = CurveTrim(startParameter: 0.0, endParameter: 0.5)

        #expect(throws: TopologyError.self) {
            try model.validate(tolerance: .standard)
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func brepValidationRejectsDegenerateEdgeGeometry() throws {
        let evaluated = try DocumentEvaluator(tolerance: .standard).evaluate(makeRectangleExtrudeDocument())
        var model = evaluated.brep
        let edge = try #require(model.edges.values.first)
        let startPoint = try #require(model.vertices[edge.startVertexID]?.point)
        model.vertices[edge.endVertexID]?.point = startPoint

        #expect(throws: TopologyError.self) {
            try model.validate(tolerance: .standard)
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func brepValidationRejectsFullPeriodCircleTrimAsSingleEdge() throws {
        let evaluated = try DocumentEvaluator(tolerance: .standard).evaluate(makeRectangleExtrudeDocument())
        var model = evaluated.brep
        let edge = try #require(model.edges.values.first)
        let curveID = edge.curveID
        let circlePoint = Point3D(x: 1.0, y: 0.0, z: 0.0)
        model.geometry.curves[curveID] = .circle(Circle3D(center: .origin, normal: .unitZ, radius: 1.0))
        model.vertices[edge.startVertexID]?.point = circlePoint
        model.vertices[edge.endVertexID]?.point = circlePoint
        model.edges[edge.id]?.trim = CurveTrim(startParameter: 0.0, endParameter: Double.pi * 2.0)

        #expect(throws: TopologyError.self) {
            try model.validate(tolerance: .standard)
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func brepValidationRejectsCircleTrimSpanningMoreThanOnePeriod() throws {
        let evaluated = try DocumentEvaluator(tolerance: .standard).evaluate(makeRectangleExtrudeDocument())
        var model = evaluated.brep
        let edge = try #require(model.edges.values.first)
        let curveID = edge.curveID
        let endParameter = Double.pi * 4.0 + 0.25
        model.geometry.curves[curveID] = .circle(Circle3D(center: .origin, normal: .unitZ, radius: 1.0))
        model.vertices[edge.startVertexID]?.point = Point3D(x: 1.0, y: 0.0, z: 0.0)
        model.vertices[edge.endVertexID]?.point = Point3D(x: cos(0.25), y: sin(0.25), z: 0.0)
        model.edges[edge.id]?.trim = CurveTrim(startParameter: 0.0, endParameter: endParameter)

        #expect(throws: TopologyError.self) {
            try model.validate(tolerance: .standard)
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func brepValidationRejectsMismatchedSurfaceParameterCurve() throws {
        let evaluated = try DocumentEvaluator(tolerance: .standard).evaluate(makePolySplineQuadDocument())
        var model = evaluated.brep
        let face = try #require(model.faces.values.first)
        let loopID = try #require(face.loops.first)
        var loop = try #require(model.loops[loopID])
        loop.edges[0].surfaceParameterCurve = .constantV(v: 1.0, uStart: 0.0, uEnd: 1.0)
        model.loops[loopID] = loop

        #expect(throws: TopologyError.self) {
            try model.validate(tolerance: .standard)
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func polySplineQuadMeshCreatesBSplineSheetTopology() throws {
        let document = makePolySplineQuadDocument()
        let evaluated = try DocumentEvaluator(tolerance: .standard).evaluate(document)

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
        let generatedReferences = Array(evaluated.subshapes.entries.values)
        #expect(generatedReferences.contains { $0.isBody })
        #expect(generatedReferences.contains { $0.isFace })
        #expect(generatedReferences.filter { $0.isEdge }.count == 4)
        #expect(generatedReferences.filter { $0.isVertex }.count == 4)
        let subshapeRoleStrings = evaluated.subshapes.entries.keys.map(subshapeRoleString)
        #expect(subshapeRoleStrings.contains { $0.contains("polySpline.patch:0:face") })
        #expect(subshapeRoleStrings.contains { $0.contains("polySpline.edge:source:") })
        #expect(subshapeRoleStrings.contains { $0.contains("polySpline.vertex:source:") })
    }

    @Test(.timeLimit(.minutes(1)))
    func polySplinePlanarPatchNetworkCreatesMultiPatchBSplineSheetTopology() throws {
        let document = makePolySplinePatchNetworkDocument(
            centerZ: 0.0,
            options: PolySplineOptions(mergePatches: false)
        )
        let evaluated = try DocumentEvaluator(tolerance: .standard).evaluate(document)

        #expect(evaluated.brep.bodies.count == 1)
        let body = try #require(evaluated.brep.bodies.values.first)
        #expect(body.kind == .sheet)
        #expect(evaluated.brep.faces.count == 2)
        #expect(evaluated.brep.edges.count == 7)
        #expect(evaluated.brep.vertices.count == 6)
        #expect(evaluated.brep.geometry.surfaces.count == 2)
        #expect(evaluated.meshes.values.first?.positions.count ?? 0 > 18)
        let generatedReferences = Array(evaluated.subshapes.entries.values)
        #expect(generatedReferences.contains { $0.isBody })
        #expect(generatedReferences.filter { $0.isFace }.count == 2)
        #expect(generatedReferences.filter { $0.isEdge }.count == 7)
        #expect(generatedReferences.filter { $0.isVertex }.count == 6)
        let subshapeRoleStrings = evaluated.subshapes.entries.keys.map(subshapeRoleString)
        #expect(subshapeRoleStrings.contains { $0.contains("polySpline.patch:0:face") })
        #expect(subshapeRoleStrings.contains { $0.contains("polySpline.patch:2:face") })
        let sharedEdgeNames = evaluated.subshapes.entries.filter { name, reference in
            reference.isEdge && name.role.contains("polySpline.edge:source:1:4")
        }
        #expect(sharedEdgeNames.count == 1)
    }

    @Test(.timeLimit(.minutes(1)))
    func polySplineQuadMeshPreservesMeshBoundaryWinding() throws {
        let forward = try DocumentEvaluator(tolerance: .standard).evaluate(makePolySplineQuadDocument())
        let reversed = try DocumentEvaluator(tolerance: .standard).evaluate(makePolySplineQuadDocument(indices: [0, 2, 1, 0, 3, 2]))
        let forwardSurface = try polySplineSurface(from: forward)
        let reversedSurface = try polySplineSurface(from: reversed)

        let forwardNormal = try forwardSurface.normal(u: 0.5, v: 0.5, tolerance: .standard)
        let reversedNormal = try reversedSurface.normal(u: 0.5, v: 0.5, tolerance: .standard)

        #expect(forwardNormal.z > 0.0)
        #expect(reversedNormal.z < 0.0)
    }

    @Test(.timeLimit(.minutes(1)))
    func polySplineInteriorControlPointOverrideUpdatesEvaluatedSurface() throws {
        let overridePoint = Point3D(x: 0.7, y: 0.55, z: 1.25)
        let evaluated = try DocumentEvaluator(tolerance: .standard).evaluate(makePolySplineQuadDocument(controlPointOverrides: [
            PolySplineSurfaceControlPointOverride(
                patchID: 0,
                uIndex: 1,
                vIndex: 1,
                point: overridePoint
            ),
        ]))
        let faceName = try #require(evaluated.subshapes.entries.first { name, reference in
            reference.isFace && name.role.contains("polySpline.patch:0:face")
        }?.key)
        let surfaceReference = try stableSurfaceReference(faceName, in: evaluated)
        let controlPoint = try SurfaceQueryEvaluator(tolerance: .standard).controlPoint(
            SurfaceControlPointReference(surface: surfaceReference, uIndex: 1, vIndex: 1),
            in: evaluated
        )

        #expect(controlPoint.isApproximatelyEqual(to: overridePoint, tolerance: 1.0e-12))
    }

    @Test(.timeLimit(.minutes(1)))
    func polySplineInteriorControlPointOverrideUpdatesEvaluatedWeight() throws {
        let evaluated = try DocumentEvaluator(tolerance: .standard).evaluate(makePolySplineQuadDocument(controlPointOverrides: [
            PolySplineSurfaceControlPointOverride(
                patchID: 0,
                uIndex: 1,
                vIndex: 1,
                point: Point3D(x: 0.7, y: 0.55, z: 1.25),
                weight: 2.5
            ),
        ]))
        let surface = try polySplineSurface(from: evaluated)

        #expect(surface.isRational)
        #expect(surface.weights[1][1] == 2.5)
    }

    @Test(.timeLimit(.minutes(1)))
    func bSplineSurfaceFeatureEvaluatorProducesSourceOwnedSheetTopology() throws {
        let sourceSurface = makeBSplineSurfaceFeatureSurface()
        let evaluated = try DocumentEvaluator(tolerance: .standard).evaluate(makeBSplineSurfaceDocument(surface: sourceSurface))
        let body = try #require(evaluated.brep.bodies.values.first)
        let face = try #require(evaluated.brep.faces.values.first)
        let surface = try #require(evaluated.brep.geometry.surfaces[face.surfaceID])

        #expect(body.kind == .sheet)
        #expect(evaluated.brep.faces.count == 1)
        #expect(evaluated.brep.edges.count == 4)
        #expect(evaluated.brep.vertices.count == 4)
        guard case let .bSpline(bSpline) = surface else {
            Issue.record("Expected a B-spline surface.")
            return
        }
        #expect(bSpline.isRational)
        #expect(bSpline.weights[1][1] == 2.0)
        #expect(evaluated.subshapes.entries.contains { name, reference in
            reference.isFace && name.role.contains("bSplineSurface.patch:0:face")
        })
        #expect(evaluated.subshapes.entries.contains { name, reference in
            reference.isEdge && name.role.contains("bSplineSurface.patch:0:edge:vMin")
        })
        #expect(evaluated.subshapes.entries.contains { name, reference in
            reference.isVertex && name.role.contains("bSplineSurface.patch:0:vertex:uMin:vMin")
        })
    }

    @Test(.timeLimit(.minutes(1)))
    func bSplineSurfaceFeatureEvaluatorUsesAuthoredRectangularTrimDomain() throws {
        let sourceSurface = makeBSplineSurfaceFeatureSurface()
        let trimDomain = BSplineSurfaceTrimDomain(
            uLowerBound: 0.25,
            uUpperBound: 0.75,
            vLowerBound: 0.2,
            vUpperBound: 0.8
        )
        let evaluated = try DocumentEvaluator(tolerance: .standard).evaluate(makeBSplineSurfaceDocument(
            surface: sourceSurface,
            outerTrimDomain: trimDomain
        ))
        let face = try #require(evaluated.brep.faces.values.first)
        let loopID = try #require(face.loops.first)
        let loop = try #require(evaluated.brep.loops[loopID])
        let vMinEdge = try #require(evaluated.brep.edges[loop.edges[0].edgeID])
        let uMaxEdge = try #require(evaluated.brep.edges[loop.edges[1].edgeID])
        let vMaxEdge = try #require(evaluated.brep.edges[loop.edges[2].edgeID])
        let uMinEdge = try #require(evaluated.brep.edges[loop.edges[3].edgeID])
        let vMinTrim = try #require(vMinEdge.trim)
        let uMaxTrim = try #require(uMaxEdge.trim)
        let vMaxTrim = try #require(vMaxEdge.trim)
        let uMinTrim = try #require(uMinEdge.trim)

        #expect(abs(vMinTrim.startParameter - 0.25) <= 1.0e-12)
        #expect(abs(vMinTrim.endParameter - 0.75) <= 1.0e-12)
        #expect(abs(uMaxTrim.startParameter - 0.2) <= 1.0e-12)
        #expect(abs(uMaxTrim.endParameter - 0.8) <= 1.0e-12)
        #expect(abs(vMaxTrim.startParameter - 0.75) <= 1.0e-12)
        #expect(abs(vMaxTrim.endParameter - 0.25) <= 1.0e-12)
        #expect(abs(uMinTrim.startParameter - 0.8) <= 1.0e-12)
        #expect(abs(uMinTrim.endParameter - 0.2) <= 1.0e-12)

        let bottomLeft = try #require(evaluated.brep.vertices[vMinEdge.startVertexID])
        let bottomRight = try #require(evaluated.brep.vertices[vMinEdge.endVertexID])
        let topRight = try #require(evaluated.brep.vertices[uMaxEdge.endVertexID])
        let topLeft = try #require(evaluated.brep.vertices[vMaxEdge.endVertexID])
        #expect(bottomLeft.point.isApproximatelyEqual(
            to: try sourceSurface.point(u: 0.25, v: 0.2, tolerance: .standard),
            tolerance: 1.0e-12
        ))
        #expect(bottomRight.point.isApproximatelyEqual(
            to: try sourceSurface.point(u: 0.75, v: 0.2, tolerance: .standard),
            tolerance: 1.0e-12
        ))
        #expect(topRight.point.isApproximatelyEqual(
            to: try sourceSurface.point(u: 0.75, v: 0.8, tolerance: .standard),
            tolerance: 1.0e-12
        ))
        #expect(topLeft.point.isApproximatelyEqual(
            to: try sourceSurface.point(u: 0.25, v: 0.8, tolerance: .standard),
            tolerance: 1.0e-12
        ))
    }

    @Test(.timeLimit(.minutes(1)))
    func bSplineSurfaceFeatureEvaluatorUsesAuthoredNonRectangularTrimLoop() throws {
        let sourceSurface = makeBSplineSurfaceFeatureSurface()
        let trimLoop = BSplineSurfaceTrimLoop(
            role: .outer,
            edges: [
                BSplineSurfaceTrimEdge(parameterCurve: .polyline([
                    SurfaceParameter(u: 0.2, v: 0.2),
                    SurfaceParameter(u: 0.8, v: 0.25),
                ])),
                BSplineSurfaceTrimEdge(parameterCurve: .polyline([
                    SurfaceParameter(u: 0.8, v: 0.25),
                    SurfaceParameter(u: 0.45, v: 0.8),
                ])),
                BSplineSurfaceTrimEdge(parameterCurve: .polyline([
                    SurfaceParameter(u: 0.45, v: 0.8),
                    SurfaceParameter(u: 0.2, v: 0.2),
                ])),
            ]
        )
        let evaluated = try DocumentEvaluator(tolerance: .standard).evaluate(makeBSplineSurfaceDocument(
            surface: sourceSurface,
            trimLoops: [trimLoop]
        ))
        let face = try #require(evaluated.brep.faces.values.first)
        let loopID = try #require(face.loops.first)
        let loop = try #require(evaluated.brep.loops[loopID])

        #expect(loop.edges.count == 3)
        for orientedEdge in loop.edges {
            let edge = try #require(evaluated.brep.edges[orientedEdge.edgeID])
            #expect(edge.surfaceApproximationTolerance != nil)
            #expect(orientedEdge.surfaceParameterCurve != nil)
        }
        #expect(evaluated.subshapes.entries.contains { name, reference in
            reference.isEdge && name.role.contains("bSplineSurface.patch:0:loop:0:edge:0")
        })
    }

    @Test(.timeLimit(.minutes(1)))
    func bSplineSurfaceFeatureEvaluatorPreservesAuthoredRationalTrimCurve() throws {
        let sourceSurface = makeLinearBSplineSurfaceFeatureSurface()
        let middleWeight = sqrt(0.5)
        let trimCurve = BSplineCurve2D(
            degree: 2,
            knots: [0.0, 0.0, 0.0, 1.0, 1.0, 1.0],
            controlPoints: [
                Point2D(x: 0.8, y: 0.2),
                Point2D(x: 0.8, y: 0.8),
                Point2D(x: 0.2, y: 0.8),
            ],
            weights: [1.0, middleWeight, 1.0]
        )
        let trimLoop = BSplineSurfaceTrimLoop(
            role: .outer,
            edges: [
                BSplineSurfaceTrimEdge(parameterCurve: .bSpline(trimCurve)),
                BSplineSurfaceTrimEdge(parameterCurve: .polyline([
                    SurfaceParameter(u: 0.2, v: 0.8),
                    SurfaceParameter(u: 0.2, v: 0.2),
                ])),
                BSplineSurfaceTrimEdge(parameterCurve: .polyline([
                    SurfaceParameter(u: 0.2, v: 0.2),
                    SurfaceParameter(u: 0.8, v: 0.2),
                ])),
            ]
        )
        let evaluated = try DocumentEvaluator(tolerance: .standard).evaluate(makeBSplineSurfaceDocument(
            surface: sourceSurface,
            trimLoops: [trimLoop]
        ))
        let faceName = try #require(evaluated.subshapes.entries.first { name, reference in
            reference.isFace && name.role.contains("bSplineSurface.patch:0:face")
        }?.key)
        let face = try #require(evaluated.brep.faces.values.first)
        let loopID = try #require(face.loops.first)
        let loop = try #require(evaluated.brep.loops[loopID])
        let firstEdge = try #require(evaluated.brep.edges[loop.edges[0].edgeID])
        let trim = try SurfaceQueryEvaluator(tolerance: .standard).trimCurve(
            SurfaceTrimReference(
                surface: try stableSurfaceReference(faceName, in: evaluated),
                loopIndex: 0,
                edgeIndex: 0
            ),
            in: evaluated
        )
        let mesh = try #require(evaluated.meshes.values.first)

        guard case let .bSpline(storedCurve) = trim.parameterCurve else {
            Issue.record("Expected the authored rational surface parameter curve to be preserved.")
            return
        }
        #expect(storedCurve.isRational)
        #expect(firstEdge.surfaceApproximationTolerance != nil)
        #expect(mesh.positions.isEmpty == false)
    }

    @Test(.timeLimit(.minutes(1)))
    func bSplineSurfaceTessellationUsesRectangularTrimDomain() throws {
        let sourceSurface = makeLinearBSplineSurfaceFeatureSurface()
        let trimDomain = BSplineSurfaceTrimDomain(
            uLowerBound: 0.25,
            uUpperBound: 0.75,
            vLowerBound: 0.2,
            vUpperBound: 0.8
        )
        let evaluated = try DocumentEvaluator(tolerance: .standard).evaluate(makeBSplineSurfaceDocument(
            surface: sourceSurface,
            outerTrimDomain: trimDomain
        ))
        let mesh = try #require(evaluated.meshes.values.first)

        #expect(mesh.positions.isEmpty == false)
        #expect(mesh.positions.allSatisfy { point in
            point.x >= 0.5 - 1.0e-10
                && point.x <= 1.5 + 1.0e-10
                && point.y >= 0.3 - 1.0e-10
                && point.y <= 1.2 + 1.0e-10
        })
    }

    @Test(.timeLimit(.minutes(1)))
    func bSplineSurfaceTessellationUsesAuthoredTrimLoopParameters() throws {
        let sourceSurface = makeLinearBSplineSurfaceFeatureSurface()
        let trimLoop = BSplineSurfaceTrimLoop(
            role: .outer,
            edges: [
                BSplineSurfaceTrimEdge(parameterCurve: .polyline([
                    SurfaceParameter(u: 0.2, v: 0.2),
                    SurfaceParameter(u: 0.8, v: 0.25),
                ])),
                BSplineSurfaceTrimEdge(parameterCurve: .polyline([
                    SurfaceParameter(u: 0.8, v: 0.25),
                    SurfaceParameter(u: 0.45, v: 0.8),
                ])),
                BSplineSurfaceTrimEdge(parameterCurve: .polyline([
                    SurfaceParameter(u: 0.45, v: 0.8),
                    SurfaceParameter(u: 0.2, v: 0.2),
                ])),
            ]
        )
        let evaluated = try DocumentEvaluator(tolerance: .standard).evaluate(makeBSplineSurfaceDocument(
            surface: sourceSurface,
            trimLoops: [trimLoop]
        ))
        let mesh = try #require(evaluated.meshes.values.first)
        let triangle = [
            SurfaceParameter(u: 0.2, v: 0.2),
            SurfaceParameter(u: 0.8, v: 0.25),
            SurfaceParameter(u: 0.45, v: 0.8),
        ]

        #expect(mesh.positions.isEmpty == false)
        #expect(mesh.positions.allSatisfy { point in
            parameter(linearSurfacePoint: point).isInsideOrOnTriangle(triangle, tolerance: 1.0e-10)
        })
        for triangleIndex in stride(from: 0, to: mesh.indices.count, by: 3) {
            let centroid = meshTriangleCentroid(at: triangleIndex, in: mesh)
            #expect(parameter(linearSurfacePoint: centroid).isInsideOrOnTriangle(triangle, tolerance: 1.0e-10))
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func bSplineSurfaceTessellationPreservesAuthoredInnerTrimLoopHole() throws {
        let sourceSurface = makeLinearBSplineSurfaceFeatureSurface()
        let outerDomain = try BSplineSurfaceTrimDomain.fullSurfaceDomain(
            for: sourceSurface,
            tolerance: .standard
        )
        let outerLoop = BSplineSurfaceTrimLoop.rectangularOuterLoop(domain: outerDomain)
        let innerTriangle = [
            SurfaceParameter(u: 0.35, v: 0.35),
            SurfaceParameter(u: 0.65, v: 0.35),
            SurfaceParameter(u: 0.5, v: 0.65),
        ]
        let innerLoop = BSplineSurfaceTrimLoop(
            role: .inner,
            edges: [
                BSplineSurfaceTrimEdge(parameterCurve: .polyline([innerTriangle[0], innerTriangle[1]])),
                BSplineSurfaceTrimEdge(parameterCurve: .polyline([innerTriangle[1], innerTriangle[2]])),
                BSplineSurfaceTrimEdge(parameterCurve: .polyline([innerTriangle[2], innerTriangle[0]])),
            ]
        )
        let evaluated = try DocumentEvaluator(tolerance: .standard).evaluate(makeBSplineSurfaceDocument(
            surface: sourceSurface,
            trimLoops: [outerLoop, innerLoop]
        ))
        let mesh = try #require(evaluated.meshes.values.first)

        #expect(mesh.positions.isEmpty == false)
        for triangleIndex in stride(from: 0, to: mesh.indices.count, by: 3) {
            let centroid = meshTriangleCentroid(at: triangleIndex, in: mesh)
            #expect(parameter(linearSurfacePoint: centroid).isInsideOrOnTriangle(
                innerTriangle,
                tolerance: 1.0e-10
            ) == false)
        }
        #expect(abs(meshParameterArea(in: mesh) - (1.0 - parameterTriangleArea(innerTriangle))) <= 1.0e-8)
    }

    @Test(.timeLimit(.minutes(1)))
    func bSplineSurfaceTessellationPreservesMultipleAuthoredInnerTrimLoopHoles() throws {
        let sourceSurface = makeLinearBSplineSurfaceFeatureSurface()
        let outerDomain = try BSplineSurfaceTrimDomain.fullSurfaceDomain(
            for: sourceSurface,
            tolerance: .standard
        )
        let outerLoop = BSplineSurfaceTrimLoop.rectangularOuterLoop(domain: outerDomain)
        let firstHole = [
            SurfaceParameter(u: 0.18, v: 0.24),
            SurfaceParameter(u: 0.36, v: 0.24),
            SurfaceParameter(u: 0.27, v: 0.44),
        ]
        let secondHole = [
            SurfaceParameter(u: 0.62, v: 0.58),
            SurfaceParameter(u: 0.84, v: 0.58),
            SurfaceParameter(u: 0.73, v: 0.82),
        ]
        let evaluated = try DocumentEvaluator(tolerance: .standard).evaluate(makeBSplineSurfaceDocument(
            surface: sourceSurface,
            trimLoops: [
                outerLoop,
                triangularInnerTrimLoop(firstHole),
                triangularInnerTrimLoop(secondHole),
            ]
        ))
        let mesh = try #require(evaluated.meshes.values.first)
        let expectedArea = 1.0
            - parameterTriangleArea(firstHole)
            - parameterTriangleArea(secondHole)

        #expect(mesh.positions.isEmpty == false)
        for triangleIndex in stride(from: 0, to: mesh.indices.count, by: 3) {
            let centroid = meshTriangleCentroid(at: triangleIndex, in: mesh)
            let parameter = parameter(linearSurfacePoint: centroid)
            #expect(parameter.isInsideOrOnTriangle(firstHole, tolerance: 1.0e-10) == false)
            #expect(parameter.isInsideOrOnTriangle(secondHole, tolerance: 1.0e-10) == false)
        }
        #expect(abs(meshParameterArea(in: mesh) - expectedArea) <= 1.0e-8)
    }

    @Test(.timeLimit(.minutes(1)))
    func bSplineSurfaceFeatureRejectsSelfIntersectingAuthoredTrimLoop() throws {
        let sourceSurface = makeLinearBSplineSurfaceFeatureSurface()
        let trimLoop = BSplineSurfaceTrimLoop(
            role: .outer,
            edges: [
                BSplineSurfaceTrimEdge(parameterCurve: .polyline([
                    SurfaceParameter(u: 0.2, v: 0.2),
                    SurfaceParameter(u: 0.8, v: 0.8),
                ])),
                BSplineSurfaceTrimEdge(parameterCurve: .polyline([
                    SurfaceParameter(u: 0.8, v: 0.8),
                    SurfaceParameter(u: 0.2, v: 0.8),
                ])),
                BSplineSurfaceTrimEdge(parameterCurve: .polyline([
                    SurfaceParameter(u: 0.2, v: 0.8),
                    SurfaceParameter(u: 0.8, v: 0.2),
                ])),
                BSplineSurfaceTrimEdge(parameterCurve: .polyline([
                    SurfaceParameter(u: 0.8, v: 0.2),
                    SurfaceParameter(u: 0.2, v: 0.2),
                ])),
            ]
        )

        #expect(throws: FeatureEvaluationError.self) {
            try DocumentEvaluator(tolerance: .standard).evaluate(makeBSplineSurfaceDocument(
                surface: sourceSurface,
                trimLoops: [trimLoop]
            ))
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func bSplineSurfaceFeatureRejectsInnerTrimLoopOutsideOuterLoop() throws {
        let sourceSurface = makeLinearBSplineSurfaceFeatureSurface()
        let outerLoop = BSplineSurfaceTrimLoop.rectangularOuterLoop(
            domain: BSplineSurfaceTrimDomain(
                uLowerBound: 0.2,
                uUpperBound: 0.8,
                vLowerBound: 0.2,
                vUpperBound: 0.8
            )
        )
        let innerLoop = BSplineSurfaceTrimLoop(
            role: .inner,
            edges: [
                BSplineSurfaceTrimEdge(parameterCurve: .polyline([
                    SurfaceParameter(u: 0.82, v: 0.3),
                    SurfaceParameter(u: 0.9, v: 0.3),
                ])),
                BSplineSurfaceTrimEdge(parameterCurve: .polyline([
                    SurfaceParameter(u: 0.9, v: 0.3),
                    SurfaceParameter(u: 0.86, v: 0.45),
                ])),
                BSplineSurfaceTrimEdge(parameterCurve: .polyline([
                    SurfaceParameter(u: 0.86, v: 0.45),
                    SurfaceParameter(u: 0.82, v: 0.3),
                ])),
            ]
        )

        #expect(throws: FeatureEvaluationError.self) {
            try DocumentEvaluator(tolerance: .standard).evaluate(makeBSplineSurfaceDocument(
                surface: sourceSurface,
                trimLoops: [outerLoop, innerLoop]
            ))
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func polySplineRejectsBoundaryControlPointOverride() throws {
        let feature = PolySplineFeature(
            sourceMesh: makePolySplineQuadMesh(),
            controlPointOverrides: [
                PolySplineSurfaceControlPointOverride(
                    patchID: 0,
                    uIndex: 0,
                    vIndex: 0,
                    point: Point3D(x: 0.0, y: 0.0, z: 0.2)
                ),
            ]
        )

        #expect(throws: FeatureEvaluationError.self) {
            try feature.validate(tolerance: .standard)
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func polySplineRejectsDuplicateControlPointOverrides() throws {
        let firstPoint = Point3D(x: 0.5, y: 0.5, z: 0.2)
        let secondPoint = Point3D(x: 0.6, y: 0.6, z: 0.4)
        let feature = PolySplineFeature(
            sourceMesh: makePolySplineQuadMesh(),
            controlPointOverrides: [
                PolySplineSurfaceControlPointOverride(
                    patchID: 0,
                    uIndex: 1,
                    vIndex: 1,
                    point: firstPoint
                ),
                PolySplineSurfaceControlPointOverride(
                    patchID: 0,
                    uIndex: 1,
                    vIndex: 1,
                    point: secondPoint
                ),
            ]
        )

        #expect(throws: FeatureEvaluationError.self) {
            try feature.validate(tolerance: .standard)
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func surfaceQueryEvaluatorResolvesPolySplineFaceSubobjects() throws {
        let evaluated = try DocumentEvaluator(tolerance: .standard).evaluate(makePolySplineQuadDocument())
        let faceName = try #require(evaluated.subshapes.entries.first { name, reference in
            reference.isFace && name.role.contains("polySpline.patch:0:face")
        }?.key)
        let surfaceReference = try stableSurfaceReference(faceName, in: evaluated)
        let evaluator = SurfaceQueryEvaluator(tolerance: .standard)

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
        let evaluated = try DocumentEvaluator(tolerance: .standard).evaluate(makePolySplineQuadDocument())
        let faceName = try #require(evaluated.subshapes.entries.first { name, reference in
            reference.isFace && name.role.contains("polySpline.patch:0:face")
        }?.key)
        let surfaceReference = try stableSurfaceReference(faceName, in: evaluated)
        let evaluator = SurfaceQueryEvaluator(tolerance: .standard)
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
        case .affine, .harmonic, .polyline, .bSpline, .sphericalGreatCircle:
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
        let evaluated = try DocumentEvaluator(tolerance: .standard).evaluate(makePolySplineQuadDocument())
        let faceName = try #require(evaluated.subshapes.entries.first { name, reference in
            reference.isFace && name.role.contains("polySpline.patch:0:face")
        }?.key)
        let surfaceReference = try stableSurfaceReference(faceName, in: evaluated)
        let evaluator = SelectionMeasurementEvaluator(tolerance: .standard)

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
        let evaluator = SurfaceQueryEvaluator(tolerance: .standard)
        try fixture.document.brep.validate(tolerance: .standard)

        let trim = try evaluator.trimCurve(
            SurfaceTrimReference(
                surface: try stableSurfaceReference(fixture.faceName, in: fixture.document),
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
        let middle = try trim.parameterCurve.parameter(
            atNormalizedFraction: 0.5,
            tolerance: .standard
        )

        #expect(curve.isRational)
        #expect(abs(middle.u - middleWeight) <= 1.0e-12)
        #expect(abs(middle.v - middleWeight) <= 1.0e-12)
        #expect(abs(trim.startParameter.u - 1.0) <= 1.0e-12)
        #expect(abs(trim.startParameter.v) <= 1.0e-12)
        #expect(abs(trim.endParameter.u) <= 1.0e-12)
        #expect(abs(trim.endParameter.v - 1.0) <= 1.0e-12)
    }

    @Test(.timeLimit(.minutes(1)))
    func selectionMeasurementEvaluatorResolvesSurfaceTrimParameterCurveKnotAndSpan() throws {
        let fixture = makeRationalSurfaceParameterTrimEvaluatedDocument()
        let surfaceReference = try stableSurfaceReference(fixture.faceName, in: fixture.document)
        let trimReference = SurfaceTrimReference(
            surface: surfaceReference,
            loopIndex: 0,
            edgeIndex: 0
        )
        let evaluator = SelectionMeasurementEvaluator(tolerance: .standard)
        let knotSelection = SelectionReference.surface(.trimKnot(SurfaceTrimKnotReference(
            trim: trimReference,
            knotIndex: 0
        )))
        let spanSelection = SelectionReference.surface(.trimSpan(SurfaceTrimSpanReference(
            trim: trimReference,
            spanIndex: 0
        )))

        let knotPoint = try evaluator.point(for: knotSelection, in: fixture.document)
        let spanPoint = try evaluator.point(for: spanSelection, in: fixture.document)
        let expectedMiddle = sqrt(0.5)

        #expect(knotPoint.selection == knotSelection)
        #expect(knotPoint.point.isApproximatelyEqual(to: Point3D(x: 1.0, y: 0.0, z: 0.0), tolerance: 1.0e-12))
        #expect((knotPoint.normal?.z ?? 0.0) > 0.0)
        #expect(knotPoint.tangent != nil)
        #expect(spanPoint.selection == spanSelection)
        #expect(spanPoint.point.isApproximatelyEqual(
            to: Point3D(x: expectedMiddle, y: expectedMiddle, z: 0.0),
            tolerance: 1.0e-12
        ))
        #expect((spanPoint.normal?.z ?? 0.0) > 0.0)
        #expect(spanPoint.tangent != nil)

        let distance = try evaluator.distance(
            from: knotSelection,
            to: spanSelection,
            in: fixture.document
        )
        #expect(abs(distance.distance - hypot(1.0 - expectedMiddle, expectedMiddle)) <= 1.0e-12)

        let angle = try evaluator.angle(
            between: knotSelection,
            and: spanSelection,
            in: fixture.document
        )
        #expect(angle.angleRadians.isFinite)
    }

    @Test(.timeLimit(.minutes(1)))
    func surfaceQueryEvaluatorProjectsPointToPolySplineUVFrame() throws {
        let evaluated = try DocumentEvaluator(tolerance: .standard).evaluate(makePolySplineQuadDocument())
        let faceName = try #require(evaluated.subshapes.entries.first { name, reference in
            reference.isFace && name.role.contains("polySpline.patch:0:face")
        }?.key)
        let surfaceReference = try stableSurfaceReference(faceName, in: evaluated)
        let evaluator = SurfaceQueryEvaluator(tolerance: .standard)
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
        let evaluated = try DocumentEvaluator(tolerance: .standard).evaluate(makePolySplineQuadDocument())
        let faceName = try #require(evaluated.subshapes.entries.first { name, reference in
            reference.isFace && name.role.contains("polySpline.patch:0:face")
        }?.key)
        let surfaceReference = try stableSurfaceReference(faceName, in: evaluated)
        let evaluator = SurfaceQueryEvaluator(tolerance: .standard)
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
        let evaluated = try DocumentEvaluator(tolerance: .standard).evaluate(makeCircleExtrudeDocument())
        let faceName = try #require(evaluated.subshapes.entries.first { _, reference in
            guard case let .face(faceID) = reference,
                  let face = evaluated.brep.faces[faceID],
                  let surface = evaluated.brep.geometry.surfaces[face.surfaceID],
                  case .cylinder = surface else {
                return false
            }
            return true
        }?.key)
        let surfaceReference = try stableSurfaceReference(faceName, in: evaluated)
        let evaluator = SurfaceQueryEvaluator(tolerance: .standard)

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
        let evaluated = try DocumentEvaluator(tolerance: .standard).evaluate(makeCircleExtrudeDocument())
        let faceName = try #require(evaluated.subshapes.entries.first { _, reference in
            guard case let .face(faceID) = reference,
                  let face = evaluated.brep.faces[faceID],
                  let surface = evaluated.brep.geometry.surfaces[face.surfaceID],
                  case .cylinder = surface else {
                return false
            }
            return true
        }?.key)
        let surfaceReference = try stableSurfaceReference(faceName, in: evaluated)
        let evaluator = SurfaceQueryEvaluator(tolerance: .standard)

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
        let targetFaceName = testSubshapeID(extrudeFeatureID, .startFace)
        let source = try DocumentEvaluator(tolerance: .standard).evaluate(document)
        let offsetFeature = FeatureNode(
            id: offsetFeatureID,
            operation: .faceLoopOffset(
                FaceLoopOffsetFeature(
                    target: FaceLoopOffsetTargetReference(featureID: extrudeFeatureID),
                    face: try stableSubshapeReference(targetFaceName, in: source),
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

        let evaluated = try DocumentEvaluator(tolerance: .standard).evaluate(document)
        let centerFaceName = semanticSubshapeID(
            offsetFeatureID,
            generatedRole: "faceLoopOffset",
            semanticRole: "centerFace"
        )
        let surfaceReference = try stableSurfaceReference(centerFaceName, in: evaluated)
        let evaluator = SurfaceQueryEvaluator(tolerance: .standard)

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
        let evaluated = try DocumentEvaluator(tolerance: .standard).evaluate(makeRectangleExtrudeDocument(documentUnits: .meters))
        let faceName = testSubshapeID(
            try #require(evaluated.document.designGraph.order.last),
            .startFace
        )
        let surfaceReference = try stableSurfaceReference(faceName, in: evaluated)
        let evaluator = SurfaceQueryEvaluator(tolerance: .standard)

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
        let analysis = PolySplineMeshAnalyzer().analyze(
            mesh: makePolySplineQuadMesh(),
            tolerance: .standard
        )

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
            options: PolySplineOptions(roundedCorners: true),
            tolerance: .standard
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
        let analysis = PolySplineMeshAnalyzer().analyze(
            mesh: makePolySplinePatchNetworkMesh(),
            tolerance: .standard
        )

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
            options: PolySplineOptions(mergePatches: false),
            tolerance: .standard
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

private func subshapeRoleString(_ subshapeID: SubshapeID) -> String {
    subshapeID.role
}

private func lengthInMeters(_ value: Double, unit: LengthUnit) -> Double {
    unit.toInternal(value)
}

private struct IncompleteSubshapeFeatureEvaluator: FeatureEvaluating {
    func evaluate(feature: FeatureNode, context: EvaluationContext) throws -> EvaluationResult {
        var result = try PlanarExtrudeFeatureEvaluator().evaluate(feature: feature, context: context)
        if let subshapeID = result.subshapes.keys.first {
            result.subshapes.removeValue(forKey: subshapeID)
        }
        return result
    }
}

private struct EmptyTessellator: Tessellating {
    func tessellate(model: BRepModel, options: TessellationOptions) throws -> [BodyID: Mesh] {
        [:]
    }
}

private func makePolySplineQuadDocument(
    indices: [UInt32] = [0, 1, 2, 0, 2, 3],
    controlPointOverrides: [PolySplineSurfaceControlPointOverride] = []
) -> CADDocument {
    let featureID = FeatureID()
    let feature = FeatureNode(
        id: featureID,
        name: "Quad PolySpline",
        operation: .polySpline(PolySplineFeature(
            sourceMesh: makePolySplineQuadMesh(indices: indices),
            controlPointOverrides: controlPointOverrides
        )),
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

private func makeBSplineSurfaceDocument(
    surface: BSplineSurface3D,
    outerTrimDomain: BSplineSurfaceTrimDomain? = nil,
    trimLoops: [BSplineSurfaceTrimLoop] = []
) -> CADDocument {
    let featureID = FeatureID()
    let feature = FeatureNode(
        id: featureID,
        name: "Direct B-spline Surface",
        operation: .bSplineSurface(BSplineSurfaceFeature(
            surface: surface,
            outerTrimDomain: outerTrimDomain,
            trimLoops: trimLoops
        )),
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

private func makeBSplineSurfaceFeatureSurface() -> BSplineSurface3D {
    let base = BSplineSurface3D.cubicBezierPatch(
        bottomLeft: Point3D(x: 0.0, y: 0.0, z: 0.0),
        bottomRight: Point3D(x: 2.0, y: 0.0, z: 0.0),
        topRight: Point3D(x: 2.0, y: 1.5, z: 0.0),
        topLeft: Point3D(x: 0.0, y: 1.5, z: 0.0)
    )
    var weights = base.weights
    weights[1][1] = 2.0
    return BSplineSurface3D(
        uDegree: base.uDegree,
        vDegree: base.vDegree,
        uKnots: base.uKnots,
        vKnots: base.vKnots,
        controlPoints: base.controlPoints,
        weights: weights
    )
}

private func makeLinearBSplineSurfaceFeatureSurface() -> BSplineSurface3D {
    BSplineSurface3D.cubicBezierPatch(
        bottomLeft: Point3D(x: 0.0, y: 0.0, z: 0.0),
        bottomRight: Point3D(x: 2.0, y: 0.0, z: 0.0),
        topRight: Point3D(x: 2.0, y: 1.5, z: 0.0),
        topLeft: Point3D(x: 0.0, y: 1.5, z: 0.0)
    )
}

private func parameter(linearSurfacePoint point: Point3D) -> SurfaceParameter {
    SurfaceParameter(u: point.x / 2.0, v: point.y / 1.5)
}

private func meshTriangleCentroid(at triangleIndex: Int, in mesh: Mesh) -> Point3D {
    let first = mesh.positions[Int(mesh.indices[triangleIndex])]
    let second = mesh.positions[Int(mesh.indices[triangleIndex + 1])]
    let third = mesh.positions[Int(mesh.indices[triangleIndex + 2])]
    return Point3D(
        x: (first.x + second.x + third.x) / 3.0,
        y: (first.y + second.y + third.y) / 3.0,
        z: (first.z + second.z + third.z) / 3.0
    )
}

private func meshParameterArea(in mesh: Mesh) -> Double {
    var area = 0.0
    for triangleIndex in stride(from: 0, to: mesh.indices.count, by: 3) {
        let first = parameter(linearSurfacePoint: mesh.positions[Int(mesh.indices[triangleIndex])])
        let second = parameter(linearSurfacePoint: mesh.positions[Int(mesh.indices[triangleIndex + 1])])
        let third = parameter(linearSurfacePoint: mesh.positions[Int(mesh.indices[triangleIndex + 2])])
        area += abs(parameterTriangleSignedArea(first, second, third))
    }
    return area
}

private func parameterTriangleArea(_ triangle: [SurfaceParameter]) -> Double {
    guard triangle.count == 3 else {
        return 0.0
    }
    return abs(parameterTriangleSignedArea(triangle[0], triangle[1], triangle[2]))
}

private func triangularInnerTrimLoop(_ triangle: [SurfaceParameter]) -> BSplineSurfaceTrimLoop {
    BSplineSurfaceTrimLoop(
        role: .inner,
        edges: [
            BSplineSurfaceTrimEdge(parameterCurve: .polyline([triangle[0], triangle[1]])),
            BSplineSurfaceTrimEdge(parameterCurve: .polyline([triangle[1], triangle[2]])),
            BSplineSurfaceTrimEdge(parameterCurve: .polyline([triangle[2], triangle[0]])),
        ]
    )
}

private func parameterTriangleSignedArea(
    _ first: SurfaceParameter,
    _ second: SurfaceParameter,
    _ third: SurfaceParameter
) -> Double {
    0.5 * (
        (first.u * (second.v - third.v))
            + (second.u * (third.v - first.v))
            + (third.u * (first.v - second.v))
    )
}

private extension SurfaceParameter {
    func isInsideOrOnTriangle(_ triangle: [SurfaceParameter], tolerance: Double) -> Bool {
        guard triangle.count == 3 else {
            return false
        }
        let first = signedArea(from: triangle[0], to: triangle[1], point: self)
        let second = signedArea(from: triangle[1], to: triangle[2], point: self)
        let third = signedArea(from: triangle[2], to: triangle[0], point: self)
        let hasNegative = first < -tolerance || second < -tolerance || third < -tolerance
        let hasPositive = first > tolerance || second > tolerance || third > tolerance
        return (hasNegative && hasPositive) == false
    }

    private func signedArea(
        from start: SurfaceParameter,
        to end: SurfaceParameter,
        point: SurfaceParameter
    ) -> Double {
        ((end.u - start.u) * (point.v - start.v)) - ((end.v - start.v) * (point.u - start.u))
    }
}

private func makeRationalSurfaceParameterTrimEvaluatedDocument() -> (
    document: EvaluatedDocument,
    faceName: SubshapeID
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
            Coedge(edgeID: curvedEdgeID, orientation: .forward, surfaceParameterCurve: uvTrimCurve),
            Coedge(edgeID: leftEdgeID, orientation: .forward),
            Coedge(edgeID: bottomEdgeID, orientation: .forward),
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
    let faceName = SubshapeID(
        featureID: FeatureID(),
        role: "rationalSurfaceParameterTrim.face",
        ordinal: 0
    )
    return (
        EvaluatedDocument(
            document: CADDocument(units: .meters),
            parameters: ResolvedParameterTable(),
            brep: brep,
            meshes: [:],
            caches: DocumentCaches(),
            subshapes: SubshapeIndex([faceName: .face(faceID)]),
            configuration: DocumentEvaluationConfiguration(
                tolerance: .standard,
                tessellationOptions: .standard
            )
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
        throw KernelError.unsupportedEvaluation(tolerance: .standard, message: "Expected a B-spline surface.")
    }
    return bSpline
}

private func plane(named subshapeID: SubshapeID, in document: EvaluatedDocument) throws -> Plane3D {
    guard case let .face(faceID) = try #require(document.subshapes[subshapeID]),
          let face = document.brep.faces[faceID],
          let surface = document.brep.geometry.surfaces[face.surfaceID],
          case let .plane(plane) = surface else {
        Issue.record("Expected generated face to resolve to a planar surface.")
        throw KernelError.unsupportedEvaluation(tolerance: .standard, message: "Expected generated face to resolve to a planar surface.")
    }
    return plane
}

private func plane(
    resolving reference: StableSubshapeReference,
    in document: EvaluatedDocument
) throws -> Plane3D {
    let topologyReference = try StableSubshapeResolver().topologyReference(
        for: reference,
        model: document.brep,
        subshapes: document.subshapes,
        lineage: document.lineage,
        tolerance: .standard
    )
    guard case let .face(faceID) = topologyReference,
          let face = document.brep.faces[faceID],
          let surface = document.brep.geometry.surfaces[face.surfaceID],
          case let .plane(plane) = surface else {
        Issue.record("Expected stable face reference to resolve to a planar surface.")
        throw KernelError.unsupportedEvaluation(tolerance: .standard, message: "Expected stable face reference to resolve to a planar surface.")
    }
    return plane
}

func makeRectangleExtrudeDocument(
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

private func signedMeshVolume(_ mesh: Mesh) -> Double {
    guard let origin = mesh.positions.first else {
        return 0.0
    }
    var signedVolume = 0.0
    var index = 0
    while index + 2 < mesh.indices.count {
        let first = mesh.positions[Int(mesh.indices[index])] - origin
        let second = mesh.positions[Int(mesh.indices[index + 1])] - origin
        let third = mesh.positions[Int(mesh.indices[index + 2])] - origin
        signedVolume += first.dot(second.cross(third)) / 6.0
        index += 3
    }
    return signedVolume
}

private func makeNotchedRectangleExtrudeDocument() -> CADDocument {
    let sketchFeatureID = FeatureID()
    let extrudeFeatureID = FeatureID()
    let sketchFeature = FeatureNode(
        id: sketchFeatureID,
        operation: .sketch(notchedRectangleSketch()),
        outputs: [FeatureOutput(role: .profile)]
    )
    let extrudeFeature = FeatureNode(
        id: extrudeFeatureID,
        operation: .extrude(ExtrudeFeature(
            profile: ProfileReference(featureID: sketchFeatureID),
            distance: .constant(.length(10.0, unit: .millimeter))
        )),
        inputs: [FeatureInput(featureID: sketchFeatureID, role: .profile)],
        outputs: [FeatureOutput(role: .body)]
    )
    return CADDocument(
        units: .millimeters,
        designGraph: DesignGraph(
            nodes: [
                sketchFeatureID: sketchFeature,
                extrudeFeatureID: extrudeFeature,
            ],
            order: [sketchFeatureID, extrudeFeatureID],
            dependencies: [DependencyEdge(source: sketchFeatureID, target: extrudeFeatureID)],
            revision: DocumentRevision(2)
        )
    )
}

private func notchedRectangleSketch() -> Sketch {
    func point(_ x: Double, _ y: Double) -> SketchPoint {
        SketchPoint(
            x: .constant(.length(x, unit: .millimeter)),
            y: .constant(.length(y, unit: .millimeter))
        )
    }
    func line(_ start: SketchPoint, _ end: SketchPoint) -> SketchEntity {
        .line(SketchLine(start: start, end: end))
    }
    // 40 x 20 mm rectangle whose top edge carries a semicircular notch of
    // radius 5 mm centered at (20, 20) biting down into the material. The
    // stored arc runs counterclockwise from (15, 20) through (20, 15) to
    // (25, 20); the loop orderer reverses it into the counterclockwise
    // outline, so the extracted profile carries a negative (concave) sweep.
    return Sketch(
        plane: .xy,
        entities: [
            SketchEntityID(): line(point(0.0, 0.0), point(40.0, 0.0)),
            SketchEntityID(): line(point(40.0, 0.0), point(40.0, 20.0)),
            SketchEntityID(): line(point(40.0, 20.0), point(25.0, 20.0)),
            SketchEntityID(): .arc(SketchArc(
                center: point(20.0, 20.0),
                radius: .constant(.length(5.0, unit: .millimeter)),
                startAngle: .constant(.angle(180.0, unit: .degree)),
                endAngle: .constant(.angle(360.0, unit: .degree))
            )),
            SketchEntityID(): line(point(15.0, 20.0), point(0.0, 20.0)),
            SketchEntityID(): line(point(0.0, 20.0), point(0.0, 0.0)),
        ]
    )
}

private func makeRingRectangleRevolveDocument(
    angle: CADExpression = .constant(.angle(360.0, unit: .degree))
) -> CADDocument {
    let sketchFeatureID = FeatureID()
    let revolveFeatureID = FeatureID()
    let sketchFeature = FeatureNode(
        id: sketchFeatureID,
        operation: .sketch(ringRectangleRevolveSketch()),
        outputs: [FeatureOutput(role: .profile)]
    )
    let revolveFeature = FeatureNode(
        id: revolveFeatureID,
        operation: .revolve(RevolveFeature(
            profile: ProfileReference(featureID: sketchFeatureID),
            axis: RevolveAxis(origin: .origin, direction: .unitY),
            angle: angle
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

private func ringRectangleRevolveSketch() -> Sketch {
    func point(_ x: Double, _ y: Double) -> SketchPoint {
        SketchPoint(
            x: .constant(.length(x, unit: .meter)),
            y: .constant(.length(y, unit: .meter))
        )
    }
    let innerBottom = point(0.015, -0.015)
    let outerBottom = point(0.025, -0.015)
    let outerTop = point(0.025, 0.015)
    let innerTop = point(0.015, 0.015)
    let bottomID = SketchEntityID()
    let outerID = SketchEntityID()
    let topID = SketchEntityID()
    let innerID = SketchEntityID()
    return Sketch(
        plane: .xy,
        entities: [
            bottomID: .line(SketchLine(start: innerBottom, end: outerBottom)),
            outerID: .line(SketchLine(start: outerBottom, end: outerTop)),
            topID: .line(SketchLine(start: outerTop, end: innerTop)),
            innerID: .line(SketchLine(start: innerTop, end: innerBottom)),
        ],
        constraints: [
            .coincident(.lineEnd(bottomID), .lineStart(outerID)),
            .coincident(.lineEnd(outerID), .lineStart(topID)),
            .coincident(.lineEnd(topID), .lineStart(innerID)),
            .coincident(.lineEnd(innerID), .lineStart(bottomID)),
        ],
        dimensions: []
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

private func makeChainedOrthogonalBooleanDocument() -> (
    document: CADDocument,
    firstBooleanID: FeatureID,
    secondBooleanID: FeatureID
) {
    let targetProfileID = FeatureID()
    let targetID = FeatureID()
    let firstToolProfileID = FeatureID()
    let firstToolID = FeatureID()
    let firstBooleanID = FeatureID()
    let secondToolProfileID = FeatureID()
    let secondToolID = FeatureID()
    let secondBooleanID = FeatureID()
    let depth = 10.0
    let targetProfile = FeatureNode(
        id: targetProfileID,
        operation: .sketch(offsetRectangleSketch(
            width: 40.0,
            height: 40.0,
            centerX: 0.0,
            centerY: 0.0,
            unit: .millimeter
        )),
        outputs: [FeatureOutput(role: .profile)]
    )
    let target = FeatureNode(
        id: targetID,
        operation: .extrude(ExtrudeFeature(
            profile: ProfileReference(featureID: targetProfileID),
            distance: .constant(.length(depth, unit: .millimeter))
        )),
        inputs: [FeatureInput(featureID: targetProfileID, role: .profile)],
        outputs: [FeatureOutput(role: .body)]
    )
    let firstToolProfile = FeatureNode(
        id: firstToolProfileID,
        operation: .sketch(offsetRectangleSketch(
            width: 30.0,
            height: 30.0,
            centerX: 10.0,
            centerY: 10.0,
            unit: .millimeter
        )),
        outputs: [FeatureOutput(role: .profile)]
    )
    let firstTool = FeatureNode(
        id: firstToolID,
        operation: .extrude(ExtrudeFeature(
            profile: ProfileReference(featureID: firstToolProfileID),
            distance: .constant(.length(depth, unit: .millimeter))
        )),
        inputs: [FeatureInput(featureID: firstToolProfileID, role: .profile)],
        outputs: [FeatureOutput(role: .body)]
    )
    let firstBoolean = FeatureNode(
        id: firstBooleanID,
        operation: .boolean(BooleanFeature(
            targets: [BooleanTargetReference(featureID: targetID)],
            tool: BooleanToolReference(featureID: firstToolID),
            operation: .difference
        )),
        inputs: [
            FeatureInput(featureID: targetID, role: .target),
            FeatureInput(featureID: firstToolID, role: .body),
        ],
        outputs: [FeatureOutput(role: .body)]
    )
    let secondToolProfile = FeatureNode(
        id: secondToolProfileID,
        operation: .sketch(offsetRectangleSketch(
            width: 10.0,
            height: 20.0,
            centerX: -15.0,
            centerY: -10.0,
            unit: .millimeter
        )),
        outputs: [FeatureOutput(role: .profile)]
    )
    let secondTool = FeatureNode(
        id: secondToolID,
        operation: .extrude(ExtrudeFeature(
            profile: ProfileReference(featureID: secondToolProfileID),
            distance: .constant(.length(depth, unit: .millimeter))
        )),
        inputs: [FeatureInput(featureID: secondToolProfileID, role: .profile)],
        outputs: [FeatureOutput(role: .body)]
    )
    let secondBoolean = FeatureNode(
        id: secondBooleanID,
        operation: .boolean(BooleanFeature(
            targets: [BooleanTargetReference(featureID: firstBooleanID)],
            tool: BooleanToolReference(featureID: secondToolID),
            operation: .difference
        )),
        inputs: [
            FeatureInput(featureID: firstBooleanID, role: .target),
            FeatureInput(featureID: secondToolID, role: .body),
        ],
        outputs: [FeatureOutput(role: .body)]
    )
    let designGraph = DesignGraph(
        nodes: [
            targetProfileID: targetProfile,
            targetID: target,
            firstToolProfileID: firstToolProfile,
            firstToolID: firstTool,
            firstBooleanID: firstBoolean,
            secondToolProfileID: secondToolProfile,
            secondToolID: secondTool,
            secondBooleanID: secondBoolean,
        ],
        order: [
            targetProfileID,
            targetID,
            firstToolProfileID,
            firstToolID,
            firstBooleanID,
            secondToolProfileID,
            secondToolID,
            secondBooleanID,
        ],
        dependencies: [
            DependencyEdge(source: targetProfileID, target: targetID),
            DependencyEdge(source: firstToolProfileID, target: firstToolID),
            DependencyEdge(source: targetID, target: firstBooleanID),
            DependencyEdge(source: firstToolID, target: firstBooleanID),
            DependencyEdge(source: secondToolProfileID, target: secondToolID),
            DependencyEdge(source: firstBooleanID, target: secondBooleanID),
            DependencyEdge(source: secondToolID, target: secondBooleanID),
        ],
        revision: DocumentRevision(8)
    )
    return (
        document: CADDocument(units: .millimeters, designGraph: designGraph),
        firstBooleanID: firstBooleanID,
        secondBooleanID: secondBooleanID
    )
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
    guideSketch: Sketch? = nil,
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
        operation: .sketch(guideSketch ?? straightLinePathSketch(
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

private func makeOffCenterPathSweepDocument(
    isCurved: Bool,
    unit: LengthUnit = .millimeter
) -> CADDocument {
    let profileFeatureID = FeatureID()
    let pathFeatureID = FeatureID()
    let sweepFeatureID = FeatureID()
    let pathSketch: Sketch
    if isCurved {
        // .zx-plane arc, center (0, 90) mm, radius 60 mm, 270 -> 300 degrees:
        // world start (0.030, 0, 0), start tangent +Z, bending 30 degrees
        // toward +X; the curvature center clears the profile so the sweep
        // builds cleanly.
        pathSketch = Sketch(
            plane: .zx,
            entities: [
                SketchEntityID(): .arc(SketchArc(
                    center: SketchPoint(
                        x: .constant(.length(0.0, unit: unit)),
                        y: .constant(.length(90.0, unit: unit))
                    ),
                    radius: .constant(.length(60.0, unit: unit)),
                    startAngle: .constant(.angle(270.0, unit: .degree)),
                    endAngle: .constant(.angle(300.0, unit: .degree))
                ))
            ]
        )
    } else {
        pathSketch = Sketch(
            plane: .zx,
            entities: [
                SketchEntityID(): .line(SketchLine(
                    start: SketchPoint(
                        x: .constant(.length(0.0, unit: unit)),
                        y: .constant(.length(30.0, unit: unit))
                    ),
                    end: SketchPoint(
                        x: .constant(.length(10.0, unit: unit)),
                        y: .constant(.length(30.0, unit: unit))
                    )
                ))
            ]
        )
    }
    let profileFeature = FeatureNode(
        id: profileFeatureID,
        operation: .sketch(constantRectangleSketch(
            centerX: 30.0,
            centerY: 0.0,
            width: 40.0,
            height: 20.0,
            unit: unit
        )),
        outputs: [
            FeatureOutput(role: .profile),
            FeatureOutput(role: .curve),
        ]
    )
    let pathFeature = FeatureNode(
        id: pathFeatureID,
        operation: .sketch(pathSketch),
        outputs: [FeatureOutput(role: .curve)]
    )
    let sweepFeature = FeatureNode(
        id: sweepFeatureID,
        operation: .sweep(SweepFeature(
            sections: [.profile(ProfileReference(featureID: profileFeatureID))],
            path: SweepPathReference(featureID: pathFeatureID),
            options: SweepOptions(alignment: .parallel)
        )),
        inputs: [
            FeatureInput(featureID: profileFeatureID, role: .profile),
            FeatureInput(featureID: pathFeatureID, role: .path),
        ],
        outputs: [FeatureOutput(role: .body)]
    )
    return CADDocument(
        units: .millimeters,
        designGraph: DesignGraph(
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
    )
}

private func constantRectangleSketch(
    centerX: Double,
    centerY: Double,
    width: Double,
    height: Double,
    unit: LengthUnit
) -> Sketch {
    func point(_ x: Double, _ y: Double) -> SketchPoint {
        SketchPoint(
            x: .constant(.length(x, unit: unit)),
            y: .constant(.length(y, unit: unit))
        )
    }
    let bottomLeft = point(centerX - width / 2.0, centerY - height / 2.0)
    let bottomRight = point(centerX + width / 2.0, centerY - height / 2.0)
    let topRight = point(centerX + width / 2.0, centerY + height / 2.0)
    let topLeft = point(centerX - width / 2.0, centerY + height / 2.0)
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

private func makeCurvedPathSweepDocument(
    width: Double = 40.0,
    height: Double = 20.0,
    radius: Double = 10.0,
    unit: LengthUnit = .millimeter,
    documentUnits: UnitSystem = .millimeters,
    options: SweepOptions = SweepOptions(),
    pathSketch: Sketch? = nil
) -> CADDocument {
    // The default arc path starts at plane coordinates (0, radius); the
    // profile is drawn there so it sits on the path start under the rebased
    // placement semantics. A custom pathSketch is expected to start at the
    // plane origin and keeps the origin-centered profile.
    let profileCenterY = pathSketch == nil ? radius : 0.0
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
        operation: .sketch(rectangleSketch(
            widthID: widthID,
            heightID: heightID,
            plane: .xy,
            centerY: profileCenterY,
            centerYUnit: unit
        )),
        outputs: [
            FeatureOutput(role: .profile),
            FeatureOutput(role: .curve),
        ]
    )
    let pathFeature = FeatureNode(
        id: pathFeatureID,
        operation: .sketch(pathSketch ?? curvedArcPathSketch(radius: radius, unit: unit)),
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
        operation: .sketch(rectangleSketch(
            widthID: widthID,
            heightID: heightID,
            plane: .xy,
            centerY: radius,
            centerYUnit: unit
        )),
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
    unit: LengthUnit = .millimeter
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
        continuityTolerances: .standard(modelingTolerance: .standard)
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

private func descendingCurvedArcPathSketch(radius: Double, unit: LengthUnit) -> Sketch {
    // .yz-plane arc sampled counterclockwise from 90 to 180 degrees: the world
    // path starts at z = +radius and descends to z = 0, so every sampled span
    // advances against the .xy profile's +Z winding normal.
    Sketch(
        plane: .yz,
        entities: [
            SketchEntityID(): .arc(SketchArc(
                center: SketchPoint(
                    x: .constant(.length(0.0, unit: unit)),
                    y: .constant(.length(0.0, unit: unit))
                ),
                radius: .constant(.length(radius, unit: unit)),
                startAngle: .constant(.angle(90.0, unit: .degree)),
                endAngle: .constant(.angle(180.0, unit: .degree))
            ))
        ]
    )
}

private func risingAndFallingArcPathSketch(radius: Double, unit: LengthUnit) -> Sketch {
    // 0 -> 180 degrees on .yz: z rises to +radius then falls back to 0,
    // flipping the per-span advance sign against the .xy profile normal.
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
                endAngle: .constant(.angle(180.0, unit: .degree))
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

private func lineLoopSketch(_ points: [Point2D], unit: LengthUnit = .meter) -> Sketch {
    lineLoopSketches([points], unit: unit)
}

private func lineLoopSketches(_ loops: [[Point2D]], unit: LengthUnit = .meter) -> Sketch {
    var entities: [SketchEntityID: SketchEntity] = [:]
    for loop in loops {
        guard loop.count >= 2 else {
            continue
        }
        for index in loop.indices {
            let start = loop[index]
            let end = loop[(index + 1) % loop.count]
            entities[SketchEntityID()] = .line(SketchLine(
                start: SketchPoint(
                    x: .constant(.length(start.x, unit: unit)),
                    y: .constant(.length(start.y, unit: unit))
                ),
                end: SketchPoint(
                    x: .constant(.length(end.x, unit: unit)),
                    y: .constant(.length(end.y, unit: unit))
                )
            ))
        }
    }
    return Sketch(plane: .xy, entities: entities)
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

private func makeRoundedCornerExtrudeDocument(
    radius: Double,
    depth: Double,
    unit: LengthUnit = .meter,
    documentUnits: UnitSystem = .meters
) -> CADDocument {
    let sketchFeatureID = FeatureID()
    let extrudeFeatureID = FeatureID()
    let sketchFeature = FeatureNode(
        id: sketchFeatureID,
        operation: .sketch(roundedCornerSketch(radius: radius, unit: unit)),
        outputs: [FeatureOutput(role: .profile)]
    )
    let extrudeFeature = FeatureNode(
        id: extrudeFeatureID,
        operation: .extrude(ExtrudeFeature(
            profile: ProfileReference(featureID: sketchFeatureID),
            distance: .constant(.length(depth, unit: unit)),
            direction: .normal
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

private func roundedCornerSketch(radius: Double = 1.0, unit: LengthUnit = .meter) -> Sketch {
    let bottomID = SketchEntityID()
    let arcID = SketchEntityID()
    let rightID = SketchEntityID()
    let topID = SketchEntityID()
    let leftID = SketchEntityID()

    let bottomLeft = SketchPoint(x: .constant(.length(0.0, unit: unit)), y: .constant(.length(0.0, unit: unit)))
    let arcStart = SketchPoint(x: .constant(.length(radius, unit: unit)), y: .constant(.length(0.0, unit: unit)))
    let arcEnd = SketchPoint(x: .constant(.length(radius * 2.0, unit: unit)), y: .constant(.length(radius, unit: unit)))
    let topRight = SketchPoint(
        x: .constant(.length(radius * 2.0, unit: unit)),
        y: .constant(.length(radius * 2.0, unit: unit))
    )
    let topLeft = SketchPoint(x: .constant(.length(0.0, unit: unit)), y: .constant(.length(radius * 2.0, unit: unit)))

    return Sketch(
        plane: .xy,
        entities: [
            bottomID: .line(SketchLine(start: bottomLeft, end: arcStart)),
            arcID: .arc(SketchArc(
                center: SketchPoint(
                    x: .constant(.length(radius, unit: unit)),
                    y: .constant(.length(radius, unit: unit))
                ),
                radius: .constant(.length(radius, unit: unit)),
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
    clockwise: Bool = false,
    centerY: Double = 0.0,
    centerYUnit: LengthUnit = .millimeter
) -> Sketch {
    let two = CADExpression.constant(.scalar(2.0))
    let minusOne = CADExpression.constant(.scalar(-1.0))
    let halfWidth = CADExpression.divide(.reference(widthID), two)
    let halfHeight = CADExpression.divide(.reference(heightID), two)
    let negativeHalfWidth = CADExpression.multiply(minusOne, halfWidth)
    let negativeHalfHeight = CADExpression.multiply(minusOne, halfHeight)
    let lowY: CADExpression
    let highY: CADExpression
    if centerY == 0.0 {
        lowY = negativeHalfHeight
        highY = halfHeight
    } else {
        let offset = CADExpression.constant(.length(centerY, unit: centerYUnit))
        lowY = .add(offset, negativeHalfHeight)
        highY = .add(offset, halfHeight)
    }
    let bottomLeft = SketchPoint(x: negativeHalfWidth, y: lowY)
    let bottomRight = SketchPoint(x: halfWidth, y: lowY)
    let topRight = SketchPoint(x: halfWidth, y: highY)
    let topLeft = SketchPoint(x: negativeHalfWidth, y: highY)
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
    for subshapeID: SubshapeID,
    in evaluated: EvaluatedDocument
) throws -> Vector3D {
    guard case .face(let faceID) = try #require(evaluated.subshapes[subshapeID]) else {
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
    guard case let .face(faceID) = evaluated.subshapes[testSubshapeID(featureID, role)] else {
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

private func stableEdgeReference(
    _ subshapeID: SubshapeID,
    in document: EvaluatedDocument
) throws -> EdgeReference {
    EdgeReference(subshape: try document.stableSubshapeReference(for: subshapeID))
}

private func stableSubshapeReference(
    _ subshapeID: SubshapeID,
    in document: EvaluatedDocument
) throws -> StableSubshapeReference {
    try document.stableSubshapeReference(for: subshapeID)
}

private func stableSurfaceReference(
    _ subshapeID: SubshapeID,
    in document: EvaluatedDocument
) throws -> SurfaceReference {
    SurfaceReference(subshape: try document.stableSubshapeReference(for: subshapeID))
}

private func testSubshapeID(
    _ featureID: FeatureID,
    _ role: GeneratedSubshapeRole,
    ordinal: Int = 0
) -> SubshapeID {
    SubshapeID(featureID: featureID, role: role.rawValue, ordinal: ordinal)
}

private func semanticSubshapeID(
    _ featureID: FeatureID,
    generatedRole: String,
    semanticRole: String,
    ordinal: Int = 0
) -> SubshapeID {
    SubshapeID(
        featureID: featureID,
        role: "\(generatedRole).\(semanticRole)",
        ordinal: ordinal
    )
}

private func replacing(
    _ evaluated: EvaluatedDocument,
    document: CADDocument? = nil,
    brep: BRepModel? = nil,
    meshes: PersistentMap<BodyID, Mesh>? = nil,
    caches: DocumentCaches? = nil,
    subshapes: SubshapeIndex? = nil
) -> EvaluatedDocument {
    EvaluatedDocument(
        document: document ?? evaluated.document,
        parameters: evaluated.parameters,
        brep: brep ?? evaluated.brep,
        meshes: meshes ?? evaluated.meshes,
        curves: evaluated.curves,
        caches: caches ?? evaluated.caches,
        subshapes: subshapes ?? evaluated.subshapes,
        lineage: evaluated.lineage,
        configuration: evaluated.configuration,
        evaluationMetrics: evaluated.evaluationMetrics
    )
}
