import CADCore
import CADGeometry
import Foundation

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

    /// One term a(u) b(v) of an integrand, as its boundary primitive a(u) B(v), with the scalar or
    /// vector it weights.
    private struct Term<Weight> {
        var weight: Weight
        var uFactor: UFactor
        var vPrimitive: (Double) -> Double
    }

    private static let rule = GaussLegendreRule(count: 16)
    private static let maximumPieceSpan = 0.5

    func measurement(
        of face: Face,
        on surface: AnalyticSurface3D,
        in model: BRepModel,
        tolerance: ModelingTolerance
    ) throws -> FaceAreaMeasurement {
        let support = Surface3D.analytic(surface)
        let area: [Term<Double>]
        let moments: [Term<Vector3D>]
        switch surface {
        case let .cone(apex, _, _):
            // S = apex + v P + v (Q cos u + R sin u), with P along the axis and |Q| = |R| = sin α;
            // the area element is v sin α.
            let p0 = try support.point(u: 0, v: 1, tolerance: tolerance) - apex
            let pHalf = try support.point(u: .pi / 2, v: 1, tolerance: tolerance) - apex
            let pPi = try support.point(u: .pi, v: 1, tolerance: tolerance) - apex
            let axial = (p0 + pPi) * 0.5
            let q = (p0 - pPi) * 0.5
            let r = pHalf - axial
            let s = q.length
            try requireOneNappe(face, in: model, tolerance: tolerance)
            area = [Term(weight: s, uFactor: .one) { $0 * $0 / 2 }]
            moments = [
                Term(weight: (apex - .origin) * s, uFactor: .one) { $0 * $0 / 2 },
                Term(weight: axial * s, uFactor: .one) { $0 * $0 * $0 / 3 },
                Term(weight: q * s, uFactor: .cosine) { $0 * $0 * $0 / 3 },
                Term(weight: r * s, uFactor: .sine) { $0 * $0 * $0 / 3 },
            ]
        case let .torus(center, _, major, minor):
            // S = C + (R + r cos v)(X cos u + Y sin u) + r A sin v; the element is r (R + r cos v).
            guard major > minor + tolerance.distance else {
                throw unsupported("Face area is measured on ring tori only.", tolerance)
            }
            let x = (try support.point(u: 0, v: 0, tolerance: tolerance) - center) * (1 / (major + minor))
            let y = (try support.point(u: .pi / 2, v: 0, tolerance: tolerance) - center) * (1 / (major + minor))
            let a = (try support.point(u: 0, v: .pi / 2, tolerance: tolerance) - center - x * major) * (1 / minor)
            let element: (Double) -> Double = { minor * (major * $0 + minor * sin($0)) }
            let squared: (Double) -> Double = { v in
                minor * (major * major * v + 2 * major * minor * sin(v) + minor * minor * (v / 2 + sin(2 * v) / 4))
            }
            area = [Term(weight: 1.0, uFactor: .one, vPrimitive: element)]
            moments = [
                Term(weight: center - .origin, uFactor: .one, vPrimitive: element),
                Term(weight: x, uFactor: .cosine, vPrimitive: squared),
                Term(weight: y, uFactor: .sine, vPrimitive: squared),
                Term(weight: a, uFactor: .one) { v in
                    minor * minor * (major * (1 - cos(v)) + minor * sin(v) * sin(v) / 2)
                },
            ]
        default:
            throw unsupported("Face area measures cones and tori here.", tolerance)
        }

        var signedArea = 0.0
        var moment = Vector3D.zero
        for loopID in face.loops {
            guard let loop = model.loops[loopID], !loop.coedges.isEmpty else {
                throw TopologyError.missingReference("Face area references a missing or empty loop.")
            }
            for coedge in loop.coedges {
                guard let curve = coedge.surfaceParameterCurve else {
                    throw TopologyError.invalidTrim(coedge.edgeID)
                }
                for segment in try segments(of: curve, tolerance: tolerance) {
                    for term in area {
                        signedArea -= term.weight * integral(term, from: segment.start, to: segment.end)
                    }
                    for term in moments {
                        moment = moment - term.weight * integral(term, from: segment.start, to: segment.end)
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
    private func integral<Weight>(_ term: Term<Weight>, from start: SurfaceParameter, to end: SurfaceParameter) -> Double {
        let du = end.u - start.u, dv = end.v - start.v
        guard du != 0 else { return 0 }
        let pieces = max(1, Int((max(abs(du), abs(dv)) / Self.maximumPieceSpan).rounded(.up)))
        var sum = 0.0
        for piece in 0..<pieces {
            let low = Double(piece) / Double(pieces), high = Double(piece + 1) / Double(pieces)
            sum += Self.rule.integrate(from: low, to: high) { s in
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
        tolerance: ModelingTolerance
    ) throws -> [(start: SurfaceParameter, end: SurfaceParameter)] {
        func shifted(u: Double, v: Double) -> SurfaceParameter {
            SurfaceParameter(u: u + uShift, v: v + vShift)
        }
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
            return zip(points, points.dropFirst()).map { (shifted(u: $0.u, v: $0.v), shifted(u: $1.u, v: $1.v)) }
        case let .periodicTranslation(base, translatedU, translatedV):
            return try segments(
                of: base, uShift: uShift + translatedU, vShift: vShift + translatedV, tolerance: tolerance
            )
        default:
            throw unsupported(
                "Face area on a cone or torus is measured for pcurves straight in the parameter domain only.",
                tolerance
            )
        }
    }

    /// The cone's area element is v sin α only while v keeps one sign: a face across the apex is
    /// refused rather than measured with a cancelling element.
    private func requireOneNappe(_ face: Face, in model: BRepModel, tolerance: ModelingTolerance) throws {
        var lowest = Double.infinity, highest = -Double.infinity
        for loopID in face.loops {
            for coedge in model.loops[loopID]?.coedges ?? [] {
                guard let curve = coedge.surfaceParameterCurve else { continue }
                for segment in try segments(of: curve, tolerance: tolerance) {
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
