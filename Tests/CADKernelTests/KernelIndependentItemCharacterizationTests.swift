import Testing
import CADCore
import CADGeometry
import CADIR
import CADTopology
@testable import CADKernel

@Suite("Independent item metadata actual geometry and receipt")
struct KernelIndependentItemCharacterizationTests {
    private func fixture() throws -> CADDocument {
        let id = FeatureID()
        let node = FeatureNode(id: id, operation: .primitive(PrimitiveFeature(definition: .box(BoxPrimitive(
            width: .constant(.length(1, unit: .meter)), depth: .constant(.length(2, unit: .meter)),
            height: .constant(.length(3, unit: .meter)))))), outputs: [FeatureOutput(role: .body)])
        var document = CADDocument(units: .meters, designGraph: DesignGraph(nodes: [id: node], order: [id]))
        let initial = try DocumentEvaluator(tolerance: .standard).evaluateExact(document)
        let resolver = ProductAttributeResolver()
        for kind in [ProductAttributeTarget.Kind.body, .face] {
            let subshape = try #require(initial.subshapes.entries.first {
                switch ($0.value, kind) { case (.body, .body), (.face, .face): return true; default: return false }
            }?.key)
            let target = ProductAttributeTarget(kind: kind, geometry: try resolver.sourceReference(for: subshape, in: initial))
            document.productAttributes.itemCharacterizations.append(ProductItemCharacterization(target: target,
                name: kind == .body ? "body inspection" : "\u{e9}", description: kind == .body ? nil : ""))
        }
        return document
    }

    @Test(.timeLimit(.minutes(1)))
    func metadataOnlyGeometryIsResolvedWithoutEffectiveValuesAndUnicodeChangeRejectsGenuineStaleReceipt() throws {
        var document = try fixture()
        let evaluator = DocumentEvaluator(tolerance: .standard), resolver = ProductAttributeResolver()
        let old = try evaluator.evaluateExact(document), before = try resolver.resolve(old)
        #expect(before.localGeometry.count == 2 && before.values.count == 7)
        #expect(before.values.values.allSatisfy { $0.properties.isEmpty && $0.layers.isEmpty })
        #expect(document.productAttributes.materials.isEmpty && document.productAttributes.assignments.isEmpty && document.productAttributes.layers.isEmpty)
        let fingerprint = try document.sourceFingerprint(tolerance: .standard)
        let index = try #require(document.productAttributes.itemCharacterizations.firstIndex { $0.target.kind == .face })
        let record = document.productAttributes.itemCharacterizations[index]
        document.productAttributes.itemCharacterizations[index] = ProductItemCharacterization(target: record.target,
            name: "e\u{301}", description: record.description)
        #expect(try document.sourceFingerprint(tolerance: .standard) != fingerprint)
        var stale = EvaluatedDocument(document: document, parameters: old.parameters, brep: old.brep,
            meshes: old.meshes, curves: old.curves, caches: old.caches, subshapes: old.subshapes, lineage: old.lineage,
            configuration: old.configuration, assembly: old.assembly, evaluationMetrics: old.evaluationMetrics)
        stale.validatedSourceReceipt = try #require(old.validatedSourceReceipt)
        stale.validatedBRep = try #require(old.validatedBRep)
        #expect(throws: ProductAttributeError.inconsistentArtifact("Missing or stale producer source/exact B-rep association.")) {
            _ = try resolver.resolve(stale)
        }
        let fresh = try evaluator.evaluateExact(document), after = try resolver.resolve(fresh)
        #expect(fresh.brep == old.brep && fresh.subshapes == old.subshapes && fresh.lineage == old.lineage)
        #expect(fresh.caches.brep == nil && old.caches.brep == nil)
        #expect(after.localGeometry == before.localGeometry && after.values == before.values)
        for metadata in document.productAttributes.itemCharacterizations {
            let geometry = try #require(metadata.target.geometry)
            #expect(try resolver.sourceReference(for: geometry.subshapeID, in: fresh) == geometry)
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func freshReceiptCannotAuthorizeSameKindForeignGeometrySignature() throws {
        var document = try fixture()
        let metadata = try #require(document.productAttributes.itemCharacterizations.first { $0.target.kind == .face })
        let reference = try #require(metadata.target.geometry)
        guard case let .face(original) = reference.geometrySignature else { Issue.record("Fixture requires actual face geometry."); return }
        let foreign = FaceGeometrySignature(surface: .plane(Plane3D(origin: Point3D(x: 100, y: 0, z: 0),
            normal: Vector3D(x: 0, y: 0, z: 1))), orientation: original.orientation, loops: original.loops)
        let target = ProductAttributeTarget(kind: .face, geometry: StableSubshapeReference(
            subshapeID: reference.subshapeID, geometrySignature: .face(foreign)))
        document.productAttributes.itemCharacterizations = [ProductItemCharacterization(target: target, name: "foreign", description: nil)]
        let exact = try DocumentEvaluator(tolerance: .standard).evaluateExact(document)
        #expect(exact.validatedSourceReceipt?.document == document && exact.caches.brep == nil)
        #expect(exact.subshapes.entries[reference.subshapeID] != nil)
        #expect(throws: ProductAttributeError.inconsistentArtifact("Item characterization does not match current local geometry.")) {
            _ = try ProductAttributeResolver().resolve(exact)
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func actualSplineCoefficientsConsumeWorkEvenWithIdenticalTopologyAndOneMetadataRecord() throws {
        func source(spans: Int) throws -> EvaluatedDocument {
            let knots = [0.0, 0.0] + (1..<spans).map { Double($0) / Double(spans) } + [1.0, 1.0]
            let points = [0.0, 1.0].map { y in
                (0...spans).map { index in
                    Point3D(x: Double(index) / Double(spans), y: y, z: 0)
                }
            }
            let surface = BSplineSurface3D(uDegree: 1, vDegree: 1, uKnots: knots,
                vKnots: [0, 0, 1, 1], controlPoints: points)
            let id = FeatureID(), node = FeatureNode(id: id,
                operation: .bSplineSurface(BSplineSurfaceFeature(surface: surface)), outputs: [FeatureOutput(role: .sheet)])
            var document = CADDocument(units: .meters, designGraph: DesignGraph(nodes: [id: node], order: [id]))
            let evaluator = DocumentEvaluator(tolerance: .standard)
            let initial = try evaluator.evaluateExact(document)
            let face = try #require(initial.subshapes.entries.first { if case .face = $0.value { return true }; return false }?.key)
            let reference = try ProductAttributeResolver().sourceReference(for: face, in: initial)
            if case let .face(signature) = reference.geometrySignature, case let .bSpline(actual) = signature.surface {
                #expect(actual.uControlPointCount == spans + 1 && actual.vControlPointCount == 2 && actual.uKnots.count == spans + 3)
            } else { Issue.record("The public native source must retain its original B-spline coefficients.") }
            let target = ProductAttributeTarget(kind: .face, geometry: reference)
            document.productAttributes.itemCharacterizations = [ProductItemCharacterization(target: target, name: "region", description: nil)]
            return try evaluator.evaluateExact(document)
        }
        let small = try source(spans: 1), large = try source(spans: 32), resolver = ProductAttributeResolver()
        #expect(small.brep.faces.count == large.brep.faces.count && small.brep.loops.count == large.brep.loops.count)
        #expect(small.brep.edges.count == large.brep.edges.count && small.brep.vertices.count == large.brep.vertices.count)
        #expect(small.document.productAttributes.itemCharacterizations.count == 1 && large.document.productAttributes.itemCharacterizations.count == 1)
        let allowance = try resolver.resolve(small).consumedWork
        _ = try resolver.resolve(small, limits: ProductAttributeLimits(maximumWork: allowance))
        #expect(throws: ProductAttributeError.resourceLimitExceeded("Cumulative product attribute budget.")) {
            _ = try resolver.resolve(large, limits: ProductAttributeLimits(maximumWork: allowance))
        }
        #expect(try resolver.resolve(large).consumedWork > allowance)
    }

    @Test(.timeLimit(.minutes(1)))
    func metadataActualTraversalHonorsCallerBudgetsAndCancellation() async throws {
        let document = try fixture(), exact = try DocumentEvaluator(tolerance: .standard).evaluateExact(document)
        for limits in [ProductAttributeLimits(maximumWork: 1), ProductAttributeLimits(maximumTargets: 1), ProductAttributeLimits(maximumTextBytes: 1)] {
            do { _ = try ProductAttributeResolver().resolve(exact, limits: limits); Issue.record("Independent metadata escaped caller allowance.") }
            catch let error as ProductAttributeError { guard case .resourceLimitExceeded = error else { Issue.record("Unexpected metadata resource classification: \(error)"); continue } }
        }
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try ProductAttributeResolver().resolve(exact)
        }
        do { _ = try await task.value; Issue.record("Cancelled independent metadata resolution succeeded.") }
        catch is CancellationError {}
    }
}
