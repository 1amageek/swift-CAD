import Foundation
import CADCore

public struct BSplineSurface3D: Codable, Sendable, Hashable {
    public struct DifferentialGeometry: Codable, Sendable, Hashable {
        public var position: Point3D
        public var tangentU: Vector3D
        public var tangentV: Vector3D
        public var secondDerivativeUU: Vector3D
        public var secondDerivativeUV: Vector3D
        public var secondDerivativeVV: Vector3D
        public var normal: Vector3D
        public var normalCurvatureU: Double
        public var normalCurvatureV: Double
        public var meanCurvature: Double
        public var gaussianCurvature: Double
        public var minimumPrincipalCurvature: Double
        public var maximumPrincipalCurvature: Double
        public var minimumPrincipalDirection: Vector3D
        public var maximumPrincipalDirection: Vector3D

        public init(
            position: Point3D,
            tangentU: Vector3D,
            tangentV: Vector3D,
            secondDerivativeUU: Vector3D,
            secondDerivativeUV: Vector3D,
            secondDerivativeVV: Vector3D,
            normal: Vector3D,
            normalCurvatureU: Double,
            normalCurvatureV: Double,
            meanCurvature: Double,
            gaussianCurvature: Double,
            minimumPrincipalCurvature: Double,
            maximumPrincipalCurvature: Double,
            minimumPrincipalDirection: Vector3D,
            maximumPrincipalDirection: Vector3D
        ) {
            self.position = position
            self.tangentU = tangentU
            self.tangentV = tangentV
            self.secondDerivativeUU = secondDerivativeUU
            self.secondDerivativeUV = secondDerivativeUV
            self.secondDerivativeVV = secondDerivativeVV
            self.normal = normal
            self.normalCurvatureU = normalCurvatureU
            self.normalCurvatureV = normalCurvatureV
            self.meanCurvature = meanCurvature
            self.gaussianCurvature = gaussianCurvature
            self.minimumPrincipalCurvature = minimumPrincipalCurvature
            self.maximumPrincipalCurvature = maximumPrincipalCurvature
            self.minimumPrincipalDirection = minimumPrincipalDirection
            self.maximumPrincipalDirection = maximumPrincipalDirection
        }
    }

    public var uDegree: Int
    public var vDegree: Int
    public var uKnots: [Double]
    public var vKnots: [Double]
    public var controlPoints: [[Point3D]]
    public var weights: [[Double]]

    public init(
        uDegree: Int,
        vDegree: Int,
        uKnots: [Double],
        vKnots: [Double],
        controlPoints: [[Point3D]],
        weights: [[Double]]? = nil
    ) {
        self.uDegree = uDegree
        self.vDegree = vDegree
        self.uKnots = uKnots
        self.vKnots = vKnots
        self.controlPoints = controlPoints
        self.weights = weights ?? Self.unitWeights(matching: controlPoints)
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try container.validateOnlyExpectedKeys(
            [.uDegree, .vDegree, .uKnots, .vKnots, .controlPoints, .weights],
            in: decoder
        )
        let controlPoints = try container.decode([[Point3D]].self, forKey: .controlPoints)
        self.init(
            uDegree: try container.decode(Int.self, forKey: .uDegree),
            vDegree: try container.decode(Int.self, forKey: .vDegree),
            uKnots: try container.decode([Double].self, forKey: .uKnots),
            vKnots: try container.decode([Double].self, forKey: .vKnots),
            controlPoints: controlPoints,
            weights: try container.decode([[Double]].self, forKey: .weights)
        )
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(uDegree, forKey: .uDegree)
        try container.encode(vDegree, forKey: .vDegree)
        try container.encode(uKnots, forKey: .uKnots)
        try container.encode(vKnots, forKey: .vKnots)
        try container.encode(controlPoints, forKey: .controlPoints)
        try container.encode(weights, forKey: .weights)
    }

    public var uOrder: Int {
        uDegree + 1
    }

    public var vOrder: Int {
        vDegree + 1
    }

    public var isRational: Bool {
        for row in weights {
            for weight in row where abs(weight - 1.0) > 1.0e-12 {
                return true
            }
        }
        return false
    }

    public var uControlPointCount: Int {
        controlPoints.first?.count ?? 0
    }

    public var vControlPointCount: Int {
        controlPoints.count
    }

    public var uDomain: ParameterDomain {
        guard uKnots.count > uDegree + 1 else {
            return .closed(0.0, 0.0)
        }
        return .closed(uKnots[uDegree], uKnots[uKnots.count - uDegree - 1])
    }

    public var vDomain: ParameterDomain {
        guard vKnots.count > vDegree + 1 else {
            return .closed(0.0, 0.0)
        }
        return .closed(vKnots[vDegree], vKnots[vKnots.count - vDegree - 1])
    }

