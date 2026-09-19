import Foundation
import CADCore
import CADGeometry

public struct SpatialPathFeature: Codable, Hashable, Sendable {
    public enum Kind: String, Codable, Sendable { case polyline, bezier }
    public enum Handle: String, Codable, Sendable { case position, incoming, outgoing }

    public var kind: Kind
    public var knots: [SpatialPathKnot]
    public var isClosed: Bool

    public init(kind: Kind, knots: [SpatialPathKnot], isClosed: Bool = false) {
        self.kind = kind
        self.knots = knots
        self.isClosed = isClosed
    }

    public var segmentCount: Int { isClosed ? knots.count : max(0, knots.count - 1) }

    public func validate(tolerance: ModelingTolerance) throws {
        try tolerance.validate()
        guard knots.count >= (isClosed ? 3 : 2), Set(knots.map(\.id)).count == knots.count else {
            throw FeatureEvaluationError.invalidGraph("A spatial path requires unique knots and at least two open or three closed knots.")
        }
        for knot in knots { try knot.validate(tolerance: tolerance) }
        for index in 0..<segmentCount {
            let start = knots[index]
            let end = knots[(index + 1) % knots.count]
            let chord = (end.position - start.position).length
            guard chord.isFinite,
                  chord > tolerance.distance || (kind == .bezier &&
                    (start.outgoing.length > tolerance.distance || end.incoming.length > tolerance.distance)) else {
                throw FeatureEvaluationError.invalidGraph("Spatial path segments must not collapse to a point.")
            }
        }
    }

    /// The same exact source curve is consumed by evaluation and edit previews.
    public func exactCurve(tolerance: ModelingTolerance) throws -> BSplineCurve3D {
        try validate(tolerance: tolerance)
        let degree = kind == .polyline ? 1 : 3
        var points = [knots[0].position]
        for index in 0..<segmentCount {
            let next = knots[(index + 1) % knots.count]
            if kind == .bezier {
                points.append(knots[index].position + knots[index].outgoing)
                points.append(next.position + next.incoming)
            }
            points.append(next.position)
        }
        var parameters = Array(repeating: 0.0, count: degree + 1)
        for index in 1..<segmentCount {
            parameters.append(contentsOf: repeatElement(Double(index), count: degree))
        }
        parameters.append(contentsOf: repeatElement(Double(segmentCount), count: degree + 1))
        let curve = BSplineCurve3D(degree: degree, knots: parameters, controlPoints: points)
        try curve.validate(tolerance: tolerance)
        return curve
    }

    public mutating func move(
        knotID: UUID, handle: Handle, to point: Point3D, tolerance: ModelingTolerance
    ) throws {
        try update(tolerance: tolerance) { result in
            let index = try result.index(of: knotID)
            try point.validate()
            if handle == .position {
                result.knots[index].position = point
                return
            }
            guard result.kind == .bezier else {
                throw FeatureEvaluationError.invalidGraph("Polyline knots do not have tangent handles.")
            }
            let vector = point - result.knots[index].position
            let opposite = handle == .incoming ? result.knots[index].outgoing : result.knots[index].incoming
            let replacement: Vector3D
            switch result.knots[index].mode {
            case .corner: replacement = opposite
            case .symmetric: replacement = -vector
            case .smooth:
                if vector.length <= tolerance.distance, opposite.length <= tolerance.distance {
                    replacement = .zero
                } else {
                    replacement = try -vector.normalized(tolerance: tolerance.distance) * opposite.length
                }
            }
            if handle == .incoming {
                result.knots[index].incoming = vector
                result.knots[index].outgoing = replacement
            } else {
                result.knots[index].outgoing = vector
                result.knots[index].incoming = replacement
            }
        }
    }

