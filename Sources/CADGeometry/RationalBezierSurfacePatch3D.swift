import CADCore

struct RationalBezierSurfacePatch3D: Sendable {
    private struct HomogeneousPoint: Sendable {
        let x: Double
        let y: Double
        let z: Double
        let weight: Double

        func interpolated(to other: HomogeneousPoint) -> HomogeneousPoint {
            HomogeneousPoint(
                x: (x + other.x) * 0.5,
                y: (y + other.y) * 0.5,
                z: (z + other.z) * 0.5,
                weight: (weight + other.weight) * 0.5
            )
        }

        func point() throws -> Point3D {
            guard weight.isFinite, weight > 0.0 else {
                throw GeometryError.invalidDistance(weight)
            }
            return Point3D(x: x / weight, y: y / weight, z: z / weight)
        }
    }

    let controlPoints: [[Point3D]]
    let weights: [[Double]]
    let uLower: Double
    let uUpper: Double
    let vLower: Double
    let vUpper: Double

    func boundingBox() throws -> BoundingBox3D {
        try BoundingBox3D(points: controlPoints.flatMap { $0 })
    }

    func subdivided() throws -> [RationalBezierSurfacePatch3D] {
        let homogeneous = controlPoints.indices.map { rowIndex in
            controlPoints[rowIndex].indices.map { columnIndex in
                let point = controlPoints[rowIndex][columnIndex]
                let weight = weights[rowIndex][columnIndex]
                return HomogeneousPoint(
                    x: point.x * weight,
                    y: point.y * weight,
                    z: point.z * weight,
                    weight: weight
                )
            }
        }
        let quadrants = subdivided(controlNet: homogeneous)
        let uMiddle = uLower + (uUpper - uLower) * 0.5
        let vMiddle = vLower + (vUpper - vLower) * 0.5
        let bounds = [
            (uLower, uMiddle, vLower, vMiddle),
            (uMiddle, uUpper, vLower, vMiddle),
            (uLower, uMiddle, vMiddle, vUpper),
            (uMiddle, uUpper, vMiddle, vUpper),
        ]
        return try bounds.indices.map { index in
            let points = try quadrants[index].map { row in
                try row.map { try $0.point() }
            }
            return RationalBezierSurfacePatch3D(
                controlPoints: points,
                weights: quadrants[index].map { $0.map(\.weight) },
                uLower: bounds[index].0,
                uUpper: bounds[index].1,
                vLower: bounds[index].2,
                vUpper: bounds[index].3
            )
        }
    }

    private func subdivided(controlNet: [[HomogeneousPoint]]) -> [[[HomogeneousPoint]]] {
        var uLowerRows: [[HomogeneousPoint]] = []
        var uUpperRows: [[HomogeneousPoint]] = []
        for row in controlNet {
            let halves = split(row)
            uLowerRows.append(halves.lower)
            uUpperRows.append(halves.upper)
        }
        let lowerUHalves = splitColumns(uLowerRows)
        let upperUHalves = splitColumns(uUpperRows)
        return [
            lowerUHalves.lower,
            upperUHalves.lower,
            lowerUHalves.upper,
            upperUHalves.upper,
        ]
    }

    private func splitColumns(
        _ controlNet: [[HomogeneousPoint]]
    ) -> (lower: [[HomogeneousPoint]], upper: [[HomogeneousPoint]]) {
        guard let firstRow = controlNet.first else { return ([], []) }
        var lowerColumns: [[HomogeneousPoint]] = []
        var upperColumns: [[HomogeneousPoint]] = []
        for columnIndex in firstRow.indices {
            let halves = split(controlNet.map { $0[columnIndex] })
            lowerColumns.append(halves.lower)
            upperColumns.append(halves.upper)
        }
        let lower = controlNet.indices.map { rowIndex in
            lowerColumns.map { $0[rowIndex] }
        }
        let upper = controlNet.indices.map { rowIndex in
            upperColumns.map { $0[rowIndex] }
        }
        return (lower, upper)
    }

    private func split(
        _ values: [HomogeneousPoint]
    ) -> (lower: [HomogeneousPoint], upper: [HomogeneousPoint]) {
        guard values.count > 1 else { return (values, values) }
        var levels = [values]
        while let previous = levels.last, previous.count > 1 {
            levels.append((0..<(previous.count - 1)).map { index in
                previous[index].interpolated(to: previous[index + 1])
            })
        }
        return (
            levels.map { $0[0] },
            levels.reversed().map { $0[$0.count - 1] }
        )
    }
}
