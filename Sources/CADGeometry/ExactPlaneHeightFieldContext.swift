import CADCore

struct ExactPlaneHeightFieldContext: Sendable {
    struct Witness: Sendable {
        let point: Point3D
        let firstParameter: SurfaceParameterProjection
        let secondParameter: SurfaceParameterProjection
    }

    let surface: BSplineSurface3D
    let origin: Point3D
    let u: Vector3D
    let v: Vector3D

    private let exactU: ExactExpansionArithmetic.Vector3
    private let exactV: ExactExpansionArithmetic.Vector3

    init?(surface: BSplineSurface3D) throws {
        var execution = try OriginalQueryExecution.independentGeometry()
        try self.init(surface: surface, using: &execution)
    }


    init?(surface: BSplineSurface3D, using execution: inout OriginalQueryExecution) throws {
        try execution.consumeWork(1)

        guard try Self.isSingleSpan(surface, using: &execution),
              try Self.hasConstantWeights(surface, using: &execution),
              surface.uDegree > 0,
              surface.vDegree > 0,
              surface.uDegree <= 2,
              surface.vDegree <= 2,
              let firstRow = surface.controlPoints.first,
              let lastRow = surface.controlPoints.last,
              let origin = firstRow.first,
              let uEnd = firstRow.last,
              let vEnd = lastRow.first else {
            return nil
        }
        let u = uEnd - origin
        let v = vEnd - origin
        let exactU = try ExactExpansionArithmetic.difference(uEnd, origin, using: &execution)
        let exactV = try ExactExpansionArithmetic.difference(vEnd, origin, using: &execution)
        let metricDeterminant = try ExactExpansionArithmetic.subtract(
            try ExactExpansionArithmetic.multiply(
                try ExactExpansionArithmetic.dot(exactU, exactU, using: &execution),
                try ExactExpansionArithmetic.dot(exactV, exactV, using: &execution)
            , using: &execution),
            try ExactExpansionArithmetic.multiply(
                try ExactExpansionArithmetic.dot(exactU, exactV, using: &execution),
                try ExactExpansionArithmetic.dot(exactU, exactV, using: &execution)
            , using: &execution)
        , using: &execution)
        guard try ExactExpansionArithmetic.sign(metricDeterminant, using: &execution) == .positive else {
            return nil
        }
        for vIndex in surface.controlPoints.indices {
                try execution.consumeWork(1)
            let vFraction = Double(vIndex) / Double(surface.vDegree)
            for uIndex in surface.controlPoints[vIndex].indices {
                try execution.consumeWork(1)
                let uFraction = Double(uIndex) / Double(surface.uDegree)
                let offset = try ExactExpansionArithmetic.offset(
                    surface.controlPoints[vIndex][uIndex],
                    from: origin,
                    exactU: exactU,
                    uFraction: uFraction,
                    exactV: exactV,
                    vFraction: vFraction
                , using: &execution)
                guard try ExactExpansionArithmetic.isZero(offset, using: &execution) else {
                    return nil
                }
            }
        }
        self.surface = surface
        self.origin = origin
        self.u = u
        self.v = v
        self.exactU = exactU
        self.exactV = exactV
    }

    func exactHeightControls(
        for heightSurface: BSplineSurface3D
    ) throws -> [[[Double]]]? {
        var execution = try OriginalQueryExecution.independentGeometry()
        return try exactHeightControls(for: heightSurface, using: &execution)
    }


