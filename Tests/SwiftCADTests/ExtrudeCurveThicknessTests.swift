import Foundation
import Testing
import CADCore
import CADGeometry
import CADIR
import CADTopology
@testable import CADKernel
@testable import SwiftCAD

/// A thin curve extrusion: the curve's sheet thickened into a solid wall on the curve's left about
/// the extrusion — a line's slab beside it, a circle's ring inside it.
@Suite("Extrude curve thickness")
struct ExtrudeCurveThicknessTests {
    private func length(_ value: Double) -> CADExpression { .constant(.length(value, unit: .meter)) }
    private func point(_ x: Double, _ y: Double) -> SketchPoint { SketchPoint(x: length(x), y: length(y)) }

    private func solid(_ feature: FeatureID, in builder: DocumentBuilder) throws -> (volume: Double, points: [Point3D]) {
        let evaluated = try DocumentEvaluator(tolerance: .standard, artifactPolicy: .deferred).evaluate(try builder.build(name: "thin"))
        try evaluated.brep.validate(level: .volumetric, tolerance: .standard)
        let bodyID = try #require(evaluated.subshapes.entries.compactMap { key, value -> BodyID? in
            guard key.featureID == feature, case let .body(id) = value else { return nil }
            return id
        }.first)
        let scope = try BodyTopologyScope(bodyID: bodyID, model: evaluated.brep)
        let points = scope.references.compactMap { reference -> Point3D? in
            guard case let .vertex(id) = reference else { return nil }
            return evaluated.brep.vertices[id]?.point
        }
        return (try evaluated.brep.volume(of: bodyID, tolerance: .standard), points)
    }

    @Test(.timeLimit(.minutes(2)))
    func aLineIsThickenedIntoASlabOnItsLeft() throws {
        var builder = DocumentBuilder(units: .meters, tolerance: .standard)
        let line = try builder.sketch(on: .xy) { $0.line(from: point(0, 0), to: point(0.02, 0)) }.featureID
        let wall = try builder.extrude(curve: CurveSectionReference(featureID: line), distance: length(0.01), thickness: length(0.002))
        let (volume, points) = try solid(wall, in: builder)
        #expect(abs(volume - 0.02 * 0.002 * 0.01) < 1e-12)
        #expect(points.allSatisfy { $0.y > -1e-12 && $0.y < 0.002 + 1e-12 })
    }

    @Test(.timeLimit(.minutes(2)))
    func aCircleIsThickenedIntoARingInsideIt() throws {
        var builder = DocumentBuilder(units: .meters, tolerance: .standard)
        let circle = try builder.sketch(on: .xy) { $0.circle(center: point(0, 0), radius: length(0.01)) }.featureID
        let ring = try builder.extrude(curve: CurveSectionReference(featureID: circle), distance: length(0.005), thickness: length(0.001))
        let (volume, points) = try solid(ring, in: builder)
        #expect(abs(volume - Double.pi * (0.01 * 0.01 - 0.009 * 0.009) * 0.005) < 1e-12)
        #expect(points.allSatisfy { Vector3D(x: $0.x, y: $0.y, z: 0).length < 0.01 + 1e-9 })
    }
}

/// Drafted curve sheets lean by the draft toward the curve's left; closed splines draft and thin
/// through their region.
@Suite("Extrude curve draft")
struct ExtrudeCurveDraftTests {
    private func length(_ value: Double) -> CADExpression { .constant(.length(value, unit: .meter)) }
    private func point(_ x: Double, _ y: Double) -> SketchPoint { SketchPoint(x: length(x), y: length(y)) }
    private let h = 0.01
    private let degrees = 10.0
    private var shift: Double { h * tan(degrees * Double.pi / 180) }

    private func evaluate(_ builder: DocumentBuilder) throws -> EvaluatedDocument {
        let evaluated = try DocumentEvaluator(tolerance: .standard, artifactPolicy: .deferred).evaluate(try builder.build(name: "draft"))
        try evaluated.brep.validate(level: .exact, tolerance: .standard)
        return evaluated
    }

