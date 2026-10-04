import Foundation
import Testing
import CADCore
import CADGeometry
import CADIR
import CADKernel
import CADTopology
@testable import CADExchange

@Suite("STEP physical characterization metadata")
struct STEPPhysicalCharacterizationTests {
    private func literal(name: String, description: String, item: Int = 36) -> String {
        let properties = """
        #750=SHAPE_REPRESENTATION('',(#\(item)),#7);
        #751=CHARACTERIZED_ITEM_WITHIN_REPRESENTATION(\(name),\(description),#\(item),#750);
        #752=PROPERTY_DEFINITION('material property','material name',#751);
        #753=DESCRIPTIVE_REPRESENTATION_ITEM('steel','material descriptor');
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
        return Self.geometryFixture.replacingOccurrences(of: "ENDSEC;\nEND-ISO", with: properties + "\nENDSEC;\nEND-ISO")
    }
    private func imported(_ text: String) throws -> CADDocument {
        try #require(STEPExchange(tolerance: .standard).import(Data(text.utf8)).document)
    }
    private func emitted(_ document: CADDocument) throws -> String {
        let sink = DataByteSink()
        try STEPExchange(tolerance: .standard).write(DocumentEvaluator(tolerance: .standard).evaluateExact(document), to: sink)
        return try #require(String(data: sink.bytes, encoding: .utf8))
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
    private func inspect(_ document: CADDocument, name: String, description: String?, count: Int, kind: ProductAttributeTarget.Kind) throws {
        #expect(document.designGraph.nodes.count == 1)
        let metadata = try #require(document.productAttributes.itemCharacterizations.first)
        #expect(document.productAttributes.itemCharacterizations.count == 1 && metadata.target.kind == kind)
        #expect(metadata.name.utf8.elementsEqual(name.utf8))
        switch (metadata.description, description) {
        case (nil, nil): break
        case let (left?, right?): #expect(left.utf8.elementsEqual(right.utf8))
        default: Issue.record("Characterization description lost nullable presence.")
        }
        #expect(metadata.target.definitionID == nil && metadata.target.path == nil && metadata.target.usageID == nil)
        let material = try #require(document.productAttributes.materials.first)
        #expect(material.name == "steel" && material.description == "material descriptor")
        #expect(document.productAttributes.assignments.contains { $0.target == metadata.target && $0.value == .descriptorDensity(material.id) })
        #expect(document.productAttributes.assignments.contains { $0.target == metadata.target && $0.value == .name(kind == .face ? "face alpha" : "body alpha") })
        let evaluated = try DocumentEvaluator(tolerance: .standard).evaluateExact(document)
        let local = try #require(evaluated.assembly?.local)
        let definitions = try #require(document.assembly).definitions.filter { !$0.features.isEmpty }
        #expect(Set(definitions.flatMap(\.features)).count == 1)
        #expect(local.model.bodies.count == 1 && local.model.faces.count == 1)
        #expect(local.model.vertices.count == 3 && local.model.edges.count == 3)
        #expect(evaluated.brep.bodies.count == count && evaluated.brep.faces.count == count)
        let geometry = try #require(metadata.target.geometry)
        // Each STEP import owns its exact parsed representation; transport can normalize a direction
        // and encode a polyline as an exact degree-one B-spline without retaining native enum identity.
        #expect(try ProductAttributeResolver().sourceReference(for: geometry.subshapeID, in: evaluated) == geometry)
        try inspectLiteralGeometry(geometry.geometrySignature)
        let resolved = try ProductAttributeResolver().resolve(evaluated)
        let faces = resolved.values.filter { if case .face = $0.key.topology { return true }; return false }
        #expect(faces.count == count)
        #expect(faces.values.allSatisfy { $0.properties[.density]?.value == .density(PhysicalDensity(kilogramsPerCubicMeter: 7850)) })
    }

    @Test(.timeLimit(.minutes(1)))
    func foreignNamedCharacterizationRetainsIndependentTextNativeTwoSTEPGenerationsAndNewPDFanout() throws {
        for (item, kind) in [(36, ProductAttributeTarget.Kind.face), (38, .body)] {
            var document = try imported(literal(name: #"'inspection \X2\00650301\X0\'"#, description: "'not the geometry or material label'", item: item))
            let originalName = "inspection e\u{301}", originalDescription = "not the geometry or material label"
            try inspect(document, name: originalName, description: originalDescription, count: 2, kind: kind)
            let target = try #require(document.productAttributes.itemCharacterizations.first).target
            let selectedUUID = try #require(UUID(uuidString: "33333333-3333-4333-8333-333333333333"))
            let selected = AssemblyDefinitionID(selectedUUID)
            let globalColor = ProductAttributeAssignment(target: target, value: .color(ColorRGBA(r: 0, g: 1, b: 0, a: 1)))
            let qualified = ProductAttributeTarget(kind: kind, geometry: target.geometry, definitionID: selected)
            let selectedColor = ProductAttributeAssignment(target: qualified, value: .color(ColorRGBA(r: 0, g: 0, b: 1, a: 1)), overrides: globalColor.id)
            document.productAttributes.assignments.append(contentsOf: [globalColor, selectedColor])
            document.productAttributes.layers.append(ProductLayer(name: "selected layer", members: [qualified]))
            for _ in 0..<2 {
                let native = DataByteSink(), store = NativePackageStore(tolerance: .standard)
                try store.writePackage(for: document, to: native)
                #expect(try store.loadDocument(from: native.bytes) == document)
                let text = try emitted(document)
                #expect(text.components(separatedBy: "=CHARACTERIZED_ITEM_WITHIN_REPRESENTATION(").count - 1 == 1)
                #expect(text.components(separatedBy: "=ADVANCED_FACE(").count - 1 == 1)
                document = try imported(text)
                try inspect(document, name: originalName, description: originalDescription, count: 2, kind: kind)
                let exact = try DocumentEvaluator(tolerance: .standard).evaluateExact(document)
                let resolved = try ProductAttributeResolver().resolve(exact)
                for (world, properties) in resolved.values where world.topology != nil {
                    if case .body = world.topology, kind == .face { continue }
                    let isSelected = world.definitionID == selected
                    #expect(properties.properties[.color]?.value == .color(isSelected ? ColorRGBA(r: 0, g: 0, b: 1, a: 1) : ColorRGBA(r: 0, g: 1, b: 0, a: 1)))
                    #expect(properties.properties[.color]?.assignmentChain.count == (isSelected ? 2 : 1))
                    #expect(properties.layers.isEmpty == !isSelected)
                }
            }
            var assembly = try #require(document.assembly)
            let leaf = try #require(assembly.definitions.first { !$0.features.isEmpty })
            let third = AssemblyDefinition(formationID: leaf.formationID, identifier: "new physical view", features: leaf.features)
            assembly.definitions.append(third)
            let parent = try #require(assembly.definitions.firstIndex { !$0.children.isEmpty })
            assembly.definitions[parent].children.append(AssemblyOccurrence(definitionID: third.id, placement: .translated(by: Vector3D(x: 0.2, y: 0.3, z: 0))))
            document.assembly = assembly
            document = try imported(emitted(document))
            try inspect(document, name: originalName, description: originalDescription, count: 3, kind: kind)
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func canonicalDefaultStaysAbsentAndExplicitEmptyDescriptionStaysPresent() throws {
        for (name, description, expectedName, expectedDescription) in [("''", "$", "", Optional<String>.none),
            ("''", "''", "", ""), ("'region'", "$", "region", nil)] {
            var document = try imported(literal(name: name, description: description))
            for _ in 0..<2 {
                if expectedName.isEmpty && expectedDescription == nil { #expect(document.productAttributes.itemCharacterizations.isEmpty) }
                else { try inspect(document, name: expectedName, description: expectedDescription, count: 2, kind: .face) }
                let native = DataByteSink(), store = NativePackageStore(tolerance: .standard)
                try store.writePackage(for: document, to: native)
                #expect(try store.loadDocument(from: native.bytes) == document)
                document = try imported(emitted(document))
            }
            if expectedName.isEmpty && expectedDescription == nil { #expect(document.productAttributes.itemCharacterizations.isEmpty) }
            else { try inspect(document, name: expectedName, description: expectedDescription, count: 2, kind: .face) }
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func strictNativeRequiresMetadataFieldsAndRefusesPriorEnvelopeAndDefaults() throws {
        let document = try imported(literal(name: "'region'", description: "$"))
        let sink = DataByteSink(), store = NativePackageStore(tolerance: .standard)
        try store.writePackage(for: document, to: sink)
        for mutation in 0..<5 {
            let bytes = try StoredZipArchive.withEntries(from: BorrowedBytes(sink.bytes)) { entries in
                var result: [StoredZipArchive.Entry] = []
                for path in ["manifest.json", "document.json"] {
                    let entry = try #require(entries[path])
                    var object = try #require(JSONSerialization.jsonObject(with: entry) as? [String: Any])
                    if mutation == 0 {
                        var version = try #require(object["schemaVersion"] as? [String: Any]); version["minor"] = 8; object["schemaVersion"] = version
                    } else if path == "document.json" {
                        var attributes = try #require(object["productAttributes"] as? [String: Any])
                        if mutation == 1 { attributes.removeValue(forKey: "itemCharacterizations") }
                        else {
                            var records = try #require(attributes["itemCharacterizations"] as? [[String: Any]])
                            if mutation == 2 { records[0].removeValue(forKey: "description") }
                            if mutation == 3 { records[0]["unknown"] = true }
                            if mutation == 4 { records[0]["name"] = ""; records[0]["description"] = NSNull() }
                            attributes["itemCharacterizations"] = records
                        }
                        object["productAttributes"] = attributes
                    }
                    result.append(.init(path: path, data: try JSONSerialization.data(withJSONObject: object)))
                }
                return try StoredZipArchive.make(entries: result)
            }
            if mutation == 0 { #expect(throws: SchemaError.self) { _ = try store.loadDocument(from: BorrowedBytes(bytes)) } }
            else { #expect(throws: (any Error).self) { _ = try store.loadDocument(from: BorrowedBytes(bytes)) } }
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func invalidMetadataAttachmentLimitsCancellationAndOverrideKeepPublicationAtomic() async throws {
        let source = try imported(literal(name: "'region'", description: "$"))
        let orphan = literal(name: "'region'", description: "$" )
            .replacingOccurrences(of: "#752=PROPERTY_DEFINITION('material property','material name',#751);", with: "")
            .replacingOccurrences(of: "#755=PROPERTY_DEFINITION_REPRESENTATION(#752,#754);", with: "")
            .replacingOccurrences(of: "#766=PROPERTY_DEFINITION('material property','density',#751);", with: "")
            .replacingOccurrences(of: "#768=PROPERTY_DEFINITION_REPRESENTATION(#766,#767);", with: "")
        let independent = try imported(orphan)
        #expect(independent.productAttributes.itemCharacterizations.first?.name == "region")
        #expect(independent.productAttributes.materials.isEmpty)
        #expect(!independent.productAttributes.assignments.contains { $0.value.property == .material || $0.value.property == .density })
        let foreign = literal(name: "'region'", description: "$" ).replacingOccurrences(of: "'region',$,#36,#750", with: "'region',$,#999,#750")
        #expect(throws: ProductAttributeError.missingTarget("Global physical item geometry correspondence.")) { _ = try imported(foreign) }
        var invalid = source
        let base = try #require(invalid.productAttributes.assignments.first { $0.value.property == .density })
        invalid.productAttributes.assignments.append(ProductAttributeAssignment(target: base.target, value: .density(PhysicalDensity(kilogramsPerCubicMeter: 8000)), overrides: base.id))
        let evaluated = try DocumentEvaluator(tolerance: .standard).evaluate(invalid)
        let failure = ProductAttributeError.unsupportedSemantics("Physical override chains require a standard-equivalent ordering relationship.")
        let sink = DataByteSink()
        #expect(throws: failure) { try OfficialFormatExchange(tolerance: .standard).write(evaluated, as: .step, to: sink) }
        #expect(sink.bytes.isEmpty)
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { do { try FileManager.default.removeItem(at: directory) } catch { Issue.record("Unable to remove characterization fixture: \(error)") } }
        let url = directory.appendingPathComponent("metadata.step"), original = Data("existing complete document".utf8)
        try original.write(to: url)
        #expect(throws: failure) { try OfficialFormatExchange(tolerance: .standard).export(evaluated, as: .step, to: url) }
        #expect(try Data(contentsOf: url) == original)
        var defaultMetadata = source
        let metadata = try #require(source.productAttributes.itemCharacterizations.first)
        defaultMetadata.productAttributes.itemCharacterizations = [ProductItemCharacterization(target: metadata.target, name: "", description: nil)]
        let nativeSink = DataByteSink(), store = NativePackageStore(tolerance: .standard)
        let defaultFailure = ProductAttributeError.invalidSource("Default physical characterization must be absent.")
        #expect(throws: defaultFailure) { try store.writePackage(for: defaultMetadata, to: nativeSink) }
        #expect(nativeSink.bytes.isEmpty)
        #expect(throws: defaultFailure) { try store.save(defaultMetadata, to: url) }
        #expect(try Data(contentsOf: url) == original)
        let exact = try DocumentEvaluator(tolerance: .standard).evaluateExact(source)
        let resolved = try ProductAttributeResolver().resolve(exact)
        let limited = DataByteSink()
        #expect(throws: ProductAttributeError.resourceLimitExceeded("Cumulative product attribute budget.")) {
            try STEPExchange(tolerance: .standard, resourceLimits: ExchangeResourceLimits(maximumIterations: resolved.consumedWork)).write(exact, to: limited)
        }
        #expect(limited.bytes.isEmpty)
        let task = Task { () throws -> Data in
            let output = DataByteSink(); withUnsafeCurrentTask { $0?.cancel() }
            do { try STEPExchange(tolerance: .standard).write(exact, to: output); Issue.record("Cancelled metadata export succeeded.") }
            catch is CancellationError {}
            return output.bytes
        }
        let cancelledBytes = try await task.value
        #expect(cancelledBytes.isEmpty)
    }
    // Independently authored exact AP242 input; production output is never used to author this fixture.
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
