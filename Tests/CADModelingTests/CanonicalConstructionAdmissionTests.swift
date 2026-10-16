import CADCore
import Foundation
import CADGeometry
import CADIR
import CADTopology
import Testing
import Synchronization

@testable import CADModeling

@Suite("Canonical construction admission", .timeLimit(.minutes(1)))
struct CanonicalConstructionAdmissionTests {
    private enum Construction: CaseIterable { case bridge, draft }

    @Test
    func authoredPlanarWallChartsConstructTheBridge() throws {
        let budget = try OriginalQueryBudget()
        var execution = OriginalQueryExecution(budget: budget, limits: try limits())
        let surface = try bridge(using: &execution)
        #expect(budget.snapshot.work > 0 && budget.snapshot.storageBytes > 0)
        for (v, expected) in [(0.0, Point3D(x: 0.5, y: 0, z: 0)),
                              (1.0, Point3D(x: 0.5, y: 1, z: 1))] {
            let point = try surface.point(u: 0.5, v: v, tolerance: .standard)
            #expect((point - expected).length <= ModelingTolerance.standard.distance)
        }
    }

    @Test
    func aChartAgreeingAtEveryInitialStationCannotBorrowWholeBoundaryAuthority() throws {
        // This quartic is zero at all four initial cubic Greville stations.
        // Its nonzero intervals are an independent whole-chart counterexample.
        let wrong = BSplineCurve2D(degree: 4,
            knots: [0, 0, 0, 0, 0, 1, 1, 1, 1, 1],
            controlPoints: [
                .init(x: 0, y: 0), .init(x: 0.25, y: -1.0 / 1800),
                .init(x: 0.5, y: 5.0 / 5400), .init(x: 0.75, y: -1.0 / 1800),
                .init(x: 1, y: 0)
            ])
        for t in [0.0, 1.0 / 3, 2.0 / 3, 1.0] {
            let point = try wrong.point(at: t, tolerance: .standard)
            #expect(abs(point.y) < 1e-12)
        }
        let interior = try wrong.point(at: 0.5, tolerance: .standard)
        #expect(abs(interior.y) > ModelingTolerance.standard.distance)
        var execution = OriginalQueryExecution(budget: try OriginalQueryBudget(), limits: try limits())
        do {
            _ = try bridge(startChart: .bSpline(wrong), using: &execution)
            Issue.record("A chart that only agrees at collocation stations published a bridge.")
        } catch {
            let failure = OriginalQueryFailure.classification(of: error)
            #expect(failure?.code == .intersectionFailure || failure?.code == .classificationFailure)
        }
    }

    @Test
    func nativeDraftRetainsItsOffsetLawAndEndpointContinuationForBothEntries() throws {
        let native = sourceCurve()
        let approximator = PlanarCurveOffsetApproximator(tolerance: .standard)
        let interval = try ScalarInterval(lower: -0.25, upper: 1.25)
        var execution = OriginalQueryExecution(budget: try OriginalQueryBudget(), limits: try limits())
        let basis = try approximator.basis(for: native, normal: .unitZ, reach: 0.2,
            over: interval, using: &execution)
        let continued = try approximator.offset(native, normal: .unitZ, shift: 0.2,
            knots: basis, using: &execution)
        for t in [-0.25, 0.5, 1.25] {
            let point = try continued.point(at: t, tolerance: .standard)
            #expect((point - Point3D(x: t, y: -0.2, z: 0)).length <= ModelingTolerance.standard.distance)
        }
        let source = try PlanarOffsetCurveSource(curve: native, normal: .unitZ,
            shift: 0.2, tolerance: .standard, using: &execution)
        let bounds = try source.enclosure(over: interval, tolerance: .standard, using: &execution)
        #expect(bounds.position.x.lower <= -0.25 && bounds.position.x.upper >= 1.25)
        #expect(bounds.position.y.lower <= -0.2 && bounds.position.y.upper >= -0.2)

        let builder = ExactDraftedProfileBoundaryBuilder(tolerance: .standard, splineReach: 0.25)
        let ordinary = try builder.openCurve(evaluatedCurve(), planeNormal: .unitZ,
            axis: .unitZ, height: 0.5, tangent: 0.5)
        let borrowed = try builder.openCurve(evaluatedCurve(), planeNormal: .unitZ,
            axis: .unitZ, height: 0.5, tangent: 0.5, using: &execution)
        #expect(ordinary == borrowed)
        let output = try #require(borrowed.first)
        let point = try output.point(at: 0.5, tolerance: .standard)
        #expect((point - Point3D(x: 0.5, y: 0.25, z: 0.5)).length <= ModelingTolerance.standard.distance)
    }