    private func vertices(_ feature: FeatureID, in evaluated: EvaluatedDocument) throws -> [Point3D] {
        let bodyID = try #require(evaluated.subshapes.entries.compactMap { key, value -> BodyID? in
            guard key.featureID == feature, case let .body(id) = value else { return nil }
            return id
        }.first)
        return try BodyTopologyScope(bodyID: bodyID, model: evaluated.brep).references.compactMap { reference -> Point3D? in
            guard case let .vertex(id) = reference else { return nil }
            return evaluated.brep.vertices[id]?.point
        }
    }

    private func drafted(_ curve: FeatureID, _ builder: inout DocumentBuilder) throws -> FeatureID {
        try builder.extrude(curve: CurveSectionReference(featureID: curve), distance: length(h),
                            draftAngle: .constant(.angle(degrees, unit: .degree)))
    }

    @Test(.timeLimit(.minutes(2)))
    func aDraftedLineLeansToItsLeft() throws {
        var builder = DocumentBuilder(units: .meters, tolerance: .standard)
        let line = try builder.sketch(on: .xy) { $0.line(from: point(0, 0), to: point(0.02, 0)) }.featureID
        let sheet = try drafted(line, &builder)
        let points = try vertices(sheet, in: try evaluate(builder))
        #expect(points.count == 4)
        #expect(points.filter { abs($0.z - h) < 1e-12 }.allSatisfy { abs($0.y - shift) < 1e-12 })
        #expect(points.filter { abs($0.z) < 1e-12 }.allSatisfy { abs($0.y) < 1e-12 })
    }

    @Test(.timeLimit(.minutes(2)))
    func aDraftedArcNarrowsTowardItsCentre() throws {
        var builder = DocumentBuilder(units: .meters, tolerance: .standard)
        let arc = try builder.sketch(on: .xy) { sketch in
            _ = sketch.arc(center: point(0, 0), radius: length(0.01), startAngle: .constant(.angle(0, unit: .degree)),
                           endAngle: .constant(.angle(90, unit: .degree)))
        }.featureID
        let sheet = try drafted(arc, &builder)
        let points = try vertices(sheet, in: try evaluate(builder))
        #expect(points.filter { abs($0.z - h) < 1e-12 }.allSatisfy { abs(Vector3D(x: $0.x, y: $0.y, z: 0).length - (0.01 - shift)) < 1e-12 })
    }

    @Test(.timeLimit(.minutes(2)))
    func aDraftedSplinesTopIsItsOffsetWithinAQuarterOfTheTolerance() throws {
        var builder = DocumentBuilder(units: .meters, tolerance: .standard)
        let controls: [(Double, Double)] = [(0, 0), (0.01, 0.01), (0.02, -0.005), (0.03, 0.002)]
        let spline = try builder.sketch(on: .xy) { $0.spline(SketchSpline(controlPoints: controls.map { point($0.0, $0.1) })) }.featureID
        let sheet = try drafted(spline, &builder)
        let evaluated = try evaluate(builder)
        let face = try #require(evaluated.subshapes.entries.compactMap { key, value -> Face? in
            guard key.featureID == sheet, case let .face(id) = value else { return nil }
            return evaluated.brep.faces[id]
        }.first)
        guard case let .bSpline(surface)? = evaluated.brep.geometry.surfaces[face.surfaceID] else {
            Issue.record("A drafted spline's sheet is a ruled B-spline.")
            return
        }
        let source = BSplineCurve3D(degree: 3, knots: [0, 0, 0, 0, 1, 1, 1, 1], controlPoints: controls.map { Point3D(x: $0.0, y: $0.1, z: 0) })
        for k in 0...40 {
            let t = Double(k) / 40
            let jet = try Curve3D.bSpline(source).differentialGeometry(at: t, tolerance: .standard)
            let left = try Vector3D(x: -jet.firstDerivative.y, y: jet.firstDerivative.x, z: 0).normalized(tolerance: 1e-12)
            let expected = jet.position + left * shift + Vector3D(x: 0, y: 0, z: h)
            let top = try surface.point(u: t, v: 1, tolerance: .standard)
            #expect((top - expected).length < 2.5e-7 + 1e-12)
        }
    }
}

extension ExtrudeCurveDraftTests {
    @Test(.timeLimit(.minutes(3)))
    func aClosedSplinesThinWallIsItsPerimetersRing() throws {
        var builder = DocumentBuilder(units: .meters, tolerance: .standard)
        // A convex closed spline around the origin, tangent where it closes.
        let controls: [(Double, Double)] = [(0.01, 0), (0.01, 0.007), (0.004, 0.011), (-0.006, 0.009), (-0.011, 0),
                                            (-0.006, -0.009), (0.004, -0.011), (0.01, -0.007), (0.01, 0)]
        let knots = [0, 0, 0, 0] + (1...5).map { Double($0) / 6 } + [1, 1, 1, 1]
        let loop = try builder.sketch(on: .xy) {
            $0.spline(SketchSpline(controlPoints: controls.map { point($0.0, $0.1) }, isClosed: true, knots: knots))
        }.featureID
        let t = 0.0005
        let wall = try builder.extrude(curve: CurveSectionReference(featureID: loop), distance: length(h), thickness: length(t))
        let evaluated = try DocumentEvaluator(tolerance: .standard, artifactPolicy: .deferred).evaluate(try builder.build(name: "loop"))
        try evaluated.brep.validate(level: .volumetric, tolerance: .standard)
        let curve = try #require(evaluated.curves[loop]?.first?.exactCurve)
        guard case let .closed(lower, upper)? = evaluated.curves[loop]?.first?.exactParameterDomain else {
            Issue.record("A closed spline is bounded.")
            return
        }
        var perimeter = 0.0
        for k in 0..<4000 {
            let (a, b) = (lower + (upper - lower) * Double(k) / 4000, lower + (upper - lower) * Double(k + 1) / 4000)
            perimeter += (try curve.point(at: b, tolerance: .standard) - curve.point(at: a, tolerance: .standard)).length
        }
        let bodyID = try #require(evaluated.subshapes.entries.compactMap { key, value -> BodyID? in
            guard key.featureID == wall, case let .body(id) = value else { return nil }
            return id
        }.first)
        let volume = try evaluated.brep.volume(of: bodyID, tolerance: .standard)
        #expect(abs(volume - (perimeter * t - Double.pi * t * t) * h) < 2e-10, "\(volume)")
    }
}
