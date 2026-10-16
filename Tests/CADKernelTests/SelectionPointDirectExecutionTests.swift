import CADCore
import CADGeometry
import CADIR
import CADModeling
import CADTopology
import Synchronization
import Testing
@testable import CADKernel

@Suite("Direct selection point execution", .timeLimit(.minutes(1)))
struct SelectionPointDirectExecutionTests {
    private struct Fixture {
        let document: EvaluatedDocument
        let control: SelectionReference
        let knot: SelectionReference
        let sketch: SelectionReference
        let curve: CurveOutputReference
    }

    private func fixture(compoundSketch: Bool = false) -> Fixture {
        let curveID = FeatureID()
        let sketchID = FeatureID()
        let pointID = SketchEntityID()
        let origin = Point3D.origin
        let end = Point3D(x: 4, y: 0, z: 0)
        let spline = BSplineCurve3D(degree: 1, knots: [0, 0, 1, 1],
            controlPoints: [origin, end], weights: [1, 1])
        let evaluated = EvaluatedCurve(sourceFeatureID: curveID, source: .generatedFeature,
            kind: .spline, points: [origin, end], exactCurve: .bSpline(spline),
            exactPointParameters: [0, 1])
        let x: CADExpression = compoundSketch
            ? .add(.constant(.length(1, unit: .meter)),
                .multiply(.constant(.scalar(2)), .constant(.length(1, unit: .meter))))
            : .constant(.length(3, unit: .meter))
        let y: CADExpression = compoundSketch
            ? .hypot(.constant(.length(0, unit: .meter)), .constant(.length(4, unit: .meter)))
            : .constant(.length(4, unit: .meter))
        let sketch = Sketch(plane: .zx, entities: [pointID: .point(SketchPoint(x: x, y: y))])
        let source = CADDocument(units: .meters, designGraph: DesignGraph(nodes: [
            sketchID: FeatureNode(id: sketchID, operation: .sketch(sketch),
                outputs: [FeatureOutput(role: .curve)])
        ], order: [sketchID]))
        let document = EvaluatedDocument(document: source, parameters: ResolvedParameterTable(),
            brep: BRepModel(), meshes: PersistentMap(), curves: [curveID: [evaluated]],
            caches: DocumentCaches(), configuration: .init(tolerance: .standard,
                tessellationOptions: .standard))
        let curve = CurveOutputReference(featureID: curveID)
        return Fixture(document: document,
            control: .curve(.controlPoint(.init(curve: curve, controlPointIndex: 1))),
            knot: .curve(.knot(.init(curve: curve, knotIndex: 0))),
            sketch: .sketchPoint(.init(featureID: sketchID, entityID: pointID)), curve: curve)
    }

    private func surfaceFixture() throws -> (EvaluatedDocument, SurfaceControlPointReference) {
        let surfaceID = SurfaceID()
        let faceID = FaceID()
        let name = SubshapeID(featureID: FeatureID(), role: "selection.control.face", ordinal: 0)
        let expected = Point3D(x: 4, y: 3, z: 0)
        let surface = Surface3D.bSpline(BSplineSurface3D(uDegree: 1, vDegree: 1,
            uKnots: [0, 0, 1, 1], vKnots: [0, 0, 1, 1],
            controlPoints: [[.origin, Point3D(x: 4, y: 0, z: 0)],
                [Point3D(x: 0, y: 3, z: 0), expected]], weights: [[1, 1], [1, 1]]))
        let model = BRepModel(geometry: GeometryStore(surfaces: [surfaceID: surface]),
            faces: [faceID: Face(id: faceID, surfaceID: surfaceID, loops: [])])
        let document = EvaluatedDocument(document: CADDocument(units: .meters),
            parameters: ResolvedParameterTable(), brep: model, meshes: PersistentMap(),
            caches: DocumentCaches(), subshapes: SubshapeIndex([name: .face(faceID)]),
            configuration: .init(tolerance: .standard, tessellationOptions: .standard))
        let reference = SurfaceControlPointReference(surface: .init(
            subshape: try document.stableSubshapeReference(for: name)), uIndex: 1, vIndex: 1)
        return (document, reference)
    }

