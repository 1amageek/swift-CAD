import Foundation
import CADCore
import CADGeometry
import CADIR
import CADModeling
import CADTopology
import Testing
@testable import CADKernel

@Suite("Face Rebuild direct execution", .timeLimit(.minutes(1)))
struct FaceRebuildDirectExecutionTests {
    private let tolerance = ModelingTolerance.standard

    private func surface() -> BSplineSurface3D {
        BSplineSurface3D(uDegree: 1, vDegree: 1,
            uKnots: [0, 0, 1, 1], vKnots: [0, 0, 1, 1],
            controlPoints: [
                [Point3D(x: 0, y: 0, z: 0), Point3D(x: 1, y: 0, z: 0)],
                [Point3D(x: 0, y: 1, z: 0), Point3D(x: 1, y: 1, z: 0)],
            ], weights: [[1, 1], [1, 1]])
    }

    private func execution(work: Int = 8_388_608,
        checkpoint: (@Sendable () throws -> Void)? = nil) throws -> OriginalQueryExecution {
        OriginalQueryExecution(budget: try OriginalQueryBudget(workLimit: work,
            storageByteLimit: 268_435_456, checkpoint: checkpoint),
            limits: try .init(maximumValueDepth: 32, maximumCoefficientDepth: 32,
                remainingSourceDepth: 16, maximumSubdivisionDepth: 32))
    }

    private func fixture() throws -> (context: EvaluationContext,
        request: FaceRebuildFeature, faceID: FaceID) {
        let sourceID = FeatureID(PortableIdentity128(high: 11, low: 1))
        var preparation = try execution()
        // This is an authored public B-rep input, not a sewing result or a
        // fabricated validation receipt. The evaluator validates the raw model.
        let bodyID = BodyID(PortableIdentity128(high: 13, low: 1))
        let shellID = ShellID(PortableIdentity128(high: 14, low: 1))
        let faceID = FaceID(PortableIdentity128(high: 15, low: 1))
        let surfaceID = SurfaceID(PortableIdentity128(high: 16, low: 1))
        let loopID = LoopID(PortableIdentity128(high: 17, low: 1))
        let expectedPoints = [Point3D(x: 0, y: 0, z: 0), Point3D(x: 1, y: 0, z: 0),
            Point3D(x: 1, y: 1, z: 0), Point3D(x: 0, y: 1, z: 0)]
        let vertexIDs = (1...4).map { VertexID(PortableIdentity128(high: 18, low: UInt64($0))) }
        let edgeIDs = (1...4).map { EdgeID(PortableIdentity128(high: 19, low: UInt64($0))) }
        let curveIDs = (1...4).map { CurveID(PortableIdentity128(high: 20, low: UInt64($0))) }
        let pcurves: [SurfaceParameterCurve] = [
            .constantV(v: 0, uStart: 0, uEnd: 1),
            .constantU(u: 1, vStart: 0, vEnd: 1),
            .constantV(v: 1, uStart: 1, uEnd: 0),
            .constantU(u: 0, vStart: 1, vEnd: 0),
        ]
        let nativeSurface = Surface3D.bSpline(surface())
        var points: [Point3D] = []
        for (index, pcurve) in pcurves.enumerated() {
            let start = try pcurve.parameter(atNormalizedFraction: 0, tolerance: tolerance,
                using: &preparation)
            let end = try pcurve.parameter(atNormalizedFraction: 1, tolerance: tolerance,
                using: &preparation)
            let first = try nativeSurface.point(u: start.u, v: start.v,
                tolerance: tolerance, using: &preparation)
            let last = try nativeSurface.point(u: end.u, v: end.v,
                tolerance: tolerance, using: &preparation)
            #expect(first == expectedPoints[index])
            #expect(last == expectedPoints[(index + 1) % expectedPoints.count])
            points.append(first)
        }
        var model = BRepModel(geometry: GeometryStore(surfaces: [surfaceID: nativeSurface]),
            bodies: [bodyID: Body(id: bodyID, sheetShellIDs: [shellID])],
            shells: [shellID: Shell(id: shellID, faceIDs: [faceID], orientation: .forward)],
            faces: [faceID: Face(id: faceID, surfaceID: surfaceID, loops: [loopID], orientation: .forward)],
            loops: [loopID: Loop(id: loopID, role: .outer, coedges: edgeIDs.enumerated().map {
                Coedge(edgeID: $0.element, orientation: .forward, surfaceParameterCurve: pcurves[$0.offset])
            })])
        let selected = SubshapeID(featureID: sourceID, role: "face", ordinal: 0)
        var subshapes: [SubshapeID: TopologyReference] = [
            SubshapeID(featureID: sourceID, role: "body", ordinal: 0): .body(bodyID),
            selected: .face(faceID),
        ]
        for index in points.indices {
            let next = (index + 1) % points.count
            model.vertices[vertexIDs[index]] = Vertex(id: vertexIDs[index], point: points[index])
            // The authored edge is the exact lift of this face's native chart.
            // Whole-use structural correspondence still requires source validation;
            // this fixture does not claim independent curve-to-surface certification.
            model.geometry.curves[curveIDs[index]] = .surfaceLift(SurfaceLiftCurve3D(
                surface: nativeSurface, parameterCurve: pcurves[index]))
            model.edges[edgeIDs[index]] = Edge(id: edgeIDs[index], curveID: curveIDs[index],
                startVertexID: vertexIDs[index], endVertexID: vertexIDs[next],
                trim: CurveTrim(startParameter: 0, endParameter: 1))
            subshapes[SubshapeID(featureID: sourceID, role: "edge", ordinal: index)] = .edge(edgeIDs[index])
            subshapes[SubshapeID(featureID: sourceID, role: "vertex", ordinal: index)] = .vertex(vertexIDs[index])
        }
        let lineage = Dictionary(uniqueKeysWithValues: subshapes.keys.map {
            ($0, TopologyLineage(output: $0, relation: .generated))
        })
        let signature = try SubshapeGeometrySignatureBuilder(model: model, tolerance: tolerance)
            .signature(for: .face(faceID), using: &preparation)
        let context = EvaluationContext(parameters: ResolvedParameterTable(), brep: model,
            profiles: [:], subshapes: SubshapeIndex(subshapes), lineage: lineage,
            tolerance: tolerance)
        let request = FaceRebuildFeature(target: PatternTargetReference(featureID: sourceID),
            faces: [StableSubshapeReference(subshapeID: selected, geometrySignature: signature)],
            method: .given(surface()))
        return (context, request, faceID)
    }

