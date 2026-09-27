import Testing
@testable import CADKernel
import CADCore

/// Joints of a cubic Bezier chain that split one cubic are found, and only those.
@Suite struct CubicBezierChainJointsTests {
    private let joints = CubicBezierChainJoints(tolerance: .standard)
    private let q = [Point2D(x: 0, y: 0), Point2D(x: 1, y: 2), Point2D(x: 3, y: 2), Point2D(x: 4, y: 0)]

    /// Cubic `q` split at `t` by De Casteljau: seven control points.
    private func halves(at t: Double) -> [Point2D] {
        func lerp(_ a: Point2D, _ b: Point2D) -> Point2D { Point2D(x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t) }
        let a = lerp(q[0], q[1]), b = lerp(q[1], q[2]), c = lerp(q[2], q[3])
        let d = lerp(a, b), e = lerp(b, c)
        return [q[0], a, d, lerp(d, e), e, c, q[3]]
    }

    private func close(_ a: [Point2D], _ b: [Point2D]) -> Bool {
        a.count == b.count && zip(a, b).allSatisfy { abs($0.x - $1.x) < 1e-12 && abs($0.y - $1.y) < 1e-12 }
    }

    @Test func theHalvesOfOneCubicMergeBackIntoIt() throws {
        for t in [0.3, 0.5, 0.81] {
            let merged = try #require(try joints.mergedSpan(of: halves(at: t), atJoint: 1))
            #expect(close(merged, q))
        }
        // A joint deeper in a longer chain.
        let chain = [Point2D(x: -4, y: 0), Point2D(x: -3, y: 1), Point2D(x: -1, y: 1)] + halves(at: 0.4)
        let merged = try #require(try joints.mergedSpan(of: chain, atJoint: 2))
        #expect(close(merged, q))
    }

    @Test func aJointBetweenDifferentCubicsStays() throws {
        var bent = halves(at: 0.5)
        bent[5].y += 0.1
        #expect(try joints.mergedSpan(of: bent, atJoint: 1) == nil)
        var kinked = halves(at: 0.5)
        kinked[4] = Point2D(x: kinked[4].x, y: kinked[4].y + 0.5)
        #expect(try joints.mergedSpan(of: kinked, atJoint: 1) == nil)
        var cornered = halves(at: 0.5)
        cornered[2] = cornered[3]
        #expect(try joints.mergedSpan(of: cornered, atJoint: 1) == nil)
    }

    @Test func aChainWithoutThatJointIsRefused() {
        #expect(throws: KernelError.self) { _ = try joints.mergedSpan(of: q, atJoint: 1) }
        #expect(throws: KernelError.self) { _ = try joints.mergedSpan(of: halves(at: 0.5), atJoint: 2) }
        var infinite = halves(at: 0.5)
        infinite[1].x = .infinity
        #expect(throws: KernelError.self) { _ = try joints.mergedSpan(of: infinite, atJoint: 1) }
    }
}
