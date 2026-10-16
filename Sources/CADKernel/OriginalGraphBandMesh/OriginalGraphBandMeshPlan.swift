import CADCore
import CADGeometry
import CADIR
import CADTopology

/// The same source-bound recipe owns preflight counts and complete facet emission.
struct OriginalGraphBandMeshPlan: Sendable {
    struct UseBinding: Sendable {
        let coedge: Coedge
        let edge: Edge
        let curve: Curve3D
        let startVertex: Vertex
        let endVertex: Vertex
        let from: Double
        let to: Double
        let pcurve: SurfaceParameterCurve
        let certificate: OriginalCurveSurfaceCorrespondenceCertificate
    }

    struct Grid: Sendable {
        let cellIndex: Int
        let uSteps: Int
    }

    struct Tip: Sendable {
        let joinIndex: Int
        let panelIndex: Int
        let cellIndex: Int
        let isLeft: Bool
    }

    /// Bounded temporary inputs are reused without retaining a geometric success.
    struct FacetScratch {
        private(set) var stations: [OriginalGraphBandReceipt.Station] = []
        private(set) var ids: [UInt32] = []
        private(set) var positions: [Point3D] = []
        private(set) var normals: [Vector3D] = []

        init(using execution: inout OriginalQueryExecution,
             tolerance: ModelingTolerance) throws {
            // All four three-slot buffers are admitted before allocating storage.
            for _ in 0..<12 { try execution.visitGeometricCell(depth: 0) }
            stations.reserveCapacity(3)
            ids.reserveCapacity(3)
            positions.reserveCapacity(3)
            normals.reserveCapacity(3)
        }

        mutating func bindReference(
            _ a: OriginalGraphBandReceipt.Station,
            _ b: OriginalGraphBandReceipt.Station,
            _ c: OriginalGraphBandReceipt.Station,
            ids: (UInt32, UInt32, UInt32), positions: [Point3D]
        ) {
            if stations.isEmpty {
                stations.append(a); stations.append(b); stations.append(c)
            } else {
                stations[0] = a; stations[1] = b; stations[2] = c
            }
            bindFacet(ids: ids, normals: (a.normal, b.normal, c.normal), positions: positions)
        }

        mutating func bindFacet(
            ids next: (UInt32, UInt32, UInt32),
            normals raw: (Vector3D, Vector3D, Vector3D), positions source: [Point3D]
        ) {
            if ids.isEmpty {
                ids.append(next.0); ids.append(next.1); ids.append(next.2)
                positions.append(source[Int(next.0)])
                positions.append(source[Int(next.1)])
                positions.append(source[Int(next.2)])
                normals.append(raw.0); normals.append(raw.1); normals.append(raw.2)
            } else {
                ids[0] = next.0; ids[1] = next.1; ids[2] = next.2
                positions[0] = source[Int(next.0)]
                positions[1] = source[Int(next.1)]
                positions[2] = source[Int(next.2)]
                normals[0] = raw.0; normals[1] = raw.1; normals[2] = raw.2
            }
        }
    }

    let face: Face
    let loop: Loop
    let options: TessellationOptions
    let tolerance: ModelingTolerance
    let correspondenceOptions: CurveSurfaceCorrespondenceValidationOptions
    let uses: [UseBinding]
    let receipt: OriginalGraphBandReceipt
    let grids: [Grid]
    let wSteps: Int
    let tips: [Tip]
    let vertexCount: Int
    let indexCount: Int
    let proofContribution: OriginalQueryContributionHandle

    func validateBinding(model: BRepModel, faceID: FaceID,
                         options: TessellationOptions, tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution) throws {
        guard self.options == options, self.tolerance == tolerance,
              face.id == faceID, model.faces[faceID] == face,
              model.loops[loop.id] == loop,
              model.geometry.surfaces[face.surfaceID] == .bSpline(receipt.input.surface) else {
            throw KernelError(phase: .geometry, code: .invalidInput, tolerance: tolerance,
                              message: "A retained graph mesh plan requires its exact original face and options.")
        }
        for use in uses {
            try execution.checkpoint()
            guard model.edges[use.edge.id] == use.edge,
                  model.geometry.curves[use.edge.curveID] == use.curve,
                  model.vertices[use.startVertex.id] == use.startVertex,
                  model.vertices[use.endVertex.id] == use.endVertex else {
                throw KernelError(phase: .geometry, code: .invalidInput, tolerance: tolerance,
                                  message: "A retained graph mesh plan has foreign original edge or vertex data.")
            }
            try use.certificate.validateBinding(curve: use.curve, from: use.from, to: use.to,
                surface: .bSpline(receipt.input.surface), parameterCurve: use.pcurve,
                options: correspondenceOptions, tolerance: tolerance, using: &execution)
        }
    }
}
