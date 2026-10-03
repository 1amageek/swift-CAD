import Foundation
import Testing
import CADCore
import CADIR
import CADKernel
import CADTopology
@testable import CADExchange

@Suite("Shared STEP representation and PD-scoped physical source")
struct SharedSTEPRepresentationTests {
    private func imported(_ literal: String = Self.fixture) throws -> CADDocument {
        try #require(STEPExchange(tolerance: .standard).import(Data(literal.utf8)).document)
    }
    private func entities(_ bytes: Data) throws -> [Int: String] {
        let text = try #require(String(data: bytes, encoding: .utf8))
        var result: [Int: String] = [:]
        for line in text.split(separator: "\n") where line.first == "#" {
            let separator = try #require(line.firstIndex(of: "="))
            let id = try #require(Int(line[line.index(after: line.startIndex)..<separator]))
            #expect(line.last == ";")
            let value = String(line[line.index(after: separator)..<line.index(before: line.endIndex)])
            #expect(result.updateValue(value, forKey: id) == nil)
        }
        return result
    }
    private func inspect(_ document: CADDocument) throws {
        let source = try #require(document.assembly)
        let leaves = source.definitions.filter { !$0.features.isEmpty }
        #expect(leaves.count == 2 && leaves[0].features == leaves[1].features && leaves[0].features.count == 1)
        #expect(document.designGraph.nodes.count == 1)
        #expect(Set(leaves.map(\.id.description)) == ["33333333-3333-4333-8333-333333333333", "44444444-4444-4444-8444-444444444444"])
        #expect(leaves.first { $0.identifier == "design" }?.definitionDescription == "first view description")
        #expect(leaves.first { $0.identifier == "analysis" }?.definitionDescription == nil)
        let evaluated = try DocumentEvaluator(tolerance: .standard).evaluateExact(document)
        let artifact = try #require(evaluated.assembly)
        #expect(artifact.local.model.bodies.count == 1 && artifact.local.model.faces.count == 1)
        #expect(evaluated.brep.bodies.count == 2 && evaluated.brep.faces.count == 2)
        for (x, y) in [(0.0,0.0),(0.04,0.0),(0.0,0.02),(0.03,0.1),(0.07,0.1),(0.03,0.12)] {
            #expect(evaluated.brep.vertices.values.contains { abs($0.point.x-x) < 1e-12 && abs($0.point.y-y) < 1e-12 && abs($0.point.z) < 1e-12 })
        }
        let view = try ProductAttributeResolver().resolve(evaluated)
        let densityAssignments = document.productAttributes.assignments.filter { $0.value.property == .density }
        #expect(densityAssignments.count == 2 && densityAssignments.allSatisfy { $0.target.definitionID != nil && $0.target.path == nil })
        let layer = try #require(document.productAttributes.layers.first { $0.name == "common face" })
        for occurrence in artifact.occurrences where !occurrence.features.isEmpty {
            let first = occurrence.definitionID.description == "33333333-3333-4333-8333-333333333333"
            let feature = try #require(occurrence.features.first)
            let face = try #require(feature.faces.values.first)
            let properties = try #require(view.values[ResolvedProductTarget(topology: .face(face), definitionID: occurrence.definitionID, path: occurrence.path)])
            #expect(properties.properties[.density]?.value == .density(PhysicalDensity(kilogramsPerCubicMeter: first ? 1000 : 2000)))
            #expect(properties.properties[.color]?.value == .color(first ? ColorRGBA(r: 1,g: 0,b: 0,a: 1) : ColorRGBA(r: 0,g: 1,b: 0,a: 1)))
            #expect(properties.properties[.color]?.assignmentChain.count == (first ? 2 : 3))
            #expect(properties.layers.contains(layer.id))
            #expect(properties.properties[.name]?.value == .name("face alpha"))
            let body = try #require(feature.bodies.values.first)
            let bodyProperties = try #require(view.values[ResolvedProductTarget(topology: .body(body), definitionID: occurrence.definitionID, path: occurrence.path)])
            #expect(bodyProperties.properties[.density] == nil)
        }
    }
    @Test(.timeLimit(.minutes(1)))
    func independentSharedRepresentationPreservesPDScopesAcrossNativeAndTwoSTEPGenerations() throws {
        var current = try imported()
        try inspect(current)
        let store = NativePackageStore(tolerance: .standard), native = DataByteSink()
        try store.writePackage(for: current, to: native)
        #expect(try store.loadDocument(from: native.bytes) == current)
        for _ in 0..<2 {
            let sink = DataByteSink(), evaluated = try DocumentEvaluator(tolerance: .standard).evaluate(current)
            try OfficialFormatExchange(tolerance: .standard).write(evaluated, as: .step, to: sink)
            let table = try entities(sink.bytes), syntax = STEPAssemblySyntax(entities: table)
            var geometryRepresentations: [Int] = []
            for id in table.keys where try syntax.name(id) == "SHAPE_DEFINITION_REPRESENTATION" {
                let a = try syntax.arguments(id), rep = try syntax.reference(a[1])
                let ra = try syntax.arguments(rep)
                let items = try syntax.list(ra[1])
                if try items.contains(where: { try syntax.name($0) == "SHELL_BASED_SURFACE_MODEL" }) { geometryRepresentations.append(rep) }
            }
            #expect(geometryRepresentations.count == 2 && Set(geometryRepresentations).count == 1)
            #expect(try table.keys.filter { try syntax.name($0) == "ADVANCED_FACE" }.count == 1)
            #expect(try table.keys.filter { try syntax.name($0) == "SHELL_BASED_SURFACE_MODEL" }.count == 1)
            let usages = try table.keys.filter { try syntax.name($0) == "GEOMETRIC_ITEM_SPECIFIC_USAGE" }
            #expect(usages.count == 2)
            var usageViews = Set<Int>(), identifiedItems = Set<Int>(), aspectKeys = Set<Int>()
            for usage in usages {
                let a = try syntax.arguments(usage), view = try syntax.reference(a[3]), item = try syntax.reference(a[4])
                #expect(usageViews.insert(view).inserted)
                #expect(aspectKeys.insert(try syntax.reference(a[2])).inserted)
                identifiedItems.insert(item)
                #expect(try syntax.name(view) == "SHAPE_REPRESENTATION")
                #expect(try syntax.list(syntax.arguments(view)[1]) == [item])
                #expect(!geometryRepresentations.contains(view))
            }
            #expect(identifiedItems.count == 1)
            current = try #require(OfficialFormatExchange(tolerance: .standard).import(BorrowedBytes(sink.bytes), as: .step).document)
            try inspect(current)
        }
    }
    @Test(.timeLimit(.minutes(1)))
    func distinctPDPartCarriersShareOneUnassociatedInnerGeometryAndKeepOccurrenceOverride() throws {
        var document = try imported()
        document.productAttributes.assignments.removeAll { $0.value.property == .color || $0.value.property == .opacity }
        let leaves = try #require(document.assembly).definitions.filter { !$0.features.isEmpty }.sorted { $0.id < $1.id }
        let first = ProductAttributeAssignment(target: ProductAttributeTarget(kind: .part, definitionID: leaves[0].id), value: .color(ColorRGBA(r: 0,g: 0,b: 1,a: 1)))
        let second = ProductAttributeAssignment(target: ProductAttributeTarget(kind: .part, definitionID: leaves[1].id), value: .color(ColorRGBA(r: 1,g: 0,b: 0,a: 1)))
        document.productAttributes.assignments += [first, second]
        document.productAttributes.layers.append(ProductLayer(name: "first part", members: [first.target]))
        let evaluator = DocumentEvaluator(tolerance: .standard), resolver = ProductAttributeResolver()
        let base = try evaluator.evaluateExact(document), artifact = try #require(base.assembly)
        let key = try #require(artifact.local.subshapes.entries.keys.sorted().first { key in
            if let topology = artifact.local.subshapes.entries[key], case .face = topology { return true }; return false
        })
        let reference = try resolver.sourceReference(for: key, in: base)
        let path = try #require(artifact.occurrences.first { $0.definitionID == leaves[0].id }?.path)
        document.productAttributes.assignments.append(ProductAttributeAssignment(target: ProductAttributeTarget(kind: .face, geometry: reference, path: path),
            value: .color(ColorRGBA(r: 0,g: 1,b: 0,a: 1)), overrides: first.id))
        let sink = DataByteSink()
        try STEPExchange(tolerance: .standard).write(evaluator.evaluateExact(document), to: sink)
        let table = try entities(sink.bytes), syntax = STEPAssemblySyntax(entities: table)
        let maps = try table.keys.filter { try syntax.name($0) == "REPRESENTATION_MAP" }
        #expect(maps.count == 2)
        let inner = try maps.map { try syntax.reference(syntax.arguments($0)[1]) }
        #expect(Set(inner).count == 1)
        #expect(try table.keys.filter { try syntax.name($0) == "ADVANCED_FACE" }.count == 1)
        let restored = try #require(STEPExchange(tolerance: .standard).import(sink.bytes).document)
        #expect(restored.designGraph.nodes.count == 1)
        let evaluated = try evaluator.evaluateExact(restored), view = try resolver.resolve(evaluated)
        for occurrence in try #require(evaluated.assembly).occurrences where !occurrence.features.isEmpty {
            let face = try #require(occurrence.features.first?.faces.values.first)
            let properties = try #require(view.values[ResolvedProductTarget(topology: .face(face), definitionID: occurrence.definitionID, path: occurrence.path)])
            #expect(properties.properties[.color]?.value == .color(occurrence.definitionID == leaves[0].id ? ColorRGBA(r: 0,g: 1,b: 0,a: 1) : ColorRGBA(r: 1,g: 0,b: 0,a: 1)))
            #expect(properties.properties[.color]?.assignmentChain.count == (occurrence.definitionID == leaves[0].id ? 2 : 1))
        }
    }
    @Test(.timeLimit(.minutes(1)))
    func foreignGISUMembershipSharedCarrierAndGlobalPhysicalScopeRefuseAtomically() throws {
        let foreign = Self.fixture.replacingOccurrences(of: "#702,#744,#36", with: "#702,#74,#36")
        #expect(throws: ProductAttributeError.missingTarget("Shape aspect geometry correspondence.")) { _ = try imported(foreign) }
        let carrier = Self.fixture.replacingOccurrences(of: "SHAPE_REPRESENTATION('',(#38,#17),#7)", with: "SHAPE_REPRESENTATION('',(#801,#17),#7)")
            .replacingOccurrences(of: "ENDSEC;\nEND-ISO", with: "#800=REPRESENTATION_MAP(#17,#810);\n#801=MAPPED_ITEM('',#800,#802);\n#802=CARTESIAN_TRANSFORMATION_OPERATOR_3D('',*,*,#14,#803,#10,1.,#13);\n#803=DIRECTION('',(0.,1.,0.));\n#810=SHAPE_REPRESENTATION('',(#38,#17),#7);\nENDSEC;\nEND-ISO")
        #expect(throws: ProductAttributeError.unsupportedSemantics("A whole-part carrier cannot select several definitions.")) { _ = try imported(carrier) }
        var document = try imported()
        let scoped = try #require(document.productAttributes.assignments.first { $0.value.property == .density })
        document.productAttributes.assignments.removeAll { $0.value.property == .density }
        document.productAttributes.assignments.append(ProductAttributeAssignment(target: ProductAttributeTarget(kind: scoped.target.kind, geometry: scoped.target.geometry), value: scoped.value))
        let evaluated = try DocumentEvaluator(tolerance: .standard).evaluate(document)
        let sink = DataByteSink()
        #expect(throws: ProductAttributeError.unsupportedSemantics("Global physical geometry requires a standard source-scope owner.")) {
            try OfficialFormatExchange(tolerance: .standard).write(evaluated, as: .step, to: sink)
        }
        #expect(sink.bytes.isEmpty)
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { do { try FileManager.default.removeItem(at: directory) } catch { Issue.record("Unable to remove shared representation fixture directory: \(error)") } }
        let url = directory.appendingPathComponent("shared.step"), original = Data("existing complete destination".utf8)
        try original.write(to: url)
        #expect(throws: ProductAttributeError.self) { try OfficialFormatExchange(tolerance: .standard).export(evaluated, as: .step, to: url) }
        #expect(try Data(contentsOf: url) == original)
        // A single current PD cannot turn a global source attachment into an explicit PD selector.
        let originalAssembly = try #require(document.assembly)
        let selected = try #require(originalAssembly.definitions.first { $0.id == scoped.target.definitionID })
        let formation = try #require(originalAssembly.formations.first { $0.id == selected.formationID })
        let product = try #require(originalAssembly.products.first { $0.id == formation.productID })
        document.assembly = DocumentAssembly(products: [product], formations: [formation], definitions: [selected],
            roots: [AssemblyOccurrence(definitionID: selected.id)])
        document.productAttributes = ProductAttributes(assignments: [ProductAttributeAssignment(
            target: ProductAttributeTarget(kind: scoped.target.kind, geometry: scoped.target.geometry), value: scoped.value)])
        let single = try DocumentEvaluator(tolerance: .standard).evaluate(document), singleSink = DataByteSink()
        #expect(throws: ProductAttributeError.unsupportedSemantics("Global physical geometry requires a standard source-scope owner.")) {
            try OfficialFormatExchange(tolerance: .standard).write(single, as: .step, to: singleSink)
        }
        #expect(singleSink.bytes.isEmpty)
        #expect(throws: ProductAttributeError.self) { try OfficialFormatExchange(tolerance: .standard).export(single, as: .step, to: url) }
        #expect(try Data(contentsOf: url) == original)
        #expect(throws: (any Error).self) { _ = try STEPExchange(tolerance: .standard, resourceLimits: ExchangeResourceLimits(maximumIterations: 10)).import(Data(Self.fixture.utf8)) }
    }
    @Test(.timeLimit(.minutes(1)))
    func bareMappedSharedRepresentationCannotChooseAnArbitraryPD() throws {
        var records: [String] = []
        for line in Self.fixture.split(separator: "\n") {
            if line.first == "#", let separator = line.firstIndex(of: "="),
               let id = Int(line[line.index(after: line.startIndex)..<separator]), (83...94).contains(id) { continue }
            records.append(String(line))
        }
        let literal = records.joined(separator: "\n")
            .replacingOccurrences(of: "SHAPE_REPRESENTATION('',(#17,#82),#8)", with: "SHAPE_REPRESENTATION('',(#17,#82,#805),#8)")
            .replacingOccurrences(of: "ENDSEC;\nEND-ISO", with: "#804=REPRESENTATION_MAP(#17,#54);\n#805=MAPPED_ITEM('',#804,#82);\nENDSEC;\nEND-ISO")
        #expect(throws: AssemblyError.invalidSource("STEP mapped item has an ambiguous or missing product definition.")) { _ = try imported(literal) }
    }
    @Test(.timeLimit(.minutes(1)))
    func singletonPhysicalViewsRejectMalformedUnitsMembershipAndDuplicateUsages() throws {
        let malformed = Self.fixture.replacingOccurrences(of: "SHAPE_REPRESENTATION('',(#36),#9)", with: "SHAPE_REPRESENTATION('',(#36,#38),#9)")
        #expect(throws: ProductAttributeError.invalidSource("Physical target view must contain exactly its identified item.")) { _ = try imported(malformed) }
        let wrongUnit = Self.fixture.replacingOccurrences(of: "SHAPE_REPRESENTATION('',(#36),#9)", with: "SHAPE_REPRESENTATION('',(#36),#746)")
            .replacingOccurrences(of: "ENDSEC;\nEND-ISO", with: "#745=(LENGTH_UNIT() NAMED_UNIT(*) SI_UNIT($,.METRE.));\n#746=(GEOMETRIC_REPRESENTATION_CONTEXT(3) GLOBAL_UNIT_ASSIGNED_CONTEXT((#745,#5,#6)) REPRESENTATION_CONTEXT('view',''));\nENDSEC;\nEND-ISO")
        #expect(throws: ProductAttributeError.invalidSource("Physical target view has conflicting owned units.")) { _ = try imported(wrongUnit) }
        let foreignPD = Self.fixture.replacingOccurrences(of: "SHAPE_ASPECT('','',#63,.T.)", with: "SHAPE_ASPECT('','',#73,.T.)")
        #expect(throws: ProductAttributeError.missingTarget("Shape aspect geometry correspondence.")) { _ = try imported(foreignPD) }
        let duplicateItem = Self.fixture.replacingOccurrences(of: "#702,#744,#36", with: "#702,#743,#36")
        #expect(throws: ProductAttributeError.invalidSource("Duplicate GISU representation/item or representation/definition usage.")) { _ = try imported(duplicateItem) }
        // Both body and face belong to #54; using the same shape aspect twice violates UR2 even with distinct identified items.
        let duplicateDefinition = Self.fixture.replacingOccurrences(of: "#700,#743,#36", with: "#700,#54,#38")
            .replacingOccurrences(of: "#702,#744,#36", with: "#700,#54,#36")
        #expect(throws: ProductAttributeError.invalidSource("Duplicate GISU representation/item or representation/definition usage.")) { _ = try imported(duplicateDefinition) }
    }
    @Test(.timeLimit(.minutes(1)))
    func samePhysicalTargetReusesOneGISUForMaterialAndDensity() throws {
        let literal = Self.fixture.replacingOccurrences(of: "ENDSEC;\nEND-ISO", with: "#750=DESCRIPTIVE_REPRESENTATION_ITEM('steel','explicit physical descriptor');\n#751=PROPERTY_DEFINITION('material property','material name',#700);\n#752=REPRESENTATION('material name',(#750),#7);\n#753=PROPERTY_DEFINITION_REPRESENTATION(#751,#752);\nENDSEC;\nEND-ISO")
        let document = try imported(literal), evaluator = DocumentEvaluator(tolerance: .standard)
        let material = try #require(document.productAttributes.materials.first)
        #expect(material.name == "steel" && material.description == "explicit physical descriptor")
        #expect(material.density == PhysicalDensity(kilogramsPerCubicMeter: 1000))
        let assignment = try #require(document.productAttributes.assignments.first { $0.value == .material(material.id) })
        #expect(assignment.target.kind == .face && assignment.target.definitionID?.description == "33333333-3333-4333-8333-333333333333")
        let sink = DataByteSink(); try STEPExchange(tolerance: .standard).write(evaluator.evaluateExact(document), to: sink)
        let table = try entities(sink.bytes), syntax = STEPAssemblySyntax(entities: table)
        #expect(try table.keys.filter { try syntax.name($0) == "GEOMETRIC_ITEM_SPECIFIC_USAGE" }.count == 2)
        let restored = try imported(try #require(String(data: sink.bytes, encoding: .utf8)))
        let restoredMaterial = try #require(restored.productAttributes.materials.first)
        #expect(restoredMaterial.name == material.name && restoredMaterial.density == material.density)
        let retained = restored.productAttributes.assignments.filter { $0.target.definitionID?.description == "33333333-3333-4333-8333-333333333333" && ($0.value.property == .material || $0.value.property == .density) }
        #expect(retained.count == 2 && retained[0].target == retained[1].target)
    }
    @Test(.timeLimit(.minutes(1)))
    func partialFeatureGroupOverlapRefusesBeforeSTEPPublication() throws {
        var document = try imported()
        document.productAttributes = ProductAttributes()
        let extraID = FeatureID(), extra = FeatureNode(id: extraID, operation: .primitive(PrimitiveFeature(definition: .box(BoxPrimitive(
            width: .constant(.length(1, unit: .millimeter)), depth: .constant(.length(2, unit: .millimeter)),
            height: .constant(.length(3, unit: .millimeter)))))), outputs: [FeatureOutput(role: .body)])
        document.designGraph.nodes[extraID] = extra; document.designGraph.order.append(extraID)
        var source = try #require(document.assembly)
        let index = try #require(source.definitions.firstIndex { $0.identifier == "analysis" })
        source.definitions[index].features.append(extraID); document.assembly = source
        let evaluated = try DocumentEvaluator(tolerance: .standard).evaluate(document)
        #expect(evaluated.assembly?.local.model.bodies.count == 2 && evaluated.brep.bodies.count == 3)
        let sink = DataByteSink()
        #expect(throws: ProductAttributeError.unsupportedSemantics("Partially overlapping feature groups require modular STEP geometry transport.")) {
            try OfficialFormatExchange(tolerance: .standard).write(evaluated, as: .step, to: sink)
        }
        #expect(sink.bytes.isEmpty)
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { do { try FileManager.default.removeItem(at: directory) } catch { Issue.record("Unable to remove partial-group fixture directory: \(error)") } }
        let url = directory.appendingPathComponent("partial.step"), original = Data("existing exact output".utf8)
        try original.write(to: url)
        #expect(throws: ProductAttributeError.self) { try OfficialFormatExchange(tolerance: .standard).export(evaluated, as: .step, to: url) }
        #expect(try Data(contentsOf: url) == original)
    }
    @Test(.timeLimit(.minutes(1)))
    func cancelledSharedRepresentationImportDoesNotPublishSource() async throws {
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try STEPExchange(tolerance: .standard).import(Data(Self.fixture.utf8))
        }
        do { _ = try await task.value; Issue.record("Cancelled shared representation import published source.") }
        catch is CancellationError {}
    }
    // Independently authored standard literal: two PD/PDS associations share one exact triangle representation.
    // No production writer constructs this source or its negative variants.
    private static let fixture = #"""
