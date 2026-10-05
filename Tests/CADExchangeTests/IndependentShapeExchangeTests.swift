import Foundation
import Testing
import CADCore
import CADGeometry
import CADIR
import CADTopology
@testable import CADExchange

@Suite("Independent standard shape exchange")
struct IndependentShapeExchangeTests {
    /// Independently authored Part 21 associations: no product, topology or production writer.
    static let literalSTEP = #"""
    ISO-10303-21;
    HEADER;
    FILE_DESCRIPTION(('Independent original geometry'),'2;1');
    FILE_NAME('independent.stp','2026-10-05T00:00:00',('author'),(''),'fixture','fixture','');
    FILE_SCHEMA(('AP242_MANAGED_MODEL_BASED_3D_ENGINEERING_MIM_LF'));
    ENDSEC;
    DATA;
    #1=(LENGTH_UNIT() NAMED_UNIT(*) SI_UNIT(.MILLI.,.METRE.));
    #2=(NAMED_UNIT(*) PLANE_ANGLE_UNIT() SI_UNIT($,.RADIAN.));
    #3=(GEOMETRIC_REPRESENTATION_CONTEXT(3) GLOBAL_UNIT_ASSIGNED_CONTEXT((#1,#2)) REPRESENTATION_CONTEXT('original millimeters','3D'));
    #10=CARTESIAN_POINT('',(100.,200.,300.));
    #11=DIRECTION('',(2.,0.,0.));
    #12=VECTOR('',#11,5.);
    #13=LINE('line law',#10,#12);
    #14=TRIMMED_CURVE('forward',#13,(PARAMETER_VALUE(-2.)),(PARAMETER_VALUE(2.)),.T.,.PARAMETER.);
    #15=TRIMMED_CURVE('reverse',#13,(PARAMETER_VALUE(-2.)),(PARAMETER_VALUE(2.)),.F.,.PARAMETER.);
    #17=DIRECTION('',(0.,1.,0.));
    #18=DIRECTION('',(0.,0.,1.));
    #19=DIRECTION('',(1.,0.,0.));
    #20=CARTESIAN_POINT('',(0.,0.,0.));
    #21=CARTESIAN_POINT('',(0.,20.,0.));
    #22=CARTESIAN_POINT('',(10.,0.,10.));
    #23=CARTESIAN_POINT('',(10.,20.,10.));
    #31=(B_SPLINE_SURFACE(1,1,((#20,#21),(#22,#23)),.UNSPECIFIED.,.F.,.F.,.F.) B_SPLINE_SURFACE_WITH_KNOTS((2,2),(2,2),(0.,1.),(0.,1.),.UNSPECIFIED.) GEOMETRIC_REPRESENTATION_ITEM() RATIONAL_B_SPLINE_SURFACE(((1.,2.),(1.,2.))) REPRESENTATION_ITEM('rational surface'));
    #40=GEOMETRIC_SET('curves and surface',(#14,#15,#31));
    #41=AXIS2_PLACEMENT_3D('shared original frame',#20,#18,#19);
    #42=SHAPE_REPRESENTATION('local geometry',(#40,#41),#3);
    #43=REPRESENTATION_MAP(#41,#42);
    #44=CARTESIAN_TRANSFORMATION_OPERATOR_3D('first placement',#19,#17,#45,2.,#18);
    #45=CARTESIAN_POINT('',(10.,20.,30.));
    #46=MAPPED_ITEM('first instance',#43,#44);
    #47=CARTESIAN_TRANSFORMATION_OPERATOR_3D('second placement',#17,#56,#20,1.,#18);
    #48=MAPPED_ITEM('second instance',#43,#47);
    #49=SHAPE_REPRESENTATION('placed geometry',(#46,#48),#3);
    #50=GROUP('shared group',$);
    #51=APPLIED_GROUP_ASSIGNMENT(#50,(#14,#49));
    #52=GROUP('overlapping group','');
    #53=APPLIED_GROUP_ASSIGNMENT(#52,(#15,#51));
    #56=DIRECTION('',(-1.,0.,0.));
    ENDSEC;
    END-ISO-10303-21;
    """#

    private func expectResource(_ body: () throws -> Void) throws {
        do { try body(); Issue.record("Caller resource ceiling was not enforced.") }
        catch IndependentShapeExchangeError.resourceLimitExceeded { }
        catch IndependentShapeSourceError.resourceLimitExceeded { }
        catch let error as KernelError { #expect(error.code == .resourceLimitExceeded) }
    }

    private func imported(_ text: String) throws -> (ImportedExchangeModel, IndependentShapeSource) {
        let result = try STEPExchange(tolerance: .standard).import(Data(text.utf8))
        let document = try #require(result.document)
        return (result, try #require(document.independentShapes))
    }

    private func inspect(_ source: IndependentShapeSource) throws {
        #expect(source.geometry.curves.count == 1 && source.geometry.surfaces.count == 1)
        #expect(source.items.count == 3 && source.geometricSets.count == 1)
        #expect(source.representations.count == 2 && source.definitions.count == 1)
        #expect(source.frames.count == 1 && source.instances.count == 2 && source.groups.count == 2)
        let frame = try #require(source.frames.first)
        #expect(frame.name == "shared original frame")
        #expect(source.definitions[0].originFrameID == frame.id)
        let local = try #require(source.representations.first(where: { $0.name == "local geometry" }))
        #expect(local.members.contains(.frame(frame.id)))
        let forward = try #require(source.items.first(where: { $0.name == "forward" }))
        let reverse = try #require(source.items.first(where: { $0.name == "reverse" }))
        guard case .curve(let id, let trim) = forward.geometry,
              case .curve(let reversedID, let reversedTrim) = reverse.geometry else {
            Issue.record("Literal directed selections require one original curve law."); return
        }
        #expect(id == reversedID)
        #expect(trim?.startParameter == -2 && trim?.endParameter == 2)
        #expect(reversedTrim?.startParameter == 2 && reversedTrim?.endParameter == -2)
        let curve = try #require(source.geometry.curves[id])
        for t in [-2.0, 0, 2] {
            let expected = Point3D(x: 0.1 + 0.005 * t, y: 0.2, z: 0.3)
            #expect((try curve.point(at: t, tolerance: .standard) - expected).length <= ModelingTolerance.standard.distance)
        }
        let surfaceItem = try #require(source.items.first(where: { $0.name == "rational surface" }))
        guard case .surface(let surfaceID) = surfaceItem.geometry,
              case .bSpline(let surface) = source.geometry.surfaces[surfaceID] else {
            Issue.record("Literal surface must retain its original rational spline law."); return
        }
        #expect(surface.uDegree == 1 && surface.vDegree == 1)
        #expect(surface.uKnots == [0,0,1,1] && surface.vKnots == [0,0,1,1])
        #expect(surface.weights == [[1,1],[2,2]])
        for u in [0.0, 0.25, 1] { for v in [0.0, 0.5, 1] {
            let expected = Point3D(x: 0.01*u, y: 0.04*v/(1+v), z: 0.01*u)
            #expect((try surface.point(u: u, v: v, tolerance: .standard) - expected).length <= ModelingTolerance.standard.distance)
        } }
        let first = try #require(source.instances.first(where: { $0.name == "first instance" }))
        let second = try #require(source.instances.first(where: { $0.name == "second instance" }))
        #expect(first.target == second.target)
        #expect(first.placementName == "first placement" && second.placementName == "second placement")
        let localPoint = Point3D(x: 0.0025, y: 0.04/3, z: 0.0025)
        #expect((first.placement.applying(to: localPoint) - Point3D(x: 0.015, y: 0.02+0.08/3, z: 0.035)).length <= ModelingTolerance.standard.distance)
        #expect((second.placement.applying(to: localPoint) - Point3D(x: -0.04/3, y: 0.0025, z: 0.0025)).length <= ModelingTolerance.standard.distance)
        let nilDescription = try #require(source.groups.first(where: { $0.name == "shared group" }))
        let emptyDescription = try #require(source.groups.first(where: { $0.name == "overlapping group" }))
        #expect(nilDescription.description == nil && emptyDescription.description == "")
        #expect(emptyDescription.members.contains(.group(nilDescription.id)))
        #expect(source.roots == [.group(emptyDescription.id)])
        #expect(source.contexts.count == 1 && source.contexts[0].units.length == .millimeter)
        #expect(source.curveNames[id] == "line law" && source.surfaceNames[surfaceID] == "rational surface")
    }

    @Test(.timeLimit(.minutes(1)))
    func independentLiteralRetainsOriginalLawsUnitsSetsMapsAndFrameIdentity() throws {
        let (result, source) = try imported(Self.literalSTEP)
        #expect(result.brep == nil && result.meshes.isEmpty)
        try inspect(source)
    }

    @Test(.timeLimit(.minutes(1)))
    func rectangularSTEPNetRetainsUnequalAxesAndWeightsThroughTwoGenerations() throws {
        // Independently authored STEP [u][v] degree 2x1 net. Native storage is [v][u].
        let old = "#31=(B_SPLINE_SURFACE(1,1,((#20,#21),(#22,#23)),.UNSPECIFIED.,.F.,.F.,.F.) B_SPLINE_SURFACE_WITH_KNOTS((2,2),(2,2),(0.,1.),(0.,1.),.UNSPECIFIED.) GEOMETRIC_REPRESENTATION_ITEM() RATIONAL_B_SPLINE_SURFACE(((1.,2.),(1.,2.))) REPRESENTATION_ITEM('rational surface'));"
        let replacement = """
        #24=CARTESIAN_POINT('',(5.,0.,5.));
        #25=CARTESIAN_POINT('',(5.,20.,5.));
        #31=(B_SPLINE_SURFACE(2,1,((#20,#21),(#24,#25),(#22,#23)),.UNSPECIFIED.,.F.,.F.,.F.) B_SPLINE_SURFACE_WITH_KNOTS((3,3),(2,2),(0.,1.),(0.,1.),.UNSPECIFIED.) GEOMETRIC_REPRESENTATION_ITEM() RATIONAL_B_SPLINE_SURFACE(((1.,2.),(1.,2.),(1.,2.))) REPRESENTATION_ITEM('rational surface'));
        """
        var result = try STEPExchange(tolerance:.standard).import(Data(Self.literalSTEP.replacingOccurrences(of:old,with:replacement).utf8))
        for generation in 0..<3 {
            let document = try #require(result.document), source = try #require(document.independentShapes)
            let surface = try #require(source.geometry.surfaces.values.first)
            guard case .bSpline(let spline) = surface else { Issue.record("Original rectangular spline was not retained."); return }
            #expect(spline.uDegree == 2 && spline.vDegree == 1)
            #expect(spline.uControlPointCount == 3 && spline.vControlPointCount == 2)
            #expect(spline.uKnots == [0,0,0,1,1,1] && spline.vKnots == [0,0,1,1])
            #expect(spline.weights == [[1,1,1],[2,2,2]])
            #expect(spline.controlPoints[0][1] == Point3D(x:0.005,y:0,z:0.005))
            #expect(spline.controlPoints[1][0] == Point3D(x:0,y:0.02,z:0))
            for u in [0.0,0.25,0.75,1.0] {
                for v in [0.0,0.2,0.6,1.0] {
                    let expected = Point3D(x:0.01*u,y:0.04*v/(1+v),z:0.01*u)
                    #expect((try surface.point(u:u,v:v,tolerance:.standard)-expected).length <= ModelingTolerance.standard.distance)
                }
            }
            #expect(result.brep == nil && source.geometry.surfaces.count == 1)
            if generation < 2 {
                let output = DataByteSink(); try STEPExchange(tolerance:.standard).write(document,to:output)
                result = try STEPExchange(tolerance:.standard).import(output.bytes)
            }
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func standaloneOriginalSelectionsDoNotRequireARepresentationOrPhantomBody() throws {
        let retained: Set<Int> = [1,2,3,10,11,12,13,14,15,20,21,22,23,31]
        let lines = Self.literalSTEP.split(separator: "\n", omittingEmptySubsequences: false).filter { line in
            guard line.hasPrefix("#"), let equal = line.firstIndex(of: "="),
                  let id = Int(line[line.index(after: line.startIndex)..<equal]) else { return true }
            return retained.contains(id)
        }
        var result = try STEPExchange(tolerance: .standard).import(Data(lines.joined(separator: "\n").utf8))
        for generation in 0..<3 {
            let document = try #require(result.document), source = try #require(document.independentShapes)
            #expect(result.brep == nil && result.meshes.isEmpty)
            #expect(source.representations.isEmpty && source.groups.isEmpty && source.instances.isEmpty && source.frames.isEmpty)
            #expect(source.geometry.curves.count == 1 && source.geometry.surfaces.count == 1 && source.items.count == 3)
            #expect(source.roots == source.items.map { IndependentShapeReference.item($0.id) }.sorted())
            let curve = try #require(source.geometry.curves.values.first)
            #expect((try curve.point(at: 1.25, tolerance: .standard)-Point3D(x:0.10625,y:0.2,z:0.3)).length <= ModelingTolerance.standard.distance)
            let surface = try #require(source.geometry.surfaces.values.first)
            #expect((try surface.point(u:0.25,v:0.5,tolerance:.standard)-Point3D(x:0.0025,y:0.04/3,z:0.0025)).length <= ModelingTolerance.standard.distance)
            if generation < 2 {
                let output = DataByteSink()
                try STEPExchange(tolerance: .standard).write(document,to:output)
                result = try STEPExchange(tolerance: .standard).import(output.bytes)
            }
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func wholeNativeSourceAndTwoPublicSTEPGenerationsRetainAssociations() throws {
        let (first, original) = try imported(Self.literalSTEP)
        var document = try #require(first.document)
        let store = NativePackageStore(tolerance: .standard), package = DataByteSink()
        try store.writePackage(for: document, to: package)
        let reloaded = try store.loadDocument(from: package.bytes)
        #expect(reloaded == document && reloaded.independentShapes == original)
        document = reloaded
        for _ in 0..<2 {
            let sink = DataByteSink()
            try STEPExchange(tolerance: .standard).write(document, to: sink)
            let next = try STEPExchange(tolerance: .standard).import(sink.bytes)
            #expect(next.brep == nil && next.meshes.isEmpty)
            document = try #require(next.document)
            try inspect(try #require(document.independentShapes))
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func originalNonidentityMappingOriginSurvivesTwoGenerationsWithoutBakingGeometry() throws {
        let literal = Self.literalSTEP.replacingOccurrences(of: "#41=AXIS2_PLACEMENT_3D('shared original frame',#20,#18,#19);", with: """
        #60=CARTESIAN_POINT('',(20.,10.,0.));
        #41=AXIS2_PLACEMENT_3D('shared original frame',#60,#18,#19);
        """)
        let (result, _) = try imported(literal)
        var document = try #require(result.document)
        for generation in 0..<3 {
            let source = try #require(document.independentShapes)
            let origin = try #require(source.frames.first)
            #expect(origin.placement.basisX == Vector3D(x:1,y:0,z:0))
            #expect(origin.placement.basisY == Vector3D(x:0,y:1,z:0))
            #expect(origin.placement.basisZ == Vector3D(x:0,y:0,z:1))
            #expect((origin.placement.translation-Vector3D(x:0.02,y:0.01,z:0)).length <= ModelingTolerance.standard.distance)
            let first = try #require(source.instances.first { $0.name == "first instance" })
            let second = try #require(source.instances.first { $0.name == "second instance" })
            #expect(first.target == second.target && source.geometry.surfaces.count == 1)
            // The literal origin is a translation, so its inverse is independently known exactly as p - translation.
            let inMapChart = Point3D(x:0.0025,y:0.04/3,z:0.0025) + (-origin.placement.translation)
            #expect((first.placement.applying(to:inMapChart)-Point3D(x:-0.025,y:0.02+2*(0.04/3-0.01),z:0.035)).length <= ModelingTolerance.standard.distance)
            #expect((second.placement.applying(to:inMapChart)-Point3D(x:0.01-0.04/3,y:-0.0175,z:0.0025)).length <= ModelingTolerance.standard.distance)
            if generation < 2 {
                let sink = DataByteSink(); try STEPExchange(tolerance:.standard).write(document,to:sink)
                let next = try STEPExchange(tolerance:.standard).import(sink.bytes)
                document = try #require(next.document)
            }
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func publicURLAndMemoryPublicationAreAtomicUnderLimitsAndCancellation() async throws {
        let (result, _) = try imported(Self.literalSTEP), document = try #require(result.document)
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { do { try FileManager.default.removeItem(at: directory) } catch { Issue.record("Unable to remove independent fixture: \(error)") } }
        let url = directory.appendingPathComponent("independent.step")
        let exchange = OfficialFormatExchange(tolerance: .standard)
        try exchange.export(document, as: .step, to: url)
        let fromURL = try exchange.import(from: url)
        try inspect(try #require(fromURL.document?.independentShapes))
        let retained = try Data(contentsOf: url)
        let constrained = OfficialFormatExchange(tolerance: .standard,
            stepExchange: STEPExchange(tolerance: .standard, resourceLimits: .init(maximumIterations: 1)))
        let sink = DataByteSink()
        try expectResource { try constrained.write(document, as: .step, to: sink) }
        #expect(sink.bytes.isEmpty)
        try expectResource { try constrained.export(document, as: .step, to: url) }
        #expect(try Data(contentsOf: url) == retained)
        let task = Task {
            while !Task.isCancelled { await Task.yield() }
            let output = DataByteSink()
            do { try exchange.write(document, as: .step, to: output); Issue.record("Cancelled independent write succeeded.") }
            catch is CancellationError { }
            #expect(output.bytes.isEmpty)
        }
        task.cancel(); try await task.value
    }

    @Test(.timeLimit(.minutes(1)))
    func originalFramedPlaneUsesTheContextLengthChartWithoutAxisUnitGain() throws {
        let records = #"""
        #1=(LENGTH_UNIT() NAMED_UNIT(*) SI_UNIT(.MILLI.,.METRE.));
        #2=(NAMED_UNIT(*) PLANE_ANGLE_UNIT() SI_UNIT($,.RADIAN.));
        #3=(GEOMETRIC_REPRESENTATION_CONTEXT(3) GLOBAL_UNIT_ASSIGNED_CONTEXT((#1,#2)) REPRESENTATION_CONTEXT('',''));
        #10=CARTESIAN_POINT('',(100.,200.,300.));
        #11=DIRECTION('',(0.,0.,1.));
        #12=DIRECTION('',(3.,4.,0.));
        #13=AXIS2_PLACEMENT_3D('',#10,#11,#12);
        #14=PLANE('original plane',#13);
        """#
        let prefix = try #require(Self.literalSTEP.range(of:"DATA;"))
        let literal = String(Self.literalSTEP[..<prefix.upperBound])+"\n"+records+"\nENDSEC;\nEND-ISO-10303-21;"
        var document = try #require(imported(literal).0.document)
        let native = DataByteSink(); try OfficialFormatExchange(tolerance:.standard).write(document,as:.swiftCAD,to:native)
        #expect(try OfficialFormatExchange(tolerance:.standard).import(native.bytes,as:.swiftCAD).document == document)
        for generation in 0..<3 {
            let source = try #require(document.independentShapes)
            #expect(source.items.count == 1 && source.geometry.surfaces.count == 1 && source.geometry.curves.isEmpty)
            let item = try #require(source.items.first)
            guard case .surface(let id) = item.geometry, case .plane(let plane) = source.geometry.surfaces[id] else {
                Issue.record("Plane's original infinite chart was substituted."); return
            }
            #expect(item.name == "original plane" && source.surfaceNames[id] == item.name)
            let association = try #require(source.surfacePositionFrames[id])
            let frame = try #require(source.frames.first)
            #expect(source.frames.count == 1 && association.frameID == frame.id && association.parameterLengthUnit == nil)
            #expect(frame.name.isEmpty && !source.roots.contains(.frame(frame.id)))
            #expect(plane.uDirection == Vector3D(x:0.6,y:0.8,z:0))
            let point = try Surface3D.plane(plane).point(u:document.units.length.toInternal(5),v:document.units.length.toInternal(-2),tolerance:.standard)
            #expect((point-Point3D(x:0.1046,y:0.2028,z:0.3)).length < 1e-12)
            if generation < 2 {
                let sink = DataByteSink(); try STEPExchange(tolerance:.standard).write(document,units:.millimeters,to:sink)
                document = try #require(STEPExchange(tolerance:.standard).import(sink.bytes).document)
            }
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func standaloneFrameAndStandardDefaultAxesSurviveWithoutInventedShapes() throws {
        let records = #"""
        #1=(LENGTH_UNIT() NAMED_UNIT(*) SI_UNIT($,.METRE.));
        #2=(NAMED_UNIT(*) PLANE_ANGLE_UNIT() SI_UNIT($,.RADIAN.));
        #3=(GEOMETRIC_REPRESENTATION_CONTEXT(3) GLOBAL_UNIT_ASSIGNED_CONTEXT((#1,#2)) REPRESENTATION_CONTEXT('',''));
        #10=CARTESIAN_POINT('',(3.,-2.,5.));
        #11=DIRECTION('',(0.,1.,2.));
        #12=AXIS2_PLACEMENT_3D('FRAME',#10,$,#11);
        """#
        let prefix = try #require(Self.literalSTEP.range(of: "DATA;"))
        let literal = String(Self.literalSTEP[..<prefix.upperBound]) + "\n" + records + "\nENDSEC;\nEND-ISO-10303-21;"
        let (_, source) = try imported(literal)
        #expect(source.items.isEmpty && source.geometry.curves.isEmpty && source.geometry.surfaces.isEmpty)
        #expect(source.frames.count == 1 && source.roots == [.frame(source.frames[0].id)])
        #expect(source.frames[0].name == "FRAME")
        // The legal nonperpendicular proposed ref direction is projected onto the default Z plane.
        let point = Point3D(x: 2, y: 4, z: 6), expected = Point3D(x: -1, y: 0, z: 11)
        #expect(source.frames[0].placement.applying(to: point) == expected)
        var document = CADDocument(units: .meters, independentShapes: source)
        for format in [ExchangeFileFormat.step, .iges] {
            for _ in 0..<2 {
                let sink = DataByteSink()
                try OfficialFormatExchange(tolerance: .standard).write(document, as: format, to: sink)
                let result = try OfficialFormatExchange(tolerance: .standard).import(sink.bytes, as: format)
                #expect(result.brep == nil && result.meshes.isEmpty)
                document = try #require(result.document)
                let retained = try #require(document.independentShapes)
                #expect(retained.frames.count == 1 && retained.items.isEmpty && retained.geometry.curves.isEmpty && retained.geometry.surfaces.isEmpty)
                #expect(retained.frames[0].name == "FRAME")
                #expect(retained.frames[0].placement.applying(to: point) == expected)
                #expect(retained.roots == [.frame(retained.frames[0].id)])
            }
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func ordinaryConicNamesFramesAndParameterLawsSurviveTwoSTEPGenerations() throws {
        let records = #"""
        #1=(LENGTH_UNIT() NAMED_UNIT(*) SI_UNIT(.MILLI.,.METRE.));
        #2=(NAMED_UNIT(*) PLANE_ANGLE_UNIT() SI_UNIT($,.RADIAN.));
        #3=(GEOMETRIC_REPRESENTATION_CONTEXT(3) GLOBAL_UNIT_ASSIGNED_CONTEXT((#1,#2)) REPRESENTATION_CONTEXT('',''));
        #10=CARTESIAN_POINT('',(10.,20.,30.));
        #11=DIRECTION('',(0.,0.,1.));
        #12=DIRECTION('',(0.,1.,2.));
        #13=AXIS2_PLACEMENT_3D('original conic frame',#10,#11,#12);
        #14=CIRCLE('ordinary circle',#13,4.);
        #15=ELLIPSE('ordinary ellipse',#13,6.,2.);
        #16=HYPERBOLA('ordinary hyperbola',#13,6.,2.);
        #17=PARABOLA('ordinary parabola',#13,2.);
        """#
        let prefix = try #require(Self.literalSTEP.range(of: "DATA;"))
        let literal = String(Self.literalSTEP[..<prefix.upperBound]) + "\n" + records + "\nENDSEC;\nEND-ISO-10303-21;"
        var document = try #require(imported(literal).0.document)
        let native = DataByteSink(); try OfficialFormatExchange(tolerance: .standard).write(document, as: .swiftCAD, to: native)
        #expect(try OfficialFormatExchange(tolerance: .standard).import(native.bytes, as: .swiftCAD).document == document)
        let unchanged = DataByteSink()
        #expect(throws: IndependentShapeExchangeError.metadataLoss("Original parabola parameter unit differs from the output context.")) {
            try STEPExchange(tolerance: .standard).write(document, units: .meters, to: unchanged)
        }
        #expect(unchanged.bytes.isEmpty)
        for generation in 0..<3 {
            let source = try #require(document.independentShapes)
            #expect(source.items.count == 4 && source.geometry.curves.count == 4 && source.frames.count == 1 && source.curvePositionFrames.count == 4)
            let position = try #require(source.frames.first)
            #expect(position.name == "original conic frame")
            #expect(source.roots.count == 4 && !source.roots.contains(.frame(position.id)))
            for item in source.items {
                guard case .curve(let id, _) = item.geometry else { Issue.record("Conic fixture lost a curve selection."); continue }
                let association = try #require(source.curvePositionFrames[id])
                #expect(association.frameID == position.id)
                #expect(association.parameterLengthUnit == (item.name == "ordinary parabola" ? .millimeter : nil))
                let curve = try #require(source.geometry.curves[id])
                #expect(source.curveNames[id] == item.name)
                for t in [-0.25, 0, 0.4] {
                    let localX: Double, localY: Double
                    switch item.name {
                    case "ordinary circle": localX = 0.004*cos(t); localY = 0.004*sin(t)
                    case "ordinary ellipse": localX = 0.006*cos(t); localY = 0.002*sin(t)
                    case "ordinary hyperbola": localX = 0.006*cosh(t); localY = 0.002*sinh(t)
                    case "ordinary parabola": localX = 0.001*t*t/8; localY = 0.001*t
                    default: Issue.record("Ordinary standard conic label changed."); continue
                    }
                    let expected = Point3D(x: 0.01-localY, y: 0.02+localX, z: 0.03)
                    #expect((try curve.point(at: t, tolerance: .standard)-expected).length < 1e-12)
                }
            }
            if generation < 2 {
                let sink = DataByteSink(); try STEPExchange(tolerance: .standard).write(document, to: sink)
                document = try #require(STEPExchange(tolerance: .standard).import(sink.bytes).document)
            }
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func sharedBodyLINEProducerKeepsVectorMagnitudeAndExactEndpointTrim() throws {
        // Independent millimeter triangle. Every original spatial LINE advances 5 mm per parameter.
        let records = #"""
        #1=(LENGTH_UNIT() NAMED_UNIT(*) SI_UNIT(.MILLI.,.METRE.));
        #2=(NAMED_UNIT(*) PLANE_ANGLE_UNIT() SI_UNIT($,.RADIAN.));
        #3=(GEOMETRIC_REPRESENTATION_CONTEXT(3) GLOBAL_UNIT_ASSIGNED_CONTEXT((#1,#2)) REPRESENTATION_CONTEXT('',''));
        #10=CARTESIAN_POINT('',(0.,0.,0.));
        #11=CARTESIAN_POINT('',(40.,0.,0.));
        #12=CARTESIAN_POINT('',(0.,20.,0.));
        #13=DIRECTION('',(0.,0.,1.));
        #14=DIRECTION('',(1.,0.,0.));
        #15=DIRECTION('',(-2.,1.,0.));
        #16=DIRECTION('',(0.,-1.,0.));
        #17=AXIS2_PLACEMENT_3D('',#10,#13,#14);
        #18=PLANE('',#17);
        #19=VECTOR('',#14,5.);
        #20=VECTOR('',#15,5.);
        #21=VECTOR('',#16,5.);
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
        #100=(GEOMETRIC_REPRESENTATION_CONTEXT(2) PARAMETRIC_REPRESENTATION_CONTEXT() REPRESENTATION_CONTEXT('',''));
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
        """#
        let prefix = try #require(Self.literalSTEP.range(of: "DATA;"))
        let literal = String(Self.literalSTEP[..<prefix.upperBound]) + "\n" + records + "\nENDSEC;\nEND-ISO-10303-21;"
        let exchange = STEPExchange(tolerance: .standard)
        var model = try #require(exchange.import(Data(literal.utf8)).brep)
        for generation in 0..<3 {
            try model.validate(level: .exact, tolerance: .standard)
            #expect(model.bodies.count == 1 && model.faces.count == 1 && model.edges.count == 3 && model.vertices.count == 3)
            for edge in model.edges.values {
                let curve = try #require(model.geometry.curves[edge.curveID])
                let trim = try #require(edge.trim)
                let start = try #require(model.vertices[edge.startVertexID]?.point)
                let end = try #require(model.vertices[edge.endVertexID]?.point)
                #expect((try curve.point(at: trim.startParameter, tolerance: .standard)-start).length < 1e-12)
                #expect((try curve.point(at: trim.endParameter, tolerance: .standard)-end).length < 1e-12)
                #expect(abs((try curve.point(at: 1, tolerance: .standard)-curve.point(at: 0, tolerance: .standard)).length-0.005) < 1e-12)
                if start == .origin && end == Point3D(x: 0.04, y: 0, z: 0) {
                    #expect(abs(trim.startParameter) < 1e-12 && abs(trim.endParameter-8) < 1e-12)
                }
            }
            if generation < 2 {
                let sink = DataByteSink(); try exchange.write(brep: model, units: .millimeters, to: sink)
                model = try #require(exchange.import(sink.bytes).brep)
            }
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func realMissingOriginMembershipCycleAndForeignUnitsRefuse() throws {
        let missingMembership = Self.literalSTEP.replacingOccurrences(of: "(#40,#41),#3", with: "(#40),#3")
        #expect(throws: IndependentShapeSourceError.invalidSource("Mapping origin must have actual representation membership in the mapped context.")) {
            try imported(missingMembership)
        }
        let cycle = Self.literalSTEP.replacingOccurrences(of: "REPRESENTATION_MAP(#41,#42)", with: "REPRESENTATION_MAP(#41,#49)")
        #expect(throws: IndependentShapeExchangeError.invalidAssociation("Cyclic representation map.")) { try imported(cycle) }
        let foreign = Self.literalSTEP.replacingOccurrences(of: "#49=SHAPE_REPRESENTATION('placed geometry',(#46,#48),#3);", with: """
        #57=(LENGTH_UNIT() NAMED_UNIT(*) SI_UNIT($,.METRE.));
        #58=(GEOMETRIC_REPRESENTATION_CONTEXT(3) GLOBAL_UNIT_ASSIGNED_CONTEXT((#57,#2)) REPRESENTATION_CONTEXT('meters','3D'));
        #49=SHAPE_REPRESENTATION('placed geometry',(#46,#48),#58);
        #59=SHAPE_REPRESENTATION('foreign primitive',(#14),#58);
        """)
        #expect(throws: IndependentShapeExchangeError.invalidAssociation("Shared primitive has conflicting unit contexts.")) { try imported(foreign) }
    }
}
