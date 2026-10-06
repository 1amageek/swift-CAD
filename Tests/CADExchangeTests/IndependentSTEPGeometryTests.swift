import CADCore
import CADGeometry
import CADTopology
import CADExchange
import Foundation
import Testing

@Suite("Independent STEP geometry", .timeLimit(.minutes(1)))
struct IndependentSTEPGeometryTests {
    private let tolerance = ModelingTolerance.standard

    @Test func rationalCurveReverseTrimNameAndMillimetersRoundTrip() throws {
        let curve = BSplineCurve3D(degree: 2, knots: [0, 0, 0, 1, 1, 1],
            controlPoints: [.origin, .init(x: 1, y: 2, z: 0), .init(x: 2, y: 0, z: 1)], weights: [1, 0.5, 2])
        let trim = CurveTrim(startParameter: 0.875, endParameter: 0.125)
        let model = IndependentSTEPGeometry(curves: [.init(name: "rail 'A'", curve: .bSpline(curve), trim: trim)],
            units: .init(length: .millimeter, angle: .radian))
        let exchange: any IndependentSTEPGeometryExchanging = STEPExchange(tolerance: tolerance)
        let sink = DataByteSink()
        try exchange.writeIndependentGeometry(model, to: sink)
        let text = try #require(String(data: sink.bytes, encoding: .utf8))
        #expect(text.contains("GEOMETRIC_CURVE_SET('rail ''A''',"))
        #expect(!text.contains("MANIFOLD_SOLID_BREP"))
        let restored = try exchange.importIndependentGeometry(sink.bytes)
        #expect(restored.units == model.units)
        #expect(restored.curves.count == 1 && restored.surfaces.isEmpty)
        let item = try #require(restored.curves.first)
        #expect(item.name == "rail 'A'")
        #expect(item.trim == trim)
        #expect(item.curve == .bSpline(curve))
        for t in [0.125, 0.42, 0.875] {
            #expect(try item.curve.point(at: t, tolerance: tolerance) == curve.point(at: t, tolerance: tolerance))
        }
    }

    @Test func lineTrimKeepsInternalLengthsUnderForeignUnits() throws {
        let model = IndependentSTEPGeometry(curves: [.init(name: "line", curve: .line(.init(origin: .origin, direction: .unitX)),
            trim: .init(startParameter: 2, endParameter: -0.5)),
            .init(name: "analytic line", curve: .analytic(.line(origin: .origin, direction: .unitX)),
                trim: .init(startParameter: 1, endParameter: -1))], units: .init(length: .millimeter, angle: .radian))
        let exchange = STEPExchange(tolerance: tolerance), sink = DataByteSink()
        try exchange.writeIndependentGeometry(model, to: sink)
        let restored = try exchange.importIndependentGeometry(sink.bytes)
        #expect(restored.curves[0].trim == model.curves[0].trim)
        #expect(restored.curves[0].curve == model.curves[0].curve)
        #expect(restored.curves[1].curve == model.curves[1].curve)
        #expect(restored.curves[1].trim == model.curves[1].trim)
        #expect(try restored.curves[0].curve.point(at: 2, tolerance: tolerance) == Point3D(x: 2, y: 0, z: 0))
    }

    @Test func foreignLineMagnitudeAndMissingContextLengthUnitAreRefused() throws {
        let model = IndependentSTEPGeometry(curves: [.init(name: "line", curve: .line(.init(origin: .origin, direction: .unitX)),
            trim: .init(startParameter: 2, endParameter: -0.5))])
        let exchange = STEPExchange(tolerance: tolerance), sink = DataByteSink()
        try exchange.writeIndependentGeometry(model, to: sink)
        let text = try #require(String(data: sink.bytes, encoding: .utf8))
        let scaled = text.replacingOccurrences(of: ",1.)", with: ",2.)")
        #expect(throws: KernelError.self) { try exchange.importIndependentGeometry(Data(scaled.utf8)) }
        // The unused length unit declaration must not authorize an angle-only context.
        let noLength = text.replacingOccurrences(of: "GLOBAL_UNIT_ASSIGNED_CONTEXT((#1,#2))", with: "GLOBAL_UNIT_ASSIGNED_CONTEXT((#2))")
        #expect(throws: ImportError.self) { try exchange.importIndependentGeometry(Data(noLength.utf8)) }
    }