    @Test
    func bothActualBuildersRefuseResourceExhaustionAndCancellationBeforePublication() throws {
        for kind in Construction.allCases {
            let noWork = try OriginalQueryBudget(workLimit: 0)
            expectResourceRefusal(kind, budget: noWork, resource: .work, axis: .work)
            #expect(noWork.snapshot.work == 0)

            let noStorage = try OriginalQueryBudget(storageByteLimit: 0)
            expectResourceRefusal(kind, budget: noStorage, resource: .storage, axis: .storageBytes)
            #expect(noStorage.snapshot.storageBytes == 0)

            let budget = try OriginalQueryBudget(checkpoint: { throw ExactScalarFailure.cancelled })
            var execution = OriginalQueryExecution(budget: budget, limits: try limits())
            do {
                try construct(kind, using: &execution)
                Issue.record("Cancelled construction published a candidate.")
            } catch let error as ExactScalarFailure {
                guard case .cancelled = error else {
                    Issue.record("Construction lost its original cancellation cause: \(error).")
                    continue
                }
            }
            #expect(budget.snapshot.work == 0 && budget.snapshot.storageBytes == 0)
        }
    }

    @Test
    func unrepresentedOriginalBoundaryCannotUseAnApproximateSplineFallback() throws {
        var execution = OriginalQueryExecution(budget: try OriginalQueryBudget(), limits: try limits())
        let points = [Point3D.origin, Point3D(x: 1, y: 1, z: 0), Point3D(x: 3, y: 1, z: 0)]
        let original = try OriginalPolylineCurve3D(points: points, isClosed: false,
            tolerance: .standard, remainingSourceDepth: 16, maximumSubdivisionDepth: 20,
            maximumAlgebraicDepth: 32, usage: &execution)
        let curveID = CurveID(), edgeID = EdgeID()
        let start = Vertex(point: points[0]), end = Vertex(point: points[2])
        let model = BRepModel(geometry: GeometryStore(curves: [curveID: .originalPolyline(original)]),
            edges: [edgeID: Edge(id: edgeID, curveID: curveID, startVertexID: start.id,
                endVertexID: end.id, trim: .init(startParameter: 0, endParameter: 1))],
            vertices: [start.id: start, end.id: end])
        let resolver = ExactBoundaryCurveResolver(), featureID = FeatureID()
        for borrowed in [false, true] {
            do {
                if borrowed {
                    _ = try resolver.curve(edgeID: edgeID, followsStoredDirection: true,
                        model: model, tolerance: .standard, featureID: featureID, using: &execution)
                } else {
                    _ = try resolver.curve(edgeID: edgeID, followsStoredDirection: true,
                        model: model, tolerance: .standard, featureID: featureID)
                }
                Issue.record("An unrepresented original boundary published a replacement spline.")
            } catch {
                #expect(OriginalQueryFailure.classification(of: error)?.code == .unsupportedCapability)
            }
        }
    }

