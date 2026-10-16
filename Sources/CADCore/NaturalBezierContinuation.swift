/// Extensions of a cubic Bezier chain, or of any Bezier end segment, past one of its ends.
public struct NaturalBezierContinuation: Sendable {
    /// Which end of the chain is extended.
    public enum End: Sendable {
        case start
        case end
    }

    public let tolerance: ModelingTolerance

    public init(tolerance: ModelingTolerance) {
        self.tolerance = tolerance
    }

    /// Evaluates one persisted extension coordinate after both expression evaluators resolve inputs.
    public func coordinate(_ coordinates: [Quantity], length: Quantity, index: Int) throws -> Quantity {
        var admission = UnboundedAuthoringAdmission()
        return try coordinate(coordinates, length: length, index: index, using: &admission)
    }

    public func coordinate<A: NumericWorkAdmission & ~Copyable>(
        _ coordinates: [Quantity], length: Quantity, index: Int, using admission: inout A
    ) throws -> Quantity {
        try admission.checkpoint()
        try Self.validateCoordinateForm(count: coordinates.count, index: index)
        for offset in 0...coordinates.count {
            try admission.consumeWork(1)
            let value = offset < coordinates.count ? coordinates[offset] : length
            try value.validate()
            guard value.kind == .length else {
                throw UnitError.expectedQuantity(operation: "bezierNaturalExtension", expected: .length, actual: value.kind)
            }
        }
        try admission.retainStorage(count: coordinates.count / 2, stride: MemoryLayout<Point2D>.stride)
        let points = try stride(from: 0, to: coordinates.count, by: 2).map { offset in
            try admission.consumeWork(1)
            return Point2D(x: coordinates[offset].value, y: coordinates[offset + 1].value)
        }
        let result = try naturalSpan(ofSegment: points, at: .end, length: length.value, using: &admission)[index / 2]
        let value = Quantity(value: index.isMultiple(of: 2) ? result.x : result.y, kind: .length)
        try value.validate()
        try admission.checkpoint()
        return value
    }

    public static func validateCoordinateForm(count: Int, index: Int) throws {
        guard (4...24).contains(count), count.isMultiple(of: 2), (0..<(count - 2)).contains(index) else {
            throw KernelError(phase: .geometry, code: .invalidInput, tolerance: .standard,
                message: "Natural extension requires degree 1...11 and an existing output coordinate.")
        }
    }

    /// Continues the end cubic until it has run `length`, returning the three new control points.
    public func naturalSpan(of controlPoints: [Point2D], at end: End, length: Double) throws -> [Point2D] {
        var admission = UnboundedAuthoringAdmission()
        return try naturalSpan(of: controlPoints, at: end, length: length, using: &admission)
    }

    public func naturalSpan<A: NumericWorkAdmission & ~Copyable>(
        of controlPoints: [Point2D], at end: End, length: Double, using admission: inout A
    ) throws -> [Point2D] {
        try admission.checkpoint()
        guard controlPoints.count >= 4, (controlPoints.count - 1).isMultiple(of: 3) else {
            throw invalid("A cubic Bezier chain needs 3n + 1 control points.")
        }
        for point in controlPoints {
            try admission.consumeWork(1)
            guard point.x.isFinite && point.y.isFinite else {
                throw invalid("A cubic Bezier chain needs finite control points.")
            }
        }
        guard length.isFinite, length > tolerance.distance else {
            throw invalid("An extension length must be finite and above the modeling distance.")
        }
        let count = controlPoints.count
        try admission.retainStorage(count: 4, stride: MemoryLayout<Point2D>.stride)
        try admission.consumeWork(4)
        let segment: [Point2D] = switch end {
        case .end: Array(controlPoints[(count - 4)...])
        case .start: Array(controlPoints[0...3])
        }
        return try naturalSpan(ofSegment: segment, at: end, length: length, using: &admission)
    }

    /// Continues the same degree-n polynomial beyond its end; blossom values retain its clock.
    public func naturalSpan(ofSegment segment: [Point2D], at end: End, length: Double) throws -> [Point2D] {
        var admission = UnboundedAuthoringAdmission()
        return try naturalSpan(ofSegment: segment, at: end, length: length, using: &admission)
    }

