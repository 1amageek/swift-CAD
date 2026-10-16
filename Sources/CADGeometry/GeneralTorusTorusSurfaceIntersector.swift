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

struct GeneralTorusTorusSurfaceIntersector {
    struct Torus {
        let center: Point3D
        let axis: Vector3D
        let majorRadius: Double
        let minorRadius: Double

        var surface: Surface3D {
            .analytic(.torus(
                center: center,
                axis: axis,
                majorRadius: majorRadius,
                minorRadius: minorRadius
            ))
        }
    }

    struct Configuration {
        let parameterized: Torus
        let reference: Torus
        let zeroRadial: Vector3D
        let quarterRadial: Vector3D
        let characteristicLength: Double

        func radial(at angle: Double) -> Vector3D {
            zeroRadial * cos(angle) + quarterRadial * sin(angle)
        }

        func meridianCurve(at angle: Double) -> Curve3D {
            let radial = radial(at: angle)
            return .analytic(.ellipse(
                center: parameterized.center + radial * parameterized.majorRadius,
                normal: radial.cross(parameterized.axis),
                majorAxis: radial,
                majorRadius: parameterized.minorRadius,
                minorRadius: parameterized.minorRadius
            ))
        }

        func point(majorAngle: Double, minorAngle: Double) -> Point3D {
            let radial = radial(at: majorAngle)
            return parameterized.center
                + radial * (
                    parameterized.majorRadius
                        + parameterized.minorRadius * cos(minorAngle)
                )
                + parameterized.axis
                    * (parameterized.minorRadius * sin(minorAngle))
        }
    }

    private struct Cell {
        let majorAngle: Interval
        let minorAngle: Interval
        let depth: Int
    }

    private struct Interval {
        let lower: Double
        let upper: Double

        init(_ lower: Double, _ upper: Double) {
            self.lower = min(lower, upper).nextDown
            self.upper = max(lower, upper).nextUp
        }

        static func constant(_ value: Double) -> Interval {
            Interval(value, value)
        }

        var width: Double {
            upper - lower
        }

        var midpoint: Double {
            lower + width * 0.5
        }

        var containsZero: Bool {
            lower <= 0.0 && upper >= 0.0
        }

        func isDisjoint(with other: Interval) -> Bool {
            upper < other.lower || lower > other.upper
        }

        var minimumAbsoluteValue: Double {
            containsZero ? 0.0 : min(abs(lower), abs(upper)).nextDown
        }

        var maximumAbsoluteValue: Double {
            max(abs(lower), abs(upper)).nextUp
        }

        func adding(_ other: Interval) -> Interval {
            Interval(lower + other.lower, upper + other.upper)
        }

        func subtracting(_ other: Interval) -> Interval {
            Interval(lower - other.upper, upper - other.lower)
        }

        func multiplied(by other: Interval) -> Interval {
            let lowerLower = lower * other.lower
            let lowerUpper = lower * other.upper
            let upperLower = upper * other.lower
            let upperUpper = upper * other.upper
            return Interval(
                min(min(lowerLower, lowerUpper), min(upperLower, upperUpper)),
                max(max(lowerLower, lowerUpper), max(upperLower, upperUpper))
            )
        }

        func scaled(by scalar: Double) -> Interval {
            scalar >= 0.0
                ? Interval(lower * scalar, upper * scalar)
                : Interval(upper * scalar, lower * scalar)
        }

        func squared() -> Interval {
            if containsZero {
                return Interval(0.0, max(lower * lower, upper * upper))
            }
            return Interval(
                min(lower * lower, upper * upper),
                max(lower * lower, upper * upper)
            )
        }
    }

    private struct RootAssignment {
        let values: [Double]
        let candidateIndices: [Int]
        let cost: Double
        let secondCost: Double

        var maximumMovement: Double
    }

    struct MeridianRootCompletenessCertificate: Hashable, Sendable {
        let processedCellCount: Int
    }

    struct BranchSpatialDifferentialPartition: Hashable, Sendable {
        let branchIndex: Int
        let majorAngleLower: Double
        let majorAngleUpper: Double
        let minorFirstDerivativeMagnitudeUpperBound: Double
        let minorSecondDerivativeMagnitudeUpperBound: Double
        let minorThirdDerivativeMagnitudeUpperBound: Double
    }

    struct BranchSpatialDifferentialCertificate: Hashable, Sendable {
        let processedCellCount: Int
        let partitions: [BranchSpatialDifferentialPartition]
    }

    struct RootTrace: Hashable, Sendable {
        let parameters: [Double]
        let valuesByBranch: [[Double]]
        let permutation: [Int]

        func referenceValue<A: ExactScalarAdmission & ~Copyable>(branch: Int, at parameter: Double, using execution: inout A) throws -> Double {
            try execution.checkpoint()
            let result = try referenceValueImplementation(branch: branch, at: parameter, using: &execution)
            try execution.checkpoint()
            return result
        }


        private func referenceValueImplementation<A: ExactScalarAdmission & ~Copyable>(branch: Int, at parameter: Double, using execution: inout A) throws -> Double {
        try execution.checkpoint()
        try execution.consumeWork(1)
            if parameter <= parameters[0] {
                return valuesByBranch[branch][0]
            }
            if parameter >= parameters[parameters.count - 1] {
                return valuesByBranch[branch][parameters.count - 1]
            }
            var lower = 0
            var upper = parameters.count - 1
            while upper - lower > 1 {
                try execution.consumeWork(1)
                let middle = (lower + upper) / 2
                if parameters[middle] <= parameter {
                    lower = middle
                } else {
                    upper = middle
                }
            }
            let span = parameters[upper] - parameters[lower]
            let fraction = span > 0.0
                ? (parameter - parameters[lower]) / span
                : 0.0
            let lowerValue = valuesByBranch[branch][lower]
            let upperValue = valuesByBranch[branch][upper]
            return lowerValue + (upperValue - lowerValue) * fraction
        }
    }

    // FIXME(INCOMPLETE_IMPLEMENTATION): Ordinary SSI dispatch reaches this direct entry.
    // The former numerical/tolerance branches did not establish original common-set
    // authority. U4 must supply complete original source/UV coverage before success.
    func intersections(
        first: CanonicalAnalyticSurface.Torus,
        second: CanonicalAnalyticSurface.Torus,
        firstSurface: Surface3D,
        secondSurface: Surface3D,
        options: SurfaceSurfaceIntersectionOptions,
        tolerance: ModelingTolerance,
        using execution: inout OriginalQueryExecution
    ) throws -> [SurfaceSurfaceIntersection] {
        execution.context = execution.context.at(stage: .relation)
        do {
            try execution.checkpoint()
            throw KernelError(phase: .geometry, code: .unsupportedCapability, tolerance: tolerance,
                message: "GeneralTorusTorusSurfaceIntersector requires complete original source relation authority.")
        } catch { throw OriginalQueryFailure.published(error, context: execution.context, tolerance: tolerance) }
    }

    // FIXME(INCOMPLETE_IMPLEMENTATION): Existing candidate/source helper methods call
    // this ordinary publication entry. It performs no numeric solve or fallback;
    // U4 must provide source-bound relation proof and direct execution before success.
    func intersections(
        first: CanonicalAnalyticSurface.Torus,
        second: CanonicalAnalyticSurface.Torus,
        firstSurface: Surface3D,
        secondSurface: Surface3D,
        options: SurfaceSurfaceIntersectionOptions,
        tolerance: ModelingTolerance
    ) throws -> [SurfaceSurfaceIntersection] {
        var execution = try OriginalQueryExecution.independentGeometry()
        return try intersections(first: first, second: second, firstSurface: firstSurface, secondSurface: secondSurface, options: options, tolerance: tolerance, using: &execution)
    }



    private func certifiedIntersection(
        _ derived: SurfaceSurfaceIntersection,
        congruentCurve: CertifiedCongruentTorusTorusIntersectionCurve,
        firstSurface: Surface3D,
        secondSurface: Surface3D,
        tolerance: ModelingTolerance
    , using execution: inout OriginalQueryExecution) throws -> SurfaceSurfaceIntersection {
        try execution.checkpoint()
        try execution.consumeWork(1)
        guard case let .curve(derivedCurve) = derived else {
            throw KernelError(
                phase: .geometry,
                code: .intersectionFailure,
                tolerance: tolerance,
                message: "A congruent torus-torus component did not produce a derived curve cache."
            )
        }
        let truth = try CertifiedAnalyticAnalyticIntersectionCurve(
            congruentTorusTorusCurve: congruentCurve,
            firstSurface: firstSurface,
            secondSurface: secondSurface,
            tolerance: tolerance
        )
        return .curve(try SurfaceSurfaceIntersectionCurve(
            truth: .analyticAnalytic(truth),
            derivedRepresentation: derivedCurve.derivedRepresentation,
            kind: derivedCurve.kind,
            firstSurfaceAnchor: derivedCurve.firstSurfaceAnchor,
            secondSurfaceAnchor: derivedCurve.secondSurfaceAnchor,
            tolerance: tolerance
        ))
    }

