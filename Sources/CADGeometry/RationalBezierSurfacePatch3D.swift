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

    func boundingBox<A: ExactScalarAdmission & ~Copyable>(using execution: inout A) throws -> BoundingBox3D {
        try execution.consumeWork(1)
        var count = 0
        for row in controlPoints {
            let next = count.addingReportingOverflow(row.count)
            guard !next.overflow else { throw ExactScalarFailure.countOverflow }
            count = next.partialValue
        }
        try execution.retainStorage(bytes: exactScalarPayloadBytes(count: count, of: Point3D.self))
        let points = try controlPoints.flatMap { row in
            for _ in row { try execution.consumeWork(1) }
            return row
        }
        return try BoundingBox3D(points: points)
    }

    func subdivided<A: ExactScalarAdmission & ~Copyable>(using execution: inout A) throws -> [RationalBezierSurfacePatch3D] {
        try execution.consumeWork(1)
        let homogeneous = try homogeneousControlNet(using: &execution)
        let quadrants = try subdivided(controlNet: homogeneous, using: &execution)
        let uMiddle = uLower + (uUpper - uLower) * 0.5
        let vMiddle = vLower + (vUpper - vLower) * 0.5
        try execution.retainStorage(bytes: exactScalarPayloadBytes(count: 4, of: (Double, Double, Double, Double).self))
        try execution.retainStorage(bytes: exactScalarPayloadBytes(count: 4, of: Self.self))
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
                vBounds: (bounds[index].2, bounds[index].3), using: &execution
            )
        }
    }

    func trimmed<A: ExactScalarAdmission & ~Copyable>(
        uFrom requestedULower: Double,
        uTo requestedUUpper: Double,
        vFrom requestedVLower: Double,
        vTo requestedVUpper: Double,
        tolerance: ModelingTolerance, using execution: inout A
    ) throws -> RationalBezierSurfacePatch3D {
        try execution.consumeWork(1)
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
        var net = try homogeneousControlNet(using: &execution)
        var currentULower = uLower
        var currentUUpper = uUpper
        var currentVLower = vLower
        var currentVUpper = vUpper

        if targetULower > currentULower {
            let parameter = (targetULower - currentULower) / (currentUUpper - currentULower)
            try execution.retainStorage(bytes: exactScalarPayloadBytes(count: net.count, of: [HomogeneousPoint].self))
            net = try net.map { try split($0, parameter: parameter, using: &execution).upper }
            currentULower = targetULower
        }
        if targetUUpper < currentUUpper {
            let parameter = (targetUUpper - currentULower) / (currentUUpper - currentULower)
            try execution.retainStorage(bytes: exactScalarPayloadBytes(count: net.count, of: [HomogeneousPoint].self))
            net = try net.map { try split($0, parameter: parameter, using: &execution).lower }
            currentUUpper = targetUUpper
        }
        if targetVLower > currentVLower {
            let parameter = (targetVLower - currentVLower) / (currentVUpper - currentVLower)
            net = try splitColumns(net, parameter: parameter, using: &execution).upper
            currentVLower = targetVLower
        }
        if targetVUpper < currentVUpper {
            let parameter = (targetVUpper - currentVLower) / (currentVUpper - currentVLower)
            net = try splitColumns(net, parameter: parameter, using: &execution).lower
            currentVUpper = targetVUpper
        }
        return try patch(
            controlNet: net,
            uBounds: (currentULower, currentUUpper),
            vBounds: (currentVLower, currentVUpper), using: &execution
        )
    }

    func subdivided<A: ExactScalarAdmission & ~Copyable>(parameterIndex: Int, using execution: inout A) throws -> [RationalBezierSurfacePatch3D] {
        try execution.consumeWork(1)
        let homogeneous = try homogeneousControlNet(using: &execution)
        try execution.retainStorage(bytes: exactScalarPayloadBytes(count: 2, of: Self.self))
        switch parameterIndex {
        case 0:
            try execution.retainStorage(bytes: exactScalarPayloadBytes(count: homogeneous.count, of: [HomogeneousPoint].self))
            try execution.retainStorage(bytes: exactScalarPayloadBytes(count: homogeneous.count, of: [HomogeneousPoint].self))
            var lowerRows: [[HomogeneousPoint]] = []
            var upperRows: [[HomogeneousPoint]] = []
            for row in homogeneous {
                let halves = try split(row, parameter: 0.5, using: &execution)
                lowerRows.append(halves.lower)
                upperRows.append(halves.upper)
            }
            let middle = uLower + (uUpper - uLower) * 0.5
            return [
                try patch(
                    controlNet: lowerRows,
                    uBounds: (uLower, middle),
                    vBounds: (vLower, vUpper), using: &execution
                ),
                try patch(
                    controlNet: upperRows,
                    uBounds: (middle, uUpper),
                    vBounds: (vLower, vUpper), using: &execution
                ),
            ]
        case 1:
            let halves = try splitColumns(homogeneous, using: &execution)
            let middle = vLower + (vUpper - vLower) * 0.5
            return [
                try patch(
                    controlNet: halves.lower,
                    uBounds: (uLower, uUpper),
                    vBounds: (vLower, middle), using: &execution
                ),
                try patch(
                    controlNet: halves.upper,
                    uBounds: (uLower, uUpper),
                    vBounds: (middle, vUpper), using: &execution
                ),
            ]
        default:
            return []
        }
    }

    private func homogeneousControlNet<A: ExactScalarAdmission & ~Copyable>(using execution: inout A) throws -> [[HomogeneousPoint]] {
        try execution.retainStorage(bytes: exactScalarPayloadBytes(count: controlPoints.count, of: [HomogeneousPoint].self))
        return try controlPoints.indices.map { rowIndex in
            try execution.retainStorage(bytes: exactScalarPayloadBytes(count: controlPoints[rowIndex].count, of: HomogeneousPoint.self))
            return try controlPoints[rowIndex].indices.map { columnIndex in
                try execution.consumeWork(1)
                let point = controlPoints[rowIndex][columnIndex]
                let weight = weights[rowIndex][columnIndex]
                return HomogeneousPoint(x: point.x * weight, y: point.y * weight, z: point.z * weight, weight: weight)
            }
        }
    }

    private func patch<A: ExactScalarAdmission & ~Copyable>(controlNet: [[HomogeneousPoint]],
        uBounds: (Double, Double), vBounds: (Double, Double), using execution: inout A) throws -> Self {
        try execution.retainStorage(bytes: exactScalarPayloadBytes(count: controlNet.count, of: [Point3D].self))
        try execution.retainStorage(bytes: exactScalarPayloadBytes(count: controlNet.count, of: [Double].self))
        let points = try controlNet.map { row in
            try execution.retainStorage(bytes: exactScalarPayloadBytes(count: row.count, of: Point3D.self))
            return try row.map { try execution.consumeWork(1); return try $0.point() }
        }
        let weights = try controlNet.map { row in
            try execution.retainStorage(bytes: exactScalarPayloadBytes(count: row.count, of: Double.self))
            return try row.map { try execution.consumeWork(1); return $0.weight }
        }
        return Self(controlPoints: points, weights: weights,
            uLower: uBounds.0, uUpper: uBounds.1, vLower: vBounds.0, vUpper: vBounds.1)
    }

    private func subdivided<A: ExactScalarAdmission & ~Copyable>(controlNet: [[HomogeneousPoint]], using execution: inout A) throws -> [[[HomogeneousPoint]]] {
        try execution.retainStorage(bytes: exactScalarPayloadBytes(count: controlNet.count, of: [HomogeneousPoint].self))
        try execution.retainStorage(bytes: exactScalarPayloadBytes(count: controlNet.count, of: [HomogeneousPoint].self))
        var uLowerRows: [[HomogeneousPoint]] = [], uUpperRows: [[HomogeneousPoint]] = []
        uLowerRows.reserveCapacity(controlNet.count); uUpperRows.reserveCapacity(controlNet.count)
        for row in controlNet {
            let halves = try split(row, parameter: 0.5, using: &execution)
            uLowerRows.append(halves.lower); uUpperRows.append(halves.upper)
        }
        let lower = try splitColumns(uLowerRows, using: &execution)
        let upper = try splitColumns(uUpperRows, using: &execution)
        try execution.retainStorage(bytes: exactScalarPayloadBytes(count: 4, of: [[HomogeneousPoint]].self))
        return [lower.lower, upper.lower, lower.upper, upper.upper]
    }

    private func splitColumns<A: ExactScalarAdmission & ~Copyable>(_ controlNet: [[HomogeneousPoint]], using execution: inout A) throws -> (lower: [[HomogeneousPoint]], upper: [[HomogeneousPoint]]) {
        try splitColumns(controlNet, parameter: 0.5, using: &execution)
    }

    private func splitColumns<A: ExactScalarAdmission & ~Copyable>(_ controlNet: [[HomogeneousPoint]], parameter: Double, using execution: inout A) throws -> (lower: [[HomogeneousPoint]], upper: [[HomogeneousPoint]]) {
        guard let first = controlNet.first else { return ([], []) }
        try execution.retainStorage(bytes: exactScalarPayloadBytes(count: first.count, of: [HomogeneousPoint].self))
        try execution.retainStorage(bytes: exactScalarPayloadBytes(count: first.count, of: [HomogeneousPoint].self))
        var lowerColumns: [[HomogeneousPoint]] = [], upperColumns: [[HomogeneousPoint]] = []
        lowerColumns.reserveCapacity(first.count); upperColumns.reserveCapacity(first.count)
        for column in first.indices {
            try execution.retainStorage(bytes: exactScalarPayloadBytes(count: controlNet.count, of: HomogeneousPoint.self))
            let values = try controlNet.map { try execution.consumeWork(1); return $0[column] }
            let halves = try split(values, parameter: parameter, using: &execution)
            lowerColumns.append(halves.lower); upperColumns.append(halves.upper)
        }
        try execution.retainStorage(bytes: exactScalarPayloadBytes(count: controlNet.count, of: [HomogeneousPoint].self))
        try execution.retainStorage(bytes: exactScalarPayloadBytes(count: controlNet.count, of: [HomogeneousPoint].self))
        let lower = try controlNet.indices.map { row in
            try execution.retainStorage(bytes: exactScalarPayloadBytes(count: lowerColumns.count, of: HomogeneousPoint.self))
            return try lowerColumns.map { try execution.consumeWork(1); return $0[row] }
        }
        let upper = try controlNet.indices.map { row in
            try execution.retainStorage(bytes: exactScalarPayloadBytes(count: upperColumns.count, of: HomogeneousPoint.self))
            return try upperColumns.map { try execution.consumeWork(1); return $0[row] }
        }
        return (lower, upper)
    }

    private func split<A: ExactScalarAdmission & ~Copyable>(_ values: [HomogeneousPoint], parameter: Double, using execution: inout A) throws -> (lower: [HomogeneousPoint], upper: [HomogeneousPoint]) {
        guard values.count > 1 else { return (values, values) }
        try execution.retainStorage(bytes: exactScalarPayloadBytes(count: 1, of: [HomogeneousPoint].self))
        var levels = [values]
        while let previous = levels.last, previous.count > 1 {
            try execution.retainStorage(bytes: exactScalarPayloadBytes(count: 1, of: [HomogeneousPoint].self))
            try execution.retainStorage(bytes: exactScalarPayloadBytes(count: previous.count - 1, of: HomogeneousPoint.self))
            levels.append(try (0..<(previous.count - 1)).map { index in
                try execution.consumeWork(1)
                return previous[index].interpolated(to: previous[index + 1], parameter: parameter)
            })
        }
        try execution.retainStorage(bytes: exactScalarPayloadBytes(count: levels.count, of: HomogeneousPoint.self))
        try execution.retainStorage(bytes: exactScalarPayloadBytes(count: levels.count, of: HomogeneousPoint.self))
        return (try levels.map { try execution.consumeWork(1); return $0[0] },
            try levels.reversed().map { try execution.consumeWork(1); return $0[$0.count - 1] })
    }
}
