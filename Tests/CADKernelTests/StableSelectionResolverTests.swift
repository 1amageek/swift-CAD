import Testing
import CADCore
import CADIR
import CADTopology
@testable import CADKernel

@Suite("Stable selection resolver")
struct StableSelectionResolverTests {
    @Test
    func followsUniqueLineageDescendant() throws {
        let fixture = makeLineageFixture(childCount: 1)

        let resolved = try fixture.document.topologyReference(for: fixture.reference)

        #expect(resolved == fixture.topology[0])
    }

    @Test
    func rejectsAmbiguousSplitDescendants() throws {
        let fixture = makeLineageFixture(childCount: 2)

        do {
            _ = try fixture.document.topologyReference(for: fixture.reference)
            Issue.record("A split selection must not choose one descendant implicitly.")
        } catch let error as KernelError {
            #expect(error.phase == .evaluation)
            #expect(error.code == .ambiguousSelection)
            #expect(error.subshapeID == fixture.reference.subshapeID)
        }
    }

    @Test
    func fallsBackToUniqueGeometrySignature() throws {
        let fixture = makeGeometryFixture(candidateCount: 1)

        let resolved = try fixture.document.topologyReference(for: fixture.reference)

        #expect(resolved == fixture.topology[0])
    }

    @Test
    func rejectsAmbiguousGeometrySignature() throws {
        let fixture = makeGeometryFixture(candidateCount: 2)

        do {
            _ = try fixture.document.topologyReference(for: fixture.reference)
            Issue.record("A geometry signature must not choose between equal candidates implicitly.")
        } catch let error as KernelError {
            #expect(error.phase == .evaluation)
            #expect(error.code == .ambiguousSelection)
            #expect(error.subshapeID == fixture.reference.subshapeID)
        }
    }