    private func certifiedIntersection(
        _ derived: SurfaceSurfaceIntersection,
        proceduralCurve: CertifiedGeneralTorusTorusIntersectionCurve,
        firstSurface: Surface3D,
        secondSurface: Surface3D,
        tolerance: ModelingTolerance
    , using execution: inout OriginalQueryExecution) throws -> SurfaceSurfaceIntersection {
        try execution.checkpoint()
        try execution.consumeWork(1)
        guard case let .curve(derivedCurve) = derived else {
            throw KernelError(
                phase: .geometry,
                code: .intersectionFailure,
                tolerance: tolerance,
                message: "A regular general torus-torus component did not produce a derived curve cache."
            )
        }
        let truth = try CertifiedAnalyticAnalyticIntersectionCurve(
            generalTorusTorusCurve: proceduralCurve,
            firstSurface: firstSurface,
            secondSurface: secondSurface,
            tolerance: tolerance
        )
        return .curve(try SurfaceSurfaceIntersectionCurve(
            truth: .analyticAnalytic(truth),
            derivedRepresentation: derivedCurve.derivedRepresentation,
            kind: derivedCurve.kind,
            firstSurfaceAnchor: derivedCurve.firstSurfaceAnchor,
            secondSurfaceAnchor: derivedCurve.secondSurfaceAnchor,
            tolerance: tolerance
        ))
    }

    func makeConfiguration(
        parameterized: Torus,
        reference: Torus,
        tolerance: ModelingTolerance
    ) throws -> Configuration {
        var execution = try OriginalQueryExecution.independentGeometry()
        return try makeConfiguration(parameterized: parameterized, reference: reference, tolerance: tolerance, using: &execution)
    }


    func makeConfiguration(
        parameterized: Torus,
        reference: Torus,
        tolerance: ModelingTolerance
    , using execution: inout OriginalQueryExecution) throws -> Configuration {
        try execution.checkpoint()
        let result = try makeConfigurationImplementation(parameterized: parameterized, reference: reference, tolerance: tolerance, using: &execution)
        try execution.checkpoint()
        return result
    }



    private func makeConfigurationImplementation(
        parameterized: Torus,
        reference: Torus,
        tolerance: ModelingTolerance
    , using execution: inout OriginalQueryExecution) throws -> Configuration {
        try execution.checkpoint()
        try execution.consumeWork(1)
        let basis = try analyticOrthonormalBasis(
            parameterized.axis,
            tolerance: tolerance
        )
        return Configuration(
            parameterized: parameterized,
            reference: reference,
            zeroRadial: basis.u,
            quarterRadial: basis.v,
            characteristicLength: max(
                parameterized.majorRadius + parameterized.minorRadius,
                reference.majorRadius + reference.minorRadius,
                (parameterized.center - reference.center).length,
                1.0
            )
        )
    }

    func certifyConstantSimpleMeridianRoots(
        configuration: Configuration,
        options: SurfaceSurfaceIntersectionOptions,
        tolerance: ModelingTolerance
    ) throws -> MeridianRootCompletenessCertificate {
        var execution = try OriginalQueryExecution.independentGeometry()
        return try certifyConstantSimpleMeridianRoots(configuration: configuration, options: options, tolerance: tolerance, using: &execution)
    }


    func certifyConstantSimpleMeridianRoots(
        configuration: Configuration,
        options: SurfaceSurfaceIntersectionOptions,
        tolerance: ModelingTolerance
    , using execution: inout OriginalQueryExecution) throws -> MeridianRootCompletenessCertificate {
        try execution.checkpoint()
        let result = try certifyConstantSimpleMeridianRootsImplementation(configuration: configuration, options: options, tolerance: tolerance, using: &execution)
        try execution.checkpoint()
        return result
    }



    private func certifyConstantSimpleMeridianRootsImplementation(
        configuration: Configuration,
        options: SurfaceSurfaceIntersectionOptions,
        tolerance: ModelingTolerance
    , using execution: inout OriginalQueryExecution) throws -> MeridianRootCompletenessCertificate {
        try execution.checkpoint()
        try execution.consumeWork(1)
        let maximumDepth = min(options.maximumSubdivisionDepth + 16, 24)
        let maximumCellCount = min(
            max(options.maximumSeedCount * 64, 16_384),
            65_536
        )
        let period = 2.0 * Double.pi
        try execution.retainStorage(bytes: exactScalarPayloadBytes(count: 1, of: Cell.self))
        var cells = [Cell(
            majorAngle: Interval(0.0, period),
            minorAngle: Interval(0.0, period),
            depth: 0
        )]
        var cellsCapacity = cells.count
        var processedCellCount = 0
        while let cell = cells.popLast() {
            try execution.visitGeometricCell(depth: cell.depth)
            processedCellCount += 1
            guard processedCellCount <= maximumCellCount else {
                throw KernelError(
                    phase: .geometry,
                    code: .resourceLimitExceeded,
                    residual: Double(processedCellCount),
                    tolerance: tolerance,
                    message: "Torus-torus meridian tangency certification exceeded its cell limit."
                )
            }
            let values = (try implicitAndMinorDerivativeIntervals(
                majorAngle: cell.majorAngle,
                minorAngle: cell.minorAngle,
                configuration: configuration
            , using: &execution))
            if values.implicit.containsZero == false
                || values.minorDerivative.containsZero == false {
                continue
            }
            if (try excludesMeridianTangencyWithKrawczyk(
                cell: cell,
                configuration: configuration
            , using: &execution)) {
                continue
            }
            guard cell.depth < maximumDepth else {
                throw KernelError(
                    phase: .geometry,
                    code: .resourceLimitExceeded,
                    residual: max(
                        cell.majorAngle.width,
                        cell.minorAngle.width
                    ),
                    tolerance: tolerance,
                    message: "General torus-torus subdivision exhausted its budget before certifying a meridian tangency or root merge."
                )
            }
            if cell.majorAngle.width >= cell.minorAngle.width {
                let middle = cell.majorAngle.midpoint
                try CertifiedAnalyticCurveEvaluation.append(Cell(
                    majorAngle: Interval(middle, cell.majorAngle.upper),
                    minorAngle: cell.minorAngle,
                    depth: cell.depth + 1
                ), to: &cells, using: &execution, capacity: &cellsCapacity)
                try CertifiedAnalyticCurveEvaluation.append(Cell(
                    majorAngle: Interval(cell.majorAngle.lower, middle),
                    minorAngle: cell.minorAngle,
                    depth: cell.depth + 1
                ), to: &cells, using: &execution, capacity: &cellsCapacity)
            } else {
                let middle = cell.minorAngle.midpoint
                try CertifiedAnalyticCurveEvaluation.append(Cell(
                    majorAngle: cell.majorAngle,
                    minorAngle: Interval(middle, cell.minorAngle.upper),
                    depth: cell.depth + 1
                ), to: &cells, using: &execution, capacity: &cellsCapacity)
                try CertifiedAnalyticCurveEvaluation.append(Cell(
                    majorAngle: cell.majorAngle,
                    minorAngle: Interval(cell.minorAngle.lower, middle),
                    depth: cell.depth + 1
                ), to: &cells, using: &execution, capacity: &cellsCapacity)
            }
        }
        return MeridianRootCompletenessCertificate(
            processedCellCount: processedCellCount
        )
    }

