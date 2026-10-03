import Foundation
import Testing
import CADCore
import CADGeometry
import CADIR
import CADKernel
import CADTopology
@testable import CADExchange

@Suite("STEP product attribute public interchange")
struct STEPAttributesExchangeTests {
    @Test(.timeLimit(.minutes(1)))
    func definitionQualifiedGeometryRefusesSTEPProjectionAndPreservesURLDestination() throws {
        let featureID = FeatureID()
        let feature = FeatureNode(id: featureID, operation: .primitive(PrimitiveFeature(definition: .box(BoxPrimitive(
            width: .constant(.length(1, unit: .meter)), depth: .constant(.length(2, unit: .meter)),
            height: .constant(.length(3, unit: .meter)))))), outputs: [FeatureOutput(role: .body)])
        let product = AssemblyProduct(name: "qualified source"), formation = AssemblyProductFormation(productID: product.id)
        let selected = AssemblyDefinition(formationID: formation.id, features: [featureID])
        let other = AssemblyDefinition(formationID: formation.id, features: [featureID])
        var source = CADDocument(units: .meters, designGraph: DesignGraph(nodes: [featureID: feature], order: [featureID]),
            assembly: DocumentAssembly(products: [product], formations: [formation], definitions: [selected, other], roots: [
                AssemblyOccurrence(definitionID: selected.id), AssemblyOccurrence(definitionID: other.id)]))
        let evaluator = DocumentEvaluator(tolerance: .standard), resolver = ProductAttributeResolver()
        let base = try evaluator.evaluateExact(source), local = try #require(base.assembly?.local)
        let bodyKey = try #require(local.subshapes.entries.keys.sorted().first { key in
            if let topology = local.subshapes.entries[key], case .body = topology { return true }; return false
        })
        let faceKey = try #require(local.subshapes.entries.keys.sorted().first { key in
            if let topology = local.subshapes.entries[key], case .face = topology { return true }; return false
        })
        let body = ProductAttributeTarget(kind: .body, geometry: try resolver.sourceReference(for: bodyKey, in: base), definitionID: selected.id)
        let face = ProductAttributeTarget(kind: .face, geometry: try resolver.sourceReference(for: faceKey, in: base), definitionID: selected.id)
        let variants = [ProductAttributes(assignments: [ProductAttributeAssignment(target: body, value: .name("selected body"))]),
            ProductAttributes(assignments: [ProductAttributeAssignment(target: face, value: .color(ColorRGBA(r: 1, g: 0, b: 0, a: 1)))]),
            ProductAttributes(layers: [ProductLayer(name: "selected faces", members: [face])])]
        let failure = ProductAttributeError.unsupportedSemantics("Definition-qualified geometry requires scope-preserving STEP transport.")
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { do { try FileManager.default.removeItem(at: directory) } catch { Issue.record("Unable to remove STEP scope fixture directory: \(error)") } }
        let url = directory.appendingPathComponent("scope.step"), original = Data("existing complete STEP destination".utf8)
        try original.write(to: url)
        for attributes in variants {
            source.productAttributes = attributes
            let native = DataByteSink(), store = NativePackageStore(tolerance: .standard)
            try store.writePackage(for: source, to: native)
            let restored = try store.loadDocument(from: native.bytes)
            #expect(restored == source && restored.schemaVersion == SchemaVersion(major: 0, minor: 8, patch: 0))
            let evaluated = try evaluator.evaluate(restored), resolved = try resolver.resolve(evaluated)
            let writer: any STEPAttributesWriting = STEPAttributesWriter()
            #expect(resolved.consumedWork > 1)
            let lowCeiling = ExchangeResourceLimits(maximumIterations: 1)
            let exhaustedByResolution = ExchangeResourceLimits(maximumIterations: resolved.consumedWork)
            for ceiling in [lowCeiling, exhaustedByResolution] {
                #expect(throws: ProductAttributeError.resourceLimitExceeded("Cumulative product attribute budget.")) {
                    _ = try writer.geometryNames(for: evaluated, resolved: resolved, limits: ceiling)
                }
                #expect(throws: ProductAttributeError.resourceLimitExceeded("Cumulative product attribute budget.")) {
                    _ = try writer.records(for: evaluated, resolved: resolved, transfer: STEPAttributeWriteTransfer(), startingAt: 1, limits: ceiling)
                }
            }
            let boundedSink = DataByteSink()
            #expect(throws: ProductAttributeError.resourceLimitExceeded("Cumulative product attribute budget.")) {
                try STEPExchange(tolerance: .standard, resourceLimits: exhaustedByResolution).write(evaluated, to: boundedSink)
            }
            #expect(boundedSink.bytes.isEmpty)
            if attributes.assignments.isEmpty {
                // Visiting the layer consumes one work unit; its scoped member requires a second.
                let memberCeiling = ExchangeResourceLimits(maximumIterations: resolved.consumedWork + 1)
                #expect(throws: ProductAttributeError.resourceLimitExceeded("Cumulative product attribute budget.")) {
                    _ = try writer.geometryNames(for: evaluated, resolved: resolved, limits: memberCeiling)
                }
                #expect(throws: ProductAttributeError.resourceLimitExceeded("Cumulative product attribute budget.")) {
                    _ = try writer.records(for: evaluated, resolved: resolved, transfer: STEPAttributeWriteTransfer(), startingAt: 1, limits: memberCeiling)
                }
            }
            #expect(throws: failure) { _ = try writer.geometryNames(for: evaluated, resolved: resolved, limits: .standard) }
            #expect(throws: failure) {
                _ = try writer.records(for: evaluated, resolved: resolved, transfer: STEPAttributeWriteTransfer(), startingAt: 1, limits: .standard)
            }
            let sink = DataByteSink()
            #expect(throws: failure) { try STEPExchange(tolerance: .standard).write(evaluated, to: sink) }
            #expect(sink.bytes.isEmpty)
            let facade = OfficialFormatExchange(tolerance: .standard)
            #expect(throws: failure) { try facade.write(evaluated, as: .step, to: sink) }
            #expect(sink.bytes.isEmpty)
            #expect(throws: failure) { try facade.export(evaluated, as: .step, to: url) }
            #expect(try Data(contentsOf: url) == original)
        }
        // The ordinary public route must also forward the caller ceiling to name projection.
        var ordinary = CADDocument(units: .meters, designGraph: source.designGraph)
        ordinary.productAttributes = ProductAttributes(assignments: [ProductAttributeAssignment(
            target: ProductAttributeTarget(kind: .body, geometry: body.geometry), value: .name("global ordinary name"))])
        let ordinaryEvaluated = try evaluator.evaluate(ordinary), ordinaryResolved = try resolver.resolve(ordinaryEvaluated)
        let ordinarySink = DataByteSink()
        #expect(throws: ProductAttributeError.resourceLimitExceeded("Cumulative product attribute budget.")) {
            try STEPExchange(tolerance: .standard,
                resourceLimits: ExchangeResourceLimits(maximumIterations: ordinaryResolved.consumedWork)).write(ordinaryEvaluated, to: ordinarySink)
        }
        #expect(ordinarySink.bytes.isEmpty)
    }
    private func imported(_ text: String = Self.independentFixture) throws -> CADDocument {
        let result = try STEPExchange(tolerance: .standard).import(Data(text.utf8))
        return try #require(result.document)
    }
    @Test(.timeLimit(.minutes(1)))
    func independentMultiBodyCarrierKeepsPartScopeAndFaceOverride() throws {
        let document = try imported(), assembly = try #require(document.assembly)
        #expect(assembly.definitions.count == 1 && assembly.roots.count == 1)
        let part = try #require(assembly.definitions.first)
        #expect(part.features.count == 2 && document.designGraph.order.count == 2)
        #expect(assembly.products.first?.name == "two-body real part")
        let colors = document.productAttributes.assignments.filter { $0.value.property == .color }
        let base = try #require(colors.first { $0.target.kind == .part })
        let faceOverride = try #require(colors.first { $0.target.kind == .face })
        #expect(base.target.definitionID == part.id && faceOverride.overrides == base.id)
        #expect(document.productAttributes.layers.count == 2)
        #expect(document.productAttributes.layers.first { $0.name == "whole part" }?.members.first?.kind == .part)
        let material = try #require(document.productAttributes.materials.first)
        #expect(material.name == "steel" && abs((material.density?.kilogramsPerCubicMeter ?? 0) - 7850) < 1e-9)
        #expect(document.productAttributes.assignments.contains { $0.value == .descriptorDensity(material.id) })
        let evaluated = try DocumentEvaluator(tolerance: .standard).evaluateExact(document)
        let resolved = try ProductAttributeResolver().resolve(evaluated)
        let faces = resolved.values.filter { target, _ in if case .face = target.topology { return true }; return false }
        #expect(faces.count == 2)
        #expect(faces.values.filter { $0.properties[.color]?.value == .color(ColorRGBA(r: 1,g: 0,b: 0,a: 1)) }.count == 1)
        #expect(faces.values.filter { $0.properties[.color]?.value == .color(ColorRGBA(r: 0,g: 0,b: 1,a: 1)) }.count == 1)
        let density = try #require(material.density)
        #expect(faces.values.allSatisfy { $0.properties[.density]?.value == .density(density) })
        let points = evaluated.brep.vertices.values.map(\.point)
        #expect(points.count == 6 && points.contains { abs($0.x - 0.1) < 1e-12 })
    }
    @Test(.timeLimit(.minutes(1)))
    func publicSTEPAndNativeMemoryAndURLRoundTripsPreserveSourceScope() throws {
        let document = try imported(), evaluated = try DocumentEvaluator(tolerance: .standard).evaluate(document)
        let facade = OfficialFormatExchange(tolerance: .standard), sink = DataByteSink()
        try facade.write(evaluated, as: .step, to: sink)
        let text = try #require(String(data: sink.bytes, encoding: .utf8))
        #expect(text.components(separatedBy: "MAPPED_ITEM(").count - 1 == 1)
        let restored = try imported(text)
        #expect(attributeSignature(restored) == attributeSignature(document))
        #expect(restored.assembly?.definitions.count == 1 && restored.designGraph.order.count == 2)
        let native = DataByteSink(), store = NativePackageStore(tolerance: .standard)
        try store.writePackage(for: document, to: native)
        #expect(try store.loadDocument(from: native.bytes) == document)
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { do { try FileManager.default.removeItem(at: directory) } catch { Issue.record("Cleanup failed: \(error)") } }
        let url = directory.appendingPathComponent("attributes.step")
        try facade.export(evaluated, as: .step, to: url)
        let urlImport = try #require(facade.import(from: url).document)
        #expect(attributeSignature(urlImport) == attributeSignature(document))
        let before = try Data(contentsOf: url)
        let limited = OfficialFormatExchange(tolerance: .standard, stepExchange: STEPExchange(tolerance: .standard,
            resourceLimits: ExchangeResourceLimits(maximumEntities: 20)))
        #expect(throws: (any Error).self) { try limited.export(evaluated, as: .step, to: url) }
        #expect(try Data(contentsOf: url) == before)
    }
    @Test(.timeLimit(.minutes(1)))
    func malformedCarriersCompetingPropertiesAndUnsupportedLossRefuse() throws {
        for fixture in [
            Self.independentFixture.replacingOccurrences(of: "#10,1.,#13", with: "#10,2.,#13"),
            Self.independentFixture.replacingOccurrences(of: "(#58,#17),#7", with: "(#58,#38,#17),#7"),
            Self.independentFixture.replacingOccurrences(of: "(#38,#238,#17),#7", with: "(#38,#238,#58,#17),#7"),
            Self.independentFixture.replacingOccurrences(of: "ENDSEC;\nEND-ISO", with: "#419=PROPERTY_DEFINITION('material property','density',#52);\n#420=PROPERTY_DEFINITION_REPRESENTATION(#419,#417);\nENDSEC;\nEND-ISO"),
            Self.independentFixture.replacingOccurrences(of: "SURFACE_STYLE_USAGE(.BOTH.", with: "SURFACE_STYLE_USAGE(.POSITIVE."),
            Self.independentFixture.replacingOccurrences(of: "DERIVED_UNIT_ELEMENT(#411,-3.)", with: "DERIVED_UNIT_ELEMENT(#411,-2.)"),
            Self.independentFixture.replacingOccurrences(of: "DERIVED_UNIT_ELEMENT(#411,-3.)", with: "DERIVED_UNIT_ELEMENT(#414,-3.)"),
            Self.independentFixture.replacingOccurrences(of: "STYLED_ITEM('',(#76),#58)", with: "STYLED_ITEM('',(#76),#52)")
        ] { #expect(throws: (any Error).self) { _ = try imported(fixture) } }
        let evaluated = try DocumentEvaluator(tolerance: .standard).evaluate(imported())
        for format in [ExchangeFileFormat.glb, .ply, .iges] {
            let sink = DataByteSink()
            #expect(throws: ProductAttributeError.self) { try OfficialFormatExchange(tolerance: .standard).write(evaluated, as: format, to: sink) }
            #expect(sink.bytes.isEmpty)
        }
    }
    @Test(.timeLimit(.minutes(1)))
    func standardBodyFaceAndDirectUsagePhysicalTargetsKeepTheirDeclaredScope() throws {
        for (entity, kind) in [(38, ProductAttributeTarget.Kind.body), (36, .face)] {
            var fixture = Self.independentFixture.replacingOccurrences(of: "'material name',#52", with: "'material name',#430")
                .replacingOccurrences(of: "'density',#52", with: "'density',#430")
            fixture = fixture.replacingOccurrences(of: "ENDSEC;\nEND-ISO", with: "#430=SHAPE_ASPECT('','',#53,.T.);\n#431=GEOMETRIC_ITEM_SPECIFIC_USAGE('','',#430,#54,#\(entity));\nENDSEC;\nEND-ISO")
            let document = try imported(fixture)
            let definition = try #require(document.assembly?.definitions.first)
            #expect(document.productAttributes.assignments.filter { $0.value.property == .material || $0.value.property == .density }.allSatisfy {
                $0.target.kind == kind && $0.target.definitionID == definition.id
            })
            let sink = DataByteSink()
            try STEPExchange(tolerance: .standard).write(DocumentEvaluator(tolerance: .standard).evaluateExact(document), to: sink)
            let restored = try #require(STEPExchange(tolerance: .standard).import(sink.bytes).document)
            #expect(attributeSignature(restored) == attributeSignature(document))
        }
        var document = try imported()
        document.productAttributes.assignments.removeAll { $0.value.property == .material || $0.value.property == .density }
        let material = PhysicalMaterialDescriptor(name: "usage material")
        let root = try #require(document.assembly?.roots.first)
        document.productAttributes.materials = [material]
        document.productAttributes.assignments.append(ProductAttributeAssignment(target: ProductAttributeTarget(kind: .directUsage, usageID: root.id), value: .material(material.id)))
        let sink = DataByteSink()
        try STEPExchange(tolerance: .standard).write(DocumentEvaluator(tolerance: .standard).evaluateExact(document), to: sink)
        let restored = try #require(STEPExchange(tolerance: .standard).import(sink.bytes).document)
        #expect(restored.productAttributes.assignments.contains { $0.target.kind == .directUsage && $0.value.property == .material })
        #expect(restored.assembly?.roots.first?.id == root.id)
    }
    @Test(.timeLimit(.minutes(1)))
    func coincidentTransparencyPreservesSeparatePropertiesAndIncompletePhysicalPathsRefuseAtomically() throws {
        var document = try imported()
        let part = try #require(document.assembly?.definitions.first)
        let target = ProductAttributeTarget(kind: .part, definitionID: part.id)
        document.productAttributes.assignments.append(ProductAttributeAssignment(target: target, value: .opacity(0.75)))
        let sink = DataByteSink()
        try STEPExchange(tolerance: .standard).write(DocumentEvaluator(tolerance: .standard).evaluateExact(document), to: sink)
        let restored = try #require(STEPExchange(tolerance: .standard).import(sink.bytes).document)
        #expect(restored.productAttributes.assignments.contains { $0.target.kind == .part && $0.value == .opacity(0.75) })
        #expect(restored.productAttributes.assignments.filter { $0.value.property == .color }.count == 2)
        let root = try #require(document.assembly?.roots.first)
        document.productAttributes.assignments.append(ProductAttributeAssignment(target: ProductAttributeTarget(kind: .occurrence,
            path: AssemblyOccurrencePath([root.id])), value: .density(PhysicalDensity(kilogramsPerCubicMeter: 7000)),
            overrides: document.productAttributes.assignments.first { $0.value.property == .density }?.id))
        let evaluated = try DocumentEvaluator(tolerance: .standard).evaluateExact(document), refused = DataByteSink()
        #expect(throws: ProductAttributeError.self) { try STEPExchange(tolerance: .standard).write(evaluated, to: refused) }
        #expect(refused.bytes.isEmpty)
    }
    @Test(.timeLimit(.minutes(1)))
    func contextualOccurrenceColorAndLayerRoundTripKeepSharedDefinitionAndFullPath() throws {
        var document = try imported()
        let original = try #require(document.assembly?.roots.first)
        let second = AssemblyOccurrence(name: "second placement", definitionID: original.definitionID,
            placement: .translated(by: Vector3D(x: 0.2,y: 0,z: 0)))
        document.assembly?.roots.append(second)
        document.productAttributes.assignments.removeAll { $0.target.kind == .face && $0.value.property == .color }
        let blue = try #require(document.productAttributes.assignments.first { $0.target.kind == .part && $0.value.property == .color })
        let target = ProductAttributeTarget(kind: .occurrence, path: AssemblyOccurrencePath([second.id]))
        let green = ProductAttributeAssignment(target: target, value: .color(ColorRGBA(r: 0,g: 1,b: 0,a: 1)), overrides: blue.id)
        document.productAttributes.assignments.append(green)
        document.productAttributes.layers.append(ProductLayer(name: "placed component", members: [target]))
        let evaluated = try DocumentEvaluator(tolerance: .standard).evaluateExact(document)
        let sink = DataByteSink()
        try STEPExchange(tolerance: .standard).write(evaluated, to: sink)
        let restored = try #require(STEPExchange(tolerance: .standard).import(sink.bytes).document)
        #expect(restored.assembly?.definitions.count == 1 && restored.assembly?.roots.count == 2)
        let contextual = try #require(restored.productAttributes.assignments.first { $0.target.kind == .occurrence })
        #expect(contextual.target.path == target.path && contextual.value == green.value && contextual.overrides != nil)
        #expect(restored.productAttributes.layers.first { $0.name == "placed component" }?.members == [target])
        let view = try ProductAttributeResolver().resolve(DocumentEvaluator(tolerance: .standard).evaluateExact(restored))
        #expect(view.values.contains { key, value in key.path == target.path && value.properties[.color]?.value == green.value })
        #expect(view.values.contains { key, value in key.path == AssemblyOccurrencePath([original.id]) && value.properties[.color]?.value == blue.value })
    }
    @Test(.timeLimit(.minutes(1)))
    func strictNativeCurrentAttributesAndOlderEnvelopesDoNotSilentlyMigrate() throws {
        let document = try imported(), store = NativePackageStore(tolerance: .standard), sink = DataByteSink()
        try store.writePackage(for: document, to: sink)
        for mutation in 0..<3 {
            let bytes = try StoredZipArchive.withEntries(from: BorrowedBytes(sink.bytes)) { entries in
                let source = try #require(entries["document.json"]), header = try #require(entries["manifest.json"])
                var json = try #require(JSONSerialization.jsonObject(with: source) as? [String: Any])
                switch mutation {
                case 0: json.removeValue(forKey: "productAttributes")
                case 1: json["productAttributes"] = ["materials": [], "assignments": [], "layers": [], "unknown": true] as [String: Any]
                default: json["schemaVersion"] = ["major": 0, "minor": 4, "patch": 0]
                }
                return try StoredZipArchive.make(entries: [.init(path: "manifest.json", data: header),
                    .init(path: "document.json", data: JSONSerialization.data(withJSONObject: json, options: [.sortedKeys]))])
            }
            #expect(throws: (any Error).self) { _ = try store.loadDocument(from: BorrowedBytes(bytes)) }
        }
    }
    @Test(.timeLimit(.minutes(1)))
    func bareGeometryAndGenuineNamedSingleProductSelectTheirActualSourceAuthority() throws {
        let lines = Self.independentFixture.split(separator: "\n").map(String.init)
        let removed = Set([56,57,58,59,60] + Array(70...91) + Array(400...418))
        let retained = lines.filter { line in
            guard line.first == "#", let end = line.firstIndex(of: "="),
                  let id = Int(line[line.index(after: line.startIndex)..<end]) else { return true }
            return !removed.contains(id)
        }.joined(separator: "\n").replacingOccurrences(of: "SHAPE_DEFINITION_REPRESENTATION(#53,#56)",
            with: "SHAPE_DEFINITION_REPRESENTATION(#53,#54)")
        let genuineIdentifier = retained.replacingOccurrences(of: "PRODUCT('part','two-body real part'", with: "PRODUCT('part',''")
        let bare = genuineIdentifier.replacingOccurrences(of: "PRODUCT('part',''", with: "PRODUCT('SWIFTCAD',''")
        let exchange = STEPExchange(tolerance: .standard)
        let ordinary = try exchange.import(Data(bare.utf8)), repeated = try exchange.import(Data(bare.utf8))
        let ordinarySource = try #require(ordinary.document), ordinaryBRep = try #require(ordinary.brep)
        #expect(ordinarySource.assembly == nil && ordinarySource.designGraph.order.count == 2)
        #expect(ordinaryBRep == repeated.brep)
        #expect(ordinarySource.productAttributes.assignments.contains { $0.value == .name("body alpha") })
        let identifierSource = try #require(exchange.import(Data(genuineIdentifier.utf8)).document)
        #expect(identifierSource.assembly?.products.first?.identifier == "part")
        #expect(identifierSource.assembly?.products.first?.name == "")
        #expect(identifierSource.assembly?.definitions.count == 1)
        let named = try exchange.import(Data(retained.utf8))
        let namedSource = try #require(named.document), part = try #require(namedSource.assembly?.definitions.first)
        #expect(namedSource.assembly?.definitions.count == 1 && part.features.count == 2)
        #expect(namedSource.assembly?.products.first?.name == "two-body real part")
        let sink = DataByteSink()
        try exchange.write(brep: ordinaryBRep, to: sink)
        let written = try #require(String(data: sink.bytes, encoding: .utf8))
        #expect(written.contains("PRODUCT('SWIFTCAD','','',"))
        let writtenSource = try #require(exchange.import(sink.bytes).document)
        #expect(writtenSource.assembly == nil)
        let described = genuineIdentifier.replacingOccurrences(of: "PRODUCT('part','',''", with: "PRODUCT('part','','real product description'")
        let describedSource = try #require(exchange.import(Data(described.utf8)).document)
        #expect(describedSource.assembly?.products.first?.description == "real product description")
        let describedSink = DataByteSink()
        try exchange.write(DocumentEvaluator(tolerance: .standard).evaluateExact(describedSource), to: describedSink)
        let restoredDescription = try #require(exchange.import(describedSink.bytes).document)
        #expect(restoredDescription.assembly?.products.first?.description == "real product description")
    }
    @Test(.timeLimit(.minutes(1)))
    func ordinaryAttributedGeometryRetainsCallerWorkLimitAtFinalResolution() throws {
        // Repetition expands independently authored exact triangles and their body names,
        // rather than using the production STEP writer to manufacture the regression input.
        let count = 200
        let lines = Self.independentFixture.split(separator: "\n").map(String.init)
        func entityID(_ line: String) -> Int? {
            guard line.first == "#", let end = line.firstIndex(of: "=") else { return nil }
            return Int(line[line.index(after: line.startIndex)..<end])
        }
        let units = lines.filter { line in guard let id = entityID(line) else { return false }; return (1...7).contains(id) }
        let triangle = lines.filter { line in guard let id = entityID(line) else { return false }; return (10...38).contains(id) || (100...121).contains(id) }
        var records = units
        for index in 0..<count {
            let offset = (index + 1) * 1000
            for original in triangle {
                var line = original.replacingOccurrences(of: "'body alpha'", with: "'triangle \(index)'")
                    .replacingOccurrences(of: "'face alpha'", with: "''")
                // All references in this standalone triangle are local; shared global units
                // are in #1...#7 and are deliberately outside this independently authored block.
                for id in stride(from: 121, through: 10, by: -1) {
                    line = line.replacingOccurrences(of: "#\(id)=", with: "#\(offset + id)=")
                    for terminator in [",", ")", ";"] {
                        line = line.replacingOccurrences(of: "#\(id)" + terminator, with: "#\(offset + id)" + terminator)
                    }
                }
                records.append(line)
            }
        }
        let fixture = "ISO-10303-21;\nHEADER;\nFILE_DESCRIPTION(('ordinary attributed triangles'),'2;1');\nFILE_NAME('ordinary.step','2000-01-01T00:00:00',(''),(''),'fixture','','');\nFILE_SCHEMA(('AP242_MANAGED_MODEL_BASED_3D_ENGINEERING_MIM_LF'));\nENDSEC;\nDATA;\n"
            + records.joined(separator: "\n") + "\nENDSEC;\nEND-ISO-10303-21;"
        let imported = try STEPExchange(tolerance: .standard).import(Data(fixture.utf8))
        let document = try #require(imported.document)
        #expect(document.assembly == nil && document.designGraph.order.count == count)
        let evaluated = try DocumentEvaluator(tolerance: .standard).evaluateExact(document)
        let limits = ExchangeResourceLimits(maximumIterations: fixture.utf8.count)
        let attributes = ProductAttributeLimits(maximumRecords: limits.maximumEntities, maximumTargets: limits.maximumEntities,
            maximumDepth: limits.maximumNesting, maximumTextBytes: limits.maximumBytes, maximumWork: limits.maximumIterations)
        let resolved = try ProductAttributeResolver().resolve(evaluated)
        #expect(resolved.consumedWork > limits.maximumIterations)
        var transfer = STEPAttributeReadTransfer()
        for index in 0..<count {
            let name = "triangle \(index)"
            let assignment = try #require(document.productAttributes.assignments.first { $0.value == .name(name) })
            let reference = try #require(assignment.target.geometry)
            let offset = (index + 1) * 1000
            transfer.geometry[offset + 38] = reference.subshapeID
            transfer.geometry[offset + 36] = SubshapeID(featureID: reference.subshapeID.featureID,
                role: GeneratedSubshapeRole.face.rawValue, ordinal: 0)
        }
        var entities: [Int: String] = [:]
        for record in records {
            guard let id = entityID(record), id > 0, let delimiter = record.firstIndex(of: "="), record.last == ";" else {
                Issue.record("Malformed independently authored STEP fixture record.")
                return
            }
            let value = String(record[record.index(after: delimiter)..<record.index(before: record.endIndex)])
            guard !value.isEmpty, entities.updateValue(value, forKey: id) == nil else {
                Issue.record("Duplicate or empty independently authored STEP fixture entity.")
                return
            }
        }
        // The actual reader/source admission succeeds under the same ceiling; the full
        // local topology/provenance resolution exceeds it. A refusal here is not parser-only.
        let retained = try STEPAttributesReader().read(entities: entities, transfer: transfer, evaluated: evaluated, limits: limits)
        #expect(retained.assignments.count == count)
        do {
            _ = try ProductAttributeResolver().resolve(evaluated, limits: attributes)
            Issue.record("Final consistency resolution ignored the caller ceiling.")
        } catch let error as ProductAttributeError {
            guard case .resourceLimitExceeded = error else { Issue.record("Unexpected resolution failure: \(error)"); return }
        }
        do {
            _ = try STEPExchange(tolerance: .standard, resourceLimits: limits).import(Data(fixture.utf8))
            Issue.record("Ordinary attributed STEP import reset the final consistency ceiling.")
        } catch let error as ProductAttributeError {
            guard case .resourceLimitExceeded = error else { Issue.record("Unexpected ordinary import failure: \(error)"); return }
        }
    }
    private func attributeSignature(_ document: CADDocument) -> [String] {
        let source = document.productAttributes
        var result = source.assignments.map { assignment -> String in
            let value: String
            switch assignment.value {
            case let .name(name): value = "name:" + name
            case let .color(c): value = "color:\(c.r),\(c.g),\(c.b)"
            case let .opacity(v): value = "opacity:\(v)"
            case let .material(id): value = "material:" + (source.materials.first { $0.id == id }?.name ?? "missing")
            case let .density(v): value = "density:\(v.kilogramsPerCubicMeter)"
            case let .descriptorDensity(id): value = "density:\(source.materials.first { $0.id == id }?.density?.kilogramsPerCubicMeter ?? -1)"
            }
            return assignment.target.kind.rawValue + ":" + (assignment.target.definitionID?.description ?? "global") + ":" + value + ":" + String(assignment.overrides != nil)
        }
        result += source.layers.map { $0.name + ":" + $0.description + ":" + $0.members.map { $0.kind.rawValue }.sorted().joined(separator: ",") }
        return result.sorted()
    }
    // Literal standard STEP fixture: two distinct millimetre triangles, unique identity whole-part carrier,
    // blue part style, red explicit face override, set layers, and 7.85 g/cm^3 physical density.
    // Neither the production geometry writer nor the production attribute writer creates this input.
    static let independentFixture = #"""
