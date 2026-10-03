import Foundation
import Testing
import CADCore
import CADExchange
import CADGeometry
import CADIR
import CADTopology
@testable import CADKernel
@testable import SwiftCAD

/// Square framed by fewer than four curves: two apart ruled between, two at a corner completed by
/// their translated copies, three closed by a straight side — each side kept exactly, the sides
/// without a curve left to the fairness — and the options' round trip.
@Suite("Square frames")
struct SquareFrameTests {
    private func length(_ value: Double) -> CADExpression { .constant(.length(value, unit: .meter)) }
    private func point(_ x: Double, _ y: Double) -> SketchPoint { SketchPoint(x: length(x), y: length(y)) }

    private func line(_ builder: inout DocumentBuilder, _ start: SketchPoint, _ end: SketchPoint, height: Double = 0) throws -> FeatureID {
        let plane: SketchPlane = height == 0 ? .xy : .plane(Plane3D(origin: Point3D(x: 0, y: 0, z: height), normal: .unitZ))
        return try builder.sketch(on: plane) { _ = $0.line(from: start, to: end) }.featureID
    }

    private func sheet(_ builder: DocumentBuilder, _ square: FeatureID) throws -> BSplineSurface3D {
        let evaluated = try DocumentEvaluator(tolerance: .standard, artifactPolicy: .deferred).evaluate(try builder.build(name: "square"))
        try evaluated.brep.validate(tolerance: .standard)
        let surface = try #require(evaluated.subshapes.entries.compactMap { key, value -> Surface3D? in
            guard key.featureID == square, case let .face(id) = value, let face = evaluated.brep.faces[id] else { return nil }
            return evaluated.brep.geometry.surfaces[face.surfaceID]
        }.first)
        guard case let .bSpline(spline) = surface else {
            throw KernelError(phase: .evaluation, code: .invalidInput, tolerance: nil, message: "A Square is a B-spline sheet.")
        }
        return spline
    }

    private func natural() -> SquareFitOptions { SquareFitOptions(boundaryFlow: .natural) }

    @Test(.timeLimit(.minutes(2)))
    func twoLinesApartAreRuledFlat() throws {
        var builder = DocumentBuilder(units: .meters, tolerance: .standard)
        let low = try line(&builder, point(0, 0), point(0.02, 0))
        // Drawn the other way, 10 mm higher: the connectors pair the nearest ends.
        let high = try line(&builder, point(0, 0.02), point(0.02, 0.02), height: 0.01)
        let square = try builder.square(sides: [low, high].map { SquareSide(curve: CurveSectionReference(featureID: $0)) }, options: natural())
        let spline = try sheet(builder, square)
        // The plane through both lines, z = y / 2, bends nothing: the fair sheet is it.
        #expect(spline.controlPoints.joined().allSatisfy { abs($0.z - $0.y / 2) < 1e-9 })
        let corners = try [(0.0, 0.0), (1.0, 0.0), (0.0, 1.0), (1.0, 1.0)].map { try spline.point(u: $0.0, v: $0.1, tolerance: .standard) }
        #expect(Set(corners.map { "\(Int(($0.x * 1e6).rounded())),\(Int(($0.y * 1e6).rounded()))" }) == ["0,0", "20000,0", "0,20000", "20000,20000"])
    }

    @Test(.timeLimit(.minutes(2)))
    func twoLinesAtACornerSpanTheirParallelogram() throws {
        var builder = DocumentBuilder(units: .meters, tolerance: .standard)
        let first = try line(&builder, point(0, 0), point(0.02, 0))
        let second = try line(&builder, point(0.01, 0.02), point(0, 0))
        let square = try builder.square(sides: [first, second].map { SquareSide(curve: CurveSectionReference(featureID: $0)) }, options: natural())
        let spline = try sheet(builder, square)
        let corners = try [(0.0, 0.0), (1.0, 0.0), (0.0, 1.0), (1.0, 1.0)].map { try spline.point(u: $0.0, v: $0.1, tolerance: .standard) }
        // The far corner is the first's end translated along the second.
        #expect(corners.contains { abs($0.x - 0.03) < 1e-9 && abs($0.y - 0.02) < 1e-9 && abs($0.z) < 1e-12 })
        #expect(spline.controlPoints.joined().allSatisfy { abs($0.z) < 1e-12 })
    }

    @Test(.timeLimit(.minutes(2)))
    func threeLinesAreClosedByAStraightSide() throws {
        var builder = DocumentBuilder(units: .meters, tolerance: .standard)
        let lines = try [(point(0, 0), point(0.02, 0)), (point(0.02, 0), point(0.02, 0.02)), (point(0.02, 0.02), point(0, 0.03))].map {
            try line(&builder, $0.0, $0.1)
        }
        let square = try builder.square(sides: lines.map { SquareSide(curve: CurveSectionReference(featureID: $0)) }, options: natural())
        let spline = try sheet(builder, square)
        let corners = try [(0.0, 0.0), (1.0, 0.0), (0.0, 1.0), (1.0, 1.0)].map { try spline.point(u: $0.0, v: $0.1, tolerance: .standard) }
        #expect(Set(corners.map { "\(Int(($0.x * 1e6).rounded())),\(Int(($0.y * 1e6).rounded()))" }) == ["0,0", "20000,0", "20000,20000", "0,30000"])
        #expect(spline.controlPoints.joined().allSatisfy { abs($0.z) < 1e-12 })
    }

    @Test(.timeLimit(.minutes(1)))
    func optionsAndFreeSidesRoundTrip() throws {
        let feature = SquareSurfaceFeature(
            sides: [SquareSide(curve: CurveSectionReference(featureID: FeatureID()), isFree: true),
                    SquareSide(curve: CurveSectionReference(featureID: FeatureID()))],
            options: SquareFitOptions(uDegree: 5, vDegree: 4, uSpans: 2, vSpans: 1, flatness: 0.97, weight: 3, boundaryFlow: .next)
        )
        let decoded = try JSONDecoder().decode(SquareSurfaceFeature.self, from: try JSONEncoder().encode(feature))
        #expect(decoded == feature)
        // Flatness 0 is the membrane alone, as Plasticity accepts it; past 1 is refused.
        try SquareFitOptions(flatness: 0).validate()
        #expect(throws: (any Error).self) {
            try SquareFitOptions(flatness: 1.01).validate()
        }
    }

    @Test(.timeLimit(.minutes(2)))
    func aMembraneSquareAtFlatnessZeroSpansItsFrame() throws {
        // Four lines of a planar quadrilateral, Flatness 0: the membrane fit spans the frame flat.
        var builder = DocumentBuilder(units: .meters, tolerance: .standard)
        let lines = try [(point(0, 0), point(0.02, 0)), (point(0.02, 0), point(0.02, 0.02)), (point(0.02, 0.02), point(0, 0.03)),
                         (point(0, 0.03), point(0, 0))].map {
            try line(&builder, $0.0, $0.1)
        }
        var options = natural()
        options.flatness = 0
        let square = try builder.square(sides: lines.map { SquareSide(curve: CurveSectionReference(featureID: $0)) }, options: options)
        let spline = try sheet(builder, square)
        #expect(spline.controlPoints.joined().allSatisfy { abs($0.z) < 1e-12 })
    }
}

