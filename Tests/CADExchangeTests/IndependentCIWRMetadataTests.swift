import Foundation
import Testing
import CADCore
import CADGeometry
import CADIR
import CADKernel
import CADTopology
@testable import CADExchange

@Suite("Independent CIWR item metadata")
struct IndependentCIWRMetadataTests {
    private func literal(shared: Bool = true, defaults: Bool = false) -> String {
        let bodyName = defaults ? "''" : "'body inspection'"
        let faceName = defaults ? "''" : #"'inspection \X2\00650301\X0\'"#
        var text = Self.geometryFixture
            .replacingOccurrences(of: "ADVANCED_FACE('face alpha'", with: "ADVANCED_FACE(''")
            .replacingOccurrences(of: "SHELL_BASED_SURFACE_MODEL('body alpha'", with: "SHELL_BASED_SURFACE_MODEL(''")
        if !shared {
            let excluded = Set([50,51,52,53,54,55,62,63,65,70,71,72,73,74,75,80,82,83,84,85,86,87,90,91,92,93,94,600,601,602,603,604,605,606,607])
            text = text.split(separator: "\n", omittingEmptySubsequences: false).filter { line in
                guard line.first == "#", let separator = line.firstIndex(of: "="),
                      let id = Int(line[line.index(after: line.startIndex)..<separator]) else { return true }
                return !excluded.contains(id)
            }.joined(separator: "\n")
        }
        let records = """
        #750=SHAPE_REPRESENTATION('',(#38),#7);
        #751=CHARACTERIZED_ITEM_WITHIN_REPRESENTATION(\(bodyName),$,#38,#750);
        #752=SHAPE_REPRESENTATION('',(#36),#7);
        #753=CHARACTERIZED_ITEM_WITHIN_REPRESENTATION(\(faceName),\(defaults ? "$" : "''"),#36,#752);
        """
        return text.replacingOccurrences(of: "ENDSEC;\nEND-ISO", with: records + "\nENDSEC;\nEND-ISO")
    }
    private func imported(_ text: String) throws -> CADDocument {
        try #require(STEPExchange(tolerance: .standard).import(Data(text.utf8)).document)
    }
    private func emitted(_ document: CADDocument) throws -> String {
        let sink = DataByteSink()
        try STEPExchange(tolerance: .standard).write(DocumentEvaluator(tolerance: .standard).evaluateExact(document), to: sink)
        return try #require(String(data: sink.bytes, encoding: .utf8))
    }
    private func count(_ entity: String, in text: String) -> Int {
        text.components(separatedBy: "=" + entity + "(").count - 1
    }
    private func inspectLiteralGeometry(_ signature: SubshapeGeometrySignature) throws {
        let face: FaceGeometrySignature
        switch signature {
        case let .face(value): face = value
        case let .body(value):
            #expect(value.kind == .sheet && value.shells.count == 1)
            let shell = try #require(value.shells.first)
            #expect(shell.orientation == .forward && shell.faces.count == 1)
            face = try #require(shell.faces.first)
        default:
            Issue.record("Characterization must retain the literal body or face.")
            return
        }
        #expect(face.surface == .plane(Plane3D(origin: .origin, normal: Vector3D(x: 0, y: 0, z: 1))))
        #expect(face.orientation == .forward && face.loops.count == 1)
        let loop = try #require(face.loops.first)
        #expect(loop.role == .outer && loop.coedges.count == 3)
        let vertices = [Point3D.origin, Point3D(x: 0.04, y: 0, z: 0), Point3D(x: 0, y: 0.02, z: 0)]
        for (index, coedge) in loop.coedges.enumerated() {
            guard index < vertices.count else { continue }
            let start = vertices[index], end = vertices[(index + 1) % vertices.count]
            #expect(coedge.orientation == .forward)
            #expect((coedge.edge.startPoint - start).length <= ModelingTolerance.standard.distance)
            #expect((coedge.edge.endPoint - end).length <= ModelingTolerance.standard.distance)
            #expect(coedge.edge.startParameter == nil && coedge.edge.endParameter == nil)
            guard case let .line(line) = coedge.edge.curve else {
                Issue.record("The independently authored triangle requires straight spatial edges.")
                continue
            }
            let direction = try (end - start).normalized(tolerance: ModelingTolerance.standard.distance)
            #expect((line.origin - start).length <= ModelingTolerance.standard.distance)
            #expect((line.direction - direction).length <= ModelingTolerance.standard.angle)
            let controls: [Point2D]
            switch coedge.surfaceParameterCurve {
            case let .polyline(points): controls = points.map { Point2D(x: $0.u, y: $0.v) }
            case let .bSpline(curve):
                // These algebraic conditions prove the complete linear p-curve, not sampled agreement.
                #expect(curve.degree == 1 && curve.knots == [0, 0, 1, 1] && curve.weights == [1, 1])
                controls = curve.controlPoints
            default:
                Issue.record("The triangle requires an exact linear p-curve.")
                continue
            }
            #expect(controls.count == 2)
            let first = try #require(controls.first), last = try #require(controls.last)
            #expect(abs(first.x - start.x) <= ModelingTolerance.standard.distance && abs(first.y - start.y) <= ModelingTolerance.standard.distance)
            #expect(abs(last.x - end.x) <= ModelingTolerance.standard.distance && abs(last.y - end.y) <= ModelingTolerance.standard.distance)
        }
    }
    private func inspect(_ document: CADDocument, instances: Int, shared: Bool) throws {
        #expect(document.designGraph.nodes.count == 1)
        #expect((document.assembly != nil) == shared)
        let source = document.productAttributes
        #expect(source.materials.isEmpty && source.assignments.isEmpty && source.layers.isEmpty && source.shapeElementDescriptions.isEmpty)
        #expect(source.itemCharacterizations.count == 2)
        let body = try #require(source.itemCharacterizations.first { $0.target.kind == .body })
        let face = try #require(source.itemCharacterizations.first { $0.target.kind == .face })
        #expect(body.name.utf8.elementsEqual("body inspection".utf8) && body.description == nil)
        #expect(face.name.utf8.elementsEqual("inspection e\u{301}".utf8) && face.description != nil && face.description?.utf8.isEmpty == true)
        let evaluated = try DocumentEvaluator(tolerance: .standard).evaluateExact(document)
        let localModel = evaluated.assembly?.local.model ?? evaluated.brep
        #expect(localModel.bodies.count == 1 && localModel.faces.count == 1 && localModel.edges.count == 3 && localModel.vertices.count == 3)
        #expect(evaluated.brep.bodies.count == instances && evaluated.brep.faces.count == instances)
        let resolver = ProductAttributeResolver(), resolved = try resolver.resolve(evaluated)
        #expect(resolved.localGeometry.count == 2)
        #expect(resolved.values.values.allSatisfy { $0.properties.isEmpty && $0.layers.isEmpty })
        for record in source.itemCharacterizations {
            let geometry = try #require(record.target.geometry)
            #expect(record.target.definitionID == nil && record.target.path == nil && record.target.usageID == nil)
            // The genuine imported producer, not a second test-built signature, establishes exact current correspondence.
            #expect(try resolver.sourceReference(for: geometry.subshapeID, in: evaluated) == geometry)
            try inspectLiteralGeometry(geometry.geometrySignature)
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func noPropertyLiteralSurvivesSharedNativeTwoSTEPGenerationsAndThirdDefinition() throws {
        var document = try imported(literal())
        try inspect(document, instances: 2, shared: true)
        for _ in 0..<2 {
            let sink = DataByteSink(), store = NativePackageStore(tolerance: .standard)
            try store.writePackage(for: document, to: sink)
            #expect(try store.loadDocument(from: sink.bytes) == document)
            let text = try emitted(document)
            #expect(count("CHARACTERIZED_ITEM_WITHIN_REPRESENTATION", in: text) == 2)
            #expect(count("PROPERTY_DEFINITION", in: text) == 0 && count("ADVANCED_FACE", in: text) == 1)
            document = try imported(text)
            try inspect(document, instances: 2, shared: true)
        }
        var assembly = try #require(document.assembly)
        let leaf = try #require(assembly.definitions.first { !$0.features.isEmpty })
        let third = AssemblyDefinition(formationID: leaf.formationID, identifier: "third metadata view", features: leaf.features)
        assembly.definitions.append(third)
        let parent = try #require(assembly.definitions.firstIndex { !$0.children.isEmpty })
        assembly.definitions[parent].children.append(AssemblyOccurrence(definitionID: third.id,
            placement: .translated(by: Vector3D(x: 0.2, y: 0.3, z: 0))))
        document.assembly = assembly
        #expect(Set(assembly.definitions.flatMap(\.features)).count == 1)
        document = try imported(emitted(document))
        try inspect(document, instances: 3, shared: true)
    }

    @Test(.timeLimit(.minutes(1)))
    func noProductMetadataMemoryURLAndCanonicalDefaultsRetainOrdinarySource() throws {
        let source = try imported(literal(shared: false))
        try inspect(source, instances: 1, shared: false)
        let defaults = try imported(literal(shared: false, defaults: true))
        #expect(defaults.assembly == nil && defaults.productAttributes.isEmpty)
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { do { try FileManager.default.removeItem(at: directory) } catch { Issue.record("Unable to remove item metadata fixture: \(error)") } }
        let url = directory.appendingPathComponent("independent.step")
        let facade = OfficialFormatExchange(tolerance: .standard)
        try facade.export(DocumentEvaluator(tolerance: .standard).evaluate(source), as: .step, to: url)
        let fromURL = try #require(facade.import(from: url).document)
        try inspect(fromURL, instances: 1, shared: false)
        let text = try emitted(fromURL)
        #expect(text.contains("PRODUCT('SWIFTCAD',''"))
        try inspect(imported(text), instances: 1, shared: false)
    }

    @Test(.timeLimit(.minutes(1)))
    func physicalAttachmentsReuseIndependentWrapperWithoutCreatingMetadataValues() throws {
        var document = try imported(literal())
        let target = try #require(document.productAttributes.itemCharacterizations.first { $0.target.kind == .face }).target
        let material = PhysicalMaterialDescriptor(name: "steel", description: "descriptor", density: PhysicalDensity(kilogramsPerCubicMeter: 7850))
        document.productAttributes.materials = [material]
        document.productAttributes.assignments = [ProductAttributeAssignment(target: target, value: .material(material.id)),
            ProductAttributeAssignment(target: target, value: .descriptorDensity(material.id))]
        let text = try emitted(document)
        #expect(count("CHARACTERIZED_ITEM_WITHIN_REPRESENTATION", in: text) == 2)
        let restored = try imported(text)
        #expect(restored.productAttributes.itemCharacterizations.count == 2 && restored.productAttributes.assignments.count == 2)
        let face = try #require(restored.productAttributes.itemCharacterizations.first { $0.target.kind == .face })
        #expect(restored.productAttributes.assignments.allSatisfy { $0.target == face.target })
        let resolved = try ProductAttributeResolver().resolve(DocumentEvaluator(tolerance: .standard).evaluateExact(restored))
        let faces = resolved.values.filter { if case .face = $0.key.topology { return true }; return false }
        #expect(faces.count == 2 && faces.values.allSatisfy { $0.properties[.density]?.value == .density(PhysicalDensity(kilogramsPerCubicMeter: 7850)) })
    }

    @Test(.timeLimit(.minutes(1)))
    func strictElevenRequiresOnlyNewKeyAndRefusesPriorEnvelope() throws {
        let document = try imported(literal(shared: false))
        let store = NativePackageStore(tolerance: .standard), sink = DataByteSink()
        try store.writePackage(for: document, to: sink)
        for mutation in 0..<4 {
            let bytes = try StoredZipArchive.withEntries(from: BorrowedBytes(sink.bytes)) { entries in
                var result: [StoredZipArchive.Entry] = []
                for path in ["manifest.json", "document.json"] {
                    let entry = try #require(entries[path])
                    var object = try #require(JSONSerialization.jsonObject(with: entry) as? [String: Any])
                    if mutation == 0 {
                        var version = try #require(object["schemaVersion"] as? [String: Any]); version["minor"] = 10; object["schemaVersion"] = version
                    } else if path == "document.json" {
                        var attributes = try #require(object["productAttributes"] as? [String: Any])
                        let records = attributes.removeValue(forKey: "itemCharacterizations")
                        if mutation == 1 { attributes["physicalCharacterizations"] = records }
                        if mutation == 3 { attributes["itemCharacterizations"] = records; attributes["physicalCharacterizations"] = [] }
                        object["productAttributes"] = attributes
                    }
                    result.append(.init(path: path, data: try JSONSerialization.data(withJSONObject: object)))
                }
                return try StoredZipArchive.make(entries: result)
            }
            if mutation == 0 { #expect(throws: SchemaError.self) { _ = try store.loadDocument(from: bytes) } }
            else { #expect(throws: (any Error).self) { _ = try store.loadDocument(from: bytes) } }
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func invalidViewsBudgetCancellationAndDefaultSourceRefuseAtomically() async throws {
        for malformed in [literal().replacingOccurrences(of: "'',(#36),#7", with: "'',(#36,#38),#7"),
            literal().replacingOccurrences(of: #"'inspection \X2\00650301\X0\','',#36,#752"#, with: #"'inspection \X2\00650301\X0\','',#999,#752"#),
            literal().replacingOccurrences(of: "#750=SHAPE_REPRESENTATION('',(#38),#7)", with: "#750=SHAPE_REPRESENTATION('',(#38),#100)"),
            literal().replacingOccurrences(of: "#753=CHARACTERIZED_ITEM_WITHIN_REPRESENTATION", with: "#753=CONTEXT_DEPENDENT_SHAPE_REPRESENTATION")] {
            #expect(throws: (any Error).self) { _ = try imported(malformed) }
        }
        let source = try imported(literal(shared: false))
        let exact = try DocumentEvaluator(tolerance: .standard).evaluateExact(source)
        let sink = DataByteSink()
        do {
            try STEPExchange(tolerance: .standard, resourceLimits: ExchangeResourceLimits(maximumIterations: 1)).write(exact, to: sink)
            Issue.record("Independent metadata export exceeded caller work.")
        } catch let error as ProductAttributeError { guard case .resourceLimitExceeded = error else { Issue.record("Unexpected resource classification: \(error)"); return } }
        #expect(sink.bytes.isEmpty)
        let immutable = exact
        let task = Task {
            let output = DataByteSink(); withUnsafeCurrentTask { $0?.cancel() }
            do { try STEPExchange(tolerance: .standard).write(immutable, to: output); Issue.record("Cancelled independent metadata export succeeded.") }
            catch is CancellationError {}
            return output.bytes
        }
        #expect(try await task.value.isEmpty)
        var invalid = source
        let target = try #require(source.productAttributes.itemCharacterizations.first).target
        invalid.productAttributes.itemCharacterizations = [ProductItemCharacterization(target: target, name: "", description: nil)]
        let native = DataByteSink(), store = NativePackageStore(tolerance: .standard)
        let failure = ProductAttributeError.invalidSource("Default physical characterization must be absent.")
        #expect(throws: failure) { try store.writePackage(for: invalid, to: native) }
        #expect(native.bytes.isEmpty)
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { do { try FileManager.default.removeItem(at: directory) } catch { Issue.record("Unable to remove atomic fixture: \(error)") } }
        let url = directory.appendingPathComponent("metadata.step"), original = Data("existing complete document".utf8)
        try original.write(to: url)
        #expect(throws: failure) { try store.save(invalid, to: url) }
        #expect(try Data(contentsOf: url) == original)
        #expect(throws: (any Error).self) {
            try OfficialFormatExchange(tolerance: .standard,
                stepExchange: STEPExchange(tolerance: .standard, resourceLimits: ExchangeResourceLimits(maximumIterations: 1)))
                .export(DocumentEvaluator(tolerance: .standard).evaluate(source), as: .step, to: url)
        }
        #expect(try Data(contentsOf: url) == original)
    }
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
#54=MANIFOLD_SURFACE_SHAPE_REPRESENTATION('',(#38,#17),#7);
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