    private func execution(budget: OriginalQueryBudget) throws -> OriginalQueryExecution {
        OriginalQueryExecution(budget: budget,
            limits: try .init(maximumValueDepth: 32, maximumCoefficientDepth: 32,
                remainingSourceDepth: 16, maximumTransportDepth: 16,
                maximumSubdivisionDepth: 32))
    }

    private func expectWorkRefusal(_ error: any Error, context: OriginalQueryFailureContext,
        limit: Int) {
        let published = OriginalQueryFailure.published(error, context: context, tolerance: .standard)
        guard let failure = published as? OriginalQueryFailure else {
            Issue.record("The direct selector must retain its concrete original work failure.")
            return
        }
        #expect(failure.kernelFailure.code == .resourceLimitExceeded)
        #expect(failure.context.resource?.axis == .work)
        #expect(failure.context.resource?.limit == .known(limit))
    }

    @Test func directPointPreservesControlKnotAndSketchValues() throws {
        let f = fixture()
        let evaluator = SelectionMeasurementEvaluator(tolerance: .standard)
        let selectors = [f.control, f.knot, f.sketch]
        let expected = [Point3D(x: 4, y: 0, z: 0), .origin, Point3D(x: 4, y: 0, z: 3)]
        for index in selectors.indices {
            let ordinary = try evaluator.point(for: selectors[index], in: f.document)
            let budget = try OriginalQueryBudget()
            var direct = try execution(budget: budget)
            let value = try evaluator.point(for: selectors[index], in: f.document, using: &direct)
            #expect(value == ordinary)
            #expect(value.point == expected[index])
            #expect(value.selection == selectors[index])
            #expect(budget.snapshot.work > 0)
            #expect(budget.snapshot.work == direct.localWork)
        }
        let budget = try OriginalQueryBudget()
        var direct = try execution(budget: budget)
        let handle = try CurveQueryEvaluator(tolerance: .standard).controlPoint(
            .init(curve: f.curve, controlPointIndex: 1), in: f.document, using: &direct)
        #expect(handle == expected[0])
        #expect(budget.snapshot.work > 0)
    }

    @Test func eachSelectorHonorsExactWorkAndSelectedZeroLimits() throws {
        let f = fixture()
        let evaluator = SelectionMeasurementEvaluator(tolerance: .standard)
        for selection in [f.control, f.knot, f.sketch] {
            let baseline = try OriginalQueryBudget()
            var baselineExecution = try execution(budget: baseline)
            let expected = try evaluator.point(for: selection, in: f.document, using: &baselineExecution)
            let required = baseline.snapshot.work
            #expect(required > 0)
            let exact = try OriginalQueryBudget(workLimit: required)
            var exactExecution = try execution(budget: exact)
            let value = try evaluator.point(for: selection, in: f.document, using: &exactExecution)
            #expect(value == expected)
            #expect(exact.snapshot.work == required)
            let short = try OriginalQueryBudget(workLimit: required - 1)
            var shortExecution = try execution(budget: short)
            do {
                _ = try evaluator.point(for: selection, in: f.document, using: &shortExecution)
                Issue.record("N-1 work must not publish a selection point.")
            } catch {
                expectWorkRefusal(error, context: shortExecution.context, limit: required - 1)
            }
            #expect(short.snapshot.work <= required - 1)
            let parent = try OriginalQueryBudget()
            var selected = try execution(budget: parent)
            let contribution = try selected.makeContributionHandle(workLimit: 0)
            try selected.withContributionScope(contribution) { execution in
                let before = parent.snapshot.work
                do {
                    _ = try evaluator.point(for: selection, in: f.document, using: &execution)
                    Issue.record("A selector must not escape a selected zero-work ceiling.")
                } catch {
                    expectWorkRefusal(error, context: execution.context, limit: 0)
                }
                #expect(parent.snapshot.work == before)
                #expect(contribution.snapshot.work == 0)
            }
        }
    }