    private func excludesMeridianTangencyWithKrawczyk<A: ExactScalarAdmission & ~Copyable>(
        cell: Cell,
        configuration: Configuration
    , using execution: inout A) throws -> Bool {
        try execution.checkpoint()
        try execution.consumeWork(1)
        let centerMajor = cell.majorAngle.midpoint
        let centerMinor = cell.minorAngle.midpoint
        let center = (try implicitDifferentialIntervals(
            majorAngle: .constant(centerMajor),
            minorAngle: .constant(centerMinor),
            configuration: configuration
        , using: &execution))
        let jacobian00 = center.majorDerivative.midpoint
        let jacobian01 = center.minorDerivative.midpoint
        let jacobian10 = center.majorMinorDerivative.midpoint
        let jacobian11 = center.minorMinorDerivative.midpoint
        let determinant = jacobian00 * jacobian11
            - jacobian01 * jacobian10
        guard determinant.isFinite, determinant != 0.0 else {
            return false
        }
        let inverse00 = jacobian11 / determinant
        let inverse01 = -jacobian01 / determinant
        let inverse10 = -jacobian10 / determinant
        let inverse11 = jacobian00 / determinant
        guard inverse00.isFinite,
              inverse01.isFinite,
              inverse10.isFinite,
              inverse11.isFinite else {
            return false
        }

        let domain = (try implicitDifferentialIntervals(
            majorAngle: cell.majorAngle,
            minorAngle: cell.minorAngle,
            configuration: configuration
        , using: &execution))
        let centerImageMajor = Interval.constant(centerMajor).subtracting(
            center.implicit.scaled(by: inverse00)
                .adding(center.minorDerivative.scaled(by: inverse01))
        )
        let centerImageMinor = Interval.constant(centerMinor).subtracting(
            center.implicit.scaled(by: inverse10)
                .adding(center.minorDerivative.scaled(by: inverse11))
        )
        let residual00 = Interval.constant(1.0).subtracting(
            domain.majorDerivative.scaled(by: inverse00)
                .adding(domain.majorMinorDerivative.scaled(by: inverse01))
        )
        let residual01 = domain.minorDerivative.scaled(by: inverse00)
            .adding(domain.minorMinorDerivative.scaled(by: inverse01))
            .scaled(by: -1.0)
        let residual10 = domain.majorDerivative.scaled(by: inverse10)
            .adding(domain.majorMinorDerivative.scaled(by: inverse11))
            .scaled(by: -1.0)
        let residual11 = Interval.constant(1.0).subtracting(
            domain.minorDerivative.scaled(by: inverse10)
                .adding(domain.minorMinorDerivative.scaled(by: inverse11))
        )
        let majorDelta = Interval(
            cell.majorAngle.lower - centerMajor,
            cell.majorAngle.upper - centerMajor
        )
        let minorDelta = Interval(
            cell.minorAngle.lower - centerMinor,
            cell.minorAngle.upper - centerMinor
        )
        let majorImage = centerImageMajor
            .adding(residual00.multiplied(by: majorDelta))
            .adding(residual01.multiplied(by: minorDelta))
        let minorImage = centerImageMinor
            .adding(residual10.multiplied(by: majorDelta))
            .adding(residual11.multiplied(by: minorDelta))
        return majorImage.isDisjoint(with: cell.majorAngle)
            || minorImage.isDisjoint(with: cell.minorAngle)
    }

    private func implicitAndMinorDerivativeIntervals<A: ExactScalarAdmission & ~Copyable>(
        majorAngle: Interval,
        minorAngle: Interval,
        configuration: Configuration
    , using execution: inout A) throws -> (implicit: Interval, minorDerivative: Interval) {
        try execution.checkpoint()
        try execution.consumeWork(1)
        let majorCosine = (try cosineInterval(majorAngle, using: &execution))
        let majorSine = (try sineInterval(majorAngle, using: &execution))
        let minorCosine = (try cosineInterval(minorAngle, using: &execution))
        let minorSine = (try sineInterval(minorAngle, using: &execution))

        let radialX = radialInterval(
            zero: configuration.zeroRadial.x,
            quarter: configuration.quarterRadial.x,
            cosine: majorCosine,
            sine: majorSine
        )
        let radialY = radialInterval(
            zero: configuration.zeroRadial.y,
            quarter: configuration.quarterRadial.y,
            cosine: majorCosine,
            sine: majorSine
        )
        let radialZ = radialInterval(
            zero: configuration.zeroRadial.z,
            quarter: configuration.quarterRadial.z,
            cosine: majorCosine,
            sine: majorSine
        )
        let radialScale = Interval.constant(
            configuration.parameterized.majorRadius
        ).adding(
            minorCosine.scaled(by: configuration.parameterized.minorRadius)
        )
        let axialScale = minorSine.scaled(
            by: configuration.parameterized.minorRadius
        )
        let centerOffset = configuration.parameterized.center
            - configuration.reference.center
        let x = Interval.constant(centerOffset.x)
            .adding(radialX.multiplied(by: radialScale))
            .adding(axialScale.scaled(by: configuration.parameterized.axis.x))
        let y = Interval.constant(centerOffset.y)
            .adding(radialY.multiplied(by: radialScale))
            .adding(axialScale.scaled(by: configuration.parameterized.axis.y))
        let z = Interval.constant(centerOffset.z)
            .adding(radialZ.multiplied(by: radialScale))
            .adding(axialScale.scaled(by: configuration.parameterized.axis.z))

        let minorRadialScale = minorSine.scaled(
            by: -configuration.parameterized.minorRadius
        )
        let minorAxialScale = minorCosine.scaled(
            by: configuration.parameterized.minorRadius
        )
        let minorTangentX = radialX.multiplied(by: minorRadialScale)
            .adding(minorAxialScale.scaled(by: configuration.parameterized.axis.x))
        let minorTangentY = radialY.multiplied(by: minorRadialScale)
            .adding(minorAxialScale.scaled(by: configuration.parameterized.axis.y))
        let minorTangentZ = radialZ.multiplied(by: minorRadialScale)
            .adding(minorAxialScale.scaled(by: configuration.parameterized.axis.z))

        let squaredLength = x.squared().adding(y.squared()).adding(z.squared())
        let axialDistance = x.scaled(by: configuration.reference.axis.x)
            .adding(y.scaled(by: configuration.reference.axis.y))
            .adding(z.scaled(by: configuration.reference.axis.z))
        let radiusDifference = configuration.reference.majorRadius
            * configuration.reference.majorRadius
            - configuration.reference.minorRadius
                * configuration.reference.minorRadius
        let q = squaredLength.adding(.constant(radiusDifference))
        let radialSquared = squaredLength.subtracting(axialDistance.squared())
        let majorFactor = 4.0 * configuration.reference.majorRadius
            * configuration.reference.majorRadius
        let implicit = q.squared().subtracting(
            radialSquared.scaled(by: majorFactor)
        )

        let referenceRadialX = x.subtracting(
            axialDistance.scaled(by: configuration.reference.axis.x)
        )
        let referenceRadialY = y.subtracting(
            axialDistance.scaled(by: configuration.reference.axis.y)
        )
        let referenceRadialZ = z.subtracting(
            axialDistance.scaled(by: configuration.reference.axis.z)
        )
        let gradientX = q.multiplied(by: x).scaled(by: 4.0)
            .subtracting(referenceRadialX.scaled(by: 2.0 * majorFactor))
        let gradientY = q.multiplied(by: y).scaled(by: 4.0)
            .subtracting(referenceRadialY.scaled(by: 2.0 * majorFactor))
        let gradientZ = q.multiplied(by: z).scaled(by: 4.0)
            .subtracting(referenceRadialZ.scaled(by: 2.0 * majorFactor))
        let minorDerivative = gradientX.multiplied(by: minorTangentX)
            .adding(gradientY.multiplied(by: minorTangentY))
            .adding(gradientZ.multiplied(by: minorTangentZ))
        return (implicit, minorDerivative)
    }

    func certifyBranchSpatialDifferentials(
        trace: RootTrace,
        configuration: Configuration,
        options: SurfaceSurfaceIntersectionOptions,
        tolerance: ModelingTolerance
    ) throws -> BranchSpatialDifferentialCertificate {
        var execution = try OriginalQueryExecution.independentGeometry()
        return try certifyBranchSpatialDifferentials(trace: trace, configuration: configuration, options: options, tolerance: tolerance, using: &execution)
    }


    func certifyBranchSpatialDifferentials(
        trace: RootTrace,
        configuration: Configuration,
        options: SurfaceSurfaceIntersectionOptions,
        tolerance: ModelingTolerance
    , using execution: inout OriginalQueryExecution) throws -> BranchSpatialDifferentialCertificate {
        try execution.checkpoint()
        let result = try certifyBranchSpatialDifferentialsImplementation(trace: trace, configuration: configuration, options: options, tolerance: tolerance, using: &execution)
        try execution.checkpoint()
        return result
    }



