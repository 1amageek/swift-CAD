import CADCore
import CADGeometry
import CADIR
import CADModeling
import CADTopology
import Testing
@testable import CADKernel

@Suite("Boolean Open Face Arrangement")
struct BooleanOpenFaceArrangementTests {
    private let tolerance = ModelingTolerance.standard

    @Test(.timeLimit(.minutes(1)))
    func transverseSegmentSplitsSourceEdgesAndSelectsOneExactCycle() throws {
        let source = try PlanarSheetTestFixture.make(featureID: FeatureID(), tolerance: .standard)
        let body = try #require(source.brep.bodies.values.first)
        let shell = try #require(source.brep.shells[body.shellIDs[0]])
        let face = try #require(source.brep.faces[shell.faceIDs[0]])
        let surface = try #require(source.brep.geometry.surfaces[face.surfaceID])
        let startPoint = Point3D(x: 0.0, y: -0.010, z: 0.0)
        let endPoint = Point3D(x: 0.0, y: 0.010, z: 0.0)
        let startParameter = try surface.parameterProjection(
            of: startPoint,
            tolerance: tolerance
        )
        let endParameter = try surface.parameterProjection(
            of: endPoint,
            tolerance: tolerance
        )
        let start = try BooleanUVPoint(
            point: startPoint,
            targetU: startParameter.u,
            targetV: startParameter.v,
            toolU: startParameter.u,
            toolV: startParameter.v,
            residual: startParameter.residual,
            tolerance: tolerance
        )
        let end = try BooleanUVPoint(
            point: endPoint,
            targetU: endParameter.u,
            targetV: endParameter.v,
            toolU: endParameter.u,
            toolV: endParameter.v,
            residual: endParameter.residual,
            tolerance: tolerance
        )
        let pair = BooleanFacePairCandidate(
            targetFaceID: face.id,
            toolFaceID: FaceID()
        )
        let componentID = BooleanFaceSplitComponentID(ordinal: 0)
        let oppositeBodyID = BodyID()
        let decisions = BooleanRegionSelectionGraph(decisions: [
            decision(
                pair: pair,
                componentID: componentID,
                faceID: face.id,
                oppositeBodyID: oppositeBodyID,
                side: .negative,
                point: startPoint,
                action: .discard
            ),
            decision(
                pair: pair,
                componentID: componentID,
                faceID: face.id,
                oppositeBodyID: oppositeBodyID,
                side: .positive,
                point: endPoint,
                action: .keep
            ),
        ])
        let boundary = try #require(BooleanFaceArrangementBoundary.make(
            reference: BooleanFaceSplitComponentReference(
                facePair: pair,
                componentID: componentID
            ),
            geometry: .transverseSegment(start: start, end: end),
            face: face,
            surfaceSide: .first,
            regionSelectionGraph: decisions,
            parentSubshapeIDs: source.subshapes.entries.compactMap {
                $0.value == .face(face.id) ? $0.key : nil
            },
            tolerance: tolerance
        ).first)

        let result = try BooleanOpenFaceArrangementBuilder().build(
            faceID: face.id,
            boundaries: [boundary],
            model: source.brep,
            sourceSubshapes: source.subshapes.entries,
            tolerance: tolerance
        )

        #expect(result.isPartitioned)
        #expect(result.patches.count == 1)
        let patch = try #require(result.patches.first)
        try patch.validate(tolerance: tolerance)
        #expect(patch.orientation == .forward)
        #expect(patch.loops.count == 1)
        #expect(patch.loops[0].edges.count == 4)
        #expect(patch.loops[0].edges.contains { edge in
            edge.stableID.hasPrefix("face-intersection:")
        })
        let area = try signedArea(patch.loops[0])
        #expect(area > tolerance.distance * tolerance.distance)
    }

    @Test(.timeLimit(.minutes(1)))
    func transverseSegmentPreservesNestedSourceHoleInSelectedCell() throws {
        let source = try planarSheetWithRectangularHole()
        let body = try #require(source.brep.bodies.values.first)
        let shell = try #require(source.brep.shells[body.shellIDs[0]])
        let face = try #require(source.brep.faces[shell.faceIDs[0]])
        let surface = try #require(source.brep.geometry.surfaces[face.surfaceID])
        let startPoint = Point3D(x: 0.010, y: -0.010, z: 0.0)
        let endPoint = Point3D(x: 0.010, y: 0.010, z: 0.0)
        let pair = BooleanFacePairCandidate(
            targetFaceID: face.id,
            toolFaceID: FaceID()
        )
        let componentID = BooleanFaceSplitComponentID(ordinal: 0)
        let boundary = try #require(BooleanFaceArrangementBoundary.make(
            reference: BooleanFaceSplitComponentReference(
                facePair: pair,
                componentID: componentID
            ),
            geometry: .transverseSegment(
                start: try uvPoint(startPoint, surface: surface),
                end: try uvPoint(endPoint, surface: surface)
            ),
            face: face,
            surfaceSide: .first,
            regionSelectionGraph: BooleanRegionSelectionGraph(decisions: [
                decision(
                    pair: pair,
                    componentID: componentID,
                    faceID: face.id,
                    oppositeBodyID: BodyID(),
                    side: .negative,
                    point: startPoint,
                    action: .discard
                ),
                decision(
                    pair: pair,
                    componentID: componentID,
                    faceID: face.id,
                    oppositeBodyID: BodyID(),
                    side: .positive,
                    point: endPoint,
                    action: .keep
                ),
            ]),
            parentSubshapeIDs: [],
            tolerance: tolerance
        ).first)

        let result = try BooleanOpenFaceArrangementBuilder().build(
            faceID: face.id,
            boundaries: [boundary],
            model: source.brep,
            sourceSubshapes: source.subshapes.entries,
            tolerance: tolerance
        )

        #expect(result.isPartitioned)
        #expect(result.patches.count == 1)
        let patch = try #require(result.patches.first)
        try patch.validate(tolerance: tolerance)
        #expect(patch.loops.filter { $0.role == .outer }.count == 1)
        #expect(patch.loops.filter { $0.role == .inner }.count == 1)
        #expect(try signedArea(try #require(patch.loops.first { $0.role == .inner })) < 0.0)
    }

    @Test(.timeLimit(.minutes(1)))
    func disconnectedIntersectionNetworkProducesExactInnerLoop() throws {
        let source = try PlanarSheetTestFixture.make(featureID: FeatureID(), tolerance: .standard)
        let body = try #require(source.brep.bodies.values.first)
        let shell = try #require(source.brep.shells[body.shellIDs[0]])
        let face = try #require(source.brep.faces[shell.faceIDs[0]])
        let surface = try #require(source.brep.geometry.surfaces[face.surfaceID])
        let points = [
            Point3D(x: -0.010, y: -0.005, z: 0.0),
            Point3D(x: 0.010, y: -0.005, z: 0.0),
            Point3D(x: 0.010, y: 0.005, z: 0.0),
            Point3D(x: -0.010, y: 0.005, z: 0.0),
        ]
        let componentID = BooleanFaceSplitComponentID(ordinal: 0)
        let oppositeBodyID = BodyID()
        let parentSubshapeIDs = source.subshapes.entries.compactMap {
            $0.value == .face(face.id) ? $0.key : nil
        }
        let boundaries = try points.indices.map { index in
            let startPoint = points[index]
            let endPoint = points[(index + 1) % points.count]
            let start = try uvPoint(startPoint, surface: surface)
            let end = try uvPoint(endPoint, surface: surface)
            let pair = BooleanFacePairCandidate(
                targetFaceID: face.id,
                toolFaceID: FaceID()
            )
            let decisions = BooleanRegionSelectionGraph(decisions: [
                decision(
                    pair: pair,
                    componentID: componentID,
                    faceID: face.id,
                    oppositeBodyID: oppositeBodyID,
                    side: .negative,
                    point: startPoint,
                    action: .keep
                ),
                decision(
                    pair: pair,
                    componentID: componentID,
                    faceID: face.id,
                    oppositeBodyID: oppositeBodyID,
                    side: .positive,
                    point: endPoint,
                    action: .discard
                ),
            ])
            return try #require(BooleanFaceArrangementBoundary.make(
                reference: BooleanFaceSplitComponentReference(
                    facePair: pair,
                    componentID: componentID
                ),
                geometry: .transverseSegment(start: start, end: end),
                face: face,
                surfaceSide: .first,
                regionSelectionGraph: decisions,
                parentSubshapeIDs: parentSubshapeIDs,
                tolerance: tolerance
            ).first)
        }

        let result = try BooleanOpenFaceArrangementBuilder().build(
            faceID: face.id,
            boundaries: boundaries,
            model: source.brep,
            sourceSubshapes: source.subshapes.entries,
            tolerance: tolerance
        )

        #expect(result.isPartitioned)
        #expect(result.patches.count == 1)
        let patch = try #require(result.patches.first)
        try patch.validate(tolerance: tolerance)
        #expect(patch.loops.count == 2)
        let outer = try #require(patch.loops.first { $0.role == .outer })
        let inner = try #require(patch.loops.first { $0.role == .inner })
        #expect(outer.edges.count == 4)
        #expect(inner.edges.count == 4)
        #expect(try signedArea(outer) > tolerance.distance * tolerance.distance)
        #expect(try signedArea(inner) < -tolerance.distance * tolerance.distance)
    }

    @Test(.timeLimit(.minutes(1)))
    func translatedBoxesMaterializeThroughGeneralOpenArrangement() throws {
        let target = try DocumentEvaluator(tolerance: .standard).evaluate(makeRectangleExtrudeDocument(
            width: 40.0,
            height: 40.0,
            depth: 20.0
        ))
        let toolDocument = try makeRectangleExtrudeDocument(
            width: 20.0,
            height: 20.0,
            depth: 20.0,
            sketchPlane: .plane(Plane3D(
                origin: Point3D(x: 0.0, y: 0.0, z: 0.005),
                normal: .unitZ
            ))
        ).translatingSources(
            by: Vector3D(x: 0.005, y: 0.003, z: 0.0),
            tolerance: .standard
        )
        let tool = try DocumentEvaluator(tolerance: .standard).evaluate(toolDocument)
        let model = try BRepModelCombiner().combined([target.brep, tool.brep])
        let targetBodyID = try #require(target.brep.bodies.keys.first)
        let toolBodyID = try #require(tool.brep.bodies.keys.first)
        let pipeline = BooleanPipeline(evaluator: ExactBRepBooleanEvaluator())
        let intersectionGraph = try pipeline.intersectionGraph(
            targetBodyIDs: [targetBodyID],
            toolBodyID: toolBodyID,
            operation: .difference,
            model: model,
            tolerance: tolerance
        )
        let uvSplitGraph = try pipeline.uvSplitGraph(
            intersectionGraph: intersectionGraph,
            model: model,
            tolerance: tolerance
        )
        #expect(uvSplitGraph.splits.isEmpty == false)
        #expect(uvSplitGraph.splits.flatMap(\.components).allSatisfy { component in
            if case .transverseSegment = component.geometry { return true }
            if case .tangent = component.geometry { return true }
            return false
        })
        let classificationGraph = try pipeline.classificationGraph(
            uvSplitGraph: uvSplitGraph,
            targetBodyIDs: [targetBodyID],
            toolBodyID: toolBodyID,
            model: model,
            tolerance: tolerance
        )
        let selectionGraph = try pipeline.regionSelectionGraph(
            operation: .difference,
            classificationGraph: classificationGraph,
            tolerance: tolerance
        )
        let sourceSubshapes = target.subshapes.entries.merging(
            tool.subshapes.entries
        ) { current, _ in current }
        let request = try OpenIntersectionFacePatchMaterializer().materialize(
            operation: .difference,
            targetBodyIDs: [targetBodyID],
            toolBodyID: toolBodyID,
            featureID: FeatureID(),
            model: model,
            sourceSubshapes: sourceSubshapes,
            uvSplitGraph: uvSplitGraph,
            regionSelectionGraph: selectionGraph,
            tolerance: tolerance
        )

        try request.validate(tolerance: tolerance)
        #expect(request.shells.isEmpty == false)
        #expect(request.shells.flatMap(\.patches).contains { patch in
            patch.stableID.hasPrefix("open-arrangement:")
        })
        let sewn = try DefaultBRepSewer().sew(request, tolerance: tolerance)
        try sewn.brep.validate(level: .exact, tolerance: tolerance)
    }

    @Test(.timeLimit(.minutes(1)))
    func trimmedExactCurvesComposeDisconnectedInnerLoop() throws {
        let source = try PlanarSheetTestFixture.make(featureID: FeatureID(), tolerance: .standard)
        let body = try #require(source.brep.bodies.values.first)
        let shell = try #require(source.brep.shells[body.shellIDs[0]])
        let face = try #require(source.brep.faces[shell.faceIDs[0]])
        let surface = try #require(source.brep.geometry.surfaces[face.surfaceID])
        let radius = 0.005
        let curve = Curve3D.circle(Circle3D(
            center: .origin,
            normal: .unitZ,
            radius: radius
        ))
        let centerParameter = try surface.parameterProjection(
            of: .origin,
            tolerance: tolerance
        )
        let cosineParameter = try surface.parameterProjection(
            of: Point3D(x: radius, y: 0.0, z: 0.0),
            tolerance: tolerance
        )
        let sineParameter = try surface.parameterProjection(
            of: Point3D(x: 0.0, y: radius, z: 0.0),
            tolerance: tolerance
        )
        let pcurve = SurfaceParameterCurve.harmonic(
            center: Point2D(x: centerParameter.u, y: centerParameter.v),
            cosine: Point2D(
                x: cosineParameter.u - centerParameter.u,
                y: cosineParameter.v - centerParameter.v
            ),
            sine: Point2D(
                x: sineParameter.u - centerParameter.u,
                y: sineParameter.v - centerParameter.v
            ),
            startParameter: 0.0,
            endParameter: 2.0 * Double.pi
        )
        let anchor = try SurfaceParameterProjection(
            u: cosineParameter.u,
            v: cosineParameter.v,
            point: Point3D(x: radius, y: 0.0, z: 0.0),
            residual: 0.0
        )
        let intersection = try SurfaceSurfaceIntersectionCurve(
            truth: .parametric(curve),
            derivedRepresentation: try SurfaceSurfaceIntersectionDerivedRepresentation(
                curve: curve,
                firstSurfaceParameterCurve: pcurve,
                secondSurfaceParameterCurve: pcurve,
                maximumResidualUpperBound: 0.0,
                tolerance: tolerance
            ),
            kind: .transverse,
            firstSurfaceAnchor: anchor,
            secondSurfaceAnchor: anchor,
            tolerance: tolerance
        )
        let intervals = [(0.0, Double.pi), (Double.pi, 2.0 * Double.pi)]
        let componentID = BooleanFaceSplitComponentID(ordinal: 0)
        let boundaries = try intervals.map { interval in
            let lower = interval.0
            let upper = interval.1
            let startPoint = try curve.point(at: lower, tolerance: tolerance)
            let endPoint = try curve.point(at: upper, tolerance: tolerance)
            let pair = BooleanFacePairCandidate(
                targetFaceID: face.id,
                toolFaceID: FaceID()
            )
            let decisions = BooleanRegionSelectionGraph(decisions: [
                decision(
                    pair: pair,
                    componentID: componentID,
                    faceID: face.id,
                    oppositeBodyID: BodyID(),
                    side: .negative,
                    point: startPoint,
                    action: .keep
                ),
                decision(
                    pair: pair,
                    componentID: componentID,
                    faceID: face.id,
                    oppositeBodyID: BodyID(),
                    side: .positive,
                    point: endPoint,
                    action: .discard
                ),
            ])
            let trimmed = try BooleanTrimmedFaceIntersection(
                intersection: intersection,
                startParameter: lower,
                endParameter: upper,
                start: uvPoint(startPoint, surface: surface),
                end: uvPoint(endPoint, surface: surface),
                tolerance: tolerance
            )
            return try #require(BooleanFaceArrangementBoundary.make(
                reference: BooleanFaceSplitComponentReference(
                    facePair: pair,
                    componentID: componentID
                ),
                geometry: .trimmedCurve(try BooleanTrimmedFaceIntersectionChain(
                    segments: [trimmed],
                    tolerance: tolerance
                )),
                face: face,
                surfaceSide: .first,
                regionSelectionGraph: decisions,
                parentSubshapeIDs: [],
                tolerance: tolerance
            ).first)
        }

        let result = try BooleanOpenFaceArrangementBuilder().build(
            faceID: face.id,
            boundaries: boundaries,
            model: source.brep,
            sourceSubshapes: source.subshapes.entries,
            tolerance: tolerance
        )

        let patch = try #require(result.patches.first)
        let inner = try #require(patch.loops.first { $0.role == .inner })
        #expect(result.patches.count == 1)
        #expect(inner.edges.count == 2)
        #expect(inner.edges.allSatisfy { edge in
            if case .circle = edge.curve { return true }
            return false
        })
        try patch.validate(tolerance: tolerance)
    }

    @Test(.timeLimit(.minutes(1)))
    func closedExactCurveNormalizesIntoTwoArrangementHalfEdges() throws {
        let source = try PlanarSheetTestFixture.make(featureID: FeatureID(), tolerance: .standard)
        let body = try #require(source.brep.bodies.values.first)
        let shell = try #require(source.brep.shells[body.shellIDs[0]])
        let face = try #require(source.brep.faces[shell.faceIDs[0]])
        let surface = try #require(source.brep.geometry.surfaces[face.surfaceID])
        let boundaries = try closedCircleBoundaries(
            center: .origin,
            radius: 0.005,
            face: face,
            surface: surface,
            componentOrdinal: 0
        )

        #expect(boundaries.count == 2)
        #expect(Set(boundaries.map(\.edge.stableID)).count == 2)
        let result = try BooleanOpenFaceArrangementBuilder().build(
            faceID: face.id,
            boundaries: boundaries,
            model: source.brep,
            sourceSubshapes: source.subshapes.entries,
            tolerance: tolerance
        )

        let patch = try #require(result.patches.first)
        let inner = try #require(patch.loops.first { $0.role == .inner })
        #expect(result.patches.count == 1)
        #expect(inner.edges.count == 2)
        #expect(inner.edges.allSatisfy { edge in
            if case .circle = edge.curve { return true }
            return false
        })
        try patch.validate(tolerance: tolerance)
    }

    @Test(.timeLimit(.minutes(1)))
    func connectedOpenCellComposesWithDisconnectedClosedCell() throws {
        let source = try PlanarSheetTestFixture.make(featureID: FeatureID(), tolerance: .standard)
        let body = try #require(source.brep.bodies.values.first)
        let shell = try #require(source.brep.shells[body.shellIDs[0]])
        let face = try #require(source.brep.faces[shell.faceIDs[0]])
        let surface = try #require(source.brep.geometry.surfaces[face.surfaceID])
        let startPoint = Point3D(x: 0.0, y: -0.010, z: 0.0)
        let endPoint = Point3D(x: 0.0, y: 0.010, z: 0.0)
        let start = try uvPoint(startPoint, surface: surface)
        let end = try uvPoint(endPoint, surface: surface)
        let pair = BooleanFacePairCandidate(
            targetFaceID: face.id,
            toolFaceID: FaceID()
        )
        let componentID = BooleanFaceSplitComponentID(ordinal: 0)
        let openBoundary = try #require(BooleanFaceArrangementBoundary.make(
            reference: BooleanFaceSplitComponentReference(
                facePair: pair,
                componentID: componentID
            ),
            geometry: .transverseSegment(start: start, end: end),
            face: face,
            surfaceSide: .first,
            regionSelectionGraph: BooleanRegionSelectionGraph(decisions: [
                decision(
                    pair: pair,
                    componentID: componentID,
                    faceID: face.id,
                    oppositeBodyID: BodyID(),
                    side: .negative,
                    point: startPoint,
                    action: .discard
                ),
                decision(
                    pair: pair,
                    componentID: componentID,
                    faceID: face.id,
                    oppositeBodyID: BodyID(),
                    side: .positive,
                    point: endPoint,
                    action: .keep
                ),
            ]),
            parentSubshapeIDs: [],
            tolerance: tolerance
        ).first)
        let closedBoundaries = try closedCircleBoundaries(
            center: Point3D(x: -0.008, y: 0.0, z: 0.0),
            radius: 0.003,
            face: face,
            surface: surface,
            componentOrdinal: 1
        )

        let result = try BooleanOpenFaceArrangementBuilder().build(
            faceID: face.id,
            boundaries: [openBoundary] + closedBoundaries,
            model: source.brep,
            sourceSubshapes: source.subshapes.entries,
            tolerance: tolerance
        )

        #expect(result.patches.count == 1)
        let patch = try #require(result.patches.first)
        #expect(patch.loops.count == 2)
        #expect(patch.loops.contains { $0.role == .inner && $0.edges.count == 2 })
        try patch.validate(tolerance: tolerance)
    }

    @Test(.timeLimit(.minutes(1)))
    func nestedClosedCellsPreserveAlternatingRegionSelection() throws {
        let source = try PlanarSheetTestFixture.make(featureID: FeatureID(), tolerance: .standard)
        let body = try #require(source.brep.bodies.values.first)
        let shell = try #require(source.brep.shells[body.shellIDs[0]])
        let face = try #require(source.brep.faces[shell.faceIDs[0]])
        let surface = try #require(source.brep.geometry.surfaces[face.surfaceID])
        let outerBoundaries = try closedCircleBoundaries(
            center: .origin,
            radius: 0.008,
            face: face,
            surface: surface,
            componentOrdinal: 0
        )
        let innerBoundaries = try closedCircleBoundaries(
            center: .origin,
            radius: 0.003,
            face: face,
            surface: surface,
            componentOrdinal: 1,
            exteriorAction: .discard,
            interiorAction: .keep
        )

        let result = try BooleanOpenFaceArrangementBuilder().build(
            faceID: face.id,
            boundaries: outerBoundaries + innerBoundaries,
            model: source.brep,
            sourceSubshapes: source.subshapes.entries,
            tolerance: tolerance
        )

        #expect(result.patches.count == 2)
        #expect(result.patches.filter { $0.loops.count == 2 }.count == 1)
        #expect(result.patches.filter { $0.loops.count == 1 }.count == 1)
        for patch in result.patches {
            try patch.validate(tolerance: tolerance)
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func periodicCylinderArrangementUnwrapsAcrossSeam() throws {
        let source = try periodicCylinderSheet()
        let body = try #require(source.brep.bodies.values.first)
        let shell = try #require(source.brep.shells[body.shellIDs[0]])
        let face = try #require(source.brep.faces[shell.faceIDs[0]])
        let surface = try #require(source.brep.geometry.surfaces[face.surfaceID])
        let startPoint = try surface.point(u: 6.0, v: -1.0, tolerance: tolerance)
        let endPoint = try surface.point(u: 6.0, v: 1.0, tolerance: tolerance)
        let start = try BooleanUVPoint(
            point: startPoint,
            targetU: 6.0,
            targetV: -1.0,
            toolU: 6.0,
            toolV: -1.0,
            residual: 0.0,
            tolerance: tolerance
        )
        let end = try BooleanUVPoint(
            point: endPoint,
            targetU: 6.0,
            targetV: 1.0,
            toolU: 6.0,
            toolV: 1.0,
            residual: 0.0,
            tolerance: tolerance
        )
        let pair = BooleanFacePairCandidate(
            targetFaceID: face.id,
            toolFaceID: FaceID()
        )
        let componentID = BooleanFaceSplitComponentID(ordinal: 0)
        let boundary = try #require(BooleanFaceArrangementBoundary.make(
            reference: BooleanFaceSplitComponentReference(
                facePair: pair,
                componentID: componentID
            ),
            geometry: .transverseSegment(start: start, end: end),
            face: face,
            surfaceSide: .first,
            regionSelectionGraph: BooleanRegionSelectionGraph(decisions: [
                decision(
                    pair: pair,
                    componentID: componentID,
                    faceID: face.id,
                    oppositeBodyID: BodyID(),
                    side: .negative,
                    point: startPoint,
                    action: .discard
                ),
                decision(
                    pair: pair,
                    componentID: componentID,
                    faceID: face.id,
                    oppositeBodyID: BodyID(),
                    side: .positive,
                    point: endPoint,
                    action: .keep
                ),
            ]),
            parentSubshapeIDs: [],
            tolerance: tolerance
        ).first)

        let result = try BooleanOpenFaceArrangementBuilder().build(
            faceID: face.id,
            boundaries: [boundary],
            model: source.brep,
            sourceSubshapes: source.subshapes.entries,
            tolerance: tolerance
        )

        #expect(result.patches.count == 1)
        let patch = try #require(result.patches.first)
        #expect(patch.loops[0].edges.count == 4)
        try patch.validate(tolerance: tolerance)
    }

    @Test(.timeLimit(.minutes(1)))
    func periodicCylinderEssentialCurveMaterializesFiniteStripCell() throws {
        let source = try fullPeriodicCylinderSheet()
        let body = try #require(source.brep.bodies.values.first)
        let shell = try #require(source.brep.shells[body.shellIDs[0]])
        let face = try #require(source.brep.faces[shell.faceIDs[0]])
        let boundaries = try periodicCylinderCircleBoundaries(face: face)

        let result = try BooleanOpenFaceArrangementBuilder().build(
            faceID: face.id,
            boundaries: boundaries,
            model: source.brep,
            sourceSubshapes: source.subshapes.entries,
            tolerance: tolerance
        )

        #expect(result.isPartitioned)
        #expect(result.patches.count == 1)
        let patch = try #require(result.patches.first)
        #expect(patch.loops.count == 1)
        #expect(patch.loops[0].edges.filter {
            $0.stableID.hasPrefix("face-intersection:")
        }.count == 3)
        #expect(try signedArea(patch.loops[0]) > 0.0)
        try patch.validate(tolerance: tolerance)
        let sewn = try DefaultBRepSewer().sew(BRepSewingRequest(
            featureID: FeatureID(),
            bodyKind: .sheet,
            shells: [BRepSewingShell(
                stableID: "periodic-strip-result:shell",
                patches: [patch]
            )]
        ), tolerance: tolerance)
        _ = try ValidatedBRepModel(
            sewn.brep,
            tolerance: tolerance,
            validationLevel: .exact
        )
    }

    private func decision(
        pair: BooleanFacePairCandidate,
        componentID: BooleanFaceSplitComponentID,
        faceID: FaceID,
        oppositeBodyID: BodyID,
        side: BooleanClassificationGraph.Side,
        point: Point3D,
        action: BooleanRegionSelectionAction
    ) -> BooleanRegionSelectionGraph.Decision {
        BooleanRegionSelectionGraph.Decision(
            sample: BooleanClassificationGraph.Sample(
                facePair: pair,
                componentID: componentID,
                sourceFaceID: faceID,
                oppositeBodyID: oppositeBodyID,
                side: side,
                point: point,
                classification: side == .positive ? .inside : .outside
            ),
            action: action
        )
    }

    private func signedArea(_ loop: BRepSewingLoop) throws -> Double {
        let points = try loop.edges.map {
            try $0.surfaceParameterCurve.startParameter(tolerance: tolerance)
        }
        var doubleArea = 0.0
        for index in points.indices {
            let current = points[index]
            let next = points[(index + 1) % points.count]
            doubleArea += current.u * next.v - current.v * next.u
        }
        return doubleArea * 0.5
    }

    private func uvPoint(
        _ point: Point3D,
        surface: Surface3D
    ) throws -> BooleanUVPoint {
        let parameter = try surface.parameterProjection(
            of: point,
            tolerance: tolerance
        )
        return try BooleanUVPoint(
            point: point,
            targetU: parameter.u,
            targetV: parameter.v,
            toolU: parameter.u,
            toolV: parameter.v,
            residual: parameter.residual,
            tolerance: tolerance
        )
    }

    private func closedCircleBoundaries(
        center: Point3D,
        radius: Double,
        face: Face,
        surface: Surface3D,
        componentOrdinal: Int,
        exteriorAction: BooleanRegionSelectionAction = .keep,
        interiorAction: BooleanRegionSelectionAction = .discard
    ) throws -> [BooleanFaceArrangementBoundary] {
        let curve = Curve3D.circle(Circle3D(
            center: center,
            normal: .unitZ,
            radius: radius
        ))
        let centerParameter = try surface.parameterProjection(
            of: center,
            tolerance: tolerance
        )
        let cosine = try surface.parameterProjection(
            of: Point3D(x: center.x + radius, y: center.y, z: center.z),
            tolerance: tolerance
        )
        let sine = try surface.parameterProjection(
            of: Point3D(x: center.x, y: center.y + radius, z: center.z),
            tolerance: tolerance
        )
        let pcurve = SurfaceParameterCurve.harmonic(
            center: Point2D(x: centerParameter.u, y: centerParameter.v),
            cosine: Point2D(
                x: cosine.u - centerParameter.u,
                y: cosine.v - centerParameter.v
            ),
            sine: Point2D(
                x: sine.u - centerParameter.u,
                y: sine.v - centerParameter.v
            ),
            startParameter: 0.0,
            endParameter: 2.0 * Double.pi
        )
        let anchorPoint = try curve.point(at: 0.0, tolerance: tolerance)
        let anchor = try SurfaceParameterProjection(
            u: cosine.u,
            v: cosine.v,
            point: anchorPoint,
            residual: 0.0
        )
        let intersection = try SurfaceSurfaceIntersectionCurve(
            truth: .parametric(curve),
            derivedRepresentation: try SurfaceSurfaceIntersectionDerivedRepresentation(
                curve: curve,
                firstSurfaceParameterCurve: pcurve,
                secondSurfaceParameterCurve: pcurve,
                maximumResidualUpperBound: 0.0,
                tolerance: tolerance
            ),
            kind: .transverse,
            firstSurfaceAnchor: anchor,
            secondSurfaceAnchor: anchor,
            tolerance: tolerance
        )
        let samples = try (0..<32).map { index in
            let parameter = 2.0 * Double.pi * Double(index) / 32.0
            let point = try curve.point(at: parameter, tolerance: tolerance)
            let surfaceParameter = try pcurve.parameter(
                atCurveParameter: parameter,
                curveDomain: curve.parameterDomain,
                tolerance: tolerance
            )
            return try BooleanCurveUVSample(
                curveParameter: parameter,
                uvPoint: BooleanUVPoint(
                    point: point,
                    targetU: surfaceParameter.u,
                    targetV: surfaceParameter.v,
                    toolU: surfaceParameter.u,
                    toolV: surfaceParameter.v,
                    residual: 0.0,
                    tolerance: tolerance
                ),
                tolerance: tolerance
            )
        }
        let closed = try BooleanClosedFaceIntersection(
            intersection: intersection,
            samples: samples,
            tolerance: tolerance
        )
        let pair = BooleanFacePairCandidate(
            targetFaceID: face.id,
            toolFaceID: FaceID()
        )
        let componentID = BooleanFaceSplitComponentID(ordinal: componentOrdinal)
        return try BooleanFaceArrangementBoundary.make(
            reference: BooleanFaceSplitComponentReference(
                facePair: pair,
                componentID: componentID
            ),
            geometry: .closedCurve(closed),
            face: face,
            surfaceSide: .first,
            regionSelectionGraph: BooleanRegionSelectionGraph(decisions: [
                decision(
                    pair: pair,
                    componentID: componentID,
                    faceID: face.id,
                    oppositeBodyID: BodyID(),
                    side: .negative,
                    point: anchorPoint,
                    action: exteriorAction
                ),
                decision(
                    pair: pair,
                    componentID: componentID,
                    faceID: face.id,
                    oppositeBodyID: BodyID(),
                    side: .positive,
                    point: center,
                    action: interiorAction
                ),
            ]),
            parentSubshapeIDs: [],
            tolerance: tolerance
        )
    }

    private func periodicCylinderSheet() throws -> PlanarSheetTestFixture {
        let surface = Surface3D.cylinder(Cylinder3D(
            origin: .origin,
            axis: .unitZ,
            radius: 1.0
        ))
        let lowerU = 5.5
        let upperU = 2.0 * Double.pi + 0.5
        let bottomStart = try surface.point(u: lowerU, v: -1.0, tolerance: tolerance)
        let bottomEnd = try surface.point(u: upperU, v: -1.0, tolerance: tolerance)
        let topStart = try surface.point(u: upperU, v: 1.0, tolerance: tolerance)
        let topEnd = try surface.point(u: lowerU, v: 1.0, tolerance: tolerance)
        let bottomCircle = Curve3D.circle(Circle3D(
            center: Point3D(x: 0.0, y: 0.0, z: -1.0),
            normal: .unitZ,
            radius: 1.0
        ))
        let topCircle = Curve3D.circle(Circle3D(
            center: Point3D(x: 0.0, y: 0.0, z: 1.0),
            normal: .unitZ,
            radius: 1.0
        ))
        let rightOffset = topStart - bottomEnd
        let leftOffset = bottomStart - topEnd
        let edges = [
            BRepSewingEdge(
                stableID: "periodic-cylinder:bottom",
                curve: bottomCircle,
                startParameter: lowerU,
                endParameter: upperU,
                startPoint: bottomStart,
                endPoint: bottomEnd,
                surfaceParameterCurve: .constantV(
                    v: -1.0,
                    uStart: lowerU,
                    uEnd: upperU
                )
            ),
            BRepSewingEdge(
                stableID: "periodic-cylinder:right",
                curve: .line(Line3D(
                    origin: bottomEnd,
                    direction: try rightOffset.normalized(tolerance: tolerance.distance)
                )),
                startParameter: 0.0,
                endParameter: rightOffset.length,
                startPoint: bottomEnd,
                endPoint: topStart,
                surfaceParameterCurve: .constantU(
                    u: upperU,
                    vStart: -1.0,
                    vEnd: 1.0
                )
            ),
            BRepSewingEdge(
                stableID: "periodic-cylinder:top",
                curve: topCircle,
                startParameter: upperU,
                endParameter: lowerU,
                startPoint: topStart,
                endPoint: topEnd,
                surfaceParameterCurve: .constantV(
                    v: 1.0,
                    uStart: upperU,
                    uEnd: lowerU
                )
            ),
            BRepSewingEdge(
                stableID: "periodic-cylinder:left",
                curve: .line(Line3D(
                    origin: topEnd,
                    direction: try leftOffset.normalized(tolerance: tolerance.distance)
                )),
                startParameter: 0.0,
                endParameter: leftOffset.length,
                startPoint: topEnd,
                endPoint: bottomStart,
                surfaceParameterCurve: .constantU(
                    u: lowerU,
                    vStart: 1.0,
                    vEnd: -1.0
                )
            ),
        ]
        let sewn = try DefaultBRepSewer().sew(BRepSewingRequest(
            featureID: FeatureID(),
            bodyKind: .sheet,
            shells: [BRepSewingShell(
                stableID: "periodic-cylinder:shell",
                patches: [BRepSewingFacePatch(
                    stableID: "periodic-cylinder:face",
                    surface: surface,
                    orientation: .forward,
                    loops: [BRepSewingLoop(
                        stableID: "periodic-cylinder:outer",
                        role: .outer,
                        edges: edges
                    )]
                )]
            )]
        ), tolerance: tolerance)
        return PlanarSheetTestFixture(
            brep: sewn.brep,
            subshapes: SubshapeIndex(sewn.subshapes),
            lineage: sewn.lineage
        )
    }

    private func fullPeriodicCylinderSheet() throws -> PlanarSheetTestFixture {
        let surface = Surface3D.cylinder(Cylinder3D(
            origin: .origin,
            axis: .unitZ,
            radius: 1.0
        ))
        let period = 2.0 * Double.pi
        let seamU = 0.4
        let oppositeU = seamU + Double.pi
        let upperU = seamU + period
        let bottomCircle = Curve3D.circle(Circle3D(
            center: Point3D(x: 0.0, y: 0.0, z: -1.0),
            normal: .unitZ,
            radius: 1.0
        ))
        let topCircle = Curve3D.circle(Circle3D(
            center: Point3D(x: 0.0, y: 0.0, z: 1.0),
            normal: .unitZ,
            radius: 1.0
        ))
        let bottomStart = try surface.point(u: seamU, v: -1.0, tolerance: tolerance)
        let bottomMiddle = try surface.point(u: oppositeU, v: -1.0, tolerance: tolerance)
        let topStart = try surface.point(u: seamU, v: 1.0, tolerance: tolerance)
        let topMiddle = try surface.point(u: oppositeU, v: 1.0, tolerance: tolerance)
        let seamOffset = topStart - bottomStart
        let seam = Curve3D.line(Line3D(
            origin: bottomStart,
            direction: try seamOffset.normalized(tolerance: tolerance.distance)
        ))
        let edges = [
            BRepSewingEdge(
                stableID: "full-periodic-cylinder:bottom:0",
                curve: bottomCircle,
                startParameter: seamU,
                endParameter: oppositeU,
                startPoint: bottomStart,
                endPoint: bottomMiddle,
                surfaceParameterCurve: .constantV(
                    v: -1.0,
                    uStart: seamU,
                    uEnd: oppositeU
                )
            ),
            BRepSewingEdge(
                stableID: "full-periodic-cylinder:bottom:1",
                curve: bottomCircle,
                startParameter: oppositeU,
                endParameter: upperU,
                startPoint: bottomMiddle,
                endPoint: bottomStart,
                surfaceParameterCurve: .constantV(
                    v: -1.0,
                    uStart: oppositeU,
                    uEnd: upperU
                )
            ),
            BRepSewingEdge(
                stableID: "full-periodic-cylinder:seam:right",
                curve: seam,
                startParameter: 0.0,
                endParameter: seamOffset.length,
                startPoint: bottomStart,
                endPoint: topStart,
                surfaceParameterCurve: .constantU(
                    u: upperU,
                    vStart: -1.0,
                    vEnd: 1.0
                )
            ),
            BRepSewingEdge(
                stableID: "full-periodic-cylinder:top:1",
                curve: topCircle,
                startParameter: upperU,
                endParameter: oppositeU,
                startPoint: topStart,
                endPoint: topMiddle,
                surfaceParameterCurve: .constantV(
                    v: 1.0,
                    uStart: upperU,
                    uEnd: oppositeU
                )
            ),
            BRepSewingEdge(
                stableID: "full-periodic-cylinder:top:0",
                curve: topCircle,
                startParameter: oppositeU,
                endParameter: seamU,
                startPoint: topMiddle,
                endPoint: topStart,
                surfaceParameterCurve: .constantV(
                    v: 1.0,
                    uStart: oppositeU,
                    uEnd: seamU
                )
            ),
            BRepSewingEdge(
                stableID: "full-periodic-cylinder:seam:left",
                curve: seam,
                startParameter: seamOffset.length,
                endParameter: 0.0,
                startPoint: topStart,
                endPoint: bottomStart,
                surfaceParameterCurve: .constantU(
                    u: seamU,
                    vStart: 1.0,
                    vEnd: -1.0
                )
            ),
        ]
        let sewn = try DefaultBRepSewer().sew(BRepSewingRequest(
            featureID: FeatureID(),
            bodyKind: .sheet,
            shells: [BRepSewingShell(
                stableID: "full-periodic-cylinder:shell",
                patches: [BRepSewingFacePatch(
                    stableID: "full-periodic-cylinder:face",
                    surface: surface,
                    orientation: .forward,
                    loops: [BRepSewingLoop(
                        stableID: "full-periodic-cylinder:outer",
                        role: .outer,
                        edges: edges
                    )]
                )]
            )]
        ), tolerance: tolerance)
        return PlanarSheetTestFixture(
            brep: sewn.brep,
            subshapes: SubshapeIndex(sewn.subshapes),
            lineage: sewn.lineage
        )
    }

    private func periodicCylinderCircleBoundaries(
        face: Face
    ) throws -> [BooleanFaceArrangementBoundary] {
        let period = 2.0 * Double.pi
        let circle = Curve3D.circle(Circle3D(
            center: .origin,
            normal: .unitZ,
            radius: 1.0
        ))
        let pcurve = SurfaceParameterCurve.constantV(
            v: 0.0,
            uStart: 0.0,
            uEnd: period
        )
        let anchorPoint = try circle.point(at: 0.0, tolerance: tolerance)
        let anchor = try SurfaceParameterProjection(
            u: 0.0,
            v: 0.0,
            point: anchorPoint,
            residual: 0.0
        )
        let intersection = try SurfaceSurfaceIntersectionCurve(
            truth: .parametric(circle),
            derivedRepresentation: try SurfaceSurfaceIntersectionDerivedRepresentation(
                curve: circle,
                firstSurfaceParameterCurve: pcurve,
                secondSurfaceParameterCurve: pcurve,
                maximumResidualUpperBound: 0.0,
                tolerance: tolerance
            ),
            kind: .transverse,
            firstSurfaceAnchor: anchor,
            secondSurfaceAnchor: anchor,
            tolerance: tolerance
        )
        let samples = try (0..<32).map { index in
            let parameter = period * Double(index) / 32.0
            let point = try circle.point(at: parameter, tolerance: tolerance)
            return try BooleanCurveUVSample(
                curveParameter: parameter,
                uvPoint: BooleanUVPoint(
                    point: point,
                    targetU: parameter,
                    targetV: 0.0,
                    toolU: parameter,
                    toolV: 0.0,
                    residual: 0.0,
                    tolerance: tolerance
                ),
                tolerance: tolerance
            )
        }
        let closed = try BooleanClosedFaceIntersection(
            intersection: intersection,
            samples: samples,
            tolerance: tolerance
        )
        let pair = BooleanFacePairCandidate(
            targetFaceID: face.id,
            toolFaceID: FaceID()
        )
        let componentID = BooleanFaceSplitComponentID(ordinal: 0)
        return try BooleanFaceArrangementBoundary.make(
            reference: BooleanFaceSplitComponentReference(
                facePair: pair,
                componentID: componentID
            ),
            geometry: .closedCurve(closed),
            face: face,
            surfaceSide: .first,
            regionSelectionGraph: BooleanRegionSelectionGraph(decisions: [
                decision(
                    pair: pair,
                    componentID: componentID,
                    faceID: face.id,
                    oppositeBodyID: BodyID(),
                    side: .negative,
                    point: Point3D(x: 1.0, y: 0.0, z: -0.5),
                    action: .discard
                ),
                decision(
                    pair: pair,
                    componentID: componentID,
                    faceID: face.id,
                    oppositeBodyID: BodyID(),
                    side: .positive,
                    point: Point3D(x: 1.0, y: 0.0, z: 0.5),
                    action: .keep
                ),
            ]),
            parentSubshapeIDs: [],
            tolerance: tolerance
        )
    }

    private func planarSheetWithRectangularHole() throws -> PlanarSheetTestFixture {
        let surface = Surface3D.plane(Plane3D(origin: .origin, normal: .unitZ))
        let outer = [
            Point3D(x: -0.020, y: -0.010, z: 0.0),
            Point3D(x: 0.020, y: -0.010, z: 0.0),
            Point3D(x: 0.020, y: 0.010, z: 0.0),
            Point3D(x: -0.020, y: 0.010, z: 0.0),
        ]
        let inner = [
            Point3D(x: -0.004, y: -0.003, z: 0.0),
            Point3D(x: -0.004, y: 0.003, z: 0.0),
            Point3D(x: 0.004, y: 0.003, z: 0.0),
            Point3D(x: 0.004, y: -0.003, z: 0.0),
        ]
        func edges(points: [Point3D], stablePrefix: String) throws -> [BRepSewingEdge] {
            try points.indices.map { index in
                let start = points[index]
                let end = points[(index + 1) % points.count]
                let delta = end - start
                let startUV = try surface.parameterProjection(of: start, tolerance: tolerance)
                let endUV = try surface.parameterProjection(of: end, tolerance: tolerance)
                return BRepSewingEdge(
                    stableID: "\(stablePrefix):edge:\(index)",
                    curve: .line(Line3D(
                        origin: start,
                        direction: try delta.normalized(tolerance: tolerance.distance)
                    )),
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
        }
        let sewn = try DefaultBRepSewer().sew(BRepSewingRequest(
            featureID: FeatureID(),
            bodyKind: .sheet,
            shells: [BRepSewingShell(
                stableID: "planar-hole:shell",
                patches: [BRepSewingFacePatch(
                    stableID: "planar-hole:face",
                    surface: surface,
                    orientation: .forward,
                    loops: [
                        BRepSewingLoop(
                            stableID: "planar-hole:outer",
                            role: .outer,
                            edges: try edges(points: outer, stablePrefix: "planar-hole:outer")
                        ),
                        BRepSewingLoop(
                            stableID: "planar-hole:inner",
                            role: .inner,
                            edges: try edges(points: inner, stablePrefix: "planar-hole:inner")
                        ),
                    ]
                )]
            )]
        ), tolerance: tolerance)
        return PlanarSheetTestFixture(
            brep: sewn.brep,
            subshapes: SubshapeIndex(sewn.subshapes),
            lineage: sewn.lineage
        )
    }
}