    @Test func admittedDistanceRetainsControlAndSketchFallbackSemantics() throws {
        let f = fixture()
        let evaluator = SelectionMeasurementEvaluator(tolerance: .standard)
        let options = BRepDistanceOptions(absoluteAccuracy: ModelingTolerance.standard.distance)
        let ordinary = try evaluator.distance(from: f.control, to: f.sketch,
            in: f.document, options: options)
        let budget = try OriginalQueryBudget()
        var direct = try execution(budget: budget)
        let value = try evaluator.distance(from: f.control, to: f.sketch,
            in: f.document, options: options, using: &direct)
        #expect(value.first.point == Point3D(x: 4, y: 0, z: 0))
        #expect(value.second.point == Point3D(x: 4, y: 0, z: 3))
        #expect(value.distance == ordinary.distance)
        #expect(value.minimumBounds?.contains(3) == true)
        #expect(budget.snapshot.work == direct.localWork)
        #expect(budget.snapshot.work > 0)
    }

    @Test func surfaceConstructionControlUsesItsOriginalSourceAndCaller() throws {
        let (document, reference) = try surfaceFixture()
        let expected = Point3D(x: 4, y: 3, z: 0)
        let selector = SelectionReference.surface(.controlPoint(reference))
        let evaluator = SelectionMeasurementEvaluator(tolerance: .standard)
        let ordinary = try evaluator.point(for: selector, in: document)
        let budget = try OriginalQueryBudget()
        var direct = try execution(budget: budget)
        let value = try evaluator.point(for: selector, in: document, using: &direct)
        #expect(value == ordinary)
        #expect(value.point == expected)
        #expect(budget.snapshot.work == direct.localWork)
        #expect(budget.snapshot.work > 0)
        let helperBudget = try OriginalQueryBudget()
        var helperExecution = try execution(budget: helperBudget)
        let helperValue = try SurfaceQueryEvaluator(tolerance: .standard).controlPoint(
            reference, in: document, using: &helperExecution)
        #expect(helperValue == expected)
        #expect(helperBudget.snapshot.work > 0)
        let limit = budget.snapshot.work - 1
        let short = try OriginalQueryBudget(workLimit: limit)
        var shortExecution = try execution(budget: short)
        do {
            _ = try evaluator.point(for: selector, in: document, using: &shortExecution)
            Issue.record("Surface construction control escaped its measured caller work ceiling.")
        } catch {
            expectWorkRefusal(error, context: shortExecution.context, limit: limit)
        }
        #expect(short.snapshot.work <= limit)
    }

    @Test func surfaceSpanPointRetainsItsStationAndExactCallerCeiling() throws {
        let (document, reference) = try surfaceFixture()
        let selector = SelectionReference.surface(.span(.init(surface: reference.surface,
            direction: .u, spanIndex: 0)))
        let evaluator = SelectionMeasurementEvaluator(tolerance: .standard)
        let ordinary = try evaluator.point(for: selector, in: document)
        let budget = try OriginalQueryBudget()
        var direct = try execution(budget: budget)
        let expected = try evaluator.point(for: selector, in: document, using: &direct)
        #expect(expected == ordinary)
        #expect(expected.point == Point3D(x: 2, y: 1.5, z: 0))
        #expect(expected.normal?.z == 1)
        let required = budget.snapshot.work
        #expect(required > 0)
        #expect(required == direct.localWork)
        let exact = try OriginalQueryBudget(workLimit: required)
        var exactExecution = try execution(budget: exact)
        let value = try evaluator.point(for: selector, in: document, using: &exactExecution)
        #expect(value == expected)
        #expect(exact.snapshot.work == required)
        let short = try OriginalQueryBudget(workLimit: required - 1)
        var shortExecution = try execution(budget: short)
        do {
            _ = try evaluator.point(for: selector, in: document, using: &shortExecution)
            Issue.record("Surface span point escaped its measured caller ceiling.")
        } catch {
            expectWorkRefusal(error, context: shortExecution.context, limit: required - 1)
        }
        #expect(short.snapshot.work <= required - 1)
        let cancelled = try OriginalQueryBudget(checkpoint: { throw CancellationError() })
        var cancelledExecution = try execution(budget: cancelled)
        do {
            _ = try evaluator.point(for: selector, in: document, using: &cancelledExecution)
            Issue.record("Cancelled surface span point query published output.")
        } catch {
            let published = OriginalQueryFailure.published(error,
                context: cancelledExecution.context, tolerance: .standard)
            #expect(published is CancellationError)
        }
        #expect(cancelled.snapshot.work == 0)
    }