    @Test
    func shellEdgeFanRetainsNativeLineSpanCorrespondence() throws {
        var execution = OriginalQueryExecution(budget: try OriginalQueryBudget(), limits: try limits())
        let fan = BRepSewingEdgeFan(tolerance: .standard)
        let line = try sewingEdge(.line(.init(origin: .origin, direction: .unitX)), using: &execution)
        for reversed in [false, true] {
            let span = try sewingEdge(.bSpline(sourceCurve()), reversed: reversed, using: &execution)
            #expect(try fan.edgesMatch(line, span, using: &execution))
            #expect(try fan.edgesMatch(line, span))
        }
    }

    @Test
    func fiveMatchingStationsCannotAuthorizeAShellConnection() throws {
        var execution = OriginalQueryExecution(budget: try OriginalQueryBudget(), limits: try limits())
        // The Bernstein ordinates represent t(t-1/4)(t-1/2)(t-3/4)(t-1).
        let heights = [0.0, 3.0 / 160, -13.0 / 320, 13.0 / 320, -3.0 / 160, 0.0]
        let candidate = Curve3D.bSpline(.init(degree: 5,
            knots: Array(repeating: 0, count: 6) + Array(repeating: 1, count: 6),
            controlPoints: heights.enumerated().map { index, height in
                Point3D(x: Double(index) / 5, y: 0, z: height)
            }))
        let line = Curve3D.line(.init(origin: .origin, direction: .unitX))
        for t in [0.0, 0.25, 0.5, 0.75, 1.0] {
            let point = try candidate.point(at: t, tolerance: .standard, using: &execution)
            let expected = try line.point(at: t, tolerance: .standard, using: &execution)
            #expect((point - expected).length <= ModelingTolerance.standard.distance)
        }
        let interior = try candidate.point(at: 0.125, tolerance: .standard, using: &execution)
        #expect(abs(interior.z) > ModelingTolerance.standard.distance)
        let first = try sewingEdge(line, using: &execution)
        let second = try sewingEdge(candidate, using: &execution)
        let fan = BRepSewingEdgeFan(tolerance: .standard)
        #expect(try !fan.edgesMatch(first, second, using: &execution))
        #expect(try !fan.edgesMatch(first, second))
    }

    @Test
    func sewingRequestBodyParentsDebitTheActualScanAndRetainRefusal() throws {
        let small = sewingRequest(parentCount: 1)
        let large = sewingRequest(parentCount: 17)
        func charge(_ request: BRepSewingRequest) throws -> Int {
            let budget = try OriginalQueryBudget()
            var execution = OriginalQueryExecution(budget: budget, limits: try limits())
            try request.validate(tolerance: .standard, using: &execution)
            return budget.snapshot.work
        }
        let smallWork = try charge(small), total = try charge(large)
        #expect(total - smallWork == 16)

        let exact = try OriginalQueryBudget(workLimit: total)
        var exactExecution = OriginalQueryExecution(budget: exact, limits: try limits())
        try large.validate(tolerance: .standard, using: &exactExecution)
        #expect(exact.snapshot.work == total)

        let oneLess = try OriginalQueryBudget(workLimit: total - 1)
        var limited = OriginalQueryExecution(budget: oneLess, limits: try limits())
        do {
            try large.validate(tolerance: .standard, using: &limited)
            Issue.record("A sewing request escaped its cumulative parent validation work ceiling.")
        } catch {
            assertResourceCause(error, resource: .work, axis: .work)
        }
        #expect(oneLess.snapshot.work <= total - 1)

        let observed = Mutex(0)
        let cancelled = try OriginalQueryBudget(consumeWorkUnits: { units in
            let shouldCancel = observed.withLock { work in
                work += units
                return work >= 5
            }
            if shouldCancel { throw ExactScalarFailure.cancelled }
        })
        var cancelledExecution = OriginalQueryExecution(budget: cancelled, limits: try limits())
        do {
            try large.validate(tolerance: .standard, using: &cancelledExecution)
            Issue.record("Cancellation during the body parent scan returned validation success.")
        } catch {
            #expect(isOriginalCancellation(error))
        }
        // Two request units and the third parent's committed unit precede
        // the outside-lock observer refusal; shell validation has not begun.
        #expect(cancelled.snapshot.work == 5)
    }

