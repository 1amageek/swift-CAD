import Foundation
import Testing
@testable import SwiftCAD
import CADTopology

private func collectBytes(_ operation: (any ByteSink) throws -> Void) throws -> Data {
    let sink = DataByteSink()
    try operation(sink)
    return sink.bytes
}

private extension CADPipeline {
    func exportBinarySTL(from evaluatedDocument: EvaluatedDocument, lengthUnit: LengthUnit = .meter) throws -> Data {
        try collectBytes { try writeBinarySTL(from: evaluatedDocument, lengthUnit: lengthUnit, to: $0) }
    }

    func packageData(for document: CADDocument) throws -> Data {
        try collectBytes { try writePackage(for: document, to: $0) }
    }

    func loadDocument(fromPackageData data: Data) throws -> CADDocument {
        try loadDocument(from: BorrowedBytes(data))
    }
}

@Suite("SwiftCAD facade")
struct SwiftCADTests {
    @Test(.timeLimit(.minutes(1)))
    func facadeBuildsEvaluatesExportsAndRoundTripsOfficialPipeline() throws {
        let document = try CADDocument.millimeters(tolerance: .standard, named: "Box") { cad in
            let width = try cad.lengthParameter(named: "width", 40.0)
            let height = try cad.lengthParameter(named: "height", 20.0)
            let depth = try cad.lengthParameter(named: "depth", 10.0)

            let profile = try cad.sketch(on: .xy, named: "Base sketch") { sketch in
                sketch.rectangle(width: .parameter(width), height: .parameter(height))
            }

            try cad.extrude(profile, distance: depth, named: "Extrude")
        }

        let pipeline = CADPipeline(tolerance: .standard)
        let evaluated = try pipeline.evaluate(document)
        #expect(evaluated.brep.bodies.count == 1)
        #expect(evaluated.brep.faces.count == 6)
        #expect(evaluated.meshes.values.first?.indices.count == 36)
        #expect(evaluated.caches.brep?.parameterRevision == document.parameters.revision)

        let stl = try pipeline.exportBinarySTL(from: evaluated, lengthUnit: .millimeter)
        #expect(stl.count == 84 + 12 * 50)

        let packageData = try pipeline.packageData(for: document)
        let loaded = try pipeline.loadDocument(fromPackageData: packageData)
        #expect(loaded.metadata.name == "Box")
        #expect(loaded.designGraph.order.count == 2)
        #expect(loaded.parameters.parameters.count == 3)
    }

    @Test(.timeLimit(.minutes(1)))
    func facadeBuildsBridgeCurveSweepThroughSharedOperations() throws {
        let document = try CADDocument.millimeters(tolerance: .standard, named: "Bridge Sweep") { cad in
            let width = try cad.lengthParameter(named: "width", 40.0)
            let height = try cad.lengthParameter(named: "height", 20.0)

            let profile = try cad.sketch(on: .xy, named: "Profile") { sketch in
                sketch.rectangle(width: .parameter(width), height: .parameter(height))
            }
            let startSource = try cad.sketch(on: .zx, named: "Bridge start source") { sketch in
                sketch.line(
                    from: bridgePoint(-10.0, 0.0),
                    to: bridgePoint(0.0, 0.0)
                )
            }
            let endSource = try cad.sketch(on: .zx, named: "Bridge end source") { sketch in
                sketch.line(
                    from: bridgePoint(10.0, 0.0),
                    to: bridgePoint(20.0, 0.0)
                )
            }
            let path = try cad.bridgeCurve(
                from: BridgeCurveEndpointReference(
                    curve: CurveOutputReference(featureID: startSource.featureID),
                    end: .end,
                    requiredLevel: .tangent
                ),
                to: BridgeCurveEndpointReference(
                    curve: CurveOutputReference(featureID: endSource.featureID),
                    end: .start,
                    requiredLevel: .tangent
                ),
                continuityTolerances: .standard(modelingTolerance: .standard),
                named: "Bridge path"
            )

            try cad.sweep(profile, along: path, named: "Sweep")
        }

        let pipeline = CADPipeline(tolerance: .standard)
        let evaluated = try pipeline.evaluate(document)
        #expect(evaluated.brep.bodies.count == 1)
        #expect(evaluated.brep.faces.count == 6)

        let packageData = try pipeline.packageData(for: document)
        let loaded = try pipeline.loadDocument(fromPackageData: packageData)
        #expect(loaded.metadata.name == "Bridge Sweep")
        #expect(loaded.designGraph.order.count == 5)
    }

    @Test(.timeLimit(.minutes(1)))
    func facadeBuildsCurveEditSweepThroughSharedOperations() throws {
        var editedPathID: FeatureID?
        let document = try CADDocument.millimeters(tolerance: .standard, named: "Edited Curve Sweep") { cad in
            let width = try cad.lengthParameter(named: "width", 8.0)
            let height = try cad.lengthParameter(named: "height", 6.0)

            let profile = try cad.sketch(on: .xy, named: "Profile") { sketch in
                sketch.rectangle(width: .parameter(width), height: .parameter(height))
            }
            let startSource = try cad.sketch(on: .zx, named: "Bridge start source") { sketch in
                sketch.line(
                    from: bridgePoint(-20.0, 0.0),
                    to: bridgePoint(0.0, 0.0)
                )
            }
            let endSource = try cad.sketch(on: .zx, named: "Bridge end source") { sketch in
                sketch.line(
                    from: bridgePoint(20.0, 0.0),
                    to: bridgePoint(40.0, 0.0)
                )
            }
            let path = try cad.bridgeCurve(
                from: BridgeCurveEndpointReference(
                    curve: CurveOutputReference(featureID: startSource.featureID),
                    end: .end,
                    requiredLevel: .tangent
                ),
                to: BridgeCurveEndpointReference(
                    curve: CurveOutputReference(featureID: endSource.featureID),
                    end: .start,
                    requiredLevel: .tangent
                ),
                continuityTolerances: .standard(modelingTolerance: .standard),
                named: "Bridge path"
            )
            let source = CurveOutputReference(featureID: path)
            let editedPath = try cad.editCurve(
                source,
                edits: [
                    .setControlPoint(CurveControlPointEdit(
                        target: CurveControlPointReference(curve: source, controlPointIndex: 1),
                        point: Point3D(x: 0.002, y: 0.0, z: 0.006)
                    ))
                ],
                named: "Edited path"
            )
            editedPathID = editedPath

            try cad.sweep(profile, along: editedPath, named: "Sweep")
        }

        let pipeline = CADPipeline(tolerance: .standard)
        let evaluated = try pipeline.evaluate(document)
        let editedPath = try #require(editedPathID)
        let editedControlPoint = try CurveQueryEvaluator(tolerance: .standard).controlPoint(
            CurveControlPointReference(
                curve: CurveOutputReference(featureID: editedPath),
                controlPointIndex: 1
            ),
            in: evaluated
        )

        #expect(evaluated.brep.bodies.count == 1)
        #expect(editedControlPoint == Point3D(x: 0.002, y: 0.0, z: 0.006))

        let packageData = try pipeline.packageData(for: document)
        let loaded = try pipeline.loadDocument(fromPackageData: packageData)
        #expect(loaded.metadata.name == "Edited Curve Sweep")
        #expect(loaded.designGraph.order.count == 4)
    }

