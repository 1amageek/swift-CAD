import Foundation
import CADCore
import CADGeometry
import CADIR
import CADModeling
import CADTopology

/// Refit Face's Analysis (Square's Refit, Plasticity's REFIT FACE labels): for each edge of each
/// refitted face, the largest distance from the edge's curve to the new surface's boundary along it
/// — the face keeps its edges, and its new surface's boundary runs along them only as closely as
/// its Degree and Spans let it. The edge's curve is sampled at 33 points, each measured to the
/// nearest point of the boundary stretch its trimming curve names, and judged against the modeling
/// distance; the analysis is shown at the edge's middle.
public struct FaceRefitAnalyzer {
    public init() {}

    /// One analysis per edge, faces in the feature's order and edges in their loop's.
    public func analyze(_ featureID: FeatureID, in document: EvaluatedDocument) throws -> [SquareSideAnalysis] {
        let tolerance = document.configuration.tolerance
        guard let node = document.document.designGraph.nodes[featureID], case let .faceRebuild(rebuild) = node.operation,
              case .square = rebuild.method else {
            throw refusal("Refit analysis takes a Rebuild Face refitted by Square.", featureID, tolerance)
        }
        let model = document.brep
        let resolver = StableSubshapeResolver()
        var result: [SquareSideAnalysis] = []
        for reference in rebuild.faces {
            guard case let .face(faceID) = try resolver.topologyReference(
                for: reference, model: model, subshapes: document.subshapes, lineage: document.lineage, tolerance: tolerance
            ), let face = model.faces[faceID], let surface = model.geometry.surfaces[face.surfaceID],
                  let loop = face.loops.first.flatMap({ model.loops[$0] }) else {
                throw refusal("A refitted face is not in the evaluated model.", featureID, tolerance)
            }
            for coedge in loop.coedges {
                guard let edge = model.edges[coedge.edgeID], let curve = model.geometry.curves[edge.curveID], let trim = edge.trim,
                      let pcurve = coedge.surfaceParameterCurve else {
                    throw refusal("A refitted face's edge has no curve or trimming curve.", featureID, tolerance)
                }
                func boundaryDistance(_ point: Point3D) throws -> Double {
                    func distance(_ fraction: Double) throws -> Double {
                        let parameter = try pcurve.parameter(atNormalizedFraction: fraction, tolerance: tolerance)
                        return (try surface.point(u: parameter.u, v: parameter.v, tolerance: tolerance) - point).length
                    }
                    let steps = 64
                    var best = (fraction: 0.0, distance: try distance(0))
                    for k in 1...steps {
                        let fraction = Double(k) / Double(steps)
                        let value = try distance(fraction)
                        if value < best.distance { best = (fraction, value) }
                    }
                    var a = max(0, best.fraction - 1 / Double(steps)), b = min(1, best.fraction + 1 / Double(steps))
                    let ratio = (5.0.squareRoot() - 1) / 2
                    for _ in 0..<60 {
                        let c = b - ratio * (b - a), d = a + ratio * (b - a)
                        if try distance(c) < distance(d) { b = d } else { a = c }
                    }
                    return min(best.distance, try distance(0.5 * (a + b)))
                }
                let points = try (0...32).map {
                    try curve.point(at: trim.startParameter + (trim.endParameter - trim.startParameter) * Double($0) / 32, tolerance: tolerance)
                }
                let position = try points.map(boundaryDistance).max() ?? 0
                result.append(SquareSideAnalysis(side: result.count, position: position, positionLimit: tolerance.distance, point: points[16]))
            }
        }
        return result
    }

    private func refusal(_ message: String, _ featureID: FeatureID, _ tolerance: ModelingTolerance) -> KernelError {
        KernelError(phase: .evaluation, code: .invalidInput, featureID: featureID, tolerance: tolerance, message: message)
    }
}