    @Test func compoundSketchExpressionsConsumeTheSameCallerAtTheirActualNodes() throws {
        let simple = fixture()
        let compound = fixture(compoundSketch: true)
        let evaluator = SelectionMeasurementEvaluator(tolerance: .standard)
        let simpleBudget = try OriginalQueryBudget()
        var simpleExecution = try execution(budget: simpleBudget)
        let simplePoint = try evaluator.point(for: simple.sketch, in: simple.document,
            using: &simpleExecution)
        let budget = try OriginalQueryBudget()
        var direct = try execution(budget: budget)
        let value = try evaluator.point(for: compound.sketch, in: compound.document, using: &direct)
        #expect(value.point == simplePoint.point)
        #expect(value.point == Point3D(x: 4, y: 0, z: 3))
        #expect(budget.snapshot.work == direct.localWork)
        #expect(budget.snapshot.work > simpleBudget.snapshot.work)
        let limit = budget.snapshot.work - 1
        let short = try OriginalQueryBudget(workLimit: limit)
        var shortExecution = try execution(budget: short)
        do {
            _ = try evaluator.point(for: compound.sketch, in: compound.document, using: &shortExecution)
            Issue.record("Compound sketch evaluation escaped the caller's measured work ceiling.")
        } catch {
            expectWorkRefusal(error, context: shortExecution.context, limit: limit)
        }
        #expect(short.snapshot.work <= limit)
    }

    @Test func pointCancellationBeforeEntryAndFinalPublicationReturnsNoPoint() throws {
        let f = fixture()
        let evaluator = SelectionMeasurementEvaluator(tolerance: .standard)
        let baselineCount = Mutex(0)
        let baseline = try OriginalQueryBudget(checkpoint: {
            baselineCount.withLock { $0 += 1 }
        })
        var baselineExecution = try execution(budget: baseline)
        _ = try evaluator.point(for: f.control, in: f.document, using: &baselineExecution)
        let terminal = baselineCount.withLock { $0 }
        #expect(terminal > 0)
        for stop in [1, terminal] {
            let count = Mutex(0)
            let budget = try OriginalQueryBudget(checkpoint: {
                let current = count.withLock { state in state += 1; return state }
                if current == stop { throw CancellationError() }
            })
            var direct = try execution(budget: budget)
            do {
                _ = try evaluator.point(for: f.control, in: f.document, using: &direct)
                Issue.record("Cancellation must prevent selection point publication.")
            } catch {
                let published = OriginalQueryFailure.published(error,
                    context: direct.context, tolerance: .standard)
                #expect(published is CancellationError)
            }
            #expect(count.withLock { $0 } == stop)
            #expect(budget.snapshot.work <= baseline.snapshot.work)
            if stop == 1 {
                #expect(budget.snapshot.work == 0)
                #expect(direct.context.stage == .source)
            } else {
                #expect(direct.context.stage == .publication)
            }
        }
    }
}