    @Test(.timeLimit(.minutes(1)))
    func facadeBuildsExactCurveOffsetsThroughSharedOperations() throws {
        var lineOffsetID: FeatureID?
        var circleOffsetID: FeatureID?
        var arcOffsetID: FeatureID?
        let document = try CADDocument.millimeters(tolerance: .standard, named: "Exact Curve Offsets") { cad in
            let profile = try cad.sketch(on: .xy, named: "Body profile") { sketch in
                sketch.rectangle(
                    width: .constant(.length(20.0, unit: .millimeter)),
                    height: .constant(.length(10.0, unit: .millimeter))
                )
            }
            try cad.extrude(
                profile,
                distance: .constant(.length(5.0, unit: .millimeter)),
                named: "Body"
            )

            let lineSketch = try cad.sketch(on: .xy, named: "Offset line source") { sketch in
                _ = sketch.line(
                    from: SketchPoint(
                        x: .constant(.length(0.0, unit: .millimeter)),
                        y: .constant(.length(0.0, unit: .millimeter))
                    ),
                    to: SketchPoint(
                        x: .constant(.length(10.0, unit: .millimeter)),
                        y: .constant(.length(0.0, unit: .millimeter))
                    )
                )
            }
            lineOffsetID = try cad.offsetCurve(
                CurveOutputReference(featureID: lineSketch.featureID),
                distance: .constant(.length(5.0, unit: .millimeter)),
                planeNormal: .unitZ,
                side: .left,
                named: "Line offset"
            )

            let circleSketch = try cad.sketch(on: .xy, named: "Offset circle source") { sketch in
                sketch.circle(
                    center: SketchPoint(
                        x: .constant(.length(0.0, unit: .millimeter)),
                        y: .constant(.length(0.0, unit: .millimeter))
                    ),
                    radius: .constant(.length(10.0, unit: .millimeter))
                )
            }
            circleOffsetID = try cad.offsetCurve(
                CurveOutputReference(featureID: circleSketch.featureID),
                distance: .constant(.length(2.0, unit: .millimeter)),
                planeNormal: .unitZ,
                side: .left,
                named: "Circle offset"
            )

            let arcSketch = try cad.sketch(on: .xy, named: "Offset arc source") { sketch in
                sketch.arc(
                    center: SketchPoint(
                        x: .constant(.length(0.0, unit: .millimeter)),
                        y: .constant(.length(0.0, unit: .millimeter))
                    ),
                    radius: .constant(.length(10.0, unit: .millimeter)),
                    startAngle: .constant(.angle(0.0, unit: .radian)),
                    endAngle: .constant(.angle(90.0, unit: .degree))
                )
            }
            arcOffsetID = try cad.offsetCurve(
                CurveOutputReference(featureID: arcSketch.featureID),
                distance: .constant(.length(2.0, unit: .millimeter)),
                planeNormal: .unitZ,
                side: .left,
                named: "Arc offset"
            )
        }

        let pipeline = CADPipeline(tolerance: .standard)
        let evaluated = try pipeline.evaluate(document)
        let lineOffset = try CurveQueryEvaluator(tolerance: .standard).resolve(
            CurveOutputReference(featureID: try #require(lineOffsetID)),
            in: evaluated
        )
        let circleOffset = try CurveQueryEvaluator(tolerance: .standard).resolve(
            CurveOutputReference(featureID: try #require(circleOffsetID)),
            in: evaluated
        )
        let arcOffset = try CurveQueryEvaluator(tolerance: .standard).resolve(
            CurveOutputReference(featureID: try #require(arcOffsetID)),
            in: evaluated
        )

        guard case let .line(line)? = lineOffset.exactCurve else {
            Issue.record("Line offset must preserve an exact line representation.")
            return
        }
        guard case let .circle(circle)? = circleOffset.exactCurve else {
            Issue.record("Circle offset must preserve an exact circle representation.")
            return
        }
        guard case let .circle(arcCircle)? = arcOffset.exactCurve else {
            Issue.record("Arc offset must preserve an exact circle representation with a finite domain.")
            return
        }
        let lineStart = try #require(lineOffset.points.first)
        let lineEnd = try #require(lineOffset.points.last)
        let circleStart = try #require(circleOffset.points.first)
        let circleEnd = try #require(circleOffset.points.last)
        let arcStart = try #require(arcOffset.points.first)
        let arcEnd = try #require(arcOffset.points.last)
        let lineMidpoint = try CurveQueryEvaluator(tolerance: .standard).point(
            at: CurveParameterReference(
                curve: CurveOutputReference(featureID: try #require(lineOffsetID)),
                parameter: 0.005
            ),
            in: evaluated
        )
        let arcMidpoint = try CurveQueryEvaluator(tolerance: .standard).point(
            at: CurveParameterReference(
                curve: CurveOutputReference(featureID: try #require(arcOffsetID)),
                parameter: Double.pi / 4.0
            ),
            in: evaluated
        )

        #expect(evaluated.brep.bodies.count == 1)
        #expect(abs(line.direction.x - 1.0) < 1.0e-12)
        #expect(abs(line.direction.y) < 1.0e-12)
        #expect(abs(line.direction.z) < 1.0e-12)
        #expect(abs(lineStart.y - 0.005) < 1.0e-12)
        #expect(abs(lineEnd.y - 0.005) < 1.0e-12)
        #expect(abs(lineMidpoint.point.x - 0.005) < 1.0e-12)
        #expect(abs(lineMidpoint.point.y - 0.005) < 1.0e-12)
        #expect(lineMidpoint.isExact)
        #expect(abs(circle.radius - 0.008) < 1.0e-12)
        #expect(circleStart.isApproximatelyEqual(to: circleEnd, tolerance: 1.0e-12))
        #expect(arcOffset.kind == .arc)
        #expect(arcOffset.isClosed == false)
        #expect(abs(arcCircle.radius - 0.008) < 1.0e-12)
        #expect(arcStart.isApproximatelyEqual(to: Point3D(x: 0.008, y: 0.0, z: 0.0), tolerance: 1.0e-12))
        #expect(arcEnd.isApproximatelyEqual(to: Point3D(x: 0.0, y: 0.008, z: 0.0), tolerance: 1.0e-12))
        #expect(arcMidpoint.isExact)
        #expect(abs(arcMidpoint.point.x - 0.008 / Double(2.0).squareRoot()) < 1.0e-12)
        #expect(abs(arcMidpoint.point.y - 0.008 / Double(2.0).squareRoot()) < 1.0e-12)

        let packageData = try pipeline.packageData(for: document)
        let loaded = try pipeline.loadDocument(fromPackageData: packageData)
        #expect(loaded.metadata.name == "Exact Curve Offsets")
        #expect(loaded.designGraph.order.count == 8)
    }

    @Test(.timeLimit(.minutes(1)))
    func facadeBuildsExactCurveTrimsThroughSharedOperations() throws {
        var trimmedArcID: FeatureID?
        let document = try CADDocument.millimeters(tolerance: .standard, named: "Exact Curve Trims") { cad in
            let profile = try cad.sketch(on: .xy, named: "Body profile") { sketch in
                sketch.rectangle(
                    width: .constant(.length(12.0, unit: .millimeter)),
                    height: .constant(.length(8.0, unit: .millimeter))
                )
            }
            try cad.extrude(
                profile,
                distance: .constant(.length(4.0, unit: .millimeter)),
                named: "Body"
            )

            let arcSketch = try cad.sketch(on: .xy, named: "Trim arc source") { sketch in
                sketch.arc(
                    center: SketchPoint(
                        x: .constant(.length(0.0, unit: .millimeter)),
                        y: .constant(.length(0.0, unit: .millimeter))
                    ),
                    radius: .constant(.length(10.0, unit: .millimeter)),
                    startAngle: .constant(.angle(0.0, unit: .radian)),
                    endAngle: .constant(.angle(90.0, unit: .degree))
                )
            }
            trimmedArcID = try cad.trimCurve(
                CurveOutputReference(featureID: arcSketch.featureID),
                domain: .closed(0.0, Double.pi / 4.0),
                named: "Trimmed arc"
            )
        }

        let evaluated = try CADPipeline(tolerance: .standard).evaluate(document)
        let trimmedArc = try CurveQueryEvaluator(tolerance: .standard).resolve(
            CurveOutputReference(featureID: try #require(trimmedArcID)),
            in: evaluated
        )
        guard case let .circle(circle)? = trimmedArc.exactCurve else {
            Issue.record("Trimmed arc must preserve the exact source circle representation.")
            return
        }
        let start = try #require(trimmedArc.points.first)
        let end = try #require(trimmedArc.points.last)
        let midpoint = try CurveQueryEvaluator(tolerance: .standard).point(
            at: CurveParameterReference(
                curve: CurveOutputReference(featureID: try #require(trimmedArcID)),
                parameter: Double.pi / 8.0
            ),
            in: evaluated
        )

        #expect(evaluated.brep.bodies.count == 1)
        #expect(trimmedArc.kind == .arc)
        #expect(trimmedArc.isClosed == false)
        #expect(abs(circle.radius - 0.010) < 1.0e-12)
        #expect(start.isApproximatelyEqual(to: Point3D(x: 0.010, y: 0.0, z: 0.0), tolerance: 1.0e-12))
        #expect(end.isApproximatelyEqual(
            to: Point3D(x: 0.010 / Double(2.0).squareRoot(), y: 0.010 / Double(2.0).squareRoot(), z: 0.0),
            tolerance: 1.0e-12
        ))
        #expect(midpoint.isExact)

        let packageData = try CADPipeline(tolerance: .standard).packageData(for: document)
        let loaded = try CADPipeline(tolerance: .standard).loadDocument(fromPackageData: packageData)
        #expect(loaded.metadata.name == "Exact Curve Trims")
        #expect(loaded.designGraph.order.count == 4)
    }

    @Test(.timeLimit(.minutes(1)))
    func facadeProjectsExactGeneratedCurvesThroughSharedQueries() throws {
        var lineFeatureID: FeatureID?
        var trimmedArcID: FeatureID?
        let document = try CADDocument.millimeters(tolerance: .standard, named: "Exact Curve Projection") { cad in
            let profile = try cad.sketch(on: .xy, named: "Body profile") { sketch in
                sketch.rectangle(
                    width: .constant(.length(8.0, unit: .millimeter)),
                    height: .constant(.length(6.0, unit: .millimeter))
                )
            }
            try cad.extrude(
                profile,
                distance: .constant(.length(3.0, unit: .millimeter)),
                named: "Body"
            )

            let lineSketch = try cad.sketch(on: .xy, named: "Projection line") { sketch in
                _ = sketch.line(
                    from: SketchPoint(
                        x: .constant(.length(0.0, unit: .millimeter)),
                        y: .constant(.length(0.0, unit: .millimeter))
                    ),
                    to: SketchPoint(
                        x: .constant(.length(10.0, unit: .millimeter)),
                        y: .constant(.length(0.0, unit: .millimeter))
                    )
                )
            }
            lineFeatureID = lineSketch.featureID

            let arcSketch = try cad.sketch(on: .xy, named: "Projection arc source") { sketch in
                sketch.arc(
                    center: SketchPoint(
                        x: .constant(.length(0.0, unit: .millimeter)),
                        y: .constant(.length(0.0, unit: .millimeter))
                    ),
                    radius: .constant(.length(10.0, unit: .millimeter)),
                    startAngle: .constant(.angle(0.0, unit: .radian)),
                    endAngle: .constant(.angle(90.0, unit: .degree))
                )
            }
            trimmedArcID = try cad.trimCurve(
                CurveOutputReference(featureID: arcSketch.featureID),
                domain: .closed(0.0, Double.pi / 4.0),
                named: "Projection trimmed arc"
            )
        }

        let evaluated = try CADPipeline(tolerance: .standard).evaluate(document)
        let evaluator = CurveQueryEvaluator(tolerance: .standard)
        let lineReference = CurveOutputReference(featureID: try #require(lineFeatureID))
        let lineClosest = try evaluator.closestPoint(
            to: Point3D(x: 0.006, y: 0.003, z: 0.0),
            on: lineReference,
            in: evaluated
        )
        let lineProjected = try evaluator.project(
            Point3D(x: 0.006, y: 0.003, z: 0.0),
            along: -Vector3D.unitY,
            onto: lineReference,
            in: evaluated,
            options: CurveDirectionalProjectionOptions(range: .ray)
        )

        #expect(lineClosest.isExact)
        #expect(lineClosest.converged)
        #expect(abs(lineClosest.parameterReference.parameter - 0.006) <= 1.0e-12)
        #expect(lineClosest.projectedPoint.isApproximatelyEqual(
            to: Point3D(x: 0.006, y: 0.0, z: 0.0),
            tolerance: 1.0e-12
        ))
        #expect(abs(lineClosest.distance - 0.003) <= 1.0e-12)
        #expect(lineProjected.isExact)
        #expect(lineProjected.converged)
        #expect(abs(lineProjected.signedDistanceAlongDirection - 0.003) <= 1.0e-12)
        #expect(lineProjected.lineDistance <= 1.0e-12)

        let arcReference = CurveOutputReference(featureID: try #require(trimmedArcID))
        let targetAngle = Double.pi / 8.0
        let targetPoint = Point3D(
            x: 0.010 * cos(targetAngle),
            y: 0.010 * sin(targetAngle),
            z: 0.0
        )
        let arcClosest = try evaluator.closestPoint(
            to: Point3D(
                x: 0.014 * cos(targetAngle),
                y: 0.014 * sin(targetAngle),
                z: 0.0
            ),
            on: arcReference,
            in: evaluated
        )
        let arcProjected = try evaluator.project(
            targetPoint + Vector3D.unitZ * 0.020,
            along: -Vector3D.unitZ,
            onto: arcReference,
            in: evaluated,
            options: CurveDirectionalProjectionOptions(range: .ray)
        )

        #expect(arcClosest.isExact)
        #expect(arcClosest.converged)
        #expect(abs(arcClosest.parameterReference.parameter - targetAngle) <= 1.0e-9)
        #expect(arcClosest.projectedPoint.isApproximatelyEqual(to: targetPoint, tolerance: 1.0e-12))
        #expect(abs(arcClosest.distance - 0.004) <= 1.0e-12)
        #expect(arcProjected.isExact)
        #expect(arcProjected.converged)
        #expect(abs(arcProjected.parameterReference.parameter - targetAngle) <= 1.0e-9)
        #expect(abs(arcProjected.signedDistanceAlongDirection - 0.020) <= 1.0e-12)
        #expect(arcProjected.lineDistance <= 1.0e-12)
    }

    @Test(.timeLimit(.minutes(1)))
    func facadeBuildsPlanarEditFeaturesThroughSharedOperations() throws {
        var knifeCenterFaceName: SubshapeID?
        var knifeFeatureID: FeatureID?
        let document = try CADDocument.millimeters(tolerance: .standard, named: "Planar Edit Chain") { cad in
            let width = try cad.lengthParameter(named: "width", 40.0)
            let height = try cad.lengthParameter(named: "height", 20.0)
            let depth = try cad.lengthParameter(named: "depth", 10.0)
            let offsetDistance = try cad.lengthParameter(named: "offset", 2.0)

            let profile = try cad.sketch(on: .xy, named: "Base sketch") { sketch in
                sketch.rectangle(width: .parameter(width), height: .parameter(height))
            }
            let extrudeID = try cad.extrude(profile, distance: depth, named: "Extrude")
            let startFace = try cad.stableSubshape(
                generatedBy: extrudeID,
                selector: .generated(role: .startFace)
            )
            let offsetID = try cad.faceLoopOffset(
                target: extrudeID,
                face: startFace,
                distance: offsetDistance,
                named: "Offset"
            )
            let offsetCenterFace = try cad.stableSubshape(
                generatedBy: offsetID,
                selector: .faceLoopOffsetCenterFace
            )
            let knifeID = try cad.faceKnife(
                target: offsetID,
                face: offsetCenterFace,
                loop: [
                    Point3D(x: -0.004, y: -0.002, z: 0.0),
                    Point3D(x: 0.004, y: -0.002, z: 0.0),
                    Point3D(x: 0.004, y: 0.002, z: 0.0),
                    Point3D(x: -0.004, y: 0.002, z: 0.0),
                ],
                named: "Knife"
            )
            knifeFeatureID = knifeID
            knifeCenterFaceName = SubshapeID(
                featureID: knifeID,
                role: "faceKnife.centerFace",
                ordinal: 0
            )
        }

        let pipeline = CADPipeline(tolerance: .standard)
        let evaluated = try pipeline.evaluate(document)
        let faceName = try #require(knifeCenterFaceName)
        let knifeID = try #require(knifeFeatureID)
        guard case let .face(faceID) = try #require(evaluated.subshapes.entries[faceName]) else {
            Issue.record("Expected face knife center face to be generated.")
            return
        }
        let face = try #require(evaluated.brep.faces[faceID])
        let loopID = try #require(face.loops.first)
        let loop = try #require(evaluated.brep.loops[loopID])
        let storedParameterCurve = try #require(loop.edges.first?.surfaceParameterCurve)
        let trim = try SurfaceQueryEvaluator(tolerance: .standard).trimCurve(
            SurfaceTrimReference(
                surface: SurfaceReference(
                    subshape: try evaluated.stableSubshapeReference(
                        for: SubshapeID(
                            featureID: knifeID,
                            role: "faceKnife.centerFace",
                            ordinal: 0
                        )
                    )
                ),
                loopIndex: 0,
                edgeIndex: 0
            ),
            in: evaluated
        )

        #expect(document.designGraph.order.count == 4)
        #expect(evaluated.brep.faces.count > 7)
        #expect(loop.edges.allSatisfy { $0.surfaceParameterCurve != nil })
        #expect(trim.parameterCurve == storedParameterCurve)

        let packageData = try pipeline.packageData(for: document)
        let loaded = try pipeline.loadDocument(fromPackageData: packageData)
        #expect(loaded.metadata.name == "Planar Edit Chain")
        #expect(loaded.designGraph.order.count == 4)
    }

    @Test(.timeLimit(.minutes(1)))
    func facadeBuildsFaceDeleteSheetThroughSharedOperations() throws {
        var targetFaceName: SubshapeID?
        let document = try CADDocument.millimeters(tolerance: .standard, named: "Face Delete Sheet") { cad in
            let profile = try cad.sketch(on: .xy, named: "Base sketch") { sketch in
                sketch.rectangle(
                    width: .constant(.length(40.0, unit: .millimeter)),
                    height: .constant(.length(20.0, unit: .millimeter))
                )
            }
            let extrudeID = try cad.extrude(
                profile,
                distance: .constant(.length(10.0, unit: .millimeter)),
                named: "Extrude"
            )
            let faceName = SubshapeID(
                featureID: extrudeID,
                role: GeneratedSubshapeRole.startFace.rawValue,
                ordinal: 0
            )
            targetFaceName = faceName
            let face = try cad.stableSubshape(
                generatedBy: extrudeID,
                selector: .generated(role: .startFace)
            )
            try cad.faceDelete(
                target: extrudeID,
                faces: [face],
                named: "Delete Face"
            )
        }

        let pipeline = CADPipeline(tolerance: .standard)
        let evaluated = try pipeline.evaluate(document)
        let faceName = try #require(targetFaceName)

        #expect(document.designGraph.order.count == 3)
        #expect(evaluated.brep.bodies.values.first?.kind == .sheet)
        #expect(evaluated.brep.faces.count == 5)
        #expect(evaluated.subshapes.entries[faceName] == nil)

        let packageData = try pipeline.packageData(for: document)
        let loaded = try pipeline.loadDocument(fromPackageData: packageData)
        #expect(loaded.metadata.name == "Face Delete Sheet")
        #expect(loaded.designGraph.order.count == 3)
    }

    @Test(.timeLimit(.minutes(1)))
    func facadeBuildsFaceDraftBodyThroughSharedOperations() throws {
        let document = try CADDocument.millimeters(tolerance: .standard, named: "Face Draft Body") { cad in
            let profile = try cad.sketch(on: .xy, named: "Base sketch") { sketch in
                sketch.rectangle(
                    width: .constant(.length(40.0, unit: .millimeter)),
                    height: .constant(.length(20.0, unit: .millimeter))
                )
            }
            let extrudeID = try cad.extrude(
                profile,
                distance: .constant(.length(10.0, unit: .millimeter)),
                named: "Extrude"
            )
            let targetFace = try cad.stableSubshape(
                generatedBy: extrudeID,
                selector: .generated(role: .sideFace, index: 0)
            )
            let neutralFace = try cad.stableSubshape(
                generatedBy: extrudeID,
                selector: .generated(role: .startFace)
            )
            try cad.faceDraft(
                target: extrudeID,
                faces: [targetFace],
                neutralFace: neutralFace,
                angle: .constant(.angle(10.0, unit: .degree)),
                named: "Draft Face"
            )
        }

        let pipeline = CADPipeline(tolerance: .standard)
        let evaluated = try pipeline.evaluate(document)
        let draftFeatureID = try #require(document.designGraph.order.last)
        let draftNode = try #require(document.designGraph.nodes[draftFeatureID])

        guard case .faceDraft = draftNode.operation else {
            Issue.record("Expected facade to create a Face Draft operation.")
            return
        }
        #expect(document.designGraph.order.count == 3)
        #expect(evaluated.brep.bodies.values.first?.kind == .solid)
        #expect(evaluated.brep.faces.count == 6)

        let packageData = try pipeline.packageData(for: document)
        let loaded = try pipeline.loadDocument(fromPackageData: packageData)
        #expect(loaded.metadata.name == "Face Draft Body")
        #expect(loaded.designGraph.order.count == 3)
    }

    @Test(.timeLimit(.minutes(1)))
    func facadeBuildsPolySplineSheetThroughSharedOperations() throws {
        var sheetFeatureID: FeatureID?
        let document = try CADDocument.millimeters(tolerance: .standard, named: "PolySpline Sheet") { cad in
            sheetFeatureID = try cad.polySpline(
                sourceMesh: makeFacadePolySplineQuadMesh(),
                named: "Patch"
            )
        }

        let pipeline = CADPipeline(tolerance: .standard)
        let evaluated = try pipeline.evaluate(document)
        let featureID = try #require(sheetFeatureID)
        let faceName = SubshapeID(
            featureID: featureID,
            role: "polySpline.patch:0:face",
            ordinal: 0
        )
        guard case let .face(faceID) = try #require(evaluated.subshapes.entries[faceName]) else {
            Issue.record("Expected PolySpline face to be generated.")
            return
        }
        let face = try #require(evaluated.brep.faces[faceID])
        let loopID = try #require(face.loops.first)
        let loop = try #require(evaluated.brep.loops[loopID])
        let storedParameterCurve = try #require(loop.edges.first?.surfaceParameterCurve)
        let trim = try SurfaceQueryEvaluator(tolerance: .standard).trimCurve(
            SurfaceTrimReference(
                surface: SurfaceReference(
                    subshape: try evaluated.stableSubshapeReference(
                        for: SubshapeID(
                            featureID: featureID,
                            role: "polySpline.patch:0:face",
                            ordinal: 0
                        )
                    )
                ),
                loopIndex: 0,
                edgeIndex: 0
            ),
            in: evaluated
        )

        #expect(document.designGraph.order.count == 1)
        #expect(evaluated.brep.bodies.values.first?.kind == .sheet)
        #expect(evaluated.brep.faces.count == 1)
        #expect(loop.edges.allSatisfy { $0.surfaceParameterCurve != nil })
        #expect(trim.parameterCurve == storedParameterCurve)
    }











    @Test(.timeLimit(.minutes(1)))
    func facadeExposesIntentFilteredSnapQueries() throws {
        let document = try makeBoxDocument(named: "Snap Box")
        let pipeline = CADPipeline(tolerance: .standard)
        let evaluated = try pipeline.evaluate(document)
        let result = try pipeline.snapCandidates(
            near: Point3D(x: 0.0, y: -0.012, z: -0.002),
            in: evaluated,
            options: SnapQueryOptions(maximumDistance: 0.003, intent: .face)
        )

        let first = try #require(result.candidates.first)
        #expect(first.kind == .face)
        guard case .surface(.parameter) = first.selection else {
            Issue.record("Expected facade snap query to return a surface parameter reference.")
            return
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func kernelQueryReturnsCurveKeypointSnapCandidatesThroughSharedPipeline() throws {
        var lineFeatureID: FeatureID?
        let document = try CADDocument.millimeters(tolerance: .standard, named: "Agent Snap Query") { cad in
            let profile = try cad.sketch(on: .xy, named: "Body profile") { sketch in
                sketch.rectangle(
                    width: .constant(.length(8.0, unit: .millimeter)),
                    height: .constant(.length(6.0, unit: .millimeter))
                )
            }
            try cad.extrude(
                profile,
                distance: .constant(.length(3.0, unit: .millimeter)),
                named: "Body"
            )
            let lineSketch = try cad.sketch(on: .xy, named: "Agent query line") { sketch in
                _ = sketch.line(
                    from: SketchPoint(
                        x: .constant(.length(0.0, unit: .millimeter)),
                        y: .constant(.length(0.0, unit: .millimeter))
                    ),
                    to: SketchPoint(
                        x: .constant(.length(10.0, unit: .millimeter)),
                        y: .constant(.length(0.0, unit: .millimeter))
                    )
                )
            }
            lineFeatureID = lineSketch.featureID
        }
        let query = KernelQuery.snap(SnapQueryRequest(
            point: Point3D(x: 0.0015, y: 0.0, z: 0.0),
            options: SnapQueryOptions(maximumDistance: 0.002, intent: .curvePoint)
        ))

        let encodedQuery = try JSONEncoder().encode(query)
        let decodedQuery = try JSONDecoder().decode(KernelQuery.self, from: encodedQuery)
        let result = try CADPipeline(tolerance: .standard).execute(decodedQuery, on: document)
        guard case let .snap(rawSnapResult) = result else {
            Issue.record("Expected a kernel snap query result.")
            return
        }
        let snapResult = try JSONDecoder().decode(
            SnapQueryResult.self,
            from: JSONEncoder().encode(rawSnapResult)
        )
        let first = try #require(snapResult.candidates.first)
        #expect(first.kind == .curvePoint)
        #expect(first.role == .curveStart)
        guard case let .curve(.parameter(reference)) = first.selection else {
            Issue.record("Expected kernel snap query to return a curve parameter reference.")
            return
        }
        let expectedLineFeatureID = try #require(lineFeatureID)
        #expect(reference.curve.featureID == expectedLineFeatureID)
        #expect(abs(reference.parameter) <= 1.0e-12)
    }

    @Test(.timeLimit(.minutes(1)))
    func kernelMeasurementQueriesResolveSharedSelectionReferences() throws {
        var horizontalFeatureID: FeatureID?
        var verticalFeatureID: FeatureID?
        let document = try CADDocument.millimeters(tolerance: .standard, named: "Agent Measurement Query") { cad in
            let profile = try cad.sketch(on: .xy, named: "Body profile") { sketch in
                sketch.rectangle(
                    width: .constant(.length(8.0, unit: .millimeter)),
                    height: .constant(.length(6.0, unit: .millimeter))
                )
            }
            try cad.extrude(
                profile,
                distance: .constant(.length(3.0, unit: .millimeter)),
                named: "Body"
            )
            let horizontal = try cad.sketch(on: .xy, named: "Horizontal line") { sketch in
                _ = sketch.line(
                    from: SketchPoint(
                        x: .constant(.length(0.0, unit: .millimeter)),
                        y: .constant(.length(0.0, unit: .millimeter))
                    ),
                    to: SketchPoint(
                        x: .constant(.length(10.0, unit: .millimeter)),
                        y: .constant(.length(0.0, unit: .millimeter))
                    )
                )
            }
            horizontalFeatureID = horizontal.featureID
            let vertical = try cad.sketch(on: .xy, named: "Vertical line") { sketch in
                _ = sketch.line(
                    from: SketchPoint(
                        x: .constant(.length(0.0, unit: .millimeter)),
                        y: .constant(.length(0.0, unit: .millimeter))
                    ),
                    to: SketchPoint(
                        x: .constant(.length(0.0, unit: .millimeter)),
                        y: .constant(.length(10.0, unit: .millimeter))
                    )
                )
            }
            verticalFeatureID = vertical.featureID
        }

        let pipeline = CADPipeline(tolerance: .standard)
        let startSnap = try pipeline.execute(
            .snap(SnapQueryRequest(
                point: Point3D(x: 0.0001, y: 0.0, z: 0.0),
                options: SnapQueryOptions(maximumDistance: 0.001, intent: .curvePoint)
            )),
            on: document
        )
        let endSnap = try pipeline.execute(
            .snap(SnapQueryRequest(
                point: Point3D(x: 0.010, y: 0.0, z: 0.0),
                options: SnapQueryOptions(maximumDistance: 0.001, intent: .curvePoint)
            )),
            on: document
        )

        guard case let .snap(startSnapResult) = startSnap,
              case let .snap(endSnapResult) = endSnap else {
            Issue.record("Expected snap query results.")
            return
        }
        let startSelection = try #require(startSnapResult.candidates.first?.selection)
        let endSelection = try #require(endSnapResult.candidates.first?.selection)
        let distanceQuery = KernelQuery.measurement(MeasurementQuery(
            kind: .distance,
            first: startSelection,
            second: endSelection
        ))
        let decodedDistanceQuery = try JSONDecoder().decode(
            KernelQuery.self,
            from: try JSONEncoder().encode(distanceQuery)
        )
        let distanceResult = try pipeline.execute(decodedDistanceQuery, on: document)
        guard case let .measurement(rawMeasurement) = distanceResult else {
            Issue.record("Expected a measurement query result.")
            return
        }
        let decodedMeasurement = try JSONDecoder().decode(
            MeasurementQueryResult.self,
            from: try JSONEncoder().encode(rawMeasurement)
        )
        guard case let .distance(distance) = decodedMeasurement else {
            Issue.record("Expected a distance measurement result.")
            return
        }
        #expect(abs(distance.distance - 0.010) < 1.0e-12)
        #expect(abs(distance.vector.x - 0.010) < 1.0e-12)

        let pointResult = try pipeline.execute(
            .measurement(MeasurementQuery(kind: .point, first: startSelection)),
            on: document
        )
        guard case let .measurement(.point(point)) = pointResult else {
            Issue.record("Expected a point measurement result.")
            return
        }
        #expect(point.point.isApproximatelyEqual(to: .origin, tolerance: 1.0e-12))

        let horizontal = CurveOutputReference(featureID: try #require(horizontalFeatureID))
        let vertical = CurveOutputReference(featureID: try #require(verticalFeatureID))
        let angleResult = try pipeline.execute(
            .measurement(MeasurementQuery(
                kind: .angle,
                first: .curve(.parameter(CurveParameterReference(curve: horizontal, parameter: 0.005))),
                second: .curve(.parameter(CurveParameterReference(curve: vertical, parameter: 0.005)))
            )),
            on: document
        )
        guard case let .measurement(.angle(angle)) = angleResult else {
            Issue.record("Expected an angle measurement result.")
            return
        }
        #expect(abs(angle.angleRadians - Double.pi / 2.0) < 1.0e-12)
        #expect(abs(angle.angleDegrees - 90.0) < 1.0e-12)
    }



    @Test(.timeLimit(.minutes(1)))
    func facadeSolvesSketchConstraintsInsideDocument() throws {
        let lineID = SketchEntityID()
        let sketchID = FeatureID()
        let extrudeID = FeatureID()
        let sketch = Sketch(
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
            ],
            dimensions: [
                .distance(
                    from: .lineStart(lineID),
                    to: .lineEnd(lineID),
                    value: .constant(.length(2.0, unit: .meter))
                )
            ]
        )
        let document = CADDocument(
            units: .meters,
            designGraph: DesignGraph(
                nodes: [
                    sketchID: FeatureNode(
                        id: sketchID,
                        operation: .sketch(sketch),
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

        let result = try CADPipeline(tolerance: .standard).solveSketchConstraints(in: document, featureID: sketchID)

        #expect(result.featureID == sketchID)
        #expect(result.invalidatedFeatureIDs == [extrudeID])
        #expect(result.document.designGraph.revision == document.designGraph.revision.advanced())
        #expect(result.constraintResult.status == .underConstrained)
        #expect(result.constraintResult.maximumNormalizedResidual <= 1.0)
        let updatedFeature = try #require(result.document.designGraph.nodes[sketchID])
        guard case let .sketch(updatedSketch) = updatedFeature.operation,
              case let .line(updatedLine) = updatedSketch.entities[lineID] else {
            Issue.record("Expected solved document to update the sketch line.")
            return
        }
        let startX = try result.document.parameters.resolvedValue(for: updatedLine.start.x)
        let startY = try result.document.parameters.resolvedValue(for: updatedLine.start.y)
        let endX = try result.document.parameters.resolvedValue(for: updatedLine.end.x)
        let endY = try result.document.parameters.resolvedValue(for: updatedLine.end.y)
        #expect(abs(hypot(endX.value - startX.value, endY.value - startY.value) - 2.0) <= 1.0e-6)
    }

    @Test(.timeLimit(.minutes(1)))
    func facadeRejectsNonSketchConstraintSolveTargets() throws {
        let document = try makeBoxDocument(named: "Box")
        let extrudeID = try #require(document.designGraph.order.last)

        #expect(throws: KernelError.self) {
            _ = try CADPipeline(tolerance: .standard).solveSketchConstraints(in: document, featureID: extrudeID)
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func facadeSavesLoadsExportsAndImportsThroughMappedFiles() throws {
        let document = try makeBoxDocument(named: "Mapped Box")
        let pipeline = CADPipeline(tolerance: .standard)

        try withTemporaryDirectory { directoryURL in
            let nativeURL = directoryURL.appendingPathComponent("box.swcad")
            try pipeline.save(document, to: nativeURL)

            let loaded = try pipeline.load(from: nativeURL)
            #expect(loaded.metadata.name == "Mapped Box")
            #expect(loaded.designGraph.order.count == 2)

            let importedNative = try pipeline.importExchange(MappedFileByteSource(url: nativeURL), as: .swiftCAD)
            #expect(importedNative.document?.metadata.name == "Mapped Box")

            let evaluated = try pipeline.evaluate(loaded)
            let stlURL = directoryURL.appendingPathComponent("box.stl")
            let stlSink = try FileByteSink(url: stlURL)
            try pipeline.write(evaluated, as: .stl, to: stlSink)
            try stlSink.close()

            let attributes = try FileManager.default.attributesOfItem(atPath: stlURL.path)
            let byteCount = try #require(attributes[.size] as? NSNumber).intValue
            #expect(byteCount == 84 + 12 * 50)

            let importedSTL = try pipeline.importExchange(MappedFileByteSource(url: stlURL), as: .stl)
            #expect(importedSTL.format == .stl)
            #expect(importedSTL.units.length == .millimeter)
            #expect(importedSTL.meshes.count == 1)
            for mesh in importedSTL.meshes.values {
                try mesh.validate(tolerance: .standard)
            }
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func facadeWritesEveryOfficialFormatAndImportsSupportedExports() throws {
        let document = try makeBoxDocument(named: "Format Matrix")
        let pipeline = CADPipeline(tolerance: .standard)
        let evaluated = try pipeline.evaluate(document)

        for format in ExchangeFileFormat.allCases {
            let exported = try collectBytes { sink in
                try pipeline.write(evaluated, as: format, to: sink)
            }
            #expect(!exported.isEmpty)

            guard format.supportsImport else {
                continue
            }

            let imported = try pipeline.importExchange(BorrowedBytes(exported), as: format)
            #expect(imported.format == format)
            if format == .swiftCAD {
                #expect(imported.document?.metadata.name == "Format Matrix")
            } else {
                #expect(!imported.meshes.isEmpty)
                #expect(imported.units.length == .millimeter)
                for mesh in imported.meshes.values {
                    try mesh.validate(tolerance: .standard)
                }
            }
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func facadeRejectsMalformedMappedImportFiles() throws {
        let pipeline = CADPipeline(tolerance: .standard)

        try withTemporaryDirectory { directoryURL in
            let invalidNativeURL = directoryURL.appendingPathComponent("broken.swcad")
            try Data("not a native package".utf8).write(to: invalidNativeURL)
            #expect(throws: SchemaError.self) {
                _ = try pipeline.importExchange(MappedFileByteSource(url: invalidNativeURL), as: .swiftCAD)
            }

            let invalidImportCases: [(format: ExchangeFileFormat, fileName: String, data: Data)] = [
                (.step, "broken.step", Data("""
                ISO-10303-21;
                HEADER;
                ENDSEC;
                DATA;
                ENDSEC;
                END-ISO-10303-21;
                """.utf8)),
                (.iges, "broken.iges", Data()),
                (.stl, "broken.stl", Data(count: 83)),
                (.threeMF, "broken.3mf", Data("not a zip archive".utf8)),
                (.obj, "broken.obj", Data("""
                # Swift-CAD OBJ
                # unit millimeter
                v 0 0 0
                """.utf8)),
                (.dxf, "broken.dxf", Data("""
                0
                SECTION
                2
                ENTITIES
                0
                ENDSEC
                0
                EOF
                """.utf8)),
                (.svg, "broken.svg", Data("""
                <svg xmlns="http://www.w3.org/2000/svg" data-unit="millimeter"></svg>
                """.utf8)),
                (.usda, "broken.usda", Data("""
                #usda 1.0
                (
                    metersPerUnit = 0.001
                    upAxis = "Z"
                )
                """.utf8))
            ]

            for testCase in invalidImportCases {
                let url = directoryURL.appendingPathComponent(testCase.fileName)
                try testCase.data.write(to: url)
                #expect(throws: ImportError.self) {
                    _ = try pipeline.importExchange(MappedFileByteSource(url: url), as: testCase.format)
                }
            }
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func facadeRejectsFormatMismatchesAndUnsupportedImports() throws {
        let document = try makeBoxDocument(named: "Mismatch Matrix")
        let pipeline = CADPipeline(tolerance: .standard)
        let evaluated = try pipeline.evaluate(document)
        let packageData = try pipeline.packageData(for: document)
        let stlData = try pipeline.exportBinarySTL(from: evaluated, lengthUnit: .millimeter)

        #expect(throws: ImportError.self) {
            _ = try pipeline.importExchange(BorrowedBytes(packageData), as: .stl)
        }
        #expect(throws: SchemaError.self) {
            _ = try pipeline.importExchange(BorrowedBytes(stlData), as: .swiftCAD)
        }
        #expect(throws: ImportError.self) {
            _ = try pipeline.importExchange(BorrowedBytes(stlData), as: .obj)
        }

        for format in ExchangeFileFormat.allCases where !format.supportsImport {
            #expect(throws: ImportError.self) {
                _ = try pipeline.importExchange(BorrowedBytes(stlData), as: format)
            }
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func failedFacadeNativeSavePreservesExistingFileContents() throws {
        var document = try makeBoxDocument(named: "Invalid Save")
        document.schemaVersion = SchemaVersion(major: SchemaVersion.current.major + 1, minor: 0, patch: 0)
        let pipeline = CADPipeline(tolerance: .standard)

        try withTemporaryDirectory { directoryURL in
            let url = directoryURL.appendingPathComponent("existing.swcad")
            let originalData = Data("existing native payload".utf8)
            try originalData.write(to: url)

            #expect(throws: SchemaError.self) {
                try pipeline.save(document, to: url)
            }
            let preservedData = try Data(contentsOf: url)
            #expect(preservedData == originalData)
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func facadePropagatesSinkFailuresWithoutSwallowingErrors() throws {
        let document = try makeBoxDocument(named: "Failing Sink")
        let pipeline = CADPipeline(tolerance: .standard)
        let evaluated = try pipeline.evaluate(document)

        #expect(throws: FailingByteSink.Error.self) {
            try pipeline.write(evaluated, as: .stl, to: FailingByteSink())
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func facadeRejectsInvalidDocumentsDuringBuild() {
        #expect(throws: ParameterError.self) {
            _ = try CADDocument.millimeters(tolerance: .standard) { cad in
                try cad.lengthParameter(named: "width", 40.0)
                try cad.lengthParameter(named: "width", 20.0)
            }
        }

        #expect(throws: UnitError.self) {
            var builder = DocumentBuilder(units: .millimeters, tolerance: .standard)
            try builder.lengthParameter(named: "depth", .nan)
            _ = try builder.build()
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func facadeRejectsStaleEvaluatedDocumentBeforeSTLExport() throws {
        let document = try CADDocument.millimeters(tolerance: .standard) { cad in
            let width = try cad.lengthParameter(named: "width", 40.0)
            let height = try cad.lengthParameter(named: "height", 20.0)
            let depth = try cad.lengthParameter(named: "depth", 10.0)
            let profile = try cad.sketch(on: .xy) { sketch in
                sketch.rectangle(width: .parameter(width), height: .parameter(height))
            }
            try cad.extrude(profile, distance: depth)
        }
        let pipeline = CADPipeline(tolerance: .standard)
        let evaluated = try pipeline.evaluate(document)
        let bodyID = try #require(evaluated.meshes.keys.first)
        var staleMeshes = evaluated.meshes
        staleMeshes[bodyID]?.positions[0].x += 0.25
        let staleEvaluated = EvaluatedDocument(
            document: evaluated.document,
            parameters: evaluated.parameters,
            brep: evaluated.brep,
            meshes: staleMeshes,
            curves: evaluated.curves,
            caches: evaluated.caches,
            subshapes: evaluated.subshapes,
            lineage: evaluated.lineage,
            configuration: evaluated.configuration,
            evaluationMetrics: evaluated.evaluationMetrics
        )

        #expect(throws: CacheValidationError.self) {
            _ = try pipeline.exportBinarySTL(from: staleEvaluated, lengthUnit: .millimeter)
        }
    }
}

private func bridgePoint(_ z: Double, _ x: Double) -> SketchPoint {
    SketchPoint(
        x: .constant(.length(z, unit: .millimeter)),
        y: .constant(.length(x, unit: .millimeter))
    )
}

private struct FailingByteSink: ByteSink {
    enum Error: Swift.Error, Equatable {
        case forced
    }

    func write(_ bytes: UnsafeRawBufferPointer) throws {
        throw Error.forced
    }
}

private func makeBoxDocument(named name: String) throws -> CADDocument {
    try CADDocument.millimeters(tolerance: .standard, named: name) { cad in
        let width = try cad.lengthParameter(named: "width", 40.0)
        let height = try cad.lengthParameter(named: "height", 20.0)
        let depth = try cad.lengthParameter(named: "depth", 10.0)

        let profile = try cad.sketch(on: .xy, named: "Base sketch") { sketch in
            sketch.rectangle(width: .parameter(width), height: .parameter(height))
        }

        try cad.extrude(profile, distance: depth, named: "Extrude")
    }
}

private func makeFacadePolySplineQuadMesh() -> Mesh {
    Mesh(
        positions: [
            Point3D(x: 0.0, y: 0.0, z: 0.0),
            Point3D(x: 2.0, y: 0.0, z: 0.1),
            Point3D(x: 2.0, y: 1.5, z: 0.4),
            Point3D(x: 0.0, y: 1.5, z: 0.0),
        ],
        indices: [0, 1, 2, 0, 2, 3]
    )
}

private func jsonObject(from data: Data) throws -> [String: Any] {
    guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
        throw FeatureEvaluationError.invalidGraph("Expected a JSON object.")
    }
    return object
}

private func withTemporaryDirectory<Result>(_ body: (URL) throws -> Result) throws -> Result {
    let fileManager = FileManager.default
    let directoryURL = fileManager.temporaryDirectory.appendingPathComponent(
        "SwiftCADFacadeTests-\(UUID().uuidString)",
        isDirectory: true
    )
    try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
    do {
        let result = try body(directoryURL)
        try fileManager.removeItem(at: directoryURL)
        return result
    } catch {
        let primaryError = error
        do {
            try fileManager.removeItem(at: directoryURL)
        } catch {
        }
        throw primaryError
    }
}
