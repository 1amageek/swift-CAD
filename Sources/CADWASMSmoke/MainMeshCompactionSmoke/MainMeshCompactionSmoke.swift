import CADCore
import CADIR
import CADKernel
import CADTopology

enum MainMeshCompactionSmoke {
    static func run(model: BRepModel, tolerance: ModelingTolerance) throws {
        let original = model
        let options = TessellationOptions.standard
        let meshes = try MeshTessellator(tolerance: tolerance).tessellate(
            model: model,
            options: options
        )
        try require(meshes.count == 1, tolerance: tolerance, message: "Expected one published box mesh.")
        guard let mesh = meshes.values.first else {
            throw failure(tolerance: tolerance, message: "The box mesh is missing.")
        }
        try require(
            mesh.indices.count == 36 && mesh.normals.count == mesh.positions.count,
            tolerance: tolerance,
            message: "The box mesh has incorrect triangle or normal counts."
        )
        try require(
            mesh.faceRuns.count == 6 && mesh.faceRuns.allSatisfy { $0.triangleCount == 2 }
                && Set(mesh.faceRuns.map { $0.faceID }) == Set(model.faces.keys),
            tolerance: tolerance,
            message: "The box mesh lost complete generating-face provenance."
        )

        var referenced = Set<Int>()
        for index in mesh.indices {
            guard let nativeIndex = Int(exactly: index), mesh.positions.indices.contains(nativeIndex) else {
                throw failure(tolerance: tolerance, message: "The box mesh contains an unrepresentable or invalid index.")
            }
            referenced.insert(nativeIndex)
        }
        try require(
            referenced.count == mesh.positions.count,
            tolerance: tolerance,
            message: "The compacted box mesh retains an unreferenced position."
        )
        let dimensions = [0.04, 0.02, 0.01]
        for point in mesh.positions {
            for (axis, coordinate) in [point.x, point.y, point.z].enumerated() {
                try require(
                    abs(coordinate) <= 1.0e-12 || abs(coordinate - dimensions[axis]) <= 1.0e-12,
                    tolerance: tolerance,
                    message: "The box mesh position differs from the literal box corners."
                )
            }
        }
        var planes = Set<Int>()
        for offset in stride(from: 0, to: mesh.indices.count, by: 3) {
            guard let i0 = Int(exactly: mesh.indices[offset]),
                  let i1 = Int(exactly: mesh.indices[offset + 1]),
                  let i2 = Int(exactly: mesh.indices[offset + 2]) else {
                throw failure(tolerance: tolerance, message: "A box triangle index is unrepresentable.")
            }
            let points = [mesh.positions[i0], mesh.positions[i1], mesh.positions[i2]]
            var plane: Int?
            var expected = Vector3D(x: 0, y: 0, z: 0)
            for axis in 0..<3 {
                for side in 0..<2 {
                    let coordinate = side == 0 ? 0.0 : dimensions[axis]
                    if points.allSatisfy({ point in
                        let value = axis == 0 ? point.x : (axis == 1 ? point.y : point.z)
                        return abs(value - coordinate) <= 1.0e-12
                    }) {
                        try require(plane == nil, tolerance: tolerance, message: "A box triangle is degenerate.")
                        plane = axis * 2 + side
                        let sign = side == 0 ? -1.0 : 1.0
                        expected = Vector3D(
                            x: axis == 0 ? sign : 0,
                            y: axis == 1 ? sign : 0,
                            z: axis == 2 ? sign : 0
                        )
                    }
                }
            }
            guard let plane else {
                throw failure(tolerance: tolerance, message: "A box triangle does not lie on a literal box plane.")
            }
            planes.insert(plane)
            for index in [i0, i1, i2] {
                try require(
                    (mesh.normals[index] - expected).length <= 1.0e-12,
                    tolerance: tolerance,
                    message: "A box triangle normal differs from its literal outward normal."
                )
            }
            try require(
                (points[1] - points[0]).cross(points[2] - points[0]).dot(expected) > 0,
                tolerance: tolerance,
                message: "A box triangle has incorrect outward winding."
            )
        }
        try require(planes.count == 6, tolerance: tolerance, message: "The mesh omits a literal box plane.")
        try require(model == original, tolerance: tolerance, message: "Tessellation changed the original box.")
        print("MAIN_MESH_COMPACTION_OK")

        var limits = TessellationLimits.standard
        limits.maximumVertexCount = 1
        do {
            _ = try MeshTessellator(tolerance: tolerance, limits: limits).tessellate(model: model, options: options)
        } catch let error as TessellationError {
            guard case let .resourceExhausted(.vertexCount, requested, limit) = error,
                  requested > 1, limit == 1 else {
                throw error
            }
            try require(model == original, tolerance: tolerance, message: "Resource refusal changed the original box.")
            print("MAIN_MESH_STORAGE_REFUSAL_OK")
            return
        }
        throw failure(tolerance: tolerance, message: "The box mesh ignored the original vertex storage ceiling.")
    }

    private static func require(_ condition: Bool, tolerance: ModelingTolerance, message: String) throws {
        guard condition else { throw failure(tolerance: tolerance, message: message) }
    }

    private static func failure(tolerance: ModelingTolerance, message: String) -> KernelError {
        KernelError(phase: .validation, code: .topologyFailure, tolerance: tolerance, message: message)
    }
}
