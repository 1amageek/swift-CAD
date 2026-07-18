import Testing
import CADCore
@testable import CADIR

@Suite("CAD document source translation")
struct CADDocumentTranslationTests {
    @Test(.timeLimit(.minutes(1)))
    func translatesStandardPlaneSketchInLocalCoordinates() throws {
        let parameterID = ParameterID()
        let lineID = SketchEntityID()
        let featureID = FeatureID()
        let document = CADDocument(
            units: .meters,
            parameters: ParameterTable(parameters: [
                parameterID: Parameter(
                    id: parameterID,
                    name: "siteX",
                    expression: .constant(.length(10_000.0, unit: .meter)),
                    kind: .length
                ),
            ]),
            designGraph: DesignGraph(
                nodes: [
                    featureID: FeatureNode(
                        id: featureID,
                        operation: .sketch(Sketch(
                            plane: .xy,
                            entities: [
                                lineID: .line(SketchLine(
                                    start: SketchPoint(
                                        x: .reference(parameterID),
                                        y: .constant(.length(20_000.0, unit: .meter))
                                    ),
                                    end: SketchPoint(
                                        x: .constant(.length(10_010.0, unit: .meter)),
                                        y: .constant(.length(20_020.0, unit: .meter))
                                    )
                                )),
                            ]
                        )),
                        outputs: [FeatureOutput(role: .curve)]
                    ),
                ],
                order: [featureID]
            )
        )

        let translated = try document.translatingSources(
            by: Vector3D(x: -9_999.0, y: -20_000.0, z: 0.0),
            tolerance: .standard
        )
        let sketch = try translatedSketch(in: translated, featureID: featureID)
        let line = try translatedLine(in: sketch, entityID: lineID)

        #expect(try resolvedLength(line.start.x, in: translated) == 1.0)
        #expect(try resolvedLength(line.start.y, in: translated) == 0.0)
        #expect(try resolvedLength(line.end.x, in: translated) == 11.0)
        #expect(try resolvedLength(line.end.y, in: translated) == 20.0)
        if case .add(.reference(let translatedParameterID), .constant) = line.start.x {
            #expect(translatedParameterID == parameterID)
        } else {
            Issue.record("Translated parameter-driven coordinates must preserve their parameter reference.")
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func rejectsStandardPlaneNormalTranslation() throws {
        let featureID = FeatureID()
        let document = CADDocument(
            units: .meters,
            designGraph: DesignGraph(
                nodes: [
                    featureID: FeatureNode(
                        id: featureID,
                        operation: .sketch(Sketch(plane: .xy, entities: [
                            SketchEntityID(): .point(SketchPoint(
                                x: .constant(.length(0.0, unit: .meter)),
                                y: .constant(.length(0.0, unit: .meter))
                            )),
                        ])),
                        outputs: [FeatureOutput(role: .curve)]
                    ),
                ],
                order: [featureID]
            )
        )

        #expect(throws: FeatureEvaluationError.self) {
            try document.translatingSources(
                by: Vector3D(x: 0.0, y: 0.0, z: 1.0),
                tolerance: .standard
            )
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func translatesCustomPlaneSketchByMovingPlaneOrigin() throws {
        let pointID = SketchEntityID()
        let featureID = FeatureID()
        let document = CADDocument(
            units: .meters,
            designGraph: DesignGraph(
                nodes: [
                    featureID: FeatureNode(
                        id: featureID,
                        operation: .sketch(Sketch(
                            plane: .plane(Plane3D(
                                origin: Point3D(x: 1.0, y: 2.0, z: 3.0),
                                normal: .unitZ
                            )),
                            entities: [
                                pointID: .point(SketchPoint(
                                    x: .constant(.length(4.0, unit: .meter)),
                                    y: .constant(.length(5.0, unit: .meter))
                                )),
                            ]
                        )),
                        outputs: [FeatureOutput(role: .curve)]
                    ),
                ],
                order: [featureID]
            )
        )

        let translated = try document.translatingSources(
            by: Vector3D(x: 10.0, y: 20.0, z: 30.0),
            tolerance: .standard
        )
        let sketch = try translatedSketch(in: translated, featureID: featureID)

        guard case .plane(let plane) = sketch.plane else {
            Issue.record("Translated custom sketch must remain on a custom plane.")
            return
        }
        #expect(plane.origin == Point3D(x: 11.0, y: 22.0, z: 33.0))
        guard case .point(let point) = sketch.entities[pointID] else {
            Issue.record("Expected translated sketch point.")
            return
        }
        #expect(try resolvedLength(point.x, in: translated) == 4.0)
        #expect(try resolvedLength(point.y, in: translated) == 5.0)
    }

    @Test(.timeLimit(.minutes(1)))
    func translatesSurfaceAndPolySplineSourceCoordinates() throws {
        let surfaceFeatureID = FeatureID()
        let polySplineFeatureID = FeatureID()
        let document = CADDocument(
            units: .meters,
            designGraph: DesignGraph(
                nodes: [
                    surfaceFeatureID: FeatureNode(
                        id: surfaceFeatureID,
                        operation: .bSplineSurface(BSplineSurfaceFeature(
                            surface: BSplineSurface3D(
                                uDegree: 1,
                                vDegree: 1,
                                uKnots: [0.0, 0.0, 1.0, 1.0],
                                vKnots: [0.0, 0.0, 1.0, 1.0],
                                controlPoints: [
                                    [
                                        Point3D(x: 1.0, y: 2.0, z: 3.0),
                                        Point3D(x: 2.0, y: 2.0, z: 3.0),
                                    ],
                                    [
                                        Point3D(x: 1.0, y: 3.0, z: 3.0),
                                        Point3D(x: 2.0, y: 3.0, z: 3.0),
                                    ],
                                ]
                            )
                        )),
                        outputs: [FeatureOutput(role: .sheet)]
                    ),
                    polySplineFeatureID: FeatureNode(
                        id: polySplineFeatureID,
                        operation: .polySpline(PolySplineFeature(
                            sourceMesh: Mesh(
                                positions: [
                                    Point3D(x: 10.0, y: 0.0, z: 0.0),
                                    Point3D(x: 11.0, y: 0.0, z: 0.0),
                                    Point3D(x: 10.0, y: 1.0, z: 0.0),
                                ],
                                indices: [0, 1, 2]
                            ),
                            controlPointOverrides: [
                                PolySplineSurfaceControlPointOverride(
                                    patchID: 0,
                                    uIndex: 1,
                                    vIndex: 1,
                                    point: Point3D(x: 10.0, y: 0.0, z: 1.0)
                                ),
                            ]
                        )),
                        outputs: [FeatureOutput(role: .sheet)]
                    ),
                ],
                order: [surfaceFeatureID, polySplineFeatureID]
            )
        )

        let translated = try document.translatingSources(
            by: Vector3D(x: -10.0, y: 5.0, z: 2.0),
            tolerance: .standard
        )

        guard case .bSplineSurface(let surfaceFeature) = translated.designGraph.nodes[surfaceFeatureID]?.operation else {
            Issue.record("Expected translated B-spline surface feature.")
            return
        }
        #expect(surfaceFeature.surface.controlPoints[0][0] == Point3D(x: -9.0, y: 7.0, z: 5.0))

        guard case .polySpline(let polySplineFeature) = translated.designGraph.nodes[polySplineFeatureID]?.operation else {
            Issue.record("Expected translated PolySpline feature.")
            return
        }
        #expect(polySplineFeature.sourceMesh.positions[0] == Point3D(x: 0.0, y: 5.0, z: 2.0))
        #expect(polySplineFeature.controlPointOverrides[0].point == Point3D(x: 0.0, y: 5.0, z: 3.0))
    }
}

private func translatedSketch(
    in document: CADDocument,
    featureID: FeatureID
) throws -> Sketch {
    let node = try #require(document.designGraph.nodes[featureID])
    guard case .sketch(let sketch) = node.operation else {
        Issue.record("Expected translated sketch feature.")
        return Sketch(plane: .xy)
    }
    return sketch
}

private func translatedLine(
    in sketch: Sketch,
    entityID: SketchEntityID
) throws -> SketchLine {
    guard case .line(let line) = sketch.entities[entityID] else {
        Issue.record("Expected translated sketch line.")
        return SketchLine(
            start: SketchPoint(
                x: .constant(.length(0.0, unit: .meter)),
                y: .constant(.length(0.0, unit: .meter))
            ),
            end: SketchPoint(
                x: .constant(.length(0.0, unit: .meter)),
                y: .constant(.length(0.0, unit: .meter))
            )
        )
    }
    return line
}

private func resolvedLength(
    _ expression: CADExpression,
    in document: CADDocument
) throws -> Double {
    let quantity = try document.parameters.resolvedValue(for: expression)
    #expect(quantity.kind == .length)
    return quantity.value
}
