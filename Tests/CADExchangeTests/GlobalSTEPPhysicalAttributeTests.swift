import Foundation
import Testing
import CADCore
import CADGeometry
import CADIR
import CADKernel
import CADTopology
@testable import CADExchange

@Suite("Global STEP physical item characterization")
struct GlobalSTEPPhysicalAttributeTests {
    private func literal(item: Int, base: String = Self.geometryFixture) -> String {
        let properties = """
        #750=SHAPE_REPRESENTATION('',(#\(item)),#7);
        #751=CHARACTERIZED_ITEM_WITHIN_REPRESENTATION('',$,#\(item),#750);
        #752=PROPERTY_DEFINITION('material property','material name',#751);
        #753=DESCRIPTIVE_REPRESENTATION_ITEM('steel','global physical descriptor');
        #754=REPRESENTATION('material name',(#753),#7);
        #755=PROPERTY_DEFINITION_REPRESENTATION(#752,#754);
        #760=(MASS_UNIT() NAMED_UNIT(*) SI_UNIT(.KILO.,.GRAM.));
        #761=(LENGTH_UNIT() NAMED_UNIT(*) SI_UNIT($,.METRE.));
        #762=DERIVED_UNIT_ELEMENT(#760,1.);
        #763=DERIVED_UNIT_ELEMENT(#761,-3.);
        #764=DERIVED_UNIT((#762,#763));
        #765=(MEASURE_REPRESENTATION_ITEM() MEASURE_WITH_UNIT(MASS_DENSITY_MEASURE(7850.),#764) REPRESENTATION_ITEM('density'));
        #766=PROPERTY_DEFINITION('material property','density',#751);
        #767=REPRESENTATION('density',(#765),#7);
        #768=PROPERTY_DEFINITION_REPRESENTATION(#766,#767);
        """
        return base.replacingOccurrences(of: "ENDSEC;\nEND-ISO", with: properties + "\nENDSEC;\nEND-ISO")
    }
    private func imported(_ text: String) throws -> CADDocument {
        try #require(STEPExchange(tolerance: .standard).import(Data(text.utf8)).document)
    }
    private func inspect(_ document: CADDocument, kind: ProductAttributeTarget.Kind, count: Int) throws {
        let physical = document.productAttributes.assignments.filter { $0.value.property == .material || $0.value.property == .density }
        #expect(physical.count == 2)
        #expect(physical.allSatisfy { $0.target.kind == kind && $0.target.definitionID == nil && $0.target.path == nil && $0.target.usageID == nil })
        let material = try #require(document.productAttributes.materials.first)
        #expect(material.name == "steel" && material.description == "global physical descriptor")
        #expect(material.density == PhysicalDensity(kilogramsPerCubicMeter: 7850))
        #expect(physical.contains { $0.value == .descriptorDensity(material.id) })
        #expect(document.designGraph.nodes.count == 1)
        let evaluated = try DocumentEvaluator(tolerance: .standard).evaluateExact(document)
        #expect(evaluated.brep.bodies.count == count && evaluated.brep.faces.count == count)
        if let assembly = evaluated.assembly { #expect(assembly.local.model.bodies.count == 1 && assembly.local.model.faces.count == 1) }
        let resolved = try ProductAttributeResolver().resolve(evaluated)
        let faces = resolved.values.filter { if case .face = $0.key.topology { return true }; return false }
        #expect(faces.count == count)
        for properties in faces.values {
            #expect(properties.properties[.material]?.value == .material(material.id))
            #expect(properties.properties[.density]?.value == .density(PhysicalDensity(kilogramsPerCubicMeter: 7850)))
            #expect(properties.properties[.density]?.assignmentChain.count == 1)
        }
        let bodies = resolved.values.filter { if case .body = $0.key.topology { return true }; return false }
        #expect(bodies.count == count)
        if kind == .body { #expect(bodies.values.allSatisfy { $0.properties[.density]?.value == .density(PhysicalDensity(kilogramsPerCubicMeter: 7850)) }) }
        else { #expect(bodies.values.allSatisfy { $0.properties[.density] == nil && $0.properties[.material] == nil }) }
    }
    @Test(.timeLimit(.minutes(1)))
    func independentGlobalBodyAndFacePropertiesPersistAndFanOutToThirdPD() throws {
        for (item, kind) in [(38, ProductAttributeTarget.Kind.body), (36, .face)] {
            var document = try imported(literal(item: item))
            try inspect(document, kind: kind, count: 2)
            let store = NativePackageStore(tolerance: .standard), native = DataByteSink()
            try store.writePackage(for: document, to: native)
            #expect(try store.loadDocument(from: native.bytes) == document)
            for _ in 0..<2 {
                let sink = DataByteSink()
                try OfficialFormatExchange(tolerance: .standard).write(DocumentEvaluator(tolerance: .standard).evaluate(document), as: .step, to: sink)
                let emitted = try #require(String(data: sink.bytes, encoding: .utf8))
                #expect(emitted.components(separatedBy: "=CHARACTERIZED_ITEM_WITHIN_REPRESENTATION(").count - 1 == 1)
                #expect(emitted.components(separatedBy: "=ADVANCED_FACE(").count - 1 == 1)
                document = try imported(emitted); try inspect(document, kind: kind, count: 2)
            }
            var assembly = try #require(document.assembly)
            let leaf = try #require(assembly.definitions.first { !$0.features.isEmpty })
            let third = AssemblyDefinition(formationID: leaf.formationID, identifier: "third view", features: leaf.features)
            assembly.definitions.append(third)
            let parent = try #require(assembly.definitions.firstIndex { !$0.children.isEmpty })
            assembly.definitions[parent].children.append(AssemblyOccurrence(definitionID: third.id,
                placement: RigidTransform3D.translated(by: Vector3D(x: 0.2, y: 0.3, z: 0))))
            document.assembly = assembly
            try inspect(document, kind: kind, count: 3)
            let sink = DataByteSink(); try STEPExchange(tolerance: .standard).write(DocumentEvaluator(tolerance: .standard).evaluateExact(document), to: sink)
            let thirdSource = try imported(try #require(String(data: sink.bytes, encoding: .utf8)))
            try inspect(thirdSource, kind: kind, count: 3)
        }
    }
    @Test(.timeLimit(.minutes(1)))
    func independentNoProductGlobalGeometryKeepsOrdinarySourceRoute() throws {
        var records: [String] = []
        for line in Self.geometryFixture.split(separator: "\n") {
            if line.first == "#", let separator = line.firstIndex(of: "="), let id = Int(line[line.index(after: line.startIndex)..<separator]),
               (50...94).contains(id) || (600...607).contains(id) { continue }
            records.append(String(line))
        }
        let document = try imported(literal(item: 36, base: records.joined(separator: "\n")))
        #expect(document.assembly == nil)
        try inspect(document, kind: .face, count: 1)
        let sink = DataByteSink(); try STEPExchange(tolerance: .standard).write(DocumentEvaluator(tolerance: .standard).evaluateExact(document), to: sink)
        let emitted = try #require(String(data: sink.bytes, encoding: .utf8))
        #expect(emitted.contains("=PRODUCT('SWIFTCAD','','',"))
        let restored = try imported(emitted)
        #expect(restored.assembly == nil)
        try inspect(restored, kind: .face, count: 1)
        var named = document
        named.metadata.name = "ordinary physical product"
        let namedSink = DataByteSink()
        try STEPExchange(tolerance: .standard).write(DocumentEvaluator(tolerance: .standard).evaluateExact(named), to: namedSink)
        let namedText = try #require(String(data: namedSink.bytes, encoding: .utf8))
        #expect(namedText.contains("=PRODUCT('SWIFTCAD','ordinary physical product','',"))
        let namedSource = try imported(namedText)
        let namedAssembly = try #require(namedSource.assembly)
        #expect(namedAssembly.products.count == 1 && namedAssembly.products.first?.name == named.metadata.name)
        try inspect(namedSource, kind: .face, count: 1)
    }
    @Test(.timeLimit(.minutes(1)))
    func qualifiedDensityAndGlobalMaterialRemainDistinctAndCompetingDensityRefuses() throws {
        let base = literal(item: 36).replacingOccurrences(of: "#766=PROPERTY_DEFINITION('material property','density',#751);",
            with: "#766=PROPERTY_DEFINITION('material property','density',#780);")
            .replacingOccurrences(of: "ENDSEC;\nEND-ISO", with: "#779=SHAPE_REPRESENTATION('',(#36),#7);\n#780=SHAPE_ASPECT('','',#53,.T.);\n#781=GEOMETRIC_ITEM_SPECIFIC_USAGE('','',#780,#779,#36);\nENDSEC;\nEND-ISO")
        let document = try imported(base)
        let global = try #require(document.productAttributes.assignments.first { $0.value.property == .material })
        let scoped = try #require(document.productAttributes.assignments.first { $0.value.property == .density })
        #expect(global.target.definitionID == nil && scoped.target.definitionID?.description == "33333333-3333-4333-8333-333333333333")
        let evaluated = try DocumentEvaluator(tolerance: .standard).evaluateExact(document), resolved = try ProductAttributeResolver().resolve(evaluated)
        for (target, properties) in resolved.values where target.topology != nil {
            if case .face = target.topology {
                #expect(properties.properties[.material] != nil)
                #expect((properties.properties[.density] != nil) == (target.definitionID?.description == "33333333-3333-4333-8333-333333333333"))
            }
        }
        let sink = DataByteSink(); try STEPExchange(tolerance: .standard).write(evaluated, to: sink)
        let restored = try imported(try #require(String(data: sink.bytes, encoding: .utf8)))
        #expect(restored.productAttributes.assignments.first { $0.value.property == .material }?.target.definitionID == nil)
        #expect(restored.productAttributes.assignments.first { $0.value.property == .density }?.target.definitionID == scoped.target.definitionID)
        var competing = document
        competing.productAttributes.assignments.append(ProductAttributeAssignment(target: global.target, value: scoped.value))
        #expect(throws: ProductAttributeError.ambiguousProperty("density")) { _ = try ProductAttributeResolver().resolve(DocumentEvaluator(tolerance: .standard).evaluateExact(competing)) }
    }
    @Test(.timeLimit(.minutes(1)))
    func malformedCharacterizationProfilesRejectBeforePublication() throws {
        let valid = literal(item: 38)
        let failure = ProductAttributeError.unsupportedSemantics("Global physical characterization requires an unassociated singleton view.")
        let associated = valid.replacingOccurrences(of: "'',$,#38,#750", with: "'',$,#38,#54")
        #expect(throws: failure) { _ = try imported(associated) }
        let mapped = valid.replacingOccurrences(of: "ENDSEC;\nEND-ISO", with: "#790=REPRESENTATION_MAP(#38,#750);\nENDSEC;\nEND-ISO")
        #expect(throws: failure) { _ = try imported(mapped) }
        let related = valid.replacingOccurrences(of: "ENDSEC;\nEND-ISO", with: "#790=SHAPE_REPRESENTATION_RELATIONSHIP('','',#54,#750);\nENDSEC;\nEND-ISO")
        #expect(throws: failure) { _ = try imported(related) }
        let complex = valid.replacingOccurrences(of: "ENDSEC;\nEND-ISO", with: "#790=(REPRESENTATION_RELATIONSHIP('','',#54,#750) REPRESENTATION_RELATIONSHIP_WITH_TRANSFORMATION(#791) SHAPE_REPRESENTATION_RELATIONSHIP());\n#791=ITEM_DEFINED_TRANSFORMATION('','',#17,#17);\nENDSEC;\nEND-ISO")
        #expect(throws: failure) { _ = try imported(complex) }
        let multiple = valid.replacingOccurrences(of: "SHAPE_REPRESENTATION('',(#38),#7)", with: "SHAPE_REPRESENTATION('',(#38,#36),#7)")
        #expect(throws: ProductAttributeError.invalidSource("Global physical view must contain exactly its identified item.")) { _ = try imported(multiple) }
        let foreign = valid.replacingOccurrences(of: "'',$,#38,#750", with: "'',$,#999,#750")
        #expect(throws: ProductAttributeError.missingTarget("Global physical item geometry correspondence.")) { _ = try imported(foreign) }
        let duplicate = valid.replacingOccurrences(of: "ENDSEC;\nEND-ISO", with: "#790=CHARACTERIZED_ITEM_WITHIN_REPRESENTATION('',$,#38,#750);\nENDSEC;\nEND-ISO")
        #expect(throws: ProductAttributeError.invalidSource("Duplicate characterized item/representation owner.")) { _ = try imported(duplicate) }
        let metadata = valid.replacingOccurrences(of: "CHARACTERIZED_ITEM_WITHIN_REPRESENTATION('',$", with: "CHARACTERIZED_ITEM_WITHIN_REPRESENTATION('independent wrapper',$")
        #expect(try imported(metadata).productAttributes.itemCharacterizations.first?.name == "independent wrapper")
        let raw = valid.replacingOccurrences(of: "'material name',#751", with: "'material name',#38")
        #expect(throws: ProductAttributeError.unsupportedSemantics("Physical property requires a legal characterized-definition owner.")) { _ = try imported(raw) }
        let unit = valid.replacingOccurrences(of: "SHAPE_REPRESENTATION('',(#38),#7)", with: "SHAPE_REPRESENTATION('',(#38),#791)")
            .replacingOccurrences(of: "ENDSEC;\nEND-ISO", with: "#790=(LENGTH_UNIT() NAMED_UNIT(*) SI_UNIT($,.METRE.));\n#791=(GEOMETRIC_REPRESENTATION_CONTEXT(3) GLOBAL_UNIT_ASSIGNED_CONTEXT((#790,#5,#6)) REPRESENTATION_CONTEXT('view',''));\nENDSEC;\nEND-ISO")
        #expect(throws: ProductAttributeError.invalidSource("Global physical view has conflicting owned units.")) { _ = try imported(unit) }
    }
    @Test(.timeLimit(.minutes(1)))
    func physicalOverrideFailuresKeepMemoryAndURLAtomicAndCallerCeilings() throws {
        var document = try imported(literal(item: 36))
        let base = try #require(document.productAttributes.assignments.first { $0.value.property == .density })
        document.productAttributes.assignments.append(ProductAttributeAssignment(target: base.target,
            value: .density(PhysicalDensity(kilogramsPerCubicMeter: 8000)), overrides: base.id))
        let evaluated = try DocumentEvaluator(tolerance: .standard).evaluate(document)
        let sink = DataByteSink(), failure = ProductAttributeError.unsupportedSemantics("Physical override chains require a standard-equivalent ordering relationship.")
        #expect(throws: failure) { try OfficialFormatExchange(tolerance: .standard).write(evaluated, as: .step, to: sink) }
        #expect(sink.bytes.isEmpty)
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { do { try FileManager.default.removeItem(at: directory) } catch { Issue.record("Unable to remove CIWR fixture directory: \(error)") } }
        let url = directory.appendingPathComponent("global.step"), original = Data("existing complete output".utf8)
        try original.write(to: url)
        #expect(throws: failure) { try OfficialFormatExchange(tolerance: .standard).export(evaluated, as: .step, to: url) }
        #expect(try Data(contentsOf: url) == original)
        let clean = try imported(literal(item: 36)), exact = try DocumentEvaluator(tolerance: .standard).evaluateExact(clean)
        let resolved = try ProductAttributeResolver().resolve(exact)
        let limits = ExchangeResourceLimits(maximumIterations: resolved.consumedWork)
        #expect(throws: ProductAttributeError.resourceLimitExceeded("Cumulative product attribute budget.")) {
            _ = try STEPAttributesWriter().records(for: exact, resolved: resolved, transfer: STEPAttributeWriteTransfer(), startingAt: 1, limits: limits)
        }
        let boundedSink = DataByteSink()
        #expect(throws: ProductAttributeError.self) { try STEPExchange(tolerance: .standard, resourceLimits: limits).write(exact, to: boundedSink) }
        #expect(boundedSink.bytes.isEmpty)
    }
    @Test(.timeLimit(.minutes(1)))
    func lexicalComponentPresenceIgnoresQuotedLookalikesAndRejectsMalformedEntities() throws {
        let fields: any STEPFieldReading = STEPAssemblySyntax(entities: [
            1: "(GEOMETRIC_REPRESENTATION_CONTEXT(3) REPRESENTATION_CONTEXT('REPRESENTATION_RELATIONSHIP(#1,#2)',''))",
            2: "(REPRESENTATION_RELATIONSHIP('','',#1,#2) REPRESENTATION_RELATIONSHIP_WITH_TRANSFORMATION(#3) SHAPE_REPRESENTATION_RELATIONSHIP())",
            3: "REPRESENTATION_RELATIONSHIP('don''t match quotes','',#1,#2)",
            4: "(REPRESENTATION_CONTEXT('unterminated','')",
            5: "REPRESENTATION_CONTEXT('unterminated)",
            6: "(GEOMETRIC_REPRESENTATION_CONTEXT(3) REPRESENTATION_CONTEXT('\u{301}REPRESENTATION_RELATIONSHIP(',''))"])
        #expect(try !fields.hasComponent(1, named: "REPRESENTATION_RELATIONSHIP"))
        #expect(try fields.hasComponent(2, named: "REPRESENTATION_RELATIONSHIP"))
        #expect(try fields.hasComponent(3, named: "REPRESENTATION_RELATIONSHIP"))
        #expect(try !fields.hasComponent(6, named: "REPRESENTATION_RELATIONSHIP"))
        for id in [4,5] { #expect(throws: ImportError.invalidData("Malformed STEP lexical entity.")) { _ = try fields.hasComponent(id, named: "REPRESENTATION_RELATIONSHIP") } }
        #expect(try fields.arguments(2, component: "REPRESENTATION_RELATIONSHIP") == ["''", "''", "#1", "#2"])
    }
    @Test(.timeLimit(.minutes(1)))
    func cancelledGlobalPhysicalImportDoesNotPublish() async throws {
        let text = literal(item: 36)
        let task = Task { withUnsafeCurrentTask { $0?.cancel() }; return try STEPExchange(tolerance: .standard).import(Data(text.utf8)) }
        do { _ = try await task.value; Issue.record("Cancelled CIWR import published source.") }
        catch is CancellationError {}
    }
    // Independently authored standard geometry/product literal, retained from the shared-representation fixture.
    // CIWR/material/density records above are literal standard records; no production writer creates input fixtures.
    private static let geometryFixture = #"""
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
ENDSEC;
END-ISO-10303-21;
"""#
}