    public func naturalSpan<A: NumericWorkAdmission & ~Copyable>(
        ofSegment segment: [Point2D], at end: End, length: Double, using admission: inout A
    ) throws -> [Point2D] {
        try admission.checkpoint()
        guard segment.count >= 2 else {
            throw invalid("A Bezier segment needs at least two control points.")
        }
        for point in segment {
            try admission.consumeWork(1)
            guard point.x.isFinite && point.y.isFinite else {
                throw invalid("A Bezier segment needs finite control points.")
            }
        }
        guard length.isFinite, length > tolerance.distance else {
            throw invalid("An extension length must be finite and above the modeling distance.")
        }
        let span: [Point2D]
        switch end {
        case .end: span = segment
        case .start:
            try admission.retainStorage(count: segment.count, stride: MemoryLayout<Point2D>.stride)
            try admission.consumeWork(segment.count)
            span = segment.reversed()
        }
        let endSpeed = try speed(span, at: 1, using: &admission)
        guard endSpeed > tolerance.distance else {
            throw invalid("The chain's end has no tangent to continue along.")
        }
        var s = 1 + length / endSpeed
        for _ in 0..<50 {
            try admission.consumeWork(1)
            let error = try arcLength(span, from: 1, to: s, using: &admission) - length
            let step = try error / speed(span, at: s, using: &admission)
            guard step.isFinite else { throw invalid("The Natural extension did not converge.") }
            s -= step
            if abs(step) <= 1e-14 * max(1, s) { break }
        }
        guard s > 1, abs(try arcLength(span, from: 1, to: s, using: &admission) - length) <= tolerance.distance else {
            throw invalid("The Natural extension did not reach the requested length.")
        }
        // The piece on [1, s] has control points f(1…1, s…s) with i values s, i = 1…n.
        let degree = span.count - 1
        try admission.retainStorage(count: degree, stride: MemoryLayout<Point2D>.stride)
        var continued: [Point2D] = []
        continued.reserveCapacity(degree)
        for count in 1...degree {
            try admission.consumeWork(1)
            try admission.retainStorage(count: degree, stride: MemoryLayout<Double>.stride)
            var parameters: [Double] = []
            parameters.reserveCapacity(degree)
            for offset in 0..<degree {
                try admission.consumeWork(1)
                parameters.append(offset < degree - count ? 1 : s)
            }
            continued.append(try blossom(span, parameters, using: &admission))
        }
        let result: [Point2D]
        switch end {
        case .end: result = continued
        case .start:
            try admission.retainStorage(count: continued.count, stride: MemoryLayout<Point2D>.stride)
            try admission.consumeWork(continued.count)
            result = continued.reversed()
        }
        try admission.checkpoint()
        return result
    }

    /// De Casteljau with a different parameter at each level.
    private func blossom<A: NumericWorkAdmission & ~Copyable>(
        _ p: [Point2D], _ parameters: [Double], using admission: inout A
    ) throws -> Point2D {
        var points = p
        for u in parameters {
            try admission.consumeWork(1)
            try admission.retainStorage(count: points.count - 1, stride: MemoryLayout<Point2D>.stride)
            points = try zip(points, points.dropFirst()).map { a, b in
                try admission.consumeWork(1)
                return Point2D(x: a.x + (b.x - a.x) * u, y: a.y + (b.y - a.y) * u)
            }
        }
        return points[0]
    }

    private func speed<A: NumericWorkAdmission & ~Copyable>(
        _ p: [Point2D], at u: Double, using admission: inout A
    ) throws -> Double {
        let n = Double(p.count - 1)
        try admission.retainStorage(count: p.count - 1, stride: MemoryLayout<Point2D>.stride)
        let derivative = try zip(p, p.dropFirst()).map { a, b in
            try admission.consumeWork(1)
            return Point2D(x: n * (b.x - a.x), y: n * (b.y - a.y))
        }
        try admission.retainStorage(count: derivative.count - 1, stride: MemoryLayout<Double>.stride)
        try admission.consumeWork(derivative.count - 1)
        let d = try blossom(derivative, Array(repeating: u, count: derivative.count - 1), using: &admission)
        return (d.x * d.x + d.y * d.y).squareRoot()
    }

    private func arcLength<A: NumericWorkAdmission & ~Copyable>(
        _ p: [Point2D], from a: Double, to b: Double, using admission: inout A
    ) throws -> Double {
        try admission.retainStorage(count: 10, stride: MemoryLayout<Double>.stride)
        try admission.consumeWork(10)
        let nodes = [0.0, -0.538_469_310_105_683_1, 0.538_469_310_105_683_1, -0.906_179_845_938_664, 0.906_179_845_938_664]
        let weights = [0.568_888_888_888_888_9, 0.478_628_670_499_366_5, 0.478_628_670_499_366_5, 0.236_926_885_056_189_1, 0.236_926_885_056_189_1]
        let pieces = 16
        let width = (b - a) / Double(pieces)
        var total = 0.0
        for piece in 0..<pieces {
            try admission.consumeWork(1)
            let middle = a + (Double(piece) + 0.5) * width
            for (node, weight) in zip(nodes, weights) {
                try admission.consumeWork(1)
                total += try weight * speed(p, at: middle + node * width / 2, using: &admission)
            }
        }
        return total * width / 2
    }

    private func invalid(_ message: String) -> KernelError {
        KernelError(phase: .geometry, code: .invalidInput, tolerance: tolerance, message: message)
    }
}
