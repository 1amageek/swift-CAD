import Testing
import Synchronization
import CADCore
import CADGeometry
import CADIR
import CADTopology
@testable import CADModeling

@Suite("Boolean dimensional admission and publication")
struct BooleanDimensionTests {
    private let resolver: any BooleanDimensionResolving = DefaultBooleanDimensionResolver()

    @Test(.timeLimit(.minutes(1)))
    func defaultOperationMatrixConsumesRootDimensionRatherThanBoundaryEdges() throws {
        let model = try tetrahedron()
        let solid = Shape(root: .solid(try #require(model.bodies.keys.first)), model: model)
        let sheet = Shape(root: .face(try #require(model.faces.keys.first)), model: model)
        for operation in BooleanOperation.allCases {
            for target in [solid, sheet] {
                for tool in [solid, sheet] {
                    let feature = boolean(operation: operation)
                    let contract = try resolver.resolve(feature: feature, targets: [target], tools: [tool], tolerance: .standard)
                    let targetIsSolid = target.root == solid.root
                    #expect(contract.targetDimensions == [targetIsSolid ? .volume : .surface])
                    #expect(contract.toolDimensions == [tool.root == solid.root ? .volume : .surface])
                    #expect(contract.outputDimension == (operation == .region || targetIsSolid ? .volume : .surface))
                    #expect(contract.lossPolicy.returnsStandaloneLowerDimensionalContacts == false)
                    #expect(contract.lossPolicy.replacesTargetIdentities)
                }
            }
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func materialMatrixConsumesCADIRPortAuthorityAndDeclaresSliceLoss() throws {
        let model = try tetrahedron()
        let solid = Shape(root: .solid(try #require(model.bodies.keys.first)), model: model)
        let sheet = Shape(root: .shell(try #require(model.shells.keys.first)), model: model)
        for target in [solid, sheet] {
            for tool in [solid, sheet] {
                for targetMaterial in BooleanMaterial.allCases {
                    for toolMaterial in BooleanMaterial.allCases {
                        let feature = boolean(operation: .slice, keepTools: true,
                            targetMaterial: targetMaterial, toolMaterial: toolMaterial)
                        let contract = try resolver.resolve(feature: feature, targets: [target], tools: [tool], tolerance: .standard)
                        let targetPort: FeaturePort = target.root == solid.root ? .body : .sheet
                        #expect(contract.outputPort == (try feature.resultPort(targetPorts: [targetPort])))
                        #expect(contract.lossPolicy.retainsOriginalTools)
                        let completeEnvelope = target.root == solid.root && tool.root == solid.root
                            && targetMaterial == .default && toolMaterial == .default
                        #expect(contract.lossPolicy.sliceToolRegions == (completeEnvelope
                            ? .includedForDefaultSolidInputs : .notGeneratedInCurrentEnvelope))
                    }
                }
            }
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func validStandaloneEdgeWireAndVertexAreNotBooleanCapability() throws {
        let model = try tetrahedron()
        let edgeID = try #require(model.edges.keys.first)
        let roots: [ShapeReference] = [.edge(edgeID), .wire(ShapeWire(edges: [ShapeEdgeUse(edgeID: edgeID)])),
            .vertex(try #require(model.vertices.keys.first))]
        let solid = Shape(root: .solid(try #require(model.bodies.keys.first)), model: model)
        for root in roots {
            let input = Shape(root: root, model: model)
            try DefaultShapeOperator().validate(input, tolerance: .standard)
            expectKernelError(.unsupportedCapability) {
                _ = try resolver.resolve(feature: boolean(), targets: [solid], tools: [input], tolerance: .standard)
            }
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func sheetAggregatesPreserveAllRootsAndRejectHeterogeneousSelections() throws {
        let model = try tetrahedron()
        let faces = Array(model.faces.keys)
        let first = try #require(faces.first)
        let second = try #require(faces.dropFirst().first)
        let solidID = try #require(model.bodies.keys.first)
        let solid = Shape(root: .solid(solidID), model: model)
        let sheet = Shape(root: .compound([.face(first), .compound([.face(second)])]), model: model)
        #expect(try resolver.resolve(feature: boolean(), targets: [sheet], tools: [solid], tolerance: .standard).outputDimension == .surface)
        let mixed = Shape(root: .compound([.face(first), .edge(try #require(model.edges.keys.first))]), model: model)
        try DefaultShapeOperator().validate(mixed, tolerance: .standard)
        expectKernelError(.unsupportedCapability) {
            _ = try resolver.resolve(feature: boolean(), targets: [mixed], tools: [solid], tolerance: .standard)
        }
        expectKernelError(.invalidInput) {
            _ = try resolver.resolve(feature: boolean(), targets: [Shape(root: .compound([]), model: model)], tools: [solid], tolerance: .standard)
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func mixedTargetsAndNonVolumeMultipleToolsAreRefusedBeforeGeometry() throws {
        let model = try tetrahedron()
        let solid = Shape(root: .solid(try #require(model.bodies.keys.first)), model: model)
        let sheet = Shape(root: .face(try #require(model.faces.keys.first)), model: model)
        var feature = boolean()
        feature.targets.append(BooleanTargetReference(featureID: FeatureID()))
        expectKernelError(.invalidInput) {
            _ = try resolver.resolve(feature: feature, targets: [solid, sheet], tools: [solid], tolerance: .standard)
        }
        feature = boolean()
        feature.tools.append(BooleanToolReference(featureID: FeatureID()))
        expectKernelError(.invalidInput) {
            _ = try resolver.resolve(feature: feature, targets: [solid], tools: [solid, sheet], tolerance: .standard)
        }
        #expect(try resolver.resolve(feature: feature, targets: [solid], tools: [solid, solid], tolerance: .standard).toolDimensions == [.volume, .volume])
        feature.toolMaterial = .outside
        expectKernelError(.invalidInput) {
            _ = try resolver.resolve(feature: feature, targets: [solid], tools: [solid, solid], tolerance: .standard)
        }
        feature.operation = .region
        feature.toolMaterial = .default
        #expect(try resolver.resolve(feature: feature, targets: [sheet], tools: [solid, sheet], tolerance: .standard).outputDimension == .volume)
    }

    @available(macOS 15.0, iOS 18.0, tvOS 18.0, watchOS 11.0, *)
    @Test(.timeLimit(.minutes(1)))
    func changingProviderIsAcquiredOnceAndItsOwnedSnapshotIsUsed() throws {
        let model = try tetrahedron()
        let solid = Shape(root: .solid(try #require(model.bodies.keys.first)), model: model)
        let provider = ChangingProvider(first: solid,
            later: Shape(root: .edge(try #require(model.edges.keys.first)), model: model))
        let contract = try resolver.resolve(feature: boolean(), targets: [provider], tools: [solid], tolerance: .standard)
        #expect(provider.acquisitions == 1)
        #expect(contract.targetDimensions == [.volume])
        expectKernelError(.unsupportedCapability) {
            _ = try resolver.resolve(feature: boolean(), targets: [provider], tools: [solid], tolerance: .standard)
        }
        #expect(provider.acquisitions == 2)
        #expect(contract.targetDimensions == [.volume])
    }

    @Test(.timeLimit(.minutes(1)))
    func malformedSelectionFailsValidityRatherThanCapabilityAdmission() throws {
        let model = try tetrahedron()
        let solid = Shape(root: .solid(try #require(model.bodies.keys.first)), model: model)
        do {
            _ = try resolver.resolve(feature: boolean(), targets: [solid],
                tools: [Shape(root: .edge(EdgeID()), model: model)], tolerance: .standard)
            Issue.record("A missing selected edge must fail T1 validity before Boolean admission.")
        } catch TopologyError.missingReference {
            // Preserve T1's original typed failure rather than replacing it with
            // a Boolean capability refusal or wrapping it in a different error.
        } catch {
            Issue.record("Expected TopologyError.missingReference, received \(error).")
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func publishedBodyKindIsVerifiedIndependentlyOfUnrelatedSolidBodies() throws {
        let model = try tetrahedron()
        let solid = Shape(root: .solid(try #require(model.bodies.keys.first)), model: model)
        let featureID = FeatureID()
        let output = SubshapeID(featureID: featureID, role: GeneratedSubshapeRole.body.rawValue, ordinal: 0)
        let contract = try resolver.resolve(feature: boolean(), targets: [solid], tools: [solid], tolerance: .standard)
        let sheet = try sheetModel(from: tetrahedron(offset: Vector3D(x: 3, y: 0, z: 0)))
        let sheetID = try #require(sheet.bodies.keys.first)
        var mixed = model
        try BRepModelCombiner().merge(sheet, into: &mixed)
        expectKernelError(.topologyFailure) {
            try contract.validateResult(EvaluationResult(brep: mixed, subshapes: [output: .body(sheetID)]),
                featureID: featureID, tolerance: .standard)
        }
        try contract.validateResult(EvaluationResult(brep: mixed, subshapes: [output: .body(try #require(model.bodies.keys.first))]),
            featureID: featureID, tolerance: .standard)
        expectKernelError(.topologyFailure) {
            try contract.validateResult(EvaluationResult(brep: mixed), featureID: featureID, tolerance: .standard)
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func productionEvaluatorRejectsWrongBodyKindAndPropagatesGeometryFailure() throws {
        let first = try tetrahedron()
        let second = try tetrahedron(offset: Vector3D(x: 3, y: 0, z: 0))
        var model = first
        try BRepModelCombiner().merge(second, into: &model)
        let boolean = boolean()
        let feature = FeatureNode(operation: .boolean(boolean), outputs: [FeatureOutput(role: .body)])
        let context = EvaluationContext(parameters: ResolvedParameterTable(), brep: model, profiles: [:],
            subshapes: SubshapeIndex([
                SubshapeID(featureID: boolean.targets[0].featureID, role: GeneratedSubshapeRole.body.rawValue, ordinal: 0):
                    .body(try #require(first.bodies.keys.first)),
                SubshapeID(featureID: boolean.tools[0].featureID, role: GeneratedSubshapeRole.body.rawValue, ordinal: 0):
                    .body(try #require(second.bodies.keys.first))
            ]), tolerance: .standard)
        let wrongDimension = try sheetModel(from: first)
        try wrongDimension.validate(level: .exact, tolerance: .standard)
        expectKernelError(.topologyFailure) {
            _ = try BooleanFeatureEvaluator(applicator: FixtureApplicator(output: wrongDimension))
                .evaluate(feature: feature, context: context)
        }
        expectKernelError(.unsupportedCapability) {
            _ = try BooleanFeatureEvaluator(applicator: FixtureApplicator(output: nil))
                .evaluate(feature: feature, context: context)
        }
        var wrongPort = feature
        wrongPort.outputs = [FeatureOutput(role: .sheet)]
        expectKernelError(.invalidInput) {
            _ = try BooleanFeatureEvaluator(applicator: FixtureApplicator(output: nil))
                .evaluate(feature: wrongPort, context: context)
        }
    }

    private func boolean(operation: BooleanOperation = .difference, keepTools: Bool = false,
                         targetMaterial: BooleanMaterial = .default,
                         toolMaterial: BooleanMaterial = .default) -> BooleanFeature {
        BooleanFeature(targets: [BooleanTargetReference(featureID: FeatureID())],
            tools: [BooleanToolReference(featureID: FeatureID())], operation: operation,
            keepTools: keepTools, targetMaterial: targetMaterial, toolMaterial: toolMaterial)
    }

    private func expectKernelError(_ code: KernelErrorCode, _ operation: () throws -> Void) {
        do { try operation(); Issue.record("Expected the dimensional contract to refuse this operation.") }
        catch let error as KernelError { #expect(error.code == code) }
        catch { Issue.record("Expected a typed KernelError, received \(error).") }
    }

    private func sheetModel(from model: BRepModel) throws -> BRepModel {
        let faceID = try #require(model.faces.keys.first)
        var sheet = try DefaultShapeOperator().extract(Shape(root: .face(faceID), model: model), tolerance: .standard).model
        let shell = Shell(faceIDs: [faceID])
        let body = Body(sheetShellIDs: [shell.id])
        sheet.shells[shell.id] = shell
        sheet.bodies[body.id] = body
        return sheet
    }

    // An independently oriented closed tetrahedron with exact line trims and planar pcurves.
    private func tetrahedron(offset: Vector3D = .zero) throws -> BRepModel {
        let points = [Point3D.origin, Point3D(x: 1, y: 0, z: 0), Point3D(x: 0, y: 1, z: 0), Point3D(x: 0, y: 0, z: 1)]
            .map { $0 + offset }
        let vertices = points.map { Vertex(point: $0) }
        var model = BRepModel(vertices: Dictionary(uniqueKeysWithValues: vertices.map { ($0.id, $0) }))
        var edgeIDs: [String: EdgeID] = [:]
        var faceIDs: [FaceID] = []
        for indices in [[0, 2, 1], [0, 1, 3], [0, 3, 2], [1, 2, 3]] {
            let a = points[indices[0]], b = points[indices[1]], c = points[indices[2]]
            let normal = try (b - a).cross(c - a).normalized(tolerance: ModelingTolerance.standard.distance)
            let surface = Surface3D.plane(Plane3D(origin: a, normal: normal))
            let surfaceID = SurfaceID()
            model.geometry.surfaces[surfaceID] = surface
            var uses: [Coedge] = []
            for index in indices.indices {
                let first = indices[index], last = indices[(index + 1) % indices.count]
                let key = "\(min(first, last)):\(max(first, last))"
                let edgeID: EdgeID
                let orientation: Orientation
                if let existingID = edgeIDs[key], let existing = model.edges[existingID] {
                    edgeID = existingID
                    orientation = existing.startVertexID == vertices[first].id ? .forward : .reversed
                } else {
                    let curveID = CurveID()
                    let direction = try (points[last] - points[first]).normalized(tolerance: ModelingTolerance.standard.distance)
                    model.geometry.curves[curveID] = .line(Line3D(origin: points[first], direction: direction))
                    let edge = Edge(curveID: curveID, startVertexID: vertices[first].id, endVertexID: vertices[last].id,
                        trim: CurveTrim(startParameter: 0, endParameter: (points[last] - points[first]).length))
                    edgeID = edge.id
                    model.edges[edgeID] = edge
                    edgeIDs[key] = edgeID
                    orientation = .forward
                }
                let start = try surface.parameterProjection(of: points[first], tolerance: .standard)
                let end = try surface.parameterProjection(of: points[last], tolerance: .standard)
                uses.append(Coedge(edgeID: edgeID, orientation: orientation,
                    surfaceParameterCurve: .polyline([SurfaceParameter(u: start.u, v: start.v), SurfaceParameter(u: end.u, v: end.v)])))
            }
            let loop = Loop(coedges: uses)
            let face = Face(surfaceID: surfaceID, loops: [loop.id])
            model.loops[loop.id] = loop
            model.faces[face.id] = face
            faceIDs.append(face.id)
        }
        let shell = Shell(faceIDs: faceIDs)
        let body = Body(solidComponents: [SolidShellComponent(outerShellID: shell.id)])
        model.shells[shell.id] = shell
        model.bodies[body.id] = body
        return model
    }

    // Deliberately adversarial applicator: tests publication enforcement, not Boolean geometry.
    private struct FixtureApplicator: BooleanOperationApplying {
        let output: BRepModel?

        func apply(operation: BooleanOperation, targetBodyIDs: [BodyID], toolBodyID: BodyID,
                   keepTools: Bool, featureID: FeatureID, model: BRepModel,
                   subshapes: [SubshapeID: TopologyReference], toolSubshapes: [SubshapeID: TopologyReference],
                   inputLineage: [SubshapeID: TopologyLineage], materials: BooleanMaterials,
                   tolerance: ModelingTolerance) throws -> EvaluationResult {
            guard let output else {
                throw KernelError(phase: .evaluation, code: .unsupportedCapability, featureID: featureID,
                    tolerance: tolerance, message: "Fixture geometry capability refusal.")
            }
            let bodyID = try #require(output.bodies.keys.first)
            let id = SubshapeID(featureID: featureID, role: GeneratedSubshapeRole.body.rawValue, ordinal: 0)
            return EvaluationResult(brep: output, subshapes: [id: .body(bodyID)],
                lineage: [id: TopologyLineage(output: id, relation: .generated)])
        }
    }

    @available(macOS 15.0, iOS 18.0, tvOS 18.0, watchOS 11.0, *)
    private final class ChangingProvider: ShapeRepresenting {
        private struct State {
            let first: Shape
            let later: Shape
            var count = 0
        }
        private let state: Mutex<State>

        init(first: Shape, later: Shape) { state = Mutex(State(first: first, later: later)) }
        var acquisitions: Int { state.withLock { $0.count } }
        func shapeSnapshot() -> Shape {
            state.withLock {
                $0.count += 1
                return $0.count == 1 ? $0.first : $0.later
            }
        }
    }
}