    public mutating func setMode(
        _ mode: SpatialPathKnot.Mode, knotID: UUID, tolerance: ModelingTolerance
    ) throws {
        try update(tolerance: tolerance) { result in
            guard result.kind == .bezier else {
                throw FeatureEvaluationError.invalidGraph("Polyline knots do not have tangent modes.")
            }
            let index = try result.index(of: knotID)
            var knot = result.knots[index]
            if mode != .corner {
                let direction = knot.outgoing.length > tolerance.distance ? knot.outgoing : -knot.incoming
                if direction.length > tolerance.distance {
                    let unit = try direction.normalized(tolerance: tolerance.distance)
                    if mode == .symmetric {
                        knot.outgoing = direction
                        knot.incoming = -direction
                    } else {
                        guard knot.incoming.length > tolerance.distance, knot.outgoing.length > tolerance.distance else {
                            throw FeatureEvaluationError.invalidGraph("Smooth mode needs two nonzero tangent arms.")
                        }
                        knot.outgoing = unit * knot.outgoing.length
                        knot.incoming = -unit * knot.incoming.length
                    }
                }
            }
            knot.mode = mode
            result.knots[index] = knot
        }
    }

    @discardableResult
    public mutating func insert(
        after knotID: UUID, fraction: Double, tolerance: ModelingTolerance
    ) throws -> UUID {
        let insertedID = UUID()
        try update(tolerance: tolerance) { result in
            let index = try result.index(of: knotID)
            guard index < result.segmentCount, fraction.isFinite, fraction > 0, fraction < 1 else {
                throw FeatureEvaluationError.invalidGraph("Path insertion requires a segment and an interior fraction.")
            }
            let nextIndex = (index + 1) % result.knots.count
            let start = result.knots[index]
            let end = result.knots[nextIndex]
            func interpolate(_ a: Point3D, _ b: Point3D) -> Point3D { a + (b - a) * fraction }
            let newKnot: SpatialPathKnot
            if result.kind == .polyline {
                newKnot = SpatialPathKnot(id: insertedID, position: interpolate(start.position, end.position))
            } else {
                let a = interpolate(start.position, start.position + start.outgoing)
                let b = interpolate(start.position + start.outgoing, end.position + end.incoming)
                let c = interpolate(end.position + end.incoming, end.position)
                let d = interpolate(a, b)
                let e = interpolate(b, c)
                let position = interpolate(d, e)
                result.knots[index].outgoing = a - start.position
                result.knots[nextIndex].incoming = c - end.position
                if start.mode == .symmetric { result.knots[index].mode = .smooth }
                if end.mode == .symmetric { result.knots[nextIndex].mode = .smooth }
                newKnot = SpatialPathKnot(
                    id: insertedID, position: position, incoming: d - position,
                    outgoing: e - position, mode: .smooth
                )
            }
            result.knots.insert(newKnot, at: index + 1)
        }
        return insertedID
    }

    public mutating func remove(knotID: UUID, tolerance: ModelingTolerance) throws {
        try update(tolerance: tolerance) { result in
            result.knots.remove(at: try result.index(of: knotID))
        }
    }

    public mutating func reverse(tolerance: ModelingTolerance) throws {
        try update(tolerance: tolerance) { result in
            result.knots.reverse()
            for index in result.knots.indices {
                let incoming = result.knots[index].incoming
                result.knots[index].incoming = result.knots[index].outgoing
                result.knots[index].outgoing = incoming
            }
        }
    }

    private func index(of id: UUID) throws -> Int {
        guard let index = knots.firstIndex(where: { $0.id == id }) else {
            throw FeatureEvaluationError.missingInput("Spatial path knot no longer exists.")
        }
        return index
    }

    private mutating func update(
        tolerance: ModelingTolerance, _ edit: (inout Self) throws -> Void
    ) throws {
        try validate(tolerance: tolerance)
        var result = self
        try edit(&result)
        try result.validate(tolerance: tolerance)
        self = result
    }

    private enum CodingKeys: String, CodingKey { case kind, knots, isClosed }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        try values.validateOnlyExpectedKeys([.kind, .knots, .isClosed], in: decoder)
        self.init(
            kind: try values.decode(Kind.self, forKey: .kind),
            knots: try values.decode([SpatialPathKnot].self, forKey: .knots),
            isClosed: try values.decode(Bool.self, forKey: .isClosed)
        )
        try validate(tolerance: CADIRPersistenceValidation.tolerance)
    }

    public func encode(to encoder: Encoder) throws {
        try validate(tolerance: CADIRPersistenceValidation.tolerance)
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(kind, forKey: .kind)
        try values.encode(knots, forKey: .knots)
        try values.encode(isClosed, forKey: .isClosed)
    }
}