    public func validate(tolerance: ModelingTolerance) throws {
        try tolerance.validate()
        try validateControlPoints()
        try validateWeights()
        try validateKnots(uKnots, degree: uDegree, controlPointCount: uControlPointCount)
        try validateKnots(vKnots, degree: vDegree, controlPointCount: vControlPointCount)
        try uDomain.validate(tolerance: tolerance)
        try vDomain.validate(tolerance: tolerance)
    }

    public func insertingKnot(
        direction: SurfaceParameterDirection,
        value: Double,
        tolerance: ModelingTolerance
    ) throws -> BSplineSurface3D {
        try validate(tolerance: tolerance)
        let insertionValue: Double
        switch direction {
        case .u:
            insertionValue = canonicalKnotValue(value, in: uKnots, tolerance: tolerance)
        case .v:
            insertionValue = canonicalKnotValue(value, in: vKnots, tolerance: tolerance)
        }
        let homogeneousRows = homogeneousControlRows()
        let insertedSurface: BSplineSurface3D
        switch direction {
        case .u:
            let insertion = try knotInsertion(
                value: insertionValue,
                knots: uKnots,
                degree: uDegree,
                controlPointCount: uControlPointCount,
                tolerance: tolerance
            )
            let updatedRows = try homogeneousRows.map { row in
                try insertedControlLine(row, insertion: insertion, degree: uDegree)
            }
            let controlNet = try controlNet(from: updatedRows)
            insertedSurface = BSplineSurface3D(
                uDegree: uDegree,
                vDegree: vDegree,
                uKnots: insertion.knots,
                vKnots: vKnots,
                controlPoints: controlNet.controlPoints,
                weights: controlNet.weights
            )
        case .v:
            let insertion = try knotInsertion(
                value: insertionValue,
                knots: vKnots,
                degree: vDegree,
                controlPointCount: vControlPointCount,
                tolerance: tolerance
            )
            var updatedColumns: [[HomogeneousPoint]] = []
            updatedColumns.reserveCapacity(uControlPointCount)
            for uIndex in 0..<uControlPointCount {
                let column = homogeneousRows.map { $0[uIndex] }
                updatedColumns.append(try insertedControlLine(column, insertion: insertion, degree: vDegree))
            }
            let updatedVCount = vControlPointCount + 1
            var updatedRows = Array(
                repeating: Array(repeating: HomogeneousPoint.zero, count: uControlPointCount),
                count: updatedVCount
            )
            for uIndex in 0..<uControlPointCount {
                for vIndex in 0..<updatedVCount {
                    updatedRows[vIndex][uIndex] = updatedColumns[uIndex][vIndex]
                }
            }
            let controlNet = try controlNet(from: updatedRows)
            insertedSurface = BSplineSurface3D(
                uDegree: uDegree,
                vDegree: vDegree,
                uKnots: uKnots,
                vKnots: insertion.knots,
                controlPoints: controlNet.controlPoints,
                weights: controlNet.weights
            )
        }
        try insertedSurface.validate(tolerance: tolerance)
        return insertedSurface
    }

    public func trimmed(
        uFrom startUParameter: Double,
        uTo endUParameter: Double,
        vFrom startVParameter: Double,
        vTo endVParameter: Double,
        tolerance: ModelingTolerance
    ) throws -> BSplineSurface3D {
        try validate(tolerance: tolerance)
        let startU = canonicalKnotValue(
            startUParameter,
            in: uKnots,
            tolerance: tolerance
        )
        let endU = canonicalKnotValue(
            endUParameter,
            in: uKnots,
            tolerance: tolerance
        )
        let startV = canonicalKnotValue(
            startVParameter,
            in: vKnots,
            tolerance: tolerance
        )
        let endV = canonicalKnotValue(
            endVParameter,
            in: vKnots,
            tolerance: tolerance
        )
        return try BSplineSurfacePatchAssembler().trimmedSurface(
            source: self,
            uBounds: (startU, endU),
            vBounds: (startV, endV),
            tolerance: tolerance
        )
    }

    public func point(u: Double, v: Double, tolerance: ModelingTolerance) throws -> Point3D {
        try validate(tolerance: tolerance)
        guard try uDomain.contains(u, tolerance: tolerance),
              try vDomain.contains(v, tolerance: tolerance) else {
            throw GeometryError.invalidDistance(0.0)
        }
        let clampedU = BSplineBasis.clampedParameter(u, knots: uKnots, degree: uDegree)
        let clampedV = BSplineBasis.clampedParameter(v, knots: vKnots, degree: vDegree)
        let uBasis = BSplineBasis.values(parameter: clampedU, degree: uDegree, knots: uKnots, count: uControlPointCount)
        let vBasis = BSplineBasis.values(parameter: clampedV, degree: vDegree, knots: vKnots, count: vControlPointCount)
        return try rationalPoint(uBasis: uBasis, vBasis: vBasis)
    }

