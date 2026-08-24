import CADCore

/// Selects a deterministic, geometry-derived origin for shell flux integrals.
/// Topology identifiers are intentionally excluded because generated UUID order
/// must not change numeric conditioning, proof budgets, or diagnostic values.
package struct BRepShellReferencePointResolver {
    package init() {}

    package func referencePoint(
        for shell: Shell,
        in model: BRepModel,
        context: String
    ) throws -> Point3D {
        var minimum: Point3D?
        var maximum: Point3D?

        for faceID in shell.faceIDs {
            guard let face = model.faces[faceID] else {
                throw TopologyError.missingReference(
                    "\(context) references a missing face."
                )
            }
            for loopID in face.loops {
                guard let loop = model.loops[loopID] else {
                    throw TopologyError.missingReference(
                        "\(context) references a missing loop."
                    )
                }
                for coedge in loop.coedges {
                    guard let edge = model.edges[coedge.edgeID],
                          let start = model.vertices[edge.startVertexID]?.point,
                          let end = model.vertices[edge.endVertexID]?.point else {
                        throw TopologyError.missingReference(
                            "\(context) references a missing boundary vertex."
                        )
                    }
                    include(start, minimum: &minimum, maximum: &maximum)
                    include(end, minimum: &minimum, maximum: &maximum)
                }
            }
        }

        guard let minimum, let maximum else {
            throw TopologyError.openShell(shell.id)
        }
        return Point3D(
            x: minimum.x * 0.5 + maximum.x * 0.5,
            y: minimum.y * 0.5 + maximum.y * 0.5,
            z: minimum.z * 0.5 + maximum.z * 0.5
        )
    }

    private func include(
        _ point: Point3D,
        minimum: inout Point3D?,
        maximum: inout Point3D?
    ) {
        guard let currentMinimum = minimum,
              let currentMaximum = maximum else {
            minimum = point
            maximum = point
            return
        }
        minimum = Point3D(
            x: min(currentMinimum.x, point.x),
            y: min(currentMinimum.y, point.y),
            z: min(currentMinimum.z, point.z)
        )
        maximum = Point3D(
            x: max(currentMaximum.x, point.x),
            y: max(currentMaximum.y, point.y),
            z: max(currentMaximum.z, point.z)
        )
    }
}
