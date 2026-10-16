import HashTreeCollections
import CADCore
import CADGeometry
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#elseif canImport(WASILibc)
import WASILibc
#else
#error("A C math implementation is required.")
#endif

/// Measures a face on a cone or a torus bounded by pcurves that are straight in the parameter
/// domain: affine and coordinate segments and polylines, and periodic translations of them.
///
/// On both supports the area element and every coordinate function times it are sums of terms
/// a(u) · b(v), with a one of 1, cos u and sin u. Green's theorem turns the face's integral of each
/// term into −∮ a(u) B(v) du over its boundary, with B′ = b. Along a straight segment that
/// integrand is an entire function of the segment parameter, made of trigonometric functions of
/// frequency at most two and polynomials of degree at most three; each segment is split into
/// pieces no longer than half a radian in u and v, and a 16-node Gauss–Legendre rule on a piece
/// leaves a remainder bounded by (1/2)³³ (16!)⁴ / (33 (32!)³) times the integrand's 32nd derivative,
/// far below double rounding.
struct RevolvedSurfaceFaceAreaIntegrator {
    private enum UFactor {
        case one, cosine, sine

        func callAsFunction(_ u: Double) -> Double {
            switch self {
            case .one: 1
            case .cosine: cos(u)
            case .sine: sin(u)
            }
        }
    }

    /// Inline primitives avoid a separately allocated capture context for each term.
    private enum VPrimitive {
        case squareHalf, cubeThird
        case torusElement(major: Double, minor: Double)
        case torusSquared(major: Double, minor: Double)
        case torusAxial(major: Double, minor: Double)

        func callAsFunction(_ v: Double) -> Double {
            switch self {
            case .squareHalf: v * v / 2
            case .cubeThird: v * v * v / 3
            case let .torusElement(major, minor): minor * (major * v + minor * sin(v))
            case let .torusSquared(major, minor):
                minor * (major * major * v + 2 * major * minor * sin(v) + minor * minor * (v / 2 + sin(2 * v) / 4))
            case let .torusAxial(major, minor):
                minor * minor * (major * (1 - cos(v)) + minor * sin(v) * sin(v) / 2)
            }
        }
    }

    /// One term a(u) b(v) of an integrand, as its boundary primitive a(u) B(v), with the scalar or
    /// vector it weights.
    private struct Term<Weight> {
        var weight: Weight
        var uFactor: UFactor
        var vPrimitive: VPrimitive
    }

    private static let maximumPieceSpan = 0.5