    public func normal(u: Double, v: Double, tolerance: ModelingTolerance) throws -> Vector3D {
        try validate(tolerance: tolerance)
        guard try uDomain.contains(u, tolerance: tolerance),
              try vDomain.contains(v, tolerance: tolerance) else {
            throw GeometryError.invalidDistance(0.0)
        }
        let derivatives = try surfaceDerivatives(atU: u, v: v, tolerance: tolerance)
        return try strictSurfaceNormal(
            tangentU: derivatives.tangentU,
            tangentV: derivatives.tangentV,
            tolerance: tolerance
        )
    }

    public func differentialGeometry(
        atU u: Double,
        v: Double,
        tolerance: ModelingTolerance
    ) throws -> DifferentialGeometry {
        try validate(tolerance: tolerance)
        guard try uDomain.contains(u, tolerance: tolerance),
              try vDomain.contains(v, tolerance: tolerance) else {
            throw GeometryError.invalidDistance(0.0)
        }
        let derivatives = try surfaceDerivatives(atU: u, v: v, tolerance: tolerance)
        let tangentU = derivatives.tangentU
        let tangentV = derivatives.tangentV
        let secondDerivativeUU = derivatives.secondDerivativeUU
        let secondDerivativeUV = derivatives.secondDerivativeUV
        let secondDerivativeVV = derivatives.secondDerivativeVV
        let normal = try strictSurfaceNormal(tangentU: tangentU, tangentV: tangentV, tolerance: tolerance)
        let firstE = tangentU.dot(tangentU)
        let firstF = tangentU.dot(tangentV)
        let firstG = tangentV.dot(tangentV)
        let firstDeterminant = firstE * firstG - firstF * firstF
        let tangentULength = sqrt(max(0.0, firstE))
        let tangentVLength = sqrt(max(0.0, firstG))
        let determinantScale = firstE * firstG
        let normalizedDeterminant = determinantScale > 0.0
            ? max(0.0, firstDeterminant / determinantScale)
            : 0.0
        let angularMetricTolerance = max(
            sin(min(tolerance.angle, Double.pi * 0.5))
                * sin(min(tolerance.angle, Double.pi * 0.5)),
            tolerance.relative * tolerance.relative,
            Double.ulpOfOne * 512.0
        )
        guard tangentULength.isFinite,
              tangentVLength.isFinite,
              tangentULength > tolerance.distance,
              tangentVLength > tolerance.distance,
              firstDeterminant.isFinite,
              normalizedDeterminant > angularMetricTolerance else {
            throw KernelError(
                phase: .geometry,
                code: .singularSystem,
                residual: normalizedDeterminant,
                tolerance: tolerance,
                message: "Rational B-spline differential geometry is singular at the requested parameter."
            )
        }
        let secondL = secondDerivativeUU.dot(normal)
        let secondM = secondDerivativeUV.dot(normal)
        let secondN = secondDerivativeVV.dot(normal)
        let meanCurvature = (
            firstE * secondN - 2.0 * firstF * secondM + firstG * secondL
        ) / (2.0 * firstDeterminant)
        let gaussianCurvature = (
            secondL * secondN - secondM * secondM
        ) / firstDeterminant
        let normalCurvatureU = secondL / firstE
        let normalCurvatureV = secondN / firstG
        guard meanCurvature.isFinite,
              gaussianCurvature.isFinite,
              normalCurvatureU.isFinite,
              normalCurvatureV.isFinite else {
            throw KernelError(
                phase: .geometry,
                code: .resourceLimitExceeded,
                tolerance: tolerance,
                message: "Rational B-spline surface curvature exceeded the finite numeric range."
            )
        }
        let discriminant = max(meanCurvature * meanCurvature - gaussianCurvature, 0.0)
        let root = sqrt(discriminant)
        let firstPrincipal = meanCurvature - root
        let secondPrincipal = meanCurvature + root
        guard discriminant.isFinite,
              root.isFinite,
              firstPrincipal.isFinite,
              secondPrincipal.isFinite else {
            throw KernelError(
                phase: .geometry,
                code: .resourceLimitExceeded,
                tolerance: tolerance,
                message: "Rational B-spline principal curvature evaluation exceeded the finite numeric range."
            )
        }
        let principalDirections = try principalDirections(
            minimumCurvature: min(firstPrincipal, secondPrincipal),
            maximumCurvature: max(firstPrincipal, secondPrincipal),
            firstE: firstE,
            firstF: firstF,
            firstG: firstG,
            secondL: secondL,
            secondM: secondM,
            secondN: secondN,
            tangentU: tangentU,
            tangentV: tangentV,
            normal: normal,
            tolerance: tolerance
        )
        return DifferentialGeometry(
            position: derivatives.position,
            tangentU: tangentU,
            tangentV: tangentV,
            secondDerivativeUU: secondDerivativeUU,
            secondDerivativeUV: secondDerivativeUV,
            secondDerivativeVV: secondDerivativeVV,
            normal: normal,
            normalCurvatureU: normalCurvatureU,
            normalCurvatureV: normalCurvatureV,
            meanCurvature: meanCurvature,
            gaussianCurvature: gaussianCurvature,
            minimumPrincipalCurvature: min(firstPrincipal, secondPrincipal),
            maximumPrincipalCurvature: max(firstPrincipal, secondPrincipal),
            minimumPrincipalDirection: principalDirections.minimum,
            maximumPrincipalDirection: principalDirections.maximum
        )
    }

