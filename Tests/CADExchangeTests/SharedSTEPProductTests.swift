import Foundation
import Testing
import CADCore
import CADIR
import CADKernel
import CADTopology
@testable import CADExchange

@Suite("Shared STEP product and formation authorities")
struct SharedSTEPProductTests {
    private func imported(_ literal: String = Self.fixture) throws -> CADDocument {
        try #require(STEPExchange(tolerance: .standard).import(Data(literal.utf8)).document)
    }
    private func partDefinitions(_ document: CADDocument) throws -> [AssemblyDefinition] {
        let assembly = try #require(document.assembly)
        return assembly.definitions.filter { !$0.features.isEmpty }.sorted { $0.identifier < $1.identifier }
    }
    private func sourceMetadata(_ assembly: DocumentAssembly) -> [String] {
        var result = assembly.products.map { "P:" + $0.id.description + ":" + $0.identifier + ":" + $0.name + ":" + String(describing: $0.description) }
        result += assembly.formations.map { "F:" + $0.id.description + ":" + $0.productID.description + ":" + $0.versionIdentifier + ":" + String(describing: $0.description) + ":" + String(describing: $0.specifiedSource) }
        result += assembly.definitions.map { "D:" + $0.id.description + ":" + $0.formationID.description + ":" + $0.identifier + ":" + String(describing: $0.definitionDescription) }
        return result.sorted()
    }
    @Test(.timeLimit(.minutes(1)))
    func literalSharedOwnersAndTwoPublicSTEPGenerationsPreserveIdentifiersAndPlacements() throws {
        let document = try imported(), assembly = try #require(document.assembly)
        let definitions = try partDefinitions(document)
        #expect(assembly.products.count == 2 && assembly.formations.count == 2 && assembly.definitions.count == 3)
        #expect(definitions.count == 2 && definitions[0].formationID == definitions[1].formationID)
        let product = try #require(assembly.products.first { $0.identifier == "part" })
        #expect(product.name == "shared 部品" && product.description == "product description")
        #expect(product.id.description == "11111111-1111-4111-8111-111111111111")
        let formation = try #require(assembly.formations.first { $0.productID == product.id })
        #expect(formation.versionIdentifier == "v1" && formation.description == "formation description" && formation.specifiedSource == .made)
        #expect(Set(definitions.map(\.id.description)) == ["33333333-3333-4333-8333-333333333333", "44444444-4444-4444-8444-444444444444"])
        #expect(definitions.first { $0.identifier == "design" }?.definitionDescription == "first view description")
        #expect(definitions.first { $0.identifier == "analysis" }?.definitionDescription == nil)
        let parent = try #require(assembly.definitions.first { $0.features.isEmpty })
        #expect(parent.identifier == "77777777-7777-4777-8777-777777777777" && parent.id.description != parent.identifier)
        let evaluator = DocumentEvaluator(tolerance: .standard), exchange = STEPExchange(tolerance: .standard)
        let first = try evaluator.evaluateExact(document)
        #expect(first.assembly?.local.model.bodies.count == 2 && first.brep.bodies.count == 2)
        for (x,y) in [(0.0,0.0),(0.04,0.0),(0.0,0.02),(0.09,0.1),(0.13,0.1),(0.09,0.12)] {
            #expect(first.brep.vertices.values.contains { abs($0.point.x-x) < 1e-12 && abs($0.point.y-y) < 1e-12 && abs($0.point.z) < 1e-12 })
        }
        #expect(first.assembly?.local.model.vertices.values.contains { abs($0.point.x-0.06) < 1e-12 } == true)
        var current = document
        for _ in 0..<2 {
            let sink = DataByteSink()
            try exchange.write(evaluator.evaluateExact(current), to: sink)
            let text = try #require(String(data: sink.bytes, encoding: .utf8))
            #expect(text.components(separatedBy: "=PRODUCT(").count - 1 == 3) // Real shared product, parent and authored root envelope.
            #expect(text.components(separatedBy: "=PRODUCT_DEFINITION_FORMATION_WITH_SPECIFIED_SOURCE(").count - 1 == 1)
            current = try #require(exchange.import(sink.bytes).document)
            let restoredAssembly = try #require(current.assembly)
            #expect(sourceMetadata(restoredAssembly) == sourceMetadata(assembly))
            let rebuilt = try evaluator.evaluateExact(current)
            let points = rebuilt.brep.vertices.values.map(\.point)
            #expect(points.count == first.brep.vertices.count)
            #expect(first.brep.vertices.values.allSatisfy { vertex in points.contains { ($0-vertex.point).length < 1e-12 } })
        }
        let native = DataByteSink(), store = NativePackageStore(tolerance: .standard)
        try store.writePackage(for: current, to: native)
        #expect(try store.loadDocument(from: native.bytes) == current)
    }
    @Test(.timeLimit(.minutes(1)))
    func rawEmptyAndUUIDShapedIdentifiersNeverBecomeNativeIdentityAuthority() throws {
        let empty = Self.fixture.replacingOccurrences(of: "PRODUCT('part'", with: "PRODUCT(''")
            .replacingOccurrences(of: "SOURCE('v1'", with: "SOURCE(''")
            .replacingOccurrences(of: "PRODUCT_DEFINITION('design'", with: "PRODUCT_DEFINITION(''")
        let shaped = Self.fixture.replacingOccurrences(of: "PRODUCT('part'", with: "PRODUCT('77777777-7777-4777-8777-777777777777'")
            .replacingOccurrences(of: "PRODUCT_DEFINITION('design'", with: "PRODUCT_DEFINITION('11111111-1111-4111-8111-111111111111'")
        let realReservedLabels = Self.fixture.replacingOccurrences(of: "PRODUCT('parent','real parent'",
            with: "PRODUCT('swiftcad.assembly.roots','swiftcad.assembly.roots'")
        for literal in [empty, shaped, realReservedLabels] {
            let source = try imported(literal), sink = DataByteSink()
            try STEPExchange(tolerance: .standard).write(DocumentEvaluator(tolerance: .standard).evaluateExact(source), to: sink)
            let restored = try #require(STEPExchange(tolerance: .standard).import(sink.bytes).document)
            let restoredAssembly = try #require(restored.assembly), sourceAssembly = try #require(source.assembly)
            #expect(sourceMetadata(restoredAssembly) == sourceMetadata(sourceAssembly))
            #expect(source.assembly?.products.first { $0.name == "shared 部品" }?.id.description == "11111111-1111-4111-8111-111111111111")
        }
        let noAssignment = shaped.split(separator: "\n").filter { !$0.hasPrefix("#60") }.joined(separator: "\n")
        let unassigned = try imported(noAssignment), parts = try partDefinitions(unassigned)
        #expect(parts.count == 2 && parts[0].id != parts[1].id)
        #expect(unassigned.assembly?.products.first { $0.name == "shared 部品" }?.id.description != "77777777-7777-4777-8777-777777777777")
        #expect(parts.first { $0.identifier == "11111111-1111-4111-8111-111111111111" }?.id.description != "11111111-1111-4111-8111-111111111111")
    }
    @Test(.timeLimit(.minutes(1)))
    func sharedNamesAndDefinitionLocalStylesSurvivePublicExchangeAndReuseGeometry() throws {
        var document = try imported()
        let parts = try partDefinitions(document), firstPart = parts[0], secondPart = parts[1]
        let blue = ProductAttributeAssignment(target: ProductAttributeTarget(kind: .part, definitionID: firstPart.id), value: .color(ColorRGBA(r: 0,g: 0,b: 1,a: 1)))
        let red = ProductAttributeAssignment(target: ProductAttributeTarget(kind: .part, definitionID: secondPart.id), value: .color(ColorRGBA(r: 1,g: 0,b: 0,a: 1)))
        document.productAttributes.assignments += [blue,red]
        let evaluator = DocumentEvaluator(tolerance: .standard), resolver: any ProductAttributeResolving = ProductAttributeResolver()
        let before = try evaluator.evaluate(document), original = try document.sourceFingerprint(tolerance: .standard)
        let productIndex = try #require(document.assembly?.products.firstIndex { $0.name == "shared 部品" })
        document.assembly?.products[productIndex].name = "shared edited name"
        let edited = try evaluator.evaluate(document, reusing: before)
        #expect(edited.evaluationMetrics.reusedFeatureCount == 2 && edited.evaluationMetrics.rebuiltFeatureCount == 0)
        #expect(edited.brep == before.brep && edited.assembly?.local == before.assembly?.local)
        #expect(try document.sourceFingerprint(tolerance: .standard) != original)
        let resolved = try resolver.resolve(edited, limits: .standard)
        for (part, color) in [(firstPart,blue.value),(secondPart,red.value)] {
            let properties = try #require(resolved.values[ResolvedProductTarget(definitionID: part.id)])
            #expect(properties.sourceName == "shared edited name" && properties.properties[.color]?.value == color)
        }
        let definitionIndex = try #require(document.assembly?.definitions.firstIndex { $0.id == firstPart.id })
        document.assembly?.definitions[definitionIndex].definitionDescription = "local edited description"
        let localEdit = try evaluator.evaluate(document, reusing: edited)
        #expect(localEdit.evaluationMetrics.reusedFeatureCount == 2 && localEdit.brep == edited.brep)
        let sink = DataByteSink()
        try OfficialFormatExchange(tolerance: .standard).write(localEdit, as: .step, to: sink)
        let restored = try #require(STEPExchange(tolerance: .standard).import(sink.bytes).document)
        let view = try resolver.resolve(evaluator.evaluateExact(restored), limits: .standard)
        #expect(view.values[ResolvedProductTarget(definitionID: firstPart.id)]?.properties[.color]?.value == blue.value)
        #expect(view.values[ResolvedProductTarget(definitionID: secondPart.id)]?.properties[.color]?.value == red.value)
        #expect(restored.assembly?.definitions.first { $0.id == secondPart.id }?.definitionDescription == secondPart.definitionDescription)
        #expect(restored.assembly?.definitions.first { $0.id == firstPart.id }?.definitionDescription == "local edited description")
        let store = NativePackageStore(tolerance: .standard), native = DataByteSink()
        try store.writePackage(for: document, to: native)
        #expect(try store.loadDocument(from: native.bytes) == document)
        let exact = try evaluator.evaluateExact(document)
        _ = try resolver.resolve(exact, limits: .standard)
        let reconstructed = EvaluatedDocument(document: document, parameters: exact.parameters, brep: exact.brep,
            meshes: exact.meshes, caches: exact.caches, subshapes: exact.subshapes, lineage: exact.lineage,
            configuration: exact.configuration, assembly: exact.assembly)
        #expect(throws: ProductAttributeError.self) { _ = try resolver.resolve(reconstructed, limits: .standard) }
    }
    @Test(.timeLimit(.minutes(1)))
    func conflictingMalformedIdentityAndFormationOrGeometryAmbiguitiesFailAtomically() throws {
        let duplicate = Self.fixture.replacingOccurrences(of: "ENDSEC;\nEND-ISO", with:
            "#609=APPLIED_EXTERNAL_IDENTIFICATION_ASSIGNMENT('AAAAAAAA-AAAA-4AAA-8AAA-AAAAAAAAAAAA',#603,#600,(#52));\nENDSEC;\nEND-ISO")
        let identityFailures: [(String, AssemblyError)] = [
            (duplicate, .invalidSource("Competing STEP native UUID assignments.")),
            (Self.fixture.replacingOccurrences(of: "urn:swiftcad:assembly-source-id", with: "urn:other:identity"),
             .invalidSource("Unsupported STEP identity namespace.")),
            (Self.fixture.replacingOccurrences(of: "IDENTIFICATION_ROLE('definition'", with: "IDENTIFICATION_ROLE('product'"),
             .invalidSource("STEP identity role and single target do not match.")),
            (Self.fixture.replacingOccurrences(of: "33333333-3333-4333-8333-333333333333", with: "invalid UUID"),
             .invalidSource("Malformed STEP native UUID assignment."))]
        for (literal, failure) in identityFailures { #expect(throws: failure) { _ = try imported(literal) } }
        let variants = [
            Self.fixture.replacingOccurrences(of: "'analysis',$,#51", with: "'analysis',$,#610").replacingOccurrences(of: "ENDSEC;\nEND-ISO", with: "#610=PRODUCT_DEFINITION_FORMATION('v1',$,#50);\nENDSEC;\nEND-ISO"),
            Self.fixture.replacingOccurrences(of: ".MADE.", with: ".INVENTED.")]
        for literal in variants { #expect(throws: (any Error).self) { _ = try imported(literal) } }
        let unassociatedGeometry = Self.fixture.replacingOccurrences(of: "SHAPE_DEFINITION_REPRESENTATION(#63,#64)", with: "SHAPE_DEFINITION_REPRESENTATION(#63,#54)")
        #expect(throws: AssemblyError.invalidSource("Unassociated STEP geometry would be discarded.")) { _ = try imported(unassociatedGeometry) }
        let source = try imported(), evaluated = try DocumentEvaluator(tolerance: .standard).evaluate(source)
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { do { try FileManager.default.removeItem(at: directory) } catch { Issue.record("Unable to remove shared product fixture directory: \(error)") } }
        let url = directory.appendingPathComponent("shared.step"), before = Data("existing complete output".utf8)
        try before.write(to: url)
        let constrained = OfficialFormatExchange(tolerance: .standard, stepExchange: STEPExchange(tolerance: .standard,
            resourceLimits: ExchangeResourceLimits(maximumEntities: 10)))
        #expect(throws: (any Error).self) { try constrained.export(evaluated, as: .step, to: url) }
        #expect(try Data(contentsOf: url) == before)
        #expect(throws: (any Error).self) { _ = try STEPExchange(tolerance: .standard,
            resourceLimits: ExchangeResourceLimits(maximumIterations: 10)).import(Data(Self.fixture.utf8)) }
        let native = DataByteSink(), store = NativePackageStore(tolerance: .standard)
        try store.writePackage(for: source, to: native)
        for mutation in 0..<3 {
            let bytes = try StoredZipArchive.withEntries(from: BorrowedBytes(native.bytes)) { entries in
                let header = try #require(entries["manifest.json"]), payload = try #require(entries["document.json"])
                var json = try #require(JSONSerialization.jsonObject(with: payload) as? [String: Any])
                if mutation == 0 {
                    var version = try #require(json["schemaVersion"] as? [String: Any]); version["minor"] = 6; json["schemaVersion"] = version
                } else {
                    var assembly = try #require(json["assembly"] as? [String: Any])
                    assembly.removeValue(forKey: mutation == 1 ? "products" : "formations"); json["assembly"] = assembly
                }
                return try StoredZipArchive.make(entries: [.init(path: "manifest.json", data: header),
                    .init(path: "document.json", data: JSONSerialization.data(withJSONObject: json))])
            }
            #expect(throws: (any Error).self) { _ = try store.loadDocument(from: BorrowedBytes(bytes)) }
        }
    }
    @Test(.timeLimit(.minutes(1)))
    func independentSingleProductIdentifierAndNullableOnlyMetadataSurviveRoundTrips() throws {
        let exchange = STEPExchange(tolerance: .standard), evaluator = DocumentEvaluator(tolerance: .standard)
        let ordinary = try exchange.import(Data(Self.singleProductFixture.utf8))
        #expect(ordinary.document?.assembly == nil)
        #expect(try exchange.import(Data(Self.singleProductFixture.utf8)).brep == ordinary.brep)
        let variants = [
            Self.singleProductFixture.replacingOccurrences(of: "PRODUCT('SWIFTCAD'", with: "PRODUCT('part'"),
            Self.singleProductFixture.replacingOccurrences(of: "PRODUCT('SWIFTCAD'", with: "PRODUCT(''"),
            Self.singleProductFixture.replacingOccurrences(of: "PRODUCT('SWIFTCAD'", with: "PRODUCT('11111111-1111-4111-8111-111111111111'"),
            Self.singleProductFixture.replacingOccurrences(of: "PRODUCT_DEFINITION('design'", with: "PRODUCT_DEFINITION(''"),
            Self.singleProductFixture.replacingOccurrences(of: "PRODUCT_DEFINITION('design'", with: "PRODUCT_DEFINITION('22222222-2222-4222-8222-222222222222'"),
            Self.singleProductFixture.replacingOccurrences(of: "PRODUCT('SWIFTCAD','',''", with: "PRODUCT('SWIFTCAD','',$"),
            Self.singleProductFixture.replacingOccurrences(of: "PRODUCT_DEFINITION_FORMATION('',''", with: "PRODUCT_DEFINITION_FORMATION('',$"),
            Self.singleProductFixture.replacingOccurrences(of: "PRODUCT_DEFINITION('design',''", with: "PRODUCT_DEFINITION('design',$")]
        for literal in variants {
            let source = try imported(literal), assembly = try #require(source.assembly)
            #expect(assembly.products.count == 1 && assembly.formations.count == 1 && assembly.definitions.count == 1)
            let product = assembly.products[0], formation = assembly.formations[0], definition = assembly.definitions[0]
            #expect(product.id.description != product.identifier && definition.id.description != definition.identifier)
            let sink = DataByteSink()
            try exchange.write(evaluator.evaluateExact(source), to: sink)
            let restored = try #require(exchange.import(sink.bytes).document), graph = try #require(restored.assembly)
            #expect(graph.products == assembly.products && graph.formations == assembly.formations)
            let view = try #require(graph.definitions.first)
            #expect(view.id == definition.id && view.identifier.utf8.elementsEqual(definition.identifier.utf8))
            if let description = definition.definitionDescription {
                let retained = try #require(view.definitionDescription)
                #expect(retained.utf8.elementsEqual(description.utf8))
            } else { #expect(view.definitionDescription == nil) }
            let native = DataByteSink(), store = NativePackageStore(tolerance: .standard)
            try store.writePackage(for: source, to: native)
            #expect(try store.loadDocument(from: native.bytes) == source)
        }
    }
    @Test(.timeLimit(.minutes(1)))
    func explicitIdentityDecoderRetainsExactCallerWorkAndTextCeilings() throws {
        let entities = [
            1: "PRODUCT('part','shared',$,(#9))",
            2: "EXTERNAL_SOURCE(IDENTIFIER('urn:swiftcad:assembly-source-id'))",
            3: "IDENTIFICATION_ROLE('product',$)",
            4: "APPLIED_EXTERNAL_IDENTIFICATION_ASSIGNMENT('11111111-1111-4111-8111-111111111111',#3,#2,(#1))"]
        let fields: any STEPFieldReading = STEPAssemblySyntax(entities: entities)
        let names = [1: "PRODUCT", 2: "EXTERNAL_SOURCE", 3: "IDENTIFICATION_ROLE", 4: "APPLIED_EXTERNAL_IDENTIFICATION_ASSIGNMENT"]
        let reader: any STEPSourceIdentityReading = STEPSourceIdentityReader()
        let deadline = ExchangeProcessingBudget(maximumDuration: .seconds(30))
        let admitted = try reader.read(fields: fields, names: names, processingBudget: deadline, limits: .standard,
            remainingWork: 10000, remainingTextBytes: 10000)
        #expect(admitted.values[1]?.uuidString == "11111111-1111-4111-8111-111111111111")
        let exact = try reader.read(fields: fields, names: names, processingBudget: deadline, limits: .standard,
            remainingWork: admitted.consumedWork, remainingTextBytes: admitted.textBytes)
        #expect(exact.values == admitted.values)
        #expect(throws: STEPStringError.resourceLimitExceeded) {
            _ = try reader.read(fields: fields, names: names, processingBudget: deadline, limits: .standard,
                remainingWork: admitted.consumedWork - 1, remainingTextBytes: admitted.textBytes)
        }
        #expect(throws: STEPStringError.resourceLimitExceeded) {
            _ = try reader.read(fields: fields, names: names, processingBudget: deadline, limits: .standard,
                remainingWork: admitted.consumedWork, remainingTextBytes: admitted.textBytes - 1)
        }
    }
    @Test(.timeLimit(.minutes(1)))
    func cancelledPublicSharedProductImportDoesNotPublishSource() async throws {
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try STEPExchange(tolerance: .standard).import(Data(Self.fixture.utf8))
        }
        do { _ = try await task.value; Issue.record("Cancelled shared product import published source.") }
        catch is CancellationError {}
    }
    // Product/formation/definition/usage/identity records are independently authored standard literals.
    // Exact triangle records retain the independently authored coedge/p-curve charts of the sibling fixture.
    // No production writer creates this fixture or its negative variants.
    private static let fixture = #"""
