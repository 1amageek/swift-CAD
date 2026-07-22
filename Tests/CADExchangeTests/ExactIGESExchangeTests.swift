import Foundation
import Testing
import CADCore
import CADGeometry
import CADIR
import CADModeling
import CADTopology
import CADKernel
@testable import CADExchange

@Suite("Exact IGES exchange")
struct ExactIGESExchangeTests {
    @Test(.timeLimit(.minutes(1)))
    func rejectsInvalidExplicitToleranceBeforeImport() {
        let exchange = IGESExchange(tolerance: ModelingTolerance(distance: 0.0, angle: 1.0e-9))

        #expect(throws: GeometryError.self) {
            _ = try exchange.import(Data())
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func roundTripsWatertightPlanarSolidWithoutMeshFallback() throws {
        let source = try rectangularSolid()
        let sink = DataByteSink()
        try IGESExchange(tolerance: .standard).write(brep: source, units: .millimeters, to: sink)
        let text = try #require(String(data: sink.bytes, encoding: .utf8))
        let records = text.split(separator: "\n")
        #expect(records.allSatisfy { $0.count == 80 })
        #expect(text.contains("TRIANGULATED") == false)

        let imported = try IGESExchange(tolerance: .standard).import(sink.bytes)
        let result = try #require(imported.brep)
        try result.validate(level: .volumetric, tolerance: .standard)
        #expect(imported.meshes.isEmpty)
        #expect(imported.units == UnitSystem(length: .millimeter, angle: .radian))
        #expect(result.bodies.values.allSatisfy { $0.kind == .solid })
        #expect(result.faces.count == 6)
        #expect(result.edges.count == 12)
        #expect(result.vertices.count == 8)
        #expect(abs(try result.volume(tolerance: .standard) - source.volume(tolerance: .standard)) <= 1.0e-12)
    }

    @Test(.timeLimit(.minutes(1)))
    func roundTripsSolidVoidShellTopologyAndVolume() throws {
        let source = try ExactExchangeVoidFixture.rectangularCavitySolid()
        let sourceVolume = try source.volume(tolerance: .standard)
        let sink = DataByteSink()
        try IGESExchange(tolerance: .standard).write(
            brep: source,
            units: .millimeters,
            to: sink
        )

        let imported = try IGESExchange(tolerance: .standard).import(sink.bytes)
        let result = try #require(imported.brep)
        try result.validate(level: .volumetric, tolerance: .standard)
        let body = try #require(result.bodies.values.first)
        let orientations = body.shellIDs.compactMap { result.shells[$0]?.orientation }
        #expect(imported.meshes.isEmpty)
        #expect(result.bodies.count == 1)
        #expect(body.shellIDs.count == 2)
        #expect(orientations.filter { $0 == .forward }.count == 1)
        #expect(orientations.filter { $0 == .reversed }.count == 1)
        #expect(result.faces.count == source.faces.count)
        #expect(result.edges.count == source.edges.count)
        #expect(result.vertices.count == source.vertices.count)
        #expect(abs(try result.volume(tolerance: .standard) - sourceVolume) <= 1.0e-12)
    }

    @Test(.timeLimit(.minutes(1)))
    func roundTripsMultiShellSheetBodyAsForm7Group() throws {
        let source = try ExactExchangeMultiShellFixture.disconnectedSheetBody()
        let sink = DataByteSink()
        try IGESExchange(tolerance: .standard).write(
            brep: source,
            units: .millimeters,
            to: sink
        )
        let text = try #require(String(data: sink.bytes, encoding: .utf8))
        let parameterData = text
            .split(separator: "\n")
            .filter { line in
                let characters = Array(line)
                return characters.count == 80 && characters[72] == "P"
            }
            .map { String($0.prefix(64)).trimmingCharacters(in: .whitespaces) }
            .joined()
        #expect(text.contains("SHEETBDY"))
        #expect(parameterData.contains("402,2,"))

        let imported = try IGESExchange(tolerance: .standard).import(sink.bytes)
        let result = try #require(imported.brep)
        try result.validate(level: .exact, tolerance: .standard)
        let body = try #require(result.bodies.values.first)
        #expect(imported.meshes.isEmpty)
        #expect(result.bodies.count == 1)
        #expect(body.kind == .sheet)
        #expect(body.shellIDs.count == 2)
        #expect(body.shellIDs.allSatisfy { result.shells[$0]?.orientation == .forward })
        #expect(result.shells.count == source.shells.count)
        #expect(result.faces.count == source.faces.count)
        #expect(result.edges.count == source.edges.count)
        #expect(result.vertices.count == source.vertices.count)
    }

    @Test(.timeLimit(.minutes(1)))
    func assignsDeterministicTopologyIdentifiersDuringImport() throws {
        let sink = DataByteSink()
        try IGESExchange(tolerance: .standard).write(brep: try rectangularSolid(), units: .millimeters, to: sink)
        let first = try #require(IGESExchange(tolerance: .standard).import(sink.bytes).brep)
        let second = try #require(IGESExchange(tolerance: .standard).import(sink.bytes).brep)
        #expect(first == second)
    }

    @Test(.timeLimit(.minutes(1)))
    func enforcesOutputEntityLimit() throws {
        let exchange = IGESExchange(tolerance: .standard, resourceLimits: ExchangeResourceLimits(
            maximumBytes: 1_000_000,
            maximumEntities: 10,
            maximumNesting: 32,
            maximumIterations: 10_000
        ))
        #expect(throws: KernelError.self) {
            try exchange.write(brep: rectangularSolid(), to: DataByteSink())
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func roundTripsRationalBSplineCurveSurfaceAndPcurves() throws {
        let source = try ExactExchangeNURBSFixture.rationalSheet()
        let sink = DataByteSink()
        try IGESExchange(tolerance: .standard).write(brep: source, units: .millimeters, to: sink)

        let result = try #require(IGESExchange(tolerance: .standard).import(sink.bytes).brep)
        try result.validate(level: .exact, tolerance: .standard)

        let sourceSurface = try #require(source.geometry.surfaces.values.first)
        let resultSurface = try #require(result.geometry.surfaces.values.first)
        guard case let .bSpline(sourceSpline) = sourceSurface,
              case let .bSpline(resultSpline) = resultSurface else {
            Issue.record("IGES rational B-spline surface was not preserved.")
            return
        }
        #expect(resultSpline.uDegree == sourceSpline.uDegree)
        #expect(resultSpline.vDegree == sourceSpline.vDegree)
        #expect(resultSpline.uKnots == sourceSpline.uKnots)
        #expect(resultSpline.vKnots == sourceSpline.vKnots)
        #expect(resultSpline.weights == sourceSpline.weights)
        #expect(result.geometry.curves.values.allSatisfy {
            if case .bSpline = $0 { return true }
            return false
        })
        for (u, v) in [(0.0, 0.0), (0.25, 0.75), (1.0, 1.0)] {
            let expected = try sourceSurface.point(u: u, v: v, tolerance: .standard)
            let actual = try resultSurface.point(u: u, v: v, tolerance: .standard)
            #expect(actual.isApproximatelyEqual(to: expected, tolerance: 1.0e-12))
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func roundTripsReversedCompleteDomainRationalBSplineEdges() throws {
        let source = try ExactExchangeNURBSFixture.reversedRationalSheet()
        let sink = DataByteSink()
        try IGESExchange(tolerance: .standard).write(brep: source, units: .millimeters, to: sink)

        let result = try #require(IGESExchange(tolerance: .standard).import(sink.bytes).brep)
        try result.validate(level: .exact, tolerance: .standard)
        let bSplineEdges = result.edges.values.filter { edge in
            if case .bSpline = result.geometry.curves[edge.curveID] {
                return true
            }
            return false
        }
        #expect(bSplineEdges.isEmpty == false)
        #expect(bSplineEdges.allSatisfy { edge in
            guard let trim = edge.trim else { return false }
            return trim.startParameter > trim.endParameter
        })
    }