    func exactHeightControls(
        for heightSurface: BSplineSurface3D
    , using execution: inout OriginalQueryExecution) throws -> [[[Double]]]? {
        try execution.consumeWork(1)

        guard let firstRow = heightSurface.controlPoints.first,
              let lastRow = heightSurface.controlPoints.last,
              let heightOrigin = firstRow.first,
              let heightUEnd = firstRow.last,
              let heightVEnd = lastRow.first else {
            return nil
        }
        let heightExactU = try ExactExpansionArithmetic.difference(
            heightUEnd,
            heightOrigin
        , using: &execution)
        let heightExactV = try ExactExpansionArithmetic.difference(
            heightVEnd,
            heightOrigin
        , using: &execution)
        let projectedDeterminant = try ExactExpansionArithmetic.subtract(
            try ExactExpansionArithmetic.multiply(
                try ExactExpansionArithmetic.dot(heightExactU, exactU, using: &execution),
                try ExactExpansionArithmetic.dot(heightExactV, exactV, using: &execution)
            , using: &execution),
            try ExactExpansionArithmetic.multiply(
                try ExactExpansionArithmetic.dot(heightExactU, exactV, using: &execution),
                try ExactExpansionArithmetic.dot(heightExactV, exactU, using: &execution)
            , using: &execution)
        , using: &execution)
        guard try ExactExpansionArithmetic.sign(projectedDeterminant, using: &execution) != .zero else {
            return nil
        }

        var result: [[[Double]]] = []
        try execution.retainStorage(count: heightSurface.controlPoints.count, stride: MemoryLayout<[[Double]]>.stride)
        result.reserveCapacity(heightSurface.controlPoints.count)
        for vIndex in heightSurface.controlPoints.indices {
                try execution.consumeWork(1)
            let vFraction = Double(vIndex) / Double(heightSurface.vDegree)
            var row: [[Double]] = []
            try execution.retainStorage(count: heightSurface.controlPoints[vIndex].count, stride: MemoryLayout<[Double]>.stride)
            row.reserveCapacity(heightSurface.controlPoints[vIndex].count)
            for uIndex in heightSurface.controlPoints[vIndex].indices {
                try execution.consumeWork(1)
                let point = heightSurface.controlPoints[vIndex][uIndex]
                let uFraction = Double(uIndex) / Double(heightSurface.uDegree)
                let affineResidual = try ExactExpansionArithmetic.offset(
                    point,
                    from: heightOrigin,
                    exactU: heightExactU,
                    uFraction: uFraction,
                    exactV: heightExactV,
                    vFraction: vFraction
                , using: &execution)
                guard try ExactExpansionArithmetic.sign(
                    try ExactExpansionArithmetic.dot(affineResidual, exactU, using: &execution)
                , using: &execution) == .zero,
                try ExactExpansionArithmetic.sign(
                    try ExactExpansionArithmetic.dot(affineResidual, exactV, using: &execution)
                , using: &execution) == .zero else {
                    return nil
                }
                row.append(try ExactExpansionArithmetic.tripleProduct(
                    exactU,
                    exactV,
                    try ExactExpansionArithmetic.difference(point, origin, using: &execution)
                , using: &execution))
            }
            result.append(row)
        }
        return result
    }

    func verifiedWitness(
        on heightSurface: BSplineSurface3D,
        normalized: Point2D,
        planeIsFirst: Bool,
        certificateName: String,
        tolerance: ModelingTolerance
    ) throws -> Witness {
        var execution = try OriginalQueryExecution.independentGeometry()
        return try verifiedWitness(on: heightSurface, normalized: normalized, planeIsFirst: planeIsFirst, certificateName: certificateName, tolerance: tolerance, using: &execution)
    }


