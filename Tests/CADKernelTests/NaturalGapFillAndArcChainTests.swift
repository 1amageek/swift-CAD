import CADCore
import CADGeometry
import Foundation
import Testing
@testable import CADKernel

/// Natural gap fill continues each offset's end span along its own cubic until they meet; a
/// joined chain of spans of any degree offsets as one curve; an arc is a cubic chain within the
/// modeling distance.
@Suite("Natural gap fill and arc chains")
struct NaturalGapFillAndArcChainTests {
    private let offsetter = CubicBezierChainOffset(tolerance: .standard)

    private func point(_ chain: [Point2D], span: Int, t: Double) -> Point2D {
        let p = Array(chain[(3 * span)...(3 * span + 3)]), s = 1 - t
        return Point2D(
            x: s * s * s * p[0].x + 3 * s * s * t * p[1].x + 3 * s * t * t * p[2].x + t * t * t * p[3].x,
            y: s * s * s * p[0].y + 3 * s * s * t * p[1].y + 3 * s * t * t * p[2].y + t * t * t * p[3].y
        )
    }

    @Test func straightSpansMeetWhereTheirLinesDo() throws {
        // Right along x, then up: the right-hand offset (negative distance) parts at the corner.
        let spans = [[Point2D(x: 0, y: 0), Point2D(x: 10, y: 0)], [Point2D(x: 10, y: 0), Point2D(x: 10, y: 10)]]
        let natural = try offsetter.offset(spans: spans, distance: -1, gapFill: .natural)
        let linear = try offsetter.offset(spans: spans, distance: -1, gapFill: .linear)
        #expect(natural.contains { hypot($0.x - 11, $0.y + 1) < 1.0e-9 })
        #expect(hypot(natural[0].x - linear[0].x, natural[0].y - linear[0].y) < 1.0e-12)
        #expect(hypot(natural.last!.x - linear.last!.x, natural.last!.y - linear.last!.y) < 1.0e-12)
    }

    @Test func curvedSpansMeetAlongTheirOwnCubics() throws {
        // Two bulging cubics meeting in a V at (10, 0); below the V (the right-hand offset,
        // negative distance) their offsets part.
        let first = [Point2D(x: 0, y: 0), Point2D(x: 3, y: 3), Point2D(x: 7, y: 3), Point2D(x: 10, y: 0)]
        let second = [Point2D(x: 10, y: 0), Point2D(x: 13, y: 3), Point2D(x: 17, y: 3), Point2D(x: 20, y: 0)]
        let natural = try offsetter.offset(spans: [first, second], distance: -1, gapFill: .natural)
        let linear = try offsetter.offset(spans: [first, second], distance: -1, gapFill: .linear)
        #expect((natural.count - 1).isMultiple(of: 3))
        // The chain is continuous and differs from the straight continuation at the corner.
        let spanCount = (natural.count - 1) / 3
        for span in 0..<(spanCount - 1) {
            let end = point(natural, span: span, t: 1), start = point(natural, span: span + 1, t: 0)
            #expect(hypot(end.x - start.x, end.y - start.y) < 1.0e-12)
        }
        #expect(natural != linear)
    }

    @Test func aLineTangentToAnArcOffsetsWithoutACorner() throws {
        let arc = try CubicBezierArcApproximation(tolerance: .standard)
            .chain(center: Point2D(x: 10, y: 5), radius: 5, startAngle: -.pi / 2, sweep: .pi)
        let arcSpans = stride(from: 0, to: arc.count - 1, by: 3).map { Array(arc[$0...($0 + 3)]) }
        let spans = [[Point2D(x: 0, y: 0), Point2D(x: 10, y: 0)]] + arcSpans
        let offset = try offsetter.offset(spans: spans, distance: 1, gapFill: nil)
        // Every point is 1 from the line or from the circle (radius 4 inside it).
        for span in 0..<((offset.count - 1) / 3) {
            for i in 0...8 {
                let p = point(offset, span: span, t: Double(i) / 8)
                let fromLine = abs(p.y - 1), fromCircle = abs(hypot(p.x - 10, p.y - 5) - 4)
                #expect(min(fromLine, fromCircle) < 2.0e-6)
            }
        }
    }

    @Test func anArcChainStaysOnItsCircle() throws {
        let approximation = CubicBezierArcApproximation(tolerance: .standard)
        let chain = try approximation.chain(center: Point2D(x: 1, y: 2), radius: 3, startAngle: 0.3, sweep: 2 * .pi)
        #expect(hypot(chain[0].x - chain.last!.x, chain[0].y - chain.last!.y) < 1.0e-12)
        for span in 0..<((chain.count - 1) / 3) {
            for i in 0...16 {
                let p = point(chain, span: span, t: Double(i) / 16)
                #expect(abs(hypot(p.x - 1, p.y - 2) - 3) <= 1.0e-6)
            }
        }
        #expect(throws: KernelError.self) { try approximation.chain(center: Point2D(x: 0, y: 0), radius: 0, startAngle: 0, sweep: 1) }
    }
}
