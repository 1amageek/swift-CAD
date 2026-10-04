import Foundation
import Testing
import CADCore
import CADGeometry
import CADIR
import CADKernel
import CADTopology
@testable import CADExchange

@Suite("Definition-qualified STEP geometry attributes")
struct DefinitionQualifiedSTEPAttributeTests {
    private func imported(_ text: String = Self.fixture) throws -> CADDocument {
        try #require(STEPExchange(tolerance: .standard).import(Data(text.utf8)).document)
    }
    private func inspect(_ document: CADDocument, selectedCount: Int = 2, total: Int = 3) throws {
        let selected = try #require(document.assembly?.definitions.first { $0.id.description == "33333333-3333-4333-8333-333333333333" })
        #expect(document.designGraph.nodes.count == 1 && selected.features.count == 1)
        let evaluated = try DocumentEvaluator(tolerance: .standard).evaluateExact(document)
        let artifact = try #require(evaluated.assembly), resolved = try ProductAttributeResolver().resolve(evaluated)
        #expect(artifact.local.model.bodies.count == 1 && artifact.local.model.faces.count == 1)
        #expect(evaluated.brep.bodies.count == total && evaluated.brep.faces.count == total)
        #expect(artifact.occurrences.filter { $0.definitionID == selected.id }.count == selectedCount)
        let labels = document.productAttributes.assignments.filter { $0.value.property == .name }
        #expect(labels.count == 2 && labels.allSatisfy { $0.target.definitionID == selected.id && $0.target.path == nil })
        let selectedLayer = try #require(document.productAttributes.layers.first { $0.name == "selected face layer" })
        let otherLayer = try #require(document.productAttributes.layers.first { $0.name == "other face layer only" })
        #expect(selectedLayer.members.count == 1 && selectedLayer.members.first?.definitionID == selected.id)
        #expect(otherLayer.members.count == 1 && otherLayer.members.first?.definitionID?.description == "44444444-4444-4444-8444-444444444444")
        #expect(document.productAttributes.assignments.filter { $0.value.property == .color }.count == 3)
        for occurrence in artifact.occurrences where !occurrence.features.isEmpty {
            let selectedInstance = occurrence.definitionID == selected.id
            #expect(occurrence.features.count == 1)
            let feature = try #require(occurrence.features.first)
            #expect(feature.bodies.count == 1 && feature.faces.count == 1)
            let body = try #require(feature.bodies.values.first)
            let face = try #require(feature.faces.values.first)
            let b = try #require(resolved.values[ResolvedProductTarget(topology: .body(body), definitionID: occurrence.definitionID, path: occurrence.path)])
            let f = try #require(resolved.values[ResolvedProductTarget(topology: .face(face), definitionID: occurrence.definitionID, path: occurrence.path)])
            #expect(b.properties[.color]?.value == .color(selectedInstance ? ColorRGBA(r: 0,g: 0,b: 1,a: 1) : ColorRGBA(r: 0,g: 1,b: 0,a: 1)))
            #expect(f.properties[.color]?.value == .color(selectedInstance ? ColorRGBA(r: 1,g: 0,b: 0,a: 1) : ColorRGBA(r: 0,g: 1,b: 0,a: 1)))
            #expect(b.properties[.color]?.assignmentChain.count == (selectedInstance ? 2 : 1))
            #expect(f.properties[.color]?.assignmentChain.count == (selectedInstance ? 3 : 1))
            #expect(b.properties[.name]?.value == (selectedInstance ? .name("selected body") : nil))
            #expect(f.properties[.name]?.value == (selectedInstance ? .name("selected face") : nil))
            #expect(f.layers.contains(selectedLayer.id) == selectedInstance)
            #expect(f.layers.contains(otherLayer.id) == (occurrence.definitionID.description == "44444444-4444-4444-8444-444444444444"))
            #expect(b.layers.isEmpty)
        }
    }
    @Test(.timeLimit(.minutes(1)))
    func independentNamedElementsCarrierStylesAndLayerOnlyScopesSurvivePublicTransport() throws {
        var document = try imported()
        try inspect(document)
        let store = NativePackageStore(tolerance: .standard), native = DataByteSink()
        try store.writePackage(for: document, to: native)
        #expect(try store.loadDocument(from: native.bytes) == document)
        for _ in 0..<2 {
            let sink = DataByteSink()
            try OfficialFormatExchange(tolerance: .standard).write(DocumentEvaluator(tolerance: .standard).evaluate(document), as: .step, to: sink)
            let text = try #require(String(data: sink.bytes, encoding: .utf8))
            #expect(text.components(separatedBy: "=ADVANCED_FACE(").count - 1 == 1)
            #expect(text.contains("PRESENTATION_STYLE_BY_CONTEXT((NULL_STYLE(.NULL.))"))
            #expect(!text.contains("ADVANCED_FACE('selected face'"))
            document = try imported(text); try inspect(document)
        }
        var assembly = try #require(document.assembly)
        let selected = try #require(assembly.definitions.first { !$0.features.isEmpty })
        let third = AssemblyDefinition(formationID: selected.formationID, identifier: "new PD", features: selected.features)
        assembly.definitions.append(third)
        let parent = try #require(assembly.definitions.firstIndex { !$0.children.isEmpty })
        assembly.definitions[parent].children.append(AssemblyOccurrence(definitionID: third.id,
            placement: RigidTransform3D.translated(by: Vector3D(x: 0.2, y: 0.3, z: 0))))
        document.assembly = assembly
        try inspect(document, total: 4)
        let sink = DataByteSink(); try STEPExchange(tolerance: .standard).write(DocumentEvaluator(tolerance: .standard).evaluateExact(document), to: sink)
        let restored = try imported(try #require(String(data: sink.bytes, encoding: .utf8)))
        try inspect(restored, total: 4)
    }
    @Test(.timeLimit(.minutes(1)))
    func standaloneCarrierStyleDoesNotInventGlobalColorOrPredecessor() throws {
        var lines: [String] = []
        for line in Self.fixture.split(separator: "\n") {
            if line.first == "#", let equal = line.firstIndex(of: "="), let id = Int(line[line.index(after: line.startIndex)..<equal]),
               (830...837).contains(id) || (850...857).contains(id) || id == 863 { continue }
            lines.append(String(line))
        }
        let literal = lines.joined(separator: "\n").replacingOccurrences(of: "#847=CONTEXT_DEPENDENT_OVER_RIDING_STYLED_ITEM('',(#846),#38,#837,(#801));", with: "#847=STYLED_ITEM('',(#846),#38);")
            .replacingOccurrences(of: "#862=DRAUGHTING_MODEL('',(#837,#847,#857,#861),#7);", with: "#838=PRESENTATION_STYLE_ASSIGNMENT((NULL_STYLE(.NULL.)));\n#839=STYLED_ITEM('',(#838),#38);\n#862=DRAUGHTING_MODEL('',(#839,#847,#861),#7);")
        var document = try imported(literal)
        for _ in 0..<2 {
            let colors = document.productAttributes.assignments.filter { $0.value.property == .color }
            #expect(colors.count == 1 && colors.first?.overrides == nil && colors.first?.target.definitionID?.description == "33333333-3333-4333-8333-333333333333")
            let evaluated = try DocumentEvaluator(tolerance: .standard).evaluateExact(document), resolved = try ProductAttributeResolver().resolve(evaluated)
            #expect(resolved.values.filter { $0.key.definitionID?.description == "44444444-4444-4444-8444-444444444444" }.values.allSatisfy { $0.properties[.color] == nil })
            let sink = DataByteSink(); try STEPExchange(tolerance: .standard).write(evaluated, to: sink)
            document = try imported(try #require(String(data: sink.bytes, encoding: .utf8)))
        }
    }
    @Test(.timeLimit(.minutes(1)))
    func invalidCarrierContextsDescriptionsAndAbsentScopeRefuse() throws {
        let unknown = Self.fixture.replacingOccurrences(of: "#846=PRESENTATION_STYLE_BY_CONTEXT((#845),#801);", with: "#846=PRESENTATION_STYLE_BY_CONTEXT((#845),#54);")
        #expect(throws: ProductAttributeError.unsupportedSemantics("Style context requires a proved identity PD carrier.")) { _ = try imported(unknown) }
        let competing = Self.fixture.replacingOccurrences(of: "#38,#837,(#801)", with: "#38,#837,(#802)")
        #expect(throws: ProductAttributeError.ambiguousProperty("Competing qualified style contexts.")) { _ = try imported(competing) }
        let foreign = Self.fixture.replacingOccurrences(of: "#847=CONTEXT_DEPENDENT_OVER_RIDING_STYLED_ITEM('',(#846),#38", with: "#847=CONTEXT_DEPENDENT_OVER_RIDING_STYLED_ITEM('',(#846),#17")
        #expect(throws: ProductAttributeError.missingTarget("Qualified style carrier geometry correspondence.")) { _ = try imported(foreign) }
        let foreignFeature = Self.fixture.replacingOccurrences(of: "#803=REPRESENTATION_MAP(#17,#810);", with: "#803=REPRESENTATION_MAP(#17,#811);")
            .replacingOccurrences(of: "ENDSEC;\nEND-ISO", with: """
            #811=SHAPE_REPRESENTATION('',(#938,#17),#7);
            #925=VERTEX_POINT('',#10);
            #926=VERTEX_POINT('',#11);
            #927=VERTEX_POINT('',#12);
            #928=EDGE_CURVE('',#925,#926,#119,.T.);
            #929=EDGE_CURVE('',#926,#927,#120,.T.);
            #930=EDGE_CURVE('',#927,#925,#121,.T.);
            #931=ORIENTED_EDGE('',*,*,#928,.T.);
            #932=ORIENTED_EDGE('',*,*,#929,.T.);
            #933=ORIENTED_EDGE('',*,*,#930,.T.);
            #934=EDGE_LOOP('',(#931,#932,#933));
            #935=FACE_OUTER_BOUND('',#934,.T.);
            #936=ADVANCED_FACE('',(#935),#18,.T.);
            #937=OPEN_SHELL('',(#936));
            #938=SHELL_BASED_SURFACE_MODEL('',(#937));
            ENDSEC;
            END-ISO
            """)
        #expect(throws: ProductAttributeError.missingTarget("Qualified style carrier feature membership.")) { _ = try imported(foreignFeature) }
        let nonidentity = Self.fixture.replacingOccurrences(of: "#10,1.,#13", with: "#80,1.,#13")
        #expect(throws: AssemblyError.invalidSource("Whole-part carrier transform is not identity.")) { _ = try imported(nonidentity) }
        let description = Self.fixture.replacingOccurrences(of: "SHAPE_ASPECT('selected body',''", with: "SHAPE_ASPECT('selected body','independent description'")
        #expect(throws: ProductAttributeError.unsupportedSemantics("Independent shape-element descriptions require a retained source owner.")) { _ = try imported(description) }
    }
    @Test(.timeLimit(.minutes(1)))
    func nameHistoryEmptyLabelsAndCallerLimitsKeepOutputAtomic() throws {
        let original = try imported(), evaluator = DocumentEvaluator(tolerance: .standard)
        let name = try #require(original.productAttributes.assignments.first { $0.value == .name("selected face") })
        let failure = ProductAttributeError.unsupportedSemantics("Qualified shape-element names require a nonempty standalone label.")
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { do { try FileManager.default.removeItem(at: directory) } catch { Issue.record("Unable to remove qualified STEP fixture: \(error)") } }
        let url = directory.appendingPathComponent("qualified.step"), bytes = Data("existing complete destination".utf8)
        try bytes.write(to: url)
        for history in [false,true] {
            var document = original
            if history { document.productAttributes.assignments.append(ProductAttributeAssignment(target: name.target, value: .name("new label"), overrides: name.id)) }
            else {
                document.productAttributes.assignments.removeAll { $0.id == name.id }
                document.productAttributes.assignments.append(ProductAttributeAssignment(target: name.target, value: .name("")))
            }
            let evaluated = try evaluator.evaluate(document), sink = DataByteSink(), facade = OfficialFormatExchange(tolerance: .standard)
            #expect(throws: failure) { try facade.write(evaluated, as: .step, to: sink) }
            #expect(sink.bytes.isEmpty)
            #expect(throws: failure) { try facade.export(evaluated, as: .step, to: url) }
            #expect(try Data(contentsOf: url) == bytes)
        }
        let exact = try evaluator.evaluateExact(original), resolved = try ProductAttributeResolver().resolve(exact)
        let sink = DataByteSink()
        #expect(throws: ProductAttributeError.resourceLimitExceeded("Cumulative product attribute budget.")) {
            try STEPExchange(tolerance: .standard, resourceLimits: ExchangeResourceLimits(maximumIterations: resolved.consumedWork)).write(exact, to: sink)
        }
        #expect(sink.bytes.isEmpty)
    }
    @Test(.timeLimit(.minutes(1)))
    func cancelledQualifiedImportDoesNotPublish() async throws {
        let task = Task { withUnsafeCurrentTask { $0?.cancel() }; return try STEPExchange(tolerance: .standard).import(Data(Self.fixture.utf8)) }
        do { _ = try await task.value; Issue.record("Cancelled qualified STEP import published source.") }
        catch is CancellationError {}
    }
    // Independently authored standard topology/product literal and literal attribute records.
    // No production writer generates the test input.
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
#36=ADVANCED_FACE('',(#35),#18,.T.);
#37=OPEN_SHELL('',(#36));
#38=SHELL_BASED_SURFACE_MODEL('',(#37));
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
#54=SHAPE_REPRESENTATION('',(#801,#17),#7);
#55=SHAPE_DEFINITION_REPRESENTATION(#53,#54);
#62=PRODUCT_DEFINITION('analysis',$,#51,#3);
#63=PRODUCT_DEFINITION_SHAPE('','',#62);
#65=SHAPE_DEFINITION_REPRESENTATION(#63,#66);
#66=SHAPE_REPRESENTATION('',(#802,#17),#7);
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
#93=(REPRESENTATION_RELATIONSHIP('','',#66,#74) REPRESENTATION_RELATIONSHIP_WITH_TRANSFORMATION(#92) SHAPE_REPRESENTATION_RELATIONSHIP());
#94=CONTEXT_DEPENDENT_SHAPE_REPRESENTATION(#93,#91);
#600=EXTERNAL_SOURCE(IDENTIFIER('urn:swiftcad:assembly-source-id'));
#601=IDENTIFICATION_ROLE('product',$);
#602=IDENTIFICATION_ROLE('formation',$);
#603=IDENTIFICATION_ROLE('definition',$);
#604=APPLIED_EXTERNAL_IDENTIFICATION_ASSIGNMENT('11111111-1111-4111-8111-111111111111',#601,#600,(#50));
#605=APPLIED_EXTERNAL_IDENTIFICATION_ASSIGNMENT('22222222-2222-4222-8222-222222222222',#602,#600,(#51));
#606=APPLIED_EXTERNAL_IDENTIFICATION_ASSIGNMENT('33333333-3333-4333-8333-333333333333',#603,#600,(#52));
#607=APPLIED_EXTERNAL_IDENTIFICATION_ASSIGNMENT('44444444-4444-4444-8444-444444444444',#603,#600,(#62));

#95=NEXT_ASSEMBLY_USAGE_OCCURRENCE('selected again','second selected usage','',#72,#52,$);
#96=PRODUCT_DEFINITION_SHAPE('','',#95);
#97=ITEM_DEFINED_TRANSFORMATION('','',#17,#82);
#98=(REPRESENTATION_RELATIONSHIP('','',#54,#74) REPRESENTATION_RELATIONSHIP_WITH_TRANSFORMATION(#97) SHAPE_REPRESENTATION_RELATIONSHIP());
#99=CONTEXT_DEPENDENT_SHAPE_REPRESENTATION(#98,#96);
#800=REPRESENTATION_MAP(#17,#810);
#801=MAPPED_ITEM('',#800,#804);
#802=MAPPED_ITEM('',#803,#804);
#803=REPRESENTATION_MAP(#17,#810);
#804=CARTESIAN_TRANSFORMATION_OPERATOR_3D('',*,*,#14,#805,#10,1.,#13);
#805=DIRECTION('',(0.,1.,0.));
#810=SHAPE_REPRESENTATION('',(#38,#17),#7);
#820=SHAPE_REPRESENTATION('',(#38),#7);
#821=SHAPE_ASPECT('selected body','',#53,.T.);
#822=GEOMETRIC_ITEM_SPECIFIC_USAGE('','',#821,#820,#38);
#823=SHAPE_REPRESENTATION('',(#36),#7);
#824=SHAPE_ASPECT('selected face',$,#53,.T.);
#825=GEOMETRIC_ITEM_SPECIFIC_USAGE('','',#824,#823,#36);
#830=COLOUR_RGB('',0.,1.,0.);
#831=FILL_AREA_STYLE_COLOUR('',#830);
#832=FILL_AREA_STYLE('',(#831));
#833=SURFACE_STYLE_FILL_AREA(#832);
#834=SURFACE_SIDE_STYLE('',(#833));
#835=SURFACE_STYLE_USAGE(.BOTH.,#834);
#836=PRESENTATION_STYLE_ASSIGNMENT((#835));
#837=STYLED_ITEM('',(#836),#38);
#840=COLOUR_RGB('',0.,0.,1.);
#841=FILL_AREA_STYLE_COLOUR('',#840);
#842=FILL_AREA_STYLE('',(#841));
#843=SURFACE_STYLE_FILL_AREA(#842);
#844=SURFACE_SIDE_STYLE('',(#843));
#845=SURFACE_STYLE_USAGE(.BOTH.,#844);
#846=PRESENTATION_STYLE_BY_CONTEXT((#845),#801);
#847=CONTEXT_DEPENDENT_OVER_RIDING_STYLED_ITEM('',(#846),#38,#837,(#801));
#850=COLOUR_RGB('',1.,0.,0.);
#851=FILL_AREA_STYLE_COLOUR('',#850);
#852=FILL_AREA_STYLE('',(#851));
#853=SURFACE_STYLE_FILL_AREA(#852);
#854=SURFACE_SIDE_STYLE('',(#853));
#855=SURFACE_STYLE_USAGE(.BOTH.,#854);
#856=PRESENTATION_STYLE_BY_CONTEXT((#855),#801);
#857=CONTEXT_DEPENDENT_OVER_RIDING_STYLED_ITEM('',(#856),#36,#847,(#801));
#860=PRESENTATION_STYLE_BY_CONTEXT((NULL_STYLE(.NULL.)),#802);
#861=STYLED_ITEM('',(#860),#36);
#862=DRAUGHTING_MODEL('',(#837,#847,#857,#861),#7);
#863=PRESENTATION_LAYER_ASSIGNMENT('selected face layer','',(#857));
#864=PRESENTATION_LAYER_ASSIGNMENT('other face layer only','',(#861));
ENDSEC;
END-ISO-10303-21;
"""#
}