    private func certifyBranchSpatialDifferentialsImplementation(
        trace: RootTrace,
        configuration: Configuration,
        options: SurfaceSurfaceIntersectionOptions,
        tolerance: ModelingTolerance
    , using execution: inout OriginalQueryExecution) throws -> BranchSpatialDifferentialCertificate {
        try execution.checkpoint()
        try execution.consumeWork(1)
        struct BranchCell {
            let branchIndex: Int
            let majorAngle: Interval
            let depth: Int
        }

        let period = 2.0 * Double.pi
        let initialSegmentCount = 128
        let maximumDepth = min(options.maximumSubdivisionDepth + 12, 24)
        let maximumCellCount = min(
            max(options.maximumSeedCount * 128, 32_768),
            131_072
        )
        var cells: [BranchCell] = []
        var cellsCapacity = cells.count
        for branchIndex in trace.valuesByBranch.indices {
            try execution.consumeWork(1)
            for segmentIndex in 0..<initialSegmentCount {
                try execution.consumeWork(1)
                try CertifiedAnalyticCurveEvaluation.append(BranchCell(
                    branchIndex: branchIndex,
                    majorAngle: Interval(
                        period * Double(segmentIndex)
                            / Double(initialSegmentCount),
                        period * Double(segmentIndex + 1)
                            / Double(initialSegmentCount)
                    ),
                    depth: 0
                ), to: &cells, using: &execution, capacity: &cellsCapacity)
            }
        }
        var processedCellCount = 0
        var partitions: [BranchSpatialDifferentialPartition] = []
        var partitionsCapacity = partitions.count
        while let cell = cells.popLast() {
            try execution.visitGeometricCell(depth: cell.depth)
            processedCellCount += 1
            guard processedCellCount <= maximumCellCount else {
                throw KernelError(
                    phase: .geometry,
                    code: .resourceLimitExceeded,
                    residual: Double(processedCellCount),
                    tolerance: tolerance,
                    message: "General torus-torus branch differential certification exceeded its cell limit."
                )
            }
            let majorMidpoint = cell.majorAngle.midpoint
            let branchCenters = try (try CertifiedAnalyticCurveEvaluation.map(trace.valuesByBranch.indices, using: &execution) { branchIndex, execution in
                try refinedMinorRoot(
                    majorAngle: majorMidpoint,
                    initialMinorAngle: (try trace.referenceValue(
                        branch: branchIndex,
                        at: majorMidpoint
                    , using: &execution)),
                    configuration: configuration,
                    tolerance: tolerance
                , using: &execution)
             })
            let center = branchCenters[cell.branchIndex]
            let otherIndices = try CertifiedAnalyticCurveEvaluation.filter(branchCenters.indices,
                using: &execution) { index, _ in index != cell.branchIndex }
            let distances = try CertifiedAnalyticCurveEvaluation.map(otherIndices,
                using: &execution) { index, _ in
                periodicDistance(branchCenters[index], center, period: period)
            }
            let nearestOtherRootDistance = distances.min() ?? period
            let halfWidth = min(
                period / 256.0,
                nearestOtherRootDistance * 0.25
            )
            let minorAngle = Interval(
                center - halfWidth,
                center + halfWidth
            )
            let lowerBoundary = (try implicitDifferentialIntervals(
                majorAngle: cell.majorAngle,
                minorAngle: .constant(minorAngle.lower),
                configuration: configuration
            , using: &execution)).implicit
            let upperBoundary = (try implicitDifferentialIntervals(
                majorAngle: cell.majorAngle,
                minorAngle: .constant(minorAngle.upper),
                configuration: configuration
            , using: &execution)).implicit
            let values = (try implicitDifferentialIntervals(
                majorAngle: cell.majorAngle,
                minorAngle: minorAngle,
                configuration: configuration
            , using: &execution))
            let boundariesHaveOppositeSigns = (
                lowerBoundary.upper < 0.0 && upperBoundary.lower > 0.0
            ) || (
                lowerBoundary.lower > 0.0 && upperBoundary.upper < 0.0
            )
            if boundariesHaveOppositeSigns,
               values.minorDerivative.containsZero == false {
                let denominator = values.minorDerivative.minimumAbsoluteValue
                let minorFirstDerivative = (
                    values.majorDerivative.maximumAbsoluteValue / denominator
                ).nextUp
                let minorSecondDerivative = ((
                    values.majorMajorDerivative.maximumAbsoluteValue
                        + 2.0
                            * values.majorMinorDerivative.maximumAbsoluteValue
                            * minorFirstDerivative
                        + values.minorMinorDerivative.maximumAbsoluteValue
                            * minorFirstDerivative * minorFirstDerivative
                ) / denominator).nextUp
                let minorFirst = Interval(
                    -minorFirstDerivative,
                    minorFirstDerivative
                )
                let minorSecond = Interval(
                    -minorSecondDerivative,
                    minorSecondDerivative
                )
                let minorFirstSquared = minorFirst.squared()
                let minorFirstCubed = minorFirstSquared.multiplied(
                    by: minorFirst
                )
                let minorFirstTimesSecond = minorFirst.multiplied(
                    by: minorSecond
                )
                let spatialFirst = (try CertifiedAnalyticCurveEvaluation.map(values.majorTangent.indices, using: &execution) { index, execution in
                    values.majorTangent[index].adding(
                        values.minorTangent[index].multiplied(by: minorFirst)
                    )
                 })
                let spatialSecond = (try CertifiedAnalyticCurveEvaluation.map(values.majorSecond.indices, using: &execution) { index, execution in
                    values.majorSecond[index]
                        .adding(
                            values.majorMinor[index]
                                .multiplied(by: minorFirst)
                                .scaled(by: 2.0)
                        )
                        .adding(
                            values.minorSecond[index]
                                .multiplied(by: minorFirstSquared)
                        )
                        .adding(
                            values.minorTangent[index]
                                .multiplied(by: minorSecond)
                        )
                 })
                let knownSpatialThird = (try CertifiedAnalyticCurveEvaluation.map(values.majorThird.indices, using: &execution) { index, execution in
                    values.majorThird[index]
                        .adding(
                            values.majorMajorMinor[index]
                                .multiplied(by: minorFirst)
                                .scaled(by: 3.0)
                        )
                        .adding(
                            values.majorMinorMinor[index]
                                .multiplied(by: minorFirstSquared)
                                .scaled(by: 3.0)
                        )
                        .adding(
                            values.minorThird[index]
                                .multiplied(by: minorFirstCubed)
                        )
                        .adding(
                            values.majorMinor[index]
                                .multiplied(by: minorSecond)
                                .scaled(by: 3.0)
                        )
                        .adding(
                            values.minorSecond[index]
                                .multiplied(by: minorFirstTimesSecond)
                                .scaled(by: 3.0)
                        )
                 })
                let knownThirdImplicit = torusThirdDifferentialInterval(
                    offset: values.offset,
                    first: spatialFirst,
                    second: spatialFirst,
                    third: spatialFirst
                ).adding(
                    torusHessianBilinearInterval(
                        offset: values.offset,
                        q: values.q,
                        first: spatialSecond,
                        second: spatialFirst,
                        torus: configuration.reference
                    ).scaled(by: 3.0)
                ).adding(
                    dotInterval(values.gradient, knownSpatialThird)
                )
                let minorThirdDerivative = (
                    knownThirdImplicit.maximumAbsoluteValue / denominator
                ).nextUp
                try CertifiedAnalyticCurveEvaluation.append(BranchSpatialDifferentialPartition(
                    branchIndex: cell.branchIndex,
                    majorAngleLower: cell.majorAngle.lower,
                    majorAngleUpper: cell.majorAngle.upper,
                    minorFirstDerivativeMagnitudeUpperBound:
                        minorFirstDerivative,
                    minorSecondDerivativeMagnitudeUpperBound:
                        minorSecondDerivative,
                    minorThirdDerivativeMagnitudeUpperBound:
                        minorThirdDerivative
                ), to: &partitions, using: &execution, capacity: &partitionsCapacity)
                continue
            }
            guard cell.depth < maximumDepth else {
                throw KernelError(
                    phase: .geometry,
                    code: .resourceLimitExceeded,
                    residual: cell.majorAngle.width,
                    tolerance: tolerance,
                    message: "General torus-torus branch tube could not certify a unique simple root."
                )
            }
            let middle = cell.majorAngle.midpoint
            try CertifiedAnalyticCurveEvaluation.append(BranchCell(
                branchIndex: cell.branchIndex,
                majorAngle: Interval(middle, cell.majorAngle.upper),
                depth: cell.depth + 1
            ), to: &cells, using: &execution, capacity: &cellsCapacity)
            try CertifiedAnalyticCurveEvaluation.append(BranchCell(
                branchIndex: cell.branchIndex,
                majorAngle: Interval(cell.majorAngle.lower, middle),
                depth: cell.depth + 1
            ), to: &cells, using: &execution, capacity: &cellsCapacity)
        }
        guard partitions.isEmpty == false else {
            throw KernelError(
                phase: .geometry,
                code: .intersectionFailure,
                tolerance: tolerance,
                message: "General torus-torus branch differential certification produced no partitions."
            )
        }
        return BranchSpatialDifferentialCertificate(
            processedCellCount: processedCellCount,
            partitions: partitions
        )
    }