ISO-10303-21;
HEADER;
FILE_DESCRIPTION(('Independent shared exact shape representation'),'2;1');
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
#65=SHAPE_DEFINITION_REPRESENTATION(#63,#54);
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
#93=(REPRESENTATION_RELATIONSHIP('','',#54,#74) REPRESENTATION_RELATIONSHIP_WITH_TRANSFORMATION(#92) SHAPE_REPRESENTATION_RELATIONSHIP());
#94=CONTEXT_DEPENDENT_SHAPE_REPRESENTATION(#93,#91);
#600=EXTERNAL_SOURCE(IDENTIFIER('urn:swiftcad:assembly-source-id'));
#601=IDENTIFICATION_ROLE('product',$);
#602=IDENTIFICATION_ROLE('formation',$);
#603=IDENTIFICATION_ROLE('definition',$);
#604=APPLIED_EXTERNAL_IDENTIFICATION_ASSIGNMENT('11111111-1111-4111-8111-111111111111',#601,#600,(#50));
#605=APPLIED_EXTERNAL_IDENTIFICATION_ASSIGNMENT('22222222-2222-4222-8222-222222222222',#602,#600,(#51));
#606=APPLIED_EXTERNAL_IDENTIFICATION_ASSIGNMENT('33333333-3333-4333-8333-333333333333',#603,#600,(#52));
#607=APPLIED_EXTERNAL_IDENTIFICATION_ASSIGNMENT('44444444-4444-4444-8444-444444444444',#603,#600,(#62));
#700=SHAPE_ASPECT('','',#53,.T.);
#701=GEOMETRIC_ITEM_SPECIFIC_USAGE('','',#700,#743,#36);
#702=SHAPE_ASPECT('','',#63,.T.);
#703=GEOMETRIC_ITEM_SPECIFIC_USAGE('','',#702,#744,#36);
#704=(MASS_UNIT() NAMED_UNIT(*) SI_UNIT(.KILO.,.GRAM.));
#705=(LENGTH_UNIT() NAMED_UNIT(*) SI_UNIT($,.METRE.));
#706=DERIVED_UNIT_ELEMENT(#704,1.);
#707=DERIVED_UNIT_ELEMENT(#705,-3.);
#708=DERIVED_UNIT((#706,#707));
#709=(MEASURE_REPRESENTATION_ITEM() MEASURE_WITH_UNIT(MASS_DENSITY_MEASURE(1000.),#708) REPRESENTATION_ITEM('density'));
#710=PROPERTY_DEFINITION('material property','density',#700);
#711=REPRESENTATION('density',(#709),#7);
#712=PROPERTY_DEFINITION_REPRESENTATION(#710,#711);
#713=(MEASURE_REPRESENTATION_ITEM() MEASURE_WITH_UNIT(MASS_DENSITY_MEASURE(2000.),#708) REPRESENTATION_ITEM('density'));
#714=PROPERTY_DEFINITION('material property','density',#702);
#715=REPRESENTATION('density',(#713),#7);
#716=PROPERTY_DEFINITION_REPRESENTATION(#714,#715);
#717=COLOUR_RGB('',0.,0.,1.);
#718=FILL_AREA_STYLE_COLOUR('',#717);
#719=FILL_AREA_STYLE('',(#718));
#720=SURFACE_STYLE_FILL_AREA(#719);
#721=SURFACE_SIDE_STYLE('',(#720));
#722=SURFACE_STYLE_USAGE(.BOTH.,#721);
#723=PRESENTATION_STYLE_ASSIGNMENT((#722));
#724=STYLED_ITEM('',(#723),#38);
#725=COLOUR_RGB('',1.,0.,0.);
#726=FILL_AREA_STYLE_COLOUR('',#725);
#727=FILL_AREA_STYLE('',(#726));
#728=SURFACE_STYLE_FILL_AREA(#727);
#729=SURFACE_SIDE_STYLE('',(#728));
#730=SURFACE_STYLE_USAGE(.BOTH.,#729);
#731=PRESENTATION_STYLE_ASSIGNMENT((#730));
#732=OVER_RIDING_STYLED_ITEM('',(#731),#36,#724);
#733=COLOUR_RGB('',0.,1.,0.);
#734=FILL_AREA_STYLE_COLOUR('',#733);
#735=FILL_AREA_STYLE('',(#734));
#736=SURFACE_STYLE_FILL_AREA(#735);
#737=SURFACE_SIDE_STYLE('',(#736));
#738=SURFACE_STYLE_USAGE(.BOTH.,#737);
#739=PRESENTATION_STYLE_ASSIGNMENT((#738));
#740=CONTEXT_DEPENDENT_OVER_RIDING_STYLED_ITEM('',(#739),#36,#732,(#93));
#741=DRAUGHTING_MODEL('',(#724,#732,#740),#7);
#742=PRESENTATION_LAYER_ASSIGNMENT('common face','shared item layer',(#36));
#743=SHAPE_REPRESENTATION('',(#36),#7);
#744=SHAPE_REPRESENTATION('',(#36),#9);
ENDSEC;
END-ISO-10303-21;
"""#
}