extension SquareFrameTests {
    @Test(.timeLimit(.minutes(2)))
    func aFreeSideReportsItsDeviation() throws {
        var builder = DocumentBuilder(units: .meters, tolerance: .standard)
        let bottom = try line(&builder, point(0, 0), point(0.02, 0))
        let right = try line(&builder, point(0.02, 0), point(0.02, 0.02))
        let top = try line(&builder, point(0.02, 0.02), point(0, 0.02))
        // A left side bowing out of the others' plane, followed loosely.
        let left = try builder.sketch(on: .plane(Plane3D(origin: .origin, normal: .unitX))) { sketch in
            _ = sketch.spline(SketchSpline(controlPoints: [point(0.02, 0), point(0.013, 0.006), point(0.007, 0.006), point(0, 0)]))
        }.featureID
        let square = try builder.square(sides: [
            SquareSide(curve: CurveSectionReference(featureID: bottom)), SquareSide(curve: CurveSectionReference(featureID: right)),
            SquareSide(curve: CurveSectionReference(featureID: top)), SquareSide(curve: CurveSectionReference(featureID: left), isFree: true)
        ], options: SquareFitOptions(weight: 0.01, boundaryFlow: .natural))
        let evaluated = try DocumentEvaluator(tolerance: .standard, artifactPolicy: .deferred).evaluate(try builder.build(name: "square"))
        let analysis = try SquareSideAnalyzer().analyze(square, in: evaluated)
        #expect(analysis[0...2].allSatisfy { $0.position < 1e-9 })
        #expect(analysis[3].position > 1e-5)
        #expect(analysis[3].isWithin == false)
        // Each side's Analysis is shown at the middle of its curve: the bottom's at (10, 0) mm.
        let bottomMiddle = try #require(analysis[0].point)
        #expect((bottomMiddle - Point3D(x: 0.01, y: 0, z: 0)).length < 1e-9)
        #expect(analysis.allSatisfy { $0.point != nil })
    }
}
