import Testing
import CADCore
import CADGeometry
import CADIR
import CADTopology
@testable import CADKernel

@Suite("Product attribute local/world resolution")
struct ProductAttributeResolutionTests {
    private func fixture(depth: Int = 2) -> CADDocument {
        let id = FeatureID()
        let feature = FeatureNode(id: id, operation: .primitive(PrimitiveFeature(definition: .box(BoxPrimitive(
            width: .constant(.length(1, unit: .meter)), depth: .constant(.length(2, unit: .meter)),
            height: .constant(.length(3, unit: .meter)))))), outputs: [FeatureOutput(role: .body)])
        var products = [AssemblyProduct(name: "real part"), AssemblyProduct(name: "shared assembly")]
        var formations = products.map { AssemblyProductFormation(productID: $0.id) }
        let leaf = AssemblyDefinition(formationID: formations[0].id, features: [id])
        let edge = AssemblyOccurrence(name: "leaf usage", definitionID: leaf.id)
        let middle = AssemblyDefinition(formationID: formations[1].id, children: [edge])
        var definitions = [leaf, middle]
        var rootDefinition = middle.id
        if depth == 3 {
            let product = AssemblyProduct(name: "outer"), formation = AssemblyProductFormation(productID: product.id)
            products.append(product); formations.append(formation)
            let outer = AssemblyDefinition(formationID: formation.id, children: [AssemblyOccurrence(definitionID: middle.id)])
            definitions.append(outer); rootDefinition = outer.id
        }
        return CADDocument(units: .meters, designGraph: DesignGraph(nodes: [id: feature], order: [id]),
            assembly: DocumentAssembly(products: products, formations: formations, definitions: definitions, roots: [AssemblyOccurrence(name: "first", definitionID: rootDefinition),
                AssemblyOccurrence(name: "second", definitionID: rootDefinition, placement: .translated(by: Vector3D(x: 5,y: 0,z: 0)))]))
    }
    @Test(.timeLimit(.minutes(1)))
    func sharedPartFaceOverrideKeepsPropertyProvenanceAndOccurrenceScope() throws {
        var document = fixture()
        let evaluator = DocumentEvaluator(tolerance: .standard), resolver: any ProductAttributeResolving = ProductAttributeResolver()
        let base = try evaluator.evaluateExact(document), artifact = try #require(base.assembly)
        let part = try #require(document.assembly?.definitions.first { !$0.features.isEmpty })
        let faceID = try #require(artifact.local.subshapes.entries.keys.sorted().first { key in if let topology = artifact.local.subshapes.entries[key], case .face = topology { return true }; return false })
        let reference = try resolver.sourceReference(for: faceID, in: base)
        let partTarget = ProductAttributeTarget(kind: .part, definitionID: part.id)
        let blue = ProductAttributeAssignment(target: partTarget, value: .color(ColorRGBA(r: 0,g: 0,b: 1,a: 1)))
        let path = try #require(artifact.occurrences.first { !$0.features.isEmpty }?.path)
        let face = ProductAttributeTarget(kind: .face, geometry: reference, path: path)
        let red = ProductAttributeAssignment(target: face, value: .color(ColorRGBA(r: 1,g: 0,b: 0,a: 1)), overrides: blue.id)
        let steel = PhysicalMaterialDescriptor(name: "steel", density: PhysicalDensity(kilogramsPerCubicMeter: 7850))
        let material = ProductAttributeAssignment(target: partTarget, value: .material(steel.id))
        document.productAttributes = ProductAttributes(materials: [steel], assignments: [blue, red, material],
            layers: [ProductLayer(name: "part layer", members: [partTarget]), ProductLayer(name: "placed face layer", members: [face])])
        let evaluated = try evaluator.evaluateExact(document)
        let resolved = try resolver.resolve(evaluated, limits: .standard)
        let local = try #require(resolved.localGeometry[face])
        guard case let .face(localFace) = local else { Issue.record("Face target mapped to a different kind."); return }
        let occurrence = try #require(evaluated.assembly?.occurrences.first { $0.path == path })
        let world = try #require(occurrence.features.first?.faces[localFace])
        let selected = try #require(resolved.values[ResolvedProductTarget(topology: .face(world), definitionID: part.id, path: path)])
        #expect(selected.properties[.color]?.value == red.value)
        #expect(selected.properties[.color]?.assignmentChain == [blue.id, red.id])
        #expect(selected.properties[.material]?.value == .material(steel.id))
        #expect(selected.properties[.density] == nil)
        #expect(selected.layers.count == 2)
        #expect(resolved.values.contains { target, value in target.path != path && target.topology != nil && value.properties[.color]?.value == blue.value })
        document.productAttributes.assignments.append(ProductAttributeAssignment(target: partTarget, value: .descriptorDensity(steel.id)))
        let withDensity = try resolver.resolve(evaluator.evaluateExact(document), limits: .standard)
        #expect(withDensity.values[ResolvedProductTarget(topology: .face(world), definitionID: part.id, path: path)]?.properties[.density]?.value == .density(PhysicalDensity(kilogramsPerCubicMeter: 7850)))
    }
    @Test(.timeLimit(.minutes(1)))
    func validThreeComponentAttachmentRefusesWithTypedDepthBudget() throws {
        var document = fixture(depth: 3)
        let evaluator = DocumentEvaluator(tolerance: .standard)
        let base = try evaluator.evaluateExact(document)
        let path = try #require(base.assembly?.occurrences.first { $0.path.components.count == 3 }?.path)
        document.productAttributes = ProductAttributes(assignments: [ProductAttributeAssignment(target: ProductAttributeTarget(kind: .occurrence, path: path), value: .opacity(0.5))])
        let evaluated = try evaluator.evaluateExact(document)
        do {
            _ = try ProductAttributeResolver().resolve(evaluated, limits: ProductAttributeLimits(maximumDepth: 2))
            Issue.record("Three-component occurrence attachment exceeded its ceiling.")
        } catch let error as ProductAttributeError {
            guard case .resourceLimitExceeded = error else { Issue.record("Depth failure was misclassified: \(error)"); return }
        }
    }
    @Test(.timeLimit(.minutes(1)))
    func competingPropertiesAndStaleArtifactsDoNotPublishAResolvedView() throws {
        var document = fixture()
        let part = try #require(document.assembly?.definitions.first { !$0.features.isEmpty })
        let target = ProductAttributeTarget(kind: .part, definitionID: part.id)
        let evaluator = DocumentEvaluator(tolerance: .standard)
        let old = try evaluator.evaluateExact(document)
        document.productAttributes = ProductAttributes(assignments: [ProductAttributeAssignment(target: target, value: .opacity(0.2)), ProductAttributeAssignment(target: target, value: .opacity(0.8))])
        #expect(throws: ProductAttributeError.self) { _ = try evaluator.evaluateExact(document) }
        #expect(throws: ProductAttributeError.self) { _ = try ProductAttributeResolver().resolve(old, limits: ProductAttributeLimits(maximumWork: 1)) }
        document.productAttributes.assignments.removeLast()
        let stale = EvaluatedDocument(document: document, parameters: old.parameters, brep: old.brep, meshes: old.meshes,
            caches: old.caches, subshapes: old.subshapes, lineage: old.lineage, configuration: old.configuration, assembly: old.assembly)
        #expect(throws: ProductAttributeError.self) { _ = try ProductAttributeResolver().resolve(stale) }
    }
    @Test(.timeLimit(.minutes(1)))
    func producerExactReceiptAdmitsCachelessOutputAndRejectsUntrustedOrChangedSource() throws {
        let document = fixture(), evaluator = DocumentEvaluator(tolerance: .standard)
        let exact = try evaluator.evaluateExact(document)
        #expect(exact.caches.brep == nil && exact.meshes.isEmpty)
        _ = try ProductAttributeResolver().resolve(exact)
        let constructed = EvaluatedDocument(document: document, parameters: exact.parameters, brep: exact.brep,
            meshes: exact.meshes, caches: exact.caches, subshapes: exact.subshapes, lineage: exact.lineage,
            configuration: exact.configuration, assembly: exact.assembly)
        #expect(throws: ProductAttributeError.self) { _ = try ProductAttributeResolver().resolve(constructed) }
        var changed = document
        let part = try #require(changed.assembly?.definitions.first { !$0.features.isEmpty })
        changed.productAttributes = ProductAttributes(assignments: [ProductAttributeAssignment(target:
            ProductAttributeTarget(kind: .part, definitionID: part.id), value: .opacity(0.5))])
        var stale = EvaluatedDocument(document: changed, parameters: exact.parameters, brep: exact.brep,
            meshes: exact.meshes, caches: exact.caches, subshapes: exact.subshapes, lineage: exact.lineage,
            configuration: exact.configuration, assembly: exact.assembly)
        // Test-only retained receipt copying proves that source equality is checked even when
        // a stale artifact accidentally carries an otherwise genuine producer receipt.
        stale.validatedSourceReceipt = exact.validatedSourceReceipt; stale.validatedBRep = exact.validatedBRep
        #expect(throws: ProductAttributeError.self) { _ = try ProductAttributeResolver().resolve(stale) }
        var described = document
        described.assembly?.products[0].description = "Changed product authority"
        var staleDescription = EvaluatedDocument(document: described, parameters: exact.parameters, brep: exact.brep,
            meshes: exact.meshes, caches: exact.caches, subshapes: exact.subshapes, lineage: exact.lineage,
            configuration: exact.configuration, assembly: exact.assembly)
        staleDescription.validatedSourceReceipt = exact.validatedSourceReceipt
        staleDescription.validatedBRep = exact.validatedBRep
        #expect(throws: ProductAttributeError.self) { _ = try ProductAttributeResolver().resolve(staleDescription) }
        _ = try ProductAttributeResolver().resolve(evaluator.evaluateExact(described))
        let materialized = try evaluator.evaluate(document)
        #expect(materialized.caches.brep != nil)
        _ = try ProductAttributeResolver().resolve(materialized)
    }
    @Test(.timeLimit(.minutes(1)))
    func sharedProductAndFormationEditsUpdateBaselinesCachesAndExactProducerReceipt() throws {
        var document = fixture()
        let formation = try #require(document.assembly?.formations.first)
        let product = try #require(document.assembly?.products.first)
        document.assembly?.definitions[1].formationID = formation.id
        document.assembly?.formations = [formation]; document.assembly?.products = [product]
        let evaluator = DocumentEvaluator(tolerance: .standard), resolver = ProductAttributeResolver()
        let original = try evaluator.evaluate(document), exact = try evaluator.evaluateExact(document)
        for change in 0..<4 {
            var changed = document
            switch change {
            case 0: changed.assembly?.products[0].name = "shared edited name"
            case 1: changed.assembly?.products[0].identifier = "new business identifier"
            case 2: changed.assembly?.formations[0].versionIdentifier = "another version"
            default: changed.assembly?.formations[0].specifiedSource = .bought
            }
            let reused = try evaluator.evaluate(changed, reusing: original)
            #expect(reused.evaluationMetrics.reusedFeatureCount == 1 && reused.evaluationMetrics.rebuiltFeatureCount == 0)
            #expect(reused.brep == original.brep && reused.assembly?.local == original.assembly?.local)
            let reusedFingerprint = try reused.caches.brep?.sourceFingerprint
            let originalFingerprint = try original.caches.brep?.sourceFingerprint
            #expect(reusedFingerprint != originalFingerprint)
            let view = try resolver.resolve(reused)
            for definition in changed.assembly?.definitions ?? [] {
                #expect(view.values[ResolvedProductTarget(definitionID: definition.id)]?.sourceName == changed.assembly?.products[0].name)
            }
            var stale = EvaluatedDocument(document: changed, parameters: exact.parameters, brep: exact.brep,
                meshes: exact.meshes, caches: exact.caches, subshapes: exact.subshapes, lineage: exact.lineage,
                configuration: exact.configuration, assembly: exact.assembly)
            stale.validatedSourceReceipt = exact.validatedSourceReceipt; stale.validatedBRep = exact.validatedBRep
            #expect(throws: ProductAttributeError.self) { _ = try resolver.resolve(stale) }
            _ = try resolver.resolve(evaluator.evaluateExact(changed))
        }
    }
    @Test(.timeLimit(.minutes(1)))
    func canonicallyEquivalentUnicodeEditsInvalidateExactProducerSourceReceipt() throws {
        let composed = "é", decomposed = "e\u{301}"
        var document = fixture()
        document.assembly?.products[0].identifier = composed
        document.assembly?.products[0].name = composed
        document.assembly?.products[0].description = composed
        document.assembly?.formations[0].versionIdentifier = composed
        document.assembly?.formations[0].description = composed
        document.assembly?.definitions[0].identifier = composed
        document.assembly?.definitions[0].definitionDescription = composed
        let evaluator = DocumentEvaluator(tolerance: .standard), resolver = ProductAttributeResolver()
        let exact = try evaluator.evaluateExact(document)
        _ = try resolver.resolve(exact)
        for field in 0..<7 {
            var changed = document
            switch field {
            case 0: changed.assembly?.products[0].identifier = decomposed
            case 1: changed.assembly?.products[0].name = decomposed
            case 2: changed.assembly?.products[0].description = decomposed
            case 3: changed.assembly?.formations[0].versionIdentifier = decomposed
            case 4: changed.assembly?.formations[0].description = decomposed
            case 5: changed.assembly?.definitions[0].identifier = decomposed
            default: changed.assembly?.definitions[0].definitionDescription = decomposed
            }
            var stale = EvaluatedDocument(document: changed, parameters: exact.parameters, brep: exact.brep,
                meshes: exact.meshes, caches: exact.caches, subshapes: exact.subshapes, lineage: exact.lineage,
                configuration: exact.configuration, assembly: exact.assembly)
            stale.validatedSourceReceipt = exact.validatedSourceReceipt; stale.validatedBRep = exact.validatedBRep
            #expect(throws: ProductAttributeError.inconsistentArtifact("Missing or stale producer source/exact B-rep association.")) {
                _ = try resolver.resolve(stale)
            }
            let fresh = try evaluator.evaluateExact(changed)
            #expect(fresh.brep == exact.brep)
            _ = try resolver.resolve(fresh)
        }
    }
    @Test(.timeLimit(.minutes(1)))
    func cancellationPropagatesWithoutPartialAttributes() async throws {
        let evaluated = try DocumentEvaluator(tolerance: .standard).evaluateExact(fixture())
        let (stream, continuation) = AsyncStream<Void>.makeStream()
        let task = Task {
            for await _ in stream { break }
            return try ProductAttributeResolver().resolve(evaluated)
        }
        task.cancel(); continuation.yield(()); continuation.finish()
        do { _ = try await task.value; Issue.record("Cancelled attribute resolution returned a view.") }
        catch is CancellationError {}
    }
}