    private func implicitDifferentialIntervals<A: ExactScalarAdmission & ~Copyable>(
        majorAngle: Interval,
        minorAngle: Interval,
        configuration: Configuration
    , using execution: inout A) throws -> (
        implicit: Interval,
        majorDerivative: Interval,
        minorDerivative: Interval,
        majorMajorDerivative: Interval,
        majorMinorDerivative: Interval,
        minorMinorDerivative: Interval,
        offset: [Interval],
        q: Interval,
        gradient: [Interval],
        majorTangent: [Interval],
        minorTangent: [Interval],
        majorSecond: [Interval],
        majorMinor: [Interval],
        minorSecond: [Interval],
        majorThird: [Interval],
        majorMajorMinor: [Interval],
        majorMinorMinor: [Interval],
        minorThird: [Interval]
    ) {
        try execution.checkpoint()
        try execution.consumeWork(1)
        let majorCosine = (try cosineInterval(majorAngle, using: &execution))
        let majorSine = (try sineInterval(majorAngle, using: &execution))
        let minorCosine = (try cosineInterval(minorAngle, using: &execution))
        let minorSine = (try sineInterval(minorAngle, using: &execution))
        try execution.retainStorage(bytes: exactScalarPayloadBytes(count: 3, of: Interval.self))
        let radial = [
            radialInterval(
                zero: configuration.zeroRadial.x,
                quarter: configuration.quarterRadial.x,
                cosine: majorCosine,
                sine: majorSine
            ),
            radialInterval(
                zero: configuration.zeroRadial.y,
                quarter: configuration.quarterRadial.y,
                cosine: majorCosine,
                sine: majorSine
            ),
            radialInterval(
                zero: configuration.zeroRadial.z,
                quarter: configuration.quarterRadial.z,
                cosine: majorCosine,
                sine: majorSine
            ),
        ]
        try execution.retainStorage(bytes: exactScalarPayloadBytes(count: 3, of: Interval.self))
        let radialFirst = [
            majorSine.scaled(by: -configuration.zeroRadial.x)
                .adding(majorCosine.scaled(
                    by: configuration.quarterRadial.x
                )),
            majorSine.scaled(by: -configuration.zeroRadial.y)
                .adding(majorCosine.scaled(
                    by: configuration.quarterRadial.y
                )),
            majorSine.scaled(by: -configuration.zeroRadial.z)
                .adding(majorCosine.scaled(
                    by: configuration.quarterRadial.z
                )),
        ]
        let radialSecond = (try CertifiedAnalyticCurveEvaluation.map(radial, using: &execution) { element, execution in  element.scaled(by: -1.0)  })
        let radialScale = Interval.constant(configuration.parameterized.majorRadius)
            .adding(
                minorCosine.scaled(
                    by: configuration.parameterized.minorRadius
                )
            )
        let axialScale = minorSine.scaled(
            by: configuration.parameterized.minorRadius
        )
        let centerOffset = configuration.parameterized.center
            - configuration.reference.center
        try execution.retainStorage(bytes: exactScalarPayloadBytes(count: 3, of: Double.self))
        let offset = [centerOffset.x, centerOffset.y, centerOffset.z]
        let coordinates = (try CertifiedAnalyticCurveEvaluation.map(radial.indices, using: &execution) { index, execution in
            Interval.constant(offset[index])
                .adding(radial[index].multiplied(by: radialScale))
                .adding(
                    axialScale.scaled(
                        by: axisComponent(
                            configuration.parameterized.axis,
                            at: index
                        )
                    )
                )
         })
        let minorRadialScale = minorSine.scaled(
            by: -configuration.parameterized.minorRadius
        )
        let minorAxialScale = minorCosine.scaled(
            by: configuration.parameterized.minorRadius
        )
        let majorTangent = (try CertifiedAnalyticCurveEvaluation.map(radialFirst, using: &execution) { element, execution in 
            element.multiplied(by: radialScale)
         })
        let minorTangent = (try CertifiedAnalyticCurveEvaluation.map(radial.indices, using: &execution) { index, execution in
            radial[index].multiplied(by: minorRadialScale)
                .adding(
                    minorAxialScale.scaled(
                        by: axisComponent(
                            configuration.parameterized.axis,
                            at: index
                        )
                    )
                )
         })
        let majorSecond = (try CertifiedAnalyticCurveEvaluation.map(radialSecond, using: &execution) { element, execution in 
            element.multiplied(by: radialScale)
         })
        let majorMinor = (try CertifiedAnalyticCurveEvaluation.map(radialFirst, using: &execution) { element, execution in 
            element.multiplied(by: minorRadialScale)
         })
        let minorSecondRadialScale = minorCosine.scaled(
            by: -configuration.parameterized.minorRadius
        )
        let minorSecondAxialScale = minorSine.scaled(
            by: -configuration.parameterized.minorRadius
        )
        let minorSecond = (try CertifiedAnalyticCurveEvaluation.map(radial.indices, using: &execution) { index, execution in
            radial[index].multiplied(by: minorSecondRadialScale)
                .adding(
                    minorSecondAxialScale.scaled(
                        by: axisComponent(
                            configuration.parameterized.axis,
                            at: index
                        )
                    )
                )
         })
        let majorThird = (try CertifiedAnalyticCurveEvaluation.map(majorTangent, using: &execution) { element, execution in  element.scaled(by: -1.0)  })
        let majorMajorMinor = (try CertifiedAnalyticCurveEvaluation.map(radial, using: &execution) { element, execution in 
            element.multiplied(by: minorRadialScale).scaled(by: -1.0)
         })
        let majorMinorMinorScale = minorCosine.scaled(
            by: -configuration.parameterized.minorRadius
        )
        let majorMinorMinor = (try CertifiedAnalyticCurveEvaluation.map(radialFirst, using: &execution) { element, execution in 
            element.multiplied(by: majorMinorMinorScale)
         })
        let minorThird = (try CertifiedAnalyticCurveEvaluation.map(minorTangent, using: &execution) { element, execution in  element.scaled(by: -1.0)  })
        let squaredLength = coordinates.reduce(Interval.constant(0.0)) {
            $0.adding($1.squared())
        }
        let axialDistance = dotInterval(
            coordinates,
            configuration.reference.axis
        )
        let radiusDifference = configuration.reference.majorRadius
            * configuration.reference.majorRadius
            - configuration.reference.minorRadius
                * configuration.reference.minorRadius
        let q = squaredLength.adding(.constant(radiusDifference))
        let radialSquared = squaredLength.subtracting(axialDistance.squared())
        let majorFactor = 4.0 * configuration.reference.majorRadius
            * configuration.reference.majorRadius
        let implicit = q.squared().subtracting(
            radialSquared.scaled(by: majorFactor)
        )
        let referenceRadial = (try CertifiedAnalyticCurveEvaluation.map(coordinates.indices, using: &execution) { index, execution in
            coordinates[index].subtracting(
                axialDistance.scaled(
                    by: axisComponent(
                        configuration.reference.axis,
                        at: index
                    )
                )
            )
         })
        let gradient = (try CertifiedAnalyticCurveEvaluation.map(coordinates.indices, using: &execution) { index, execution in
            q.multiplied(by: coordinates[index]).scaled(by: 4.0)
                .subtracting(
                    referenceRadial[index].scaled(by: 2.0 * majorFactor)
                )
         })
        let majorDerivative = dotInterval(gradient, majorTangent)
        let minorDerivative = dotInterval(gradient, minorTangent)
        let majorMajorDerivative = torusHessianBilinearInterval(
            offset: coordinates,
            q: q,
            first: majorTangent,
            second: majorTangent,
            torus: configuration.reference
        ).adding(dotInterval(gradient, majorSecond))
        let majorMinorDerivative = torusHessianBilinearInterval(
            offset: coordinates,
            q: q,
            first: majorTangent,
            second: minorTangent,
            torus: configuration.reference
        ).adding(dotInterval(gradient, majorMinor))
        let minorMinorDerivative = torusHessianBilinearInterval(
            offset: coordinates,
            q: q,
            first: minorTangent,
            second: minorTangent,
            torus: configuration.reference
        ).adding(dotInterval(gradient, minorSecond))
        return (
            implicit,
            majorDerivative,
            minorDerivative,
            majorMajorDerivative,
            majorMinorDerivative,
            minorMinorDerivative,
            coordinates,
            q,
            gradient,
            majorTangent,
            minorTangent,
            majorSecond,
            majorMinor,
            minorSecond,
            majorThird,
            majorMajorMinor,
            majorMinorMinor,
            minorThird
        )
    }