    @Test func rationalSurfaceAndAnalyticSupportRoundTripTogether() throws {
        let surface = BSplineSurface3D(uDegree: 1, vDegree: 1, uKnots: [0, 0, 1, 1], vKnots: [0, 0, 1, 1],
            controlPoints: [[.origin, .init(x: 1, y: 0, z: 0)], [.init(x: 0, y: 1, z: 0), .init(x: 1, y: 1, z: 1)]],
            weights: [[1, 2], [0.5, 1]])
        let sphere = Surface3D.analytic(.sphere(center: .init(x: 1, y: 2, z: 3), radius: 2))
        let model = IndependentSTEPGeometry(surfaces: [.init(name: "patch", surface: .bSpline(surface)), .init(name: "sphere", surface: sphere)])
        let exchange: any IndependentSTEPGeometryExchanging = STEPExchange(tolerance: tolerance)
        let sink = DataByteSink()
        try exchange.writeIndependentGeometry(model, to: sink)
        let restored = try exchange.importIndependentGeometry(sink.bytes)
        #expect(restored.curves.isEmpty && restored.surfaces.count == 2)
        #expect(restored.surfaces[0].name == "patch")
        #expect(restored.surfaces[0].surface == .bSpline(surface))
        #expect(restored.surfaces[1].surface == sphere)
        #expect(try restored.surfaces[0].surface.point(u: 0.3, v: 0.7, tolerance: tolerance)
            == surface.point(u: 0.3, v: 0.7, tolerance: tolerance))
    }

    @Test func analyticCircleEllipseAndNativeArcRetainTheirParameterLaws() throws {
        let curves: [IndependentSTEPCurve] = [
            .init(name: "analytic circle", curve: .analytic(.circle(center: .origin, normal: .unitZ, radius: 2))),
            .init(name: "ellipse", curve: .analytic(.ellipse(center: .origin, normal: .unitZ,
                majorAxis: .unitX, majorRadius: 2, minorRadius: 1))),
            .init(name: "arc", curve: .analytic(.arc(center: .origin, normal: .unitZ, radius: 2,
                startAngle: 0.2, endAngle: 0.8)))
        ]
        let exchange = STEPExchange(tolerance: tolerance), sink = DataByteSink()
        try exchange.writeIndependentGeometry(.init(curves: curves), to: sink)
        let restored = try exchange.importIndependentGeometry(sink.bytes)
        #expect(restored.curves.count == curves.count)
        for index in curves.indices {
            #expect(restored.curves[index].curve == curves[index].curve)
            #expect(restored.curves[index].trim == nil)
            for parameter in [0.2, 0.4, 0.8] {
                #expect(try restored.curves[index].curve.point(at: parameter, tolerance: tolerance)
                    == curves[index].curve.point(at: parameter, tolerance: tolerance))
            }
        }
    }

    @Test func convertedChartsComposeWithIndependentExchange() throws {
        let nativeCurve = Curve3D.analytic(.circle(center: .origin, normal: .unitZ, radius: 2))
        let nativeSurface = Surface3D.analytic(.plane(origin: .origin, normal: .unitZ))
        let curveSource = try AffineCurveConversionSource(
            source: NativeCurveConversionSource(nativeCurve, tolerance: tolerance), scale: -2, offset: 0.5)
        let surfaceSource = try AffineSurfaceConversionSource(
            source: NativeSurfaceConversionSource(nativeSurface, tolerance: tolerance),
            uScale: -0.5, uOffset: 0.25, vScale: 2, vOffset: -1)
        let converter: any GeometryConverting = CertifiedGeometryConverter()
        let limits = GeometryConversionRequirements(maximumPositionError: 0.001,
            maximumTangentAngle: 0.1, maximumCurvatureError: 0.1,
            maximumScalarCount: 64_000_000, maximumWorkUnits: 1_000_000_000)
        let curve = try converter.approximateCurve(source: curveSource,
            over: ScalarInterval(lower: 0, upper: 0.125), requirements: limits, tolerance: tolerance)
        let surface = try converter.approximateSurface(source: surfaceSource,
            over: .init(u: ScalarInterval(lower: 0, upper: 1), v: ScalarInterval(lower: 0, upper: 1)),
            requirements: limits, tolerance: tolerance)
        let exchange: any IndependentSTEPGeometryExchanging = STEPExchange(tolerance: tolerance)
        let sink = DataByteSink()
        try exchange.writeIndependentGeometry(.init(curves: [.init(name: "converted rail", curve: .bSpline(curve.curve))],
            surfaces: [.init(name: "converted panel", surface: .bSpline(surface.surface))]), to: sink)
        let restored = try exchange.importIndependentGeometry(sink.bytes)
        #expect(restored.curves[0].curve == .bSpline(curve.curve))
        #expect(restored.surfaces[0].surface == .bSpline(surface.surface))
        #expect(try (restored.curves[0].curve.point(at: 0.0625, tolerance: tolerance)
            - nativeCurve.point(at: 0.375, tolerance: tolerance)).length <= limits.maximumPositionError)
        #expect(try (restored.surfaces[0].surface.point(u: 0.3, v: 0.7, tolerance: tolerance)
            - nativeSurface.point(u: 0.1, v: 0.4, tolerance: tolerance)).length <= limits.maximumPositionError)
    }

    @Test func unsupportedEmptyAndExhaustedExportsDoNotWriteTheSink() throws {
        let sink = DataByteSink()
        let exchange = STEPExchange(tolerance: tolerance)
        #expect(throws: KernelError.self) { try exchange.writeIndependentGeometry(.init(), to: sink) }
        #expect(sink.bytes.isEmpty)
        let line = IndependentSTEPGeometry(curves: [.init(name: "unbounded", curve: .line(.init(origin: .origin, direction: .unitX)))])
        #expect(throws: KernelError.self) { try exchange.writeIndependentGeometry(line, to: sink) }
        #expect(sink.bytes.isEmpty)
        let model = IndependentSTEPGeometry(curves: [.init(name: "circle", curve: .circle(.init(center: .origin, normal: .unitZ, radius: 1)))])
        let bounded = STEPExchange(tolerance: tolerance, resourceLimits: .init(maximumBytes: 32, maximumEntities: 2))
        #expect(throws: KernelError.self) { try bounded.writeIndependentGeometry(model, to: sink) }
        #expect(sink.bytes.isEmpty)
        let degrees = IndependentSTEPGeometry(curves: model.curves, units: .millimeters)
        #expect(throws: KernelError.self) { try exchange.writeIndependentGeometry(degrees, to: sink) }
        #expect(sink.bytes.isEmpty)
    }

    @Test func malformedMixedAndMissingRepresentationItemsAreRefused() throws {
        let model = IndependentSTEPGeometry(curves: [.init(name: "circle", curve: .circle(.init(center: .origin, normal: .unitZ, radius: 1)))])
        let exchange = STEPExchange(tolerance: tolerance), sink = DataByteSink()
        try exchange.writeIndependentGeometry(model, to: sink)
        let text = try #require(String(data: sink.bytes, encoding: .utf8))
        #expect(throws: ImportError.self) { try exchange.importIndependentGeometry(Data("not STEP".utf8)) }
        let mixed = text.replacingOccurrences(of: "DATA;", with: "DATA;\n#99999=MANIFOLD_SOLID_BREP('',#99998);")
        #expect(throws: KernelError.self) { try exchange.importIndependentGeometry(Data(mixed.utf8)) }
        let metadata = text.replacingOccurrences(of: "DATA;", with: "DATA;\n#99999=PRODUCT('id','authored name','',());")
        #expect(throws: KernelError.self) { try exchange.importIndependentGeometry(Data(metadata.utf8)) }
        let missing = text.replacingOccurrences(of: "GEOMETRIC_CURVE_SET('circle',(", with: "GEOMETRIC_CURVE_SET('circle',(#99999,")
        #expect(throws: KernelError.self) { try exchange.importIndependentGeometry(Data(missing.utf8)) }
        let limited = STEPExchange(tolerance: tolerance, resourceLimits: .init(maximumBytes: 8))
        #expect(throws: KernelError.self) { try limited.importIndependentGeometry(sink.bytes) }
    }

    @Test func cancellationPreventsSourcePublicationAndSinkMutation() async throws {
        let model = IndependentSTEPGeometry(curves: [.init(name: "circle", curve: .circle(.init(center: .origin, normal: .unitZ, radius: 1)))])
        let exchange = STEPExchange(tolerance: tolerance)
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            let sink = DataByteSink()
            defer { #expect(sink.bytes.isEmpty) }
            try exchange.writeIndependentGeometry(model, to: sink)
        }
        await #expect(throws: CancellationError.self) { try await task.value }
        let sink = DataByteSink()
        try exchange.writeIndependentGeometry(model, to: sink)
        let bytes = sink.bytes
        let importTask = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try exchange.importIndependentGeometry(bytes)
        }
        await #expect(throws: CancellationError.self) { try await importTask.value }
    }
}