    public static func cubicBezierPatch(
        bottomLeft: Point3D,
        bottomRight: Point3D,
        topRight: Point3D,
        topLeft: Point3D
    ) -> BSplineSurface3D {
        var rows: [[Point3D]] = []
        for vIndex in 0..<4 {
            let v = Double(vIndex) / 3.0
            var row: [Point3D] = []
            for uIndex in 0..<4 {
                let u = Double(uIndex) / 3.0
                row.append(
                    bilinearPoint(
                        bottomLeft: bottomLeft,
                        bottomRight: bottomRight,
                        topRight: topRight,
                        topLeft: topLeft,
                        u: u,
                        v: v
                    )
                )
            }
            rows.append(row)
        }
        return BSplineSurface3D(
            uDegree: 3,
            vDegree: 3,
            uKnots: [0.0, 0.0, 0.0, 0.0, 1.0, 1.0, 1.0, 1.0],
            vKnots: [0.0, 0.0, 0.0, 0.0, 1.0, 1.0, 1.0, 1.0],
            controlPoints: rows
        )
    }

    public static func bilinearPatch(
        bottomLeft: Point3D,
        bottomRight: Point3D,
        topRight: Point3D,
        topLeft: Point3D
    ) -> BSplineSurface3D {
        BSplineSurface3D(
            uDegree: 1,
            vDegree: 1,
            uKnots: [0.0, 0.0, 1.0, 1.0],
            vKnots: [0.0, 0.0, 1.0, 1.0],
            controlPoints: [
                [bottomLeft, bottomRight],
                [topLeft, topRight],
            ]
        )
    }

    private enum CodingKeys: String, CodingKey {
        case uDegree
        case vDegree
        case uKnots
        case vKnots
        case controlPoints
        case weights
    }

    private struct WeightedVector {
        var point: Vector3D
        var weight: Double
    }

    private struct HomogeneousPoint {
        var point: Vector3D
        var weight: Double

        static let zero = HomogeneousPoint(point: .zero, weight: 0.0)

        func interpolated(to other: HomogeneousPoint, alpha: Double) -> HomogeneousPoint {
            HomogeneousPoint(
                point: point * (1.0 - alpha) + other.point * alpha,
                weight: weight * (1.0 - alpha) + other.weight * alpha
            )
        }
    }

    private struct KnotInsertion {
        var value: Double
        var span: Int
        var multiplicity: Int
        var sourceKnots: [Double]
        var knots: [Double]
    }

    struct RationalDerivatives {
        var position: Point3D
        var tangentU: Vector3D
        var tangentV: Vector3D
        var secondDerivativeUU: Vector3D
        var secondDerivativeUV: Vector3D
        var secondDerivativeVV: Vector3D
    }

    private func validateControlPoints() throws {
        guard uDegree >= 1,
              vDegree >= 1,
              controlPoints.count >= vDegree + 1,
              let firstRow = controlPoints.first,
              firstRow.count >= uDegree + 1 else {
            throw GeometryError.invalidDistance(0.0)
        }
        for row in controlPoints {
            guard row.count == firstRow.count else {
                throw GeometryError.invalidDistance(0.0)
            }
            for point in row {
                try point.validate()
            }
        }
    }

    private func validateWeights() throws {
        guard weights.count == vControlPointCount else {
            throw GeometryError.invalidDistance(Double(weights.count))
        }
        for row in weights {
            guard row.count == uControlPointCount else {
                throw GeometryError.invalidDistance(Double(row.count))
            }
            for weight in row {
                guard weight.isFinite else {
                    throw GeometryError.invalidCoordinate(weight)
                }
                guard weight > 0.0 else {
                    throw GeometryError.invalidDistance(weight)
                }
            }
        }
    }