    private func refinedMinorRoot(
        majorAngle: Double,
        initialMinorAngle: Double,
        configuration: Configuration,
        tolerance: ModelingTolerance
    , using execution: inout OriginalQueryExecution) throws -> Double {
        try execution.checkpoint()
        try execution.consumeWork(1)
        var minorAngle = initialMinorAngle
        let derivativeThreshold = max(
            tolerance.angle * pow(configuration.characteristicLength, 4.0),
            Double.ulpOfOne
                * pow(configuration.characteristicLength, 4.0) * 256.0
        )
        var converged = false
        for _ in 0..<16 {
            try execution.consumeWork(1)
            let valueAndDerivative = implicitValueAndMinorDerivative(
                majorAngle: majorAngle,
                minorAngle: minorAngle,
                configuration: configuration
            )
            guard valueAndDerivative.value.isFinite,
                  valueAndDerivative.minorDerivative.isFinite,
                  abs(valueAndDerivative.minorDerivative)
                    > derivativeThreshold else {
                throw KernelError(
                    phase: .geometry,
                    code: .singularSystem,
                    residual: abs(valueAndDerivative.minorDerivative),
                    tolerance: tolerance,
                    message: "General torus-torus branch refinement reached a meridian-tangent root."
                )
            }
            let step = valueAndDerivative.value
                / valueAndDerivative.minorDerivative
            minorAngle -= step
            if abs(step) <= max(
                tolerance.angle * 0.25,
                Double.ulpOfOne * 256.0
            ) {
                converged = true
                break
            }
        }
        guard converged,
              periodicDistance(
                  minorAngle,
                  initialMinorAngle,
                  period: 2.0 * Double.pi
              ) < Double.pi * 0.25 else {
            throw KernelError(
                phase: .geometry,
                code: .intersectionFailure,
                residual: periodicDistance(
                    minorAngle,
                    initialMinorAngle,
                    period: 2.0 * Double.pi
                ),
                tolerance: tolerance,
                message: "General torus-torus branch refinement left its certified continuation neighborhood."
            )
        }
        return liftedPeriodicValue(
            minorAngle,
            near: initialMinorAngle,
            period: 2.0 * Double.pi
        )
    }

    func implicitValueAndMinorDerivative(
        majorAngle: Double,
        minorAngle: Double,
        configuration: Configuration
    ) -> (value: Double, minorDerivative: Double) {
        let radial = configuration.radial(at: majorAngle)
        let minorCosine = cos(minorAngle)
        let minorSine = sin(minorAngle)
        let minorRadius = configuration.parameterized.minorRadius
        let radialScale = configuration.parameterized.majorRadius
            + minorRadius * minorCosine
        let point = configuration.parameterized.center
            + radial * radialScale
            + configuration.parameterized.axis
                * (minorRadius * minorSine)
        let offset = point - configuration.reference.center
        let squaredLength = offset.dot(offset)
        let axialDistance = offset.dot(configuration.reference.axis)
        let q = squaredLength
            + configuration.reference.majorRadius
                * configuration.reference.majorRadius
            - configuration.reference.minorRadius
                * configuration.reference.minorRadius
        let radialSquared = squaredLength
            - axialDistance * axialDistance
        let majorRadiusSquared = configuration.reference.majorRadius
            * configuration.reference.majorRadius
        let value = q * q - 4.0 * majorRadiusSquared * radialSquared
        let referenceRadial = offset
            - configuration.reference.axis * axialDistance
        let gradient = offset * (4.0 * q)
            - referenceRadial * (8.0 * majorRadiusSquared)
        let minorTangent = radial * (-minorRadius * minorSine)
            + configuration.parameterized.axis
                * (minorRadius * minorCosine)
        return (value, gradient.dot(minorTangent))
    }

    func makeRootTrace(
        initialRoots: [Double],
        configuration: Configuration,
        options: SurfaceSurfaceIntersectionOptions,
        tolerance: ModelingTolerance
    ) throws -> RootTrace {
        var execution = try OriginalQueryExecution.independentGeometry()
        return try makeRootTrace(initialRoots: initialRoots, configuration: configuration, options: options, tolerance: tolerance, using: &execution)
    }


    func makeRootTrace(
        initialRoots: [Double],
        configuration: Configuration,
        options: SurfaceSurfaceIntersectionOptions,
        tolerance: ModelingTolerance
    , using execution: inout OriginalQueryExecution) throws -> RootTrace {
        try execution.checkpoint()
        let result = try makeRootTraceImplementation(initialRoots: initialRoots, configuration: configuration, options: options, tolerance: tolerance, using: &execution)
        try execution.checkpoint()
        return result
    }



    private func makeRootTraceImplementation(
        initialRoots: [Double],
        configuration: Configuration,
        options: SurfaceSurfaceIntersectionOptions,
        tolerance: ModelingTolerance
    , using execution: inout OriginalQueryExecution) throws -> RootTrace {
        try execution.checkpoint()
        try execution.consumeWork(1)
        let period = 2.0 * Double.pi
        try execution.retainStorage(bytes: exactScalarPayloadBytes(count: 1, of: Double.self))
        var parameters = [0.0]
        var parametersCapacity = parameters.count
        var valuesByBranch = (try CertifiedAnalyticCurveEvaluation.map(initialRoots, using: &execution) { element, execution in try CertifiedAnalyticCurveEvaluation.values(element, using: &execution)  })
        var valuesByBranchCapacities = try CertifiedAnalyticCurveEvaluation.repeated(1, count: valuesByBranch.count, using: &execution)
        var finalCandidateIndices = try CertifiedAnalyticCurveEvaluation.map(initialRoots.indices, using: &execution) { index, _ in index }
        var acceptedSegmentCount = 0




        func appendInterval(
            lowerParameter: Double,
            lowerValues: [Double],
            upperParameter: Double,
            depth: Int
        , using execution: inout OriginalQueryExecution) throws -> [Double] {
            try execution.visitGeometricCell(depth: depth)
            try execution.checkpoint()
            try execution.consumeWork(1)
            let roots = try verifiedRoots(
                majorAngle: upperParameter,
                configuration: configuration,
                options: options,
                tolerance: tolerance
            , using: &execution)
            guard roots.count == initialRoots.count else {
                throw KernelError(
                    phase: .geometry,
                    code: .intersectionFailure,
                    residual: Double(abs(roots.count - initialRoots.count)),
                    tolerance: tolerance,
                    message: "Certified torus-torus meridian root count changed during tracing."
                )
            }
            let assignment = (try bestAssignment(
                previous: lowerValues,
                candidates: roots,
                period: period
            , using: &execution))
            let ambiguityTolerance = max(
                tolerance.angle * tolerance.angle * 64.0,
                Double.ulpOfOne * 1_024.0
            )
            let assignmentIsStable = assignment.maximumMovement < Double.pi * 0.5
                && (assignment.secondCost - assignment.cost > ambiguityTolerance
                    || assignment.secondCost.isInfinite)
            if assignmentIsStable {
                acceptedSegmentCount += 1
                guard acceptedSegmentCount <= options.maximumSeedCount else {
                    throw KernelError(
                        phase: .geometry,
                        code: .resourceLimitExceeded,
                        residual: Double(acceptedSegmentCount),
                        tolerance: tolerance,
                        message: "Torus-torus periodic root tracing exceeded its segment limit."
                    )
                }
                try CertifiedAnalyticCurveEvaluation.append(upperParameter, to: &parameters, using: &execution, capacity: &parametersCapacity)
                for branch in valuesByBranch.indices {
                    try execution.consumeWork(1)
                    try CertifiedAnalyticCurveEvaluation.append(assignment.values[branch], to: &valuesByBranch[branch], using: &execution, capacity: &valuesByBranchCapacities[branch])
                }
                if abs(upperParameter - period) <= tolerance.angle {
                    finalCandidateIndices = assignment.candidateIndices
                }
                return assignment.values
            }
            guard depth < min(options.maximumSubdivisionDepth + 8, 24) else {
                throw KernelError(
                    phase: .geometry,
                    code: .singularSystem,
                    residual: assignment.maximumMovement,
                    tolerance: tolerance,
                    message: "Torus-torus periodic root assignment remained ambiguous after adaptive continuation."
                )
            }
            let middle = lowerParameter + (upperParameter - lowerParameter) * 0.5
            let middleValues = try appendInterval(
                lowerParameter: lowerParameter,
                lowerValues: lowerValues,
                upperParameter: middle,
                depth: depth + 1
            , using: &execution)
            return try appendInterval(
                lowerParameter: middle,
                lowerValues: middleValues,
                upperParameter: upperParameter,
                depth: depth + 1
            , using: &execution)
        }

        let initialSegmentCount = 32
        var lowerParameter = 0.0
        var lowerValues = initialRoots
        for index in 1...initialSegmentCount {
            try execution.consumeWork(1)
            let upperParameter = period * Double(index)
                / Double(initialSegmentCount)
            lowerValues = try appendInterval(
                lowerParameter: lowerParameter,
                lowerValues: lowerValues,
                upperParameter: upperParameter,
                depth: 0
            , using: &execution)
            lowerParameter = upperParameter
        }
        try execution.retainStorage(bytes: exactScalarPayloadBytes(count: finalCandidateIndices.count, of: Int.self))
        try execution.consumeWork(finalCandidateIndices.count)
        guard Set(finalCandidateIndices).count == initialRoots.count else {
            throw KernelError(
                phase: .geometry,
                code: .singularSystem,
                tolerance: tolerance,
                message: "Torus-torus periodic continuation did not produce a root permutation."
            )
        }
        return RootTrace(
            parameters: parameters,
            valuesByBranch: valuesByBranch,
            permutation: finalCandidateIndices
        )
    }