    @Test
    func rejectsDifferentExactCurveWithSameEndpointsAndMidpoint() throws {
        let sourceCurve = BSplineCurve3D(
            degree: 3,
            knots: [0.0, 0.0, 0.0, 0.0, 1.0, 1.0, 1.0, 1.0],
            controlPoints: [
                .origin,
                Point3D(x: 0.25, y: 1.0, z: 0.0),
                Point3D(x: 0.75, y: 1.0, z: 0.0),
                Point3D(x: 1.0, y: 0.0, z: 0.0),
            ],
            weights: [1.0, 1.0, 1.0, 1.0]
        )
        let differentCurve = BSplineCurve3D(
            degree: 3,
            knots: sourceCurve.knots,
            controlPoints: [
                .origin,
                Point3D(x: 0.25, y: 2.0, z: 0.0),
                Point3D(x: 0.75, y: 0.0, z: 0.0),
                Point3D(x: 1.0, y: 0.0, z: 0.0),
            ],
            weights: sourceCurve.weights
        )
        let featureID = FeatureID()
        let sourceID = SubshapeID(featureID: featureID, role: "edge", ordinal: 0)
        let candidateID = SubshapeID(featureID: featureID, role: "edge", ordinal: 1)
        let source = try makeEdgeDocument(curve: sourceCurve, subshapeID: sourceID)
        let candidate = try makeEdgeDocument(curve: differentCurve, subshapeID: candidateID)
        let reference = try source.stableSubshapeReference(for: sourceID)

        #expect(try sourceCurve.point(at: 0.5, tolerance: .standard)
            == differentCurve.point(at: 0.5, tolerance: .standard))
        #expect(try sourceCurve.point(at: 0.25, tolerance: .standard)
            != differentCurve.point(at: 0.25, tolerance: .standard))
        do {
            _ = try candidate.topologyReference(for: reference)
            Issue.record("Exact geometry fallback must not select a different curve sharing three sample points.")
        } catch let error as KernelError {
            #expect(error.phase == .evaluation)
            #expect(error.code == .missingReference)
            #expect(error.subshapeID == sourceID)
        }
    }

    @Test
    func createsStableReferenceDirectlyFromSubshapeIndex() throws {
        let fixture = makeGeometryFixture(candidateCount: 1)
        let subshapeID = try #require(fixture.document.subshapes.entries.keys.first)

        let reference = try fixture.document.stableSubshapeReference(for: subshapeID)

        #expect(reference.subshapeID == subshapeID)
        #expect(reference.geometrySignature == fixture.reference.geometrySignature)
    }

    @Test
    func rejectsEqualGeometryFromDifferentFeatureProvenance() throws {
        let point = Point3D(x: 1.0, y: 2.0, z: 3.0)
        let source = SubshapeID(featureID: FeatureID(), role: "vertex", ordinal: 0)
        let unrelated = SubshapeID(featureID: FeatureID(), role: "vertex", ordinal: 0)
        let vertexID = VertexID()
        var brep = BRepModel()
        brep.vertices[vertexID] = Vertex(id: vertexID, point: point)
        let document = EvaluatedDocument(
            document: CADDocument(units: .meters),
            parameters: ResolvedParameterTable(),
            brep: brep,
            meshes: PersistentMap(),
            caches: DocumentCaches(),
            subshapes: SubshapeIndex([unrelated: .vertex(vertexID)]),
            configuration: standardConfiguration
        )

        do {
            _ = try document.topologyReference(for: StableSubshapeReference(
                subshapeID: source,
                geometrySignature: .vertex(point: point)
            ))
            Issue.record("Geometry fallback must not cross feature provenance.")
        } catch let error as KernelError {
            #expect(error.code == .missingReference)
            #expect(error.subshapeID == source)
        }
    }

    @Test
    func fallsBackWithExactBodyFaceAndEdgeWitnesses() throws {
        let featureID = FeatureID()
        let sourceFixture = try PlanarSheetTestFixture.make(
            featureID: featureID,
            tolerance: .standard
        )
        let candidateFixture = try PlanarSheetTestFixture.make(
            featureID: FeatureID(),
            tolerance: .standard
        )
        let source = evaluatedDocument(from: sourceFixture)
        let remappedCandidateEntries = Dictionary(uniqueKeysWithValues:
            candidateFixture.subshapes.entries.map { candidateID, topologyReference in
                (
                    SubshapeID(
                        featureID: featureID,
                        role: candidateID.role,
                        ordinal: candidateID.ordinal + 100
                    ),
                    topologyReference
                )
            }
        )
        let candidate = EvaluatedDocument(
            document: CADDocument(units: .meters),
            parameters: ResolvedParameterTable(),
            brep: candidateFixture.brep,
            meshes: PersistentMap(),
            caches: DocumentCaches(),
            subshapes: SubshapeIndex(remappedCandidateEntries),
            configuration: standardConfiguration
        )
        let sourceEntries = source.subshapes.entries.sorted { $0.key < $1.key }
        let sourceIDs = [
            try #require(sourceEntries.first(where: { if case .body = $0.value { true } else { false } })?.key),
            try #require(sourceEntries.first(where: { if case .face = $0.value { true } else { false } })?.key),
            try #require(sourceEntries.first(where: { if case .edge = $0.value { true } else { false } })?.key),
        ]

        for sourceID in sourceIDs {
            let reference = try source.stableSubshapeReference(for: sourceID)
            let resolved = try candidate.topologyReference(for: reference)
            let candidateID = try #require(candidate.subshapes.entries.first {
                $0.value == resolved
            }?.key)
            let candidateReference = try candidate.stableSubshapeReference(for: candidateID)

            #expect(candidateReference.geometrySignature == reference.geometrySignature)
        }
    }

    @Test
    func rejectsDirectIdentityWithDifferentTopologyKind() throws {
        let subshapeID = SubshapeID(featureID: FeatureID(), role: "edge", ordinal: 0)
        let reference = StableSubshapeReference(
            subshapeID: subshapeID,
            geometrySignature: .vertex(point: Point3D(x: 1.0, y: 2.0, z: 3.0))
        )
        let document = EvaluatedDocument(
            document: CADDocument(units: .meters),
            parameters: ResolvedParameterTable(),
            brep: BRepModel(),
            meshes: PersistentMap(),
            caches: DocumentCaches(),
            subshapes: SubshapeIndex([subshapeID: .edge(EdgeID())]),
            configuration: standardConfiguration
        )

        do {
            _ = try document.topologyReference(for: reference)
            Issue.record("A direct identity must agree with the geometry signature topology kind.")
        } catch let error as KernelError {
            #expect(error.phase == .validation)
            #expect(error.code == .invalidInput)
            #expect(error.subshapeID == subshapeID)
        }
    }

    @Test
    func ignoresWrongKindLineageDescendantBeforeGeometryFallback() throws {
        let point = Point3D(x: 1.0, y: 2.0, z: 3.0)
        let source = SubshapeID(featureID: FeatureID(), role: "vertex", ordinal: 0)
        let wrongKind = SubshapeID(featureID: FeatureID(), role: "edge", ordinal: 0)
        let geometryMatch = SubshapeID(featureID: source.featureID, role: "vertex", ordinal: 1)
        let vertexID = VertexID()
        var brep = BRepModel()
        brep.vertices[vertexID] = Vertex(id: vertexID, point: point)
        let expected = TopologyReference.vertex(vertexID)
        let document = EvaluatedDocument(
            document: CADDocument(units: .meters),
            parameters: ResolvedParameterTable(),
            brep: brep,
            meshes: PersistentMap(),
            caches: DocumentCaches(),
            subshapes: SubshapeIndex([
                wrongKind: .edge(EdgeID()),
                geometryMatch: expected,
            ]),
            lineage: [
                wrongKind: TopologyLineage(output: wrongKind, parents: [source], relation: .preserved),
            ],
            configuration: standardConfiguration
        )
        let reference = StableSubshapeReference(
            subshapeID: source,
            geometrySignature: .vertex(point: point)
        )

        let resolved = try document.topologyReference(for: reference)

        #expect(resolved == expected)
    }

    @Test
    func rejectsMultipleLiveDescendantsAcrossLineageGenerations() throws {
        let source = SubshapeID(featureID: FeatureID(), role: "vertex", ordinal: 0)
        let firstChild = SubshapeID(featureID: FeatureID(), role: "vertex", ordinal: 0)
        let secondChild = SubshapeID(featureID: FeatureID(), role: "vertex", ordinal: 0)
        let firstVertexID = VertexID()
        let secondVertexID = VertexID()
        var brep = BRepModel()
        brep.vertices[firstVertexID] = Vertex(id: firstVertexID, point: Point3D(x: 1.0, y: 0.0, z: 0.0))
        brep.vertices[secondVertexID] = Vertex(id: secondVertexID, point: Point3D(x: 2.0, y: 0.0, z: 0.0))
        let document = EvaluatedDocument(
            document: CADDocument(units: .meters),
            parameters: ResolvedParameterTable(),
            brep: brep,
            meshes: PersistentMap(),
            caches: DocumentCaches(),
            subshapes: SubshapeIndex([
                firstChild: .vertex(firstVertexID),
                secondChild: .vertex(secondVertexID),
            ]),
            lineage: [
                firstChild: TopologyLineage(output: firstChild, parents: [source], relation: .preserved),
                secondChild: TopologyLineage(output: secondChild, parents: [firstChild], relation: .preserved),
            ],
            configuration: standardConfiguration
        )
        let reference = StableSubshapeReference(
            subshapeID: source,
            geometrySignature: .vertex(point: Point3D(x: 0.0, y: 0.0, z: 0.0))
        )

        do {
            _ = try document.topologyReference(for: reference)
            Issue.record("All live descendants must participate in ambiguity detection.")
        } catch let error as KernelError {
            #expect(error.phase == .evaluation)
            #expect(error.code == .ambiguousSelection)
            #expect(error.subshapeID == source)
        }
    }

    @Test
    func rejectsReachableLineageCycle() throws {
        let source = SubshapeID(featureID: FeatureID(), role: "vertex", ordinal: 0)
        let child = SubshapeID(featureID: FeatureID(), role: "vertex", ordinal: 0)
        let document = EvaluatedDocument(
            document: CADDocument(units: .meters),
            parameters: ResolvedParameterTable(),
            brep: BRepModel(),
            meshes: PersistentMap(),
            caches: DocumentCaches(),
            subshapes: SubshapeIndex(),
            lineage: [
                source: TopologyLineage(output: source, parents: [child], relation: .preserved),
                child: TopologyLineage(output: child, parents: [source], relation: .preserved),
            ],
            configuration: standardConfiguration
        )
        let reference = StableSubshapeReference(
            subshapeID: source,
            geometrySignature: .vertex(point: Point3D(x: 0.0, y: 0.0, z: 0.0))
        )

        do {
            _ = try document.topologyReference(for: reference)
            Issue.record("A reachable lineage cycle must fail before geometry fallback.")
        } catch let error as KernelError {
            #expect(error.phase == .topology)
            #expect(error.code == .topologyFailure)
        }
    }

    private func makeLineageFixture(
        childCount: Int
    ) -> (
        document: EvaluatedDocument,
        reference: StableSubshapeReference,
        topology: [TopologyReference]
    ) {
        let point = Point3D(x: 1.0, y: 2.0, z: 3.0)
        let parent = SubshapeID(featureID: FeatureID(), role: "vertex", ordinal: 0)
        let children = (0..<childCount).map {
            SubshapeID(featureID: FeatureID(), role: "vertex", ordinal: $0)
        }
        let vertexIDs = children.map { _ in VertexID() }
        var brep = BRepModel()
        for (index, vertexID) in vertexIDs.enumerated() {
            brep.vertices[vertexID] = Vertex(
                id: vertexID,
                point: Point3D(x: point.x + Double(index), y: point.y, z: point.z)
            )
        }
        let topology = vertexIDs.map(TopologyReference.vertex)
        let subshapes = SubshapeIndex(Dictionary(uniqueKeysWithValues: zip(children, topology)))
        let lineage = Dictionary(uniqueKeysWithValues: children.map { child in
            (child, TopologyLineage(output: child, parents: [parent], relation: .split))
        })
        return (
            EvaluatedDocument(
                document: CADDocument(units: .meters),
                parameters: ResolvedParameterTable(),
                brep: brep,
                meshes: PersistentMap(),
                caches: DocumentCaches(),
                subshapes: subshapes,
                lineage: lineage,
                configuration: standardConfiguration
            ),
            StableSubshapeReference(subshapeID: parent, geometrySignature: .vertex(point: point)),
            topology
        )
    }

    private func makeGeometryFixture(
        candidateCount: Int
    ) -> (
        document: EvaluatedDocument,
        reference: StableSubshapeReference,
        topology: [TopologyReference]
    ) {
        let point = Point3D(x: 1.0, y: 2.0, z: 3.0)
        let featureID = FeatureID()
        let reference = StableSubshapeReference(
            subshapeID: SubshapeID(featureID: featureID, role: "vertex", ordinal: candidateCount + 1),
            geometrySignature: .vertex(point: point)
        )
        let candidateIDs = (0..<candidateCount).map {
            SubshapeID(featureID: featureID, role: "vertex", ordinal: $0)
        }
        let vertexIDs = candidateIDs.map { _ in VertexID() }
        var brep = BRepModel()
        for vertexID in vertexIDs {
            brep.vertices[vertexID] = Vertex(id: vertexID, point: point)
        }
        let topology = vertexIDs.map(TopologyReference.vertex)
        let subshapes = SubshapeIndex(Dictionary(uniqueKeysWithValues: zip(candidateIDs, topology)))
        return (
            EvaluatedDocument(
                document: CADDocument(units: .meters),
                parameters: ResolvedParameterTable(),
                brep: brep,
                meshes: PersistentMap(),
                caches: DocumentCaches(),
                subshapes: subshapes,
                configuration: standardConfiguration
            ),
            reference,
            topology
        )
    }

    private func makeEdgeDocument(
        curve: BSplineCurve3D,
        subshapeID: SubshapeID
    ) throws -> EvaluatedDocument {
        let curveID = CurveID()
        let edgeID = EdgeID()
        let startVertexID = VertexID()
        let endVertexID = VertexID()
        let start = try curve.point(at: 0.0, tolerance: .standard)
        let end = try curve.point(at: 1.0, tolerance: .standard)
        let brep = BRepModel(
            geometry: GeometryStore(curves: [curveID: .bSpline(curve)]),
            edges: [
                edgeID: Edge(
                    id: edgeID,
                    curveID: curveID,
                    startVertexID: startVertexID,
                    endVertexID: endVertexID,
                    trim: CurveTrim(startParameter: 0.0, endParameter: 1.0)
                ),
            ],
            vertices: [
                startVertexID: Vertex(id: startVertexID, point: start),
                endVertexID: Vertex(id: endVertexID, point: end),
            ]
        )
        return EvaluatedDocument(
            document: CADDocument(units: .meters),
            parameters: ResolvedParameterTable(),
            brep: brep,
            meshes: PersistentMap(),
            caches: DocumentCaches(),
            subshapes: SubshapeIndex([subshapeID: .edge(edgeID)]),
            configuration: standardConfiguration
        )
    }

    private func evaluatedDocument(
        from fixture: PlanarSheetTestFixture
    ) -> EvaluatedDocument {
        EvaluatedDocument(
            document: CADDocument(units: .meters),
            parameters: ResolvedParameterTable(),
            brep: fixture.brep,
            meshes: PersistentMap(),
            caches: DocumentCaches(),
            subshapes: fixture.subshapes,
            lineage: fixture.lineage,
            configuration: standardConfiguration
        )
    }

    private var standardConfiguration: DocumentEvaluationConfiguration {
        DocumentEvaluationConfiguration(tolerance: .standard, tessellationOptions: .standard)
    }
}
