import Foundation
import Testing
import CADCore
import CADGeometry
import CADIR
import CADKernel
import CADTopology
@testable import CADExchange

@Suite("Direct-usage STEP appearance")
struct DirectUsageSTEPAttributeTests {
    private func imported(_ text: String = Self.fixture) throws -> CADDocument {
        try #require(STEPExchange(tolerance: .standard).import(Data(text.utf8)).document)
    }
    private func usage(_ name: String, in document: CADDocument) throws -> AssemblyOccurrence {
        let source = try #require(document.assembly)
        return try #require(source.definitions.flatMap(\.children).first { $0.name == name })
    }
    private func inspect(_ document: CADDocument, parents: Int = 2) throws {
        let selected = try usage("rotated triangle", in: document), sibling = try usage("layer only sibling", in: document)
        #expect(selected.id.description == "11111111-1111-4111-8111-111111111111")
        #expect(sibling.id.description == "22222222-2222-4222-8222-222222222222")
        #expect(document.designGraph.nodes.count == 1)
        let appearance = document.productAttributes.assignments.filter { $0.target.kind == .directUsage }
        #expect(appearance.count == 2 && appearance.allSatisfy { $0.target.usageID == selected.id && $0.target.path == nil && $0.overrides != nil })
        #expect(document.productAttributes.assignments.filter { $0.value.property == .color }.count == 3)
        #expect(document.productAttributes.assignments.filter { $0.value.property == .opacity }.count == 3)
        let selectedLayer = try #require(document.productAttributes.layers.first { $0.name == "selected usage layer" })
        let siblingLayer = try #require(document.productAttributes.layers.first { $0.name == "sibling usage layer" })
        #expect(selectedLayer.members == [ProductAttributeTarget(kind: .directUsage, usageID: selected.id)])
        #expect(siblingLayer.members == [ProductAttributeTarget(kind: .directUsage, usageID: sibling.id)])
        let commonLayer = try #require(document.productAttributes.layers.first { $0.name == "common face layer" })
        let definitionLayer = try #require(document.productAttributes.layers.first { $0.name == "selected definition face layer" })
        let evaluated = try DocumentEvaluator(tolerance: .standard).evaluateExact(document)
        let artifact = try #require(evaluated.assembly), resolved = try ProductAttributeResolver().resolve(evaluated)
        #expect(artifact.local.model.bodies.count == 1 && artifact.local.model.faces.count == 1)
        #expect(evaluated.brep.bodies.count == parents * 3 && evaluated.brep.faces.count == parents * 3)
        #expect(artifact.occurrences.filter { $0.path.components.last == selected.id }.count == parents)
        #expect(artifact.occurrences.filter { $0.path.components.last == sibling.id }.count == parents)
        for occurrence in artifact.occurrences where !occurrence.features.isEmpty {
            #expect(occurrence.features.count == 1)
            let feature = try #require(occurrence.features.first)
            #expect(feature.bodies.count == 1 && feature.faces.count == 1)
            let body = try #require(feature.bodies.values.first), face = try #require(feature.faces.values.first)
            let selectedInstance = occurrence.path.components.last == selected.id
            let siblingInstance = occurrence.path.components.last == sibling.id
            let color = selectedInstance ? ColorRGBA(r: 1,g: 0,b: 0,a: 1) : siblingInstance ? ColorRGBA(r: 0,g: 0,b: 1,a: 1) : ColorRGBA(r: 0,g: 1,b: 0,a: 1)
            for topology in [TopologyReference.body(body), .face(face)] {
                let properties = try #require(resolved.values[ResolvedProductTarget(topology: topology, definitionID: occurrence.definitionID, path: occurrence.path)])
                #expect(properties.properties[.color]?.value == .color(color))
                #expect(properties.properties[.color]?.assignmentChain.count == (selectedInstance ? 2 : 1))
                #expect(properties.properties[.opacity]?.assignmentChain.count == (selectedInstance ? 2 : 1))
                if case let .opacity(value)? = properties.properties[.opacity]?.value {
                    #expect(abs(value - (selectedInstance ? 0.6 : 0.9)) < 1e-12)
                } else { Issue.record("Missing actual direct-usage opacity.") }
                #expect(properties.layers.contains(selectedLayer.id) == selectedInstance)
                #expect(properties.layers.contains(siblingLayer.id) == siblingInstance)
                if case .body = topology { #expect(properties.properties[.name]?.value == .name("common body")) }
                else {
                    #expect(properties.layers.contains(commonLayer.id))
                    #expect(properties.layers.contains(definitionLayer.id) == (occurrence.definitionID == selected.definitionID))
                    #expect(properties.properties[.name]?.value == (occurrence.definitionID == selected.definitionID ? .name("selected definition face") : nil))
                }
            }
        }
    }
    @Test(.timeLimit(.minutes(1)))
    func independentSharedNestedUsageRetainsSelectorProvenanceAndLayerOnlyScope() throws {
        var document = try imported(); try inspect(document)
        let native = DataByteSink(), store = NativePackageStore(tolerance: .standard)
        try store.writePackage(for: document, to: native)
        #expect(try store.loadDocument(from: native.bytes) == document)
        for _ in 0..<2 {
            let evaluated = try DocumentEvaluator(tolerance: .standard).evaluate(document), sink = DataByteSink()
            try OfficialFormatExchange(tolerance: .standard).write(evaluated, as: .step, to: sink)
            let text = try #require(String(data: sink.bytes, encoding: .utf8))
            #expect(text.components(separatedBy: "=ADVANCED_FACE(").count - 1 == 1)
            #expect(text.contains("PRESENTATION_STYLE_BY_CONTEXT((NULL_STYLE(.NULL.))"))
            document = try imported(text); try inspect(document)
        }
        let selected = try usage("rotated triangle", in: document)
        let middle = try #require(document.assembly?.definitions.first { $0.children.contains { $0.id == selected.id } })
        document.assembly?.roots.append(AssemblyOccurrence(name: "third shared parent", definitionID: middle.id,
            placement: .translated(by: Vector3D(x: 0.3,y: 0.4,z: 0))))
        try inspect(document, parents: 3)
        let sink = DataByteSink()
        try STEPExchange(tolerance: .standard).write(DocumentEvaluator(tolerance: .standard).evaluateExact(document), to: sink)
        try inspect(imported(try #require(String(data: sink.bytes, encoding: .utf8))), parents: 3)
    }
    @Test(.timeLimit(.minutes(1)))
    func standaloneUsageStyleDoesNotInventBaselineOrExpandedPaths() throws {
        var lines: [String] = []
        for line in Self.fixture.split(separator: "\n") {
            if line.first == "#", let equal = line.firstIndex(of: "="), let id = Int(line[line.index(after: line.startIndex)..<equal]),
               (830...837).contains(id) { continue }
            lines.append(String(line))
        }
        let literal = lines.joined(separator: "\n")
            .replacingOccurrences(of: "#847=CONTEXT_DEPENDENT_OVER_RIDING_STYLED_ITEM('',(#846),#801,#837,(#84));", with: "#847=STYLED_ITEM('',(#846),#801);")
            .replacingOccurrences(of: "(#837,#847,#857,#861,#871,#881)", with: "(#847,#857,#861,#871,#881)")
        var document = try imported(literal)
        for _ in 0..<2 {
            let selected = try usage("rotated triangle", in: document), sibling = try usage("layer only sibling", in: document)
            let attributes = document.productAttributes.assignments.filter { $0.target.kind == .directUsage }
            #expect(attributes.count == 2 && attributes.allSatisfy { $0.target.usageID == selected.id && $0.target.path == nil && $0.overrides == nil })
            let evaluated = try DocumentEvaluator(tolerance: .standard).evaluateExact(document), resolved = try ProductAttributeResolver().resolve(evaluated)
            let artifact = try #require(evaluated.assembly)
            #expect(artifact.occurrences.filter { $0.path.components.last == selected.id }.count == 2)
            for placed in artifact.occurrences where placed.path.components.last == sibling.id {
                let body = try #require(placed.features.first?.bodies.values.first)
                let values = try #require(resolved.values[ResolvedProductTarget(topology: .body(body), definitionID: placed.definitionID, path: placed.path)])
                #expect(values.properties[.color] == nil && values.properties[.opacity] == nil)
            }
            let sink = DataByteSink(); try STEPExchange(tolerance: .standard).write(evaluated, to: sink)
            document = try imported(try #require(String(data: sink.bytes, encoding: .utf8)))
        }
    }
    @Test(.timeLimit(.minutes(1)))
    func explicitFullPathOverrideRemainsDistinctFromSharedUsage() throws {
        var document = try imported()
        let selected = try usage("rotated triangle", in: document)
        let evaluated = try DocumentEvaluator(tolerance: .standard).evaluateExact(document)
        let occurrence = try #require(evaluated.assembly?.occurrences.first { $0.path.components.last == selected.id })
        let target = ProductAttributeTarget(kind: .occurrence, path: occurrence.path)
        for value in [ProductAttributeValue.color(ColorRGBA(r: 1,g: 1,b: 0,a: 1)), .opacity(0.5)] {
            let predecessor = try #require(document.productAttributes.assignments.first { $0.target.usageID == selected.id && $0.value.property == value.property })
            document.productAttributes.assignments.append(ProductAttributeAssignment(target: target, value: value, overrides: predecessor.id))
        }
        for _ in 0..<2 {
            let snapshot = try DocumentEvaluator(tolerance: .standard).evaluateExact(document), resolved = try ProductAttributeResolver().resolve(snapshot)
            #expect(document.productAttributes.assignments.filter { $0.target == target }.count == 2)
            #expect(document.productAttributes.assignments.filter { $0.target.kind == .directUsage }.count == 2)
            for placed in try #require(snapshot.assembly).occurrences where placed.path.components.last == selected.id {
                let body = try #require(placed.features.first?.bodies.values.first)
                let values = try #require(resolved.values[ResolvedProductTarget(topology: .body(body), definitionID: placed.definitionID, path: placed.path)])
                #expect(values.properties[.color]?.value == .color(placed.path == occurrence.path ? ColorRGBA(r: 1,g: 1,b: 0,a: 1) : ColorRGBA(r: 1,g: 0,b: 0,a: 1)))
                #expect(values.properties[.color]?.assignmentChain.count == (placed.path == occurrence.path ? 3 : 2))
            }
            let sink = DataByteSink(); try STEPExchange(tolerance: .standard).write(snapshot, to: sink)
            document = try imported(try #require(String(data: sink.bytes, encoding: .utf8)))
        }
    }
    @Test(.timeLimit(.minutes(1)))
    func foreignMixedCompetingAndUnprovedUsageContextsRefuse() throws {
        let foreign = Self.fixture.replacingOccurrences(of: "#847=CONTEXT_DEPENDENT_OVER_RIDING_STYLED_ITEM('',(#846),#801", with: "#847=CONTEXT_DEPENDENT_OVER_RIDING_STYLED_ITEM('',(#846),#802")
        #expect(throws: ProductAttributeError.missingTarget("Direct usage style carrier does not select its child definition.")) { _ = try imported(foreign) }
        let competing = Self.fixture.replacingOccurrences(of: "#801,#837,(#84)", with: "#801,#837,(#99)")
        #expect(throws: ProductAttributeError.ambiguousProperty("Competing direct usage style contexts.")) { _ = try imported(competing) }
        let mixed = Self.fixture.replacingOccurrences(of: "#801,#837,(#84)", with: "#801,#837,(#84,#99)")
        #expect(throws: ProductAttributeError.unsupportedSemantics("Direct usage style context must select one proved CDSR.")) { _ = try imported(mixed) }
        let pathGuess = Self.fixture.replacingOccurrences(of: "#801,#837,(#84)", with: "#801,#837,(#83)")
        #expect(throws: ProductAttributeError.ambiguousProperty("Competing direct usage style contexts.")) { _ = try imported(pathGuess) }
        let unknown = Self.fixture.replacingOccurrences(of: "#846=PRESENTATION_STYLE_BY_CONTEXT((#845),#84);", with: "#846=PRESENTATION_STYLE_BY_CONTEXT((#845),#41);")
        #expect(throws: ProductAttributeError.unsupportedSemantics("Style context requires a proved identity PD carrier.")) { _ = try imported(unknown) }
        let unproved = Self.fixture.replacingOccurrences(of: "#846=PRESENTATION_STYLE_BY_CONTEXT((#845),#84);", with: "#846=PRESENTATION_STYLE_BY_CONTEXT((#845),#895);")
            .replacingOccurrences(of: "ENDSEC;\nEND-ISO", with: "#895=CONTEXT_DEPENDENT_SHAPE_REPRESENTATION(#83,#53);\nENDSEC;\nEND-ISO")
        #expect(throws: AssemblyError.invalidSource("STEP occurrence has missing or multiple placement associations.")) { _ = try imported(unproved) }
        let nonidentity = Self.fixture.replacingOccurrences(of: "#805,#40,1.,#13", with: "#805,#42,1.,#13")
        #expect(throws: AssemblyError.invalidSource("Whole-part carrier transform is not identity.")) { _ = try imported(nonidentity) }
        let nonleaf = Self.fixture.replacingOccurrences(of: "#846=PRESENTATION_STYLE_BY_CONTEXT((#845),#84);", with: "#846=PRESENTATION_STYLE_BY_CONTEXT((#845),#89);")
            .replacingOccurrences(of: "#801,#837,(#84)", with: "#801,#837,(#89)")
        #expect(throws: ProductAttributeError.unsupportedSemantics("Direct usage appearance requires a nonempty leaf child.")) { _ = try imported(nonleaf) }
        let cycle = Self.fixture.replacingOccurrences(of: "#801,#837,(#84)", with: "#801,#847,(#84)")
        #expect(throws: ProductAttributeError.invalidSource("STEP style override cycle.")) { _ = try imported(cycle) }
    }
    @Test(.timeLimit(.minutes(1)))
    func nonleafEmptyAndBudgetRefusalsPreserveAtomicOutput() throws {
        let original = try imported(), evaluator = DocumentEvaluator(tolerance: .standard)
        let selected = try usage("rotated triangle", in: original)
        let middle = try #require(original.assembly?.definitions.first { $0.children.contains { $0.id == selected.id } })
        let parentUsage = try #require(original.assembly?.definitions.flatMap(\.children).first { $0.definitionID == middle.id })
        var nonleaf = original
        nonleaf.productAttributes.assignments.append(ProductAttributeAssignment(target: ProductAttributeTarget(kind: .directUsage, usageID: parentUsage.id), value: .color(ColorRGBA(r: 1,g: 0,b: 1,a: 1))))
        var empty = original
        let emptyDefinition = AssemblyDefinition(formationID: middle.formationID, identifier: "empty view")
        let emptyUsage = AssemblyOccurrence(name: "empty usage", definitionID: emptyDefinition.id)
        empty.assembly?.definitions.append(emptyDefinition)
        let middleIndex = try #require(empty.assembly?.definitions.firstIndex { $0.id == middle.id })
        empty.assembly?.definitions[middleIndex].children.append(emptyUsage)
        empty.productAttributes.layers.append(ProductLayer(name: "empty usage layer", members: [ProductAttributeTarget(kind: .directUsage, usageID: emptyUsage.id)]))
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { do { try FileManager.default.removeItem(at: directory) } catch { Issue.record("Unable to remove direct usage fixture: \(error)") } }
        let url = directory.appendingPathComponent("usage.step"), bytes = Data("existing complete destination".utf8)
        try bytes.write(to: url)
        let failure = ProductAttributeError.unsupportedSemantics("Direct usage appearance requires a nonempty leaf child.")
        for document in [nonleaf,empty] {
            let evaluated = try evaluator.evaluate(document), sink = DataByteSink(), facade = OfficialFormatExchange(tolerance: .standard)
            #expect(throws: failure) { try facade.write(evaluated, as: .step, to: sink) }
            #expect(sink.bytes.isEmpty)
            #expect(throws: failure) { try facade.export(evaluated, as: .step, to: url) }
            #expect(try Data(contentsOf: url) == bytes)
        }
        let snapshot = try evaluator.evaluateExact(original), resolved = try ProductAttributeResolver().resolve(snapshot), sink = DataByteSink()
        #expect(throws: ProductAttributeError.resourceLimitExceeded("Cumulative product attribute budget.")) {
            try STEPExchange(tolerance: .standard, resourceLimits: ExchangeResourceLimits(maximumIterations: resolved.consumedWork)).write(snapshot, to: sink)
        }
        #expect(sink.bytes.isEmpty)
        #expect(throws: (any Error).self) { _ = try STEPExchange(tolerance: .standard, resourceLimits: ExchangeResourceLimits(maximumNesting: 2)).import(Data(Self.fixture.utf8)) }
    }
    @Test(.timeLimit(.minutes(1)))
    func cancelledUsageImportDoesNotPublish() async throws {
        let task = Task { withUnsafeCurrentTask { $0?.cancel() }; return try STEPExchange(tolerance: .standard).import(Data(Self.fixture.utf8)) }
        do { _ = try await task.value; Issue.record("Cancelled direct-usage import published source.") }
        catch is CancellationError {}
    }

    // Independently authored exact topology/product literal and standard appearance records.
    // No production writer generates this fixture.
    private static let fixture = #"""
ISO-10303-21;
HEADER;
FILE_DESCRIPTION(('Independent assembly fixture'),'2;1');
FILE_NAME('assembly.step','2000-01-01T00:00:00',(''),(''),'fixture','','');
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
#8=(GEOMETRIC_REPRESENTATION_CONTEXT(3) GLOBAL_UNIT_ASSIGNED_CONTEXT((#4,#5,#6)) REPRESENTATION_CONTEXT('nested',''));
#9=(GEOMETRIC_REPRESENTATION_CONTEXT(3) GLOBAL_UNIT_ASSIGNED_CONTEXT((#4,#5,#6)) REPRESENTATION_CONTEXT('root',''));
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
#38=SHELL_BASED_SURFACE_MODEL('common body',(#37));
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
#40=CARTESIAN_POINT('',(10.,0.,0.));
#41=AXIS2_PLACEMENT_3D('child nonorigin',#40,#13,#14);
#42=CARTESIAN_POINT('',(100.,50.,0.));
#43=DIRECTION('',(0.,1.,0.));
#44=AXIS2_PLACEMENT_3D('rotated child target',#42,#13,#43);
#45=CARTESIAN_POINT('',(0.,0.,0.));
#46=AXIS2_PLACEMENT_3D('nested origin',#45,#13,#14);
#47=CARTESIAN_POINT('',(0.,200.,0.));
#48=AXIS2_PLACEMENT_3D('second nested target',#47,#13,#14);
#49=AXIS2_PLACEMENT_3D('root origin',#45,#13,#14);
#50=PRODUCT('part','triangle part','',(#2));
#51=PRODUCT_DEFINITION_FORMATION('','',#50);
#52=PRODUCT_DEFINITION('design','',#51,#3);
#53=PRODUCT_DEFINITION_SHAPE('','',#52);
#54=SHAPE_REPRESENTATION('',(#801,#41),#7);
#55=SHAPE_DEFINITION_REPRESENTATION(#53,#54);
#60=PRODUCT('nested','shared nested assembly','',(#2));
#61=PRODUCT_DEFINITION_FORMATION('','',#60);
#62=PRODUCT_DEFINITION('design','',#61,#3);
#63=PRODUCT_DEFINITION_SHAPE('','',#62);
#64=SHAPE_REPRESENTATION('',(#44,#46,#146,#147),#8);
#65=SHAPE_DEFINITION_REPRESENTATION(#63,#64);
#70=PRODUCT('root','root assembly','',(#2));
#71=PRODUCT_DEFINITION_FORMATION('','',#70);
#72=PRODUCT_DEFINITION('design','',#71,#3);
#73=PRODUCT_DEFINITION_SHAPE('','',#72);
#74=SHAPE_REPRESENTATION('',(#46,#48,#49),#9);
#75=SHAPE_DEFINITION_REPRESENTATION(#73,#74);
#80=NEXT_ASSEMBLY_USAGE_OCCURRENCE('11111111-1111-4111-8111-111111111111','rotated triangle','',#62,#52,$);
#81=PRODUCT_DEFINITION_SHAPE('','',#80);
#82=ITEM_DEFINED_TRANSFORMATION('','',#41,#44);
#83=(REPRESENTATION_RELATIONSHIP('','',#54,#64) REPRESENTATION_RELATIONSHIP_WITH_TRANSFORMATION(#82) SHAPE_REPRESENTATION_RELATIONSHIP());
#84=CONTEXT_DEPENDENT_SHAPE_REPRESENTATION(#83,#81);
#85=NEXT_ASSEMBLY_USAGE_OCCURRENCE('nested first','first','',#72,#62,$);
#86=PRODUCT_DEFINITION_SHAPE('','',#85);
#87=ITEM_DEFINED_TRANSFORMATION('','',#46,#49);
#88=(REPRESENTATION_RELATIONSHIP('','',#64,#74) REPRESENTATION_RELATIONSHIP_WITH_TRANSFORMATION(#87) SHAPE_REPRESENTATION_RELATIONSHIP());
#89=CONTEXT_DEPENDENT_SHAPE_REPRESENTATION(#88,#86);
#90=NEXT_ASSEMBLY_USAGE_OCCURRENCE('nested second','second','',#72,#62,$);
#91=PRODUCT_DEFINITION_SHAPE('','',#90);
#92=ITEM_DEFINED_TRANSFORMATION('','',#46,#48);
#93=(REPRESENTATION_RELATIONSHIP('','',#64,#74) REPRESENTATION_RELATIONSHIP_WITH_TRANSFORMATION(#92) SHAPE_REPRESENTATION_RELATIONSHIP());
#94=CONTEXT_DEPENDENT_SHAPE_REPRESENTATION(#93,#91);
#122=(GEOMETRIC_REPRESENTATION_CONTEXT(3) GLOBAL_UNIT_ASSIGNED_CONTEXT((#4,#5,#6)) REPRESENTATION_CONTEXT('other definition',''));
#145=CARTESIAN_POINT('',(200.,50.,0.));
#146=AXIS2_PLACEMENT_3D('sibling target',#145,#13,#14);
#147=AXIS2_PLACEMENT_3D('other PD target',#47,#13,#14);
#95=NEXT_ASSEMBLY_USAGE_OCCURRENCE('22222222-2222-4222-8222-222222222222','layer only sibling','',#62,#52,$);
#96=PRODUCT_DEFINITION_SHAPE('','',#95);
#97=ITEM_DEFINED_TRANSFORMATION('','',#41,#146);
#98=(REPRESENTATION_RELATIONSHIP('','',#54,#64) REPRESENTATION_RELATIONSHIP_WITH_TRANSFORMATION(#97) SHAPE_REPRESENTATION_RELATIONSHIP());
#99=CONTEXT_DEPENDENT_SHAPE_REPRESENTATION(#98,#96);
#152=PRODUCT_DEFINITION('other design','',#51,#3);
#153=PRODUCT_DEFINITION_SHAPE('','',#152);
#154=SHAPE_REPRESENTATION('',(#802,#41),#122);
#155=SHAPE_DEFINITION_REPRESENTATION(#153,#154);
#156=NEXT_ASSEMBLY_USAGE_OCCURRENCE('33333333-3333-4333-8333-333333333333','other definition usage','',#62,#152,$);
#157=PRODUCT_DEFINITION_SHAPE('','',#156);
#158=ITEM_DEFINED_TRANSFORMATION('','',#41,#147);
#159=(REPRESENTATION_RELATIONSHIP('','',#154,#64) REPRESENTATION_RELATIONSHIP_WITH_TRANSFORMATION(#158) SHAPE_REPRESENTATION_RELATIONSHIP());
#160=CONTEXT_DEPENDENT_SHAPE_REPRESENTATION(#159,#157);
#800=REPRESENTATION_MAP(#41,#810);
#801=MAPPED_ITEM('',#800,#804);
#802=MAPPED_ITEM('',#800,#804);
#804=CARTESIAN_TRANSFORMATION_OPERATOR_3D('',*,*,#14,#805,#40,1.,#13);
#805=DIRECTION('',(0.,1.,0.));
#810=SHAPE_REPRESENTATION('',(#38,#41),#7);
#820=SHAPE_REPRESENTATION('',(#36),#7);
#821=SHAPE_ASPECT('selected definition face','',#53,.T.);
#822=GEOMETRIC_ITEM_SPECIFIC_USAGE('','',#821,#820,#36);
#830=COLOUR_RGB('',0.,0.,1.);
#831=SURFACE_STYLE_TRANSPARENT(0.1);
#832=SURFACE_STYLE_RENDERING_WITH_PROPERTIES(.NORMAL_SHADING.,#830,(#831));
#833=SURFACE_SIDE_STYLE('',(#832));
#834=SURFACE_STYLE_USAGE(.BOTH.,#833);
#835=PRESENTATION_STYLE_ASSIGNMENT((#834));
#837=STYLED_ITEM('',(#835),#801);
#840=COLOUR_RGB('',1.,0.,0.);
#841=SURFACE_STYLE_TRANSPARENT(0.4);
#842=SURFACE_STYLE_RENDERING_WITH_PROPERTIES(.NORMAL_SHADING.,#840,(#841));
#843=SURFACE_SIDE_STYLE('',(#842));
#845=SURFACE_STYLE_USAGE(.BOTH.,#843);
#846=PRESENTATION_STYLE_BY_CONTEXT((#845),#84);
#847=CONTEXT_DEPENDENT_OVER_RIDING_STYLED_ITEM('',(#846),#801,#837,(#84));
#850=COLOUR_RGB('',0.,1.,0.);
#851=SURFACE_STYLE_TRANSPARENT(0.1);
#852=SURFACE_STYLE_RENDERING_WITH_PROPERTIES(.NORMAL_SHADING.,#850,(#851));
#853=SURFACE_SIDE_STYLE('',(#852));
#854=SURFACE_STYLE_USAGE(.BOTH.,#853);
#855=PRESENTATION_STYLE_ASSIGNMENT((#854));
#857=STYLED_ITEM('',(#855),#802);
#860=PRESENTATION_STYLE_BY_CONTEXT((NULL_STYLE(.NULL.)),#99);
#861=STYLED_ITEM('',(#860),#801);
#870=PRESENTATION_STYLE_BY_CONTEXT((NULL_STYLE(.NULL.)),#801);
#871=STYLED_ITEM('',(#870),#36);
#880=PRESENTATION_STYLE_ASSIGNMENT((NULL_STYLE(.NULL.)));
#881=STYLED_ITEM('',(#880),#38);
#890=DRAUGHTING_MODEL('',(#837,#847,#857,#861,#871,#881),#7);
#891=PRESENTATION_LAYER_ASSIGNMENT('sibling usage layer','',(#861));
#892=PRESENTATION_LAYER_ASSIGNMENT('selected usage layer','',(#847));
#893=PRESENTATION_LAYER_ASSIGNMENT('common face layer','',(#36));
#894=PRESENTATION_LAYER_ASSIGNMENT('selected definition face layer','',(#871));
ENDSEC;
END-ISO-10303-21;
"""#
}
