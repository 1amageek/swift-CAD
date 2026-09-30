import Foundation
import CADCore
import CADGeometry

/// Where a point of a face's parameter rectangle lands when the face is laid flat (Unwrap Face):
/// an isometry for the surfaces that unroll without stretching, and otherwise the net of
/// parameter lines laid out by arc length.
///
/// | Surface | Flat point of (u, v) |
/// |---|---|
/// | plane | (u, v): its parameters are lengths along orthonormal axes |
/// | cylinder of radius r | (r·u, v): the angle unrolled around the axis |
/// | cone of half-angle α | v·(cos(u·sin α), −sin(u·sin α)): the slant distance and the angle scaled into a sector |
/// | other | (arc length along the middle V line to u, arc length along the middle U line to v) |
///
/// Each map turns (u, v) counterclockwise into the plane, so a face's front stays its front.
struct FaceDevelopment {
    private enum Kind {
        case plane
        case cylinder(radius: Double)
        case cone(sine: Double)
        case netByArcLength(u: ArcLengthTable, v: ArcLengthTable)
    }

    private let kind: Kind

    init(surface: Surface3D, box: SurfaceParameterBox, tolerance: ModelingTolerance) throws {
        switch surface {
        case .plane, .analytic(.plane):
            kind = .plane
        case let .cylinder(cylinder):
            kind = .cylinder(radius: cylinder.radius)
        case let .analytic(.cylinder(_, _, radius)):
            kind = .cylinder(radius: radius)
        case let .analytic(.cone(_, _, halfAngle)):
            kind = .cone(sine: sin(halfAngle))
        default:
            let middleU = (box.u.lower + box.u.upper) / 2
            let middleV = (box.v.lower + box.v.upper) / 2
            kind = .netByArcLength(
                u: try ArcLengthTable(over: box.u, tolerance: tolerance) { u in
                    try surface.differentialGeometry(u: u, v: middleV, tolerance: tolerance).tangentU.length
                },
                v: try ArcLengthTable(over: box.v, tolerance: tolerance) { v in
                    try surface.differentialGeometry(u: middleU, v: v, tolerance: tolerance).tangentV.length
                }
            )
        }
    }

    /// The flat point of (u, v), in the XY plane.
    func point(u: Double, v: Double) throws -> (x: Double, y: Double) {
        switch kind {
        case .plane:
            return (u, v)
        case let .cylinder(radius):
            return (radius * u, v)
        case let .cone(sine):
            return (v * cos(u * sine), -v * sin(u * sine))
        case let .netByArcLength(uTable, vTable):
            return (try uTable.length(to: u), try vTable.length(to: v))
        }
    }
}

/// The arc length of a parameter line from the start of an interval, integrated by five-point
/// Gauss–Legendre quadrature over 64 equal cells, the cells' running sums kept.
private struct ArcLengthTable {
    private static let cells = 64
    private static let nodes: [(x: Double, w: Double)] = [
        (0, 128.0 / 225.0),
        (-1.0 / 3.0 * (5 - 2 * (10.0 / 7.0).squareRoot()).squareRoot(), (322 + 13 * 70.0.squareRoot()) / 900),
        (1.0 / 3.0 * (5 - 2 * (10.0 / 7.0).squareRoot()).squareRoot(), (322 + 13 * 70.0.squareRoot()) / 900),
        (-1.0 / 3.0 * (5 + 2 * (10.0 / 7.0).squareRoot()).squareRoot(), (322 - 13 * 70.0.squareRoot()) / 900),
        (1.0 / 3.0 * (5 + 2 * (10.0 / 7.0).squareRoot()).squareRoot(), (322 - 13 * 70.0.squareRoot()) / 900),
    ]

    private let interval: ScalarInterval
    private let speed: (Double) throws -> Double
    private let sums: [Double]

    init(over interval: ScalarInterval, tolerance: ModelingTolerance, speed: @escaping (Double) throws -> Double) throws {
        guard interval.width > 0 else {
            throw KernelError(phase: .geometry, code: .invalidInput, tolerance: tolerance, message: "A face to lay flat spans no parameter extent.")
        }
        self.interval = interval
        self.speed = speed
        var sums = [0.0]
        let width = interval.width / Double(Self.cells)
        for cell in 0..<Self.cells {
            let lower = interval.lower + width * Double(cell)
            sums.append(sums[cell] + (try Self.integral(speed, from: lower, to: lower + width)))
        }
        self.sums = sums
    }

    func length(to parameter: Double) throws -> Double {
        let width = interval.width / Double(Self.cells)
        let cell = min(max(Int(((parameter - interval.lower) / width).rounded(.down)), 0), Self.cells - 1)
        let lower = interval.lower + width * Double(cell)
        return sums[cell] + (try Self.integral(speed, from: lower, to: parameter))
    }

    private static func integral(_ speed: (Double) throws -> Double, from a: Double, to b: Double) throws -> Double {
        let half = (b - a) / 2
        let middle = (a + b) / 2
        return try nodes.reduce(0) { $0 + $1.w * (try speed(middle + half * $1.x)) } * half
    }
}
