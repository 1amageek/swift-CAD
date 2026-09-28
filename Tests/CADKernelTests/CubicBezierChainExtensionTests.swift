import Testing
@testable import CADKernel
import CADCore

/// The Natural extension continues a chain's end span as its own cubic.
@Suite struct CubicBezierChainExtensionTests {
    private let extension_ = CubicBezierChainExtension(tolerance: .standard)
    private let q = [Point2D(x: 0, y: 0), Point2D(x: 1, y: 2), Point2D(x: 3, y: 2), Point2D(x: 4, y: 0)]

    /// Control points of cubic `q` restricted to [a, b].
    private func piece(_ a: Double, _ b: Double) -> [Point2D] {
        func blossom(_ u: [Double]) -> Point2D {
            var points = q
            for t in u { points = zip(points, points.dropFirst()).map { Point2D(x: $0.x + ($1.x - $0.x) * t, y: $0.y + ($1.y - $0.y) * t) } }
            return points[0]
        }
        return [blossom([a, a, a]), blossom([a, a, b]), blossom([a, b, b]), blossom([b, b, b])]
    }

    /// Arc length of `q` on [a, b], by fine sampling.
    private func length(_ a: Double, _ b: Double) -> Double {
        let samples = 20_000
        var total = 0.0
        var previous = piece(a, a)[0]
        for i in 1...samples {
            let point = piece(a, a + (b - a) * Double(i) / Double(samples))[3]
            total += ((point.x - previous.x) * (point.x - previous.x) + (point.y - previous.y) * (point.y - previous.y)).squareRoot()
            previous = point
        }
        return total
    }

    private func close(_ a: [Point2D], _ b: [Point2D], _ tolerance: Double) -> Bool {
        a.count == b.count && zip(a, b).allSatisfy { abs($0.x - $1.x) < tolerance && abs($0.y - $1.y) < tolerance }
    }

    /// A quintic end segment continues as its own quintic: the extension of q5 on [0, 0.5] by
    /// the length of q5 on [0.5, 0.8] is q5 on [0.5, 0.8], at either end.
    @Test func aSegmentOfAnyDegreeContinuesAsItsOwnPolynomial() throws {
        let q5 = [Point2D(x: 0, y: 0), Point2D(x: 1, y: 2), Point2D(x: 2, y: -1), Point2D(x: 3, y: 3), Point2D(x: 4, y: 1), Point2D(x: 5, y: 2)]
        func blossom(_ u: [Double]) -> Point2D {
            var points = q5
            for t in u { points = zip(points, points.dropFirst()).map { Point2D(x: $0.x + ($1.x - $0.x) * t, y: $0.y + ($1.y - $0.y) * t) } }
            return points[0]
        }
        func piece(_ a: Double, _ b: Double) -> [Point2D] {
            (0...5).map { blossom(Array(repeating: a, count: 5 - $0) + Array(repeating: b, count: $0)) }
        }
        func arcLength(_ a: Double, _ b: Double) -> Double {
            var total = 0.0
            var previous = blossom(Array(repeating: a, count: 5))
            for i in 1...20_000 {
                let point = blossom(Array(repeating: a + (b - a) * Double(i) / 20_000, count: 5))
                total += ((point.x - previous.x) * (point.x - previous.x) + (point.y - previous.y) * (point.y - previous.y)).squareRoot()
                previous = point
            }
            return total
        }
        let atEnd = try extension_.naturalSpan(ofSegment: piece(0, 0.5), at: .end, length: arcLength(0.5, 0.8))
        #expect(close(atEnd, Array(piece(0.5, 0.8).dropFirst()), 1e-6))
        let atStart = try extension_.naturalSpan(ofSegment: piece(0.5, 1), at: .start, length: arcLength(0.2, 0.5))
        #expect(close(atStart, Array(piece(0.2, 0.5).dropLast()), 1e-6))
    }

    @Test func theEndSpanContinuesAsItsOwnCubic() throws {
        let chain = piece(0, 0.5)
        let extended = try extension_.naturalSpan(of: chain, at: .end, length: length(0.5, 0.8))
        #expect(close(extended, Array(piece(0.5, 0.8).dropFirst()), 1e-6))
    }

    @Test func theStartSpanContinuesBackward() throws {
        let chain = piece(0.4, 1)
        let extended = try extension_.naturalSpan(of: chain, at: .start, length: length(0.1, 0.4))
        #expect(close(extended, Array(piece(0.1, 0.4).dropLast()), 1e-6))
    }

    @Test func aDegenerateEndOrLengthIsRefused() {
        let pinched = [Point2D(x: 0, y: 0), Point2D(x: 1, y: 1), Point2D(x: 2, y: 2), Point2D(x: 2, y: 2)]
        #expect(throws: KernelError.self) { _ = try extension_.naturalSpan(of: pinched, at: .end, length: 1) }
        #expect(throws: KernelError.self) { _ = try extension_.naturalSpan(of: q, at: .end, length: 0) }
        #expect(throws: KernelError.self) { _ = try extension_.naturalSpan(of: Array(q.prefix(3)), at: .end, length: 1) }
    }
}
