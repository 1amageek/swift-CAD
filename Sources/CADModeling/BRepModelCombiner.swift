import CADCore
import CADIR
import CADTopology

package struct BRepModelCombiner {
    package init() {}

    package func combined(_ models: [BRepModel]) throws -> BRepModel {
        guard let first = models.first else { return BRepModel() }
        var result = first
        for model in models.dropFirst() {
            try merge(model, into: &result)
        }
        return result
    }

    package func merge(_ source: BRepModel, into destination: inout BRepModel) throws {
        for (key, value) in source.geometry.curves {
            try requireVacant(destination.geometry.curves[key], label: "curve")
            destination.geometry.curves[key] = value
        }
        for (key, value) in source.geometry.surfaces {
            try requireVacant(destination.geometry.surfaces[key], label: "surface")
            destination.geometry.surfaces[key] = value
        }
        for (key, value) in source.vertices {
            try requireVacant(destination.vertices[key], label: "vertex")
            destination.vertices[key] = value
        }
        for (key, value) in source.edges {
            try requireVacant(destination.edges[key], label: "edge")
            destination.edges[key] = value
        }
        for (key, value) in source.loops {
            try requireVacant(destination.loops[key], label: "loop")
            destination.loops[key] = value
        }
        for (key, value) in source.faces {
            try requireVacant(destination.faces[key], label: "face")
            destination.faces[key] = value
        }
        for (key, value) in source.shells {
            try requireVacant(destination.shells[key], label: "shell")
            destination.shells[key] = value
        }
        for (key, value) in source.bodies {
            try requireVacant(destination.bodies[key], label: "body")
            destination.bodies[key] = value
        }
    }

    private func requireVacant<Value>(_ value: Value?, label: String) throws {
        guard value == nil else {
            throw KernelError(
                phase: .topology,
                code: .invalidInput,
                tolerance: nil,
                message: "B-rep model combination encountered a duplicate \(label) identity."
            )
        }
    }
}
