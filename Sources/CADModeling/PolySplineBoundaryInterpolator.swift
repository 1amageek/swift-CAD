import Foundation
import CADCore

/// Interpolate Boundary Exactly for PolySplines of a general mesh: a boundary runs on the cubic
/// B-spline of its vertices, which only passes near them, so the boundary vertices are replaced by
/// the control points whose cubic B-spline passes through them — (P₋ + 4P + P₊)/6 = V at each
/// smooth boundary vertex, a kept corner held where it is. The interior then follows the moved
/// boundary as the patch rules take it; the refinement keeps the same boundary curve.
package struct PolySplineBoundaryInterpolator {
    private let tolerance: ModelingTolerance

    package init(tolerance: ModelingTolerance) {
        self.tolerance = tolerance
    }

    /// `positions` with the boundary vertices of `faces` moved so the boundary passes through
    /// their old places; a vertex on one face is a kept corner unless `roundsCorners`.
    package func interpolating(positions: [Point3D], faces: [[Int]], roundsCorners: Bool) -> [Point3D] {
        var uses: [[Int]: Int] = [:]
        var facesAt: [Int: Int] = [:]
        var next: [Int: Int] = [:]
        for face in faces {
            for k in face.indices {
                let (a, b) = (face[k], face[(k + 1) % face.count])
                uses[[min(a, b), max(a, b)], default: 0] += 1
                facesAt[a, default: 0] += 1
            }
        }
        // Boundary edges run once, in their face's direction.
        for face in faces {
            for k in face.indices {
                let (a, b) = (face[k], face[(k + 1) % face.count])
                if uses[[min(a, b), max(a, b)]] == 1 { next[a] = b }
            }
        }
        var previous: [Int: Int] = [:]
        for (a, b) in next { previous[b] = a }
        let held = { (vertex: Int) in roundsCorners == false && facesAt[vertex] == 1 }
        var result = positions
        // Jacobi sweeps: the system is strictly diagonally dominant (4 against 1 + 1), halving
        // the error each sweep.
        let smooth = next.keys.filter { held($0) == false }.sorted()
        guard smooth.isEmpty == false else { return positions }
        let scale = positions.reduce(0) { max($0, ($1 - .origin).length) }
        for _ in 0..<200 {
            var moved = result
            var change = 0.0
            for vertex in smooth {
                guard let before = previous[vertex], let after = next[vertex] else { continue }
                let p = (positions[vertex] - .origin) * 1.5 - ((result[before] - .origin) + (result[after] - .origin)) * 0.25
                let point = Point3D.origin + p
                change = max(change, (point - result[vertex]).length)
                moved[vertex] = point
            }
            result = moved
            if change <= max(scale, 1) * Double.ulpOfOne * 16 { break }
        }
        return result
    }
}
