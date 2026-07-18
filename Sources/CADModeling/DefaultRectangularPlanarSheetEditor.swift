import CADCore
import CADGeometry
import CADIR
import CADTopology

package struct DefaultRectangularPlanarSheetEditor: RectangularPlanarSheetEditing {
    package init() {}

    package func bounds(
        bodyID: BodyID,
        model: BRepModel,
        tolerance: ModelingTolerance
    ) throws -> PlanarSheetParameterBounds {
        let sheet = try details(bodyID: bodyID, model: model, tolerance: tolerance)
        return sheet.bounds
    }

    package func resize(
        bodyID: BodyID,
        to bounds: PlanarSheetParameterBounds,
        model: inout BRepModel,
        tolerance: ModelingTolerance
    ) throws {
        guard bounds.upperU - bounds.lowerU > tolerance.distance,
              bounds.upperV - bounds.lowerV > tolerance.distance else {
            throw KernelError(
                phase: .evaluation,
                code: .invalidInput,
                tolerance: tolerance,
                message: "Planar sheet resize requires positive U and V spans."
            )
        }
        let sheet = try details(bodyID: bodyID, model: model, tolerance: tolerance)
        let surface = Surface3D.plane(sheet.plane)
        for corner in sheet.corners {
            let u = corner.isUpperU ? bounds.upperU : bounds.lowerU
            let v = corner.isUpperV ? bounds.upperV : bounds.lowerV
            guard var vertex = model.vertices[corner.vertexID] else {
                throw TopologyError.missingReference("Planar sheet resize vertex is missing.")
            }
            vertex.point = try surface.point(u: u, v: v, tolerance: tolerance)
            model.vertices[corner.vertexID] = vertex
        }
    }

    private func details(
        bodyID: BodyID,
        model: BRepModel,
        tolerance: ModelingTolerance
    ) throws -> SheetDetails {
        guard let body = model.bodies[bodyID],
              body.kind == .sheet,
              body.shellIDs.count == 1,
              let shellID = body.shellIDs.first,
              let shell = model.shells[shellID],
              shell.faceIDs.count == 1,
              let faceID = shell.faceIDs.first,
              let face = model.faces[faceID],
              face.loops.count == 1,
              let loopID = face.loops.first,
              let loop = model.loops[loopID],
              loop.role == .outer,
              loop.coedges.count == 4,
              case let .plane(plane) = model.geometry.surfaces[face.surfaceID] else {
            throw KernelError(
                phase: .evaluation,
                code: .unsupportedCapability,
                tolerance: tolerance,
                message: "Rectangular planar sheet editing requires one four-edge planar sheet face."
            )
        }
        let surface = Surface3D.plane(plane)
        var parameters: [(vertexID: VertexID, u: Double, v: Double)] = []
        for coedge in loop.coedges {
            guard let edge = model.edges[coedge.edgeID],
                  case .line = model.geometry.curves[edge.curveID] else {
                throw KernelError(
                    phase: .evaluation,
                    code: .unsupportedCapability,
                    tolerance: tolerance,
                    message: "Rectangular planar sheet editing requires straight boundary edges."
                )
            }
            let vertexID = coedge.orientation == .forward ? edge.startVertexID : edge.endVertexID
            guard let point = model.vertices[vertexID]?.point else {
                throw TopologyError.missingReference("Rectangular planar sheet vertex is missing.")
            }
            let projection = try surface.parameterProjection(of: point, tolerance: tolerance)
            parameters.append((vertexID, projection.u, projection.v))
        }
        let lowerU = parameters.map(\.u).min() ?? 0.0
        let upperU = parameters.map(\.u).max() ?? 0.0
        let lowerV = parameters.map(\.v).min() ?? 0.0
        let upperV = parameters.map(\.v).max() ?? 0.0
        guard upperU - lowerU > tolerance.distance,
              upperV - lowerV > tolerance.distance else {
            throw KernelError(
                phase: .topology,
                code: .topologyFailure,
                tolerance: tolerance,
                message: "Rectangular planar sheet parameter bounds are degenerate."
            )
        }
        var combinations = Set<String>()
        let corners = try parameters.map { parameter -> Corner in
            let isUpperU = try endpointSide(
                parameter.u,
                lower: lowerU,
                upper: upperU,
                tolerance: tolerance
            )
            let isUpperV = try endpointSide(
                parameter.v,
                lower: lowerV,
                upper: upperV,
                tolerance: tolerance
            )
            combinations.insert("\(isUpperU):\(isUpperV)")
            return Corner(
                vertexID: parameter.vertexID,
                isUpperU: isUpperU,
                isUpperV: isUpperV
            )
        }
        guard combinations.count == 4 else {
            throw KernelError(
                phase: .evaluation,
                code: .unsupportedCapability,
                tolerance: tolerance,
                message: "Planar sheet boundary must be an axis-aligned rectangle in surface parameters."
            )
        }
        return SheetDetails(
            plane: plane,
            bounds: PlanarSheetParameterBounds(
                lowerU: lowerU,
                upperU: upperU,
                lowerV: lowerV,
                upperV: upperV
            ),
            corners: corners
        )
    }

    private func endpointSide(
        _ value: Double,
        lower: Double,
        upper: Double,
        tolerance: ModelingTolerance
    ) throws -> Bool {
        if abs(value - lower) <= tolerance.distance {
            return false
        }
        if abs(value - upper) <= tolerance.distance {
            return true
        }
        throw KernelError(
            phase: .evaluation,
            code: .unsupportedCapability,
            residual: min(abs(value - lower), abs(value - upper)),
            tolerance: tolerance,
            message: "Planar sheet vertex is not on a rectangular parameter corner."
        )
    }

    private struct SheetDetails {
        let plane: Plane3D
        let bounds: PlanarSheetParameterBounds
        let corners: [Corner]
    }

    private struct Corner {
        let vertexID: VertexID
        let isUpperU: Bool
        let isUpperV: Bool
    }
}
