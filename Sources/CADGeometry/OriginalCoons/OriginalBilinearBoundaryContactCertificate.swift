import CADCore

/// Whole convex support admission; touching support is restricted to proven original incidence.
struct OriginalBilinearBoundaryContactCertificate {
    func proves<B: RationalAlgebraAdmitting>(_ first: OriginalBilinearEmbeddingCertificate,
        _ second: OriginalBilinearEmbeddingCertificate,
        sharedBoundaries: [OriginalSurfaceSharedBoundary], allowedCorners: [(Point2D, Point2D)],
        tolerance: ModelingTolerance, usage: inout B) throws -> Bool {
        typealias Proof = OriginalBilinearEmbeddingCertificate
        try usage.retainExactStorage(52)
        var axes = [first.normal, second.normal]
        var firstEdges: [[ExactRationalCoefficient]] = [], secondEdges: [[ExactRationalCoefficient]] = []
        for index in 0..<4 {
            firstEdges.append(try Proof.subtract(first.vertices[(index + 1) % 4], first.vertices[index], usage: &usage))
            secondEdges.append(try Proof.subtract(second.vertices[(index + 1) % 4], second.vertices[index], usage: &usage))
        }
        for edge in firstEdges + secondEdges {
            axes.append(try Proof.cross(edge, first.normal, usage: &usage))
            axes.append(try Proof.cross(edge, second.normal, usage: &usage))
        }
        for a in firstEdges { for b in secondEdges { axes.append(try Proof.cross(a, b, usage: &usage)) } }
        let distance = try ExactRationalCoefficient.originalDouble(tolerance.distance, usage: &usage)
        let distanceSquared = try distance.multiplied(by: distance, usage: &usage)
        for axis in axes {
            try Task.checkCancellation(); try usage.visitExactCell(depth: 0)
            if axis.allSatisfy(\.isZero) { continue }
            try usage.retainExactStorage(8)
            let a = try first.vertices.map { try Proof.dot(axis, $0, usage: &usage) }
            let b = try second.vertices.map { try Proof.dot(axis, $0, usage: &usage) }
            let aBounds = try bounds(a, usage: &usage), bBounds = try bounds(b, usage: &usage)
            for (left, right, leftBounds, rightBounds, firstIsLeft) in [
                (a, b, aBounds, bBounds, true), (b, a, bBounds, aBounds, false)] {
                let gap = try rightBounds.0.subtracting(leftBounds.1, usage: &usage)
                if gap.isPositive {
                    let required = try distanceSquared.multiplied(by: Proof.dot(axis, axis, usage: &usage), usage: &usage)
                    if try gap.multiplied(by: gap, usage: &usage).subtracting(required, usage: &usage).isPositive { return true }
                }
                guard gap.isZero else { continue }
                try usage.consumeExactWork(8); try usage.retainExactStorage(8)
                let leftSupport = left.indices.filter { left[$0] == leftBounds.1 }
                let rightSupport = right.indices.filter { right[$0] == rightBounds.0 }
                for seam in sharedBoundaries {
                    let leftEdge = edge(firstIsLeft ? seam.first : seam.second)
                    let rightEdge = edge(firstIsLeft ? seam.second : seam.first)
                    if leftSupport.allSatisfy({ leftEdge.contains($0) })
                        || rightSupport.allSatisfy({ rightEdge.contains($0) }) { return true }
                }
                for corner in allowedCorners {
                    let leftCorner = vertex(firstIsLeft ? corner.0 : corner.1)
                    let rightCorner = vertex(firstIsLeft ? corner.1 : corner.0)
                    if leftSupport.allSatisfy({ $0 == leftCorner })
                        || rightSupport.allSatisfy({ $0 == rightCorner }) { return true }
                }
            }
        }
        return false
    }

    private func bounds<B: RationalAlgebraAdmitting>(_ values: [ExactRationalCoefficient], usage: inout B)
        throws -> (ExactRationalCoefficient, ExactRationalCoefficient) {
        var lower = values[0], upper = values[0]
        for value in values.dropFirst() {
            if try value.subtracting(lower, usage: &usage).isNegative { lower = value }
            if try value.subtracting(upper, usage: &usage).isPositive { upper = value }
        }
        return (lower, upper)
    }
    private func edge(_ boundary: SurfaceParameterBoundary) -> [Int] {
        switch boundary { case .uLower: [0, 3]; case .uUpper: [1, 2]; case .vLower: [0, 1]; case .vUpper: [2, 3] }
    }
    private func vertex(_ corner: Point2D) -> Int {
        corner.y == 0 ? (corner.x == 0 ? 0 : 1) : (corner.x == 0 ? 3 : 2)
    }
}
