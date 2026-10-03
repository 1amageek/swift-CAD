import Foundation
import CADCore
import CADIR

/// Column-major affine transform with invocation-owned storage.
struct MeshPlacement {
    var values: [Double]
    static let identity = MeshPlacement(values: [1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1])

    init(values: [Double]) { self.values = values }

    func multiplied(by other: MeshPlacement) -> MeshPlacement {
        var result = [Double](repeating: 0, count: 16)
        for c in 0..<4 {
            for r in 0..<4 {
                for k in 0..<4 { result[c * 4 + r] += values[k * 4 + r] * other.values[c * 4 + k] }
            }
        }
        return MeshPlacement(values: result)
    }

    static func translation(_ v: [Double]) -> MeshPlacement {
        var m = identity; m.values[12] = v[0]; m.values[13] = v[1]; m.values[14] = v[2]; return m
    }

    static func scale(_ v: [Double]) -> MeshPlacement {
        var m = identity; m.values[0] = v[0]; m.values[5] = v[1]; m.values[10] = v[2]; return m
    }

    static func quaternion(_ q: [Double]) throws -> MeshPlacement {
        let norm = q.reduce(0) { $0 + $1 * $1 }
        guard norm.isFinite, abs(norm - 1) < 1e-5 else {
            throw ImportError.invalidData("glTF rotation must be a unit quaternion.")
        }
        let x = q[0], y = q[1], z = q[2], w = q[3]
        return MeshPlacement(values: [
            1-2*(y*y+z*z), 2*(x*y+z*w), 2*(x*z-y*w), 0,
            2*(x*y-z*w), 1-2*(x*x+z*z), 2*(y*z+x*w), 0,
            2*(x*z+y*w), 2*(y*z-x*w), 1-2*(x*x+y*y), 0,
            0, 0, 0, 1
        ])
    }

    static func axisAngle(_ v: [Double]) throws -> MeshPlacement {
        let length = sqrt(v[0]*v[0] + v[1]*v[1] + v[2]*v[2])
        guard length > 0, length.isFinite else { throw ImportError.invalidData("Invalid VRML rotation axis.") }
        let s = sin(v[3] / 2) / length
        return try quaternion([v[0]*s, v[1]*s, v[2]*s, cos(v[3]/2)])
    }

    func applying(to mesh: Mesh, tolerance: ModelingTolerance) throws -> Mesh {
        let m = values
        guard m.count == 16, m.allSatisfy(\.isFinite), m[3] == 0, m[7] == 0, m[11] == 0, m[15] == 1 else {
            throw ImportError.invalidData("Mesh placement must be finite and affine.")
        }
        let a = Vector3D(x: m[0], y: m[1], z: m[2])
        let b = Vector3D(x: m[4], y: m[5], z: m[6])
        let c = Vector3D(x: m[8], y: m[9], z: m[10])
        let determinant = a.dot(b.cross(c))
        guard determinant.isFinite, determinant != 0 else {
            throw ImportError.invalidData("Mesh placement is singular.")
        }
        var output = mesh
        output.positions = try mesh.positions.map { p in
            try Task.checkCancellation()
            return Point3D(x: m[0]*p.x + m[4]*p.y + m[8]*p.z + m[12],
                           y: m[1]*p.x + m[5]*p.y + m[9]*p.z + m[13],
                           z: m[2]*p.x + m[6]*p.y + m[10]*p.z + m[14])
        }
        output.normals = try mesh.normals.map { n in
            try Task.checkCancellation()
            let normal = (b.cross(c)*n.x + c.cross(a)*n.y + a.cross(b)*n.z) / determinant
            guard normal.length.isFinite, normal.length > 0 else { throw ImportError.invalidData("Invalid transformed normal.") }
            return normal / normal.length
        }
        if determinant < 0 {
            for i in stride(from: 0, to: output.indices.count, by: 3) {
                output.indices.swapAt(i + 1, i + 2)
            }
        }
        try validateImportedMesh(output, formatName: "Standard mesh", tolerance: tolerance)
        return output
    }
}
