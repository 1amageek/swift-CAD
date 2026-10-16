#if !hasFeature(Embedded)
import Foundation
#elseif canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#elseif canImport(WASILibc)
import WASILibc
#else
#error("CADGeometry numeric algorithms require the target C math module.")
#endif
import CADCore

public struct BSplineSurface3D: Sendable, Hashable {
    public struct DifferentialGeometry: Sendable, Hashable {
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
    public var isUPeriodic: Bool
    public var isVPeriodic: Bool
    public var uPeriodicOrigin: Double?
    public var vPeriodicOrigin: Double?

    public init(
        uDegree: Int,
        vDegree: Int,
        uKnots: [Double],
        vKnots: [Double],
        controlPoints: [[Point3D]],
        weights: [[Double]]? = nil,
        isUPeriodic: Bool = false,
        isVPeriodic: Bool = false,
        uPeriodicOrigin: Double? = nil,
        vPeriodicOrigin: Double? = nil
    ) {
        self.uDegree = uDegree
        self.vDegree = vDegree
        self.uKnots = uKnots
        self.vKnots = vKnots
        self.controlPoints = controlPoints
        self.weights = weights ?? Self.unitWeights(matching: controlPoints)
        self.isUPeriodic = isUPeriodic
        self.isVPeriodic = isVPeriodic
        self.uPeriodicOrigin = uPeriodicOrigin
        self.vPeriodicOrigin = vPeriodicOrigin
    }

#if !hasFeature(Embedded)
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try container.validateOnlyExpectedKeys(
            [.uDegree, .vDegree, .uKnots, .vKnots, .controlPoints, .weights,
             .isUPeriodic, .isVPeriodic, .uPeriodicOrigin, .vPeriodicOrigin],
            in: decoder
        )
        let controlPoints = try container.decode([[Point3D]].self, forKey: .controlPoints)
        self.init(
            uDegree: try container.decode(Int.self, forKey: .uDegree),
            vDegree: try container.decode(Int.self, forKey: .vDegree),
            uKnots: try container.decode([Double].self, forKey: .uKnots),
            vKnots: try container.decode([Double].self, forKey: .vKnots),
            controlPoints: controlPoints,
            weights: try container.decode([[Double]].self, forKey: .weights),
            isUPeriodic: try container.decode(Bool.self, forKey: .isUPeriodic),
            isVPeriodic: try container.decode(Bool.self, forKey: .isVPeriodic),
            uPeriodicOrigin: try container.decodeIfPresent(Double.self, forKey: .uPeriodicOrigin),
            vPeriodicOrigin: try container.decodeIfPresent(Double.self, forKey: .vPeriodicOrigin)
        )
    }
#endif

#if !hasFeature(Embedded)
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(uDegree, forKey: .uDegree)
        try container.encode(vDegree, forKey: .vDegree)
        try container.encode(uKnots, forKey: .uKnots)
        try container.encode(vKnots, forKey: .vKnots)
        try container.encode(controlPoints, forKey: .controlPoints)
        try container.encode(weights, forKey: .weights)
        try container.encode(isUPeriodic, forKey: .isUPeriodic)
        try container.encode(isVPeriodic, forKey: .isVPeriodic)
        try container.encodeIfPresent(uPeriodicOrigin, forKey: .uPeriodicOrigin)
        try container.encodeIfPresent(vPeriodicOrigin, forKey: .vPeriodicOrigin)
    }