    @Test
    func retainedValidityEqualityAdmitsAnIndependentlyBackedSourceGraph() throws {
        let authored = try authoredPlaneLiftSheet()
        let certificate = try ValidatedBRepModel(authored, tolerance: .standard, validationLevel: .exact)
        // Encoding/decoding precedes the measured queries and replaces backing
        // collections and scalar buffers while preserving the original source.
        let wire = try JSONEncoder().encode(certificate.model)
        let independent = try JSONDecoder().decode(BRepModel.self, from: wire)
        #expect(independent == certificate.model)
        #expect(!independent.geometry.curves.isEmpty && !independent.geometry.surfaces.isEmpty)
        var mismatch = independent
        for (id, curve) in independent.geometry.curves {
            guard case .surfaceLift(let lift) = curve,
                  case .plane(let plane) = lift.surface else {
                Issue.record("The cache fixture contains a source other than its authored plane lift.")
                return
            }
            let shifted = Surface3D.plane(.init(origin: plane.origin + Vector3D.unitZ,
                normal: plane.normal, uDirection: plane.uDirection))
            mismatch.geometry.curves[id] = .surfaceLift(.init(
                surface: shifted, parameterCurve: lift.parameterCurve))
        }
        for (id, surface) in independent.geometry.surfaces {
            guard case .plane(let plane) = surface else {
                Issue.record("The native cache fixture contains a non-plane source.")
                return
            }
            mismatch.geometry.surfaces[id] = .plane(.init(origin: plane.origin + Vector3D.unitZ,
                normal: plane.normal, uDirection: plane.uDirection))
        }
        for (id, vertex) in independent.vertices {
            mismatch.vertices[id] = Vertex(id: id, point: vertex.point + Vector3D.unitZ)
        }
        #expect(mismatch != certificate.model)

        for publication in [false, true] {
            func replay(_ budget: OriginalQueryBudget, model: BRepModel) throws -> Int {
                var execution = OriginalQueryExecution(budget: budget, limits: try limits())
                if publication {
                    var result = EvaluationResult(brep: model)
                    result.validatedBRep = certificate
                    let validated = try ValidatedFeatureEvaluation(validating: result,
                        tolerance: .standard, using: &execution)
                    #expect(validated.brep.model == model)
                } else {
                    var context = EvaluationContext(parameters: ResolvedParameterTable(),
                        validatedBRep: certificate, profiles: [:])
                    context.brep = model
                    try FeatureEvaluationBoundary.validateExactInput(context,
                        featureID: FeatureID(), tolerance: .standard, using: &execution)
                }
                return budget.snapshot.work
            }
            let total = try replay(OriginalQueryBudget(), model: independent)
            #expect(total > 1)
            let exact = try OriginalQueryBudget(workLimit: total)
            #expect(try replay(exact, model: independent) == total)
            for limit in [1, total - 1] {
                let refused = try OriginalQueryBudget(workLimit: limit)
                do {
                    _ = try replay(refused, model: independent)
                    Issue.record("Retained validity equality escaped its cumulative source comparison ceiling.")
                } catch {
                    assertResourceCause(error, resource: .work, axis: .work)
                }
                #expect(refused.snapshot.work <= limit)
            }
            // Both graphs have identical payload sizes. A source mismatch must
            // leave the cache and pay the existing genuine validation fallback.
            #expect(try replay(OriginalQueryBudget(), model: mismatch) > total)
            let mismatchLimited = try OriginalQueryBudget(workLimit: total)
            do {
                _ = try replay(mismatchLimited, model: mismatch)
                Issue.record("A different original source reused the retained validity certificate.")
            } catch {
                assertResourceCause(error, resource: .work, axis: .work)
            }
            let cancelled = try OriginalQueryBudget(checkpoint: { throw ExactScalarFailure.cancelled })
            do {
                _ = try replay(cancelled, model: independent)
                Issue.record("Retained validity comparison published after cancellation.")
            } catch {
                #expect(isOriginalCancellation(error))
            }
            #expect(cancelled.snapshot.work == 0)
        }
    }