    @Test func nativeGivenKeepsItsEdgesUnderTheIncomingExecution() async throws {
        // Only authentic fixture authoring uses the main executor; the evaluator
        // and its measured incoming execution run after this preparation boundary.
        let fixture = try await MainActor.run { try fixture() }
        var execution = try execution()
        let feature = FeatureNode(id: FeatureID(PortableIdentity128(high: 12, low: 1)),
            operation: .faceRebuild(fixture.request))
        let result = try FaceRebuildFeatureEvaluator().evaluate(feature: feature,
            context: fixture.context, using: &execution)
        #expect(result.brep.edges == fixture.context.brep.edges)
        #expect(result.brep.vertices == fixture.context.brep.vertices)
        #expect(result.brep.geometry.curves == fixture.context.brep.geometry.curves)
        #expect(result.brep.loops == fixture.context.brep.loops)
        #expect(result.brep.faces.count == 1)
        let face = try #require(result.brep.faces[fixture.faceID])
        let retainedSurface = try #require(result.brep.geometry.surfaces[face.surfaceID])
        #expect(retainedSurface == .bSpline(surface()))
        #expect(try retainedSurface.normal(u: 0.5, v: 0.5, tolerance: tolerance,
            using: &execution) == .unitZ)
        #expect(execution.localWork > 0)
        #expect(execution.localStorageBytes > 0)
    }

    @Test func givenMethodValidationRequiresEveryNativeSourceDebit() throws {
        let surface = surface()
        var source = try execution()
        try surface.validate(tolerance: tolerance, using: &source)
        let requiredWork = source.localWork + 1
        var exact = try execution(work: requiredWork)
        try FaceRebuildMethod.given(surface).validate(using: &exact)
        #expect(exact.localWork == requiredWork)
        var short = try execution(work: requiredWork - 1)
        do {
            try FaceRebuildMethod.given(surface).validate(using: &short)
            Issue.record("Given request validation escaped its caller's native source work.")
        } catch {
            let published = OriginalQueryFailure.published(error, context: short.context, tolerance: tolerance)
            #expect(OriginalQueryFailure.classification(of: published)?.code == .resourceLimitExceeded)
        }
    }

    @Test func squareRequiredProducerRefusesWithoutPublishing() async throws {
        // Only authentic fixture authoring uses the main executor; the evaluator
        // and its measured incoming execution run after this preparation boundary.
        let fixture = try await MainActor.run { try fixture() }
        var request = fixture.request
        request.method = .square(SquareRefit())
        let feature = FeatureNode(id: FeatureID(PortableIdentity128(high: 12, low: 2)),
            operation: .faceRebuild(request))
        var execution = try execution()
        do {
            _ = try FaceRebuildFeatureEvaluator().evaluate(feature: feature,
                context: fixture.context, using: &execution)
            Issue.record("Square refit published through an ordinary-only source producer.")
        } catch {
            #expect(OriginalQueryFailure.classification(of: error)?.code == .unsupportedCapability)
        }
        #expect(fixture.context.brep.faces[fixture.faceID] != nil)
    }

    @Test func nativeGivenPreservesCallerCancellation() async throws {
        // Only authentic fixture authoring uses the main executor; the evaluator
        // and its measured incoming execution run after this preparation boundary.
        let fixture = try await MainActor.run { try fixture() }
        let feature = FeatureNode(id: FeatureID(PortableIdentity128(high: 12, low: 3)),
            operation: .faceRebuild(fixture.request))
        var execution = try execution(checkpoint: { throw CancellationError() })
        do {
            _ = try FaceRebuildFeatureEvaluator().evaluate(feature: feature,
                context: fixture.context, using: &execution)
            Issue.record("Cancelled native given support returned a rebuilt body.")
        } catch let failure as ExactScalarFailure {
            guard case .cancelled = failure else { throw failure }
        } catch is CancellationError {
        } catch {
            #expect(OriginalQueryFailure.classification(of: error)?.code == .cancelled)
        }
    }
}
