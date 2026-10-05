import CADCore

/// Exact original convex-planar bilinear authority, including a stationary corner.
struct OriginalBilinearEmbeddingCertificate {
    let vertices: [[ExactRationalCoefficient]]
    let normal: [ExactRationalCoefficient]

    static func proven<B: RationalAlgebraAdmitting>(_ source: BSplineSurface3D,
        usage: inout B) throws -> Self? {
        try usage.consumeExactWork(32)
        guard source.uDegree == 1, source.vDegree == 1, source.uKnots == [0, 0, 1, 1],
              source.vKnots == [0, 0, 1, 1], source.controlPoints.count == 2,
              source.controlPoints.allSatisfy({ $0.count == 2 }), source.weights == [[1, 1], [1, 1]] else { return nil }
        let points = [source.controlPoints[0][0], source.controlPoints[0][1],
                      source.controlPoints[1][1], source.controlPoints[1][0]]
        try usage.retainExactStorage(20)
        var vertices: [[ExactRationalCoefficient]] = []
        for p in points {
            vertices.append(try [p.x, p.y, p.z].map { try .originalDouble($0, usage: &usage) })
        }
        for a in 0..<4 { for b in (a + 1)..<4 {
            try usage.consumeExactWork(3)
            if vertices[a] == vertices[b] { return nil }
        } }
        var planeNormal: [ExactRationalCoefficient]?
        for axisPair in [(0, 1), (1, 2), (2, 0)] {
            var orientation = 0, zeros = 0
            var candidateNormal: [ExactRationalCoefficient]?
            for index in 0..<4 {
                let a = try subtract(vertices[(index + 1) % 4], vertices[index], usage: &usage)
                let b = try subtract(vertices[(index + 2) % 4], vertices[index], usage: &usage)
                let determinant = try a[axisPair.0].multiplied(by: b[axisPair.1], usage: &usage)
                    .subtracting(a[axisPair.1].multiplied(by: b[axisPair.0], usage: &usage), usage: &usage)
                if determinant.isZero { zeros += 1; continue }
                let sign = determinant.isPositive ? 1 : -1
                if orientation != 0, orientation != sign { orientation = 0; zeros = 4; break }
                orientation = sign
                if candidateNormal == nil { candidateNormal = try cross(a, b, usage: &usage) }
            }
            if orientation != 0, zeros <= 1, let candidateNormal {
                planeNormal = candidateNormal; break
            }
        }
        guard let normal = planeNormal else { return nil }
        for vertex in vertices {
            let displacement = try subtract(vertex, vertices[0], usage: &usage)
            guard try dot(normal, displacement, usage: &usage).isZero else { return nil }
        }
        return .init(vertices: vertices, normal: normal)
    }

    static func subtract<B: RationalAlgebraAdmitting>(_ a: [ExactRationalCoefficient],
        _ b: [ExactRationalCoefficient], usage: inout B) throws -> [ExactRationalCoefficient] {
        try usage.retainExactStorage(3)
        return try (0..<3).map { try a[$0].subtracting(b[$0], usage: &usage) }
    }
    static func cross<B: RationalAlgebraAdmitting>(_ a: [ExactRationalCoefficient],
        _ b: [ExactRationalCoefficient], usage: inout B) throws -> [ExactRationalCoefficient] {
        try usage.retainExactStorage(3)
        return try (0..<3).map { axis in
            let next = (axis + 1) % 3, last = (axis + 2) % 3
            return try a[next].multiplied(by: b[last], usage: &usage)
                .subtracting(a[last].multiplied(by: b[next], usage: &usage), usage: &usage)
        }
    }
    static func dot<B: RationalAlgebraAdmitting>(_ a: [ExactRationalCoefficient],
        _ b: [ExactRationalCoefficient], usage: inout B) throws -> ExactRationalCoefficient {
        var result = ExactRationalCoefficient.zero
        for axis in 0..<3 {
            result = try result.adding(a[axis].multiplied(by: b[axis], usage: &usage), usage: &usage)
        }
        return result
    }
}