    func measurement(
        of face: Face,
        on surface: AnalyticSurface3D,
        in model: BRepModel,
        tolerance: ModelingTolerance,
        using execution: inout OriginalQueryExecution
    ) throws -> FaceAreaMeasurement {
        try execution.consumeWork(1)
        let support = Surface3D.analytic(surface)
        try execution.retainStorage(bytes: MemoryLayout<Term<Double>>.stride)
        try execution.retainStorage(bytes: 4 * MemoryLayout<Term<Vector3D>>.stride)
        let area: [Term<Double>]
        let moments: [Term<Vector3D>]
        switch surface {
        case let .cone(apex, _, _):
            // S = apex + v P + v (Q cos u + R sin u), with P along the axis and |Q| = |R| = sin α;
            // the area element is v sin α.
            let p0 = try support.point(u: 0, v: 1, tolerance: tolerance, using: &execution) - apex
            let pHalf = try support.point(u: .pi / 2, v: 1, tolerance: tolerance, using: &execution) - apex
            let pPi = try support.point(u: .pi, v: 1, tolerance: tolerance, using: &execution) - apex
            let axial = (p0 + pPi) * 0.5
            let q = (p0 - pPi) * 0.5
            let r = pHalf - axial
            let s = q.length
            try requireOneNappe(face, in: model, tolerance: tolerance, using: &execution)
            area = [Term(weight: s, uFactor: .one, vPrimitive: .squareHalf)]
            moments = [
                Term(weight: (apex - .origin) * s, uFactor: .one, vPrimitive: .squareHalf),
                Term(weight: axial * s, uFactor: .one, vPrimitive: .cubeThird),
                Term(weight: q * s, uFactor: .cosine, vPrimitive: .cubeThird),
                Term(weight: r * s, uFactor: .sine, vPrimitive: .cubeThird),
            ]
        case let .torus(center, _, major, minor):
            // S = C + (R + r cos v)(X cos u + Y sin u) + r A sin v; the element is r (R + r cos v).
            guard major > minor + tolerance.distance else {
                throw unsupported("Face area is measured on ring tori only.", tolerance)
            }
            let x = (try support.point(u: 0, v: 0, tolerance: tolerance, using: &execution) - center) * (1 / (major + minor))
            let y = (try support.point(u: .pi / 2, v: 0, tolerance: tolerance, using: &execution) - center) * (1 / (major + minor))
            let a = (try support.point(u: 0, v: .pi / 2, tolerance: tolerance, using: &execution) - center - x * major) * (1 / minor)
            let element = VPrimitive.torusElement(major: major, minor: minor)
            let squared = VPrimitive.torusSquared(major: major, minor: minor)
            area = [Term(weight: 1.0, uFactor: .one, vPrimitive: element)]
            moments = [
                Term(weight: center - .origin, uFactor: .one, vPrimitive: element),
                Term(weight: x, uFactor: .cosine, vPrimitive: squared),
                Term(weight: y, uFactor: .sine, vPrimitive: squared),
                Term(weight: a, uFactor: .one, vPrimitive: .torusAxial(major: major, minor: minor)),
            ]
        default:
            throw unsupported("Face area measures cones and tori here.", tolerance)
        }

        let rule = try GaussLegendreRule(count: 16, using: &execution)
        var signedArea = 0.0
        var moment = Vector3D.zero
        for loopID in face.loops {
            try execution.consumeWork(1)
            guard let loop = model.loops[loopID], !loop.coedges.isEmpty else {
                throw TopologyError.missingReference("Face area references a missing or empty loop.")
            }
            for coedge in loop.coedges {
                try execution.consumeWork(1)
                guard let curve = coedge.surfaceParameterCurve else {
                    throw TopologyError.invalidTrim(coedge.edgeID)
                }
                for segment in try segments(of: curve, tolerance: tolerance, using: &execution) {
                    for term in area {
                        signedArea -= term.weight * (try integral(term, from: segment.start, to: segment.end, rule: rule, using: &execution))
                    }
                    for term in moments {
                        moment = moment - term.weight * (try integral(term, from: segment.start, to: segment.end, rule: rule, using: &execution))
                    }
                }
            }
        }
        guard abs(signedArea) > tolerance.distance * tolerance.distance else {
            throw KernelError(
                phase: .topology, code: .topologyFailure, residual: signedArea, tolerance: tolerance,
                message: "Face area found a face bounding no area."
            )
        }
        // Moments over the signed area: the loops' traversal sense cancels.
        return FaceAreaMeasurement(area: abs(signedArea), centroid: .origin + moment * (1 / signedArea))
    }

    /// ∫ a(u) B(v) du along the straight segment from `start` to `end`.
    private func integral<Weight>(_ term: Term<Weight>, from start: SurfaceParameter, to end: SurfaceParameter,
        rule: GaussLegendreRule, using execution: inout OriginalQueryExecution) throws -> Double {
        try execution.consumeWork(1)
        let du = end.u - start.u, dv = end.v - start.v
        guard du != 0 else { return 0 }
        let roundedPieces = (max(abs(du), abs(dv)) / Self.maximumPieceSpan).rounded(.up)
        guard let requestedPieces = Int(exactly: roundedPieces) else { throw ExactScalarFailure.countOverflow }
        let pieces = max(1, requestedPieces)
        var sum = 0.0
        for piece in 0..<pieces {
            try execution.consumeWork(1)
            let low = Double(piece) / Double(pieces), high = Double(piece + 1) / Double(pieces)
            sum += try rule.integrate(from: low, to: high, using: &execution) { s, _ in
                term.uFactor(start.u + du * s) * term.vPrimitive(start.v + dv * s)
            }
        }
        return sum * du
    }

