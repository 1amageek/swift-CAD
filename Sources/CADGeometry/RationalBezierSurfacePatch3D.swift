import CADCore

struct RationalBezierSurfacePatch3D: Sendable {
    private struct HomogeneousPoint: Sendable {
        let x: Double
        let y: Double
        let z: Double
        let weight: Double

        func interpolated(
            to other: HomogeneousPoint,
            parameter: Double
        ) -> HomogeneousPoint {
            HomogeneousPoint(
                x: x * (1.0 - parameter) + other.x * parameter,
                y: y * (1.0 - parameter) + other.y * parameter,
                z: z * (1.0 - parameter) + other.z * parameter,
                weight: weight * (1.0 - parameter) + other.weight * parameter
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
        let homogeneous = homogeneousControlNet()
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
            try patch(
                controlNet: quadrants[index],
                uBounds: (bounds[index].0, bounds[index].1),
                vBounds: (bounds[index].2, bounds[index].3)
            )
        }
    }

    func trimmed(
        uFrom requestedULower: Double,
        uTo requestedUUpper: Double,
        vFrom requestedVLower: Double,
        vTo requestedVUpper: Double,
        tolerance: ModelingTolerance
    ) throws -> RationalBezierSurfacePatch3D {
        let parameterTolerance = max(
            tolerance.relative * max(
                1.0,
                abs(uLower),
                abs(uUpper),
                abs(vLower),
                abs(vUpper)
            ),
            Double.ulpOfOne * 256.0
        )
        guard requestedULower.isFinite,
              requestedUUpper.isFinite,
              requestedVLower.isFinite,
              requestedVUpper.isFinite,
              requestedULower >= uLower - parameterTolerance,
              requestedUUpper <= uUpper + parameterTolerance,
              requestedVLower >= vLower - parameterTolerance,
              requestedVUpper <= vUpper + parameterTolerance,
              requestedUUpper - requestedULower > parameterTolerance,
              requestedVUpper - requestedVLower > parameterTolerance else {
            throw KernelError(
                phase: .geometry,
                code: .invalidInput,
                tolerance: tolerance,
                message: "Rational Bezier surface trimming requires a positive subdomain of the source patch."
            )
        }
        let targetULower = abs(requestedULower - uLower) <= parameterTolerance
            ? uLower
            : requestedULower
        let targetUUpper = abs(requestedUUpper - uUpper) <= parameterTolerance
            ? uUpper
            : requestedUUpper
        let targetVLower = abs(requestedVLower - vLower) <= parameterTolerance
            ? vLower
            : requestedVLower
        let targetVUpper = abs(requestedVUpper - vUpper) <= parameterTolerance
            ? vUpper
            : requestedVUpper
        var net = homogeneousControlNet()
        var currentULower = uLower
        var currentUUpper = uUpper
        var currentVLower = vLower
        var currentVUpper = vUpper

        if targetULower > currentULower {
            let parameter = (targetULower - currentULower) / (currentUUpper - currentULower)
            net = net.map { split($0, parameter: parameter).upper }
            currentULower = targetULower
        }
        if targetUUpper < currentUUpper {
            let parameter = (targetUUpper - currentULower) / (currentUUpper - currentULower)
            net = net.map { split($0, parameter: parameter).lower }
            currentUUpper = targetUUpper
        }
        if targetVLower > currentVLower {
            let parameter = (targetVLower - currentVLower) / (currentVUpper - currentVLower)
            net = splitColumns(net, parameter: parameter).upper
            currentVLower = targetVLower
        }
        if targetVUpper < currentVUpper {
            let parameter = (targetVUpper - currentVLower) / (currentVUpper - currentVLower)
            net = splitColumns(net, parameter: parameter).lower
            currentVUpper = targetVUpper
        }
        return try patch(
            controlNet: net,
            uBounds: (currentULower, currentUUpper),
            vBounds: (currentVLower, currentVUpper)
        )
    }