#endif

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
        axisDomain(direction: .u, fundamental: false)
    }

    public var vDomain: ParameterDomain {
        axisDomain(direction: .v, fundamental: false)
    }

    public func validate(tolerance: ModelingTolerance) throws {
        var execution = OriginalQueryExecution(budget: try OriginalQueryBudget(),
            limits: try OriginalQueryExecutionLimits(maximumValueDepth: 32, maximumCoefficientDepth: 32))
        try validate(tolerance: tolerance, using: &execution)
    }

    /// Native controls and cyclic source predicates share the caller's allowance.
    package func validate<A: ExactScalarAdmission & ~Copyable>(tolerance: ModelingTolerance, using execution: inout A) throws {
        try execution.consumeWork(1); try tolerance.validate()
        try validateControlPoints(using: &execution)
        try validateWeights(using: &execution)
        try validateKnots(uKnots, degree: uDegree, controlPointCount: uControlPointCount, using: &execution)
        try validateKnots(vKnots, degree: vDegree, controlPointCount: vControlPointCount, using: &execution)
        try execution.consumeWork(1); try uDomain.validate(tolerance: tolerance)
        try execution.consumeWork(1); try vDomain.validate(tolerance: tolerance)
        try validatePeriodicity(tolerance: tolerance, using: &execution)
    }

    public func insertingKnot(
        direction: SurfaceParameterDirection,
        value: Double,
        expansionOptions: PeriodicBSplineExpansionOptions = .init(),
        tolerance: ModelingTolerance
    ) throws -> BSplineSurface3D {
        var execution = OriginalQueryExecution(budget: try OriginalQueryBudget(),
            limits: try OriginalQueryExecutionLimits(maximumValueDepth: 32, maximumCoefficientDepth: 32))
        return try insertingKnot(direction: direction, value: value, expansionOptions: expansionOptions, tolerance: tolerance, using: &execution)
    }

    public func trimmed(
        uFrom startUParameter: Double,
        uTo endUParameter: Double,
        vFrom startVParameter: Double,
        vTo endVParameter: Double,
        expansionOptions: PeriodicBSplineExpansionOptions = .init(),
        tolerance: ModelingTolerance
    ) throws -> BSplineSurface3D {
        var execution = OriginalQueryExecution(budget: try OriginalQueryBudget(),
            limits: try OriginalQueryExecutionLimits(maximumValueDepth: 32, maximumCoefficientDepth: 32))
        return try trimmed(uFrom: startUParameter, uTo: endUParameter, vFrom: startVParameter, vTo: endVParameter, expansionOptions: expansionOptions, tolerance: tolerance, using: &execution)
    }

    public func insertingKnot<A: ExactScalarAdmission & ~Copyable>(
        direction: SurfaceParameterDirection,
        value: Double,
        expansionOptions: PeriodicBSplineExpansionOptions = .init(),
        tolerance: ModelingTolerance, using execution: inout A
    ) throws -> BSplineSurface3D {
        try execution.consumeWork(1)
        try validate(tolerance: tolerance, using: &execution)
        if isUPeriodic || isVPeriodic {
            return try refiningTensorAxis(direction: direction, value: value,
                options: expansionOptions, tolerance: tolerance, using: &execution)
        }
        let insertionValue: Double
        switch direction {
        case .u:
            insertionValue = try canonicalKnotValue(value, in: uKnots, tolerance: tolerance, using: &execution)
        case .v:
            insertionValue = try canonicalKnotValue(value, in: vKnots, tolerance: tolerance, using: &execution)
        }
        let homogeneousRows = try homogeneousControlRows(using: &execution)
        let insertedSurface: BSplineSurface3D
        switch direction {
        case .u:
            let insertion = try knotInsertion(
                value: insertionValue,
                knots: uKnots,
                degree: uDegree,
                controlPointCount: uControlPointCount,
                tolerance: tolerance, using: &execution
            )
            try execution.retainStorage(bytes: exactScalarPayloadBytes(count: homogeneousRows.count, of: [HomogeneousPoint].self))
            let updatedRows = try homogeneousRows.map { row in
                try insertedControlLine(row, insertion: insertion, degree: uDegree, using: &execution)
            }
            let controlNet = try controlNet(from: updatedRows, using: &execution)
            insertedSurface = BSplineSurface3D(
                uDegree: uDegree,
                vDegree: vDegree,
                uKnots: insertion.knots,
                vKnots: vKnots,
                controlPoints: controlNet.controlPoints,
                weights: controlNet.weights,
                isUPeriodic: isUPeriodic, isVPeriodic: isVPeriodic,
                uPeriodicOrigin: uPeriodicOrigin, vPeriodicOrigin: vPeriodicOrigin
            )
        case .v:
            let insertion = try knotInsertion(
                value: insertionValue,
                knots: vKnots,
                degree: vDegree,
                controlPointCount: vControlPointCount,
                tolerance: tolerance, using: &execution
            )
            try execution.retainStorage(bytes: exactScalarPayloadBytes(count: uControlPointCount, of: [HomogeneousPoint].self))
            var updatedColumns: [[HomogeneousPoint]] = []
            updatedColumns.reserveCapacity(uControlPointCount)
            for uIndex in 0..<uControlPointCount {
                try execution.consumeWork(1)
                try execution.retainStorage(bytes: exactScalarPayloadBytes(count: homogeneousRows.count, of: HomogeneousPoint.self))
                let column = try homogeneousRows.map { try execution.consumeWork(1); return $0[uIndex] }
                updatedColumns.append(try insertedControlLine(column, insertion: insertion, degree: vDegree, using: &execution))
            }
            let vCount = vControlPointCount.addingReportingOverflow(1)
            guard !vCount.overflow else { throw ExactScalarFailure.countOverflow }
            let updatedVCount = vCount.partialValue
            try retainNumericMatrix(rows: updatedVCount, columns: uControlPointCount, of: HomogeneousPoint.self, using: &execution)
            var updatedRows = Array(
                repeating: Array(repeating: HomogeneousPoint.zero, count: uControlPointCount),
                count: updatedVCount
            )
            for uIndex in 0..<uControlPointCount {
                try execution.consumeWork(1)
                for vIndex in 0..<updatedVCount {
                    try execution.consumeWork(1)
                    updatedRows[vIndex][uIndex] = updatedColumns[uIndex][vIndex]
                }
            }
            let controlNet = try controlNet(from: updatedRows, using: &execution)
            insertedSurface = BSplineSurface3D(
                uDegree: uDegree,
                vDegree: vDegree,
                uKnots: uKnots,
                vKnots: insertion.knots,
                controlPoints: controlNet.controlPoints,
                weights: controlNet.weights,
                isUPeriodic: isUPeriodic, isVPeriodic: isVPeriodic,
                uPeriodicOrigin: uPeriodicOrigin, vPeriodicOrigin: vPeriodicOrigin
            )
        }
        try insertedSurface.validate(tolerance: tolerance, using: &execution)
        return insertedSurface
    }

    public func trimmed<A: ExactScalarAdmission & ~Copyable>(
        uFrom startUParameter: Double,
        uTo endUParameter: Double,
        vFrom startVParameter: Double,
        vTo endVParameter: Double,
        expansionOptions: PeriodicBSplineExpansionOptions = .init(),
        tolerance: ModelingTolerance, using execution: inout A
    ) throws -> BSplineSurface3D {
        try execution.consumeWork(1)
        try validate(tolerance: tolerance, using: &execution)
        if isUPeriodic || isVPeriodic {
            return try restrictingTensor(uFrom: startUParameter, uTo: endUParameter,
                vFrom: startVParameter, vTo: endVParameter,
                options: expansionOptions, tolerance: tolerance, using: &execution)
        }
        let startU = try canonicalKnotValue(
            startUParameter,
            in: uKnots,
            tolerance: tolerance, using: &execution
        )
        let endU = try canonicalKnotValue(
            endUParameter,
            in: uKnots,
            tolerance: tolerance, using: &execution
        )
        let startV = try canonicalKnotValue(
            startVParameter,
            in: vKnots,
            tolerance: tolerance, using: &execution
        )
        let endV = try canonicalKnotValue(
            endVParameter,
            in: vKnots,
            tolerance: tolerance, using: &execution
        )
        return try BSplineSurfacePatchAssembler().trimmedSurface(
            source: self,
            uBounds: (startU, endU),
            vBounds: (startV, endV),
            tolerance: tolerance, using: &execution
        )
    }

    public func point(u: Double, v: Double, tolerance: ModelingTolerance) throws -> Point3D {
        var execution = OriginalQueryExecution(budget: try OriginalQueryBudget(),
            limits: try OriginalQueryExecutionLimits(maximumValueDepth: 32, maximumCoefficientDepth: 32))
        return try point(u: u, v: v, tolerance: tolerance, using: &execution)
    }

    public func normal(u: Double, v: Double, tolerance: ModelingTolerance) throws -> Vector3D {
        var execution = OriginalQueryExecution(budget: try OriginalQueryBudget(),
            limits: try OriginalQueryExecutionLimits(maximumValueDepth: 32, maximumCoefficientDepth: 32))
        return try normal(u: u, v: v, tolerance: tolerance, using: &execution)
    }

    public func differentialGeometry(
        u: Double,
        v: Double,
        tolerance: ModelingTolerance
    ) throws -> DifferentialGeometry {
        var execution = OriginalQueryExecution(budget: try OriginalQueryBudget(),
            limits: try OriginalQueryExecutionLimits(maximumValueDepth: 32, maximumCoefficientDepth: 32))
        return try differentialGeometry(u: u, v: v, tolerance: tolerance, using: &execution)
    }

    public func point<A: ExactScalarAdmission & ~Copyable>(u: Double, v: Double, tolerance: ModelingTolerance, using execution: inout A) throws -> Point3D {
        try execution.consumeWork(1)
        try validate(tolerance: tolerance, using: &execution)
        return try pointAssumingValid(u: u, v: v, tolerance: tolerance, using: &execution)
    }

    package func pointAssumingValid<A: ExactScalarAdmission & ~Copyable>(
        u: Double,
        v: Double,
        tolerance: ModelingTolerance, using execution: inout A
    ) throws -> Point3D {
        try execution.consumeWork(1)
        guard try uDomain.contains(u, tolerance: tolerance),
              try vDomain.contains(v, tolerance: tolerance) else {
            throw GeometryError.invalidDistance(0.0)
        }
        let clampedU = try basisParameter(u, direction: .u, tolerance: tolerance)
        let clampedV = try basisParameter(v, direction: .v, tolerance: tolerance)
        let uBasis = try BSplineBasis.values(parameter: clampedU, degree: uDegree, knots: uKnots, count: uControlPointCount, using: &execution)
        let vBasis = try BSplineBasis.values(parameter: clampedV, degree: vDegree, knots: vKnots, count: vControlPointCount, using: &execution)
        return try rationalPoint(uBasis: uBasis, vBasis: vBasis, using: &execution)
    }

    public func normal<A: ExactScalarAdmission & ~Copyable>(u: Double, v: Double, tolerance: ModelingTolerance, using execution: inout A) throws -> Vector3D {
        try execution.consumeWork(1)
        try validate(tolerance: tolerance, using: &execution)
        guard try uDomain.contains(u, tolerance: tolerance),
              try vDomain.contains(v, tolerance: tolerance) else {
            throw GeometryError.invalidDistance(0.0)
        }
        let derivatives = try surfaceDerivatives(u: u, v: v, tolerance: tolerance, using: &execution)
        return try strictSurfaceNormal(
            tangentU: derivatives.tangentU,
            tangentV: derivatives.tangentV,
            tolerance: tolerance
        )
    }

    /// Evaluates the original selected native side at its actual closed endpoint.
    package func normal<A: ExactScalarAdmission & ~Copyable>(
        u: Double, v: Double,
        owning span: PreparedBSplineSurfaceDifferentialEncloser.OriginalNativeSpan,
        tolerance: ModelingTolerance, using execution: inout A
    ) throws -> Vector3D {
        try execution.consumeWork(1)
        let derivatives = try selectedOriginalDerivatives(u: u, v: v, owning: span, tolerance: tolerance, using: &execution)
        return try strictSurfaceNormal(tangentU: derivatives.tangentU,
                                      tangentV: derivatives.tangentV, tolerance: tolerance)
    }

    public func differentialGeometry<A: ExactScalarAdmission & ~Copyable>(
        u: Double,
        v: Double,
        tolerance: ModelingTolerance, using execution: inout A
    ) throws -> DifferentialGeometry {
        try execution.consumeWork(1)
        try validate(tolerance: tolerance, using: &execution)
        guard try uDomain.contains(u, tolerance: tolerance),
              try vDomain.contains(v, tolerance: tolerance) else {
            throw GeometryError.invalidDistance(0.0)
        }
        let derivatives = try surfaceDerivatives(u: u, v: v, tolerance: tolerance, using: &execution)
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

#if !hasFeature(Embedded)
    private enum CodingKeys: String, CodingKey {
        case uDegree
        case vDegree
        case uKnots
        case vKnots
        case controlPoints
        case weights
        case isUPeriodic
        case isVPeriodic
        case uPeriodicOrigin
        case vPeriodicOrigin
    }
#endif

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

    private func validateControlPoints<A: ExactScalarAdmission & ~Copyable>(using execution: inout A) throws {
        guard uDegree >= 1,
              vDegree >= 1,
              vDegree < controlPoints.count,
              let firstRow = controlPoints.first,
              uDegree < firstRow.count else {
            throw GeometryError.invalidDistance(0.0)
        }
        for row in controlPoints {
            try execution.consumeWork(1)
            guard row.count == firstRow.count else {
                throw GeometryError.invalidDistance(0.0)
            }
            for point in row {
                try execution.consumeWork(1); try execution.consumeWork(1); try execution.consumeWork(1)
                try point.validate()
            }
        }
    }

    private func validateWeights<A: ExactScalarAdmission & ~Copyable>(using execution: inout A) throws {
        guard weights.count == vControlPointCount else {
            throw GeometryError.invalidDistance(Double(weights.count))
        }
        for row in weights {
            try execution.consumeWork(1)
            guard row.count == uControlPointCount else {
                throw GeometryError.invalidDistance(Double(row.count))
            }
            for weight in row {
                try execution.consumeWork(1)
                guard weight.isFinite else {
                    throw GeometryError.invalidCoordinate(weight)
                }
                guard weight > 0.0 else {
                    throw GeometryError.invalidDistance(weight)
                }
            }
        }
    }

    private func validateKnots<A: ExactScalarAdmission & ~Copyable>(_ knots: [Double], degree: Int, controlPointCount: Int, using execution: inout A) throws {
        let (count, overflow) = controlPointCount.addingReportingOverflow(degree)
        guard !overflow, count < Int.max, knots.count == count + 1 else {
            throw GeometryError.invalidDistance(Double(knots.count))
        }
        for knot in knots {
            try execution.consumeWork(1)
            guard knot.isFinite else {
                throw GeometryError.invalidCoordinate(knot)
            }
        }
        for index in 1..<knots.count {
            try execution.consumeWork(1)
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
            try execution.consumeWork(1)
            var runEnd = runStart + 1
            while runEnd < knots.count {
                try execution.consumeWork(1)
                guard knots[runEnd] == knots[runStart] else { break }
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

    private func homogeneousControlRows<A: ExactScalarAdmission & ~Copyable>(using execution: inout A) throws -> [[HomogeneousPoint]] {
        try execution.consumeWork(1)
        var result: [[HomogeneousPoint]] = []
        try execution.retainStorage(bytes: exactScalarPayloadBytes(count: vControlPointCount, of: [HomogeneousPoint].self))
        result.reserveCapacity(vControlPointCount)
        for vIndex in 0..<vControlPointCount {
            try execution.consumeWork(1)
            var row: [HomogeneousPoint] = []
            try execution.retainStorage(bytes: exactScalarPayloadBytes(count: uControlPointCount, of: HomogeneousPoint.self))
            row.reserveCapacity(uControlPointCount)
            for uIndex in 0..<uControlPointCount {
                try execution.consumeWork(1)
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

    private func knotInsertion<A: ExactScalarAdmission & ~Copyable>(
        value: Double,
        knots: [Double],
        degree: Int,
        controlPointCount: Int,
        tolerance: ModelingTolerance, using execution: inout A
    ) throws -> KnotInsertion {
        try execution.consumeWork(1)
        guard value.isFinite else {
            throw GeometryError.invalidCoordinate(value)
        }
        let lowerBound = knots[degree]
        let upperBound = knots[controlPointCount]
        let parameterTolerance = try parameterTolerance(
            for: knots,
            tolerance: tolerance, using: &execution
        )
        guard value > lowerBound + parameterTolerance,
              value < upperBound - parameterTolerance else {
            throw GeometryError.invalidDistance(value)
        }
        let multiplicity = try knots.reduce(0) {
            try execution.consumeWork(1)
            return $0 + (abs($1 - value) <= parameterTolerance ? 1 : 0)
        }
        guard multiplicity < degree else {
            throw GeometryError.invalidDistance(value)
        }
        let span = try knotInsertionSpan(
            value: value,
            knots: knots,
            degree: degree,
            controlPointCount: controlPointCount, using: &execution
        )
        let count = knots.count.addingReportingOverflow(1)
        guard !count.overflow else { throw ExactScalarFailure.countOverflow }
        try execution.retainStorage(bytes: exactScalarPayloadBytes(count: count.partialValue, of: Double.self))
        var insertedKnots = knots
        insertedKnots.reserveCapacity(count.partialValue)
        insertedKnots.insert(value, at: span + 1)
        return KnotInsertion(
            value: value,
            span: span,
            multiplicity: multiplicity,
            sourceKnots: knots,
            knots: insertedKnots
        )
    }

    private func knotInsertionSpan<A: ExactScalarAdmission & ~Copyable>(
        value: Double,
        knots: [Double],
        degree: Int,
        controlPointCount: Int, using execution: inout A
    ) throws -> Int {
        try execution.consumeWork(1)
        for index in degree..<controlPointCount {
            try execution.consumeWork(1)
            if value < knots[index + 1] {
                return index
            }
        }
        return controlPointCount - 1
    }

    private func insertedControlLine<A: ExactScalarAdmission & ~Copyable>(
        _ controlLine: [HomogeneousPoint],
        insertion: KnotInsertion,
        degree: Int, using execution: inout A
    ) throws -> [HomogeneousPoint] {
        try execution.consumeWork(1)
        let count = controlLine.count.addingReportingOverflow(1)
        guard !count.overflow else { throw ExactScalarFailure.countOverflow }
        try execution.retainStorage(bytes: exactScalarPayloadBytes(count: count.partialValue, of: HomogeneousPoint.self))
        var result = Array(repeating: HomogeneousPoint.zero, count: count.partialValue)
        let firstUnchangedEnd = insertion.span - degree
        if firstUnchangedEnd >= 0 {
            for index in 0...firstUnchangedEnd {
                try execution.consumeWork(1)
                result[index] = controlLine[index]
            }
        }
        let secondUnchangedStart = insertion.span - insertion.multiplicity
        if secondUnchangedStart < controlLine.count {
            for index in secondUnchangedStart..<controlLine.count {
                try execution.consumeWork(1)
                result[index + 1] = controlLine[index]
            }
        }
        let firstBlended = firstUnchangedEnd + 1
        let lastBlended = secondUnchangedStart
        if firstBlended <= lastBlended {
            for index in firstBlended...lastBlended {
                try execution.consumeWork(1)
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

    private func canonicalKnotValue<A: ExactScalarAdmission & ~Copyable>(
        _ value: Double,
        in knots: [Double],
        tolerance: ModelingTolerance, using execution: inout A
    ) throws -> Double {
        try execution.consumeWork(1)
        let parameterTolerance = try parameterTolerance(
            for: knots,
            tolerance: tolerance, using: &execution
        )
        for knot in knots {
            try execution.consumeWork(1)
            if abs(knot - value) <= parameterTolerance { return knot }
        }
        return value
    }

    private func parameterTolerance<A: ExactScalarAdmission & ~Copyable>(
        for knots: [Double],
        tolerance: ModelingTolerance, using execution: inout A
    ) throws -> Double {
        try execution.consumeWork(1)
        for _ in knots { try execution.consumeWork(2) }
        let lower = knots.min() ?? 0.0
        let upper = knots.max() ?? 0.0
        let scale = max(abs(lower), abs(upper), upper - lower, 1.0)
        return max(
            tolerance.relative * scale,
            Double.ulpOfOne * scale * 256.0
        )
    }

    private func controlNet<A: ExactScalarAdmission & ~Copyable>(
        from homogeneousRows: [[HomogeneousPoint]], using execution: inout A
    ) throws -> (controlPoints: [[Point3D]], weights: [[Double]]) {
        try execution.consumeWork(1)
        var controlPoints: [[Point3D]] = []
        var weights: [[Double]] = []
        try execution.retainStorage(bytes: exactScalarPayloadBytes(count: homogeneousRows.count, of: [Point3D].self))
        controlPoints.reserveCapacity(homogeneousRows.count)
        try execution.retainStorage(bytes: exactScalarPayloadBytes(count: homogeneousRows.count, of: [Double].self))
        weights.reserveCapacity(homogeneousRows.count)
        for homogeneousRow in homogeneousRows {
            try execution.consumeWork(1)
            var pointRow: [Point3D] = []
            var weightRow: [Double] = []
            try execution.retainStorage(bytes: exactScalarPayloadBytes(count: homogeneousRow.count, of: Point3D.self))
            pointRow.reserveCapacity(homogeneousRow.count)
            try execution.retainStorage(bytes: exactScalarPayloadBytes(count: homogeneousRow.count, of: Double.self))
            weightRow.reserveCapacity(homogeneousRow.count)
            for homogeneousPoint in homogeneousRow {
                try execution.consumeWork(1)
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

    func retainNumericMatrix<T, A: ExactScalarAdmission & ~Copyable>(rows: Int, columns: Int, of: T.Type, using execution: inout A) throws {
        try execution.retainStorage(bytes: exactScalarPayloadBytes(count: rows, of: [T].self))
        for _ in 0..<rows { try execution.retainStorage(bytes: exactScalarPayloadBytes(count: columns, of: T.self)) }
    }

    /// Immutable preparation; point and selected-normal laws keep their original order.
    struct StationNumericRow: Sendable {
        fileprivate let surface: BSplineSurface3D
        fileprivate let tolerance: ModelingTolerance
        fileprivate let uBasis: [Double]
        fileprivate let uLocal: [BSplineBasis.NonzeroValues]
        fileprivate let baseU: Double
        fileprivate let uSpanIndex: Int
        fileprivate let vSpanIndex: Int

        func point<A: ExactScalarAdmission & ~Copyable>(v: Double, using execution: inout A) throws -> Point3D {
            try execution.consumeWork(1)
            let parameter = try surface.basisParameter(v, direction: .v, tolerance: tolerance)
            let basis = try BSplineBasis.values(parameter: parameter, degree: surface.vDegree,
                                            knots: surface.vKnots, count: surface.vControlPointCount, using: &execution)
            return try surface.rationalPoint(uBasis: uBasis, vBasis: basis, using: &execution)
        }

        func normal<A: ExactScalarAdmission & ~Copyable>(baseV: Double, using execution: inout A) throws -> Vector3D {
            try execution.consumeWork(1)
            let derivatives = try surface.surfaceDerivativesAssumingPreparedU(u: baseU, v: baseV, tolerance: tolerance,
                owningUSpan: uSpanIndex, owningVSpan: vSpanIndex, retainedULocal: uLocal, using: &execution)
            return try surface.strictSurfaceNormal(tangentU: derivatives.tangentU,
                                                    tangentV: derivatives.tangentV, tolerance: tolerance)
        }
    }

    /// The selected native-span owner validates source and exact stations before entry.
    func prepareStationNumericRow<A: ExactScalarAdmission & ~Copyable>(u: Double, baseU: Double, owningUSpan: Int, owningVSpan: Int,
                                   tolerance: ModelingTolerance, using execution: inout A) throws
      -> StationNumericRow {
        try execution.consumeWork(1)
        let parameter = try basisParameter(u, direction: .u, tolerance: tolerance)
        let values = try BSplineBasis.values(parameter: parameter, degree: uDegree,
                                         knots: uKnots, count: uControlPointCount, using: &execution)
        let local = try BSplineBasis.nonzeroDerivativeValues(parameter: baseU, degree: uDegree,
            throughDerivativeOrder: 2, knots: uKnots, count: uControlPointCount,
            owningSpan: owningUSpan, tolerance: tolerance, using: &execution)
        try execution.checkpoint()
        return StationNumericRow(surface: self, tolerance: tolerance, uBasis: values, uLocal: local,
                                 baseU: baseU, uSpanIndex: owningUSpan, vSpanIndex: owningVSpan)
    }

    private func rationalPoint<A: ExactScalarAdmission & ~Copyable>(
        uBasis: [Double],
        vBasis: [Double], using execution: inout A
    ) throws -> Point3D {
        try execution.consumeWork(1)
        let weighted = try weightedSurfaceVector(uBasis: uBasis, vBasis: vBasis, using: &execution)
        let position = try rationalVector(weighted)
        return Point3D(x: position.x, y: position.y, z: position.z)
    }

    func surfaceDerivatives<A: ExactScalarAdmission & ~Copyable>(
        u: Double,
        v: Double,
        tolerance: ModelingTolerance,
        owningUSpan: Int? = nil,
        owningVSpan: Int? = nil, using execution: inout A
    ) throws -> RationalDerivatives {
        try execution.consumeWork(1)
        return try surfaceDerivativesAssumingPreparedU(u: u, v: v, tolerance: tolerance,
            owningUSpan: owningUSpan, owningVSpan: owningVSpan, retainedULocal: nil, using: &execution)
    }

    private func surfaceDerivativesAssumingPreparedU<A: ExactScalarAdmission & ~Copyable>(u: Double, v: Double,
        tolerance: ModelingTolerance, owningUSpan: Int?, owningVSpan: Int?,
        retainedULocal: [BSplineBasis.NonzeroValues]?, using execution: inout A) throws -> RationalDerivatives {
        try execution.consumeWork(1)
        // A validated selected token already resolved its exact original base station.
        // Canonical normalization here would replace a closed upper/left seam owner.
        let u = try owningUSpan == nil ? basisParameter(u, direction: .u, tolerance: tolerance) : u
        let v = try owningVSpan == nil ? basisParameter(v, direction: .v, tolerance: tolerance) : v
        // Only the (p + 1)(q + 1) basis products of the knot spans holding (u, v) are nonzero:
        // the local bases to second order, and one pass over those control points gathering the
        // weighted position and its five derivatives together.
        let uLocal = try retainedULocal ?? owningUSpan.map {
            try BSplineBasis.nonzeroDerivativeValues(parameter: u, degree: uDegree, throughDerivativeOrder: 2,
                knots: uKnots, count: uControlPointCount, owningSpan: $0, tolerance: tolerance, using: &execution)
        } ?? BSplineBasis.nonzeroDerivativeValues(parameter: u, degree: uDegree, throughDerivativeOrder: 2,
                                                  knots: uKnots, count: uControlPointCount, using: &execution)
        let vLocal = try owningVSpan.map {
            try BSplineBasis.nonzeroDerivativeValues(parameter: v, degree: vDegree, throughDerivativeOrder: 2,
                knots: vKnots, count: vControlPointCount, owningSpan: $0, tolerance: tolerance, using: &execution)
        } ?? BSplineBasis.nonzeroDerivativeValues(parameter: v, degree: vDegree, throughDerivativeOrder: 2,
                                                  knots: vKnots, count: vControlPointCount, using: &execution)
        var (s0, su, sv, suu, suv, svv) = (Vector3D.zero, Vector3D.zero, Vector3D.zero, Vector3D.zero, Vector3D.zero, Vector3D.zero)
        var (w0, wu, wv, wuu, wuv, wvv) = (0.0, 0.0, 0.0, 0.0, 0.0, 0.0)
        var uniformWeight: Double?
        var hasUniformOwningWeights = true
        let (u0, v0) = (uLocal[0].startIndex, vLocal[0].startIndex)
        let (uValues, uFirsts, uSeconds) = (uLocal[0].values, uLocal[1].values, uLocal[2].values)
        let (vValues, vFirsts, vSeconds) = (vLocal[0].values, vLocal[1].values, vLocal[2].values)
        for j in vValues.indices {
            try execution.consumeWork(1)
            let vIndex = v0 + j
            guard vIndex >= 0, vIndex < vControlPointCount else {
                hasUniformOwningWeights = false
                continue
            }
            let (bv, dv, ddv) = (vValues[j], vFirsts[j], vSeconds[j])
            let pointRow = controlPoints[vIndex], weightRow = weights[vIndex]
            for i in uValues.indices {
                try execution.consumeWork(1)
                let uIndex = u0 + i
                guard uIndex >= 0, uIndex < uControlPointCount else {
                    hasUniformOwningWeights = false
                    continue
                }
                let w = weightRow[uIndex]
                // Every control of the owning native span participates in this proof,
                // including controls whose value basis vanishes at a knot endpoint.
                if let uniformWeight {
                    hasUniformOwningWeights = hasUniformOwningWeights && w == uniformWeight
                } else {
                    uniformWeight = w
                    hasUniformOwningWeights = hasUniformOwningWeights && w.isFinite && w > 0
                }
                let p = vector(from: pointRow[uIndex]) * w
                let (bu, du, ddu) = (uValues[i], uFirsts[i], uSeconds[i])
                // Position, ∂u, ∂v, ∂uu, ∂uv, ∂vv of the homogeneous surface.
                let (f0, fu, fv, fuu, fuv, fvv) = (bu * bv, du * bv, bu * dv, ddu * bv, du * dv, bu * ddv)
                s0 = s0 + p * f0; su = su + p * fu; sv = sv + p * fv
                suu = suu + p * fuu; suv = suv + p * fuv; svv = svv + p * fvv
                w0 += w * f0; wu += w * fu; wv += w * fv; wuu += w * fuu; wuv += w * fuv; wvv += w * fvv
            }
        }
        let result: RationalDerivatives
        if hasUniformOwningWeights, let uniformWeight {
            // Partition of unity retains the common positive original weight.
            // Polynomial derivatives skip quotient terms and their roundoff residues.
            let position = try rationalVector(WeightedVector(point: s0, weight: uniformWeight))
            result = RationalDerivatives(position: Point3D(x: position.x, y: position.y, z: position.z),
                                         tangentU: su / uniformWeight, tangentV: sv / uniformWeight,
                                         secondDerivativeUU: suu / uniformWeight,
                                         secondDerivativeUV: suv / uniformWeight,
                                         secondDerivativeVV: svv / uniformWeight)
        } else {
            try execution.retainStorage(bytes: exactScalarPayloadBytes(count: 6, of: WeightedVector.self))
            let sums = [WeightedVector(point: s0, weight: w0), WeightedVector(point: su, weight: wu), WeightedVector(point: sv, weight: wv),
                        WeightedVector(point: suu, weight: wuu), WeightedVector(point: suv, weight: wuv), WeightedVector(point: svv, weight: wvv)]
            result = try rationalDerivatives(base: sums[0], uFirst: sums[1], vFirst: sums[2], uSecond: sums[3], uvSecond: sums[4],
                                             vSecond: sums[5], using: &execution)
        }
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

    private func rationalDerivatives<A: ExactScalarAdmission & ~Copyable>(
        base: WeightedVector,
        uFirst: WeightedVector,
        vFirst: WeightedVector,
        uSecond: WeightedVector,
        uvSecond: WeightedVector,
        vSecond: WeightedVector, using execution: inout A
    ) throws -> RationalDerivatives {
        try execution.consumeWork(1)
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

    private func weightedSurfaceVector<A: ExactScalarAdmission & ~Copyable>(
        uBasis: [Double],
        vBasis: [Double], using execution: inout A
    ) throws -> WeightedVector {
        try execution.consumeWork(1)
        var point = Vector3D.zero
        var weightSum = 0.0
        var uniformWeight: Double?
        var hasUniformWeights = true
        for vIndex in 0..<vControlPointCount {
            try execution.consumeWork(1)
            for uIndex in 0..<uControlPointCount {
                try execution.consumeWork(1)
                let weight = weights[vIndex][uIndex]
                // Retain the existing full-net point evaluation and establish
                // global uniformity during its existing weight reads, before
                // skipping any zero basis products. No additional scan is needed.
                if let uniformWeight {
                    hasUniformWeights = hasUniformWeights && weight == uniformWeight
                } else {
                    uniformWeight = weight
                    hasUniformWeights = hasUniformWeights && weight.isFinite && weight > 0
                }
                let basisWeight = uBasis[uIndex] * vBasis[vIndex] * weight
                guard basisWeight != 0.0 else {
                    continue
                }
                point = point + vector(from: controlPoints[vIndex][uIndex]) * basisWeight
                weightSum += basisWeight
            }
        }
        if hasUniformWeights, let uniformWeight {
            weightSum = uniformWeight
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
        // The candidate is a product of the rows and the tangents, so its rounding scales with
        // theirs; a fixed floor would reject every direction of a nearly flat surface measured
        // in metres, whose rows are minute.
        let coefficientScale = max(
            abs(firstRowU),
            abs(firstRowV),
            abs(secondRowV)
        )
        let tangentScale = max(tangentU.length, tangentV.length)
        let candidateTolerance = max(
            tolerance.relative * coefficientScale * tangentScale * 64.0,
            Double.ulpOfOne * coefficientScale * tangentScale * 512.0
        )
        guard candidate.length.isFinite,
              candidate.length > candidateTolerance else {
            return nil
        }
        return candidate / candidate.length
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

#if !hasFeature(Embedded)
extension BSplineSurface3D: Codable {}
extension BSplineSurface3D.DifferentialGeometry: Codable {}
#endif
