import Foundation
import Testing
import CADCore
import CADGeometry
import CADIR
import CADKernel
import CADTopology
@testable import CADExchange

@Suite("Partial STEP item sharing and source scopes")
struct PartialSTEPRepresentationTests {
    private func imported(_ literal: String = Self.fixture) throws -> CADDocument {
        try #require(OfficialFormatExchange(tolerance: .standard).import(BorrowedBytes(Data(literal.utf8)), as: .step).document)
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
    private func inspect(_ document: CADDocument, third: Bool = false) throws {
        let source = try #require(document.assembly)
        let design = try #require(source.definitions.first { $0.identifier == "design" })
        let analysis = try #require(source.definitions.first { $0.identifier == "analysis" })
        #expect(design.features.count == 1 && analysis.features.count == 2)
        #expect(Set(design.features).isSubset(of: Set(analysis.features)))
        #expect(document.designGraph.nodes.count == 2)
        let common = try #require(design.features.first)
        let other = try #require(analysis.features.first { $0 != common })
        let evaluated = try DocumentEvaluator(tolerance: .standard).evaluateExact(document)
        let artifact = try #require(evaluated.assembly)
        #expect(artifact.local.model.bodies.count == 2 && artifact.local.model.faces.count == 2 && artifact.local.model.vertices.count == 6)
        #expect(evaluated.brep.bodies.count == (third ? 4 : 3) && evaluated.brep.faces.count == (third ? 4 : 3))
        #expect(artifact.local.model.vertices.values.contains { abs($0.point.x - 0.12) < 1e-12 && abs($0.point.y) < 1e-12 })
        #expect(evaluated.brep.vertices.values.contains { abs($0.point.x - 0.15) < 1e-12 && abs($0.point.y - 0.1) < 1e-12 })
        let resolved = try ProductAttributeResolver().resolve(evaluated)
        let material = try #require(document.productAttributes.materials.first { $0.name == "steel" })
        let physical = document.productAttributes.assignments.filter { $0.value.property == .material || $0.value.property == .density }
        #expect(physical.count == 4)
        #expect(physical.contains { $0.value.property == .material && $0.target.geometry?.subshapeID.featureID == common && $0.target.definitionID == nil && $0.target.path == nil })
        #expect(physical.contains { $0.value.property == .density && $0.target.geometry?.subshapeID.featureID == other && $0.target.definitionID == nil && $0.target.path == nil })
        let globalLayer = try #require(document.productAttributes.layers.first { $0.name == "common face" })
        let scopedLayer = try #require(document.productAttributes.layers.first { $0.name == "design face only" })
        #expect(scopedLayer.members.count == 1 && scopedLayer.members.first?.definitionID == design.id)
        var commonInstances = 0, otherInstances = 0
        for occurrence in artifact.occurrences {
            for feature in occurrence.features {
                #expect(feature.bodies.count == 1 && feature.faces.count == 1)
                let body = try #require(feature.bodies.values.first), face = try #require(feature.faces.values.first)
                let bodyProperties = try #require(resolved.values[ResolvedProductTarget(topology: .body(body), definitionID: occurrence.definitionID, path: occurrence.path)])
                let faceProperties = try #require(resolved.values[ResolvedProductTarget(topology: .face(face), definitionID: occurrence.definitionID, path: occurrence.path)])
                if feature.featureID == common {
                    commonInstances += 1
                    #expect(bodyProperties.properties[.material]?.value == .material(material.id))
                    #expect(faceProperties.properties[.material]?.value == .material(material.id))
                    #expect(bodyProperties.properties[.density] == nil)
                    #expect(faceProperties.layers.contains(globalLayer.id))
                    let selected = occurrence.definitionID == design.id
                    #expect(faceProperties.layers.contains(scopedLayer.id) == selected)
                    if selected {
                        #expect(faceProperties.properties[.density]?.value == .density(PhysicalDensity(kilogramsPerCubicMeter: 1000)))
                        #expect(faceProperties.properties[.color]?.value == .color(ColorRGBA(r: 1, g: 1, b: 0, a: 1)))
                        #expect(faceProperties.properties[.color]?.assignmentChain.count == 3)
                    } else if occurrence.definitionID == analysis.id {
                        #expect(faceProperties.properties[.density]?.value == .density(PhysicalDensity(kilogramsPerCubicMeter: 2000)))
                        #expect(faceProperties.properties[.color]?.value == .color(ColorRGBA(r: 0, g: 1, b: 0, a: 1)))
                        #expect(faceProperties.properties[.color]?.assignmentChain.count == 3)
                    } else {
                        #expect(faceProperties.properties[.density] == nil)
                        #expect(faceProperties.properties[.color]?.value == .color(ColorRGBA(r: 1, g: 0, b: 0, a: 1)))
                        #expect(faceProperties.properties[.color]?.assignmentChain.count == 2)
                    }
                } else {
                    otherInstances += 1
                    #expect(feature.featureID == other && occurrence.definitionID == analysis.id)
                    #expect(faceProperties.properties[.density]?.value == .density(PhysicalDensity(kilogramsPerCubicMeter: 7000)))
                    #expect(bodyProperties.properties[.material] == nil && faceProperties.properties[.material] == nil)
                    #expect(bodyProperties.properties[.color]?.value == .color(ColorRGBA(r: 0.25, g: 0.5, b: 0.75, a: 1)))
                    #expect(faceProperties.properties[.color]?.value == .color(ColorRGBA(r: 0.25, g: 0.5, b: 0.75, a: 1)))
                    #expect(faceProperties.properties[.color]?.assignmentChain.count == 1 && faceProperties.layers.isEmpty)
                }
            }
        }
        #expect(commonInstances == (third ? 3 : 2) && otherInstances == 1)
    }
    private func inspectTransport(_ bytes: Data) throws {
        let table = try entities(bytes), syntax = STEPAssemblySyntax(entities: table)
        #expect(try table.keys.filter { try syntax.name($0) == "SHELL_BASED_SURFACE_MODEL" }.count == 2)
        #expect(try table.keys.filter { try syntax.name($0) == "ADVANCED_FACE" }.count == 2)
        #expect(try table.keys.filter { try syntax.name($0) == "CHARACTERIZED_ITEM_WITHIN_REPRESENTATION" }.count == 2)
        var associated = Set<Int>(), globalViews: [Int: Int] = [:]
        for id in table.keys {
            let name = try syntax.name(id)
            if name == "SHAPE_DEFINITION_REPRESENTATION" {
                associated.insert(try syntax.reference(syntax.arguments(id)[1]))
            } else if name == "CHARACTERIZED_ITEM_WITHIN_REPRESENTATION" {
                let a = try syntax.arguments(id)
                globalViews[try syntax.reference(a[3])] = try syntax.reference(a[2])
            }
        }
        var groups: [Set<Int>] = []
        var bodyContexts: [Int: Set<Int>] = [:]
        for id in table.keys {
            let name = try syntax.name(id)
            if name == "MANIFOLD_SURFACE_SHAPE_REPRESENTATION" {
                let a = try syntax.arguments(id), items = try syntax.list(a[1])
                let bodies = try Set(items.filter { try syntax.name($0) == "SHELL_BASED_SURFACE_MODEL" })
                if !bodies.isEmpty {
                    groups.append(bodies)
                    let context = try syntax.reference(a[2])
                    for body in bodies { bodyContexts[body, default: []].insert(context) }
                }
            } else if name == "SHAPE_REPRESENTATION" {
                let a = try syntax.arguments(id), items = try syntax.list(a[1])
                let directBodies = try items.filter { try ["SHELL_BASED_SURFACE_MODEL", "MANIFOLD_SOLID_BREP", "BREP_WITH_VOIDS"].contains(syntax.name($0)) }
                if !directBodies.isEmpty {
                    // An unassociated singleton CIWR view characterizes an existing item; it is not a PD geometry representation.
                    #expect(!associated.contains(id) && items.count == 1 && directBodies.count == 1)
                    #expect(globalViews[id] == directBodies.first)
                }
                for item in items where try syntax.name(item) == "MAPPED_ITEM" {
                    let ma = try syntax.arguments(item), map = try syntax.reference(ma[1])
                    let mapping = try syntax.arguments(map), child = try syntax.reference(mapping[1])
                    // A real generic assembly usage maps an associated child PD; a geometry carrier maps unassociated inner geometry.
                    #expect(associated.contains(id) && associated.contains(child))
                    #expect(try syntax.list(syntax.arguments(child)[1]).contains(syntax.reference(mapping[0])))
                }
            } else if name == "REPRESENTATION_MAP" {
                let a = try syntax.arguments(id), inner = try syntax.reference(a[1])
                if !associated.contains(inner) {
                    #expect(try syntax.name(inner) == "MANIFOLD_SURFACE_SHAPE_REPRESENTATION")
                    #expect(try syntax.list(syntax.arguments(inner)[1]).contains { try syntax.name($0) == "SHELL_BASED_SURFACE_MODEL" })
                }
            }
        }
        #expect(bodyContexts.count == 2 && bodyContexts.values.allSatisfy { $0.count == 1 })
        let single = try #require(groups.first { $0.count == 1 }), pair = try #require(groups.first { $0.count == 2 })
        #expect(single.isSubset(of: pair))
    }
    @Test(.timeLimit(.minutes(1)))
    func independentPartialItemsPreserveOneOwnerNativeAndTwoSTEPGenerations() throws {
        var current = try imported()
        try inspect(current)
        let native = DataByteSink(), store = NativePackageStore(tolerance: .standard)
        try store.writePackage(for: current, to: native)
        #expect(try store.loadDocument(from: native.bytes) == current)
        for _ in 0..<2 {
            let sink = DataByteSink()
            try OfficialFormatExchange(tolerance: .standard).write(DocumentEvaluator(tolerance: .standard).evaluate(current), as: .step, to: sink)
            try inspectTransport(sink.bytes)
            current = try #require(OfficialFormatExchange(tolerance: .standard).import(BorrowedBytes(sink.bytes), as: .step).document)
            try inspect(current)
        }
    }
    @Test(.timeLimit(.minutes(1)))
    func thirdPDReusesCommonFeatureAndRetainsGlobalVersusQualifiedScope() throws {
        var document = try imported(), source = try #require(document.assembly)
        let selected = try #require(source.definitions.first { $0.identifier == "design" })
        let third = AssemblyDefinition(formationID: selected.formationID, identifier: "third view", features: selected.features)
        source.definitions.append(third)
        let parent = try #require(source.definitions.firstIndex { !$0.children.isEmpty })
        source.definitions[parent].children.append(AssemblyOccurrence(definitionID: third.id,
            placement: RigidTransform3D.translated(by: Vector3D(x: 0.2, y: 0.3, z: 0))))
        document.assembly = source
        try inspect(document, third: true)
        let sink = DataByteSink()
        try STEPExchange(tolerance: .standard).write(DocumentEvaluator(tolerance: .standard).evaluateExact(document), to: sink)
        try inspectTransport(sink.bytes)
        let restored = try #require(STEPExchange(tolerance: .standard).import(sink.bytes).document)
        try inspect(restored, third: true)
    }
    @Test(.timeLimit(.minutes(1)))
    func equalValuedDistinctItemsRemainDistinctSourceOwners() throws {
        let literal = Self.fixture.replacingOccurrences(of: "#210=CARTESIAN_POINT('',(80.,0.,0.));", with: "#210=CARTESIAN_POINT('',(0.,0.,0.));")
            .replacingOccurrences(of: "#211=CARTESIAN_POINT('',(120.,0.,0.));", with: "#211=CARTESIAN_POINT('',(40.,0.,0.));")
            .replacingOccurrences(of: "#212=CARTESIAN_POINT('',(80.,20.,0.));", with: "#212=CARTESIAN_POINT('',(0.,20.,0.));")
        let document = try imported(literal), evaluated = try DocumentEvaluator(tolerance: .standard).evaluateExact(document)
        #expect(document.designGraph.nodes.count == 2)
        #expect(evaluated.assembly?.local.model.bodies.count == 2 && evaluated.brep.bodies.count == 3)
        let sink = DataByteSink(); try STEPExchange(tolerance: .standard).write(evaluated, to: sink)
        try inspectTransport(sink.bytes)
        let restored = try #require(STEPExchange(tolerance: .standard).import(sink.bytes).document)
        #expect(restored.designGraph.nodes.count == 2)
        #expect(try DocumentEvaluator(tolerance: .standard).evaluateExact(restored).assembly?.local.model.bodies.count == 2)
    }
    @Test(.timeLimit(.minutes(1)))
    func foreignUnitsTopologyAndCarrierFamilyRefuseWithoutPublication() throws {
        let differentUnits = Self.fixture.replacingOccurrences(of: "GLOBAL_UNIT_ASSIGNED_CONTEXT((#4,#5,#6)) REPRESENTATION_CONTEXT('second view','')",
            with: "GLOBAL_UNIT_ASSIGNED_CONTEXT((#705,#5,#6)) REPRESENTATION_CONTEXT('second view','')")
        #expect(throws: AssemblyError.invalidSource("Shared geometry has conflicting owned units.")) { _ = try imported(differentUnits) }
        let competingTopology = Self.fixture.replacingOccurrences(of: "#238=SHELL_BASED_SURFACE_MODEL('body beta',(#237));", with: "#238=SHELL_BASED_SURFACE_MODEL('body beta',(#37));")
        #expect(throws: AssemblyError.invalidSource("Distinct exact items have competing topology ownership.")) { _ = try imported(competingTopology) }
        let wrongFamily = Self.fixture.replacingOccurrences(of: "#810=MANIFOLD_SURFACE_SHAPE_REPRESENTATION", with: "#810=ADVANCED_BREP_SHAPE_REPRESENTATION")
        #expect(throws: AssemblyError.invalidSource("Whole-part carrier has conflicting representation family.")) { _ = try imported(wrongFamily) }
        let nonidentity = Self.fixture.replacingOccurrences(of: "#802=CARTESIAN_TRANSFORMATION_OPERATOR_3D('',*,*,#14,#805,#10,1.,#13);", with: "#802=CARTESIAN_TRANSFORMATION_OPERATOR_3D('',*,*,#14,#805,#80,1.,#13);")
        #expect(throws: AssemblyError.invalidSource("Whole-part carrier transform is not identity.")) { _ = try imported(nonidentity) }
        let foreignScope = Self.fixture.replacingOccurrences(of: "#703=GEOMETRIC_ITEM_SPECIFIC_USAGE('','',#702,#744,#36);", with: "#703=GEOMETRIC_ITEM_SPECIFIC_USAGE('','',#700,#744,#236);")
        #expect(throws: ProductAttributeError.missingTarget("Shape aspect geometry correspondence.")) { _ = try imported(foreignScope) }
    }
    @Test(.timeLimit(.minutes(1)))
    func callerResourceCeilingsPreserveMemoryAndAtomicDestination() throws {
        let document = try imported(), evaluated = try DocumentEvaluator(tolerance: .standard).evaluate(document)
        let limits = ExchangeResourceLimits(maximumIterations: 1)
        let facade = OfficialFormatExchange(tolerance: .standard, stepExchange: STEPExchange(tolerance: .standard, resourceLimits: limits)), sink = DataByteSink()
        #expect(throws: AssemblyError.resourceLimitExceeded("source work")) { try facade.write(evaluated, as: .step, to: sink) }
        #expect(sink.bytes.isEmpty)
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { do { try FileManager.default.removeItem(at: directory) } catch { Issue.record("Unable to remove partial item fixture: \(error)") } }
        let url = directory.appendingPathComponent("partial.step"), original = Data("existing complete destination".utf8)
        try original.write(to: url)
        #expect(throws: AssemblyError.resourceLimitExceeded("source work")) { try facade.export(evaluated, as: .step, to: url) }
        #expect(try Data(contentsOf: url) == original)
        #expect(throws: KernelError.self) { _ = try STEPExchange(tolerance: .standard, resourceLimits: limits).import(Data(Self.fixture.utf8)) }
    }
    @Test(.timeLimit(.minutes(1)))
    func cancelledPartialImportAndExportDoNotPublish() async throws {
        let evaluated = try DocumentEvaluator(tolerance: .standard).evaluate(imported())
        let importTask = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try STEPExchange(tolerance: .standard).import(Data(Self.fixture.utf8))
        }
        do { _ = try await importTask.value; Issue.record("Cancelled partial import published source.") }
        catch is CancellationError {}
        let exportTask = Task {
            let sink = DataByteSink()
            withUnsafeCurrentTask { $0?.cancel() }
            do {
                try OfficialFormatExchange(tolerance: .standard).write(evaluated, as: .step, to: sink)
                Issue.record("Cancelled partial export published output.")
            } catch is CancellationError {}
            return sink.bytes
        }
        #expect(try await exportTask.value.isEmpty)
    }
    // Independently authored exact triangles and standard product/style/property records.
    // The two PD-associated same-family carriers share item #38; only the second contains #238.
    // No production STEP writer constructs the fixture or its malformed variants.
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
#54=MANIFOLD_SURFACE_SHAPE_REPRESENTATION('',(#801,#17),#7);
#55=SHAPE_DEFINITION_REPRESENTATION(#53,#54);
#62=PRODUCT_DEFINITION('analysis',$,#51,#3);
#63=PRODUCT_DEFINITION_SHAPE('','',#62);
#64=MANIFOLD_SURFACE_SHAPE_REPRESENTATION('',(#803,#17),#9);
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
#741=DRAUGHTING_MODEL('',(#724,#732,#740,#843,#858,#927),#7);
#742=PRESENTATION_LAYER_ASSIGNMENT('common face','shared item layer',(#36));
#743=SHAPE_REPRESENTATION('',(#36),#7);
#744=SHAPE_REPRESENTATION('',(#36),#9);
#210=CARTESIAN_POINT('',(80.,0.,0.));
#211=CARTESIAN_POINT('',(120.,0.,0.));
#212=CARTESIAN_POINT('',(80.,20.,0.));
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
#800=REPRESENTATION_MAP(#17,#810);
#801=MAPPED_ITEM('',#800,#802);
#802=CARTESIAN_TRANSFORMATION_OPERATOR_3D('',*,*,#14,#805,#10,1.,#13);
#803=MAPPED_ITEM('',#804,#802);
#804=REPRESENTATION_MAP(#17,#812);
#805=DIRECTION('',(0.,1.,0.));
#810=MANIFOLD_SURFACE_SHAPE_REPRESENTATION('',(#38,#17),#7);
#812=MANIFOLD_SURFACE_SHAPE_REPRESENTATION('',(#38,#238,#17),#9);
#841=PRESENTATION_STYLE_BY_CONTEXT((NULL_STYLE(.NULL.)),#801);
#843=STYLED_ITEM('',(#841),#36);
#844=PRESENTATION_LAYER_ASSIGNMENT('design face only','selected PD layer',(#843));
#850=COLOUR_RGB('',1.,1.,0.);
#851=FILL_AREA_STYLE_COLOUR('',#850);
#852=FILL_AREA_STYLE('',(#851));
#853=SURFACE_STYLE_FILL_AREA(#852);
#854=SURFACE_SIDE_STYLE('',(#853));
#855=SURFACE_STYLE_USAGE(.BOTH.,#854);
#857=PRESENTATION_STYLE_BY_CONTEXT((#855),#801);
#858=CONTEXT_DEPENDENT_OVER_RIDING_STYLED_ITEM('',(#857),#36,#732,(#801));
#900=SHAPE_REPRESENTATION('',(#38),#7);
#901=CHARACTERIZED_ITEM_WITHIN_REPRESENTATION('',$,#38,#900);
#902=PROPERTY_DEFINITION('material property','material name',#901);
#903=DESCRIPTIVE_REPRESENTATION_ITEM('steel','global shared body material');
#904=REPRESENTATION('material name',(#903),#7);
#905=PROPERTY_DEFINITION_REPRESENTATION(#902,#904);
#910=SHAPE_REPRESENTATION('',(#236),#9);
#911=CHARACTERIZED_ITEM_WITHIN_REPRESENTATION('',$,#236,#910);
#912=(MEASURE_REPRESENTATION_ITEM() MEASURE_WITH_UNIT(MASS_DENSITY_MEASURE(7000.),#708) REPRESENTATION_ITEM('density'));
#913=PROPERTY_DEFINITION('material property','density',#911);
#914=REPRESENTATION('density',(#912),#9);
#915=PROPERTY_DEFINITION_REPRESENTATION(#913,#914);
#920=COLOUR_RGB('',0.25,0.5,0.75);
#921=FILL_AREA_STYLE_COLOUR('',#920);
#922=FILL_AREA_STYLE('',(#921));
#923=SURFACE_STYLE_FILL_AREA(#922);
#924=SURFACE_SIDE_STYLE('',(#923));
#925=SURFACE_STYLE_USAGE(.BOTH.,#924);
#926=PRESENTATION_STYLE_ASSIGNMENT((#925));
#927=STYLED_ITEM('',(#926),#238);
ENDSEC;
END-ISO-10303-21;
"""#
}