    func subdivided(parameterIndex: Int) throws -> [RationalBezierSurfacePatch3D] {
        let homogeneous = homogeneousControlNet()
        switch parameterIndex {
        case 0:
            var lowerRows: [[HomogeneousPoint]] = []
            var upperRows: [[HomogeneousPoint]] = []
            for row in homogeneous {
                let halves = split(row, parameter: 0.5)
                lowerRows.append(halves.lower)
                upperRows.append(halves.upper)
            }
            let middle = uLower + (uUpper - uLower) * 0.5
            return [
                try patch(
                    controlNet: lowerRows,
                    uBounds: (uLower, middle),
                    vBounds: (vLower, vUpper)
                ),
                try patch(
                    controlNet: upperRows,
                    uBounds: (middle, uUpper),
                    vBounds: (vLower, vUpper)
                ),
            ]
        case 1:
            let halves = splitColumns(homogeneous)
            let middle = vLower + (vUpper - vLower) * 0.5
            return [
                try patch(
                    controlNet: halves.lower,
                    uBounds: (uLower, uUpper),
                    vBounds: (vLower, middle)
                ),
                try patch(
                    controlNet: halves.upper,
                    uBounds: (uLower, uUpper),
                    vBounds: (middle, vUpper)
                ),
            ]
        default:
            return []
        }
    }

    private func homogeneousControlNet() -> [[HomogeneousPoint]] {
        controlPoints.indices.map { rowIndex in
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
    }

    private func patch(
        controlNet: [[HomogeneousPoint]],
        uBounds: (Double, Double),
        vBounds: (Double, Double)
    ) throws -> RationalBezierSurfacePatch3D {
        let points = try controlNet.map { row in
            try row.map { try $0.point() }
        }
        return RationalBezierSurfacePatch3D(
            controlPoints: points,
            weights: controlNet.map { $0.map(\.weight) },
            uLower: uBounds.0,
            uUpper: uBounds.1,
            vLower: vBounds.0,
            vUpper: vBounds.1
        )
    }

    private func subdivided(controlNet: [[HomogeneousPoint]]) -> [[[HomogeneousPoint]]] {
        var uLowerRows: [[HomogeneousPoint]] = []
        var uUpperRows: [[HomogeneousPoint]] = []
        for row in controlNet {
            let halves = split(row, parameter: 0.5)
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
            let halves = split(
                controlNet.map { $0[columnIndex] },
                parameter: 0.5
            )
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
        _ values: [HomogeneousPoint],
        parameter: Double
    ) -> (lower: [HomogeneousPoint], upper: [HomogeneousPoint]) {
        guard values.count > 1 else { return (values, values) }
        var levels = [values]
        while let previous = levels.last, previous.count > 1 {
            levels.append((0..<(previous.count - 1)).map { index in
                previous[index].interpolated(
                    to: previous[index + 1],
                    parameter: parameter
                )
            })
        }
        return (
            levels.map { $0[0] },
            levels.reversed().map { $0[$0.count - 1] }
        )
    }

    private func splitColumns(
        _ controlNet: [[HomogeneousPoint]],
        parameter: Double
    ) -> (lower: [[HomogeneousPoint]], upper: [[HomogeneousPoint]]) {
        guard let firstRow = controlNet.first else { return ([], []) }
        var lowerColumns: [[HomogeneousPoint]] = []
        var upperColumns: [[HomogeneousPoint]] = []
        for columnIndex in firstRow.indices {
            let halves = split(
                controlNet.map { $0[columnIndex] },
                parameter: parameter
            )
            lowerColumns.append(halves.lower)
            upperColumns.append(halves.upper)
        }
        return (
            controlNet.indices.map { rowIndex in lowerColumns.map { $0[rowIndex] } },
            controlNet.indices.map { rowIndex in upperColumns.map { $0[rowIndex] } }
        )
    }
}
