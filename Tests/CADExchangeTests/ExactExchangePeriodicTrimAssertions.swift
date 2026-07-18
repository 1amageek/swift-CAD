import Testing
import CADCore
import CADGeometry
import CADTopology

enum ExactExchangePeriodicTrimAssertions {
    static func validate(source: BRepModel, result: BRepModel) throws {
        let sourceSamples = try periodicEdgeSamples(in: source)
        let resultSamples = try periodicEdgeSamples(in: result)
        #expect(resultSamples.count == sourceSamples.count)

        for (expected, actual) in zip(sourceSamples, resultSamples) {
            #expect(actual.kind == expected.kind)
            #expect(abs(actual.signedSpan - expected.signedSpan) <= ModelingTolerance.standard.angle)
            #expect(actual.start.isApproximatelyEqual(
                to: expected.start,
                tolerance: ModelingTolerance.standard.distance
            ))
            #expect(actual.midpoint.isApproximatelyEqual(
                to: expected.midpoint,
                tolerance: ModelingTolerance.standard.distance
            ))
            #expect(actual.end.isApproximatelyEqual(
                to: expected.end,
                tolerance: ModelingTolerance.standard.distance
            ))
        }

        let sourcePcurveSpans = periodicPcurveSpans(in: source)
        let resultPcurveSpans = periodicPcurveSpans(in: result)
        #expect(resultPcurveSpans.count == sourcePcurveSpans.count)
        for (expected, actual) in zip(sourcePcurveSpans, resultPcurveSpans) {
            #expect(abs(actual - expected) <= ModelingTolerance.standard.angle)
        }
    }

    private static func periodicEdgeSamples(in model: BRepModel) throws -> [PeriodicEdgeSample] {
        var samples: [PeriodicEdgeSample] = []
        for edge in model.edges.values {
            guard let curve = model.geometry.curves[edge.curveID] else {
                continue
            }
            let kind: PeriodicCurveKind
            switch curve {
            case .circle:
                kind = .circle
            case .analytic(.circle):
                kind = .analyticCircle
            case .analytic(.ellipse):
                kind = .ellipse
            case .line, .bSpline, .analytic(.line), .analytic(.arc):
                continue
            }
            let trim = try #require(edge.trim)
            let midpointParameter = 0.5 * (trim.startParameter + trim.endParameter)
            samples.append(PeriodicEdgeSample(
                kind: kind,
                signedSpan: trim.endParameter - trim.startParameter,
                start: try curve.point(at: trim.startParameter, tolerance: .standard),
                midpoint: try curve.point(at: midpointParameter, tolerance: .standard),
                end: try curve.point(at: trim.endParameter, tolerance: .standard)
            ))
        }
        return samples.sorted(by: sampleOrder)
    }

    private static func periodicPcurveSpans(in model: BRepModel) -> [Double] {
        model.loops.values.flatMap(\.coedges).compactMap { coedge in
            guard let pcurve = coedge.surfaceParameterCurve else {
                return nil
            }
            switch pcurve {
            case let .constantV(_, uStart, uEnd):
                return uEnd - uStart
            case let .harmonic(_, _, _, startParameter, endParameter):
                return endParameter - startParameter
            case let .polyline(points):
                guard let start = points.first,
                      let end = points.last,
                      abs(end.v - start.v) <= ModelingTolerance.standard.distance,
                      abs(end.u - start.u) > 1.0 else {
                    return nil
                }
                return end.u - start.u
            case .affine, .constantU, .sphericalGreatCircle, .bSpline:
                return nil
            }
        }.sorted()
    }

    private static func sampleOrder(_ lhs: PeriodicEdgeSample, _ rhs: PeriodicEdgeSample) -> Bool {
        if lhs.kind.rawValue != rhs.kind.rawValue {
            return lhs.kind.rawValue < rhs.kind.rawValue
        }
        if lhs.signedSpan != rhs.signedSpan {
            return lhs.signedSpan < rhs.signedSpan
        }
        if lhs.midpoint.z != rhs.midpoint.z {
            return lhs.midpoint.z < rhs.midpoint.z
        }
        if lhs.midpoint.y != rhs.midpoint.y {
            return lhs.midpoint.y < rhs.midpoint.y
        }
        return lhs.midpoint.x < rhs.midpoint.x
    }

    private enum PeriodicCurveKind: Int {
        case circle
        case analyticCircle
        case ellipse
    }

    private struct PeriodicEdgeSample {
        var kind: PeriodicCurveKind
        var signedSpan: Double
        var start: Point3D
        var midpoint: Point3D
        var end: Point3D
    }
}