ISO-10303-21;
HEADER;
FILE_DESCRIPTION(('Independent shared PRODUCT and formation'),'2;1');
FILE_NAME('shared.step','2000-01-01T00:00:00',(''),(''),'fixture','','');
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
#8=(GEOMETRIC_REPRESENTATION_CONTEXT(3) GLOBAL_UNIT_ASSIGNED_CONTEXT((#4,#5,#6)) REPRESENTATION_CONTEXT('parent',''));
#9=(GEOMETRIC_REPRESENTATION_CONTEXT(3) GLOBAL_UNIT_ASSIGNED_CONTEXT((#4,#5,#6)) REPRESENTATION_CONTEXT('second view',''));
#50=PRODUCT('part','shared \X2\90E854C1\X0\','product description',(#2));
#51=PRODUCT_DEFINITION_FORMATION_WITH_SPECIFIED_SOURCE('v1','formation description',#50,.MADE.);
#52=PRODUCT_DEFINITION('design','first view description',#51,#3);
#53=PRODUCT_DEFINITION_SHAPE('','',#52);
#54=SHAPE_REPRESENTATION('',(#38,#17),#7);
#55=SHAPE_DEFINITION_REPRESENTATION(#53,#54);
#62=PRODUCT_DEFINITION('analysis',$,#51,#3);
#63=PRODUCT_DEFINITION_SHAPE('','',#62);
#64=SHAPE_REPRESENTATION('',(#238,#17),#9);
#65=SHAPE_DEFINITION_REPRESENTATION(#63,#64);
#70=PRODUCT('parent','real parent',$,(#2));
#71=PRODUCT_DEFINITION_FORMATION('',$,#70);
#72=PRODUCT_DEFINITION('77777777-7777-4777-8777-777777777777','parent view',#71,#3);
#73=PRODUCT_DEFINITION_SHAPE('','',#72);
#74=SHAPE_REPRESENTATION('',(#17,#82),#8);
#75=SHAPE_DEFINITION_REPRESENTATION(#73,#74);
#80=CARTESIAN_POINT('',(30.,100.,0.));
#82=AXIS2_PLACEMENT_3D('',#80,#13,#14);
#83=NEXT_ASSEMBLY_USAGE_OCCURRENCE('first','first usage','',#72,#52,$);
#84=PRODUCT_DEFINITION_SHAPE('','',#83);
#85=ITEM_DEFINED_TRANSFORMATION('','',#17,#17);
#86=(REPRESENTATION_RELATIONSHIP('','',#54,#74) REPRESENTATION_RELATIONSHIP_WITH_TRANSFORMATION(#85) SHAPE_REPRESENTATION_RELATIONSHIP());
#87=CONTEXT_DEPENDENT_SHAPE_REPRESENTATION(#86,#84);
#90=NEXT_ASSEMBLY_USAGE_OCCURRENCE('second','second usage','',#72,#62,$);
#91=PRODUCT_DEFINITION_SHAPE('','',#90);
#92=ITEM_DEFINED_TRANSFORMATION('','',#17,#82);
#93=(REPRESENTATION_RELATIONSHIP('','',#64,#74) REPRESENTATION_RELATIONSHIP_WITH_TRANSFORMATION(#92) SHAPE_REPRESENTATION_RELATIONSHIP());
#94=CONTEXT_DEPENDENT_SHAPE_REPRESENTATION(#93,#91);
#600=EXTERNAL_SOURCE(IDENTIFIER('urn:swiftcad:assembly-source-id'));
#601=IDENTIFICATION_ROLE('product',$);
#602=IDENTIFICATION_ROLE('formation',$);
#603=IDENTIFICATION_ROLE('definition',$);
#604=APPLIED_EXTERNAL_IDENTIFICATION_ASSIGNMENT('11111111-1111-4111-8111-111111111111',#601,#600,(#50));
#605=APPLIED_EXTERNAL_IDENTIFICATION_ASSIGNMENT('22222222-2222-4222-8222-222222222222',#602,#600,(#51));
#606=APPLIED_EXTERNAL_IDENTIFICATION_ASSIGNMENT('33333333-3333-4333-8333-333333333333',#603,#600,(#52));
#607=APPLIED_EXTERNAL_IDENTIFICATION_ASSIGNMENT('44444444-4444-4444-8444-444444444444',#603,#600,(#62));
ENDSEC;
END-ISO-10303-21;
"""#
    // Independent one-PD standard literal with the exact authored bare metadata profile.
    // Variant edits affect only identifiers/nullability; geometry and associations are unchanged.
    private static let singleProductFixture = #"""
ISO-10303-21;
HEADER;
FILE_DESCRIPTION(('Independent single product metadata'),'2;1');
FILE_NAME('single.step','2000-01-01T00:00:00',(''),(''),'fixture','','');
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
#50=PRODUCT('SWIFTCAD','','',(#2));
#51=PRODUCT_DEFINITION_FORMATION('','',#50);
#52=PRODUCT_DEFINITION('design','',#51,#3);
#53=PRODUCT_DEFINITION_SHAPE('','',#52);
#54=SHAPE_REPRESENTATION('',(#38,#17),#7);
#55=SHAPE_DEFINITION_REPRESENTATION(#53,#54);
ENDSEC;
END-ISO-10303-21;
"""#
}