    @Test(.timeLimit(.minutes(1)))
    func roundTripsPartialDomainRationalBSplineEdgesInBothDirections() throws {
        for reversed in [false, true] {
            let source = try ExactExchangeNURBSFixture.partialRationalPcurveSheet(
                reversed: reversed
            )
            let sink = DataByteSink()
            try IGESExchange(tolerance: .standard).write(
                brep: source,
                units: .millimeters,
                to: sink
            )

            let result = try #require(
                IGESExchange(tolerance: .standard).import(sink.bytes).brep
            )
            try result.validate(level: .exact, tolerance: .standard)
            let edge = try #require(result.edges.values.first { edge in
                if case .bSpline = result.geometry.curves[edge.curveID] {
                    return true
                }
                return false
            })
            let trim = try #require(edge.trim)
            let expectedStart = reversed ? 0.8 : 0.2
            let expectedEnd = reversed ? 0.2 : 0.8
            #expect(abs(trim.startParameter - expectedStart) <= 1.0e-12)
            #expect(abs(trim.endParameter - expectedEnd) <= 1.0e-12)
            guard case let .bSpline(curve) = result.geometry.curves[edge.curveID],
                  case let .closed(lower, upper) = curve.domain else {
                Issue.record("IGES partial edge did not preserve its B-spline basis domain.")
                continue
            }
            #expect(abs(lower) <= 1.0e-12)
            #expect(abs(upper - 1.0) <= 1.0e-12)
            #expect(result.loops.values.flatMap(\.coedges).contains { coedge in
                if case .some(.bSpline) = coedge.surfaceParameterCurve {
                    return true
                }
                return false
            })
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func roundTripsCircularEdgesAndCylindricalSurface() throws {
        let source = try ExactExchangeAnalyticFixture.cylindricalSheet()
        let sink = DataByteSink()
        try IGESExchange(tolerance: .standard).write(brep: source, units: .millimeters, to: sink)

        let result = try #require(IGESExchange(tolerance: .standard).import(sink.bytes).brep)
        try result.validate(level: .exact, tolerance: .standard)
        #expect(result.geometry.surfaces.values.contains {
            if case .cylinder = $0 { return true }
            return false
        })
        #expect(result.geometry.curves.values.filter {
            if case .circle = $0 { return true }
            return false
        }.count == 2)
        let sourceSurface = try #require(source.geometry.surfaces.values.first)
        let resultSurface = try #require(result.geometry.surfaces.values.first)
        for (u, v) in [(0.0, 0.0), (Double.pi * 0.25, 0.005), (Double.pi * 0.5, 0.010)] {
            let expected = try sourceSurface.point(u: u, v: v, tolerance: .standard)
            let actual = try resultSurface.point(u: u, v: v, tolerance: .standard)
            #expect(actual.isApproximatelyEqual(to: expected, tolerance: 1.0e-12))
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func roundTripsSeamCrossingCircleAndEllipseEdges() throws {
        let fixtures = [
            try ExactExchangeAnalyticFixture.seamCrossingCylindricalSheet(),
            try ExactExchangeAdvancedAnalyticFixture.seamCrossingEllipticalSheet(),
        ]
        for source in fixtures {
            let sink = DataByteSink()
            try IGESExchange(tolerance: .standard).write(
                brep: source,
                units: .millimeters,
                to: sink
            )
            let result = try #require(
                IGESExchange(tolerance: .standard).import(sink.bytes).brep
            )
            try result.validate(level: .exact, tolerance: .standard)
            try ExactExchangePeriodicTrimAssertions.validate(source: source, result: result)
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func roundTripsClockwiseHarmonicPcurveAsExactRationalBSpline() throws {
        let source = try ExactExchangeAdvancedAnalyticFixture.clockwiseEllipticalSheet()
        let sourcePcurves: [SurfaceParameterCurve] = source.loops.values
            .flatMap(\.coedges)
            .compactMap { coedge -> SurfaceParameterCurve? in
            guard case .some(.harmonic) = coedge.surfaceParameterCurve else {
                return nil
            }
            return coedge.surfaceParameterCurve
        }
        let sourcePcurve = try #require(sourcePcurves.first)
        let sink = DataByteSink()
        try IGESExchange(tolerance: .standard).write(
            brep: source,
            units: .millimeters,
            to: sink
        )
        let text = try #require(String(data: sink.bytes, encoding: .utf8))
        #expect(text.contains("PCNURBS"))

        let imported = try IGESExchange(tolerance: .standard).import(sink.bytes)
        let result = try #require(imported.brep)
        try result.validate(level: .exact, tolerance: .standard)
        let resultCurves: [BSplineCurve2D] = result.loops.values
            .flatMap(\.coedges)
            .compactMap { coedge -> BSplineCurve2D? in
            guard case let .some(.bSpline(curve)) = coedge.surfaceParameterCurve else {
                return nil
            }
            return curve
        }
        let resultCurve = try #require(resultCurves.first)
        #expect(imported.meshes.isEmpty)
        #expect(resultCurve.degree == 2)
        #expect(resultCurve.isRational)
        #expect(resultCurve.controlPointCount == 5)
        #expect(resultCurve.knots == [0.0, 0.0, 0.0, 1.0, 1.0, 2.0, 2.0, 2.0])
        #expect(abs(resultCurve.weights[1] - sqrt(0.5)) <= 1.0e-12)
        #expect(abs(resultCurve.weights[3] - sqrt(0.5)) <= 1.0e-12)

        let resultPcurve = SurfaceParameterCurve.bSpline(resultCurve)
        var previousModelParameter = -Double.infinity
        let resultSurface = try #require(result.geometry.surfaces.values.first)
        let resultEdge = try #require(result.edges.values.first { edge in
            if case .analytic(.ellipse) = result.geometry.curves[edge.curveID] {
                return true
            }
            return false
        })
        let resultModelCurve = try #require(result.geometry.curves[resultEdge.curveID])
        let trim = try #require(resultEdge.trim)
        let parameterRange = try ScalarInterval(
            lower: min(trim.startParameter, trim.endParameter),
            upper: max(trim.startParameter, trim.endParameter)
        )
        for index in 0...16 {
            let fraction = Double(index) / 16.0
            let actual = try resultPcurve.parameter(
                atNormalizedFraction: fraction,
                tolerance: .standard
            )
            let ellipseResidual = abs(
                actual.u * actual.u / (0.040 * 0.040)
                    + actual.v * actual.v / (0.020 * 0.020)
                    - 1.0
            )
            #expect(ellipseResidual <= 1.0e-12)
            if index > 0, index < 16 {
                #expect(actual.v < 0.0)
            }
            let surfacePoint = try resultSurface.point(
                u: actual.u,
                v: actual.v,
                tolerance: .standard
            )
            let projection = try resultModelCurve.parameterProjection(
                of: surfacePoint,
                options: CurveParameterProjectionOptions(parameterRange: parameterRange),
                tolerance: .standard
            )
            #expect(projection.parameter >= previousModelParameter - ModelingTolerance.standard.angle)
            previousModelParameter = projection.parameter
        }
        let sourceStart = try sourcePcurve.startParameter(tolerance: .standard)
        let sourceEnd = try sourcePcurve.endParameter(tolerance: .standard)
        let resultStart = try resultPcurve.startParameter(tolerance: .standard)
        let resultEnd = try resultPcurve.endParameter(tolerance: .standard)
        #expect(resultStart.isApproximatelyEqual(to: sourceStart, tolerance: 1.0e-12))
        #expect(resultEnd.isApproximatelyEqual(to: sourceEnd, tolerance: 1.0e-12))
    }

    @Test(.timeLimit(.minutes(1)))
    func roundTripsArbitraryAxisAnalyticArcEdgesInBothDirections() throws {
        for reversed in [false, true] {
            let source = try ExactExchangeAdvancedAnalyticFixture.analyticArcSheet(
                reversed: reversed
            )
            let sourceEdge = try #require(source.edges.values.first { edge in
                if case .analytic(.arc) = source.geometry.curves[edge.curveID] {
                    return true
                }
                return false
            })
            let sourceCurve = try #require(source.geometry.curves[sourceEdge.curveID])
            let sourceTrim = try #require(sourceEdge.trim)
            let sink = DataByteSink()
            try IGESExchange(tolerance: .standard).write(
                brep: source,
                units: .millimeters,
                to: sink
            )
            let text = try #require(String(data: sink.bytes, encoding: .utf8))
            #expect(text.contains("ANAARC"))

            let imported = try IGESExchange(tolerance: .standard).import(sink.bytes)
            let result = try #require(imported.brep)
            try result.validate(level: .exact, tolerance: .standard)
            let resultEdge = try #require(result.edges.values.first { edge in
                if case .analytic(.arc) = result.geometry.curves[edge.curveID] {
                    return true
                }
                return false
            })
            let resultCurve = try #require(result.geometry.curves[resultEdge.curveID])
            let resultTrim = try #require(resultEdge.trim)
            #expect(imported.meshes.isEmpty)
            #expect(
                (resultTrim.endParameter > resultTrim.startParameter)
                    == (sourceTrim.endParameter > sourceTrim.startParameter)
            )
            #expect(
                abs(
                    (resultTrim.endParameter - resultTrim.startParameter)
                        - (sourceTrim.endParameter - sourceTrim.startParameter)
                ) <= ModelingTolerance.standard.angle
            )
            for index in 0...16 {
                let fraction = Double(index) / 16.0
                let sourceParameter = sourceTrim.startParameter
                    + (sourceTrim.endParameter - sourceTrim.startParameter) * fraction
                let resultParameter = resultTrim.startParameter
                    + (resultTrim.endParameter - resultTrim.startParameter) * fraction
                let expected = try sourceCurve.point(
                    at: sourceParameter,
                    tolerance: .standard
                )
                let actual = try resultCurve.point(
                    at: resultParameter,
                    tolerance: .standard
                )
                #expect(actual.isApproximatelyEqual(to: expected, tolerance: 1.0e-12))
            }
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func roundTripsTiltedCirclesThroughTransformationMatrices() throws {
        let source = try ExactExchangeAdvancedAnalyticFixture.tiltedCylindricalSheet()
        let sink = DataByteSink()
        try IGESExchange(tolerance: .standard).write(brep: source, units: .millimeters, to: sink)
        let text = try #require(String(data: sink.bytes, encoding: .utf8))
        #expect(text.contains("124,"))

        let result = try #require(IGESExchange(tolerance: .standard).import(sink.bytes).brep)
        try result.validate(level: .exact, tolerance: .standard)
        let sourceSurface = try #require(source.geometry.surfaces.values.first)
        let resultSurface = try #require(result.geometry.surfaces.values.first)
        for (u, v) in [(0.0, 0.0), (0.5, 0.004), (1.0, 0.010)] {
            let expected = try sourceSurface.point(u: u, v: v, tolerance: .standard)
            let actual = try resultSurface.point(u: u, v: v, tolerance: .standard)
            #expect(actual.isApproximatelyEqual(to: expected, tolerance: 1.0e-12))
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func roundTripsConeSphereAndTorusAnalyticSheets() throws {
        let fixtures: [(model: BRepModel, sample: (u: Double, v: Double), kind: String)] = [
            (try ExactExchangeAdvancedAnalyticFixture.conicalSheet(), (0.25, 0.030), "cone"),
            (try ExactExchangeAdvancedAnalyticFixture.sphericalSheet(), (0.25, 0.0), "sphere"),
            (try ExactExchangeAdvancedAnalyticFixture.toroidalSheet(), (0.25, 0.0), "torus"),
        ]
        for fixture in fixtures {
            do {
                let sink = DataByteSink()
                try IGESExchange(tolerance: .standard).write(brep: fixture.model, units: .millimeters, to: sink)
                let result = try #require(IGESExchange(tolerance: .standard).import(sink.bytes).brep)
                try result.validate(level: .exact, tolerance: .standard)
                let sourceSurface = try #require(fixture.model.geometry.surfaces.values.first)
                let resultSurface = try #require(result.geometry.surfaces.values.first)
                let expected = try sourceSurface.point(
                    u: fixture.sample.u,
                    v: fixture.sample.v,
                    tolerance: .standard
                )
                let actual = try resultSurface.point(
                    u: fixture.sample.u,
                    v: fixture.sample.v,
                    tolerance: .standard
                )
                #expect(
                    actual.isApproximatelyEqual(to: expected, tolerance: 1.0e-12),
                    "IGES failed to preserve the \(fixture.kind) parameterization."
                )
            } catch {
                Issue.record("IGES \(fixture.kind) round-trip failed: \(error)")
            }
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func roundTripsEllipseWithExactConicPcurve() throws {
        let source = try ExactExchangeAdvancedAnalyticFixture.ellipticalSheet()
        let sink = DataByteSink()
        try IGESExchange(tolerance: .standard).write(brep: source, units: .millimeters, to: sink)
        let text = try #require(String(data: sink.bytes, encoding: .utf8))
        #expect(text.contains("104,"))

        let result = try #require(IGESExchange(tolerance: .standard).import(sink.bytes).brep)
        try result.validate(level: .exact, tolerance: .standard)
        #expect(result.geometry.curves.values.contains {
            if case .analytic(.ellipse) = $0 { return true }
            return false
        })
        #expect(result.loops.values.flatMap(\.coedges).contains {
            if case .harmonic = $0.surfaceParameterCurve { return true }
            return false
        })
    }

    @Test(.timeLimit(.minutes(1)))
    func roundTripsOpenConicsWithType104FormsAndExactTrims() throws {
        for reversed in [false, true] {
            for fixture in [
                ("ANAHYPER", try ExactExchangeAdvancedAnalyticFixture.hyperbolicSheet(
                    reversed: reversed
                )),
                ("ANAPARAB", try ExactExchangeAdvancedAnalyticFixture.parabolicSheet(
                    reversed: reversed
                )),
            ] {
                let sink = DataByteSink()
                try IGESExchange(tolerance: .standard).write(
                    brep: fixture.1,
                    units: .millimeters,
                    to: sink
                )
                let text = try #require(String(data: sink.bytes, encoding: .utf8))
                #expect(text.contains(fixture.0))

                let result = try #require(
                    IGESExchange(tolerance: .standard).import(sink.bytes).brep
                )
                try result.validate(level: .exact, tolerance: .standard)
                let edge = try #require(result.edges.values.first { edge in
                    guard case let .analytic(curve) = result.geometry.curves[edge.curveID] else {
                        return false
                    }
                    switch curve {
                    case .hyperbola, .parabola:
                        return true
                    case .line, .circle, .arc, .ellipse, .planeTorus:
                        return false
                    }
                })
                let trim = try #require(edge.trim)
                #expect((trim.endParameter > trim.startParameter) == !reversed)
                #expect(result.loops.values.flatMap(\.coedges).contains {
                    if case .bSpline = $0.surfaceParameterCurve { return true }
                    return false
                })
            }
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func roundTripsConeHyperbolaWithoutApproximatedPcurve() throws {
        for reversed in [false, true] {
            let source = try ExactExchangeAdvancedAnalyticFixture.coneHyperbolicSheet(
                reversed: reversed
            )
            let sink = DataByteSink()
            try IGESExchange(tolerance: .standard).write(
                brep: source,
                units: .millimeters,
                to: sink
            )
            let text = try #require(String(data: sink.bytes, encoding: .utf8))
            #expect(text.contains("ANAHYPER"))
            #expect(text.contains("TRIANGULATED") == false)

            let result = try #require(
                IGESExchange(tolerance: .standard).import(sink.bytes).brep
            )
            try result.validate(level: .exact, tolerance: .standard)
            #expect(result.loops.values.flatMap(\.coedges).contains { coedge in
                guard case let .projectedAnalytic(projected) = coedge.surfaceParameterCurve,
                      case .analytic(.cone) = projected.surface,
                      case .analytic(.hyperbola) = projected.curve else {
                    return false
                }
                return (projected.endParameter > projected.startParameter) == !reversed
            })
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func roundTripsSphericalGreatCircleWithoutApproximatedPcurve() throws {
        for reversed in [false, true] {
            let source = try ExactExchangeAdvancedAnalyticFixture.greatCircleHemisphere(
                reversed: reversed
            )
            let sink = DataByteSink()
            try IGESExchange(tolerance: .standard).write(
                brep: source,
                units: .millimeters,
                to: sink
            )
            let text = try #require(String(data: sink.bytes, encoding: .utf8))
            #expect(text.contains("SPHERE"))
            #expect(text.contains("TRIANGULATED") == false)

            let result = try #require(
                IGESExchange(tolerance: .standard).import(sink.bytes).brep
            )
            try result.validate(level: .exact, tolerance: .standard)
            let greatCircles = result.loops.values.flatMap(\.coedges).filter { coedge in
                if case .sphericalGreatCircle = coedge.surfaceParameterCurve { return true }
                return false
            }
            #expect(greatCircles.count == 2)
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func roundTripsPlaneTorusIntersectionThroughNestedCurveOnSurfaceEntities() throws {
        for reversed in [false, true] {
            let source = try ExactExchangeAdvancedAnalyticFixture.planeTorusIntersectionSheet(
                reversed: reversed
            )
            let sink = DataByteSink()
            try IGESExchange(tolerance: .standard).write(
                brep: source,
                units: .millimeters,
                to: sink
            )
            let text = try #require(String(data: sink.bytes, encoding: .utf8))
            #expect(text.contains("INTPLANE"))
            #expect(text.contains("INTTORUS"))
            #expect(text.contains("TRIANGULATED") == false)

            let result = try #require(
                IGESExchange(tolerance: .standard).import(sink.bytes).brep
            )
            try result.validate(level: .exact, tolerance: .standard)
            #expect(result.geometry.curves.values.filter { curve in
                if case .analytic(.planeTorus) = curve { return true }
                return false
            }.count == 2)
            #expect(result.loops.values.flatMap(\.coedges).allSatisfy { coedge in
                if case .certifiedAnalyticPair = coedge.surfaceParameterCurve { return true }
                return false
            })
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func roundTripsCertifiedImplicitIntersectionThroughNestedCurveOnSurfaceEntities() throws {
        for reversed in [false, true] {
            let source = try ExactExchangeAdvancedAnalyticFixture.implicitBSplineIntersectionSheet(
                reversed: reversed
            )
            let sink = DataByteSink()
            try IGESExchange(tolerance: .standard).write(
                brep: source,
                units: .millimeters,
                to: sink
            )
            let text = try #require(String(data: sink.bytes, encoding: .utf8))
            #expect(text.contains("INTFIRST"))
            #expect(text.contains("INTSECOND"))
            #expect(text.contains("TRIANGULATED") == false)

            let result = try #require(
                IGESExchange(tolerance: .standard).import(sink.bytes).brep
            )
            try result.validate(level: .exact, tolerance: .standard)
            #expect(result.geometry.curves.values.contains { curve in
                if case .implicit = curve { return true }
                return false
            })
            #expect(result.loops.values.flatMap(\.coedges).contains { coedge in
                if case .certifiedImplicit = coedge.surfaceParameterCurve { return true }
                return false
            })
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func roundTripsCertifiedAnalyticBSplineIntersectionThroughNestedCurveOnSurfaceEntities() throws {
        for reversed in [false, true] {
            let source = try ExactExchangeAdvancedAnalyticFixture.analyticBSplineIntersectionSheet(
                reversed: reversed
            )
            let sink = DataByteSink()
            try IGESExchange(tolerance: .standard).write(
                brep: source,
                units: .millimeters,
                to: sink
            )
            let text = try #require(String(data: sink.bytes, encoding: .utf8))
            #expect(text.contains("ANASPHER"))
            #expect(text.contains("NURBSSRF"))
            #expect(text.contains("INTFIRST"))
            #expect(text.contains("INTSECOND"))
            #expect(text.contains("TRIANGULATED") == false)

            let result = try #require(
                IGESExchange(tolerance: .standard).import(sink.bytes).brep
            )
            try result.validate(level: .exact, tolerance: .standard)
            #expect(result.geometry.curves.values.contains { curve in
                if case .implicit = curve { return true }
                return false
            })
            #expect(result.loops.values.flatMap(\.coedges).allSatisfy { coedge in
                if case .certifiedAnalyticImplicit = coedge.surfaceParameterCurve { return true }
                return false
            })
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func roundTripsSurfaceLiftThroughExactCurveOnSurfaceEntity() throws {
        for reversed in [false, true] {
            let source = try ExactExchangeAdvancedAnalyticFixture.surfaceLiftSheet(
                reversed: reversed
            )
            let sink = DataByteSink()
            try IGESExchange(tolerance: .standard).write(
                brep: source,
                units: .millimeters,
                to: sink
            )
            let text = try #require(String(data: sink.bytes, encoding: .utf8))
            #expect(text.contains("SURFLIFT"))
            #expect(text.contains("LIFTMODEL"))
            #expect(text.contains("TRIANGULATED") == false)

            let result = try #require(
                IGESExchange(tolerance: .standard).import(sink.bytes).brep
            )
            try result.validate(level: .exact, tolerance: .standard)
            let edge = try #require(result.edges.values.first { edge in
                if case .surfaceLift = result.geometry.curves[edge.curveID] { return true }
                return false
            })
            let trim = try #require(edge.trim)
            #expect((trim.endParameter > trim.startParameter) == !reversed)
            #expect(result.loops.values.flatMap(\.coedges).contains { coedge in
                guard coedge.edgeID == edge.id,
                      case let .bSpline(curve) = coedge.surfaceParameterCurve else {
                    return false
                }
                return curve.isRational
            })
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func roundTripsRationalNonlinearPcurve() throws {
        let source = try ExactExchangeNURBSFixture.rationalPcurveSheet()
        let sink = DataByteSink()
        try IGESExchange(tolerance: .standard).write(brep: source, units: .millimeters, to: sink)
        let result = try #require(IGESExchange(tolerance: .standard).import(sink.bytes).brep)
        try result.validate(level: .exact, tolerance: .standard)
        #expect(result.loops.values.flatMap(\.coedges).contains {
            if case let .bSpline(curve) = $0.surfaceParameterCurve {
                return curve.degree == 2 && curve.isRational
            }
            return false
        })
    }

    private func rectangularSolid() throws -> BRepModel {
        let profileFeatureID = FeatureID()
        let extrudeFeatureID = FeatureID()
        let profile = Profile(
            sourceFeatureID: profileFeatureID,
            plane: .xy,
            vertices: [
                Point3D(x: 0.0, y: 0.0, z: 0.0),
                Point3D(x: 0.040, y: 0.0, z: 0.0),
                Point3D(x: 0.040, y: 0.020, z: 0.0),
                Point3D(x: 0.0, y: 0.020, z: 0.0),
            ]
        )
        let feature = FeatureNode(
            id: extrudeFeatureID,
            operation: .extrude(ExtrudeFeature(
                profile: ProfileReference(featureID: profileFeatureID),
                distance: .constant(.length(0.010, unit: .meter))
            )),
            inputs: [FeatureInput(featureID: profileFeatureID, role: .profile)],
            outputs: [FeatureOutput(role: .body)]
        )
        return try PlanarExtrudeFeatureEvaluator().evaluate(
            feature: feature,
            context: EvaluationContext(
                parameters: ResolvedParameterTable(),
                brep: BRepModel(),
                profiles: [profileFeatureID: [profile]],
                tolerance: .standard
            )
        ).brep
    }

}
