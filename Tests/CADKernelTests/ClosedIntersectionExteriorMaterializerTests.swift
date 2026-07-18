import CADCore
import CADGeometry
import CADIR
import CADModeling
import CADTopology
import Testing
@testable import CADKernel

@Suite("Closed Intersection Exterior Materializer")
struct ClosedIntersectionExteriorMaterializerTests {
    private let tolerance = ModelingTolerance.standard

    @Test(.timeLimit(.minutes(1)))
    func exteriorRegionPreservesSourceOuterLoopAndAddsExactInnerLoop() throws {
        let targetFeatureID = FeatureID()
        let target = try PlanarSheetTestFixture.make(featureID: targetFeatureID, tolerance: .standard)
        var model = target.brep
        let targetBody = try #require(model.bodies.values.first)
        let targetShell = try #require(model.shells[targetBody.shellIDs[0]])
        let targetFace = try #require(model.faces[targetShell.faceIDs[0]])
        let targetSurface = try #require(model.geometry.surfaces[targetFace.surfaceID])
        let targetLoop = try #require(model.loops[targetFace.loops[0]])
        let carriedLoop = Loop(
            role: .outer,
            coedges: try targetLoop.coedges.reversed().map { coedge in
                let pcurve = try #require(coedge.surfaceParameterCurve)
                return Coedge(
                    edgeID: coedge.edgeID,
                    orientation: coedge.orientation == .forward ? .reversed : .forward,
                    surfaceParameterCurve: try pcurve.reversed(tolerance: tolerance)
                )
            }
        )
        let carriedFace = Face(
            surfaceID: targetFace.surfaceID,
            loops: [carriedLoop.id],
            orientation: .reversed
        )
        var expandedTargetShell = targetShell
        expandedTargetShell.faceIDs.append(carriedFace.id)
        model.loops[carriedLoop.id] = carriedLoop
        model.faces[carriedFace.id] = carriedFace
        model.shells[targetShell.id] = expandedTargetShell

        let toolSurfaceID = SurfaceID()
        let toolSurface = try paraboloidSurface()
        let toolFace = Face(
            surfaceID: toolSurfaceID,
            loops: [],
            orientation: .reversed
        )
        let toolShell = Shell(faceIDs: [toolFace.id])
        let toolBody = Body(shellIDs: [toolShell.id], kind: .sheet)
        model.geometry.surfaces[toolSurfaceID] = toolSurface
        model.faces[toolFace.id] = toolFace
        model.shells[toolShell.id] = toolShell
        model.bodies[toolBody.id] = toolBody

        let closed = try closedIntersection(
            targetSurface: targetSurface,
            toolSurface: toolSurface
        )
        let facePair = BooleanFacePairCandidate(
            targetFaceID: targetFace.id,
            toolFaceID: toolFace.id
        )
        let targetInteriorSide = interiorSide(
            samples: closed.samples,
            faceOrientation: targetFace.orientation,
            parameter: { ($0.uvPoint.targetU, $0.uvPoint.targetV) }
        )
        let toolInteriorSide = interiorSide(
            samples: closed.samples,
            faceOrientation: toolFace.orientation,
            parameter: { ($0.uvPoint.toolU, $0.uvPoint.toolV) }
        )
        let decisions = BooleanRegionSelectionGraph(decisions: [
            decision(
                pair: facePair,
                faceID: targetFace.id,
                oppositeBodyID: toolBody.id,
                side: opposite(targetInteriorSide),
                point: closed.samples[0].uvPoint.point,
                classification: .outside,
                action: .keep
            ),
            decision(
                pair: facePair,
                faceID: targetFace.id,
                oppositeBodyID: toolBody.id,
                side: targetInteriorSide,
                point: closed.samples[0].uvPoint.point,
                classification: .inside,
                action: .discard
            ),
            decision(
                pair: facePair,
                faceID: toolFace.id,
                oppositeBodyID: targetBody.id,
                side: toolInteriorSide,
                point: closed.samples[0].uvPoint.point,
                classification: .inside,
                action: .keepReversed
            ),
            decision(
                pair: facePair,
                faceID: toolFace.id,
                oppositeBodyID: targetBody.id,
                side: opposite(toolInteriorSide),
                point: closed.samples[0].uvPoint.point,
                classification: .outside,
                action: .discard
            ),
        ])
        var sourceSubshapes = target.subshapes.entries
        let carriedParent = SubshapeID(featureID: FeatureID(), role: "face", ordinal: 0)
        let toolParent = SubshapeID(featureID: FeatureID(), role: "face", ordinal: 0)
        sourceSubshapes[carriedParent] = .face(carriedFace.id)
        sourceSubshapes[toolParent] = .face(toolFace.id)
        let materializer = ClosedIntersectionFacePatchMaterializer(
            unsplitFaceMaterializer: ClosedIntersectionUnsplitFaceMaterializer(
                pointClassifier: ConstantPointClassifier(classification: .outside)
            )
        )
        let resultFeatureID = FeatureID()
        let request = try materializer.materialize(
            operation: .difference,
            targetBodyIDs: [targetBody.id],
            toolBodyID: toolBody.id,
            featureID: resultFeatureID,
            model: model,
            sourceSubshapes: sourceSubshapes,
            uvSplitGraph: BooleanUVSplitGraph(splits: [BooleanFaceSplit(
                facePair: facePair,
                components: [BooleanFaceSplitComponent(
                    id: BooleanFaceSplitComponentID(ordinal: 0),
                    geometry: .closedCurve(closed)
                )]
            )]),
            regionSelectionGraph: decisions,
            tolerance: tolerance
        )

        try request.validate(tolerance: tolerance)
        let shell = try #require(request.shells.first)
        let targetPatch = try #require(shell.patches.first { patch in
            patch.stableID.hasPrefix("closed-intersection:face:\(targetFace.id):region:root")
        })
        let toolPatch = try #require(shell.patches.first { patch in
            patch.stableID.hasPrefix("closed-intersection:face:\(toolFace.id):region:")
        })
        #expect(targetPatch.loops.map(\.role).filter { $0 == .outer }.count == 1)
        #expect(targetPatch.loops.map(\.role).filter { $0 == .inner }.count == 1)
        #expect(targetPatch.loops.first { $0.role == .outer }?.edges.count == 4)
        #expect(targetPatch.loops.first { $0.role == .inner }?.edges.count == 2)
        #expect(targetPatch.parentSubshapeIDs.contains { parent in
            sourceSubshapes[parent] == .face(targetFace.id)
        })
        #expect(toolPatch.loops.count == 1)
        #expect(toolPatch.loops[0].role == .outer)
        #expect(toolPatch.loops[0].edges.count == 2)
        #expect(toolPatch.orientation == .forward)
        let carriedPatch = try #require(shell.patches.first { patch in
            patch.stableID.hasPrefix("closed-intersection:carried:target:face:")
        })
        #expect(carriedPatch.parentSubshapeIDs == [carriedParent])
        let sewn = try DefaultBRepSewer().sew(request, tolerance: tolerance)
        #expect(sewn.brep.faces.count == 3)
        #expect(sewn.brep.edges.count == 6)
        try sewn.brep.validate(level: .exact, tolerance: tolerance)
    }

    @Test(.timeLimit(.minutes(1)))
    func reversingSourcePatchReversesCoedgesPcurvesAndVertexProvenance() throws {
        let source = try PlanarSheetTestFixture.make(featureID: FeatureID(), tolerance: .standard)
        let body = try #require(source.brep.bodies.values.first)
        let shell = try #require(source.brep.shells[body.shellIDs[0]])
        let face = try #require(source.brep.faces[shell.faceIDs[0]])
        let original = try SourceBRepFacePatchBuilder().build(
            faceID: face.id,
            stableID: "orientation-source",
            from: source.brep,
            sourceSubshapes: source.subshapes.entries,
            tolerance: tolerance
        ).patch
        let reoriented = try BRepSewingPatchOrientationAdapter().reorient(
            original,
            to: .reversed,
            tolerance: tolerance
        )

        try reoriented.validate(tolerance: tolerance)
        let originalEdge = try #require(original.loops[0].edges.first)
        let reversedEdge = try #require(reoriented.loops[0].edges.last)
        #expect(reoriented.orientation == .reversed)
        #expect(reversedEdge.stableID == originalEdge.stableID)
        #expect(reversedEdge.startPoint == originalEdge.endPoint)
        #expect(reversedEdge.endPoint == originalEdge.startPoint)
        #expect(
            reversedEdge.startVertexParentSubshapeIDs
                == originalEdge.endVertexParentSubshapeIDs
        )
        #expect(
            reversedEdge.endVertexParentSubshapeIDs
                == originalEdge.startVertexParentSubshapeIDs
        )
        #expect(
            try reversedEdge.surfaceParameterCurve.startParameter(tolerance: tolerance)
                == originalEdge.surfaceParameterCurve.endParameter(tolerance: tolerance)
        )
    }

    @Test(.timeLimit(.minutes(1)))
    func disjointClosedComponentsProduceOneExteriorFaceWithTwoExactInnerLoops() throws {
        let target = try PlanarSheetTestFixture.make(featureID: FeatureID(), tolerance: .standard)
        var model = target.brep
        let targetBody = try #require(model.bodies.values.first)
        let targetShell = try #require(model.shells[targetBody.shellIDs[0]])
        let targetFace = try #require(model.faces[targetShell.faceIDs[0]])
        let targetSurface = try #require(model.geometry.surfaces[targetFace.surfaceID])
        let targetLoop = try #require(model.loops[targetFace.loops[0]])
        let carriedLoop = Loop(
            role: .outer,
            coedges: try targetLoop.coedges.reversed().map { coedge in
                let pcurve = try #require(coedge.surfaceParameterCurve)
                return Coedge(
                    edgeID: coedge.edgeID,
                    orientation: coedge.orientation == .forward ? .reversed : .forward,
                    surfaceParameterCurve: try pcurve.reversed(tolerance: tolerance)
                )
            }
        )
        let carriedFace = Face(
            surfaceID: targetFace.surfaceID,
            loops: [carriedLoop.id],
            orientation: .reversed
        )
        var expandedTargetShell = targetShell
        expandedTargetShell.faceIDs.append(carriedFace.id)
        model.loops[carriedLoop.id] = carriedLoop
        model.faces[carriedFace.id] = carriedFace
        model.shells[targetShell.id] = expandedTargetShell

        let centers = [Point2D(x: -0.02, y: 0.0), Point2D(x: 0.02, y: 0.0)]
        var toolFaces: [Face] = []
        var closedIntersections: [BooleanClosedFaceIntersection] = []
        for center in centers {
            let surfaceID = SurfaceID()
            let surface = try paraboloidSurface(center: center)
            let face = Face(surfaceID: surfaceID, loops: [], orientation: .reversed)
            model.geometry.surfaces[surfaceID] = surface
            model.faces[face.id] = face
            toolFaces.append(face)
            closedIntersections.append(try closedIntersection(
                targetSurface: targetSurface,
                toolSurface: surface,
                center: center
            ))
        }
        let toolShell = Shell(faceIDs: toolFaces.map(\.id))
        let toolBody = Body(shellIDs: [toolShell.id], kind: .sheet)
        model.shells[toolShell.id] = toolShell
        model.bodies[toolBody.id] = toolBody

        var splits: [BooleanFaceSplit] = []
        var decisions: [BooleanRegionSelectionGraph.Decision] = []
        for index in toolFaces.indices {
            let toolFace = toolFaces[index]
            let closed = closedIntersections[index]
            let pair = BooleanFacePairCandidate(
                targetFaceID: targetFace.id,
                toolFaceID: toolFace.id
            )
            splits.append(BooleanFaceSplit(
                facePair: pair,
                components: [BooleanFaceSplitComponent(
                    id: BooleanFaceSplitComponentID(ordinal: 0),
                    geometry: .closedCurve(closed)
                )]
            ))
            let targetInterior = interiorSide(
                samples: closed.samples,
                faceOrientation: targetFace.orientation,
                parameter: { ($0.uvPoint.targetU, $0.uvPoint.targetV) }
            )
            let toolInterior = interiorSide(
                samples: closed.samples,
                faceOrientation: toolFace.orientation,
                parameter: { ($0.uvPoint.toolU, $0.uvPoint.toolV) }
            )
            decisions.append(contentsOf: [
                decision(
                    pair: pair,
                    faceID: targetFace.id,
                    oppositeBodyID: toolBody.id,
                    side: opposite(targetInterior),
                    point: closed.samples[0].uvPoint.point,
                    classification: .outside,
                    action: .keep
                ),
                decision(
                    pair: pair,
                    faceID: targetFace.id,
                    oppositeBodyID: toolBody.id,
                    side: targetInterior,
                    point: closed.samples[0].uvPoint.point,
                    classification: .inside,
                    action: .discard
                ),
                decision(
                    pair: pair,
                    faceID: toolFace.id,
                    oppositeBodyID: targetBody.id,
                    side: toolInterior,
                    point: closed.samples[0].uvPoint.point,
                    classification: .inside,
                    action: .keepReversed
                ),
                decision(
                    pair: pair,
                    faceID: toolFace.id,
                    oppositeBodyID: targetBody.id,
                    side: opposite(toolInterior),
                    point: closed.samples[0].uvPoint.point,
                    classification: .outside,
                    action: .discard
                ),
            ])
        }
        var sourceSubshapes = target.subshapes.entries
        sourceSubshapes[SubshapeID(
            featureID: FeatureID(),
            role: "face",
            ordinal: 0
        )] = .face(carriedFace.id)
        for (index, face) in toolFaces.enumerated() {
            sourceSubshapes[SubshapeID(
                featureID: FeatureID(),
                role: "face",
                ordinal: index
            )] = .face(face.id)
        }
        let request = try ClosedIntersectionFacePatchMaterializer(
            unsplitFaceMaterializer: ClosedIntersectionUnsplitFaceMaterializer(
                pointClassifier: ConstantPointClassifier(classification: .outside)
            )
        ).materialize(
            operation: .difference,
            targetBodyIDs: [targetBody.id],
            toolBodyID: toolBody.id,
            featureID: FeatureID(),
            model: model,
            sourceSubshapes: sourceSubshapes,
            uvSplitGraph: BooleanUVSplitGraph(splits: splits),
            regionSelectionGraph: BooleanRegionSelectionGraph(decisions: decisions),
            tolerance: tolerance
        )

        let targetPatch = try #require(request.shells.flatMap(\.patches).first { patch in
            patch.stableID.hasPrefix("closed-intersection:face:\(targetFace.id):region:root")
        })
        #expect(targetPatch.loops.filter { $0.role == .outer }.count == 1)
        #expect(targetPatch.loops.filter { $0.role == .inner }.count == 2)
        #expect(request.shells.count == 1)
        let sewn = try DefaultBRepSewer().sew(request, tolerance: tolerance)
        #expect(sewn.brep.faces.count == 4)
        try sewn.brep.validate(level: .exact, tolerance: tolerance)
    }

    @Test(.timeLimit(.minutes(1)))
    func nestedClosedPcurvesProduceDeterministicContainmentParent() throws {
        let target = try PlanarSheetTestFixture.make(featureID: FeatureID(), tolerance: .standard)
        let body = try #require(target.brep.bodies.values.first)
        let shell = try #require(target.brep.shells[body.shellIDs[0]])
        let face = try #require(target.brep.faces[shell.faceIDs[0]])
        let surface = try #require(target.brep.geometry.surfaces[face.surfaceID])
        let outerToolSurface = try paraboloidSurface(physicalRadius: 0.007)
        let innerToolSurface = try paraboloidSurface(physicalRadius: 0.003)
        let outerClosed = try closedIntersection(
            targetSurface: surface,
            toolSurface: outerToolSurface,
            physicalRadius: 0.007
        )
        let innerClosed = try closedIntersection(
            targetSurface: surface,
            toolSurface: innerToolSurface,
            physicalRadius: 0.003
        )
        let outerReference = BooleanFaceSplitComponentReference(
            facePair: BooleanFacePairCandidate(
                targetFaceID: face.id,
                toolFaceID: FaceID()
            ),
            componentID: BooleanFaceSplitComponentID(ordinal: 0)
        )
        let innerReference = BooleanFaceSplitComponentReference(
            facePair: BooleanFacePairCandidate(
                targetFaceID: face.id,
                toolFaceID: FaceID()
            ),
            componentID: BooleanFaceSplitComponentID(ordinal: 0)
        )
        let tree = try BooleanClosedPcurveContainmentTree(
            regions: [
                BooleanClosedPcurveRegion(
                    reference: innerReference,
                    closedIntersection: innerClosed,
                    surfaceSide: .first,
                    surface: surface,
                    tolerance: tolerance
                ),
                BooleanClosedPcurveRegion(
                    reference: outerReference,
                    closedIntersection: outerClosed,
                    surfaceSide: .first,
                    surface: surface,
                    tolerance: tolerance
                ),
            ],
            tolerance: tolerance
        )

        #expect(tree.roots == [outerReference])
        #expect(tree.nodes[outerReference]?.children == [innerReference])
        #expect(tree.nodes[innerReference]?.parent == outerReference)
    }

    private func paraboloidSurface(
        center: Point2D = Point2D(x: 0.0, y: 0.0),
        physicalRadius: Double = 0.005
    ) throws -> Surface3D {
        let scale = 0.02
        let normalizedRadius = physicalRadius / scale
        let parameterValues = [0.0, 0.5, 1.0]
        let quadraticCoefficients = [0.25, -0.25, 0.25]
        let controlPoints = parameterValues.indices.map { vIndex in
            parameterValues.indices.map { uIndex in
                Point3D(
                    x: center.x + scale * (parameterValues[uIndex] - 0.5),
                    y: center.y + scale * (parameterValues[vIndex] - 0.5),
                    z: quadraticCoefficients[uIndex]
                        + quadraticCoefficients[vIndex]
                        - normalizedRadius * normalizedRadius
                )
            }
        }
        let surface = BSplineSurface3D(
            uDegree: 2,
            vDegree: 2,
            uKnots: [0.0, 0.0, 0.0, 1.0, 1.0, 1.0],
            vKnots: [0.0, 0.0, 0.0, 1.0, 1.0, 1.0],
            controlPoints: controlPoints
        )
        try surface.validate(tolerance: tolerance)
        return .bSpline(surface)
    }

    private func closedIntersection(
        targetSurface: Surface3D,
        toolSurface: Surface3D,
        center: Point2D = Point2D(x: 0.0, y: 0.0),
        physicalRadius: Double = 0.005
    ) throws -> BooleanClosedFaceIntersection {
        let surfaceScale = 0.02
        let normalizedRadius = physicalRadius / surfaceScale
        let diagonalWeight = 0.5.squareRoot()
        let weights = [
            1.0, diagonalWeight, 1.0, diagonalWeight, 1.0,
            diagonalWeight, 1.0, diagonalWeight, 1.0,
        ]
        let unitControlPoints = [
            Point2D(x: 1.0, y: 0.0),
            Point2D(x: 1.0, y: 1.0),
            Point2D(x: 0.0, y: 1.0),
            Point2D(x: -1.0, y: 1.0),
            Point2D(x: -1.0, y: 0.0),
            Point2D(x: -1.0, y: -1.0),
            Point2D(x: 0.0, y: -1.0),
            Point2D(x: 1.0, y: -1.0),
            Point2D(x: 1.0, y: 0.0),
        ]
        let knots = [
            0.0, 0.0, 0.0, 1.0, 1.0, 2.0,
            2.0, 3.0, 3.0, 4.0, 4.0, 4.0,
        ]
        let curveControlPoints = unitControlPoints.map { point in
            Point3D(
                x: center.x + physicalRadius * point.x,
                y: center.y + physicalRadius * point.y,
                z: 0.0
            )
        }
        let curve = Curve3D.bSpline(BSplineCurve3D(
            degree: 2,
            knots: knots,
            controlPoints: curveControlPoints,
            weights: weights
        ))
        let targetParameters = try curveControlPoints.map { point -> Point2D in
            let projection = try targetSurface.parameterProjection(
                of: point,
                tolerance: tolerance
            )
            return Point2D(x: projection.u, y: projection.v)
        }
        let toolParameters = unitControlPoints.map { point in
            Point2D(
                x: 0.5 + normalizedRadius * point.x,
                y: 0.5 + normalizedRadius * point.y
            )
        }
        let targetPcurve = SurfaceParameterCurve.bSpline(BSplineCurve2D(
            degree: 2,
            knots: knots,
            controlPoints: targetParameters,
            weights: weights
        ))
        let toolPcurve = SurfaceParameterCurve.bSpline(BSplineCurve2D(
            degree: 2,
            knots: knots,
            controlPoints: toolParameters,
            weights: weights
        ))
        let curveStart = try curve.point(at: 0.0, tolerance: tolerance)
        let targetAnchor = try targetSurface.parameterProjection(
            of: curveStart,
            tolerance: tolerance
        )
        let toolAnchorPoint = try toolSurface.point(
            u: 0.5 + normalizedRadius,
            v: 0.5,
            tolerance: tolerance
        )
        let toolAnchor = try SurfaceParameterProjection(
            u: 0.5 + normalizedRadius,
            v: 0.5,
            point: toolAnchorPoint,
            residual: (toolAnchorPoint - curveStart).length
        )
        let intersection = try SurfaceSurfaceIntersectionCurve(
            curve: curve,
            kind: .transverse,
            firstSurfaceParameterCurve: targetPcurve,
            secondSurfaceParameterCurve: toolPcurve,
            firstSurfaceAnchor: targetAnchor,
            secondSurfaceAnchor: toolAnchor,
            maximumResidual: (toolAnchorPoint - curveStart).length,
            tolerance: tolerance
        )
        let samples = try (0..<32).map { index in
            let parameter = 4.0 * Double(index) / 32.0
            let point = try curve.point(at: parameter, tolerance: tolerance)
            let targetParameter = try targetPcurve.parameter(
                atCurveParameter: parameter,
                curveDomain: curve.parameterDomain,
                tolerance: tolerance
            )
            let toolParameter = try toolPcurve.parameter(
                atCurveParameter: parameter,
                curveDomain: curve.parameterDomain,
                tolerance: tolerance
            )
            return try BooleanCurveUVSample(
                curveParameter: parameter,
                uvPoint: BooleanUVPoint(
                    point: point,
                    targetU: targetParameter.u,
                    targetV: targetParameter.v,
                    toolU: toolParameter.u,
                    toolV: toolParameter.v,
                    residual: 0.0,
                    tolerance: tolerance
                ),
                tolerance: tolerance
            )
        }
        return try BooleanClosedFaceIntersection(
            intersection: intersection,
            samples: samples,
            tolerance: tolerance
        )
    }

    private func decision(
        pair: BooleanFacePairCandidate,
        faceID: FaceID,
        oppositeBodyID: BodyID,
        side: BooleanClassificationGraph.Side,
        point: Point3D,
        classification: SolidPointClassification,
        action: BooleanRegionSelectionAction
    ) -> BooleanRegionSelectionGraph.Decision {
        BooleanRegionSelectionGraph.Decision(
            sample: BooleanClassificationGraph.Sample(
                facePair: pair,
                componentID: BooleanFaceSplitComponentID(ordinal: 0),
                sourceFaceID: faceID,
                oppositeBodyID: oppositeBodyID,
                side: side,
                point: point,
                classification: classification
            ),
            action: action
        )
    }

    private func interiorSide(
        samples: [BooleanCurveUVSample],
        faceOrientation: Orientation,
        parameter: (BooleanCurveUVSample) -> (u: Double, v: Double)
    ) -> BooleanClassificationGraph.Side {
        var signedDoubleArea = 0.0
        for index in samples.indices {
            let current = parameter(samples[index])
            let next = parameter(samples[(index + 1) % samples.count])
            signedDoubleArea += current.u * next.v - current.v * next.u
        }
        let counterclockwise = signedDoubleArea > 0.0
        return counterclockwise == (faceOrientation == .forward) ? .positive : .negative
    }

    private func opposite(
        _ side: BooleanClassificationGraph.Side
    ) -> BooleanClassificationGraph.Side {
        side == .positive ? .negative : .positive
    }

    private struct ConstantPointClassifier: SolidPointClassifying {
        let classification: SolidPointClassification

        func classify(
            _ point: Point3D,
            in bodyID: BodyID,
            model: BRepModel,
            tolerance: ModelingTolerance
        ) throws -> SolidPointClassification {
            try tolerance.validate()
            try point.validate()
            guard model.bodies[bodyID] != nil else {
                throw KernelError(
                    phase: .classification,
                    code: .missingReference,
                    tolerance: tolerance,
                    message: "Test classifier received a missing body."
                )
            }
            return classification
        }
    }
}
