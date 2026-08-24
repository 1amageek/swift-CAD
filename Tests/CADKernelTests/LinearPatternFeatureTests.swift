import Testing
import CADCore
import CADGeometry
import CADIR
import CADModeling
import CADTopology
@testable import CADKernel

@Suite("Linear pattern feature")
struct LinearPatternFeatureTests {
    @Test(.timeLimit(.minutes(1)))
    func createsSeparatedExactInstancesWithSplitLineage() throws {
        var document = makeRectangleExtrudeDocument(documentUnits: .meters)
        let sourceFeatureID = try #require(document.designGraph.order.last)
        let source = try DocumentEvaluator(tolerance: .standard, artifactPolicy: .deferred).evaluate(document)
        let sourceFaceID = SubshapeID(
            featureID: sourceFeatureID,
            role: GeneratedSubshapeRole.startFace.rawValue,
            ordinal: 0
        )
        let sourceFace = try source.stableSubshapeReference(for: sourceFaceID)
        let patternID = FeatureID()
        let operation = FeatureOperation.linearPattern(LinearPatternFeature(
            target: PatternTargetReference(featureID: sourceFeatureID),
            direction: .unitX,
            spacing: .constant(.length(0.060, unit: .meter)),
            count: 3
        ))
        let node = try FeatureNodeFactory.make(operation: operation, id: patternID, in: document, tolerance: .standard)
        document.designGraph.nodes[patternID] = node
        document.designGraph.order.append(patternID)
        document.designGraph.dependencies.append(DependencyEdge(source: sourceFeatureID, target: patternID))
        document.designGraph.revision = document.designGraph.revision.advanced()

        let evaluated = try DocumentEvaluator(tolerance: .standard, artifactPolicy: .deferred).evaluate(document)
        try evaluated.brep.validate(level: .volumetric, tolerance: .standard)
        #expect(evaluated.brep.bodies.count == 1)
        #expect(evaluated.brep.shells.count == 3)
        #expect(evaluated.brep.faces.count == 18)
        #expect(evaluated.brep.edges.count == 36)
        #expect(evaluated.brep.vertices.count == 24)
        #expect(abs(try evaluated.brep.volume(tolerance: .standard) - 3.0 * 0.040 * 0.020 * 0.010) <= 1.0e-12)
        let patternLineage = evaluated.lineage.values.filter { $0.output.featureID == patternID }
        #expect(patternLineage.count == 79)
        #expect(patternLineage.filter { $0.relation == .preserved && $0.output.role == "body" }.count == 1)
        #expect(patternLineage.filter { $0.relation == .split }.count == 78)
        do {
            _ = try StableSubshapeResolver().topologyReference(
                for: sourceFace,
                model: evaluated.brep,
                subshapes: evaluated.subshapes,
                lineage: evaluated.lineage,
                tolerance: .standard
            )
            Issue.record("Patterned source face must remain ambiguous across its three exact descendants.")
        } catch let error as KernelError {
            #expect(error.code == .ambiguousSelection)
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func unionsOverlappingInstancesExactly() throws {
        var document = makeRectangleExtrudeDocument(documentUnits: .meters)
        let sourceFeatureID = try #require(document.designGraph.order.last)
        let patternID = FeatureID()
        let operation = FeatureOperation.linearPattern(LinearPatternFeature(
            target: PatternTargetReference(featureID: sourceFeatureID),
            direction: .unitX,
            spacing: .constant(.length(0.020, unit: .meter)),
            count: 2
        ))
        let node = try FeatureNodeFactory.make(operation: operation, id: patternID, in: document, tolerance: .standard)
        document.designGraph.nodes[patternID] = node
        document.designGraph.order.append(patternID)
        document.designGraph.dependencies.append(DependencyEdge(source: sourceFeatureID, target: patternID))
        document.designGraph.revision = document.designGraph.revision.advanced()

        let evaluated = try DocumentEvaluator(
            tolerance: .standard,
            artifactPolicy: .deferred
        ).evaluate(document)
        try evaluated.brep.validate(level: .volumetric, tolerance: .standard)
        #expect(evaluated.brep.bodies.count == 1)
        #expect(evaluated.brep.shells.count == 1)
        #expect(evaluated.brep.faces.count == 6)
        #expect(evaluated.brep.edges.count == 12)
        #expect(evaluated.brep.vertices.count == 8)
        #expect(abs(
            try evaluated.brep.volume(tolerance: .standard)
                - 0.060 * 0.020 * 0.010
        ) <= 1.0e-12)
        let patternLineage = evaluated.lineage.values.filter {
            $0.output.featureID == patternID
        }
        #expect(patternLineage.isEmpty == false)
        #expect(patternLineage.flatMap(\.parents).allSatisfy {
            $0.featureID == sourceFeatureID
        })
    }

    @Test(.timeLimit(.minutes(1)))
    func duplicatesSeparatedParameterPreservingBSplineBodyGeometry() throws {
        let fixture = try parameterEquivalentBSplineFixture()
        let result = try fixture.rebuilder.rebuild(
            featureID: FeatureID(),
            sourceBodyID: fixture.sourceBodyID,
            transforms: [
                .translated(by: .zero),
                .translated(by: Vector3D(x: 0.060, y: 0.0, z: 0.0)),
            ],
            stablePrefix: "bSplinePattern",
            context: fixture.context
        )

        try result.brep.validate(level: .volumetric, tolerance: .standard)
        #expect(result.brep.shells.count == 2)
        #expect(result.brep.geometry.surfaces.values.allSatisfy {
            if case .bSpline = $0 { return true }
            return false
        })
        #expect(result.brep.geometry.curves.values.allSatisfy {
            if case .bSpline = $0 { return true }
            return false
        })
        #expect(abs(
            try result.brep.volume(tolerance: .standard)
                - 2.0 * 0.040 * 0.020 * 0.010
        ) <= 1.0e-12)
    }

    @Test(.timeLimit(.minutes(1)))
    func mirrorsParameterPreservingBSplineBodyGeometry() throws {
        let fixture = try parameterEquivalentBSplineFixture()
        let mirrored = try fixture.rebuilder.rebuild(
            featureID: FeatureID(),
            sourceBodyID: fixture.sourceBodyID,
            transforms: [
                .translated(by: .zero),
                try .mirrored(
                    across: Point3D(x: 0.050, y: 0.0, z: 0.0),
                    normal: .unitX,
                    tolerance: .standard
                ),
            ],
            stablePrefix: "bSplineMirror",
            context: fixture.context
        )
        try mirrored.brep.validate(level: .volumetric, tolerance: .standard)
        #expect(abs(
            try mirrored.brep.volume(tolerance: .standard)
                - 2.0 * 0.040 * 0.020 * 0.010
        ) <= 1.0e-12)
    }

    @Test(.timeLimit(.minutes(1)))
    func collapsesCoincidentParameterPreservingBSplineBodies() throws {
        let fixture = try parameterEquivalentBSplineFixture()
        let coincident = try fixture.rebuilder.rebuild(
            featureID: FeatureID(),
            sourceBodyID: fixture.sourceBodyID,
            transforms: [
                .translated(by: .zero),
                .translated(by: .zero),
            ],
            stablePrefix: "bSplineCoincidentPattern",
            context: fixture.context
        )
        try coincident.brep.validate(level: .volumetric, tolerance: .standard)
        #expect(coincident.brep.shells.count == 1)
        #expect(abs(
            try coincident.brep.volume(tolerance: .standard)
                - 0.040 * 0.020 * 0.010
        ) <= 1.0e-12)
    }

    @Test(.timeLimit(.minutes(1)))
    func unionsOverlappingParameterPreservingBSplineBodies() throws {
        let fixture = try parameterEquivalentBSplineFixture()
        let overlapping = try fixture.rebuilder.rebuild(
            featureID: FeatureID(),
            sourceBodyID: fixture.sourceBodyID,
            transforms: [
                .translated(by: .zero),
                .translated(by: Vector3D(x: 0.020, y: 0.0, z: 0.0)),
            ],
            stablePrefix: "bSplineOverlappingPattern",
            context: fixture.context
        )
        try overlapping.brep.validate(level: .volumetric, tolerance: .standard)
        #expect(overlapping.brep.shells.count == 1)
        #expect(abs(
            try overlapping.brep.volume(tolerance: .standard)
                - 0.060 * 0.020 * 0.010
        ) <= 1.0e-12)
    }

    @Test(.timeLimit(.minutes(1)))
    func preservesDisconnectedComponentsWhenALaterInstanceOverlapsOnlyOneComponent() throws {
        let fixture = try parameterEquivalentBSplineFixture()
        let patternID = FeatureID()
        let result = try fixture.rebuilder.rebuild(
            featureID: patternID,
            sourceBodyID: fixture.sourceBodyID,
            transforms: [
                .translated(by: .zero),
                .translated(by: Vector3D(x: 0.060, y: 0.0, z: 0.0)),
                .translated(by: Vector3D(x: 0.080, y: 0.0, z: 0.0)),
            ],
            stablePrefix: "bSplineMixedPattern",
            context: fixture.context
        )

        try result.brep.validate(level: .volumetric, tolerance: .standard)
        let body = try #require(result.brep.bodies.values.first)
        let components = try #require(body.solidComponents)
        #expect(components.count == 2)
        #expect(result.brep.shells.count == 2)
        #expect(abs(
            try result.brep.volume(tolerance: .standard)
                - 0.100 * 0.020 * 0.010
        ) <= 1.0e-12)
        #expect(result.lineage.values.flatMap(\.parents).allSatisfy {
            $0.featureID != patternID
        })
    }

    @Test(.timeLimit(.minutes(1)))
    func overlappingParameterPreservingBSplineBodiesProduceClosedSewingRequest() throws {
        let fixture = try parameterEquivalentBSplineFixture()
        let rebuilder = DefaultExactBodyPatternRebuilder(
            sewer: DefaultBRepSewer(),
            unionApplicator: BooleanUnionInputCapture(),
            separationValidator: ExactBodyJoinValidator()
        )
        var capturedInput: BooleanUnionInputCapture.Input?
        do {
            _ = try rebuilder.rebuild(
                featureID: FeatureID(),
                sourceBodyID: fixture.sourceBodyID,
                transforms: [
                    .translated(by: .zero),
                    .translated(by: Vector3D(x: 0.020, y: 0.0, z: 0.0)),
                ],
                stablePrefix: "bSplineOverlappingRequest",
                context: fixture.context
            )
            Issue.record("The capture applicator must stop before Boolean evaluation.")
        } catch let stop as BooleanUnionInputCapture.Stop {
            capturedInput = stop.input
        } catch {
            throw error
        }
        let input = try #require(capturedInput)
        let evaluator = ExactBRepBooleanEvaluator()
        let pipeline = BooleanPipeline(evaluator: evaluator)
        let intersectionGraph = try pipeline.intersectionGraph(
            targetBodyIDs: input.targetBodyIDs,
            toolBodyID: input.toolBodyID,
            operation: input.operation,
            model: input.model,
            tolerance: input.tolerance
        )
        let uvSplitGraph = try pipeline.uvSplitGraph(
            intersectionGraph: intersectionGraph,
            model: input.model,
            tolerance: input.tolerance
        )
        let classificationGraph = try pipeline.classificationGraph(
            uvSplitGraph: uvSplitGraph,
            targetBodyIDs: input.targetBodyIDs,
            toolBodyID: input.toolBodyID,
            model: input.model,
            tolerance: input.tolerance
        )
        let regionSelectionGraph = try pipeline.regionSelectionGraph(
            operation: input.operation,
            classificationGraph: classificationGraph,
            tolerance: input.tolerance
        )
        let selection = try evaluator.exactRegionSelection(
            operation: input.operation,
            targetBodyIDs: input.targetBodyIDs,
            toolBodyID: input.toolBodyID,
            featureID: input.featureID,
            model: input.model,
            subshapes: input.subshapes,
            uvSplitGraph: uvSplitGraph,
            regionSelectionGraph: regionSelectionGraph,
            tolerance: input.tolerance
        )
        try selection.sewingRequest.validate(tolerance: input.tolerance)
        _ = try DefaultBRepSewer().sew(
            selection.sewingRequest,
            tolerance: input.tolerance
        )
    }

    @Test(.timeLimit(.minutes(1)))
    func duplicatesExactCylinderWithMappedAnalyticPcurves() throws {
        let primitiveID = FeatureID()
        let patternID = FeatureID()
        var document = CADDocument(units: .meters)
        document.designGraph.nodes[primitiveID] = try FeatureNodeFactory.make(
            operation: .primitive(PrimitiveFeature(definition: .cylinder(
                CylinderPrimitive(
                    radius: .constant(.length(0.010, unit: .meter)),
                    height: .constant(.length(0.020, unit: .meter))
                )
            ))),
            id: primitiveID,
            in: document,
            tolerance: .standard
        )
        document.designGraph.order.append(primitiveID)
        document.designGraph.nodes[patternID] = try FeatureNodeFactory.make(
            operation: .linearPattern(LinearPatternFeature(
                target: PatternTargetReference(featureID: primitiveID),
                direction: .unitX,
                spacing: .constant(.length(0.040, unit: .meter)),
                count: 2
            )),
            id: patternID,
            in: document,
            tolerance: .standard
        )
        document.designGraph.order.append(patternID)
        document.designGraph.dependencies.append(DependencyEdge(
            source: primitiveID,
            target: patternID
        ))
        document.designGraph.revision = document.designGraph.revision.advanced()

        let evaluated = try DocumentEvaluator(
            tolerance: .standard,
            artifactPolicy: .deferred
        ).evaluate(document)

        try evaluated.brep.validate(level: .volumetric, tolerance: .standard)
        #expect(evaluated.brep.shells.count == 2)
        #expect(abs(
            try evaluated.brep.volume(tolerance: .standard)
                - 2.0 * Double.pi * 0.010 * 0.010 * 0.020
        ) <= 1.0e-12)
        #expect(evaluated.brep.geometry.surfaces.values.contains {
            if case .cylinder = $0 { return true }
            return false
        })
        #expect(evaluated.brep.loops.values.allSatisfy { loop in
            loop.coedges.allSatisfy { $0.surfaceParameterCurve != nil }
        })
    }

    private struct ParameterEquivalentBSplineFixture {
        let sourceBodyID: BodyID
        let context: EvaluationContext
        let rebuilder: DefaultExactBodyPatternRebuilder
    }

    private struct BooleanUnionInputCapture: BooleanOperationApplying {
        struct Input: Sendable {
            let operation: BooleanOperation
            let targetBodyIDs: [BodyID]
            let toolBodyID: BodyID
            let featureID: FeatureID
            let model: BRepModel
            let subshapes: [SubshapeID: TopologyReference]
            let tolerance: ModelingTolerance
        }

        struct Stop: Error {
            let input: Input
        }

        func apply(
            operation: BooleanOperation,
            targetBodyIDs: [BodyID],
            toolBodyID: BodyID,
            keepTools: Bool,
            featureID: FeatureID,
            model: BRepModel,
            subshapes: [SubshapeID: TopologyReference],
            toolSubshapes: [SubshapeID: TopologyReference],
            inputLineage: [SubshapeID: TopologyLineage],
            tolerance: ModelingTolerance
        ) throws -> EvaluationResult {
            throw Stop(input: Input(
                operation: operation,
                targetBodyIDs: targetBodyIDs,
                toolBodyID: toolBodyID,
                featureID: featureID,
                model: model,
                subshapes: subshapes,
                tolerance: tolerance
            ))
        }
    }

    private func parameterEquivalentBSplineFixture() throws
        -> ParameterEquivalentBSplineFixture {
        let document = makeRectangleExtrudeDocument(documentUnits: .meters)
        let evaluated = try DocumentEvaluator(
            tolerance: .standard,
            artifactPolicy: .deferred
        ).evaluate(document)
        var sourceModel = evaluated.brep
        try replacePlanarBoxGeometryWithParameterEquivalentBSplines(
            in: &sourceModel,
            tolerance: .standard
        )
        try sourceModel.validate(level: .exact, tolerance: .standard)
        let sourceBodyID = try #require(sourceModel.bodies.keys.first)
        return ParameterEquivalentBSplineFixture(
            sourceBodyID: sourceBodyID,
            context: EvaluationContext(
                parameters: evaluated.parameters,
                brep: sourceModel,
                profiles: [:],
                curves: evaluated.curves,
                subshapes: evaluated.subshapes,
                lineage: evaluated.lineage,
                tolerance: .standard
            ),
            rebuilder: DefaultExactBodyPatternRebuilder(
                sewer: DefaultBRepSewer(),
                unionApplicator: ExactBooleanOperationApplicator(),
                separationValidator: ExactBodyJoinValidator()
            )
        )
    }

    private func replacePlanarBoxGeometryWithParameterEquivalentBSplines(
        in model: inout BRepModel,
        tolerance: ModelingTolerance
    ) throws {
        for edgeID in model.edges.keys.sorted() {
            guard let edge = model.edges[edgeID],
                  let trim = edge.trim,
                  let curve = model.geometry.curves[edge.curveID] else {
                throw TopologyError.missingReference(
                    "B-spline pattern fixture edge geometry is missing."
                )
            }
            let lower = min(trim.startParameter, trim.endParameter)
            let upper = max(trim.startParameter, trim.endParameter)
            model.geometry.curves[edge.curveID] = .bSpline(BSplineCurve3D(
                degree: 1,
                knots: [lower, lower, upper, upper],
                controlPoints: [
                    try curve.point(at: lower, tolerance: tolerance),
                    try curve.point(at: upper, tolerance: tolerance),
                ]
            ))
        }

        for faceID in model.faces.keys.sorted() {
            guard let face = model.faces[faceID],
                  let surface = model.geometry.surfaces[face.surfaceID] else {
                throw TopologyError.missingReference(
                    "B-spline pattern fixture face geometry is missing."
                )
            }
            let loopParameters = try face.loops.flatMap { loopID -> [SurfaceParameter] in
                guard let loop = model.loops[loopID] else {
                    throw TopologyError.missingReference(
                        "B-spline pattern fixture loop is missing."
                    )
                }
                return try loop.coedges.flatMap { coedge -> [SurfaceParameter] in
                    guard let parameterCurve = coedge.surfaceParameterCurve else {
                        throw TopologyError.missingReference(
                            "B-spline pattern fixture pcurve is missing."
                        )
                    }
                    return [
                        try parameterCurve.startParameter(tolerance: tolerance),
                        try parameterCurve.endParameter(tolerance: tolerance),
                    ]
                }
            }
            let uLower = try #require(loopParameters.map(\.u).min())
            let uUpper = try #require(loopParameters.map(\.u).max())
            let vLower = try #require(loopParameters.map(\.v).min())
            let vUpper = try #require(loopParameters.map(\.v).max())
            model.geometry.surfaces[face.surfaceID] = .bSpline(BSplineSurface3D(
                uDegree: 1,
                vDegree: 1,
                uKnots: [uLower, uLower, uUpper, uUpper],
                vKnots: [vLower, vLower, vUpper, vUpper],
                controlPoints: [
                    [
                        try surface.point(u: uLower, v: vLower, tolerance: tolerance),
                        try surface.point(u: uUpper, v: vLower, tolerance: tolerance),
                    ],
                    [
                        try surface.point(u: uLower, v: vUpper, tolerance: tolerance),
                        try surface.point(u: uUpper, v: vUpper, tolerance: tolerance),
                    ],
                ]
            ))
        }
    }
}