    /// The straight parameter segments `curve` consists of; any other pcurve is refused.
    private func segments(
        of curve: SurfaceParameterCurve,
        uShift: Double = 0,
        vShift: Double = 0,
        tolerance: ModelingTolerance,
        using execution: inout OriginalQueryExecution
    ) throws -> [(start: SurfaceParameter, end: SurfaceParameter)] {
        try execution.consumeWork(1)
        try execution.admitSourceDepth(0)
        func shifted(u: Double, v: Double) -> SurfaceParameter {
            SurfaceParameter(u: u + uShift, v: v + vShift)
        }
        let capacity: Int
        switch curve {
        case let .polyline(points): capacity = max(0, points.count - 1)
        case .affine, .constantU, .constantV: capacity = 1
        default: capacity = 0
        }
        let bytes = capacity.multipliedReportingOverflow(by: MemoryLayout<(SurfaceParameter, SurfaceParameter)>.stride)
        guard !bytes.overflow else { throw ExactScalarFailure.countOverflow }
        try execution.retainStorage(bytes: bytes.partialValue)
        switch curve {
        case let .affine(origin, direction, startParameter, endParameter):
            return [(
                shifted(u: origin.x + direction.x * startParameter, v: origin.y + direction.y * startParameter),
                shifted(u: origin.x + direction.x * endParameter, v: origin.y + direction.y * endParameter)
            )]
        case let .constantU(u, vStart, vEnd):
            return [(shifted(u: u, v: vStart), shifted(u: u, v: vEnd))]
        case let .constantV(v, uStart, uEnd):
            return [(shifted(u: uStart, v: v), shifted(u: uEnd, v: v))]
        case let .polyline(points):
            return try zip(points, points.dropFirst()).map {
                try execution.consumeWork(1)
                return (shifted(u: $0.u, v: $0.v), shifted(u: $1.u, v: $1.v))
            }
        case let .periodicTranslation(base, translatedU, translatedV):
            return try execution.withSourceDepthOffset(1) { execution in
                try segments(of: base, uShift: uShift + translatedU,
                    vShift: vShift + translatedV, tolerance: tolerance, using: &execution)
            }
        default:
            throw unsupported(
                "Face area on a cone or torus is measured for pcurves straight in the parameter domain only.",
                tolerance
            )
        }
    }

    /// The cone's area element is v sin α only while v keeps one sign: a face across the apex is
    /// refused rather than measured with a cancelling element.
    private func requireOneNappe(_ face: Face, in model: BRepModel, tolerance: ModelingTolerance,
        using execution: inout OriginalQueryExecution) throws {
        var lowest = Double.infinity, highest = -Double.infinity
        for loopID in face.loops {
            try execution.consumeWork(1)
            for coedge in model.loops[loopID]?.coedges ?? [] {
                try execution.consumeWork(1)
                guard let curve = coedge.surfaceParameterCurve else { continue }
                for segment in try segments(of: curve, tolerance: tolerance, using: &execution) {
                    lowest = min(lowest, segment.start.v, segment.end.v)
                    highest = max(highest, segment.start.v, segment.end.v)
                }
            }
        }
        guard lowest >= -tolerance.distance || highest <= tolerance.distance else {
            throw unsupported("Face area does not measure a cone face across its apex.", tolerance)
        }
    }

    private func unsupported(_ message: String, _ tolerance: ModelingTolerance) -> KernelError {
        KernelError(phase: .topology, code: .unsupportedCapability, tolerance: tolerance, message: message)
    }
}