ISO-10303-21;
HEADER;
FILE_DESCRIPTION(('Independent part carrier and attributes'),'2;1');
FILE_NAME('attributes.step','2000-01-01T00:00:00',(''),(''),'fixture','','');
FILE_SCHEMA(('AP242_MANAGED_MODEL_BASED_3D_ENGINEERING_MIM_LF'));
ENDSEC;
DATA;
#1=APPLICATION_CONTEXT('mechanical design');
#2=PRODUCT_CONTEXT('',#1,'mechanical');
#3=PRODUCT_DEFINITION_CONTEXT('part definition',#1,'design');
#4=(LENGTH_UNIT() NAMED_UNIT(*) SI_UNIT(.MILLI.,.METRE.));
#5=(NAMED_UNIT(*) PLANE_ANGLE_UNIT() SI_UNIT($,.RADIAN.));
#6=(NAMED_UNIT(*) SI_UNIT($,.STERADIAN.) SOLID_ANGLE_UNIT());
#7=(GEOMETRIC_REPRESENTATION_CONTEXT(3) GLOBAL_UNIT_ASSIGNED_CONTEXT((#4,#5,#6)) REPRESENTATION_CONTEXT('part',''));
#10=CARTESIAN_POINT('',(0.,0.,0.));
#11=CARTESIAN_POINT('',(40.,0.,0.));
#12=CARTESIAN_POINT('',(0.,20.,0.));
#13=DIRECTION('',(0.,0.,1.));
#14=DIRECTION('',(1.,0.,0.));
#15=DIRECTION('',(-2.,1.,0.));
#16=DIRECTION('',(0.,-1.,0.));
#17=AXIS2_PLACEMENT_3D('',#10,#13,#14);
#18=PLANE('',#17);
#19=VECTOR('',#14,1.);
#20=VECTOR('',#15,1.);
#21=VECTOR('',#16,1.);
#22=LINE('',#10,#19);
#23=LINE('',#11,#20);
#24=LINE('',#12,#21);
#25=VERTEX_POINT('',#10);
#26=VERTEX_POINT('',#11);
#27=VERTEX_POINT('',#12);
#28=EDGE_CURVE('',#25,#26,#119,.T.);
#29=EDGE_CURVE('',#26,#27,#120,.T.);
#30=EDGE_CURVE('',#27,#25,#121,.T.);
#31=ORIENTED_EDGE('',*,*,#28,.T.);
#32=ORIENTED_EDGE('',*,*,#29,.T.);
#33=ORIENTED_EDGE('',*,*,#30,.T.);
#34=EDGE_LOOP('',(#31,#32,#33));
#35=FACE_OUTER_BOUND('',#34,.T.);
#36=ADVANCED_FACE('face alpha',(#35),#18,.T.);
#37=OPEN_SHELL('',(#36));
#38=SHELL_BASED_SURFACE_MODEL('body alpha',(#37));
#100=(GEOMETRIC_REPRESENTATION_CONTEXT(2) PARAMETRIC_REPRESENTATION_CONTEXT() REPRESENTATION_CONTEXT('plane parameters',''));
#101=CARTESIAN_POINT('',(0.,0.));
#102=CARTESIAN_POINT('',(40.,0.));
#103=CARTESIAN_POINT('',(0.,20.));
#104=DIRECTION('',(1.,0.));
#105=DIRECTION('',(-2.,1.));
#106=DIRECTION('',(0.,-1.));
#107=VECTOR('',#104,1.);
#108=VECTOR('',#105,1.);
#109=VECTOR('',#106,1.);
#110=LINE('',#101,#107);
#111=LINE('',#102,#108);
#112=LINE('',#103,#109);
#113=DEFINITIONAL_REPRESENTATION('',(#110),#100);
#114=DEFINITIONAL_REPRESENTATION('',(#111),#100);
#115=DEFINITIONAL_REPRESENTATION('',(#112),#100);
#116=PCURVE('',#18,#113);
#117=PCURVE('',#18,#114);
#118=PCURVE('',#18,#115);
#119=SURFACE_CURVE('',#22,(#116),.PCURVE_S1.);
#120=SURFACE_CURVE('',#23,(#117),.PCURVE_S1.);
#121=SURFACE_CURVE('',#24,(#118),.PCURVE_S1.);
#210=CARTESIAN_POINT('',(60.,0.,0.));
#211=CARTESIAN_POINT('',(100.,0.,0.));
#212=CARTESIAN_POINT('',(60.,20.,0.));
#213=DIRECTION('',(0.,0.,1.));
#214=DIRECTION('',(1.,0.,0.));
#215=DIRECTION('',(-2.,1.,0.));
#216=DIRECTION('',(0.,-1.,0.));
#217=AXIS2_PLACEMENT_3D('',#210,#213,#214);
#218=PLANE('',#217);
#219=VECTOR('',#214,1.);
#220=VECTOR('',#215,1.);
#221=VECTOR('',#216,1.);
#222=LINE('',#210,#219);
#223=LINE('',#211,#220);
#224=LINE('',#212,#221);
#225=VERTEX_POINT('',#210);
#226=VERTEX_POINT('',#211);
#227=VERTEX_POINT('',#212);
#228=EDGE_CURVE('',#225,#226,#319,.T.);
#229=EDGE_CURVE('',#226,#227,#320,.T.);
#230=EDGE_CURVE('',#227,#225,#321,.T.);
#231=ORIENTED_EDGE('',*,*,#228,.T.);
#232=ORIENTED_EDGE('',*,*,#229,.T.);
#233=ORIENTED_EDGE('',*,*,#230,.T.);
#234=EDGE_LOOP('',(#231,#232,#233));
#235=FACE_OUTER_BOUND('',#234,.T.);
#236=ADVANCED_FACE('face beta',(#235),#218,.T.);
#237=OPEN_SHELL('',(#236));
#238=SHELL_BASED_SURFACE_MODEL('body beta',(#237));
#300=(GEOMETRIC_REPRESENTATION_CONTEXT(2) PARAMETRIC_REPRESENTATION_CONTEXT() REPRESENTATION_CONTEXT('plane parameters',''));
#301=CARTESIAN_POINT('',(0.,0.));
#302=CARTESIAN_POINT('',(40.,0.));
#303=CARTESIAN_POINT('',(0.,20.));
#304=DIRECTION('',(1.,0.));
#305=DIRECTION('',(-2.,1.));
#306=DIRECTION('',(0.,-1.));
#307=VECTOR('',#304,1.);
#308=VECTOR('',#305,1.);
#309=VECTOR('',#306,1.);
#310=LINE('',#301,#307);
#311=LINE('',#302,#308);
#312=LINE('',#303,#309);
#313=DEFINITIONAL_REPRESENTATION('',(#310),#300);
#314=DEFINITIONAL_REPRESENTATION('',(#311),#300);
#315=DEFINITIONAL_REPRESENTATION('',(#312),#300);
#316=PCURVE('',#218,#313);
#317=PCURVE('',#218,#314);
#318=PCURVE('',#218,#315);
#319=SURFACE_CURVE('',#222,(#316),.PCURVE_S1.);
#320=SURFACE_CURVE('',#223,(#317),.PCURVE_S1.);
#321=SURFACE_CURVE('',#224,(#318),.PCURVE_S1.);
#50=PRODUCT('part','two-body real part','',(#2));
#51=PRODUCT_DEFINITION_FORMATION('','',#50);
#52=PRODUCT_DEFINITION('design','',#51,#3);
#53=PRODUCT_DEFINITION_SHAPE('','',#52);
#54=SHAPE_REPRESENTATION('',(#38,#238,#17),#7);
#55=SHAPE_DEFINITION_REPRESENTATION(#53,#56);
#56=SHAPE_REPRESENTATION('',(#58,#17),#7);
#57=REPRESENTATION_MAP(#17,#54);
#58=MAPPED_ITEM('',#57,#59);
#59=CARTESIAN_TRANSFORMATION_OPERATOR_3D('',*,*,#14,#60,#10,1.,#13);
#60=DIRECTION('',(0.,1.,0.));
#70=COLOUR_RGB('',0.,0.,1.);
#71=FILL_AREA_STYLE_COLOUR('',#70);
#72=FILL_AREA_STYLE('',(#71));
#73=SURFACE_STYLE_FILL_AREA(#72);
#74=SURFACE_SIDE_STYLE('',(#73));
#75=SURFACE_STYLE_USAGE(.BOTH.,#74);
#76=PRESENTATION_STYLE_ASSIGNMENT((#75));
#77=STYLED_ITEM('',(#76),#58);
#80=COLOUR_RGB('',1.,0.,0.);
#81=FILL_AREA_STYLE_COLOUR('',#80);
#82=FILL_AREA_STYLE('',(#81));
#83=SURFACE_STYLE_FILL_AREA(#82);
#84=SURFACE_SIDE_STYLE('',(#83));
#85=SURFACE_STYLE_USAGE(.BOTH.,#84);
#86=PRESENTATION_STYLE_ASSIGNMENT((#85));
#87=OVER_RIDING_STYLED_ITEM('',(#86),#36,#77);
#88=DRAUGHTING_MODEL('',(#77,#87),#7);
#90=PRESENTATION_LAYER_ASSIGNMENT('whole part','manufacturing',(#58));
#91=PRESENTATION_LAYER_ASSIGNMENT('inspection','face selection',(#236));
#400=PROPERTY_DEFINITION('material property','material name',#52);
#401=DESCRIPTIVE_REPRESENTATION_ITEM('steel','independent physical material');
#402=REPRESENTATION('material name',(#401),#7);
#403=PROPERTY_DEFINITION_REPRESENTATION(#400,#402);
#410=(MASS_UNIT() NAMED_UNIT(*) SI_UNIT($,.GRAM.));
#411=(LENGTH_UNIT() NAMED_UNIT(*) SI_UNIT(.CENTI.,.METRE.));
#412=DERIVED_UNIT_ELEMENT(#410,1.);
#413=DERIVED_UNIT_ELEMENT(#411,-3.);
#414=DERIVED_UNIT((#412,#413));
#415=(MEASURE_REPRESENTATION_ITEM() MEASURE_WITH_UNIT(MASS_DENSITY_MEASURE(7.85),#414) REPRESENTATION_ITEM('density'));
#416=PROPERTY_DEFINITION('material property','density',#52);
#417=REPRESENTATION('density',(#415),#7);
#418=PROPERTY_DEFINITION_REPRESENTATION(#416,#417);
ENDSEC;
END-ISO-10303-21;
"""#
}
