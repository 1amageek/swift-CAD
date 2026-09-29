import Foundation
import Testing
import CADCore
import CADGeometry
import CADModeling
@testable import CADKernel

@Suite("Native helical trim crossing", .timeLimit(.minutes(1)))
struct NativeTrimCrossingTests {
    private let tolerance = ModelingTolerance(distance: 1e-8, angle: 1e-10, relative: 1e-10)

    private struct Pair: Decodable {
        let surface: Surface3D
        let curves: [Curve3D]
        let pcurves: [SurfaceParameterCurve]
        let parameters: [Double]
        let points: [Point3D]

        func edge(_ index: Int) -> BRepSewingEdge {
            BRepSewingEdge(stableID: "native-trim-\(index)", curve: curves[index],
                startParameter: parameters[index * 2], endParameter: parameters[index * 2 + 1],
                startPoint: points[index * 2], endPoint: points[index * 2 + 1],
                surfaceParameterCurve: pcurves[index])
        }
    }

    private func pair() throws -> Pair {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .appendingPathComponent("Fixtures/NativeTrim19.json")
        return try JSONDecoder().decode(Pair.self, from: Data(contentsOf: url))
    }

    @Test func sourceBoundaryRetainsSurfaceCorrespondence() throws {
        let pair = try pair()
        for index in 0..<2 {
            let edge = pair.edge(index)
            try edge.validate(on: pair.surface, tolerance: tolerance)
            for fraction in stride(from: 0.0, through: 1.0, by: 0.0625) {
                let uv = try edge.surfaceParameterCurve.parameter(atNormalizedFraction: fraction, tolerance: tolerance)
                let surfacePoint = try pair.surface.point(u: uv.u, v: uv.v, tolerance: tolerance)
                let point = try edge.curve.point(at: edge.startParameter
                    + (edge.endParameter - edge.startParameter) * fraction, tolerance: tolerance)
                #expect((point - surfacePoint).length <= tolerance.distance)
            }
        }
    }

    @Test func contactCrossesNativeBoundaryAtItsEndpoint() throws {
        let pair = try pair()
        let contact = pair.edge(1)
        let reversed = BRepSewingEdge(stableID: "reversed-contact", curve: contact.curve,
            startParameter: contact.endParameter, endParameter: contact.startParameter,
            startPoint: contact.endPoint, endPoint: contact.startPoint,
            surfaceParameterCurve: try contact.surfaceParameterCurve.reversed(tolerance: tolerance))
        for edges in [(pair.edge(0), contact), (contact, pair.edge(0)), (pair.edge(0), reversed)] {
            let result = try ExactTrimEdgeIntersector().intersections(
                edges.0, edges.1, sharedSurface: pair.surface, tolerance: tolerance)
            guard case .subdivisionPoints(let points) = result else {
                Issue.record("The contact and source edge are not coincident."); return
            }
            #expect(points.count == 1)
            #expect(points.contains { ($0 - contact.startPoint).length <= tolerance.distance })
        }
    }

    @Test func boundaryTrimExcludesTheContact() throws {
        let pair = try pair()
        let source = pair.edge(0)
        let trimmed = BRepSewingEdge(stableID: "trimmed-source", curve: source.curve,
            startParameter: 0, endParameter: 0.5, startPoint: source.startPoint,
            endPoint: try source.curve.point(at: 0.5, tolerance: tolerance),
            surfaceParameterCurve: .constantU(u: 1, vStart: 0, vEnd: 0.5))
        let result = try ExactTrimEdgeIntersector().intersections(
            trimmed, pair.edge(1), sharedSurface: pair.surface, tolerance: tolerance)
        guard case .subdivisionPoints(let points) = result else {
            Issue.record("Disjoint trimmed edges cannot be coincident."); return
        }
        #expect(points.isEmpty)
    }

    @Test func separatedIsoparametricBoundaryExcludesTheWholeContact() throws {
        let pair = try pair()
        let uv = SurfaceParameterCurve.constantV(v: 0, uStart: 0, uEnd: 1)
        let curve = Curve3D.surfaceLift(.init(surface: pair.surface, parameterCurve: uv))
        let boundary = BRepSewingEdge(stableID: "opposite-boundary", curve: curve,
            startParameter: 0, endParameter: 1,
            startPoint: try curve.point(at: 0, tolerance: tolerance),
            endPoint: try curve.point(at: 1, tolerance: tolerance), surfaceParameterCurve: uv)
        let contact = pair.edge(1)
        let reversed = try BRepSewingPatchOrientationAdapter().reversed(contact, tolerance: tolerance)
        for edges in [(boundary, contact), (contact, boundary), (boundary, reversed)] {
            let result = try ExactTrimEdgeIntersector().intersections(
                edges.0, edges.1, sharedSurface: pair.surface, tolerance: tolerance)
            guard case .subdivisionPoints(let points) = result else {
                Issue.record("Separated coordinate ranges cannot represent coincident curves."); return
            }
            #expect(points.isEmpty)
        }
    }

    @Test func contactHasMonotoneBoundaryCoordinate() throws {
        let pair = try pair()
        guard case .constantU = pair.pcurves[0],
              case .offsetSurfaceImage(let image) = pair.pcurves[1],
              case .certifiedImplicit(let curve) = image.source else {
            Issue.record("The captured boundary must retain its native chart."); return
        }
        let encloser = try ImplicitCurveIntervalJetEncloser(
            intersection: curve.intersection, tolerance: tolerance)
        let jet = try encloser.parameterIntervalJet(of: curve.intersection,
            over: ScalarInterval(lower: min(curve.startFraction, curve.endFraction),
                                 upper: max(curve.startFraction, curve.endFraction)), tolerance: tolerance)
        let coordinate: SurfaceIntersectionParameterCoordinate = curve.role == .first ? .firstU : .secondU
        let derivative = jet[coordinate].firstDerivative
        #expect(derivative.lower > 0 || derivative.upper < 0)
        let start = try pair.pcurves[1].startParameter(tolerance: tolerance)
        let end = try pair.pcurves[1].endParameter(tolerance: tolerance)
        #expect(start.u == 1 || end.u == 1)
    }
}
