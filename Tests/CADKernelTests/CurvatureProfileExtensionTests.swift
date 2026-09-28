import Foundation
import Testing
@testable import CADKernel
import CADCore

/// Arc and Soft extensions start with the end's tangent and curvature and stay on their profile.
@Suite struct CurvatureProfileExtensionTests {
    private let extender = CurvatureProfileExtension(tolerance: .standard)

    private func derivatives(_ p: [Point2D]) -> (first: Point2D, second: Point2D) {
        (Point2D(x: 3 * (p[1].x - p[0].x), y: 3 * (p[1].y - p[0].y)),
         Point2D(x: 6 * (p[2].x - 2 * p[1].x + p[0].x), y: 6 * (p[2].y - 2 * p[1].y + p[0].y)))
    }

    @Test func anArcExtensionFollowsTheOsculatingCircle() throws {
        // A circle of radius 0.01 around (0, 0.01), leaving the origin along +x.
        let points = try extender.cubicSpans(from: Point2D(x: 0, y: 0), direction: Point2D(x: 1, y: 0), curvature: 100, length: 0.015, profile: .arc)
        #expect(points.count.isMultiple(of: 3))
        let chain = [Point2D(x: 0, y: 0)] + points
        for index in stride(from: 3, to: chain.count, by: 3) {
            #expect(abs(hypot(chain[index].x, chain[index].y - 0.01) - 0.01) <= 1e-9)
        }
        let first = derivatives(Array(chain[0...3]))
        let speed = hypot(first.first.x, first.first.y)
        #expect(abs(first.first.y) <= 1e-12)
        let curvature = (first.first.x * first.second.y - first.first.y * first.second.x) / pow(speed, 3)
        #expect(abs(curvature - 100) <= 1e-6)
        // The far end is 1.5 rad around the circle.
        let last = chain[chain.count - 1]
        #expect(abs(last.x - 0.01 * sin(1.5)) <= 1e-7 && abs(last.y - (0.01 - 0.01 * cos(1.5))) <= 1e-7)
    }

    @Test func aSoftExtensionStartsWithTheCurvatureAndEndsStraight() throws {
        let points = try extender.cubicSpans(from: Point2D(x: 0, y: 0), direction: Point2D(x: 1, y: 0), curvature: 50, length: 0.02, profile: .soft)
        let chain = [Point2D(x: 0, y: 0)] + points
        let first = derivatives(Array(chain[0...3]))
        let speed = hypot(first.first.x, first.first.y)
        #expect(abs((first.first.x * first.second.y - first.first.y * first.second.x) / pow(speed, 3) - 50) <= 1e-6)
        // It turns by κ₀L/2 = 0.5 rad in all: the last span arrives at that angle.
        let n = chain.count
        let arrival = atan2(chain[n - 1].y - chain[n - 2].y, chain[n - 1].x - chain[n - 2].x)
        #expect(abs(arrival - 0.5) <= 1e-6)
    }

    @Test func aStraightEndExtendsStraight() throws {
        let points = try extender.cubicSpans(from: Point2D(x: 1, y: 1), direction: Point2D(x: 0, y: 2), curvature: 0, length: 0.5, profile: .arc)
        #expect(points.count == 3)
        #expect(points.allSatisfy { abs($0.x - 1) <= 1e-12 })
        #expect(abs(points[2].y - 1.5) <= 1e-12)
    }
}