    func verifiedRoots(
        majorAngle: Double,
        configuration: Configuration,
        options: SurfaceSurfaceIntersectionOptions,
        tolerance: ModelingTolerance
    ) throws -> [Double] {
        var execution = try OriginalQueryExecution.independentGeometry()
        return try verifiedRoots(majorAngle: majorAngle, configuration: configuration, options: options, tolerance: tolerance, using: &execution)
    }


    func verifiedRoots(
        majorAngle: Double,
        configuration: Configuration,
        options: SurfaceSurfaceIntersectionOptions,
        tolerance: ModelingTolerance
    , using execution: inout OriginalQueryExecution) throws -> [Double] {
        try execution.checkpoint()
        let result = try verifiedRootsImplementation(majorAngle: majorAngle, configuration: configuration, options: options, tolerance: tolerance, using: &execution)
        try execution.checkpoint()
        return result
    }



    private func verifiedRootsImplementation(
        majorAngle: Double,
        configuration: Configuration,
        options: SurfaceSurfaceIntersectionOptions,
        tolerance: ModelingTolerance
    , using execution: inout OriginalQueryExecution) throws -> [Double] {
        try execution.checkpoint()
        try execution.consumeWork(1)
        let intersector = DefaultCurveSurfaceIntersector()
        let intersections = try intersector.intersections(
            curve: configuration.meridianCurve(at: majorAngle),
            surface: configuration.reference.surface,
            options: CurveSurfaceIntersectionOptions(
                maximumSubdivisionDepth: options.maximumSubdivisionDepth,
                maximumIterations: options.maximumIterations,
                maximumCandidateCount: options.maximumSeedCount
            ),
            tolerance: tolerance
        , using: &execution)
        var roots: [Double] = []
        var rootsCapacity = roots.count
        for intersection in intersections {
            try execution.consumeWork(1)
            guard intersection.kind == .transverse else {
                throw KernelError(
                    phase: .geometry,
                    code: .singularSystem,
                    residual: intersection.residual,
                    tolerance: tolerance,
                    message: "General torus-torus tracing encountered a rank-deficient meridian-tangent root."
                )
            }
            let root = normalizedAngle(intersection.curveParameter)
            let point = configuration.point(
                majorAngle: majorAngle,
                minorAngle: root
            )
            let residual = max(
                intersection.residual,
                (point - intersection.point).length
            )
            guard residual <= tolerance.distance else {
                throw KernelError(
                    phase: .geometry,
                    code: .intersectionFailure,
                    residual: residual,
                    tolerance: tolerance,
                    message: "Torus-torus meridian quartic root failed geometric residual verification."
                )
            }
            if roots.allSatisfy({
                periodicDistance($0, root, period: 2.0 * Double.pi)
                    > tolerance.angle
            }) {
                try CertifiedAnalyticCurveEvaluation.append(root, to: &roots, using: &execution, capacity: &rootsCapacity)
            }
        }
        return try CertifiedAnalyticCurveEvaluation.sorted(roots, using: &execution)
    }

    private func bestAssignment<A: ExactScalarAdmission & ~Copyable>(
        previous: [Double],
        candidates: [Double],
        period: Double
    , using execution: inout A) throws -> RootAssignment {
        try execution.checkpoint()
        try execution.consumeWork(1)
        var bestValues: [Double] = []
        var bestIndices: [Int] = []
        var bestCost = Double.infinity
        var secondCost = Double.infinity
        var bestMaximumMovement = Double.infinity

        func search(
            branch: Int,
            used: Set<Int>,
            values: [Double],
            indices: [Int],
            cost: Double,
            maximumMovement: Double
        , using execution: inout A) throws {
        try execution.checkpoint()
        try execution.consumeWork(1)
            if branch == previous.count {
                if cost < bestCost {
                    secondCost = bestCost
                    bestCost = cost
                    bestValues = values
                    bestIndices = indices
                    bestMaximumMovement = maximumMovement
                } else if cost < secondCost {
                    secondCost = cost
                }
                return
            }
            for candidateIndex in candidates.indices where used.contains(candidateIndex) == false {
                try execution.consumeWork(1)
                let candidate = liftedPeriodicValue(
                    candidates[candidateIndex],
                    near: previous[branch],
                    period: period
                )
                let movement = abs(candidate - previous[branch])
                let nextCost = cost + movement * movement
                guard nextCost < secondCost else { continue }
                let nextCount = try exactScalarCount(used.count, 1)
                try execution.retainStorage(bytes: exactScalarPayloadBytes(count: nextCount, of: Int.self))
                try execution.retainStorage(bytes: exactScalarPayloadBytes(count: try exactScalarCount(values.count, 2), of: Double.self))
                try execution.retainStorage(bytes: exactScalarPayloadBytes(count: try exactScalarCount(indices.count, 2), of: Int.self))
                var nextUsed = used
                nextUsed.insert(candidateIndex)
                (try search(
                    branch: branch + 1,
                    used: nextUsed,
                    values: values + [candidate],
                    indices: indices + [candidateIndex],
                    cost: nextCost,
                    maximumMovement: max(maximumMovement, movement)
                , using: &execution))
            }
        }

        (try search(
            branch: 0,
            used: [],
            values: [],
            indices: [],
            cost: 0.0,
            maximumMovement: 0.0
        , using: &execution))
        return RootAssignment(
            values: bestValues,
            candidateIndices: bestIndices,
            cost: bestCost,
            secondCost: secondCost,
            maximumMovement: bestMaximumMovement
        )
    }

    func selectedRoot(
        candidates: [Double],
        reference: Double,
        period: Double,
        tolerance: ModelingTolerance
    ) throws -> Double {
        var execution = try OriginalQueryExecution.independentGeometry()
        return try selectedRoot(candidates: candidates, reference: reference, period: period, tolerance: tolerance, using: &execution)
    }


    func selectedRoot(
        candidates: [Double],
        reference: Double,
        period: Double,
        tolerance: ModelingTolerance
    , using execution: inout OriginalQueryExecution) throws -> Double {
        try execution.checkpoint()
        let result = try selectedRootImplementation(candidates: candidates, reference: reference, period: period, tolerance: tolerance, using: &execution)
        try execution.checkpoint()
        return result
    }



    private func selectedRootImplementation(
        candidates: [Double],
        reference: Double,
        period: Double,
        tolerance: ModelingTolerance
    , using execution: inout OriginalQueryExecution) throws -> Double {
        try execution.checkpoint()
        try execution.consumeWork(1)
        let ranked = (try CertifiedAnalyticCurveEvaluation.sorted((try CertifiedAnalyticCurveEvaluation.map(candidates, using: &execution) { element, execution in 
            liftedPeriodicValue(element, near: reference, period: period)
         }), using: &execution, by: { abs($0 - reference) < abs($1 - reference) }))
        guard let selected = ranked.first else {
            throw KernelError(
                phase: .geometry,
                code: .intersectionFailure,
                tolerance: tolerance,
                message: "Torus-torus branch evaluation produced no meridian root."
            )
        }
        if ranked.count > 1 {
            let firstDistance = abs(ranked[0] - reference)
            let secondDistance = abs(ranked[1] - reference)
            guard secondDistance - firstDistance > tolerance.angle * 8.0 else {
                throw KernelError(
                    phase: .geometry,
                    code: .singularSystem,
                    residual: secondDistance - firstDistance,
                    tolerance: tolerance,
                    message: "Torus-torus branch evaluation found an ambiguous periodic root assignment."
                )
            }
        }
        return selected
    }

