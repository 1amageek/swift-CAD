import Foundation
import Testing
import CADCore
import CADGeometry
import CADIR
import CADModeling
import CADTopology
import CADKernel
@testable import CADExchange

@Suite("Exact STEP exchange")
struct ExactSTEPExchangeTests {
    @Test(.timeLimit(.minutes(1)))
    func rejectsInvalidExplicitToleranceBeforeImport() {
        let exchange = STEPExchange(tolerance: ModelingTolerance(distance: 0.0, angle: 1.0e-9))

        #expect(throws: GeometryError.self) {
            _ = try exchange.import(Data())
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func exportsPlanarSheetAsExactTopologyWithoutTriangles() throws {
        let sink = DataByteSink()
        try STEPExchange(tolerance: .standard).write(brep: try planarSheet(), units: .millimeters, to: sink)
        let text = try #require(String(data: sink.bytes, encoding: .utf8))
        #expect(text.contains("ADVANCED_FACE"))
        #expect(text.contains("EDGE_CURVE"))
        #expect(text.contains("SURFACE_CURVE"))
        #expect(text.contains("PCURVE"))
        #expect(text.contains("DEFINITIONAL_REPRESENTATION"))
        #expect(text.contains("OPEN_SHELL"))
        #expect(text.contains("SHELL_BASED_SURFACE_MODEL"))
        #expect(text.contains("SI_UNIT(.MILLI.,.METRE.)"))
        #expect(text.contains("TRIANGULATED_FACE_SET") == false)
    }

    @Test(.timeLimit(.minutes(1)))
    func enforcesOutputEntityLimit() throws {
        let exchange = STEPExchange(tolerance: .standard, resourceLimits: ExchangeResourceLimits(
            maximumBytes: 1_000_000,
            maximumEntities: 10,
            maximumNesting: 32,
            maximumIterations: 10_000
        ))
        do {
            try exchange.write(brep: try planarSheet(), to: DataByteSink())
            Issue.record("STEP writer must enforce its entity limit.")
        } catch let error as KernelError {
            #expect(error.code == .resourceLimitExceeded)
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func roundTripsExactPlanarTopologyUnitsAndOrientation() throws {
        let source = try planarSheet()
        let sink = DataByteSink()
        try STEPExchange(tolerance: .standard).write(brep: source, units: .millimeters, to: sink)

        let imported = try STEPExchange(tolerance: .standard).import(sink.bytes)
        let result = try #require(imported.brep)
        try result.validate(level: .exact, tolerance: .standard)

        #expect(imported.meshes.isEmpty)
        #expect(imported.units == UnitSystem(length: .millimeter, angle: .radian))
        #expect(result.bodies.count == source.bodies.count)
        #expect(result.shells.count == source.shells.count)
        #expect(result.faces.count == source.faces.count)
        #expect(result.loops.count == source.loops.count)
        #expect(result.edges.count == source.edges.count)
        #expect(result.vertices.count == source.vertices.count)
        #expect(result.bodies.values.allSatisfy { $0.kind == .sheet })
        #expect(result.faces.values.allSatisfy { $0.orientation == .forward })

        let sourcePoints = source.vertices.values.map(\.point).sorted(by: pointOrder)
        let resultPoints = result.vertices.values.map(\.point).sorted(by: pointOrder)
        #expect(resultPoints == sourcePoints)
    }

    @Test(.timeLimit(.minutes(1)))
    func roundTripsExactPlanarTopologyInConversionBasedLengthUnits() throws {
        let source = try planarSheet()
        for unit in [LengthUnit.inch, .foot] {
            let sink = DataByteSink()
            try STEPExchange(tolerance: .standard).write(
                brep: source,
                units: UnitSystem(length: unit, angle: .radian),
                to: sink
            )
            let text = try #require(String(data: sink.bytes, encoding: .utf8))
            let unitName = unit == .inch ? "INCH" : "FOOT"
            let conversionFactor = String(
                format: "%.17g",
                locale: Locale(identifier: "en_US_POSIX"),
                unit.metersPerUnit
            )
            let uncertainty = String(
                format: "%.17g",
                locale: Locale(identifier: "en_US_POSIX"),
                unit.fromInternal(ModelingTolerance.standard.distance)
            )
            #expect(text.contains("CONVERSION_BASED_UNIT('\(unitName)',"))
            #expect(text.contains("LENGTH_MEASURE_WITH_UNIT(LENGTH_MEASURE(\(conversionFactor)),"))
            #expect(text.contains("UNCERTAINTY_MEASURE_WITH_UNIT(LENGTH_MEASURE(\(uncertainty)),"))

            let imported = try STEPExchange(tolerance: .standard).import(sink.bytes)
            let result = try #require(imported.brep)
            try result.validate(level: .exact, tolerance: .standard)
            #expect(imported.meshes.isEmpty)
            #expect(imported.units == UnitSystem(length: unit, angle: .radian))
            #expect(result.bodies.count == source.bodies.count)
            #expect(result.shells.count == source.shells.count)
            #expect(result.faces.count == source.faces.count)
            #expect(result.edges.count == source.edges.count)
            #expect(result.vertices.count == source.vertices.count)

            let sourcePoints = source.vertices.values.map(\.point).sorted(by: pointOrder)
            let resultPoints = result.vertices.values.map(\.point).sorted(by: pointOrder)
            for (sourcePoint, resultPoint) in zip(sourcePoints, resultPoints) {
                #expect(resultPoint.isApproximatelyEqual(to: sourcePoint, tolerance: 1.0e-12))
            }
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func roundTripsPolylinePcurvesExactlyThroughSTEPAndIGES() throws {
        let source = try ExactExchangePolylinePcurveFixture.sheet()
        let sourcePolyline = try #require(source.loops.values
            .flatMap(\.coedges)
            .compactMap(\.surfaceParameterCurve)
            .first { curve in
                if case .polyline = curve { return true }
                return false
            })
        guard case let .polyline(sourcePoints) = sourcePolyline else {
            Issue.record("The exact fixture must contain a polyline p-curve.")
            return
        }

        let stepSink = DataByteSink()
        try STEPExchange(tolerance: .standard).write(
            brep: source,
            units: .millimeters,
            to: stepSink
        )
        let stepText = try #require(String(data: stepSink.bytes, encoding: .utf8))
        #expect(stepText.contains("B_SPLINE_CURVE_WITH_KNOTS"))
        let stepResult = try #require(
            STEPExchange(tolerance: .standard).import(stepSink.bytes).brep
        )

        let igesSink = DataByteSink()
        try IGESExchange(tolerance: .standard).write(
            brep: source,
            units: .millimeters,
            to: igesSink
        )
        let igesText = try #require(String(data: igesSink.bytes, encoding: .utf8))
        #expect(igesText.contains("PCNURBS"))
        let igesResult = try #require(
            IGESExchange(tolerance: .standard).import(igesSink.bytes).brep
        )

        for result in [stepResult, igesResult] {
            try result.validate(level: .exact, tolerance: .standard)
            let spline = try #require(result.loops.values
                .flatMap(\.coedges)
                .compactMap(\.surfaceParameterCurve)
                .compactMap { curve -> BSplineCurve2D? in
                    guard case let .bSpline(spline) = curve,
                          spline.degree == 1,
                          spline.controlPointCount == sourcePoints.count else {
                        return nil
                    }
                    return spline
                }
                .first)
            #expect(spline.knots == [0.0, 0.0, 1.0, 2.0, 2.0])
            #expect(spline.weights == [1.0, 1.0, 1.0])
            for (sourcePoint, resultPoint) in zip(sourcePoints, spline.controlPoints) {
                #expect(abs(sourcePoint.u - resultPoint.x) <= 1.0e-12)
                #expect(abs(sourcePoint.v - resultPoint.y) <= 1.0e-12)
            }
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func assignsDeterministicTopologyIdentifiersDuringImport() throws {
        let sink = DataByteSink()
        try STEPExchange(tolerance: .standard).write(brep: try planarSheet(), units: .millimeters, to: sink)

        let first = try #require(STEPExchange(tolerance: .standard).import(sink.bytes).brep)
        let second = try #require(STEPExchange(tolerance: .standard).import(sink.bytes).brep)
        #expect(first == second)
    }

    @Test(.timeLimit(.minutes(1)))
    func rejectsPcurveThatDisagreesWithItsThreeDimensionalCurve() throws {
        let sink = DataByteSink()
        try STEPExchange(tolerance: .standard).write(brep: try planarSheet(), units: .millimeters, to: sink)
        let text = try #require(String(data: sink.bytes, encoding: .utf8))
        let tampered = text.replacingOccurrences(
            of: "CARTESIAN_POINT('',(0,0))",
            with: "CARTESIAN_POINT('',(10,10))",
            options: [],
            range: text.range(of: "CARTESIAN_POINT('',(0,0))")
        )
        #expect(throws: ImportError.self) {
            _ = try STEPExchange(tolerance: .standard).import(Data(tampered.utf8))
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func roundTripsWatertightSolidAndExactVolume() throws {
        let source = try rectangularSolid()
        let sourceVolume = try source.volume(tolerance: .standard)
        let sink = DataByteSink()
        try STEPExchange(tolerance: .standard).write(brep: source, units: .millimeters, to: sink)
        let text = try #require(String(data: sink.bytes, encoding: .utf8))
        #expect(text.contains("CLOSED_SHELL"))
        #expect(text.contains("MANIFOLD_SOLID_BREP"))

        let result = try #require(STEPExchange(tolerance: .standard).import(sink.bytes).brep)
        try result.validate(level: .volumetric, tolerance: .standard)
        #expect(result.bodies.values.allSatisfy { $0.kind == .solid })
        #expect(abs(try result.volume(tolerance: .standard) - sourceVolume) <= 1.0e-12)
        #expect(result.faces.count == 6)
        #expect(result.edges.count == 12)
        #expect(result.vertices.count == 8)
    }

    @Test(.timeLimit(.minutes(1)))
    func roundTripsSolidVoidShellTopologyAndVolume() throws {
        let source = try ExactExchangeVoidFixture.rectangularCavitySolid()
        let sourceVolume = try source.volume(tolerance: .standard)
        let sink = DataByteSink()
        try STEPExchange(tolerance: .standard).write(
            brep: source,
            units: .millimeters,
            to: sink
        )
        let text = try #require(String(data: sink.bytes, encoding: .utf8))
        #expect(text.contains("BREP_WITH_VOIDS"))
        #expect(text.contains("ORIENTED_CLOSED_SHELL('',*,"))

        let imported = try STEPExchange(tolerance: .standard).import(sink.bytes)
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
    func exportsEachDisconnectedSolidComponentWithoutLosingVoidOwnership() throws {
        let source = try ExactExchangeVoidFixture.disconnectedSolidWithCavity()
        let sink = DataByteSink()
        try STEPExchange(tolerance: .standard).write(
            brep: source,
            units: .millimeters,
            to: sink
        )
        let text = try #require(String(data: sink.bytes, encoding: .utf8))
        #expect(text.components(separatedBy: "BREP_WITH_VOIDS").count - 1 == 1)
        #expect(text.components(separatedBy: "MANIFOLD_SOLID_BREP").count - 1 == 1)

        let imported = try STEPExchange(tolerance: .standard).import(sink.bytes)
        let result = try #require(imported.brep)
        #expect(result.bodies.count == 2)
        #expect(result.bodies.values.map(\.shellIDs.count).sorted() == [1, 2])
        #expect(abs(try result.volume(tolerance: .standard) - source.volume(tolerance: .standard)) <= 1.0e-12)
    }

    @Test(.timeLimit(.minutes(1)))
    func roundTripsRationalBSplineCurveSurfaceAndPcurves() throws {
        let source = try ExactExchangeNURBSFixture.rationalSheet()
        let sink = DataByteSink()
        try STEPExchange(tolerance: .standard).write(brep: source, units: .millimeters, to: sink)

        let result = try #require(STEPExchange(tolerance: .standard).import(sink.bytes).brep)
        try result.validate(level: .exact, tolerance: .standard)

        let sourceSurface = try #require(source.geometry.surfaces.values.first)
        let resultSurface = try #require(result.geometry.surfaces.values.first)
        guard case let .bSpline(sourceSpline) = sourceSurface,
              case let .bSpline(resultSpline) = resultSurface else {
            Issue.record("STEP rational B-spline surface was not preserved.")
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
        try STEPExchange(tolerance: .standard).write(brep: source, units: .millimeters, to: sink)
        let text = try #require(String(data: sink.bytes, encoding: .utf8))
        #expect(text.contains("EDGE_CURVE"))
        #expect(text.contains(",.F.);"))

        let result = try #require(STEPExchange(tolerance: .standard).import(sink.bytes).brep)
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
            try STEPExchange(tolerance: .standard).write(
                brep: source,
                units: .millimeters,
                to: sink
            )
            let text = try #require(String(data: sink.bytes, encoding: .utf8))
            #expect(text.contains("TRIMMED_CURVE('SWIFTCAD_BSPLINE_TRIM'"))

            let result = try #require(
                STEPExchange(tolerance: .standard).import(sink.bytes).brep
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
                Issue.record("STEP partial edge did not preserve its B-spline basis domain.")
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
        try STEPExchange(tolerance: .standard).write(brep: source, units: .millimeters, to: sink)

        let result = try #require(STEPExchange(tolerance: .standard).import(sink.bytes).brep)
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
            try ExactExchangeAnalyticFixture.periodicTranslatedCylindricalSheet(),
            try ExactExchangeAdvancedAnalyticFixture.seamCrossingEllipticalSheet(),
        ]
        for source in fixtures {
            let sink = DataByteSink()
            try STEPExchange(tolerance: .standard).write(
                brep: source,
                units: .millimeters,
                to: sink
            )
            let result = try #require(
                STEPExchange(tolerance: .standard).import(sink.bytes).brep
            )
            try result.validate(level: .exact, tolerance: .standard)
            try ExactExchangePeriodicTrimAssertions.validate(source: source, result: result)
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
                try STEPExchange(tolerance: .standard).write(brep: fixture.model, units: .millimeters, to: sink)
                let result = try #require(STEPExchange(tolerance: .standard).import(sink.bytes).brep)
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
                    "STEP failed to preserve the \(fixture.kind) parameterization."
                )
            } catch {
                Issue.record("STEP \(fixture.kind) round-trip failed: \(error)")
            }
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func roundTripsEllipseWithExactHarmonicPcurve() throws {
        let source = try ExactExchangeAdvancedAnalyticFixture.ellipticalSheet()
        let sink = DataByteSink()
        try STEPExchange(tolerance: .standard).write(brep: source, units: .millimeters, to: sink)
        let text = try #require(String(data: sink.bytes, encoding: .utf8))
        #expect(text.contains("AXIS2_PLACEMENT_2D"))
        #expect(text.contains("ELLIPSE('SWIFTCAD_PCURVE'"))

        let result = try #require(STEPExchange(tolerance: .standard).import(sink.bytes).brep)
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
    func roundTripsOpenConicsWithExactGeometryTrimsAndPcurves() throws {
        for reversed in [false, true] {
            for fixture in [
                ("HYPERBOLA", try ExactExchangeAdvancedAnalyticFixture.hyperbolicSheet(
                    reversed: reversed
                )),
                ("PARABOLA", try ExactExchangeAdvancedAnalyticFixture.parabolicSheet(
                    reversed: reversed
                )),
            ] {
                let sink = DataByteSink()
                try STEPExchange(tolerance: .standard).write(
                    brep: fixture.1,
                    units: .millimeters,
                    to: sink
                )
                let text = try #require(String(data: sink.bytes, encoding: .utf8))
                #expect(text.contains("\(fixture.0)('SWIFTCAD_ANALYTIC'"))

                let result = try #require(
                    STEPExchange(tolerance: .standard).import(sink.bytes).brep
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
    func roundTripsConeHyperbolaThroughExactSurfaceAssociation() throws {
        for reversed in [false, true] {
            let source = try ExactExchangeAdvancedAnalyticFixture.coneHyperbolicSheet(
                reversed: reversed
            )
            let sink = DataByteSink()
            try STEPExchange(tolerance: .standard).write(
                brep: source,
                units: .millimeters,
                to: sink
            )
            let text = try #require(String(data: sink.bytes, encoding: .utf8))
            #expect(text.contains("HYPERBOLA('SWIFTCAD_ANALYTIC'"))
            #expect(text.contains(".CURVE_3D."))
            #expect(text.contains("TRIANGULATED_FACE_SET") == false)

            let result = try #require(
                STEPExchange(tolerance: .standard).import(sink.bytes).brep
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
    func roundTripsSphericalGreatCircleThroughExactSurfaceAssociation() throws {
        for reversed in [false, true] {
            let source = try ExactExchangeAdvancedAnalyticFixture.greatCircleHemisphere(
                reversed: reversed
            )
            let sink = DataByteSink()
            try STEPExchange(tolerance: .standard).write(
                brep: source,
                units: .millimeters,
                to: sink
            )
            let text = try #require(String(data: sink.bytes, encoding: .utf8))
            #expect(text.contains(".CURVE_3D."))
            #expect(text.contains("SPHERICAL_SURFACE"))
            #expect(text.contains("TRIANGULATED_FACE_SET") == false)

            let result = try #require(
                STEPExchange(tolerance: .standard).import(sink.bytes).brep
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
    func roundTripsPlaneTorusIntersectionWithExactTwoSurfaceProvenance() throws {
        for reversed in [false, true] {
            let source = try ExactExchangeAdvancedAnalyticFixture.planeTorusIntersectionSheet(
                reversed: reversed
            )
            let sink = DataByteSink()
            try STEPExchange(tolerance: .standard).write(
                brep: source,
                units: .millimeters,
                to: sink
            )
            let text = try #require(String(data: sink.bytes, encoding: .utf8))
            #expect(text.contains("TOROIDAL_SURFACE('SWIFTCAD_ANALYTIC'"))
            #expect(text.contains(".CURVE_3D."))
            #expect(text.contains("TRIANGULATED_FACE_SET") == false)

            let result = try #require(
                STEPExchange(tolerance: .standard).import(sink.bytes).brep
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

    @Test(.timeLimit(.minutes(2)))
    func roundTripsCertifiedSphereConeIntersectionWithExactTwoSurfaceProvenance() throws {
        for reversed in [false, true] {
            try assertCertifiedSphereConeRoundTrip(
                source: ExactExchangeAdvancedAnalyticFixture
                    .certifiedSphereConeIntersectionSheet(reversed: reversed)
            )
        }
    }

    @Test(.timeLimit(.minutes(2)))
    func roundTripsRigidImageAsCanonicalCertifiedIntersection() throws {
        for reversed in [false, true] {
            try assertCertifiedSphereConeRoundTrip(
                source: ExactExchangeAdvancedAnalyticFixture
                    .rigidImageSphereConeIntersectionSheet(reversed: reversed)
            )
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func roundTripsCertifiedImplicitIntersectionWithExactSurfaceProvenance() throws {
        for reversed in [false, true] {
            let source = try ExactExchangeAdvancedAnalyticFixture.implicitBSplineIntersectionSheet(
                reversed: reversed
            )
            let sink = DataByteSink()
            try STEPExchange(tolerance: .standard).write(
                brep: source,
                units: .millimeters,
                to: sink
            )
            let text = try #require(String(data: sink.bytes, encoding: .utf8))
            #expect(text.contains("B_SPLINE_SURFACE_WITH_KNOTS"))
            #expect(text.contains(".CURVE_3D."))
            #expect(text.contains("TRIANGULATED_FACE_SET") == false)

            let result = try #require(
                STEPExchange(tolerance: .standard).import(sink.bytes).brep
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

    @Test(.timeLimit(.minutes(2)))
    func roundTripsCertifiedAnalyticBSplineIntersectionWithExactSurfaceProvenance() throws {
        try assertCertifiedAnalyticBSplineIntersectionRoundTrip(reversed: false)
    }

    @Test(.timeLimit(.minutes(2)))
    func roundTripsReversedCertifiedAnalyticBSplineIntersectionWithExactSurfaceProvenance() throws {
        try assertCertifiedAnalyticBSplineIntersectionRoundTrip(reversed: true)
    }

    @Test(.timeLimit(.minutes(2)))
    func roundTripsSurfaceLiftAsPcurveMasterWithoutChangingCanonicalTruth() throws {
        for reversed in [false, true] {
            let source = try ExactExchangeAdvancedAnalyticFixture.surfaceLiftSheet(
                reversed: reversed
            )
            let sink = DataByteSink()
            try STEPExchange(tolerance: .standard).write(
                brep: source,
                units: .millimeters,
                to: sink
            )
            let text = try #require(String(data: sink.bytes, encoding: .utf8))
            #expect(text.contains("SWIFTCAD_SURFACE_LIFT"))
            #expect(text.contains(".PCURVE_S1."))
            #expect(text.contains("TRIANGULATED_FACE_SET") == false)

            let result = try #require(
                STEPExchange(tolerance: .standard).import(sink.bytes).brep
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
        try STEPExchange(tolerance: .standard).write(brep: source, units: .millimeters, to: sink)
        let result = try #require(STEPExchange(tolerance: .standard).import(sink.bytes).brep)
        try result.validate(level: .exact, tolerance: .standard)
        #expect(result.loops.values.flatMap(\.coedges).contains {
            if case let .bSpline(curve) = $0.surfaceParameterCurve {
                return curve.degree == 2 && curve.isRational
            }
            return false
        })
    }

    @Test(.timeLimit(.minutes(1)))
    func roundTripsGeneralOffsetSurfaceWithPreservedChart() throws {
        let source = try ExactExchangeNURBSFixture.offsetRationalSheet()
        let sink = DataByteSink()
        try STEPExchange(tolerance: .standard).write(
            brep: source,
            units: .millimeters,
            to: sink
        )
        let text = try #require(String(data: sink.bytes, encoding: .utf8))
        #expect(text.contains("OFFSET_SURFACE('SWIFTCAD_OFFSET'"))
        #expect(text.contains("TRIANGULATED_FACE_SET") == false)

        let result = try #require(
            STEPExchange(tolerance: .standard).import(sink.bytes).brep
        )
        try result.validate(level: .exact, tolerance: .standard)
        let imported = try #require(result.geometry.surfaces.values.first { surface in
            if case .procedural(.offset) = surface { return true }
            return false
        })
        guard case let .procedural(.offset(offset)) = imported else {
            Issue.record("STEP must reconstruct an exact procedural offset surface.")
            return
        }
        #expect(abs(offset.distance - 0.003) <= 1.0e-12)
        #expect({ if case .bSpline = offset.source { return true }; return false }())
        #expect(result.geometry.curves.values.allSatisfy { curve in
            if case .surfaceLift = curve { return true }
            return false
        })
    }

    private func assertCertifiedAnalyticBSplineIntersectionRoundTrip(
        reversed: Bool
    ) throws {
        let source = try ExactExchangeAdvancedAnalyticFixture.analyticBSplineIntersectionSheet(
            reversed: reversed
        )
        let sink = DataByteSink()
        try STEPExchange(tolerance: .standard).write(
            brep: source,
            units: .millimeters,
            to: sink
        )
        let text = try #require(String(data: sink.bytes, encoding: .utf8))
        #expect(text.contains("SPHERICAL_SURFACE"))
        #expect(text.contains("B_SPLINE_SURFACE_WITH_KNOTS"))
        #expect(text.contains(".CURVE_3D."))
        #expect(text.contains("TRIANGULATED_FACE_SET") == false)

        let result = try #require(
            STEPExchange(tolerance: .standard).import(sink.bytes).brep
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

    private func assertCertifiedSphereConeRoundTrip(source: BRepModel) throws {
        let sink = DataByteSink()
        try STEPExchange(tolerance: .standard).write(
            brep: source,
            units: .millimeters,
            to: sink
        )
        let text = try #require(String(data: sink.bytes, encoding: .utf8))
        #expect(text.contains("SWIFTCAD_CERTIFIED_CURVE"))
        #expect(text.contains("SPHERICAL_SURFACE"))
        #expect(text.contains("CONICAL_SURFACE"))
        #expect(text.contains("TRIANGULATED_FACE_SET") == false)

        let result = try #require(
            STEPExchange(tolerance: .standard).import(sink.bytes).brep
        )
        try result.validate(level: .exact, tolerance: .standard)
        #expect(result.geometry.curves.values.allSatisfy { curve in
            if case .certifiedIntersection(.sphereCone) = curve { return true }
            return false
        })
        #expect(result.loops.values.flatMap(\.coedges).allSatisfy { coedge in
            if case .certifiedAnalyticPair = coedge.surfaceParameterCurve { return true }
            return false
        })
    }

    private func planarSheet() throws -> BRepModel {
        let points = [
            Point3D(x: 0.0, y: 0.0, z: 0.0),
            Point3D(x: 0.040, y: 0.0, z: 0.0),
            Point3D(x: 0.040, y: 0.020, z: 0.0),
            Point3D(x: 0.0, y: 0.020, z: 0.0),
        ]
        let surface = Surface3D.plane(Plane3D(origin: .origin, normal: .unitZ))
        let edges = try points.indices.map { index in
            let start = points[index]
            let end = points[(index + 1) % points.count]
            let delta = end - start
            let startUV = try surface.parameterProjection(of: start, tolerance: .standard)
            let endUV = try surface.parameterProjection(of: end, tolerance: .standard)
            return BRepSewingEdge(
                stableID: "step:edge:\(index)",
                curve: .line(Line3D(origin: start, direction: try delta.normalized(tolerance: 1.0e-9))),
                startParameter: 0.0,
                endParameter: delta.length,
                startPoint: start,
                endPoint: end,
                surfaceParameterCurve: .polyline([
                    SurfaceParameter(u: startUV.u, v: startUV.v),
                    SurfaceParameter(u: endUV.u, v: endUV.v),
                ])
            )
        }
        return try DefaultBRepSewer().sew(BRepSewingRequest(
            featureID: FeatureID(),
            bodyKind: .sheet,
            shells: [BRepSewingShell(
                stableID: "step:shell",
                patches: [BRepSewingFacePatch(
                    stableID: "step:face",
                    surface: surface,
                    orientation: .forward,
                    loops: [BRepSewingLoop(stableID: "step:outer", role: .outer, edges: edges)]
                )]
            )]
        ), tolerance: .standard).brep
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
        return try PlanarExtrudeFeatureEvaluator(sewer: DefaultBRepSewer()).evaluate(
            feature: feature,
            context: EvaluationContext(
                parameters: ResolvedParameterTable(),
                brep: BRepModel(),
                profiles: [profileFeatureID: [profile]],
                tolerance: .standard
            )
        ).brep
    }

    private func pointOrder(_ lhs: Point3D, _ rhs: Point3D) -> Bool {
        if lhs.x != rhs.x { return lhs.x < rhs.x }
        if lhs.y != rhs.y { return lhs.y < rhs.y }
        return lhs.z < rhs.z
    }
}
