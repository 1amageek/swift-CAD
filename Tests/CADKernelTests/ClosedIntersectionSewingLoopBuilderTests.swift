import CADCore
import CADGeometry
import CADIR
import CADTopology
import Testing
@testable import CADKernel

@Suite("Closed Intersection Sewing Loop Builder")
struct ClosedIntersectionSewingLoopBuilderTests {
    private let tolerance = ModelingTolerance.standard

    @Test(.timeLimit(.minutes(1)))
    func boundedRationalBSplineSelectionMaterializesExactTwoFaceShell() throws {
        let firstSurface = Surface3D.bSpline(BSplineSurface3D(
            uDegree: 2,
            vDegree: 2,
            uKnots: [0.0, 0.0, 0.0, 1.0, 1.0, 1.0],
            vKnots: [0.0, 0.0, 0.0, 1.0, 1.0, 1.0],
            controlPoints: surfaceControlPoints(centerHeight: 0.0)
        ))
        let secondSurface = Surface3D.bSpline(BSplineSurface3D(
            uDegree: 2,
            vDegree: 2,
            uKnots: [0.0, 0.0, 0.0, 1.0, 1.0, 1.0],
            vKnots: [0.0, 0.0, 0.0, 1.0, 1.0, 1.0],
            controlPoints: surfaceControlPoints(centerHeight: 1.0)
        ))
        let curvePoints = [
            Point3D(x: 0.0, y: 0.0, z: 0.0),
            Point3D(x: 1.0, y: 0.0, z: 0.0),
            Point3D(x: 1.0, y: 1.0, z: 0.0),
            Point3D(x: 0.0, y: 1.0, z: 0.0),
            Point3D(x: 0.0, y: 0.0, z: 0.0),
        ]
        let knots = [10.0, 10.0, 11.0, 12.0, 13.0, 14.0, 14.0]
        let curve = Curve3D.bSpline(BSplineCurve3D(
            degree: 1,
            knots: knots,
            controlPoints: curvePoints
        ))
        let pcurve = SurfaceParameterCurve.bSpline(BSplineCurve2D(
            degree: 1,
            knots: knots,
            controlPoints: curvePoints.map { Point2D(x: $0.x, y: $0.y) }
        ))
        let anchor = try SurfaceParameterProjection(
            u: 0.0,
            v: 0.0,
            point: curvePoints[0],
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
            let parameter = 10.0 + 4.0 * Double(index) / 32.0
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
        let closedIntersection = try BooleanClosedFaceIntersection(
            intersection: intersection,
            samples: samples,
            tolerance: tolerance
        )
        let firstSurfaceID = SurfaceID()
        let secondSurfaceID = SurfaceID()
        let targetFace = Face(surfaceID: firstSurfaceID, loops: [], orientation: .forward)
        let toolFace = Face(surfaceID: secondSurfaceID, loops: [], orientation: .reversed)
        let targetShell = Shell(faceIDs: [targetFace.id])
        let toolShell = Shell(faceIDs: [toolFace.id])
        let targetBody = Body(
            solidComponents: [SolidShellComponent(outerShellID: targetShell.id)]
        )
        let toolBody = Body(
            solidComponents: [SolidShellComponent(outerShellID: toolShell.id)]
        )
        let model = BRepModel(
            geometry: GeometryStore(surfaces: [
                firstSurfaceID: firstSurface,
                secondSurfaceID: secondSurface,
            ]),
            bodies: [
                targetBody.id: targetBody,
                toolBody.id: toolBody,
            ],
            shells: [
                targetShell.id: targetShell,
                toolShell.id: toolShell,
            ],
            faces: [
                targetFace.id: targetFace,
                toolFace.id: toolFace,
            ]
        )
        let pair = BooleanFacePairCandidate(
            targetFaceID: targetFace.id,
            toolFaceID: toolFace.id
        )
        let uvSplitGraph = BooleanUVSplitGraph(splits: [BooleanFaceSplit(
            facePair: pair,
            components: [BooleanFaceSplitComponent(
                id: BooleanFaceSplitComponentID(ordinal: 0),
                geometry: .closedCurve(closedIntersection)
            )]
        )])
        let targetDecision = BooleanRegionSelectionGraph.Decision(
            sample: BooleanClassificationGraph.Sample(
                facePair: pair,
                componentID: BooleanFaceSplitComponentID(ordinal: 0),
                sourceFaceID: targetFace.id,
                oppositeBodyID: toolBody.id,
                side: .positive,
                point: curvePoints[0],
                classification: .inside
            ),
            action: .keep
        )
        let targetExteriorDecision = BooleanRegionSelectionGraph.Decision(
            sample: BooleanClassificationGraph.Sample(
                facePair: pair,
                componentID: BooleanFaceSplitComponentID(ordinal: 0),
                sourceFaceID: targetFace.id,
                oppositeBodyID: toolBody.id,
                side: .negative,
                point: curvePoints[0],
                classification: .outside
            ),
            action: .discard
        )
        let toolDecision = BooleanRegionSelectionGraph.Decision(
            sample: BooleanClassificationGraph.Sample(
                facePair: pair,
                componentID: BooleanFaceSplitComponentID(ordinal: 0),
                sourceFaceID: toolFace.id,
                oppositeBodyID: targetBody.id,
                side: .negative,
                point: curvePoints[0],
                classification: .inside
            ),
            action: .keep
        )
        let toolExteriorDecision = BooleanRegionSelectionGraph.Decision(
            sample: BooleanClassificationGraph.Sample(
                facePair: pair,
                componentID: BooleanFaceSplitComponentID(ordinal: 0),
                sourceFaceID: toolFace.id,
                oppositeBodyID: targetBody.id,
                side: .positive,
                point: curvePoints[0],
                classification: .outside
            ),
            action: .discard
        )
        let featureID = FeatureID()
        let targetParent = SubshapeID(featureID: FeatureID(), role: "face", ordinal: 0)
        let toolParent = SubshapeID(featureID: FeatureID(), role: "face", ordinal: 0)
        let evaluator = ExactBRepBooleanEvaluator()
        let requirement = try evaluator.intersectionRequirement(
            operation: .intersect,
            targetBodyIDs: [targetBody.id],
            toolBodyID: toolBody.id,
            model: model,
            tolerance: tolerance
        )
        #expect(requirement == .required)
        let exactSelection = try evaluator.exactRegionSelection(
            operation: .intersect,
            targetBodyIDs: [targetBody.id],
            toolBodyID: toolBody.id,
            featureID: featureID,
            model: model,
            subshapes: [
                targetParent: .face(targetFace.id),
                toolParent: .face(toolFace.id),
            ],
            uvSplitGraph: uvSplitGraph,
            regionSelectionGraph: BooleanRegionSelectionGraph(
                decisions: [
                    targetDecision,
                    targetExteriorDecision,
                    toolDecision,
                    toolExteriorDecision,
                ]
            ),
            tolerance: tolerance
        )
        let classificationGraph = BooleanClassificationGraph(samples: [
            targetDecision.sample,
            targetExteriorDecision.sample,
            toolDecision.sample,
            toolExteriorDecision.sample,
        ])
        try exactSelection.validate(
            operation: .intersect,
            featureID: featureID,
            classificationGraph: classificationGraph,
            tolerance: tolerance
        )
        let intersectionGraph = BooleanIntersectionGraph(
            facePairs: [pair],
            boundaryContacts: [],
            faceIntersections: [BooleanFaceSurfaceIntersection(
                facePair: pair,
                geometry: .curve(intersection)
            )]
        )
        let result = try evaluator.evaluate(
            operation: .intersect,
            targetBodyIDs: [targetBody.id],
            toolBodyID: toolBody.id,
            keepTools: false,
            featureID: featureID,
            model: model,
            subshapes: [
                targetParent: .face(targetFace.id),
                toolParent: .face(toolFace.id),
            ],
            toolSubshapes: [:],
            intersectionGraph: intersectionGraph,
            uvSplitGraph: uvSplitGraph,
            classificationGraph: classificationGraph,
            exactRegionSelectionGraph: exactSelection,
            tolerance: tolerance
        )

        #expect(result.brep.faces.count == 2)
        #expect(result.brep.edges.count == 2)
        #expect(result.brep.vertices.count == 2)
        #expect(result.lineage.values.contains { $0.parents == [targetParent] })
        #expect(result.lineage.values.contains { $0.parents == [toolParent] })
        try result.brep.validate(level: .exact, tolerance: tolerance)
    }

    private func surfaceControlPoints(centerHeight: Double) -> [[Point3D]] {
        [0.0, 0.5, 1.0].map { v in
            [0.0, 0.5, 1.0].map { u in
                Point3D(
                    x: u,
                    y: v,
                    z: u == 0.5 && v == 0.5 ? centerHeight : 0.0
                )
            }
        }
    }
}