    func permutationCycles(
        _ permutation: [Int],
        tolerance: ModelingTolerance
    ) throws -> [[Int]] {
        var execution = try OriginalQueryExecution.independentGeometry()
        return try permutationCycles(permutation, tolerance: tolerance, using: &execution)
    }


    func permutationCycles(
        _ permutation: [Int],
        tolerance: ModelingTolerance
    , using execution: inout OriginalQueryExecution) throws -> [[Int]] {
        try execution.checkpoint()
        let result = try permutationCyclesImplementation(permutation, tolerance: tolerance, using: &execution)
        try execution.checkpoint()
        return result
    }



    private func permutationCyclesImplementation(
        _ permutation: [Int],
        tolerance: ModelingTolerance
    , using execution: inout OriginalQueryExecution) throws -> [[Int]] {
        try execution.checkpoint()
        try execution.consumeWork(1)
        try execution.retainStorage(bytes: exactScalarPayloadBytes(count: permutation.count, of: Int.self))
        var visited = Set<Int>()
        visited.reserveCapacity(permutation.count)
        var cycles: [[Int]] = []
        var cyclesCapacity = cycles.count
        for start in permutation.indices where visited.contains(start) == false {
            try execution.consumeWork(1)
            var cycle: [Int] = []
            var cycleCapacity = cycle.count
            var current = start
            while visited.contains(current) == false {
                try execution.consumeWork(1)
                guard permutation.indices.contains(current) else {
                    throw KernelError(
                        phase: .geometry,
                        code: .singularSystem,
                        tolerance: tolerance,
                        message: "Torus-torus root permutation contains an invalid branch index."
                    )
                }
                visited.insert(current)
                try CertifiedAnalyticCurveEvaluation.append(current, to: &cycle, using: &execution, capacity: &cycleCapacity)
                current = permutation[current]
            }
            guard current == start else {
                throw KernelError(
                    phase: .geometry,
                    code: .singularSystem,
                    tolerance: tolerance,
                    message: "Torus-torus root permutation does not decompose into closed cycles."
                )
            }
            try CertifiedAnalyticCurveEvaluation.append(cycle, to: &cycles, using: &execution, capacity: &cyclesCapacity)
        }
        return cycles
    }

    private func radialInterval(
        zero: Double,
        quarter: Double,
        cosine: Interval,
        sine: Interval
    ) -> Interval {
        cosine.scaled(by: zero).adding(sine.scaled(by: quarter))
    }

    private func dotInterval(
        _ first: [Interval],
        _ second: [Interval]
    ) -> Interval {
        first.indices.reduce(Interval.constant(0.0)) { result, index in
            result.adding(first[index].multiplied(by: second[index]))
        }
    }

    private func dotInterval(
        _ values: [Interval],
        _ direction: Vector3D
    ) -> Interval {
        values[0].scaled(by: direction.x)
            .adding(values[1].scaled(by: direction.y))
            .adding(values[2].scaled(by: direction.z))
    }

    private func torusHessianBilinearInterval(
        offset: [Interval],
        q: Interval,
        first: [Interval],
        second: [Interval],
        torus: Torus
    ) -> Interval {
        let firstSecond = dotInterval(first, second)
        let firstAxis = dotInterval(first, torus.axis)
        let secondAxis = dotInterval(second, torus.axis)
        return dotInterval(offset, first)
            .multiplied(by: dotInterval(offset, second))
            .scaled(by: 8.0)
            .adding(q.multiplied(by: firstSecond).scaled(by: 4.0))
            .subtracting(
                firstSecond.subtracting(
                    firstAxis.multiplied(by: secondAxis)
                ).scaled(by: 8.0 * torus.majorRadius * torus.majorRadius)
            )
    }

    private func torusThirdDifferentialInterval(
        offset: [Interval],
        first: [Interval],
        second: [Interval],
        third: [Interval]
    ) -> Interval {
        dotInterval(first, second)
            .multiplied(by: dotInterval(offset, third))
            .adding(
                dotInterval(first, third)
                    .multiplied(by: dotInterval(offset, second))
            )
            .adding(
                dotInterval(second, third)
                    .multiplied(by: dotInterval(offset, first))
            )
            .scaled(by: 8.0)
    }

    private func axisComponent(_ axis: Vector3D, at index: Int) -> Double {
        switch index {
        case 0: axis.x
        case 1: axis.y
        default: axis.z
        }
    }

    private func cosineInterval<A: ExactScalarAdmission & ~Copyable>(_ angle: Interval, using execution: inout A) throws -> Interval {
        try execution.checkpoint()
        try execution.consumeWork(1)
        return (try trigonometricInterval(angle, phase: 0.0, using: &execution))
    }

    private func sineInterval<A: ExactScalarAdmission & ~Copyable>(_ angle: Interval, using execution: inout A) throws -> Interval {
        try execution.checkpoint()
        try execution.consumeWork(1)
        return (try trigonometricInterval(angle, phase: Double.pi * 0.5, using: &execution))
    }

    private func trigonometricInterval<A: ExactScalarAdmission & ~Copyable>(
        _ angle: Interval,
        phase: Double
    , using execution: inout A) throws -> Interval {
        try execution.checkpoint()
        try execution.consumeWork(1)
        guard angle.width < 2.0 * Double.pi else {
            return Interval(-1.0, 1.0)
        }
        let first = cos(angle.lower - phase)
        let second = cos(angle.upper - phase)
        var lower = min(first, second)
        var upper = max(first, second)
        if containsPeriodicValue(
            angle,
            value: phase,
            period: 2.0 * Double.pi
        ) {
            upper = 1.0
        }
        if containsPeriodicValue(
            angle,
            value: phase + Double.pi,
            period: 2.0 * Double.pi
        ) {
            lower = -1.0
        }
        return Interval(lower, upper)
    }

    private func containsPeriodicValue(
        _ interval: Interval,
        value: Double,
        period: Double
    ) -> Bool {
        let firstIndex = ceil((interval.lower - value) / period)
        let candidate = value + firstIndex * period
        return candidate <= interval.upper
    }

    private func liftedPeriodicValue(
        _ value: Double,
        near reference: Double,
        period: Double
    ) -> Double {
        value + round((reference - value) / period) * period
    }

    private func periodicDistance(
        _ first: Double,
        _ second: Double,
        period: Double
    ) -> Double {
        abs(liftedPeriodicValue(first, near: second, period: period) - second)
    }

    private func normalizedAngle(_ angle: Double) -> Double {
        let period = 2.0 * Double.pi
        let remainder = angle.truncatingRemainder(dividingBy: period)
        return remainder >= 0.0 ? remainder : remainder + period
    }

    func canonicalTorus(
        _ torus: CanonicalAnalyticSurface.Torus,
        tolerance: ModelingTolerance
    ) throws -> Torus {
        var execution = try OriginalQueryExecution.independentGeometry()
        return try canonicalTorus(torus, tolerance: tolerance, using: &execution)
    }


    func canonicalTorus(
        _ torus: CanonicalAnalyticSurface.Torus,
        tolerance: ModelingTolerance
    , using execution: inout OriginalQueryExecution) throws -> Torus {
        try execution.checkpoint()
        let result = try canonicalTorusImplementation(torus, tolerance: tolerance, using: &execution)
        try execution.checkpoint()
        return result
    }



    private func canonicalTorusImplementation(
        _ torus: CanonicalAnalyticSurface.Torus,
        tolerance: ModelingTolerance
    , using execution: inout OriginalQueryExecution) throws -> Torus {
        try execution.checkpoint()
        try execution.consumeWork(1)
        var axis = try torus.axis.normalized(tolerance: tolerance.distance)
        if isNegative(axis) {
            axis = -axis
        }
        return Torus(
            center: torus.center,
            axis: axis,
            majorRadius: torus.majorRadius,
            minorRadius: torus.minorRadius
        )
    }

    func torusKey<A: ExactScalarAdmission & ~Copyable>(_ torus: Torus, using execution: inout A) throws -> [Double] {
        try execution.retainStorage(bytes: exactScalarPayloadBytes(count: 8, of: Double.self))
        try execution.checkpoint()
        try execution.consumeWork(1)
        return [
            torus.center.x,
            torus.center.y,
            torus.center.z,
            torus.axis.x,
            torus.axis.y,
            torus.axis.z,
            torus.majorRadius,
            torus.minorRadius,
        ]
    }

    private func isNegative(_ direction: Vector3D) -> Bool {
        direction.x < 0.0
            || (direction.x == 0.0 && direction.y < 0.0)
            || (direction.x == 0.0 && direction.y == 0.0 && direction.z < 0.0)
    }
}
