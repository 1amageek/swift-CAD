import HashTreeCollections
import CADCore
import CADGeometry
import CADIR
import CADTopology

package struct BRepModelCombiner {
    package init() {}

    package func combined(_ models: [BRepModel]) throws -> BRepModel {
        var execution = OriginalQueryExecution(budget: try OriginalQueryBudget(),
            limits: try .init(maximumValueDepth: 32, maximumCoefficientDepth: 32))
        return try combined(models, using: &execution)
    }

    package func combined(_ models: [BRepModel], using execution: inout OriginalQueryExecution) throws -> BRepModel {
        try execution.consumeWork(1)
        guard let first = models.first else { return BRepModel() }
        var result = first
        for model in models.dropFirst() {
            try execution.consumeWork(1)
            try merge(model, into: &result, using: &execution)
        }
        return result
    }

    package func merge(_ source: BRepModel, into destination: inout BRepModel) throws {
        var execution = OriginalQueryExecution(budget: try OriginalQueryBudget(),
            limits: try .init(maximumValueDepth: 32, maximumCoefficientDepth: 32))
        try merge(source, into: &destination, using: &execution)
    }

    package func merge(_ source: BRepModel, into destination: inout BRepModel, using execution: inout OriginalQueryExecution) throws {
        try execution.consumeWork(1)
        for (key, value) in source.geometry.curves {
            try execution.consumeWork(1)
            try requireVacant(destination.geometry.curves[key], label: "curve")
            try execution.retainStorage(bytes: MemoryLayout<(CurveID, Curve3D)>.stride)
            destination.geometry.curves[key] = value
        }
        for (key, value) in source.geometry.surfaces {
            try execution.consumeWork(1)
            try requireVacant(destination.geometry.surfaces[key], label: "surface")
            try execution.retainStorage(bytes: MemoryLayout<(SurfaceID, Surface3D)>.stride)
            destination.geometry.surfaces[key] = value
        }
        for (key, value) in source.vertices {
            try execution.consumeWork(1)
            try requireVacant(destination.vertices[key], label: "vertex")
            try execution.retainStorage(bytes: MemoryLayout<(VertexID, Vertex)>.stride)
            destination.vertices[key] = value
        }
        for (key, value) in source.edges {
            try execution.consumeWork(1)
            try requireVacant(destination.edges[key], label: "edge")
            try execution.retainStorage(bytes: MemoryLayout<(EdgeID, Edge)>.stride)
            destination.edges[key] = value
        }
        for (key, value) in source.loops {
            try execution.consumeWork(1)
            try requireVacant(destination.loops[key], label: "loop")
            try execution.retainStorage(bytes: MemoryLayout<(LoopID, Loop)>.stride)
            destination.loops[key] = value
        }
        for (key, value) in source.faces {
            try execution.consumeWork(1)
            try requireVacant(destination.faces[key], label: "face")
            try execution.retainStorage(bytes: MemoryLayout<(FaceID, Face)>.stride)
            destination.faces[key] = value
        }
        for (key, value) in source.shells {
            try execution.consumeWork(1)
            try requireVacant(destination.shells[key], label: "shell")
            try execution.retainStorage(bytes: MemoryLayout<(ShellID, Shell)>.stride)
            destination.shells[key] = value
        }
        for (key, value) in source.bodies {
            try execution.consumeWork(1)
            try requireVacant(destination.bodies[key], label: "body")
            try execution.retainStorage(bytes: MemoryLayout<(BodyID, Body)>.stride)
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