    func verifiedWitness(
        on heightSurface: BSplineSurface3D,
        normalized: Point2D,
        planeIsFirst: Bool,
        certificateName: String,
        tolerance: ModelingTolerance
    , using execution: inout OriginalQueryExecution) throws -> Witness {
        try execution.consumeWork(1)

        guard case let .closed(heightULower, heightUUpper) = heightSurface.uDomain,
              case let .closed(heightVLower, heightVUpper) = heightSurface.vDomain,
              case let .closed(planeULower, planeUUpper) = surface.uDomain,
              case let .closed(planeVLower, planeVUpper) = surface.vDomain else {
            throw KernelError(
                phase: .geometry,
                code: .invalidInput,
                tolerance: tolerance,
                message: "An exact \(certificateName) certificate requires closed surface domains."
            )
        }
        let heightU = heightULower
            + (heightUUpper - heightULower) * normalized.x
        let heightV = heightVLower
            + (heightVUpper - heightVLower) * normalized.y
        let point = try heightSurface.point(
            u: heightU,
            v: heightV,
            tolerance: tolerance
        , using: &execution)
        let relative = point - origin
        let metricUU = u.dot(u)
        let metricUV = u.dot(v)
        let metricVV = v.dot(v)
        let determinant = metricUU * metricVV - metricUV * metricUV
        guard determinant.isFinite, determinant > 0.0 else {
            throw KernelError(
                phase: .geometry,
                code: .singularSystem,
                tolerance: tolerance,
                message: "An exact \(certificateName) plane frame is singular."
            )
        }
        let rightU = relative.dot(u)
        let rightV = relative.dot(v)
        let normalizedPlaneU = (
            rightU * metricVV - rightV * metricUV
        ) / determinant
        let normalizedPlaneV = (
            rightV * metricUU - rightU * metricUV
        ) / determinant
        let planeU = planeULower
            + (planeUUpper - planeULower) * normalizedPlaneU
        let planeV = planeVLower
            + (planeVUpper - planeVLower) * normalizedPlaneV
        let planePoint = try surface.point(
            u: planeU,
            v: planeV,
            tolerance: tolerance
        , using: &execution)
        let residual = (planePoint - point).length
        guard residual.isFinite, residual <= tolerance.distance else {
            throw KernelError(
                phase: .geometry,
                code: .intersectionFailure,
                residual: residual,
                tolerance: tolerance,
                message: "An exact \(certificateName) witness failed plane residual verification."
            )
        }
        let planeProjection = try SurfaceParameterProjection(
            u: planeU,
            v: planeV,
            point: planePoint,
            residual: residual
        )
        let heightProjection = try SurfaceParameterProjection(
            u: heightU,
            v: heightV,
            point: point,
            residual: 0.0
        )
        return Witness(
            point: point,
            firstParameter: planeIsFirst ? planeProjection : heightProjection,
            secondParameter: planeIsFirst ? heightProjection : planeProjection
        )
    }

    static func isSingleSpan(_ surface: BSplineSurface3D) throws -> Bool {
        var execution = try OriginalQueryExecution.independentGeometry()
        return try isSingleSpan(surface, using: &execution)
    }


    static func isSingleSpan(_ surface: BSplineSurface3D, using execution: inout OriginalQueryExecution) throws -> Bool {
        try execution.consumeWork(1)

        guard surface.controlPoints.count == surface.vDegree + 1 else { return false }
        for row in surface.controlPoints {
            try execution.consumeWork(1)
            if row.count != surface.uDegree + 1 { return false }
        }
        return try isSingleSpan(knots: surface.uKnots, degree: surface.uDegree, using: &execution)
            && isSingleSpan(knots: surface.vKnots, degree: surface.vDegree, using: &execution)
    }

    static func hasConstantWeights(_ surface: BSplineSurface3D) throws -> Bool {
        var execution = try OriginalQueryExecution.independentGeometry()
        return try hasConstantWeights(surface, using: &execution)
    }


    static func hasConstantWeights(_ surface: BSplineSurface3D, using execution: inout OriginalQueryExecution) throws -> Bool {
        try execution.consumeWork(1)

        guard let reference = surface.weights.first?.first,
              reference.isFinite,
              reference > 0.0 else {
            return false
        }
        for row in surface.weights {
            try execution.consumeWork(1)
            for weight in row {
                try execution.consumeWork(1)
                if !weight.isFinite || weight <= 0.0 || weight != reference { return false }
            }
        }
        return true
    }



    private static func isSingleSpan(knots: [Double], degree: Int, using execution: inout OriginalQueryExecution) throws -> Bool {
        try execution.consumeWork(1)

        guard knots.count == 2 * (degree + 1),
              let lower = knots.first,
              let upper = knots.last,
              lower.isFinite,
              upper.isFinite,
              upper > lower else {
            return false
        }
        for value in knots.prefix(degree + 1) {
            try execution.consumeWork(1)
            if value != lower { return false }
        }
        for value in knots.suffix(degree + 1) {
            try execution.consumeWork(1)
            if value != upper { return false }
        }
        return true
    }
}
