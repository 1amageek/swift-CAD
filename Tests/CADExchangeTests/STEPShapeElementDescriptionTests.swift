import Foundation
import Testing
import CADCore
import CADGeometry
import CADIR
import CADKernel
import CADTopology
@testable import CADExchange

@Suite("Definition-qualified STEP shape element descriptions")
struct STEPShapeElementDescriptionTests {
    private func literal(bodyDescription: String, faceDescription: String) -> String {
        // The geometry, products, GISU views and styles below are independently authored standard records.
        let physical = """
        #950=(MASS_UNIT() NAMED_UNIT(*) SI_UNIT(.KILO.,.GRAM.));
        #951=(LENGTH_UNIT() NAMED_UNIT(*) SI_UNIT($,.METRE.));
        #952=DERIVED_UNIT_ELEMENT(#950,1.);
        #953=DERIVED_UNIT_ELEMENT(#951,-3.);
        #954=DERIVED_UNIT((#952,#953));
        #955=(MEASURE_REPRESENTATION_ITEM() MEASURE_WITH_UNIT(MASS_DENSITY_MEASURE(1000.),#954) REPRESENTATION_ITEM('density'));
        #956=PROPERTY_DEFINITION('material property','density',#824);
        #957=REPRESENTATION('density',(#955),#7);
        #958=PROPERTY_DEFINITION_REPRESENTATION(#956,#957);
        #960=DESCRIPTIVE_REPRESENTATION_ITEM('steel','physical descriptor');
        #961=PROPERTY_DEFINITION('material property','material name',#824);
        #962=REPRESENTATION('material name',(#960),#7);
        #963=PROPERTY_DEFINITION_REPRESENTATION(#961,#962);
        """
        return Self.fixture
            .replacingOccurrences(of: "SHAPE_ASPECT('selected body','',#53", with: "SHAPE_ASPECT('selected body',\(bodyDescription),#53")
            .replacingOccurrences(of: "SHAPE_ASPECT('selected face',$,#53", with: "SHAPE_ASPECT('selected face',\(faceDescription),#53")
            .replacingOccurrences(of: "ENDSEC;\nEND-ISO", with: physical + "\nENDSEC;\nEND-ISO")
    }
    private func imported(_ text: String) throws -> CADDocument {
        try #require(STEPExchange(tolerance: .standard).import(Data(text.utf8)).document)
    }
    private func emitted(_ document: CADDocument) throws -> String {
        let sink = DataByteSink()
        try STEPExchange(tolerance: .standard).write(DocumentEvaluator(tolerance: .standard).evaluateExact(document), to: sink)
        return try #require(String(data: sink.bytes, encoding: .utf8))
    }
    private func inspect(_ document: CADDocument, bodyDescription: String?, faceDescription: String?, total: Int = 3) throws {
        let selected = try #require(document.assembly?.definitions.first { $0.id.description == "33333333-3333-4333-8333-333333333333" })
        #expect(document.designGraph.nodes.count == 1 && selected.features.count == 1)
        #expect(document.productAttributes.shapeElementDescriptions.count == [bodyDescription, faceDescription].compactMap { $0 }.count)
        #expect(document.productAttributes.physicalCharacterizations.isEmpty)
        let evaluated = try DocumentEvaluator(tolerance: .standard).evaluateExact(document), resolver = ProductAttributeResolver()
        let artifact = try #require(evaluated.assembly), resolved = try resolver.resolve(evaluated)
        #expect(artifact.local.model.bodies.count == 1 && artifact.local.model.faces.count == 1)
        #expect(evaluated.brep.bodies.count == total && evaluated.brep.faces.count == total)
        for (kind, expected) in [(ProductAttributeTarget.Kind.body, bodyDescription), (.face, faceDescription)] {
            let record = document.productAttributes.shapeElementDescriptions.first { $0.target.kind == kind }
            if let expected {
                let actual = try #require(record)
                #expect(actual.description.utf8.elementsEqual(expected.utf8))
                #expect(actual.target.definitionID == selected.id && actual.target.path == nil && actual.target.usageID == nil)
                let reference = try #require(actual.target.geometry)
                #expect(try resolver.sourceReference(for: reference.subshapeID, in: evaluated) == reference)
                #expect(document.productAttributes.assignments.contains { $0.target == actual.target && $0.value == .name(kind == .body ? "selected body" : "selected face") })
            } else { #expect(record == nil) }
        }
        let labels = document.productAttributes.assignments.filter { $0.value.property == .name }
        #expect(labels.count == 2 && labels.allSatisfy { $0.target.definitionID == selected.id })
        let faceLabel = try #require(labels.first { $0.target.kind == .face })
        let reference = try #require(faceLabel.target.geometry)
        guard case let .face(signature) = reference.geometrySignature else {
            Issue.record("The independent face label lost its face signature.")
            return
        }
        #expect(signature.surface == .plane(Plane3D(origin: .origin, normal: .unitZ)) && signature.orientation == .forward)
        #expect(signature.loops.count == 1)
        let loop = try #require(signature.loops.first)
        #expect(loop.role == .outer && loop.coedges.count == 3)
        let corners = [Point3D.origin, Point3D(x: 0.04, y: 0, z: 0), Point3D(x: 0, y: 0.02, z: 0)]
        for (index, coedge) in loop.coedges.enumerated() {
            guard index < corners.count else { continue }
            let start = corners[index], end = corners[(index + 1) % corners.count]
            #expect(coedge.orientation == .forward && coedge.edge.startPoint == start && coedge.edge.endPoint == end)
            guard case let .line(line) = coedge.edge.curve else { Issue.record("The literal triangle lost its straight edge."); continue }
            let direction = try (end - start).normalized(tolerance: ModelingTolerance.standard.distance)
            #expect(line.origin == start && (line.direction - direction).length <= ModelingTolerance.standard.angle)
            switch coedge.surfaceParameterCurve {
            case let .polyline(points):
                #expect(points == [SurfaceParameter(u: start.x, v: start.y), SurfaceParameter(u: end.x, v: end.y)])
            case let .bSpline(curve):
                // The degree, knots, unit weights and two controls establish the whole linear p-curve.
                #expect(curve.degree == 1 && curve.knots == [0, 0, 1, 1] && curve.weights == [1, 1])
                #expect(curve.controlPoints == [Point2D(x: start.x, y: start.y), Point2D(x: end.x, y: end.y)])
            default: Issue.record("The literal triangle lost its exact linear p-curve.")
            }
        }
        let material = try #require(document.productAttributes.materials.first)
        #expect(material.name == "steel" && material.description == "physical descriptor")
        #expect(document.productAttributes.assignments.contains { $0.target.kind == .face && $0.target.definitionID == selected.id && $0.value == .descriptorDensity(material.id) })
        for occurrence in artifact.occurrences where !occurrence.features.isEmpty {
            let selectedInstance = occurrence.definitionID == selected.id
            let feature = try #require(occurrence.features.first)
            let body = try #require(feature.bodies.values.first), face = try #require(feature.faces.values.first)
            let b = try #require(resolved.values[ResolvedProductTarget(topology: .body(body), definitionID: occurrence.definitionID, path: occurrence.path)])
            let f = try #require(resolved.values[ResolvedProductTarget(topology: .face(face), definitionID: occurrence.definitionID, path: occurrence.path)])
            #expect(b.properties[.name]?.value == (selectedInstance ? .name("selected body") : nil))
            #expect(f.properties[.name]?.value == (selectedInstance ? .name("selected face") : nil))
            #expect(b.properties[.color]?.value == .color(selectedInstance ? ColorRGBA(r: 0, g: 0, b: 1, a: 1) : ColorRGBA(r: 0, g: 1, b: 0, a: 1)))
            #expect(f.properties[.color]?.value == .color(selectedInstance ? ColorRGBA(r: 1, g: 0, b: 0, a: 1) : ColorRGBA(r: 0, g: 1, b: 0, a: 1)))
            #expect(b.properties[.color]?.assignmentChain.count == (selectedInstance ? 2 : 1))
            #expect(f.properties[.color]?.assignmentChain.count == (selectedInstance ? 3 : 1))
            #expect(f.properties[.density]?.value == (selectedInstance ? .density(PhysicalDensity(kilogramsPerCubicMeter: 1000)) : nil))
            let selectedLayer = try #require(document.productAttributes.layers.first { $0.name == "selected face layer" })
            #expect(f.layers.contains(selectedLayer.id) == selectedInstance)
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func physicalOnlyDescriptionRetainsItsExistingOwnerWithoutInventingAName() throws {
        var document = try imported(literal(bodyDescription: "$", faceDescription: "'physical-only description'")
            .replacingOccurrences(of: "SHAPE_ASPECT('selected face'", with: "SHAPE_ASPECT(''"))
        for _ in 0..<2 {
            let record = try #require(document.productAttributes.shapeElementDescriptions.first)
            #expect(document.productAttributes.shapeElementDescriptions.count == 1 && record.target.kind == .face)
            #expect(record.description == "physical-only description")
            #expect(!document.productAttributes.assignments.contains { $0.target == record.target && $0.value.property == .name })
            #expect(document.productAttributes.assignments.contains { $0.target == record.target && $0.value.property == .density })
            let exact = try DocumentEvaluator(tolerance: .standard).evaluateExact(document)
            let reference = try #require(record.target.geometry)
            #expect(try ProductAttributeResolver().sourceReference(for: reference.subshapeID, in: exact) == reference)
            _ = try ProductAttributeResolver().resolve(exact)
            let native = DataByteSink(), store = NativePackageStore(tolerance: .standard)
            try store.writePackage(for: document, to: native)
            #expect(try store.loadDocument(from: native.bytes) == document)
            let text = try emitted(document)
            #expect(text.components(separatedBy: "=GEOMETRIC_ITEM_SPECIFIC_USAGE(").count - 1 == 2)
            document = try imported(text)
        }
        let retained = try #require(document.productAttributes.shapeElementDescriptions.first)
        #expect(retained.description == "physical-only description" && retained.target.definitionID?.description == "33333333-3333-4333-8333-333333333333")
        #expect(!document.productAttributes.assignments.contains { $0.target == retained.target && $0.value.property == .name })
        let reference = try #require(retained.target.geometry)
        let final = try DocumentEvaluator(tolerance: .standard).evaluateExact(document)
        #expect(try ProductAttributeResolver().sourceReference(for: reference.subshapeID, in: final) == reference)
    }

    @Test(.timeLimit(.minutes(1)))
    func independentNullableEmptyUnicodeDescriptionsShareGISUAndSurviveNativeTwoSTEPGenerationsAndNewPD() throws {
        let cases: [(String, String, String?, String?)] = [("''", "$", "", nil),
            (#"'caf\X2\00E9\X0\'"#, #"'cafe\X2\0301\X0\'"#, "caf\u{e9}", "cafe\u{301}"), ("' '", "''", " ", "")]
        for (bodyToken, faceToken, bodyDescription, faceDescription) in cases {
            var document = try imported(literal(bodyDescription: bodyToken, faceDescription: faceToken))
            try inspect(document, bodyDescription: bodyDescription, faceDescription: faceDescription)
            for _ in 0..<2 {
                let native = DataByteSink(), store = NativePackageStore(tolerance: .standard)
                try store.writePackage(for: document, to: native)
                #expect(try store.loadDocument(from: native.bytes) == document)
                let text = try emitted(document)
                #expect(text.components(separatedBy: "=ADVANCED_FACE(").count - 1 == 1)
                #expect(text.components(separatedBy: "=SHAPE_ASPECT(").count - 1 == 2)
                #expect(text.components(separatedBy: "=GEOMETRIC_ITEM_SPECIFIC_USAGE(").count - 1 == 2)
                #expect(!text.contains("ADVANCED_FACE('selected face'"))
                document = try imported(text)
                try inspect(document, bodyDescription: bodyDescription, faceDescription: faceDescription)
            }
            var assembly = try #require(document.assembly)
            let selected = try #require(assembly.definitions.first { $0.id.description == "33333333-3333-4333-8333-333333333333" })
            let third = AssemblyDefinition(formationID: selected.formationID, identifier: "third view", features: selected.features)
            assembly.definitions.append(third)
            let parent = try #require(assembly.definitions.firstIndex { !$0.children.isEmpty })
            assembly.definitions[parent].children.append(AssemblyOccurrence(definitionID: third.id, placement: .translated(by: Vector3D(x: 0.2, y: 0.3, z: 0))))
            document.assembly = assembly
            try inspect(document, bodyDescription: bodyDescription, faceDescription: faceDescription, total: 4)
            document = try imported(emitted(document))
            try inspect(document, bodyDescription: bodyDescription, faceDescription: faceDescription, total: 4)
        }
        let nullSource = try imported(literal(bodyDescription: "$", faceDescription: "$"))
        #expect(nullSource.productAttributes.shapeElementDescriptions.isEmpty)
        let restored = try imported(emitted(nullSource))
        #expect(restored.productAttributes.shapeElementDescriptions.isEmpty)
    }

    @Test(.timeLimit(.minutes(1)))
    func strictNativeRefusesPriorEnvelopeMissingArrayNullAndUnknownDescriptionFields() throws {
        let source = try imported(literal(bodyDescription: "'description'", faceDescription: "$"))
        let store = NativePackageStore(tolerance: .standard), sink = DataByteSink()
        try store.writePackage(for: source, to: sink)
        for mutation in 0..<5 {
            let bytes = try StoredZipArchive.withEntries(from: BorrowedBytes(sink.bytes)) { entries in
                var result: [StoredZipArchive.Entry] = []
                for path in ["manifest.json", "document.json"] {
                    let entry = try #require(entries[path])
                    var object = try #require(JSONSerialization.jsonObject(with: entry) as? [String: Any])
                    if mutation == 0 {
                        var version = try #require(object["schemaVersion"] as? [String: Any]); version["minor"] = 9; object["schemaVersion"] = version
                    } else if path == "document.json" {
                        var attributes = try #require(object["productAttributes"] as? [String: Any])
                        if mutation == 1 { attributes.removeValue(forKey: "shapeElementDescriptions") }
                        else {
                            var records = try #require(attributes["shapeElementDescriptions"] as? [[String: Any]])
                            if mutation == 2 { records[0].removeValue(forKey: "description") }
                            if mutation == 3 { records[0]["description"] = NSNull() }
                            if mutation == 4 { records[0]["unknown"] = true }
                            attributes["shapeElementDescriptions"] = records
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
    func foreignDuplicateUnitsAndUnsupportedUnattachedMetadataRefuse() throws {
        let original = literal(bodyDescription: "'description'", faceDescription: "''")
        let foreign = original.replacingOccurrences(of: "SHAPE_ASPECT('selected face','',#53", with: "SHAPE_ASPECT('selected face','',#73")
        #expect(throws: ProductAttributeError.missingTarget("Shape aspect geometry correspondence.")) { _ = try imported(foreign) }
        let duplicate = original.replacingOccurrences(of: "ENDSEC;\nEND-ISO", with: "#920=SHAPE_ASPECT('competing','description',#53,.T.);\n#921=GEOMETRIC_ITEM_SPECIFIC_USAGE('','',#920,#823,#36);\nENDSEC;\nEND-ISO")
        #expect(throws: ProductAttributeError.invalidSource("Duplicate GISU representation/item or representation/definition usage.")) { _ = try imported(duplicate) }
        let wrongUnits = original.replacingOccurrences(of: "#823=SHAPE_REPRESENTATION('',(#36),#7);", with: "#823=SHAPE_REPRESENTATION('',(#36),#924);\n#922=(LENGTH_UNIT() NAMED_UNIT(*) SI_UNIT($,.METRE.));\n#924=(GEOMETRIC_REPRESENTATION_CONTEXT(3) GLOBAL_UNIT_ASSIGNED_CONTEXT((#922,#5,#6)) REPRESENTATION_CONTEXT('wrong units',''));")
        #expect(throws: ProductAttributeError.invalidSource("Physical target view has conflicting owned units.")) { _ = try imported(wrongUnits) }
        let unattached = original.replacingOccurrences(of: "SHAPE_ASPECT('selected body','description'", with: "SHAPE_ASPECT('','description'")
        #expect(throws: ProductAttributeError.unsupportedSemantics("Standalone shape element description requires a name or physical attachment.")) { _ = try imported(unattached) }
    }

    @Test(.timeLimit(.minutes(1)))
    func cumulativeLimitsCancellationAndFailedNativeEditPreserveAtomicOutput() async throws {
        let source = try imported(literal(bodyDescription: "'description'", faceDescription: "''"))
        let exact = try DocumentEvaluator(tolerance: .standard).evaluateExact(source), sink = DataByteSink()
        do {
            try STEPExchange(tolerance: .standard, resourceLimits: ExchangeResourceLimits(maximumIterations: 1)).write(exact, to: sink)
            Issue.record("STEP description export reset caller work limits.")
        } catch let error as ProductAttributeError {
            guard case .resourceLimitExceeded = error else { Issue.record("Unexpected work-limit failure: \(error)"); return }
        } catch let error as AssemblyError {
            guard case .resourceLimitExceeded = error else { Issue.record("Unexpected assembly work-limit failure: \(error)"); return }
        }
        #expect(sink.bytes.isEmpty)
        let task = Task {
            let output = DataByteSink(); withUnsafeCurrentTask { $0?.cancel() }
            do { try STEPExchange(tolerance: .standard).write(exact, to: output); Issue.record("Cancelled description export succeeded.") }
            catch is CancellationError {}
            return output.bytes
        }
        #expect(try await task.value.isEmpty)
        var invalid = source
        let record = try #require(invalid.productAttributes.shapeElementDescriptions.first { $0.target.kind == .body })
        // Preserve color/opacity predecessor identities while removing only the description's permitted attachments.
        invalid.productAttributes.assignments.removeAll {
            $0.target == record.target && ($0.value.property == .name || $0.value.property == .material || $0.value.property == .density)
        }
        let store = NativePackageStore(tolerance: .standard), output = DataByteSink()
        let failure = ProductAttributeError.unsupportedSemantics("Standalone shape element description requires a name or physical attachment.")
        #expect(throws: failure) { try store.writePackage(for: invalid, to: output) }
        #expect(output.bytes.isEmpty)
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { do { try FileManager.default.removeItem(at: directory) } catch { Issue.record("Unable to remove description fixture: \(error)") } }
        let url = directory.appendingPathComponent("description.step"), oldBytes = Data("existing complete destination".utf8)
        try oldBytes.write(to: url)
        let materialized = try DocumentEvaluator(tolerance: .standard).evaluate(source)
        #expect(throws: (any Error).self) {
            try OfficialFormatExchange(tolerance: .standard,
                stepExchange: STEPExchange(tolerance: .standard, resourceLimits: ExchangeResourceLimits(maximumIterations: 1))).export(materialized, as: .step, to: url)
        }
        #expect(try Data(contentsOf: url) == oldBytes)
        #expect(throws: failure) { try store.save(invalid, to: url) }
        #expect(try Data(contentsOf: url) == oldBytes)
    }
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