    private func validateKnots(_ knots: [Double], degree: Int, controlPointCount: Int) throws {
        guard knots.count == controlPointCount + degree + 1 else {
            throw GeometryError.invalidDistance(Double(knots.count))
        }
        for knot in knots {
            guard knot.isFinite else {
                throw GeometryError.invalidCoordinate(knot)
            }
        }
        for index in 1..<knots.count {
            guard knots[index] >= knots[index - 1] else {
                throw GeometryError.invalidDistance(knots[index] - knots[index - 1])
            }
        }
        let lowerBound = knots[degree]
        let upperBound = knots[knots.count - degree - 1]
        guard upperBound > lowerBound else {
            throw GeometryError.invalidDistance(upperBound - lowerBound)
        }
        var runStart = 0
        while runStart < knots.count {
            var runEnd = runStart + 1
            while runEnd < knots.count, knots[runEnd] == knots[runStart] {
                runEnd += 1
            }
            let multiplicity = runEnd - runStart
            let value = knots[runStart]
            let maximumMultiplicity = value > lowerBound && value < upperBound
                ? degree
                : degree + 1
            guard multiplicity <= maximumMultiplicity else {
                throw GeometryError.invalidDistance(Double(multiplicity))
            }
            runStart = runEnd
        }
    }

    private func homogeneousControlRows() -> [[HomogeneousPoint]] {
        var result: [[HomogeneousPoint]] = []
        result.reserveCapacity(vControlPointCount)
        for vIndex in 0..<vControlPointCount {
            var row: [HomogeneousPoint] = []
            row.reserveCapacity(uControlPointCount)
            for uIndex in 0..<uControlPointCount {
                let weight = weights[vIndex][uIndex]
                row.append(HomogeneousPoint(
                    point: vector(from: controlPoints[vIndex][uIndex]) * weight,
                    weight: weight
                ))
            }
            result.append(row)
        }
        return result
    }

    private func knotInsertion(
        value: Double,
        knots: [Double],
        degree: Int,
        controlPointCount: Int,
        tolerance: ModelingTolerance
    ) throws -> KnotInsertion {
        guard value.isFinite else {
            throw GeometryError.invalidCoordinate(value)
        }
        let lowerBound = knots[degree]
        let upperBound = knots[controlPointCount]
        let parameterTolerance = parameterTolerance(
            for: knots,
            tolerance: tolerance
        )
        guard value > lowerBound + parameterTolerance,
              value < upperBound - parameterTolerance else {
            throw GeometryError.invalidDistance(value)
        }
        let multiplicity = knots.filter { abs($0 - value) <= parameterTolerance }.count
        guard multiplicity < degree else {
            throw GeometryError.invalidDistance(value)
        }
        let span = knotInsertionSpan(
            value: value,
            knots: knots,
            degree: degree,
            controlPointCount: controlPointCount
        )
        var insertedKnots = knots
        insertedKnots.insert(value, at: span + 1)
        return KnotInsertion(
            value: value,
            span: span,
            multiplicity: multiplicity,
            sourceKnots: knots,
            knots: insertedKnots
        )
    }

    private func knotInsertionSpan(
        value: Double,
        knots: [Double],
        degree: Int,
        controlPointCount: Int
    ) -> Int {
        for index in degree..<controlPointCount {
            if value < knots[index + 1] {
                return index
            }
        }
        return controlPointCount - 1
    }

    private func insertedControlLine(
        _ controlLine: [HomogeneousPoint],
        insertion: KnotInsertion,
        degree: Int
    ) throws -> [HomogeneousPoint] {
        var result = Array(repeating: HomogeneousPoint.zero, count: controlLine.count + 1)
        let firstUnchangedEnd = insertion.span - degree
        if firstUnchangedEnd >= 0 {
            for index in 0...firstUnchangedEnd {
                result[index] = controlLine[index]
            }
        }
        let secondUnchangedStart = insertion.span - insertion.multiplicity
        if secondUnchangedStart < controlLine.count {
            for index in secondUnchangedStart..<controlLine.count {
                result[index + 1] = controlLine[index]
            }
        }
        let firstBlended = firstUnchangedEnd + 1
        let lastBlended = secondUnchangedStart
        if firstBlended <= lastBlended {
            for index in firstBlended...lastBlended {
                let alpha = try knotBlendAlpha(
                    lower: insertion.sourceKnots[index],
                    upper: insertion.sourceKnots[index + degree],
                    value: insertion.value
                )
                result[index] = controlLine[index - 1].interpolated(
                    to: controlLine[index],
                    alpha: alpha
                )
            }
        }
        return result
    }

