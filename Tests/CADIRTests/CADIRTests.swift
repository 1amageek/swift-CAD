import Foundation
import Testing
import CADCore
@testable import CADIR

@Suite("CADIR")
struct CADIRTests {
    @Test(.timeLimit(.minutes(1)))
    func documentMetadataDefaultTimestampsAreConsistent() throws {
        let metadata = DocumentMetadata()

        #expect(metadata.createdAt == metadata.updatedAt)
        try metadata.validate()
    }

    @Test(.timeLimit(.minutes(1)))
    func designGraphRejectsMissingOrderedFeature() throws {
        let missingID = FeatureID()
        let graph = DesignGraph(nodes: [:], order: [missingID], dependencies: [])

        #expect(throws: FeatureEvaluationError.self) {
            try graph.validate()
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func designGraphRejectsUnorderedExistingNode() {
        let featureID = FeatureID()
        let graph = DesignGraph(
            nodes: [featureID: FeatureNode(
                id: featureID,
                operation: .sketch(Sketch(plane: .xy)),
                outputs: [FeatureOutput(role: .profile)]
            )],
            order: [],
            dependencies: []
        )

        #expect(throws: FeatureEvaluationError.self) {
            try graph.validate()
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func designGraphRejectsInvalidPersistentOutputNames() {
        let emptyNameFeatureID = FeatureID()
        let negativeIndexFeatureID = FeatureID()
        let emptyNameGraph = DesignGraph(
            nodes: [emptyNameFeatureID: FeatureNode(
                id: emptyNameFeatureID,
                operation: .sketch(Sketch(plane: .xy)),
                outputs: [
                    FeatureOutput(
                        role: .profile,
                        persistentName: PersistentName(components: [])
                    )
                ]
            )],
            order: [emptyNameFeatureID]
        )
        let negativeIndexGraph = DesignGraph(
            nodes: [negativeIndexFeatureID: FeatureNode(
                id: negativeIndexFeatureID,
                operation: .sketch(Sketch(plane: .xy)),
                outputs: [
                    FeatureOutput(
                        role: .profile,
                        persistentName: PersistentName(components: [
                            .feature(negativeIndexFeatureID),
                            .generated(GeneratedSubshapeRole.body.rawValue),
                            .index(-1)
                        ])
                    )
                ]
            )],
            order: [negativeIndexFeatureID]
        )

        #expect(throws: FeatureEvaluationError.self) {
            try emptyNameGraph.validate()
        }
        #expect(throws: FeatureEvaluationError.self) {
            try negativeIndexGraph.validate()
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func designGraphReportsDeterministicInvalidatedFeatures() throws {
        let sketchID = FeatureID()
        let firstExtrudeID = FeatureID()
        let secondExtrudeID = FeatureID()
        let graph = DesignGraph(
            nodes: [
                sketchID: FeatureNode(
                    id: sketchID,
                    operation: .sketch(Sketch(plane: .xy)),
                    outputs: [FeatureOutput(role: .profile)]
                ),
                firstExtrudeID: FeatureNode(
                    id: firstExtrudeID,
                    operation: .extrude(ExtrudeFeature(
                        profile: ProfileReference(featureID: sketchID),
                        distance: .constant(.length(1.0, unit: .meter))
                    )),
                    inputs: [FeatureInput(featureID: sketchID, role: .profile)],
                    outputs: [FeatureOutput(role: .body)]
                ),
                secondExtrudeID: FeatureNode(
                    id: secondExtrudeID,
                    operation: .extrude(ExtrudeFeature(
                        profile: ProfileReference(featureID: sketchID),
                        distance: .constant(.length(1.0, unit: .meter))
                    )),
                    inputs: [FeatureInput(featureID: sketchID, role: .profile)],
                    outputs: [FeatureOutput(role: .body)]
                )
            ],
            order: [sketchID, firstExtrudeID, secondExtrudeID],
            dependencies: [
                DependencyEdge(source: sketchID, target: firstExtrudeID),
                DependencyEdge(source: sketchID, target: secondExtrudeID)
            ]
        )

        #expect(try graph.invalidatedFeatureIDs(after: sketchID) == [firstExtrudeID, secondExtrudeID])
        #expect(try graph.invalidatedFeatureIDs(after: firstExtrudeID).isEmpty)
    }

    @Test(.timeLimit(.minutes(1)))
    func designGraphRejectsDependencyCyclesAndOrderViolations() {
        let firstID = FeatureID()
        let secondID = FeatureID()
        let nodes = [
            firstID: FeatureNode(
                id: firstID,
                operation: .sketch(Sketch(plane: .xy)),
                outputs: [FeatureOutput(role: .profile)]
            ),
            secondID: FeatureNode(
                id: secondID,
                operation: .sketch(Sketch(plane: .xy)),
                outputs: [FeatureOutput(role: .profile)]
            )
        ]
        let cyclicGraph = DesignGraph(
            nodes: nodes,
            order: [firstID, secondID],
            dependencies: [
                DependencyEdge(source: firstID, target: secondID),
                DependencyEdge(source: secondID, target: firstID)
            ]
        )
        let wrongOrderGraph = DesignGraph(
            nodes: nodes,
            order: [secondID, firstID],
            dependencies: [DependencyEdge(source: firstID, target: secondID)]
        )
        let duplicateDependencyGraph = DesignGraph(
            nodes: nodes,
            order: [firstID, secondID],
            dependencies: [
                DependencyEdge(source: firstID, target: secondID),
                DependencyEdge(source: firstID, target: secondID)
            ]
        )

        #expect(throws: FeatureEvaluationError.self) {
            try cyclicGraph.validate()
        }
        #expect(throws: FeatureEvaluationError.self) {
            try wrongOrderGraph.validate()
        }
        #expect(throws: FeatureEvaluationError.self) {
            try duplicateDependencyGraph.validate()
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func designGraphRejectsInvalidFeatureInputs() {
        let firstID = FeatureID()
        let secondID = FeatureID()
        let missingID = FeatureID()
        let missingInputNodes = [
            firstID: FeatureNode(
                id: firstID,
                operation: .extrude(ExtrudeFeature(
                    profile: ProfileReference(featureID: missingID),
                    distance: .constant(.length(1.0, unit: .meter))
                )),
                inputs: [FeatureInput(featureID: missingID, role: .profile)],
                outputs: [FeatureOutput(role: .body)]
            )
        ]
        let wrongOrderNodes = [
            firstID: FeatureNode(
                id: firstID,
                operation: .sketch(Sketch(plane: .xy)),
                outputs: [FeatureOutput(role: .profile)]
            ),
            secondID: FeatureNode(
                id: secondID,
                operation: .extrude(ExtrudeFeature(
                    profile: ProfileReference(featureID: firstID),
                    distance: .constant(.length(1.0, unit: .meter))
                )),
                inputs: [FeatureInput(featureID: firstID, role: .profile)],
                outputs: [FeatureOutput(role: .body)]
            )
        ]
        let missingInputGraph = DesignGraph(
            nodes: missingInputNodes,
            order: [firstID],
            dependencies: []
        )
        let wrongInputOrderGraph = DesignGraph(
            nodes: wrongOrderNodes,
            order: [secondID, firstID],
            dependencies: []
        )

        #expect(throws: FeatureEvaluationError.self) {
            try missingInputGraph.validate()
        }
        #expect(throws: FeatureEvaluationError.self) {
            try wrongInputOrderGraph.validate()
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func designGraphRejectsOperationContractViolations() {
        let sketchID = FeatureID()
        let extrudeID = FeatureID()
        let sketchWithoutOutput = DesignGraph(
            nodes: [
                sketchID: FeatureNode(id: sketchID, operation: .sketch(Sketch(plane: .xy)))
            ],
            order: [sketchID]
        )
        let extrudeWithoutBodyOutput = DesignGraph(
            nodes: [
                sketchID: FeatureNode(
                    id: sketchID,
                    operation: .sketch(Sketch(plane: .xy)),
                    outputs: [FeatureOutput(role: .profile)]
                ),
                extrudeID: FeatureNode(
                    id: extrudeID,
                    operation: .extrude(ExtrudeFeature(
                        profile: ProfileReference(featureID: sketchID),
                        distance: .constant(.length(1.0, unit: .meter))
                    )),
                    inputs: [FeatureInput(featureID: sketchID, role: .profile)]
                )
            ],
            order: [sketchID, extrudeID],
            dependencies: [DependencyEdge(source: sketchID, target: extrudeID)]
        )

        #expect(throws: FeatureEvaluationError.self) {
            try sketchWithoutOutput.validate()
        }
        #expect(throws: FeatureEvaluationError.self) {
            try extrudeWithoutBodyOutput.validate()
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func designGraphRejectsInputsWithoutDependencyEdges() {
        let sketchID = FeatureID()
        let extrudeID = FeatureID()
        let graph = DesignGraph(
            nodes: [
                sketchID: FeatureNode(
                    id: sketchID,
                    operation: .sketch(Sketch(plane: .xy)),
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
            dependencies: []
        )

        #expect(throws: FeatureEvaluationError.self) {
            try graph.validate()
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func designGraphRejectsDependencyEdgesWithoutFeatureInputs() {
        let firstID = FeatureID()
        let secondID = FeatureID()
        let graph = DesignGraph(
            nodes: [
                firstID: FeatureNode(
                    id: firstID,
                    operation: .sketch(Sketch(plane: .xy)),
                    outputs: [FeatureOutput(role: .profile)]
                ),
                secondID: FeatureNode(
                    id: secondID,
                    operation: .sketch(Sketch(plane: .xy)),
                    outputs: [FeatureOutput(role: .profile)]
                )
            ],
            order: [firstID, secondID],
            dependencies: [DependencyEdge(source: firstID, target: secondID)]
        )

        #expect(throws: FeatureEvaluationError.self) {
            try graph.validate()
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func designGraphRejectsActiveFeaturesDependingOnSuppressedSources() {
        let sketchID = FeatureID()
        let extrudeID = FeatureID()
        let graph = DesignGraph(
            nodes: [
                sketchID: FeatureNode(
                    id: sketchID,
                    operation: .sketch(Sketch(plane: .xy)),
                    outputs: [FeatureOutput(role: .profile)],
                    isSuppressed: true
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

        #expect(throws: FeatureEvaluationError.self) {
            try graph.validate()
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func sketchValidationRejectsInvalidReferences() {
        let circleID = SketchEntityID()
        let sketch = Sketch(
            plane: .xy,
            entities: [
                circleID: .circle(SketchCircle(
                    center: SketchPoint(
                        x: .constant(.length(0.0, unit: .meter)),
                        y: .constant(.length(0.0, unit: .meter))
                    ),
                    radius: .constant(.length(1.0, unit: .meter))
                ))
            ],
            constraints: [.horizontal(circleID)],
            dimensions: []
        )

        #expect(throws: SketchError.self) {
            try sketch.validate()
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func sketchBuildsSolverReadyConstraintGraph() throws {
        let lineID = SketchEntityID()
        let circleID = SketchEntityID()
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
                )),
                circleID: .circle(SketchCircle(
                    center: SketchPoint(
                        x: .constant(.length(0.5, unit: .meter)),
                        y: .constant(.length(0.5, unit: .meter))
                    ),
                    radius: .constant(.length(0.25, unit: .meter))
                ))
            ],
            constraints: [
                .horizontal(lineID),
                .coincident(.lineStart(lineID), .circleCenter(circleID))
            ],
            dimensions: [
                .radius(entity: circleID, value: .constant(.length(0.25, unit: .meter)))
            ]
        )

        let graph = try sketch.constraintGraph()

        #expect(graph.equations.map(\.kind) == [.horizontal, .coincident, .radius])
        #expect(graph.nodes.contains(SketchConstraintNode(reference: .entity(lineID), degreeOfFreedom: .angle)))
        #expect(graph.nodes.contains(SketchConstraintNode(reference: .circleRadius(circleID), degreeOfFreedom: .radius)))
    }

    @Test(.timeLimit(.minutes(1)))
    func curveAndSurfaceDomainsAreExplicitAndValidated() throws {
        let line = Curve3D.line(Line3D(origin: Point3D(x: 0.0, y: 0.0, z: 0.0), direction: .unitX))
        let circle = Curve3D.circle(Circle3D(center: Point3D(x: 0.0, y: 0.0, z: 0.0), normal: .unitZ, radius: 1.0))
        let plane = Surface3D.plane(Plane3D(origin: Point3D(x: 0.0, y: 0.0, z: 0.0), normal: .unitZ))

        #expect(line.parameterDomain == .unbounded)
        #expect(circle.parameterDomain == .periodic(period: Double.pi * 2.0))
        #expect(plane.uDomain == .unbounded)
        #expect(plane.vDomain == .unbounded)
        #expect(try circle.parameterDomain.containsSpan(from: -Double.pi, to: Double.pi))
        #expect(throws: GeometryError.self) {
            try ParameterDomain.closed(1.0, 1.0).validate()
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func documentValidationRejectsNonLengthSketchDimensionExpressions() {
        let circleID = SketchEntityID()
        let sketchID = FeatureID()
        let sketch = Sketch(
            plane: .xy,
            entities: [
                circleID: .circle(SketchCircle(
                    center: SketchPoint(
                        x: .constant(.length(0.0, unit: .meter)),
                        y: .constant(.length(0.0, unit: .meter))
                    ),
                    radius: .constant(.length(1.0, unit: .meter))
                ))
            ],
            dimensions: [.radius(entity: circleID, value: .constant(.scalar(1.0)))]
        )
        let document = CADDocument(
            units: .meters,
            designGraph: DesignGraph(
                nodes: [
                    sketchID: FeatureNode(
                        id: sketchID,
                        operation: .sketch(sketch),
                        outputs: [FeatureOutput(role: .profile)]
                    )
                ],
                order: [sketchID]
            )
        )

        #expect(throws: UnitError.self) {
            try document.validate()
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func documentValidationRejectsNonResolvableSourceExpressions() {
        let pointID = SketchEntityID()
        let sketchID = FeatureID()
        let sketch = Sketch(
            plane: .xy,
            entities: [
                pointID: .point(SketchPoint(
                    x: .divide(.constant(.length(1.0, unit: .meter)), .constant(.scalar(0.0))),
                    y: .constant(.length(0.0, unit: .meter))
                ))
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
                    )
                ],
                order: [sketchID]
            )
        )

        #expect(throws: UnitError.self) {
            try document.validate()
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func documentValidationRejectsNonPositiveResolvedDimensions() {
        let radiusID = ParameterID()
        let circleID = SketchEntityID()
        let sketchID = FeatureID()
        let invalidCircleSketch = Sketch(
            plane: .xy,
            entities: [
                circleID: .circle(SketchCircle(
                    center: SketchPoint(
                        x: .constant(.length(0.0, unit: .meter)),
                        y: .constant(.length(0.0, unit: .meter))
                    ),
                    radius: .reference(radiusID)
                ))
            ],
            dimensions: [.diameter(entity: circleID, value: .constant(.length(0.0, unit: .meter)))]
        )
        let invalidCircleDocument = CADDocument(
            units: .meters,
            parameters: ParameterTable(parameters: [
                radiusID: Parameter(
                    id: radiusID,
                    name: "radius",
                    expression: .constant(.length(-1.0, unit: .meter)),
                    kind: .length
                )
            ]),
            designGraph: DesignGraph(
                nodes: [
                    sketchID: FeatureNode(
                        id: sketchID,
                        operation: .sketch(invalidCircleSketch),
                        outputs: [FeatureOutput(role: .profile)]
                    )
                ],
                order: [sketchID]
            )
        )

        #expect(throws: GeometryError.self) {
            try invalidCircleDocument.validate()
        }

        let validCircleID = SketchEntityID()
        let invalidDimensionSketchID = FeatureID()
        let invalidDimensionSketch = Sketch(
            plane: .xy,
            entities: [
                validCircleID: .circle(SketchCircle(
                    center: SketchPoint(
                        x: .constant(.length(0.0, unit: .meter)),
                        y: .constant(.length(0.0, unit: .meter))
                    ),
                    radius: .constant(.length(1.0, unit: .meter))
                ))
            ],
            dimensions: [.diameter(entity: validCircleID, value: .constant(.length(0.0, unit: .meter)))]
        )
        let invalidDimensionDocument = CADDocument(
            units: .meters,
            designGraph: DesignGraph(
                nodes: [
                    invalidDimensionSketchID: FeatureNode(
                        id: invalidDimensionSketchID,
                        operation: .sketch(invalidDimensionSketch),
                        outputs: [FeatureOutput(role: .profile)]
                    )
                ],
                order: [invalidDimensionSketchID]
            )
        )

        #expect(throws: GeometryError.self) {
            try invalidDimensionDocument.validate()
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func documentValidationRejectsNonPositiveExtrudeDistance() {
        let sketchID = FeatureID()
        let extrudeID = FeatureID()
        let document = CADDocument(
            units: .meters,
            designGraph: DesignGraph(
                nodes: [
                    sketchID: FeatureNode(
                        id: sketchID,
                        operation: .sketch(Sketch(plane: .xy)),
                        outputs: [FeatureOutput(role: .profile)]
                    ),
                    extrudeID: FeatureNode(
                        id: extrudeID,
                        operation: .extrude(ExtrudeFeature(
                            profile: ProfileReference(featureID: sketchID),
                            distance: .constant(.length(0.0, unit: .meter))
                        )),
                        inputs: [FeatureInput(featureID: sketchID, role: .profile)],
                        outputs: [FeatureOutput(role: .body)]
                    )
                ],
                order: [sketchID, extrudeID],
                dependencies: [DependencyEdge(source: sketchID, target: extrudeID)]
            )
        )

        #expect(throws: FeatureEvaluationError.self) {
            try document.validate()
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func featureOperationUsesStableKindDiscriminator() throws {
        let sketch = Sketch(plane: .xy)
        let operation = FeatureOperation.sketch(sketch)
        let data = try JSONEncoder().encode(operation)
        let json = try #require(String(data: data, encoding: .utf8))
        #expect(json.contains("\"kind\":\"sketch\""))
    }

    @Test(.timeLimit(.minutes(1)))
    func unionDecodersRejectInactivePayloadKeys() throws {
        let point = SketchPoint(
            x: .constant(.length(0.0, unit: .meter)),
            y: .constant(.length(0.0, unit: .meter))
        )

        var operationObject = try jsonObject(from: JSONEncoder().encode(FeatureOperation.sketch(Sketch(plane: .xy))))
        operationObject["extrude"] = try jsonObject(from: JSONEncoder().encode(ExtrudeFeature(
            profile: ProfileReference(featureID: FeatureID()),
            distance: .constant(.length(1.0, unit: .meter))
        )))
        try expectDecodingFailure(FeatureOperation.self, from: operationObject)

        let lineObject = try jsonObject(from: JSONEncoder().encode(SketchEntity.line(SketchLine(start: point, end: point))))
        var entityObject = try jsonObject(from: JSONEncoder().encode(SketchEntity.point(point)))
        entityObject["line"] = lineObject["line"]
        try expectDecodingFailure(SketchEntity.self, from: entityObject)

        var directionObject = try jsonObject(from: JSONEncoder().encode(ExtrudeDirection.normal))
        directionObject["vector"] = try jsonObject(from: JSONEncoder().encode(Vector3D.unitZ))
        try expectDecodingFailure(ExtrudeDirection.self, from: directionObject)

        var planeObject = try jsonObject(from: JSONEncoder().encode(SketchPlane.xy))
        planeObject["plane"] = try jsonObject(from: JSONEncoder().encode(Plane3D(origin: .origin, normal: .unitZ)))
        try expectDecodingFailure(SketchPlane.self, from: planeObject)

        var nameComponentObject = try jsonObject(from: JSONEncoder().encode(NameComponent.feature(FeatureID())))
        nameComponentObject["value"] = "inactive"
        try expectDecodingFailure(NameComponent.self, from: nameComponentObject)

        var sketchReferenceObject = try jsonObject(from: JSONEncoder().encode(SketchReference.entity(SketchEntityID())))
        sketchReferenceObject["inactive"] = "payload"
        try expectDecodingFailure(SketchReference.self, from: sketchReferenceObject)
    }

    private func expectDecodingFailure<T: Decodable>(_ type: T.Type, from object: [String: Any]) throws {
        let data = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])

        #expect(throws: DecodingError.self) {
            _ = try JSONDecoder().decode(type, from: data)
        }
    }

    private func jsonObject(from data: Data) throws -> [String: Any] {
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw SchemaError.invalidPackage("Expected JSON object fixture.")
        }
        return object
    }

    @Test(.timeLimit(.minutes(1)))
    func meshValidationRejectsInvalidIndices() {
        let mesh = Mesh(
            positions: [Point3D.origin],
            normals: [],
            indices: [0, 1, 2]
        )

        #expect(throws: ExportError.self) {
            try mesh.validate()
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func meshValidationRejectsUnreferencedPositions() {
        let mesh = Mesh(
            positions: [
                Point3D(x: 0.0, y: 0.0, z: 0.0),
                Point3D(x: 1.0, y: 0.0, z: 0.0),
                Point3D(x: 0.0, y: 1.0, z: 0.0),
                Point3D(x: 10.0, y: 10.0, z: 10.0)
            ],
            normals: [],
            indices: [0, 1, 2]
        )

        #expect(throws: ExportError.self) {
            try mesh.validate()
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func meshValidationRejectsNonFiniteCoordinates() {
        let badPositionMesh = Mesh(
            positions: [
                Point3D(x: .nan, y: 0.0, z: 0.0),
                Point3D(x: 1.0, y: 0.0, z: 0.0),
                Point3D(x: 0.0, y: 1.0, z: 0.0)
            ],
            normals: [],
            indices: [0, 1, 2]
        )
        let badNormalMesh = Mesh(
            positions: [
                Point3D(x: 0.0, y: 0.0, z: 0.0),
                Point3D(x: 1.0, y: 0.0, z: 0.0),
                Point3D(x: 0.0, y: 1.0, z: 0.0)
            ],
            normals: [
                Vector3D(x: .infinity, y: 0.0, z: 1.0),
                Vector3D(x: 0.0, y: 0.0, z: 1.0),
                Vector3D(x: 0.0, y: 0.0, z: 1.0)
            ],
            indices: [0, 1, 2]
        )

        #expect(throws: ExportError.self) {
            try badPositionMesh.validate()
        }
        #expect(throws: ExportError.self) {
            try badNormalMesh.validate()
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func meshValidationRejectsInvalidTextureCoordinates() {
        let mismatchedTextureCoordinateMesh = Mesh(
            positions: [
                Point3D(x: 0.0, y: 0.0, z: 0.0),
                Point3D(x: 1.0, y: 0.0, z: 0.0),
                Point3D(x: 0.0, y: 1.0, z: 0.0)
            ],
            normals: [],
            indices: [0, 1, 2],
            textureCoordinates: [
                Point2D(x: 0.0, y: 0.0),
                Point2D(x: 1.0, y: 0.0)
            ]
        )
        let nonFiniteTextureCoordinateMesh = Mesh(
            positions: [
                Point3D(x: 0.0, y: 0.0, z: 0.0),
                Point3D(x: 1.0, y: 0.0, z: 0.0),
                Point3D(x: 0.0, y: 1.0, z: 0.0)
            ],
            normals: [],
            indices: [0, 1, 2],
            textureCoordinates: [
                Point2D(x: 0.0, y: 0.0),
                Point2D(x: .nan, y: 0.0),
                Point2D(x: 0.0, y: 1.0)
            ]
        )

        #expect(throws: ExportError.self) {
            try mismatchedTextureCoordinateMesh.validate()
        }
        #expect(throws: ExportError.self) {
            try nonFiniteTextureCoordinateMesh.validate()
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func meshValidationRejectsInvalidVertexColors() {
        let mismatchedVertexColorMesh = Mesh(
            positions: [
                Point3D(x: 0.0, y: 0.0, z: 0.0),
                Point3D(x: 1.0, y: 0.0, z: 0.0),
                Point3D(x: 0.0, y: 1.0, z: 0.0)
            ],
            normals: [],
            indices: [0, 1, 2],
            vertexColors: [
                ColorRGBA(r: 1.0, g: 0.0, b: 0.0, a: 1.0),
                ColorRGBA(r: 0.0, g: 1.0, b: 0.0, a: 1.0)
            ]
        )
        let outOfRangeVertexColorMesh = Mesh(
            positions: [
                Point3D(x: 0.0, y: 0.0, z: 0.0),
                Point3D(x: 1.0, y: 0.0, z: 0.0),
                Point3D(x: 0.0, y: 1.0, z: 0.0)
            ],
            normals: [],
            indices: [0, 1, 2],
            vertexColors: [
                ColorRGBA(r: 1.0, g: 0.0, b: 0.0, a: 1.0),
                ColorRGBA(r: 0.0, g: 2.0, b: 0.0, a: 1.0),
                ColorRGBA(r: 0.0, g: 0.0, b: 1.0, a: 1.0)
            ]
        )

        #expect(throws: ExportError.self) {
            try mismatchedVertexColorMesh.validate()
        }
        #expect(throws: ExportError.self) {
            try outOfRangeVertexColorMesh.validate()
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func meshDecodingDefaultsMissingOptionalVertexAttributesToEmpty() throws {
        let data = Data("""
        {
            "positions": [
                { "x": 0, "y": 0, "z": 0 },
                { "x": 1, "y": 0, "z": 0 },
                { "x": 0, "y": 1, "z": 0 }
            ],
            "normals": [],
            "indices": [0, 1, 2]
        }
        """.utf8)

        let mesh = try JSONDecoder().decode(Mesh.self, from: data)

        #expect(mesh.textureCoordinates == [])
        #expect(mesh.vertexColors == [])
    }

    @Test(.timeLimit(.minutes(1)))
    func meshValidationRejectsNonUnitNormals() {
        let mesh = Mesh(
            positions: [
                Point3D(x: 0.0, y: 0.0, z: 0.0),
                Point3D(x: 1.0, y: 0.0, z: 0.0),
                Point3D(x: 0.0, y: 1.0, z: 0.0)
            ],
            normals: [
                Vector3D(x: 0.0, y: 0.0, z: 2.0),
                Vector3D.unitZ,
                Vector3D.unitZ
            ],
            indices: [0, 1, 2]
        )

        #expect(throws: ExportError.self) {
            try mesh.validate()
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func meshValidationRejectsNormalsOpposingTriangleWinding() {
        let mesh = Mesh(
            positions: [
                Point3D(x: 0.0, y: 0.0, z: 0.0),
                Point3D(x: 1.0, y: 0.0, z: 0.0),
                Point3D(x: 0.0, y: 1.0, z: 0.0)
            ],
            normals: [
                -Vector3D.unitZ,
                -Vector3D.unitZ,
                -Vector3D.unitZ
            ],
            indices: [0, 1, 2]
        )

        #expect(throws: ExportError.self) {
            try mesh.validate()
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func meshValidationRejectsDegenerateTriangles() {
        let repeatedIndexMesh = Mesh(
            positions: [
                Point3D(x: 0.0, y: 0.0, z: 0.0),
                Point3D(x: 1.0, y: 0.0, z: 0.0),
                Point3D(x: 0.0, y: 1.0, z: 0.0)
            ],
            normals: [],
            indices: [0, 1, 1]
        )
        let collinearMesh = Mesh(
            positions: [
                Point3D(x: 0.0, y: 0.0, z: 0.0),
                Point3D(x: 1.0, y: 0.0, z: 0.0),
                Point3D(x: 2.0, y: 0.0, z: 0.0)
            ],
            normals: [],
            indices: [0, 1, 2]
        )

        #expect(throws: ExportError.self) {
            try repeatedIndexMesh.validate()
        }
        #expect(throws: ExportError.self) {
            try collinearMesh.validate()
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func meshValidationRejectsTriangleAreaOverflow() {
        let mesh = Mesh(
            positions: [
                Point3D(x: 0.0, y: 0.0, z: 0.0),
                Point3D(x: 1.0e308, y: 0.0, z: 0.0),
                Point3D(x: 0.0, y: 1.0e308, z: 0.0)
            ],
            normals: [],
            indices: [0, 1, 2]
        )

        #expect(throws: ExportError.self) {
            try mesh.validate()
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func validationRejectsInvalidModelingToleranceAtIRBoundary() {
        let mesh = Mesh(
            positions: [
                Point3D(x: 0.0, y: 0.0, z: 0.0),
                Point3D(x: 1.0, y: 0.0, z: 0.0),
                Point3D(x: 0.0, y: 1.0, z: 0.0)
            ],
            normals: [],
            indices: [0, 1, 2]
        )

        #expect(throws: GeometryError.self) {
            try mesh.validate(tolerance: ModelingTolerance(distance: -1.0, angle: 1.0e-9))
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func tessellationOptionsRejectNonFiniteAndNonPositiveValues() {
        #expect(throws: TessellationError.self) {
            try TessellationOptions(linearTolerance: .infinity, angularTolerance: 1.0e-3).validate()
        }
        #expect(throws: TessellationError.self) {
            try TessellationOptions(linearTolerance: 1.0e-4, angularTolerance: 0.0).validate()
        }
        #expect(throws: TessellationError.self) {
            try TessellationOptions(
                linearTolerance: 1.0e-4,
                angularTolerance: 1.0e-3,
                maxEdgeLength: .nan
            ).validate()
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func materialValidationRejectsOutOfRangeValues() {
        let badColor = ColorRGBA(r: 1.2, g: 0.0, b: 0.0, a: 1.0)
        let badMaterial = Material(
            name: "Invalid",
            baseColor: ColorRGBA(r: 1.0, g: 1.0, b: 1.0, a: 1.0),
            metallic: 0.0,
            roughness: .nan,
            opacity: 1.0
        )

        #expect(throws: MaterialError.self) {
            try badColor.validate()
        }
        #expect(throws: MaterialError.self) {
            try badMaterial.validate()
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func geometryValidationRejectsNonFiniteAndNonUnitDirections() {
        let badLine = Line3D(
            origin: Point3D(x: .nan, y: 0.0, z: 0.0),
            direction: Vector3D.unitX
        )
        let nonUnitPlane = Plane3D(
            origin: .origin,
            normal: Vector3D(x: 2.0, y: 0.0, z: 0.0)
        )

        #expect(throws: GeometryError.self) {
            try badLine.validate()
        }
        #expect(throws: GeometryError.self) {
            try nonUnitPlane.validate()
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func brepValidationRejectsSameDirectionEdgeUse() throws {
        let model = makeTwoFaceTriangleModelWithSameEdgeOrientations()

        #expect(throws: TopologyError.self) {
            try model.validate()
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func brepValidationRejectsDuplicateTopologyOwnershipReferences() throws {
        try makeClosedTetrahedronModel().validate()

        var duplicateShellModel = makeClosedTetrahedronModel()
        let bodyID = try #require(duplicateShellModel.bodies.keys.first)
        let shellID = try #require(duplicateShellModel.shells.keys.first)
        duplicateShellModel.bodies[bodyID]?.shellIDs.append(shellID)

        var duplicateFaceModel = makeClosedTetrahedronModel()
        let duplicateFaceShellID = try #require(duplicateFaceModel.shells.keys.first)
        let faceID = try #require(duplicateFaceModel.faces.keys.first)
        duplicateFaceModel.shells[duplicateFaceShellID]?.faceIDs.append(faceID)

        var duplicateLoopModel = makeClosedTetrahedronModel()
        let duplicateLoopFaceID = try #require(duplicateLoopModel.faces.keys.first)
        let loopID = try #require(duplicateLoopModel.loops.keys.first)
        duplicateLoopModel.faces[duplicateLoopFaceID]?.loops.append(loopID)

        var duplicateLoopEdgeModel = makeClosedTetrahedronModel()
        let duplicateEdgeLoopID = try #require(duplicateLoopEdgeModel.loops.keys.first)
        let orientedEdge = try #require(duplicateLoopEdgeModel.loops[duplicateEdgeLoopID]?.edges.first)
        duplicateLoopEdgeModel.loops[duplicateEdgeLoopID]?.edges.append(orientedEdge)

        #expect(throws: TopologyError.self) {
            try duplicateShellModel.validate()
        }
        #expect(throws: TopologyError.self) {
            try duplicateFaceModel.validate()
        }
        #expect(throws: TopologyError.self) {
            try duplicateLoopModel.validate()
        }
        #expect(throws: TopologyError.self) {
            try duplicateLoopEdgeModel.validate()
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func brepValidationRejectsTopologySharingAcrossShells() throws {
        var model = makeClosedTetrahedronModel()
        let bodyID = try #require(model.bodies.keys.first)
        let originalShellID = try #require(model.shells.keys.first)
        let originalFaceIDs = try #require(model.shells[originalShellID]?.faceIDs)
        var copiedFaceIDs: [FaceID] = []
        for originalFaceID in originalFaceIDs {
            let originalFace = try #require(model.faces[originalFaceID])
            let originalLoopID = try #require(originalFace.loops.first)
            let originalLoop = try #require(model.loops[originalLoopID])
            let copiedLoopID = LoopID()
            let copiedFaceID = FaceID()
            model.loops[copiedLoopID] = Loop(
                id: copiedLoopID,
                role: originalLoop.role,
                edges: originalLoop.edges
            )
            model.faces[copiedFaceID] = Face(
                id: copiedFaceID,
                surfaceID: originalFace.surfaceID,
                loops: [copiedLoopID],
                orientation: originalFace.orientation
            )
            copiedFaceIDs.append(copiedFaceID)
        }
        let copiedShellID = ShellID()
        model.shells[copiedShellID] = Shell(id: copiedShellID, faceIDs: copiedFaceIDs)
        model.bodies[bodyID]?.shellIDs.append(copiedShellID)

        #expect(throws: TopologyError.self) {
            try model.validate()
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func brepValidationRejectsUnreferencedTopologyAndInvalidVertexValues() {
        let vertexID = VertexID()
        let orphanModel = BRepModel(
            vertices: [vertexID: Vertex(id: vertexID, point: .origin)]
        )
        let invalidVertexModel = BRepModel(
            vertices: [vertexID: Vertex(id: vertexID, point: Point3D(x: .infinity, y: 0.0, z: 0.0))]
        )

        #expect(throws: TopologyError.self) {
            try orphanModel.validate()
        }
        #expect(throws: GeometryError.self) {
            try invalidVertexModel.validate()
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func brepValidationRejectsFaceLoopGeometryOffSurface() throws {
        var model = makeClosedTetrahedronModel()
        let faceID = try #require(model.faces.keys.first)
        let surfaceID = try #require(model.faces[faceID]?.surfaceID)
        model.geometry.surfaces[surfaceID] = .plane(Plane3D(
            origin: Point3D(x: 0.0, y: 0.0, z: 10.0),
            normal: Vector3D.unitZ
        ))

        #expect(throws: TopologyError.self) {
            try model.validate()
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func brepValidationRejectsLoopClosedByCoincidentDifferentVertexID() throws {
        var model = makeClosedTetrahedronModel()
        let sharedPoint = Point3D.origin
        let sharedVertexID = try #require(model.vertices.first { $0.value.point == sharedPoint }?.key)
        let splitVertexID = VertexID()
        let splitEdgeID = try #require(model.edges.first { _, edge in
            edge.startVertexID == sharedVertexID
                && model.vertices[edge.endVertexID]?.point == Point3D(x: 0.0, y: 1.0, z: 0.0)
        }?.key)
        model.vertices[splitVertexID] = Vertex(id: splitVertexID, point: sharedPoint)
        model.edges[splitEdgeID]?.startVertexID = splitVertexID

        #expect(throws: TopologyError.self) {
            try model.validate()
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func brepValidationRejectsInvalidTrimAndLoopRoles() {
        var invalidTrimModel = makeTwoFaceTriangleModelWithSameEdgeOrientations()
        if let edgeID = invalidTrimModel.edges.keys.first {
            invalidTrimModel.edges[edgeID]?.trim = CurveTrim(startParameter: .nan, endParameter: 1.0)
        }
        var invalidLoopRoleModel = makeTwoFaceTriangleModelWithSameEdgeOrientations()
        if let loopID = invalidLoopRoleModel.loops.keys.first {
            invalidLoopRoleModel.loops[loopID]?.role = .inner
        }

        #expect(throws: TopologyError.self) {
            try invalidTrimModel.validate()
        }
        #expect(throws: TopologyError.self) {
            try invalidLoopRoleModel.validate()
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func brepValidationRejectsUntrimmedCircularEdges() throws {
        var model = makeTwoFaceTriangleModelWithBalancedEdgeOrientations()
        let edgeID = try #require(model.edges.first { _, edge in
            model.vertices[edge.startVertexID]?.point == Point3D(x: 0.0, y: 0.0, z: 0.0)
                && model.vertices[edge.endVertexID]?.point == Point3D(x: 1.0, y: 0.0, z: 0.0)
        }?.key)
        let edge = try #require(model.edges[edgeID])
        let curveID = edge.curveID
        let center = Point3D(x: 0.5, y: 0.0, z: 0.0)
        model.geometry.curves[curveID] = .circle(Circle3D(center: center, normal: Vector3D.unitZ, radius: 0.5))

        #expect(throws: TopologyError.self) {
            try model.validate()
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func brepValidationRejectsCoincidentOppositeFacesAsNonSolidShell() {
        let model = makeTwoFaceTriangleModelWithBalancedEdgeOrientations()

        #expect(throws: TopologyError.self) {
            try model.validate()
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func brepValidationUsesAngularToleranceForCircularTrimSpans() throws {
        let model = try makeTwoFaceTriangleModelWithCircularEdge(
            radius: 10_000_000.0,
            span: 1.0e-7
        )

        try model.validate()
    }

    @Test(.timeLimit(.minutes(1)))
    func brepValidationRejectsDegenerateLineTrimSpans() throws {
        var model = makeTwoFaceTriangleModelWithBalancedEdgeOrientations()
        let edgeID = try #require(model.edges.keys.first)
        model.edges[edgeID]?.trim = CurveTrim(
            startParameter: 0.0,
            endParameter: ModelingTolerance.standard.distance / 2.0
        )

        #expect(throws: TopologyError.self) {
            try model.validate()
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func brepValidationRejectsLineOnlyLoopsWithoutArea() {
        let model = makeTwoFaceLineSegmentModelWithoutLoopArea()

        #expect(throws: TopologyError.self) {
            try model.validate()
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func documentValidationRejectsInvalidParameterReferences() {
        let missingID = ParameterID()
        let badID = ParameterID()
        let document = CADDocument(
            units: .millimeters,
            parameters: ParameterTable(parameters: [
                badID: Parameter(
                    id: badID,
                    name: "bad",
                    expression: .reference(missingID),
                    kind: .length
                )
            ])
        )

        #expect(throws: ParameterError.self) {
            try document.validate()
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func documentValidationRejectsNonResolvableParameterValues() {
        let zeroID = ParameterID()
        let dividedID = ParameterID()
        let zeroDivisionDocument = CADDocument(
            units: .meters,
            parameters: ParameterTable(parameters: [
                zeroID: Parameter(
                    id: zeroID,
                    name: "zero",
                    expression: .constant(.scalar(0.0)),
                    kind: .scalar
                ),
                dividedID: Parameter(
                    id: dividedID,
                    name: "divided",
                    expression: .divide(.constant(.length(1.0, unit: .meter)), .reference(zeroID)),
                    kind: .length
                )
            ])
        )

        let hugeID = ParameterID()
        let overflowID = ParameterID()
        let overflowDocument = CADDocument(
            units: .meters,
            parameters: ParameterTable(parameters: [
                hugeID: Parameter(
                    id: hugeID,
                    name: "huge",
                    expression: .constant(.scalar(Double.greatestFiniteMagnitude)),
                    kind: .scalar
                ),
                overflowID: Parameter(
                    id: overflowID,
                    name: "overflow",
                    expression: .multiply(.reference(hugeID), .constant(.scalar(2.0))),
                    kind: .scalar
                )
            ])
        )

        #expect(throws: UnitError.self) {
            try zeroDivisionDocument.validate()
        }
        #expect(throws: UnitError.self) {
            try overflowDocument.validate()
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func documentValidationRejectsInvalidParameterNames() {
        let badID = ParameterID()
        let document = CADDocument(
            units: .millimeters,
            parameters: ParameterTable(parameters: [
                badID: Parameter(
                    id: badID,
                    name: "bad name",
                    expression: .constant(.length(1.0, unit: .meter)),
                    kind: .length
                )
            ])
        )

        #expect(throws: ParameterError.self) {
            try document.validate()
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func documentValidationRejectsUnboundVariablesInSourceExpressions() {
        let pointID = SketchEntityID()
        let sketchID = FeatureID()
        let sketch = Sketch(
            plane: .xy,
            entities: [
                pointID: .point(SketchPoint(
                    x: .variable("externalX", .length),
                    y: .constant(.length(0.0, unit: .meter))
                ))
            ]
        )
        let document = CADDocument(
            units: .millimeters,
            designGraph: DesignGraph(
                nodes: [
                    sketchID: FeatureNode(
                        id: sketchID,
                        operation: .sketch(sketch),
                        outputs: [FeatureOutput(role: .profile)]
                    )
                ],
                order: [sketchID]
            )
        )

        #expect(throws: ParameterError.self) {
            try document.validate()
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func documentValidationRejectsUnboundVariablesInParameters() {
        let badID = ParameterID()
        let document = CADDocument(
            units: .millimeters,
            parameters: ParameterTable(parameters: [
                badID: Parameter(
                    id: badID,
                    name: "width",
                    expression: .variable("externalWidth", .length),
                    kind: .length
                )
            ])
        )

        #expect(throws: ParameterError.self) {
            try document.validate()
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func documentValidationRejectsNonFiniteParameterValues() {
        let badID = ParameterID()
        let document = CADDocument(
            units: .millimeters,
            parameters: ParameterTable(parameters: [
                badID: Parameter(
                    id: badID,
                    name: "bad",
                    expression: .constant(.length(.nan, unit: .meter)),
                    kind: .length
                )
            ])
        )

        #expect(throws: UnitError.self) {
            try document.validate()
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func documentValidationRejectsParameterTableKeyMismatch() {
        let tableKey = ParameterID()
        let embeddedID = ParameterID()
        let document = CADDocument(
            units: .millimeters,
            parameters: ParameterTable(parameters: [
                tableKey: Parameter(
                    id: embeddedID,
                    name: "width",
                    expression: .constant(.length(1.0, unit: .meter)),
                    kind: .length
                )
            ])
        )

        #expect(throws: ParameterError.self) {
            try document.validate()
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func documentValidationRejectsNegativeRevisions() {
        let parameterRevisionDocument = CADDocument(
            units: .meters,
            parameters: ParameterTable(revision: DocumentRevision(-1))
        )
        let designRevisionDocument = CADDocument(
            units: .meters,
            designGraph: DesignGraph(revision: DocumentRevision(-1))
        )

        #expect(throws: SchemaError.self) {
            try parameterRevisionDocument.validate()
        }
        #expect(throws: SchemaError.self) {
            try designRevisionDocument.validate()
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func documentValidationRejectsInvalidMetadataTimestamps() {
        let createdAt = Date(timeIntervalSinceReferenceDate: 100.0)
        let earlierUpdatedAt = Date(timeIntervalSinceReferenceDate: 99.0)
        let nonFiniteCreatedAt = Date(timeIntervalSinceReferenceDate: .nan)
        let orderedDocument = CADDocument(
            units: .meters,
            metadata: DocumentMetadata(createdAt: createdAt, updatedAt: earlierUpdatedAt)
        )
        let nonFiniteDocument = CADDocument(
            units: .meters,
            metadata: DocumentMetadata(createdAt: nonFiniteCreatedAt, updatedAt: createdAt)
        )

        #expect(throws: SchemaError.self) {
            try orderedDocument.validate()
        }
        #expect(throws: SchemaError.self) {
            try nonFiniteDocument.validate()
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func documentValidationRejectsFutureSchemaVersion() {
        let document = CADDocument(
            schemaVersion: SchemaVersion(major: 1, minor: 1, patch: 0),
            units: .millimeters
        )

        #expect(throws: SchemaError.self) {
            try document.validate()
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func documentValidationRejectsNegativeSchemaVersion() {
        let document = CADDocument(
            schemaVersion: SchemaVersion(major: 1, minor: -1, patch: 0),
            units: .millimeters
        )

        #expect(throws: SchemaError.self) {
            try document.validate()
        }
    }
}

private func makeClosedTetrahedronModel() -> BRepModel {
    let firstVertexID = VertexID()
    let secondVertexID = VertexID()
    let thirdVertexID = VertexID()
    let fourthVertexID = VertexID()
    let firstPoint = Point3D(x: 0.0, y: 0.0, z: 0.0)
    let secondPoint = Point3D(x: 1.0, y: 0.0, z: 0.0)
    let thirdPoint = Point3D(x: 0.0, y: 1.0, z: 0.0)
    let fourthPoint = Point3D(x: 0.0, y: 0.0, z: 1.0)

    let firstCurveID = CurveID()
    let secondCurveID = CurveID()
    let thirdCurveID = CurveID()
    let fourthCurveID = CurveID()
    let fifthCurveID = CurveID()
    let sixthCurveID = CurveID()
    let firstEdgeID = EdgeID()
    let secondEdgeID = EdgeID()
    let thirdEdgeID = EdgeID()
    let fourthEdgeID = EdgeID()
    let fifthEdgeID = EdgeID()
    let sixthEdgeID = EdgeID()
    let firstSurfaceID = SurfaceID()
    let secondSurfaceID = SurfaceID()
    let thirdSurfaceID = SurfaceID()
    let fourthSurfaceID = SurfaceID()
    let firstLoopID = LoopID()
    let secondLoopID = LoopID()
    let thirdLoopID = LoopID()
    let fourthLoopID = LoopID()
    let firstFaceID = FaceID()
    let secondFaceID = FaceID()
    let thirdFaceID = FaceID()
    let fourthFaceID = FaceID()
    let shellID = ShellID()
    let bodyID = BodyID()

    let diagonal = sqrt(2.0)
    let triDiagonal = sqrt(3.0)
    return BRepModel(
        geometry: GeometryStore(
            curves: [
                firstCurveID: .line(Line3D(origin: firstPoint, direction: Vector3D.unitX)),
                secondCurveID: .line(Line3D(origin: firstPoint, direction: Vector3D.unitY)),
                thirdCurveID: .line(Line3D(origin: firstPoint, direction: Vector3D.unitZ)),
                fourthCurveID: .line(Line3D(
                    origin: secondPoint,
                    direction: Vector3D(x: -1.0 / diagonal, y: 1.0 / diagonal, z: 0.0)
                )),
                fifthCurveID: .line(Line3D(
                    origin: secondPoint,
                    direction: Vector3D(x: -1.0 / diagonal, y: 0.0, z: 1.0 / diagonal)
                )),
                sixthCurveID: .line(Line3D(
                    origin: thirdPoint,
                    direction: Vector3D(x: 0.0, y: -1.0 / diagonal, z: 1.0 / diagonal)
                ))
            ],
            surfaces: [
                firstSurfaceID: .plane(Plane3D(origin: firstPoint, normal: Vector3D.unitZ)),
                secondSurfaceID: .plane(Plane3D(origin: firstPoint, normal: -Vector3D.unitY)),
                thirdSurfaceID: .plane(Plane3D(origin: firstPoint, normal: Vector3D.unitX)),
                fourthSurfaceID: .plane(Plane3D(
                    origin: secondPoint,
                    normal: Vector3D(x: 1.0 / triDiagonal, y: 1.0 / triDiagonal, z: 1.0 / triDiagonal)
                ))
            ]
        ),
        bodies: [bodyID: Body(id: bodyID, shellIDs: [shellID])],
        shells: [shellID: Shell(id: shellID, faceIDs: [firstFaceID, secondFaceID, thirdFaceID, fourthFaceID])],
        faces: [
            firstFaceID: Face(id: firstFaceID, surfaceID: firstSurfaceID, loops: [firstLoopID]),
            secondFaceID: Face(id: secondFaceID, surfaceID: secondSurfaceID, loops: [secondLoopID]),
            thirdFaceID: Face(id: thirdFaceID, surfaceID: thirdSurfaceID, loops: [thirdLoopID]),
            fourthFaceID: Face(id: fourthFaceID, surfaceID: fourthSurfaceID, loops: [fourthLoopID])
        ],
        loops: [
            firstLoopID: Loop(id: firstLoopID, edges: [
                OrientedEdge(edgeID: firstEdgeID, orientation: .forward),
                OrientedEdge(edgeID: fourthEdgeID, orientation: .forward),
                OrientedEdge(edgeID: secondEdgeID, orientation: .reversed)
            ]),
            secondLoopID: Loop(id: secondLoopID, edges: [
                OrientedEdge(edgeID: thirdEdgeID, orientation: .forward),
                OrientedEdge(edgeID: fifthEdgeID, orientation: .reversed),
                OrientedEdge(edgeID: firstEdgeID, orientation: .reversed)
            ]),
            thirdLoopID: Loop(id: thirdLoopID, edges: [
                OrientedEdge(edgeID: secondEdgeID, orientation: .forward),
                OrientedEdge(edgeID: sixthEdgeID, orientation: .forward),
                OrientedEdge(edgeID: thirdEdgeID, orientation: .reversed)
            ]),
            fourthLoopID: Loop(id: fourthLoopID, edges: [
                OrientedEdge(edgeID: fifthEdgeID, orientation: .forward),
                OrientedEdge(edgeID: sixthEdgeID, orientation: .reversed),
                OrientedEdge(edgeID: fourthEdgeID, orientation: .reversed)
            ])
        ],
        edges: [
            firstEdgeID: Edge(
                id: firstEdgeID,
                curveID: firstCurveID,
                startVertexID: firstVertexID,
                endVertexID: secondVertexID
            ),
            secondEdgeID: Edge(
                id: secondEdgeID,
                curveID: secondCurveID,
                startVertexID: firstVertexID,
                endVertexID: thirdVertexID
            ),
            thirdEdgeID: Edge(
                id: thirdEdgeID,
                curveID: thirdCurveID,
                startVertexID: firstVertexID,
                endVertexID: fourthVertexID
            ),
            fourthEdgeID: Edge(
                id: fourthEdgeID,
                curveID: fourthCurveID,
                startVertexID: secondVertexID,
                endVertexID: thirdVertexID
            ),
            fifthEdgeID: Edge(
                id: fifthEdgeID,
                curveID: fifthCurveID,
                startVertexID: secondVertexID,
                endVertexID: fourthVertexID
            ),
            sixthEdgeID: Edge(
                id: sixthEdgeID,
                curveID: sixthCurveID,
                startVertexID: thirdVertexID,
                endVertexID: fourthVertexID
            )
        ],
        vertices: [
            firstVertexID: Vertex(id: firstVertexID, point: firstPoint),
            secondVertexID: Vertex(id: secondVertexID, point: secondPoint),
            thirdVertexID: Vertex(id: thirdVertexID, point: thirdPoint),
            fourthVertexID: Vertex(id: fourthVertexID, point: fourthPoint)
        ]
    )
}

private func makeTwoFaceTriangleModelWithSameEdgeOrientations() -> BRepModel {
    let firstVertexID = VertexID()
    let secondVertexID = VertexID()
    let thirdVertexID = VertexID()
    let firstPoint = Point3D(x: 0.0, y: 0.0, z: 0.0)
    let secondPoint = Point3D(x: 1.0, y: 0.0, z: 0.0)
    let thirdPoint = Point3D(x: 0.0, y: 1.0, z: 0.0)
    let firstCurveID = CurveID()
    let secondCurveID = CurveID()
    let thirdCurveID = CurveID()
    let firstEdgeID = EdgeID()
    let secondEdgeID = EdgeID()
    let thirdEdgeID = EdgeID()
    let surfaceID = SurfaceID()
    let firstLoopID = LoopID()
    let secondLoopID = LoopID()
    let firstFaceID = FaceID()
    let secondFaceID = FaceID()
    let shellID = ShellID()
    let bodyID = BodyID()

    let diagonalLength = sqrt(2.0)
    return BRepModel(
        geometry: GeometryStore(
            curves: [
                firstCurveID: .line(Line3D(origin: firstPoint, direction: Vector3D.unitX)),
                secondCurveID: .line(Line3D(
                    origin: secondPoint,
                    direction: Vector3D(x: -1.0 / diagonalLength, y: 1.0 / diagonalLength, z: 0.0)
                )),
                thirdCurveID: .line(Line3D(origin: thirdPoint, direction: -Vector3D.unitY))
            ],
            surfaces: [surfaceID: .plane(Plane3D(origin: firstPoint, normal: Vector3D.unitZ))]
        ),
        bodies: [bodyID: Body(id: bodyID, shellIDs: [shellID])],
        shells: [shellID: Shell(id: shellID, faceIDs: [firstFaceID, secondFaceID])],
        faces: [
            firstFaceID: Face(id: firstFaceID, surfaceID: surfaceID, loops: [firstLoopID]),
            secondFaceID: Face(id: secondFaceID, surfaceID: surfaceID, loops: [secondLoopID])
        ],
        loops: [
            firstLoopID: Loop(id: firstLoopID, edges: [
                OrientedEdge(edgeID: firstEdgeID, orientation: .forward),
                OrientedEdge(edgeID: secondEdgeID, orientation: .forward),
                OrientedEdge(edgeID: thirdEdgeID, orientation: .forward)
            ]),
            secondLoopID: Loop(id: secondLoopID, edges: [
                OrientedEdge(edgeID: firstEdgeID, orientation: .forward),
                OrientedEdge(edgeID: secondEdgeID, orientation: .forward),
                OrientedEdge(edgeID: thirdEdgeID, orientation: .forward)
            ])
        ],
        edges: [
            firstEdgeID: Edge(
                id: firstEdgeID,
                curveID: firstCurveID,
                startVertexID: firstVertexID,
                endVertexID: secondVertexID
            ),
            secondEdgeID: Edge(
                id: secondEdgeID,
                curveID: secondCurveID,
                startVertexID: secondVertexID,
                endVertexID: thirdVertexID
            ),
            thirdEdgeID: Edge(
                id: thirdEdgeID,
                curveID: thirdCurveID,
                startVertexID: thirdVertexID,
                endVertexID: firstVertexID
            )
        ],
        vertices: [
            firstVertexID: Vertex(id: firstVertexID, point: firstPoint),
            secondVertexID: Vertex(id: secondVertexID, point: secondPoint),
            thirdVertexID: Vertex(id: thirdVertexID, point: thirdPoint)
        ]
    )
}

private func makeTwoFaceTriangleModelWithBalancedEdgeOrientations() -> BRepModel {
    var model = makeTwoFaceTriangleModelWithSameEdgeOrientations()
    let loopIDs = model.loops.keys.sorted { $0.description < $1.description }
    guard loopIDs.count == 2,
          let firstLoop = model.loops[loopIDs[0]] else {
        return model
    }
    model.loops[loopIDs[1]]?.edges = firstLoop.edges.reversed().map { edge in
        OrientedEdge(edgeID: edge.edgeID, orientation: .reversed)
    }
    return model
}

private func makeTwoFaceTriangleModelWithCircularEdge(radius: Double, span: Double) throws -> BRepModel {
    let firstVertexID = VertexID()
    let secondVertexID = VertexID()
    let thirdVertexID = VertexID()
    let firstPoint = Point3D(x: radius, y: 0.0, z: 0.0)
    let secondPoint = Point3D(x: radius * cos(span), y: radius * sin(span), z: 0.0)
    let thirdPoint = Point3D(x: radius + 1.0, y: 0.5, z: 0.0)
    let firstCurveID = CurveID()
    let secondCurveID = CurveID()
    let thirdCurveID = CurveID()
    let firstEdgeID = EdgeID()
    let secondEdgeID = EdgeID()
    let thirdEdgeID = EdgeID()
    let surfaceID = SurfaceID()
    let firstLoopID = LoopID()
    let secondLoopID = LoopID()
    let firstFaceID = FaceID()
    let secondFaceID = FaceID()
    let shellID = ShellID()
    let bodyID = BodyID()
    let secondDelta = thirdPoint - secondPoint
    let thirdDelta = firstPoint - thirdPoint

    return BRepModel(
        geometry: GeometryStore(
            curves: [
                firstCurveID: .circle(Circle3D(center: .origin, normal: Vector3D.unitZ, radius: radius)),
                secondCurveID: .line(Line3D(
                    origin: secondPoint,
                    direction: try secondDelta.normalized(tolerance: ModelingTolerance.standard.distance)
                )),
                thirdCurveID: .line(Line3D(
                    origin: thirdPoint,
                    direction: try thirdDelta.normalized(tolerance: ModelingTolerance.standard.distance)
                ))
            ],
            surfaces: [surfaceID: .plane(Plane3D(origin: .origin, normal: Vector3D.unitZ))]
        ),
        bodies: [bodyID: Body(id: bodyID, shellIDs: [shellID])],
        shells: [shellID: Shell(id: shellID, faceIDs: [firstFaceID, secondFaceID])],
        faces: [
            firstFaceID: Face(id: firstFaceID, surfaceID: surfaceID, loops: [firstLoopID]),
            secondFaceID: Face(id: secondFaceID, surfaceID: surfaceID, loops: [secondLoopID])
        ],
        loops: [
            firstLoopID: Loop(id: firstLoopID, edges: [
                OrientedEdge(edgeID: firstEdgeID, orientation: .forward),
                OrientedEdge(edgeID: secondEdgeID, orientation: .forward),
                OrientedEdge(edgeID: thirdEdgeID, orientation: .forward)
            ]),
            secondLoopID: Loop(id: secondLoopID, edges: [
                OrientedEdge(edgeID: thirdEdgeID, orientation: .reversed),
                OrientedEdge(edgeID: secondEdgeID, orientation: .reversed),
                OrientedEdge(edgeID: firstEdgeID, orientation: .reversed)
            ])
        ],
        edges: [
            firstEdgeID: Edge(
                id: firstEdgeID,
                curveID: firstCurveID,
                startVertexID: firstVertexID,
                endVertexID: secondVertexID,
                trim: CurveTrim(startParameter: 0.0, endParameter: span)
            ),
            secondEdgeID: Edge(
                id: secondEdgeID,
                curveID: secondCurveID,
                startVertexID: secondVertexID,
                endVertexID: thirdVertexID,
                trim: CurveTrim(startParameter: 0.0, endParameter: secondDelta.length)
            ),
            thirdEdgeID: Edge(
                id: thirdEdgeID,
                curveID: thirdCurveID,
                startVertexID: thirdVertexID,
                endVertexID: firstVertexID,
                trim: CurveTrim(startParameter: 0.0, endParameter: thirdDelta.length)
            )
        ],
        vertices: [
            firstVertexID: Vertex(id: firstVertexID, point: firstPoint),
            secondVertexID: Vertex(id: secondVertexID, point: secondPoint),
            thirdVertexID: Vertex(id: thirdVertexID, point: thirdPoint)
        ]
    )
}

private func makeTwoFaceLineSegmentModelWithoutLoopArea() -> BRepModel {
    let firstVertexID = VertexID()
    let secondVertexID = VertexID()
    let firstPoint = Point3D(x: 0.0, y: 0.0, z: 0.0)
    let secondPoint = Point3D(x: 1.0, y: 0.0, z: 0.0)
    let firstCurveID = CurveID()
    let secondCurveID = CurveID()
    let firstEdgeID = EdgeID()
    let secondEdgeID = EdgeID()
    let surfaceID = SurfaceID()
    let firstLoopID = LoopID()
    let secondLoopID = LoopID()
    let firstFaceID = FaceID()
    let secondFaceID = FaceID()
    let shellID = ShellID()
    let bodyID = BodyID()

    return BRepModel(
        geometry: GeometryStore(
            curves: [
                firstCurveID: .line(Line3D(origin: firstPoint, direction: Vector3D.unitX)),
                secondCurveID: .line(Line3D(origin: secondPoint, direction: -Vector3D.unitX))
            ],
            surfaces: [surfaceID: .plane(Plane3D(origin: firstPoint, normal: Vector3D.unitZ))]
        ),
        bodies: [bodyID: Body(id: bodyID, shellIDs: [shellID])],
        shells: [shellID: Shell(id: shellID, faceIDs: [firstFaceID, secondFaceID])],
        faces: [
            firstFaceID: Face(id: firstFaceID, surfaceID: surfaceID, loops: [firstLoopID]),
            secondFaceID: Face(id: secondFaceID, surfaceID: surfaceID, loops: [secondLoopID])
        ],
        loops: [
            firstLoopID: Loop(id: firstLoopID, edges: [
                OrientedEdge(edgeID: firstEdgeID, orientation: .forward),
                OrientedEdge(edgeID: secondEdgeID, orientation: .forward)
            ]),
            secondLoopID: Loop(id: secondLoopID, edges: [
                OrientedEdge(edgeID: secondEdgeID, orientation: .reversed),
                OrientedEdge(edgeID: firstEdgeID, orientation: .reversed)
            ])
        ],
        edges: [
            firstEdgeID: Edge(
                id: firstEdgeID,
                curveID: firstCurveID,
                startVertexID: firstVertexID,
                endVertexID: secondVertexID
            ),
            secondEdgeID: Edge(
                id: secondEdgeID,
                curveID: secondCurveID,
                startVertexID: secondVertexID,
                endVertexID: firstVertexID
            )
        ],
        vertices: [
            firstVertexID: Vertex(id: firstVertexID, point: firstPoint),
            secondVertexID: Vertex(id: secondVertexID, point: secondPoint)
        ]
    )
}