    @Test
    func callbackBoundariesPublishRawRefusalsBeforeClassifyingThem() throws {
        enum Boundary: CaseIterable { case request, validated, ordinary }
        enum Cause: CaseIterable { case work, cancelled, domain }
        for boundary in Boundary.allCases {
            for cause in Cause.allCases {
                let featureID = FeatureID()
                let originalDomain = KernelError(phase: .geometry, code: .invalidInput,
                    featureID: FeatureID(), tolerance: .standard,
                    message: "The callback's authored domain failure.")
                let budget = try OriginalQueryBudget(workLimit: 0)
                var execution = OriginalQueryExecution(budget: budget, limits: try limits(),
                    context: .init(operation: .conversion, entry: .admitted, stage: .request))
                func failBeforeOutput(using execution: inout OriginalQueryExecution) throws -> EvaluationResult {
                    switch cause {
                    case .cancelled: throw ExactScalarFailure.cancelled
                    case .domain: throw originalDomain
                    case .work:
                        try execution.consumeWork(1)
                        Issue.record("A zero-work callback escaped its original work ceiling.")
                        throw ExactScalarFailure.invalidEvidence
                    }
                }
                do {
                    switch boundary {
                    case .request:
                        try FeatureEvaluationBoundary.validateRequest(featureID: featureID,
                            tolerance: .standard, using: &execution) { execution in
                            _ = try failBeforeOutput(using: &execution)
                        }
                    case .validated:
                        _ = try FeatureEvaluationBoundary.evaluateValidated(featureID: featureID,
                            tolerance: .standard, using: &execution) { execution in
                            try failBeforeOutput(using: &execution)
                        }
                    case .ordinary:
                        _ = try FeatureEvaluationBoundary.evaluate(featureID: featureID,
                            tolerance: .standard) {
                            try failBeforeOutput(using: &execution)
                        }
                    }
                    Issue.record("A failing callback published an evaluation result.")
                } catch {
                    switch cause {
                    case .work:
                        assertResourceCause(error, resource: .work, axis: .work)
                        let failure = try #require(error as? OriginalQueryFailure)
                        #expect(failure.kernelFailure.featureID == featureID)
                        // The original query has already recorded its authority.
                        // An ordinary outer boundary only fills missing context.
                        #expect(failure.context.stage == .request)
                        #expect(failure.context.entry == .admitted)
                    case .cancelled:
                        #expect(isOriginalCancellation(error))
                        #expect(error is CancellationError)
                    case .domain:
                        let failure = try #require(error as? OriginalQueryFailure)
                        #expect(failure.kernelFailure == originalDomain)
                        #expect((failure.originalError as? KernelError) == originalDomain)
                    }
                }
                #expect(budget.snapshot.work == 0)
            }
        }
    }