    private func knotBlendAlpha(
        lower: Double,
        upper: Double,
        value: Double
    ) throws -> Double {
        let denominator = upper - lower
        guard denominator > Double.ulpOfOne else {
            throw GeometryError.invalidDistance(denominator)
        }
        let alpha = (value - lower) / denominator
        guard alpha.isFinite else {
            throw GeometryError.invalidCoordinate(alpha)
        }
        return alpha
    }

    private func canonicalKnotValue(
        _ value: Double,
        in knots: [Double],
        tolerance: ModelingTolerance
    ) -> Double {
        let parameterTolerance = parameterTolerance(
            for: knots,
            tolerance: tolerance
        )
        for knot in knots where abs(knot - value) <= parameterTolerance {
            return knot
        }
        return value
    }

    private func parameterTolerance(
        for knots: [Double],
        tolerance: ModelingTolerance
    ) -> Double {
        let lower = knots.min() ?? 0.0
        let upper = knots.max() ?? 0.0
        let scale = max(abs(lower), abs(upper), upper - lower, 1.0)
        return max(
            tolerance.relative * scale,
            Double.ulpOfOne * scale * 256.0
        )
    }

    private func controlNet(
        from homogeneousRows: [[HomogeneousPoint]]
    ) throws -> (controlPoints: [[Point3D]], weights: [[Double]]) {
        var controlPoints: [[Point3D]] = []
        var weights: [[Double]] = []
        controlPoints.reserveCapacity(homogeneousRows.count)
        weights.reserveCapacity(homogeneousRows.count)
        for homogeneousRow in homogeneousRows {
            var pointRow: [Point3D] = []
            var weightRow: [Double] = []
            pointRow.reserveCapacity(homogeneousRow.count)
            weightRow.reserveCapacity(homogeneousRow.count)
            for homogeneousPoint in homogeneousRow {
                guard homogeneousPoint.weight.isFinite,
                      homogeneousPoint.weight > Double.ulpOfOne,
                      homogeneousPoint.point.isFinite else {
                    throw GeometryError.invalidDistance(homogeneousPoint.weight)
                }
                let point = homogeneousPoint.point / homogeneousPoint.weight
                pointRow.append(Point3D(x: point.x, y: point.y, z: point.z))
                weightRow.append(homogeneousPoint.weight)
            }
            controlPoints.append(pointRow)
            weights.append(weightRow)
        }
        return (controlPoints, weights)
    }

    private func rationalPoint(
        uBasis: [Double],
        vBasis: [Double]
    ) throws -> Point3D {
        let weighted = weightedSurfaceVector(uBasis: uBasis, vBasis: vBasis)
        let position = try rationalVector(weighted)
        return Point3D(x: position.x, y: position.y, z: position.z)
    }

    func surfaceDerivatives(
        atU u: Double,
        v: Double,
        tolerance: ModelingTolerance
    ) throws -> RationalDerivatives {
        let clampedU = BSplineBasis.clampedParameter(u, knots: uKnots, degree: uDegree)
        let clampedV = BSplineBasis.clampedParameter(v, knots: vKnots, degree: vDegree)
        let uBasis = BSplineBasis.values(parameter: clampedU, degree: uDegree, knots: uKnots, count: uControlPointCount)
        let vBasis = BSplineBasis.values(parameter: clampedV, degree: vDegree, knots: vKnots, count: vControlPointCount)
        let uFirstDerivative = BSplineBasis.derivativeValues(
            parameter: clampedU,
            degree: uDegree,
            derivativeOrder: 1,
            knots: uKnots,
            count: uControlPointCount
        )
        let vFirstDerivative = BSplineBasis.derivativeValues(
            parameter: clampedV,
            degree: vDegree,
            derivativeOrder: 1,
            knots: vKnots,
            count: vControlPointCount
        )
        let uSecondDerivative = BSplineBasis.derivativeValues(
            parameter: clampedU,
            degree: uDegree,
            derivativeOrder: 2,
            knots: uKnots,
            count: uControlPointCount
        )
        let vSecondDerivative = BSplineBasis.derivativeValues(
            parameter: clampedV,
            degree: vDegree,
            derivativeOrder: 2,
            knots: vKnots,
            count: vControlPointCount
        )
        let result = try rationalDerivatives(
            uBasis: uBasis,
            vBasis: vBasis,
            uFirstDerivative: uFirstDerivative,
            vFirstDerivative: vFirstDerivative,
            uSecondDerivative: uSecondDerivative,
            vSecondDerivative: vSecondDerivative
        )
        guard result.tangentU.isFinite,
              result.tangentV.isFinite,
              result.secondDerivativeUU.isFinite,
              result.secondDerivativeUV.isFinite,
              result.secondDerivativeVV.isFinite else {
            throw KernelError(
                phase: .geometry,
                code: .resourceLimitExceeded,
                tolerance: tolerance,
                message: "Rational B-spline surface differentiation exceeded the finite numeric range."
            )
        }
        return result
    }

