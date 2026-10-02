import Foundation
import CADCore
import CADGeometry
import CADIR
import CADModeling
import CADTopology

/// Align Surface's Analysis: the aligned sheet measured against the reference along the reference
/// edge (placed in the sheet's frame) at 32 interior points — the largest distance from the edge
/// to the sheet (G0), the largest angle between their normals there (G1), and the largest
/// difference of their normal curvatures across the edge (G2), each against the feature's
/// continuity: the modeling distance, 10⁻⁶ rad and 10⁻³ m⁻¹ (sampling noise of an exact match).
public struct SurfaceAlignAnalyzer {
    public init() {}

    public func analyze(_ featureID: FeatureID, in document: EvaluatedDocument) throws -> SquareSideAnalysis {
        let tolerance = document.configuration.tolerance
        guard let node = document.document.designGraph.nodes[featureID], case let .surfaceAlign(align) = node.operation else {
            throw refusal("Analysis takes an Align Surface feature.", featureID, tolerance)
        }
        let model = document.brep
        guard let sheet = document.subshapes.entries.compactMap({ key, value -> Surface3D? in
            guard key.featureID == featureID, case let .face(id) = value, let face = model.faces[id] else { return nil }
            return model.geometry.surfaces[face.surfaceID]
        }).first else {
            throw refusal("The aligned sheet has no face to analyze.", featureID, tolerance)
        }
        let resolved = try StableSubshapeResolver().topologyReference(for: align.referenceEdge, model: model, subshapes: document.subshapes,
                                                                     lineage: document.lineage, tolerance: tolerance)
        guard case let .edge(edgeID) = resolved, let edge = model.edges[edgeID], let curve = model.geometry.curves[edge.curveID],
              let trim = edge.trim,
              let face = model.faces.values.first(where: { face in
                  face.loops.contains { model.loops[$0]?.coedges.contains { $0.edgeID == edgeID } ?? false }
              }), let reference = model.geometry.surfaces[face.surfaceID] else {
            throw refusal("The reference edge no longer borders a face.", featureID, tolerance)
        }
        let placement = align.referencePlacement
        func placed(_ point: Point3D) -> Point3D { placement.map { $0.applying(to: point) } ?? point }
        func placed(_ vector: Vector3D) -> Vector3D { placement.map { $0.applying(to: vector) } ?? vector }
        var position = 0.0, angle = 0.0, curvature = 0.0
        for k in 0..<32 {
            let t = trim.startParameter + (trim.endParameter - trim.startParameter) * (Double(k) + 0.5) / 32
            let point = try curve.point(at: t, tolerance: tolerance)
            let referenceUV = try reference.parameterProjection(of: point, tolerance: tolerance)
            let there = try reference.differentialGeometry(u: referenceUV.u, v: referenceUV.v, tolerance: tolerance)
            let target = placed(point)
            let projected = try sheet.parameterProjection(of: target, tolerance: tolerance)
            let here = try sheet.differentialGeometry(u: projected.u, v: projected.v, tolerance: tolerance)
            position = max(position, (here.position - target).length)
            let referenceNormal = placed(there.normal)
            angle = max(angle, acos(min(1, abs(here.normal.dot(referenceNormal)))))
            guard align.continuity == .curvature else { continue }
            // Across the edge: the sheet's tangent square to the edge's direction.
            let along = placed(try curve.differentialGeometry(at: t, tolerance: tolerance).firstDerivative)
            let across = try here.normal.cross(along).normalized(tolerance: tolerance.distance)
            let aligned = referenceNormal.dot(here.normal) >= 0 ? 1.0 : -1.0
            let sheetCurvature = try normalCurvature(here.tangentU, here.tangentV, here.secondDerivativeUU, here.secondDerivativeUV,
                                                     here.secondDerivativeVV, normal: here.normal, direction: across)
            let referenceCurvature = try normalCurvature(placed(there.tangentU), placed(there.tangentV), placed(there.secondDerivativeUU),
                                                         placed(there.secondDerivativeUV), placed(there.secondDerivativeVV),
                                                         normal: referenceNormal * aligned, direction: across)
            curvature = max(curvature, abs(sheetCurvature - referenceCurvature))
        }
        let measuresAngle = align.continuity != .positional
        return SquareSideAnalysis(
            side: 0, position: position, positionLimit: tolerance.distance,
            angle: measuresAngle ? angle : nil, angleLimit: measuresAngle ? 1e-6 : nil,
            curvature: align.continuity == .curvature ? curvature : nil, curvatureLimit: align.continuity == .curvature ? 1e-3 : nil
        )
    }

    private func normalCurvature(_ su: Vector3D, _ sv: Vector3D, _ suu: Vector3D, _ suv: Vector3D, _ svv: Vector3D,
                                 normal: Vector3D, direction: Vector3D) throws -> Double {
        let (e, f, g) = (su.dot(su), su.dot(sv), sv.dot(sv))
        let determinant = e * g - f * f
        guard determinant > 0 else {
            throw KernelError(phase: .evaluation, code: .invalidInput, tolerance: nil, message: "A degenerate surface has no curvature.")
        }
        let (p, q) = (direction.dot(su), direction.dot(sv))
        let (a, b) = ((g * p - f * q) / determinant, (e * q - f * p) / determinant)
        return (suu.dot(normal) * a * a + 2 * suv.dot(normal) * a * b + svv.dot(normal) * b * b) / (e * a * a + 2 * f * a * b + g * b * b)
    }

    private func refusal(_ message: String, _ featureID: FeatureID, _ tolerance: ModelingTolerance) -> KernelError {
        KernelError(phase: .evaluation, code: .invalidInput, featureID: featureID, tolerance: tolerance, message: message)
    }
}
