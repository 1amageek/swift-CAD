import CADCore
import Foundation
import Testing
@testable import CADKernel

/// The nearest point of a sketch curve, in the intersector's natural parameters.
@Suite("Sketch curve projector")
struct SketchCurveProjectorTests {
    private let projector = SketchCurveProjector(tolerance: .standard)
    private func point(_ x: Double, _ y: Double) -> Point2D { Point2D(x: x, y: y) }

    @Test func aLineProjectsInClosedFormAndClampsToItsEnds() throws {
        let line = SketchCurveGeometry2D.line(start: point(0, 0), end: point(4, 0))
        let middle = try projector.nearest(on: line, to: point(1, 3))
        #expect(abs(middle.parameter - 0.25) < 1e-15)
        #expect(abs(middle.distance - 3) < 1e-15)
        #expect(try projector.nearest(on: line, to: point(9, 1)).parameter == 1)
    }

    @Test func aCircleProjectsAlongTheRayFromItsCenter() throws {
        let circle = SketchCurveGeometry2D.circle(center: point(1, 1), radius: 2)
        let projection = try projector.nearest(on: circle, to: point(1, -4))
        #expect(abs(projection.parameter - 3 * .pi / 2) < 1e-15)
        #expect(abs(projection.point.y - -1) < 1e-15)
        #expect(abs(projection.distance - 3) < 1e-15)
    }

    @Test func anArcTakesItsNearerEndOutsideItsSweep() throws {
        let arc = SketchCurveGeometry2D.arc(center: point(0, 0), radius: 1, startAngle: 0, endAngle: .pi / 2)
        #expect(abs(try projector.nearest(on: arc, to: point(2, 2)).parameter - .pi / 4) < 1e-15)
        // Below the x axis, closer to the start at angle 0 than to the end at π/2.
        #expect(try projector.nearest(on: arc, to: point(1, -0.5)).parameter == 0)
        #expect(abs(try projector.nearest(on: arc, to: point(-0.5, 1)).parameter - .pi / 2) < 1e-15)
    }

    @Test func aChainFootIsWhereTheOffsetMeetsTheTangentAtRightAngles() throws {
        let controls = [point(0, 0), point(1, 2), point(2, 2), point(3, 0), point(4, -2), point(5, -2), point(6, 0)]
        let chain = SketchCurveGeometry2D.cubicBezierChain(controlPoints: controls)
        // The first span is symmetric about x = 1.5, so a point above its middle projects there.
        let symmetric = try projector.nearest(on: chain, to: point(1.5, 5))
        #expect(abs(symmetric.parameter - 0.5) < 1e-12)
        #expect(abs(symmetric.point.y - 1.5) < 1e-12)
        // A generic point on the second span's side: the offset is normal to the tangent there.
        let generic = try projector.nearest(on: chain, to: point(4.3, -2.7))
        #expect(generic.parameter > 1 && generic.parameter < 2)
        let t = generic.parameter - 1, s = 1 - t
        let p = Array(controls[3...6])
        let tangent = Point2D(
            x: 3 * s * s * (p[1].x - p[0].x) + 6 * s * t * (p[2].x - p[1].x) + 3 * t * t * (p[3].x - p[2].x),
            y: 3 * s * s * (p[1].y - p[0].y) + 6 * s * t * (p[2].y - p[1].y) + 3 * t * t * (p[3].y - p[2].y)
        )
        let offset = Point2D(x: generic.point.x - 4.3, y: generic.point.y - -2.7)
        #expect(abs(offset.x * tangent.x + offset.y * tangent.y) < 1e-12)
    }

    @Test func degenerateAndNonFiniteInputIsRefused() {
        #expect(throws: KernelError.self) {
            _ = try projector.nearest(on: .line(start: point(0, 0), end: point(0, 0)), to: point(1, 1))
        }
        #expect(throws: KernelError.self) {
            _ = try projector.nearest(on: .circle(center: point(0, 0), radius: 0), to: point(1, 1))
        }
        #expect(throws: KernelError.self) {
            _ = try projector.nearest(on: .circle(center: point(0, 0), radius: 1), to: point(.nan, 1))
        }
    }
}
