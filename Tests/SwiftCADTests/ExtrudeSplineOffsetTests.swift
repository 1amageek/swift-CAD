import Foundation
import Testing
import CADCore
import CADGeometry
import CADIR
import CADTopology
@testable import CADKernel
@testable import SwiftCAD

/// Drafted and thin extrusions of a section with a spline, its offset approximated within a quarter
/// of the modeling distance: a convex D of a line and a spline meeting tangentially, whose drafted
/// solid and thin wall have Steiner's volumes, A·H − P·τ·H²/2 + π·τ²·H³/3 and (P·t − π·t²)·H.
@Suite("Extrude spline offset")
struct ExtrudeSplineOffsetTests {
    private func length(_ value: Double) -> CADExpression { .constant(.length(value, unit: .meter)) }
    private func point(_ x: Double, _ y: Double) -> SketchPoint { SketchPoint(x: length(x), y: length(y)) }

    private let controls: [(Double, Double)] = [(0.02, 0), (0.03, 0), (0.03, 0.02), (-0.01, 0.02), (-0.01, 0), (0, 0)]

    /// The D's area and perimeter: the line's and, by Gauss–Legendre on the spline, Green's
    /// integral and the arc length.
    private func areaAndPerimeter() throws -> (Double, Double) {
        let spline = BSplineCurve3D(degree: 3, knots: [0, 0, 0, 0, 1.0 / 3, 2.0 / 3, 1, 1, 1, 1],
                                    controlPoints: controls.map { Point3D(x: $0.0, y: $0.1, z: 0) })
        let nodes = [-0.9061798459386640, -0.5384693101056831, 0.0, 0.5384693101056831, 0.9061798459386640]
        let weights = [0.2369268850561891, 0.4786286704993665, 0.5688888888888889, 0.4786286704993665, 0.2369268850561891]
        var area = 0.0, perimeter = 0.02
        for span in 0..<300 {
            let (a, b) = (Double(span) / 300, Double(span + 1) / 300)
            for (x, w) in zip(nodes, weights) {
                let t = 0.5 * (a + b) + 0.5 * (b - a) * x
                let jet = try Curve3D.bSpline(spline).differentialGeometry(at: t, tolerance: .standard)
                let (p, d) = (jet.position, jet.firstDerivative)
                area += 0.5 * (p.x * d.y - p.y * d.x) * w * 0.5 * (b - a)
                perimeter += d.length * w * 0.5 * (b - a)
            }
        }
        return (area, perimeter)
    }

    private func profile(_ builder: inout DocumentBuilder) throws -> ProfileReference {
        try builder.sketch(on: .xy) { sketch in
            _ = sketch.line(from: point(0, 0), to: point(0.02, 0))
            _ = sketch.spline(SketchSpline(controlPoints: controls.map { point($0.0, $0.1) }, knots: [0, 0, 0, 0, 1.0 / 3, 2.0 / 3, 1, 1, 1, 1]))
        }
    }

    private func volume(_ feature: FeatureID, in builder: DocumentBuilder) throws -> Double {
        let evaluated = try DocumentEvaluator(tolerance: .standard, artifactPolicy: .deferred).evaluate(try builder.build(name: "spline"))
        try evaluated.brep.validate(level: .volumetric, tolerance: .standard)
        let bodyID = try #require(evaluated.subshapes.entries.compactMap { key, value -> BodyID? in
            guard key.featureID == feature, case let .body(id) = value else { return nil }
            return id
        }.first)
        return try evaluated.brep.volume(of: bodyID, tolerance: .standard)
    }

    @Test(.timeLimit(.minutes(3)))
    func aDraftedSplineSectionTapersBySteinersFormula() throws {
        var builder = DocumentBuilder(units: .meters, tolerance: .standard)
        let (h, degrees) = (0.01, 10.0)
        let extrusion = try builder.extrude(try profile(&builder), distance: length(h), draftAngle: .constant(.angle(degrees, unit: .degree)))
        let (area, perimeter) = try areaAndPerimeter()
        let tangent = tan(degrees * Double.pi / 180)
        let expected = area * h - perimeter * tangent * h * h / 2 + Double.pi * tangent * tangent * h * h * h / 3
        #expect(abs(try volume(extrusion, in: builder) - expected) < 1e-9)
    }

    @Test(.timeLimit(.minutes(3)))
    func aThinSplineSectionIsAWallOfItsPerimeter() throws {
        var builder = DocumentBuilder(units: .meters, tolerance: .standard)
        let (h, t) = (0.01, 0.001)
        let extrusion = try builder.extrude(try profile(&builder), distance: length(h), thickness: length(t))
        let (_, perimeter) = try areaAndPerimeter()
        #expect(abs(try volume(extrusion, in: builder) - (perimeter * t - Double.pi * t * t) * h) < 1e-9)
    }
}