    private func strictSurfaceNormal(
        tangentU: Vector3D,
        tangentV: Vector3D,
        tolerance: ModelingTolerance
    ) throws -> Vector3D {
        guard let normal = normalizedSurfaceNormal(tangentU: tangentU, tangentV: tangentV, tolerance: tolerance) else {
            throw KernelError(
                phase: .geometry,
                code: .singularSystem,
                residual: tangentU.cross(tangentV).length,
                tolerance: tolerance,
                message: "Rational B-spline surface normal is undefined at the requested singular parameter."
            )
        }
        return normal
    }

    private func normalizedSurfaceNormal(
        tangentU: Vector3D,
        tangentV: Vector3D,
        tolerance: ModelingTolerance
    ) -> Vector3D? {
        let tangentULength = tangentU.length
        let tangentVLength = tangentV.length
        guard tangentULength.isFinite,
              tangentVLength.isFinite,
              tangentULength > tolerance.distance,
              tangentVLength > tolerance.distance else {
            return nil
        }
        let normalizedU = tangentU / tangentULength
        let normalizedV = tangentV / tangentVLength
        let cross = normalizedU.cross(normalizedV)
        let sine = cross.length
        let angularTolerance = max(
            sin(min(tolerance.angle, Double.pi * 0.5)),
            tolerance.relative,
            Double.ulpOfOne * 256.0
        )
        guard sine.isFinite,
              sine > angularTolerance else {
            return nil
        }
        return cross / sine
    }

    private func rationalDerivatives(
        uBasis: [Double],
        vBasis: [Double],
        uFirstDerivative: [Double],
        vFirstDerivative: [Double],
        uSecondDerivative: [Double],
        vSecondDerivative: [Double]
    ) throws -> RationalDerivatives {
        let base = weightedSurfaceVector(uBasis: uBasis, vBasis: vBasis)
        let uFirst = weightedSurfaceVector(uBasis: uFirstDerivative, vBasis: vBasis)
        let vFirst = weightedSurfaceVector(uBasis: uBasis, vBasis: vFirstDerivative)
        let uSecond = weightedSurfaceVector(uBasis: uSecondDerivative, vBasis: vBasis)
        let uvSecond = weightedSurfaceVector(uBasis: uFirstDerivative, vBasis: vFirstDerivative)
        let vSecond = weightedSurfaceVector(uBasis: uBasis, vBasis: vSecondDerivative)
        let positionVector = try rationalVector(base)
        let tangentU = (uFirst.point - positionVector * uFirst.weight) / base.weight
        let tangentV = (vFirst.point - positionVector * vFirst.weight) / base.weight
        let secondDerivativeUU = (
            uSecond.point -
                positionVector * uSecond.weight -
                tangentU * (2.0 * uFirst.weight)
        ) / base.weight
        let secondDerivativeUV = (
            uvSecond.point -
                positionVector * uvSecond.weight -
                tangentU * vFirst.weight -
                tangentV * uFirst.weight
        ) / base.weight
        let secondDerivativeVV = (
            vSecond.point -
                positionVector * vSecond.weight -
                tangentV * (2.0 * vFirst.weight)
        ) / base.weight
        return RationalDerivatives(
            position: Point3D(x: positionVector.x, y: positionVector.y, z: positionVector.z),
            tangentU: tangentU,
            tangentV: tangentV,
            secondDerivativeUU: secondDerivativeUU,
            secondDerivativeUV: secondDerivativeUV,
            secondDerivativeVV: secondDerivativeVV
        )
    }

    private func rationalVector(_ weighted: WeightedVector) throws -> Vector3D {
        guard weighted.weight.isFinite,
              weighted.weight > Double.ulpOfOne,
              weighted.point.isFinite else {
            throw GeometryError.invalidDistance(weighted.weight)
        }
        return weighted.point / weighted.weight
    }

    private func weightedSurfaceVector(
        uBasis: [Double],
        vBasis: [Double]
    ) -> WeightedVector {
        var point = Vector3D.zero
        var weightSum = 0.0
        for vIndex in 0..<vControlPointCount {
            for uIndex in 0..<uControlPointCount {
                let basisWeight = uBasis[uIndex] * vBasis[vIndex] * weights[vIndex][uIndex]
                guard basisWeight != 0.0 else {
                    continue
                }
                point = point + vector(from: controlPoints[vIndex][uIndex]) * basisWeight
                weightSum += basisWeight
            }
        }
        return WeightedVector(point: point, weight: weightSum)
    }

