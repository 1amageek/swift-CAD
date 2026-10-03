import Foundation
import Testing
import CADCore
import CADIR
import CADKernel
import CADTopology
@testable import CADExchange

@Suite("STEP assembly public interchange")
struct STEPAssemblyExchangeTests {
    @Test(.timeLimit(.minutes(1)))
    func independentStandardNestedSharedPartsPreserveLocalAndWorldFrames() throws {
        let imported = try OfficialFormatExchange(tolerance: .standard).import(Data(Self.independentFixture.utf8), as: .step)
        let document = try #require(imported.document), source = try #require(document.assembly)
        #expect(source.definitions.count == 3 && document.designGraph.order.count == 1)
        let nested = try #require(source.definitions.first { $0.name == "shared nested assembly" })
        let root = try #require(source.definitions.first { $0.name == "root assembly" })
        #expect(root.children.count == 2 && root.children.allSatisfy { $0.definitionID == nested.id })
        #expect(nested.children.count == 1)
        let evaluated = try DocumentEvaluator(tolerance: .standard).evaluate(document)
        try evaluated.validate()
        let artifact = try #require(evaluated.assembly)
        #expect(artifact.local.model.bodies.count == 1 && evaluated.brep.bodies.count == 2)
        let points = evaluated.brep.vertices.values.map(\.point)
        // Child frame x=10 mm maps to target (100,50); its origin maps to (100,40).
        for (x,y) in [(0.100,0.040),(0.100,0.080),(0.080,0.040),(0.100,0.240),(0.100,0.280),(0.080,0.240)] {
            #expect(points.contains { abs($0.x-x) < 1e-12 && abs($0.y-y) < 1e-12 && abs($0.z) < 1e-12 })
        }
        #expect(artifact.local.model.vertices.values.contains { $0.point.x == 0 && $0.point.y == 0 })
        #expect(imported.brep == evaluated.brep)
        // Independent parent contexts use metres while the shared part stays in millimetres.
        let mixed = Self.independentFixture
            .replacingOccurrences(of: "#8=(GEOMETRIC_REPRESENTATION_CONTEXT(3) GLOBAL_UNIT_ASSIGNED_CONTEXT((#4,#5,#6))", with: "#97=(LENGTH_UNIT() NAMED_UNIT(*) SI_UNIT($,.METRE.));\n#8=(GEOMETRIC_REPRESENTATION_CONTEXT(3) GLOBAL_UNIT_ASSIGNED_CONTEXT((#97,#5,#6))")
            .replacingOccurrences(of: "#9=(GEOMETRIC_REPRESENTATION_CONTEXT(3) GLOBAL_UNIT_ASSIGNED_CONTEXT((#4,#5,#6))", with: "#9=(GEOMETRIC_REPRESENTATION_CONTEXT(3) GLOBAL_UNIT_ASSIGNED_CONTEXT((#97,#5,#6))")
            .replacingOccurrences(of: "(100.,50.,0.)", with: "(0.1,0.05,0.)")
            .replacingOccurrences(of: "(0.,200.,0.)", with: "(0.,0.2,0.)")
        let mixedResult = try STEPExchange(tolerance: .standard).import(Data(mixed.utf8))
        let mixedModel = try #require(mixedResult.brep)
        #expect(samePoints(mixedModel, evaluated.brep))
    }
    @Test(.timeLimit(.minutes(1)))
    func publicSTEPAndNativeRoundTripsKeepDefinitionsPathsAndAtomicURLs() throws {
        let imported = try STEPExchange(tolerance: .standard).import(Data(Self.independentFixture.utf8))
        let document = try #require(imported.document)
        let evaluated = try DocumentEvaluator(tolerance: .standard).evaluate(document)
        let facade = OfficialFormatExchange(tolerance: .standard), sink = DataByteSink()
        try facade.write(evaluated, as: .step, to: sink)
        let text = try #require(String(data: sink.bytes, encoding: .utf8))
        #expect(text.components(separatedBy: "SHELL_BASED_SURFACE_MODEL(").count - 1 == 1)
        let restored = try #require(STEPExchange(tolerance: .standard).import(sink.bytes).document)
        #expect(signature(restored.assembly) == signature(document.assembly))
        let rebuilt = try DocumentEvaluator(tolerance: .standard).evaluate(restored)
        #expect(samePoints(rebuilt.brep, evaluated.brep))
        let native = DataByteSink()
        try NativePackageStore(tolerance: .standard).writePackage(for: document, to: native)
        let nativeDocument = try NativePackageStore(tolerance: .standard).loadDocument(from: native.bytes)
        #expect(nativeDocument == document)
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { do { try FileManager.default.removeItem(at: directory) } catch { Issue.record("Unable to remove assembly test directory: \(error)") } }
        let url = directory.appendingPathComponent("assembly.step")
        try facade.export(evaluated, as: .step, to: url)
        let urlImported = try facade.import(from: url)
        #expect(signature(urlImported.document?.assembly) == signature(document.assembly))
        let before = try Data(contentsOf: url)
        let limited = OfficialFormatExchange(tolerance: .standard, stepExchange: STEPExchange(tolerance: .standard, resourceLimits: ExchangeResourceLimits(maximumEntities: 10)))
        #expect(throws: (any Error).self) { try limited.export(evaluated, as: .step, to: url) }
        #expect(try Data(contentsOf: url) == before)
    }
    @Test(.timeLimit(.minutes(1)))
    func strictNativeAssemblyAdmissionRejectsMissingAndUnknownSourceFields() throws {
        let imported = try STEPExchange(tolerance: .standard).import(Data(Self.independentFixture.utf8))
        let document = try #require(imported.document)
        let store = NativePackageStore(tolerance: .standard), sink = DataByteSink()
        try store.writePackage(for: document, to: sink)
        for mutation in 0..<3 {
            let bytes = try StoredZipArchive.withEntries(from: BorrowedBytes(sink.bytes)) { entries in
                let original = try #require(entries["document.json"])
                var source = try #require(JSONSerialization.jsonObject(with: original) as? [String: Any])
                switch mutation {
                case 0: source.removeValue(forKey: "assembly")
                case 1:
                    var assembly = try #require(source["assembly"] as? [String: Any])
                    assembly["unretainedSource"] = true
                    source["assembly"] = assembly
                default:
                    var assembly = try #require(source["assembly"] as? [String: Any])
                    var roots = try #require(assembly["roots"] as? [[String: Any]])
                    var frame = try #require(roots[0]["placement"] as? [String: Any])
                    frame["scale"] = 2
                    roots[0]["placement"] = frame
                    assembly["roots"] = roots
                    source["assembly"] = assembly
                }
                let header = try #require(entries["manifest.json"])
                return try StoredZipArchive.make(entries: [.init(path: "manifest.json", data: header),
                    .init(path: "document.json", data: JSONSerialization.data(withJSONObject: source, options: [.sortedKeys]))])
            }
            #expect(throws: SchemaError.self) { _ = try store.loadDocument(from: BorrowedBytes(bytes)) }
        }
    }
    @Test(.timeLimit(.minutes(1)))
    func missingAmbiguousCyclicAndBoundedAssembliesRefuse() throws {
        let variants = [
            Self.independentFixture.replacingOccurrences(of: "#94=CONTEXT_DEPENDENT_SHAPE_REPRESENTATION(#93,#91);", with: ""),
            Self.independentFixture.replacingOccurrences(of: "(#44,#46),#8", with: "(#38,#44,#46),#8"),
            Self.independentFixture.replacingOccurrences(of: "#85=NEXT_ASSEMBLY_USAGE_OCCURRENCE('nested first','first','',#72,#62,$);",
                with: "#85=NEXT_ASSEMBLY_USAGE_OCCURRENCE('nested first','first','',#62,#72,$);"),
            Self.independentFixture.replacingOccurrences(of: "#41,#44", with: "#41,#49"),
        ]
        for variant in variants { #expect(throws: (any Error).self) { _ = try STEPExchange(tolerance: .standard).import(Data(variant.utf8)) } }
        #expect(throws: (any Error).self) {
            _ = try STEPExchange(tolerance: .standard, resourceLimits: ExchangeResourceLimits(maximumNesting: 2))
                .import(Data(Self.independentFixture.utf8))
        }
    }
    @Test(.timeLimit(.minutes(1)))
    func independentMappedItemAndCartesianPlacementExecute() throws {
        var fixture = Self.independentFixture
        let start = try #require(fixture.range(of: "#80=NEXT_ASSEMBLY_USAGE_OCCURRENCE"))
        fixture.replaceSubrange(start.lowerBound..<fixture.endIndex, with: """
        #80=REPRESENTATION_MAP(#41,#54);
        #81=MAPPED_ITEM('mapped triangle',#80,#44);
        #82=REPRESENTATION_MAP(#46,#64);
        #83=MAPPED_ITEM('first',#82,#49);
        #84=MAPPED_ITEM('second',#82,#48);
        ENDSEC;
        END-ISO-10303-21;
        """)
        fixture = fixture.replacingOccurrences(of: "(#44,#46),#8", with: "(#81,#44,#46),#8")
            .replacingOccurrences(of: "(#46,#48,#49),#9", with: "(#83,#84,#48,#49),#9")
        let mapped = try #require(STEPExchange(tolerance: .standard).import(Data(fixture.utf8)).brep)
        let ordinary = try #require(STEPExchange(tolerance: .standard).import(Data(Self.independentFixture.utf8)).brep)
        #expect(samePoints(mapped, ordinary))
        var cartesian = Self.independentFixture
        cartesian = cartesian.replacingOccurrences(of: "#82=ITEM_DEFINED_TRANSFORMATION('','',#41,#44);",
            with: "#82=CARTESIAN_TRANSFORMATION_OPERATOR_3D('','','',#43,#95,#96,1.,#13);\n#95=DIRECTION('',(-1.,0.,0.));\n#96=CARTESIAN_POINT('',(100.,40.,0.));")
            .replacingOccurrences(of: "(#44,#46),#8", with: "(#82,#44,#46),#8")
        let explicit = try #require(STEPExchange(tolerance: .standard).import(Data(cartesian.utf8)).brep)
        #expect(samePoints(explicit, ordinary))
        cartesian = cartesian.replacingOccurrences(of: "#96,1.,#13", with: "#96,2.,#13")
        #expect(throws: (any Error).self) { _ = try STEPExchange(tolerance: .standard).import(Data(cartesian.utf8)) }
    }
    private func signature(_ assembly: DocumentAssembly?) -> [String] {
        guard let assembly else { return [] }
        var values = assembly.definitions.map { definition in
            definition.id.description + ":" + definition.name + ":" + String(definition.features.count)
                + ":" + definition.children.map { $0.id.description + ":" + $0.definitionID.description + ":" + String(describing: $0.placement) }.sorted().joined(separator: ";")
        }.sorted()
        values += assembly.roots.map { $0.id.description + ":" + $0.definitionID.description + ":" + String(describing: $0.placement) }.sorted()
        return values
    }
    private func samePoints(_ a: BRepModel, _ b: BRepModel) -> Bool {
        let left = sortedPoints(a), right = sortedPoints(b)
        return left.count == right.count && zip(left, right).allSatisfy { ($0.0 - $0.1).length < 1e-12 }
    }
    private func sortedPoints(_ model: BRepModel) -> [Point3D] {
        model.vertices.values.map(\.point).sorted { a,b in a.x != b.x ? a.x < b.x : a.y != b.y ? a.y < b.y : a.z < b.z }
    }
    // Independently authored from standard product/usage/frame semantics. No production writer builds this fixture.
    // Plane #18 has the +X/+Y chart. Its 2D line origins are (0,0), (40,0), and (0,20)
    // in the part's millimetre length coordinates; directions follow the same forward
    // traversal as their associated 3D lines and all EDGE_CURVE/ORIENTED_EDGE senses.
    private static let independentFixture = #"""
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
#54=SHAPE_REPRESENTATION('',(#38,#41),#7);
#55=SHAPE_DEFINITION_REPRESENTATION(#53,#54);
#60=PRODUCT('nested','shared nested assembly','',(#2));
#61=PRODUCT_DEFINITION_FORMATION('','',#60);
#62=PRODUCT_DEFINITION('design','',#61,#3);
#63=PRODUCT_DEFINITION_SHAPE('','',#62);
#64=SHAPE_REPRESENTATION('',(#44,#46),#8);
#65=SHAPE_DEFINITION_REPRESENTATION(#63,#64);
#70=PRODUCT('root','root assembly','',(#2));
#71=PRODUCT_DEFINITION_FORMATION('','',#70);
#72=PRODUCT_DEFINITION('design','',#71,#3);
#73=PRODUCT_DEFINITION_SHAPE('','',#72);
#74=SHAPE_REPRESENTATION('',(#46,#48,#49),#9);
#75=SHAPE_DEFINITION_REPRESENTATION(#73,#74);
#80=NEXT_ASSEMBLY_USAGE_OCCURRENCE('part usage','rotated triangle','',#62,#52,$);
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
ENDSEC;
END-ISO-10303-21;
"""#
}