    private func authoredPlaneLiftSheet() throws -> BRepModel {
        let surface = Surface3D.plane(.init(origin: .origin, normal: .unitZ, uDirection: .unitX))
        let charts: [SurfaceParameterCurve] = [
            .constantV(v: 0, uStart: 0, uEnd: 1),
            .constantU(u: 1, vStart: 0, vEnd: 1),
            .constantV(v: 1, uStart: 1, uEnd: 0),
            .constantU(u: 0, vStart: 1, vEnd: 0)]
        let lifts = charts.map { SurfaceLiftCurve3D(surface: surface, parameterCurve: $0) }
        var authoring = OriginalQueryExecution(budget: try OriginalQueryBudget(), limits: try limits())
        let points = try lifts.map {
            try $0.point(atNormalizedFraction: 0, tolerance: .standard, using: &authoring)
        }
        #expect(points == [.origin, .init(x: 1, y: 0, z: 0),
            .init(x: 1, y: 1, z: 0), .init(x: 0, y: 1, z: 0)])
        let vertices = points.map { Vertex(point: $0) }
        var curves: [CurveID: Curve3D] = [:]
        var edges: [EdgeID: Edge] = [:]
        var coedges: [Coedge] = []
        for index in points.indices {
            let next = (index + 1) % points.count
            #expect(try lifts[index].point(atNormalizedFraction: 1,
                tolerance: .standard, using: &authoring) == points[next])
            let curveID = CurveID()
            curves[curveID] = .surfaceLift(lifts[index])
            let edge = Edge(curveID: curveID, startVertexID: vertices[index].id,
                endVertexID: vertices[next].id, trim: .init(startParameter: 0, endParameter: 1))
            edges[edge.id] = edge
            coedges.append(.init(edgeID: edge.id, surfaceParameterCurve: charts[index]))
        }
        let loop = Loop(coedges: coedges)
        let surfaceID = SurfaceID()
        let face = Face(surfaceID: surfaceID, loops: [loop.id])
        let shell = Shell(faceIDs: [face.id])
        let body = Body(topology: .sheet(shellIDs: [shell.id]))
        return BRepModel(geometry: .init(curves: curves, surfaces: [surfaceID: surface]),
            bodies: [body.id: body], shells: [shell.id: shell], faces: [face.id: face],
            loops: [loop.id: loop], edges: edges,
            vertices: Dictionary(uniqueKeysWithValues: vertices.map { ($0.id, $0) }))
    }

    private func sewingRequest(parentCount: Int) -> BRepSewingRequest {
        let points = [Point3D.origin, Point3D(x: 1, y: 0, z: 0),
            Point3D(x: 1, y: 1, z: 0), Point3D(x: 0, y: 1, z: 0)]
        let edges = points.indices.map { index in
            let start = points[index], end = points[(index + 1) % points.count]
            return BRepSewingEdge(stableID: "request:edge:\(index)",
                curve: .line(.init(origin: start, direction: end - start)),
                startParameter: 0, endParameter: 1, startPoint: start, endPoint: end,
                surfaceParameterCurve: .bSpline(.init(degree: 1, knots: [0, 0, 1, 1],
                    controlPoints: [.init(x: start.x, y: start.y), .init(x: end.x, y: end.y)])))
        }
        let patch = BRepSewingFacePatch(stableID: "request:patch",
            surface: .plane(.init(origin: .origin, normal: .unitZ, uDirection: .unitX)),
            orientation: .forward,
            loops: [.init(stableID: "request:loop", role: .outer, edges: edges)])
        let shell = BRepSewingShell(stableID: "request:shell", patches: [patch])
        let source = FeatureID()
        let parents = (0..<parentCount).map { SubshapeID(featureID: source, role: "source-parent", ordinal: $0) }
        return BRepSewingRequest(featureID: FeatureID(),
            bodyTopology: .sheet(shellStableIDs: [shell.stableID]), shells: [shell],
            bodyParentSubshapeIDs: parents)
    }

    private func isOriginalCancellation(_ error: any Error) -> Bool {
        if let scalar = error as? ExactScalarFailure {
            switch scalar {
            case .cancelled: return true
            case .admissionRejected(let cause): return isOriginalCancellation(cause)
            default: return false
            }
        }
        if let failure = error as? OriginalQueryFailure {
            return isOriginalCancellation(failure.originalError)
        }
        return error is CancellationError
    }

    private func sewingEdge(_ curve: Curve3D, reversed: Bool = false,
        using execution: inout OriginalQueryExecution) throws -> BRepSewingEdge {
        let start = reversed ? 1.0 : 0.0, end = reversed ? 0.0 : 1.0
        let startPoint = try curve.point(at: start, tolerance: .standard, using: &execution)
        let endPoint = try curve.point(at: end, tolerance: .standard, using: &execution)
        return try BRepSewingEdge(stableID: "canonical-native-edge", curve: curve,
            startParameter: start, endParameter: end, startPoint: startPoint, endPoint: endPoint,
            surfaceParameterCurve: .constantV(v: 0, uStart: start, uEnd: end), using: &execution)
    }

    private func bridge(startChart: SurfaceParameterCurve = .constantV(v: 0, uStart: 0, uEnd: 1),
        using execution: inout OriginalQueryExecution) throws -> BSplineSurface3D {
        try ConstrainedBridgeSurfaceBuilder().build(start: sourceCurve(),
            end: BSplineCurve3D(degree: 1, knots: [0, 0, 1, 1],
                controlPoints: [.init(x: 0, y: 1, z: 1), .init(x: 1, y: 1, z: 1)]),
            startWall: .plane(.init(origin: .origin, normal: .unitZ, uDirection: .unitX)),
            endWall: .plane(.init(origin: .init(x: 0, y: 1, z: 1), normal: .unitY, uDirection: .unitX)),
            startContinuity: .tangentPlane, endContinuity: .tangentPlane,
            startTension: 1, endTension: 1, width: nil,
            startWallBoundary: startChart,
            endWallBoundary: .constantV(v: 0, uStart: 0, uEnd: 1),
            tolerance: .standard, using: &execution)
    }

    private func construct(_ kind: Construction, using execution: inout OriginalQueryExecution) throws {
        switch kind {
        case .bridge: _ = try bridge(using: &execution)
        case .draft:
            _ = try ExactDraftedProfileBoundaryBuilder(tolerance: .standard, splineReach: 0.25)
                .openCurve(evaluatedCurve(), planeNormal: .unitZ, axis: .unitZ,
                    height: 0.5, tangent: 0.5, using: &execution)
        }
    }

    private func sourceCurve() -> BSplineCurve3D {
        .init(degree: 1, knots: [0, 0, 1, 1], controlPoints: [.origin, .init(x: 1, y: 0, z: 0)])
    }

    private func evaluatedCurve() -> EvaluatedCurve {
        .init(sourceFeatureID: FeatureID(), source: .generatedFeature, kind: .spline,
            points: [.origin, .init(x: 1, y: 0, z: 0)], plane: .xy,
            exactCurve: .bSpline(sourceCurve()), exactParameterDomain: .closed(0, 1))
    }

    private func limits() throws -> OriginalQueryExecutionLimits {
        try .init(maximumValueDepth: 32, maximumCoefficientDepth: 32,
            remainingSourceDepth: 16, maximumSubdivisionDepth: 20, maximumSpans: 4096)
    }

    private func expectResourceRefusal(_ kind: Construction, budget: OriginalQueryBudget,
        resource: ExactResource, axis: OriginalQueryResourceAxis) {
        do {
            var execution = OriginalQueryExecution(budget: budget, limits: try limits())
            try construct(kind, using: &execution)
            Issue.record("Construction escaped its caller resource ceiling.")
        } catch {
            assertResourceCause(error, resource: resource, axis: axis)
        }
    }

    private func assertResourceCause(_ error: any Error, resource: ExactResource,
        axis: OriginalQueryResourceAxis) {
        if let scalar = error as? ExactScalarFailure {
            switch scalar {
            case .resourceLimit(let actual): #expect(actual == resource)
            case .admissionRejected(let cause): assertResourceCause(cause, resource: resource, axis: axis)
            default: Issue.record("Expected a typed resource refusal, received \(scalar).")
            }
        } else if let failure = error as? OriginalQueryFailure {
            #expect(failure.kernelFailure.code == .resourceLimitExceeded)
            #expect(failure.context.resource?.axis == axis)
            assertResourceCause(failure.originalError, resource: resource, axis: axis)
        } else {
            Issue.record("Construction lost its exact resource cause: \(error).")
        }
    }
}