    private func principalDirections(
        minimumCurvature: Double,
        maximumCurvature: Double,
        firstE: Double,
        firstF: Double,
        firstG: Double,
        secondL: Double,
        secondM: Double,
        secondN: Double,
        tangentU: Vector3D,
        tangentV: Vector3D,
        normal: Vector3D,
        tolerance: ModelingTolerance
    ) throws -> (minimum: Vector3D, maximum: Vector3D) {
        let curvatureGap = abs(maximumCurvature - minimumCurvature)
        let curvatureScale = max(
            1.0,
            abs(minimumCurvature),
            abs(maximumCurvature)
        )
        let curvatureTolerance = max(
            tolerance.relative * curvatureScale * 64.0,
            Double.ulpOfOne * curvatureScale * 512.0
        )
        guard curvatureGap > curvatureTolerance else {
            return try orthonormalTangentDirections(
                tangentU: tangentU,
                tangentV: tangentV,
                normal: normal,
                tolerance: tolerance
            )
        }

        guard let minimumDirection = try principalDirection(
            curvature: minimumCurvature,
            firstE: firstE,
            firstF: firstF,
            firstG: firstG,
            secondL: secondL,
            secondM: secondM,
            secondN: secondN,
            tangentU: tangentU,
            tangentV: tangentV,
            tolerance: tolerance
        ),
        let maximumDirection = try principalDirection(
            curvature: maximumCurvature,
            firstE: firstE,
            firstF: firstF,
            firstG: firstG,
            secondL: secondL,
            secondM: secondM,
            secondN: secondN,
            tangentU: tangentU,
            tangentV: tangentV,
            tolerance: tolerance
        ) else {
            throw KernelError(
                phase: .geometry,
                code: .singularSystem,
                residual: curvatureGap,
                tolerance: tolerance,
                message: "Rational B-spline principal directions could not be resolved at a non-umbilic parameter."
            )
        }
        return (minimumDirection, maximumDirection)
    }

    private func principalDirection(
        curvature: Double,
        firstE: Double,
        firstF: Double,
        firstG: Double,
        secondL: Double,
        secondM: Double,
        secondN: Double,
        tangentU: Vector3D,
        tangentV: Vector3D,
        tolerance: ModelingTolerance
    ) throws -> Vector3D? {
        let firstRowU = secondL - curvature * firstE
        let firstRowV = secondM - curvature * firstF
        let secondRowV = secondN - curvature * firstG
        let firstCandidate = tangentU * firstRowV - tangentV * firstRowU
        let secondCandidate = tangentU * secondRowV - tangentV * firstRowV
        let candidate = firstCandidate.length >= secondCandidate.length ? firstCandidate : secondCandidate
        let coefficientScale = max(
            1.0,
            abs(firstRowU),
            abs(firstRowV),
            abs(secondRowV)
        )
        let tangentScale = max(1.0, tangentU.length, tangentV.length)
        let candidateTolerance = max(
            tolerance.relative * coefficientScale * tangentScale * 64.0,
            Double.ulpOfOne * coefficientScale * tangentScale * 512.0
        )
        guard candidate.length.isFinite,
              candidate.length > candidateTolerance else {
            return nil
        }
        return try candidate.normalized(tolerance: tolerance.distance)
    }

    private func orthonormalTangentDirections(
        tangentU: Vector3D,
        tangentV: Vector3D,
        normal: Vector3D,
        tolerance: ModelingTolerance
    ) throws -> (minimum: Vector3D, maximum: Vector3D) {
        let first = try tangentU.normalized(tolerance: tolerance.distance)
        let projectedSecond = tangentV - first * tangentV.dot(first)
        if projectedSecond.length > tolerance.distance {
            return (first, try projectedSecond.normalized(tolerance: tolerance.distance))
        }
        let fallbackSecond = normal.cross(first)
        return (first, try fallbackSecond.normalized(tolerance: tolerance.distance))
    }

    private func vector(from point: Point3D) -> Vector3D {
        Vector3D(x: point.x, y: point.y, z: point.z)
    }

    private static func unitWeights(matching controlPoints: [[Point3D]]) -> [[Double]] {
        controlPoints.map { row in Array(repeating: 1.0, count: row.count) }
    }

    private static func bilinearPoint(
        bottomLeft: Point3D,
        bottomRight: Point3D,
        topRight: Point3D,
        topLeft: Point3D,
        u: Double,
        v: Double
    ) -> Point3D {
        let bottom = vector(from: bottomLeft) * (1.0 - u) + vector(from: bottomRight) * u
        let top = vector(from: topLeft) * (1.0 - u) + vector(from: topRight) * u
        let point = bottom * (1.0 - v) + top * v
        return Point3D(x: point.x, y: point.y, z: point.z)
    }

    private static func vector(from point: Point3D) -> Vector3D {
        Vector3D(x: point.x, y: point.y, z: point.z)
    }
}
