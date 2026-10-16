import CADCore
import CADGeometry
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#elseif canImport(WASILibc)
import WASILibc
#else
#error("A C math implementation is required.")
#endif

struct SphericalGreatCirclePcurveAreaIntegrator {
    private struct WorkItem {
        let lower: Double
        let upper: Double
        let requestedWidth: Double
        let depth: Int
    }

    private struct Interval {
        let lower: Double
        let upper: Double

        var maximumAbsoluteValue: Double {
            max(abs(lower), abs(upper))
        }

        var width: Double {
            (upper - lower).nextUp
        }

        func adding(_ other: Interval) -> Interval {
            Interval(
                lower: (lower + other.lower).nextDown,
                upper: (upper + other.upper).nextUp
            )
        }

        func subtracting(_ other: Interval) -> Interval {
            Interval(
                lower: (lower - other.upper).nextDown,
                upper: (upper - other.lower).nextUp
            )
        }

        func multiplied(by other: Interval) -> Interval {
            let a = lower * other.lower, b = lower * other.upper
            let c = upper * other.lower, d = upper * other.upper
            return Interval(lower: min(min(a, b), min(c, d)).nextDown,
                upper: max(max(a, b), max(c, d)).nextUp)
        }

        func scaled(by value: Double) -> Interval {
            guard value != 0.0 else {
                return Interval(lower: 0.0, upper: 0.0)
            }
            let first = lower * value
            let second = upper * value
            return Interval(
                lower: (min(first, second)).nextDown,
                upper: (max(first, second)).nextUp
            )
        }

        func divided(byPositive divisor: Interval) -> Interval? {
            guard divisor.lower > 0.0 else { return nil }
            return multiplied(by: Interval(
                lower: (1.0 / divisor.upper).nextDown,
                upper: (1.0 / divisor.lower).nextUp
            ))
        }

        func squared() -> Interval {
            let lowerSquare: Double
            if lower <= 0.0, upper >= 0.0 {
                lowerSquare = 0.0
            } else {
                lowerSquare = min(lower * lower, upper * upper).nextDown
            }
            return Interval(
                lower: max(lowerSquare, 0.0),
                upper: max(lower * lower, upper * upper).nextUp
            )
        }
    }

    private let maximumSubdivisionDepth = 48
    private let maximumCellCount = 131_072

    func bounds(cosine: Vector3D, sine: Vector3D, startParameter: Double,
        endParameter: Double, uShift: Double, requestedWidth: Double,
        tolerance: ModelingTolerance) throws -> SurfaceParameterAreaBounds {
        var execution = OriginalQueryExecution(budget: try OriginalQueryBudget(),
            limits: try .init(maximumValueDepth: 32, maximumCoefficientDepth: 32,
                remainingSourceDepth: 16, maximumSubdivisionDepth: maximumSubdivisionDepth))
        return try bounds(cosine: cosine, sine: sine, startParameter: startParameter,
            endParameter: endParameter, uShift: uShift, requestedWidth: requestedWidth,
            tolerance: tolerance, using: &execution)
    }

    func bounds(cosine: Vector3D, sine: Vector3D, startParameter: Double,
        endParameter: Double, uShift: Double, requestedWidth: Double,
        tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution) throws -> SurfaceParameterAreaBounds {
        try execution.consumeWork(1)
        try tolerance.validate()
        try cosine.validateUnitLength(tolerance: tolerance)
        try sine.validateUnitLength(tolerance: tolerance)
        guard abs(cosine.dot(sine)) <= tolerance.angle,
              startParameter.isFinite,
              endParameter.isFinite,
              uShift.isFinite,
              requestedWidth.isFinite,
              requestedWidth > 0.0 else {
            throw KernelError(
                phase: .topology,
                code: .invalidInput,
                tolerance: tolerance,
                message: "Great-circle area integration requires finite orthonormal input."
            )
        }
        let ascendingLower = min(startParameter, endParameter)
        let ascendingUpper = max(startParameter, endParameter)
        guard ascendingUpper - ascendingLower > tolerance.angle,
              ascendingUpper - ascendingLower <= 2.0 * Double.pi + tolerance.angle else {
            throw KernelError(
                phase: .topology,
                code: .invalidInput,
                tolerance: tolerance,
                message: "Great-circle area integration requires one nondegenerate turn or less."
            )
        }

        if let meridian = try meridianBounds(
            cosine: cosine,
            sine: sine,
            lower: ascendingLower,
            upper: ascendingUpper,
            uShift: uShift,
            using: &execution) {
            try execution.checkpoint()
            guard startParameter <= endParameter else {
                return SurfaceParameterAreaBounds(
                    lower: (-meridian.upper).nextDown,
                    upper: (-meridian.lower).nextUp
                )
            }
            return meridian
        }
        let seams = try seamParameters(
                cosine: cosine,
                sine: sine,
                lower: ascendingLower,
                upper: ascendingUpper,
                tolerance: tolerance,
                using: &execution)
        var breakpoints: [Double] = []
        let breakpointCount = seams.count.addingReportingOverflow(2)
        guard !breakpointCount.overflow else { throw ExactScalarFailure.countOverflow }
        try OriginalParameterQueryStorage.reserve(breakpointCount.partialValue, in: &breakpoints, using: &execution)
        breakpoints.append(ascendingLower)
        for seam in seams { try execution.consumeWork(1); breakpoints.append(seam) }
        breakpoints.append(ascendingUpper)
        let totalSpan = ascendingUpper - ascendingLower
        var pending: [WorkItem] = []
        for index in 1..<breakpoints.count {
            try execution.consumeWork(1)
            let lower = breakpoints[index - 1]
            let upper = breakpoints[index]
            guard upper > lower else { continue }
            try OriginalParameterQueryStorage.append(WorkItem(
                lower: lower,
                upper: upper,
                requestedWidth: requestedWidth * (upper - lower) / totalSpan,
                depth: 0
            ), to: &pending, using: &execution)
        }
        var result = SurfaceParameterAreaBounds.zero
        var processedCellCount = 0
        while let item = pending.popLast() {
            try execution.visitGeometricCell(depth: item.depth)
            processedCellCount += 1
            guard processedCellCount <= maximumCellCount else {
                throw KernelError(
                    phase: .topology,
                    code: .resourceLimitExceeded,
                    tolerance: tolerance,
                    message: "Great-circle pcurve area integration exceeded its certified cell budget."
                )
            }
            if let contribution = try contributionBounds(
                cosine: cosine,
                sine: sine,
                lower: item.lower,
                upper: item.upper,
                uShift: uShift,
                tolerance: tolerance,
                using: &execution), contribution.width <= item.requestedWidth {
                result = result.adding(contribution)
                continue
            }
            guard item.depth < maximumSubdivisionDepth else {
                throw KernelError(
                    phase: .topology,
                    code: .resourceLimitExceeded,
                    tolerance: tolerance,
                    message: "Great-circle pcurve area integration could not certify the requested interval width."
                )
            }
            let midpoint = item.lower + (item.upper - item.lower) * 0.5
            guard midpoint > item.lower, midpoint < item.upper else {
                throw KernelError(
                    phase: .topology,
                    code: .resourceLimitExceeded,
                    tolerance: tolerance,
                    message: "Great-circle pcurve subdivision reached floating-point resolution."
                )
            }
            let childWidth = item.requestedWidth * 0.5
            try OriginalParameterQueryStorage.append(WorkItem(
                lower: midpoint,
                upper: item.upper,
                requestedWidth: childWidth,
                depth: item.depth + 1
            ), to: &pending, using: &execution)
            try OriginalParameterQueryStorage.append(WorkItem(
                lower: item.lower,
                upper: midpoint,
                requestedWidth: childWidth,
                depth: item.depth + 1
            ), to: &pending, using: &execution)
        }
        try execution.checkpoint()
        guard startParameter <= endParameter else {
            return SurfaceParameterAreaBounds(
                lower: (-result.upper).nextDown,
                upper: (-result.lower).nextUp
            )
        }
        return result
    }

    private func criticalIndex(_ value: Double) throws -> Int {
        guard let index = Int(exactly: value) else {
            throw GeometryConversionError.resourceLimitExceeded("Great-circle critical index is not representable.")
        }
        return index
    }

    private func meridianBounds(
        cosine: Vector3D,
        sine: Vector3D,
        lower: Double,
        upper: Double,
        uShift: Double,
        using execution: inout OriginalQueryExecution) throws -> SurfaceParameterAreaBounds? {
        let radius = hypot(cosine.z, sine.z)
        let longitudeNumerator = cosine.x * sine.y - cosine.y * sine.x
        let machineTolerance = Double.ulpOfOne * 16_384.0
        guard abs(radius - 1.0) <= machineTolerance,
              abs(longitudeNumerator) <= machineTolerance else {
            return nil
        }
        let phase = atan2(cosine.z, sine.z)
        var breakpoints: [Double] = []
        try OriginalParameterQueryStorage.append(lower, to: &breakpoints, using: &execution)
        let firstIndex = try criticalIndex(ceil(
            (lower + phase - Double.pi * 0.5) / Double.pi
        ))
        let lastIndex = try criticalIndex(floor(
            (upper + phase - Double.pi * 0.5) / Double.pi
        ))
        if firstIndex <= lastIndex {
            for index in firstIndex ... lastIndex {
                try execution.consumeWork(1)
                let parameter = Double.pi * 0.5 - phase + Double(index) * Double.pi
                if parameter > lower, parameter < upper {
                    try OriginalParameterQueryStorage.append(parameter, to: &breakpoints, using: &execution)
                }
            }
        }
        try OriginalParameterQueryStorage.append(upper, to: &breakpoints, using: &execution)
        try OriginalParameterQueryStorage.sort(&breakpoints, using: &execution, less: <)

        var result = SurfaceParameterAreaBounds.zero
        for index in 1..<breakpoints.count {
            try execution.visitGeometricCell(depth: 0)
            let segmentLower = breakpoints[index - 1]
            let segmentUpper = breakpoints[index]
            let midpoint = segmentLower + (segmentUpper - segmentLower) * 0.5
            let radial = cosine * cos(midpoint) + sine * sin(midpoint)
            var longitude = atan2(-radial.x, radial.y)
            if longitude < 0.0 {
                longitude += 2.0 * Double.pi
            }
            let lowerLatitude = asin(min(max(
                cosine.z * cos(segmentLower) + sine.z * sin(segmentLower),
                -1.0
            ), 1.0))
            let upperLatitude = asin(min(max(
                cosine.z * cos(segmentUpper) + sine.z * sin(segmentUpper),
                -1.0
            ), 1.0))
            let value = (longitude + uShift) * (upperLatitude - lowerLatitude)
            let scale = max(
                abs(value),
                abs(longitude + uShift),
                abs(upperLatitude - lowerLatitude),
                1.0
            )
            let roundoff = scale * Double.ulpOfOne * 32_768.0
            result = result.adding(SurfaceParameterAreaBounds(
                lower: (value - roundoff).nextDown,
                upper: (value + roundoff).nextUp
            ))
        }
        return result
    }

    private func seamParameters(
        cosine: Vector3D,
        sine: Vector3D,
        lower: Double,
        upper: Double,
        tolerance: ModelingTolerance,
        using execution: inout OriginalQueryExecution) throws -> [Double] {
        let horizontalScale = hypot(cosine.x, sine.x)
        guard horizontalScale > tolerance.angle else { return [] }
        let base = atan2(-cosine.x, sine.x)
        let firstIndex = try criticalIndex(ceil((lower - base) / Double.pi))
        let lastIndex = try criticalIndex(floor((upper - base) / Double.pi))
        guard firstIndex <= lastIndex else { return [] }
        var result: [Double] = []
        for index in firstIndex ... lastIndex {
                try execution.consumeWork(1)
            let parameter = base + Double(index) * Double.pi
            guard parameter > lower + tolerance.angle,
                  parameter < upper - tolerance.angle else {
                continue
            }
            let y = cosine.y * cos(parameter) + sine.y * sin(parameter)
            if y > tolerance.angle {
                try OriginalParameterQueryStorage.append(parameter, to: &result, using: &execution)
            }
        }
        try OriginalParameterQueryStorage.sort(&result, using: &execution, less: <)
        return result
    }

    private func contributionBounds(
        cosine: Vector3D,
        sine: Vector3D,
        lower: Double,
        upper: Double,
        uShift: Double,
        tolerance: ModelingTolerance,
        using execution: inout OriginalQueryExecution) throws -> SurfaceParameterAreaBounds? {
        let horizontalSquared = try horizontalSquaredBounds(
            cosine: cosine,
            sine: sine,
            lower: lower,
            upper: upper,
            using: &execution)
        let denominatorFloor = max(
            tolerance.angle * tolerance.angle,
            Double.ulpOfOne * 4_096.0
        )
        let longitudeNumerator = cosine.x * sine.y - cosine.y * sine.x
        guard horizontalSquared.lower > denominatorFloor,
              let longitudeDerivative = Interval(
                  lower: longitudeNumerator.nextDown,
                  upper: longitudeNumerator.nextUp
              ).divided(byPositive: horizontalSquared) else {
            return nil
        }
        guard let latitudeDerivatives = try latitudeDerivativeBounds(
                  cosine: cosine,
                  sine: sine,
                  lower: lower,
                  upper: upper,
                  denominatorFloor: denominatorFloor,
                  tolerance: tolerance
              , using: &execution) else {
            return nil
        }

        let midpoint = lower + (upper - lower) * 0.5
        let midpointRadial = cosine * cos(midpoint) + sine * sin(midpoint)
        var midpointLongitude = atan2(-midpointRadial.x, midpointRadial.y)
        if midpointLongitude < 0.0 {
            midpointLongitude += 2.0 * Double.pi
        }
        let roundoff = Double.ulpOfOne
            * max(abs(midpointLongitude), abs(midpoint), 1.0) * 4_096.0
        let longitudeRadius = (
            longitudeDerivative.maximumAbsoluteValue * (upper - lower) * 0.5
                + roundoff
        ).nextUp
        let unwrappedLower = (midpointLongitude - longitudeRadius).nextDown
        let unwrappedUpper = (midpointLongitude + longitudeRadius).nextUp
        let seamRoundoff = roundoff * 16.0
        guard unwrappedLower >= -seamRoundoff,
              unwrappedUpper <= 2.0 * Double.pi + seamRoundoff else {
            return nil
        }
        let longitude = Interval(
            lower: max(unwrappedLower, 0.0).nextDown,
            upper: min(unwrappedUpper, 2.0 * Double.pi).nextUp
        )
        let shiftedLongitude = longitude.adding(Interval(
            lower: uShift.nextDown,
            upper: uShift.nextUp
        ))
        let integrandDerivative = longitudeDerivative
            .multiplied(by: latitudeDerivatives.first)
            .adding(shiftedLongitude.multiplied(by: latitudeDerivatives.second))
        let midpointLatitudeDerivative = latitudeDerivative(
            cosine: cosine,
            sine: sine,
            parameter: midpoint
        )
        guard midpointLatitudeDerivative.isFinite else {
            return nil
        }
        let span = upper - lower
        let value = (midpointLongitude + uShift)
            * midpointLatitudeDerivative * span
        let analyticError = integrandDerivative.maximumAbsoluteValue
            * span * span * 0.25
        let floatingPointError = Double.ulpOfOne
            * max(abs(value), abs(analyticError), 1.0) * 16_384.0
        let totalError = (analyticError + floatingPointError).nextUp
        return SurfaceParameterAreaBounds(
            lower: (value - totalError).nextDown,
            upper: (value + totalError).nextUp
        )
    }

    private func horizontalSquaredBounds(
        cosine: Vector3D,
        sine: Vector3D,
        lower: Double,
        upper: Double,
        using execution: inout OriginalQueryExecution) throws -> Interval {
        let cosineSquared = cosine.x * cosine.x + cosine.y * cosine.y
        let sineSquared = sine.x * sine.x + sine.y * sine.y
        let cross = cosine.x * sine.x + cosine.y * sine.y
        let constant = (cosineSquared + sineSquared) * 0.5
        let cosineCoefficient = (cosineSquared - sineSquared) * 0.5
        let sineCoefficient = cross
        let phase = atan2(sineCoefficient, cosineCoefficient)
        var parameters: [Double] = []
        try OriginalParameterQueryStorage.reserve(2, in: &parameters, using: &execution)
        parameters.append(lower); parameters.append(upper)
        let firstIndex = try criticalIndex(ceil((2.0 * lower - phase) / Double.pi))
        let lastIndex = try criticalIndex(floor((2.0 * upper - phase) / Double.pi))
        if firstIndex <= lastIndex {
            for index in firstIndex ... lastIndex {
                try execution.consumeWork(1)
                try OriginalParameterQueryStorage.append((phase + Double(index) * Double.pi) * 0.5, to: &parameters, using: &execution)
            }
        }
        let values = try OriginalParameterQueryStorage.map(parameters, using: &execution) { parameter, execution in
            constant
                + cosineCoefficient * cos(2.0 * parameter)
                + sineCoefficient * sin(2.0 * parameter)
        }
        var minimum = Double.infinity, maximum = -Double.infinity
        for value in values {
            try execution.consumeWork(1)
            minimum = min(minimum, value); maximum = max(maximum, value)
        }
        return Interval(lower: minimum.nextDown, upper: maximum.nextUp)
    }

    private func latitudeDerivativeBounds(
        cosine: Vector3D,
        sine: Vector3D,
        lower: Double,
        upper: Double,
        denominatorFloor: Double,
        tolerance: ModelingTolerance,
        using execution: inout OriginalQueryExecution) throws -> (first: Interval, second: Interval)? {
        let radius = hypot(cosine.z, sine.z)
        guard radius <= 1.0 + tolerance.angle else { return nil }
        let phase = atan2(cosine.z, sine.z)
        let sineBounds = try trigonometricBounds(
            lower: lower,
            upper: upper,
            phase: phase - Double.pi * 0.5,
            using: &execution)
        let cosineBounds = try trigonometricBounds(
            lower: lower,
            upper: upper,
            phase: phase,
            using: &execution)
        let sineSquared = sineBounds.squared()
        let denominatorSquared = Interval(
            lower: (1.0 - radius * radius * sineSquared.upper).nextDown,
            upper: (1.0 - radius * radius * sineSquared.lower).nextUp
        )
        guard denominatorSquared.lower > denominatorFloor else { return nil }
        let denominator = Interval(
            lower: sqrt(denominatorSquared.lower).nextDown,
            upper: sqrt(denominatorSquared.upper).nextUp
        )
        guard let first = cosineBounds.scaled(by: radius)
            .divided(byPositive: denominator) else {
            return nil
        }
        let denominatorCubed = denominator.multiplied(by: denominator)
            .multiplied(by: denominator)
        let secondNumerator = sineBounds.scaled(
            by: -radius * (1.0 - radius * radius)
        )
        guard let second = secondNumerator.divided(byPositive: denominatorCubed) else {
            return nil
        }
        return (first, second)
    }

    private func latitudeDerivative(
        cosine: Vector3D,
        sine: Vector3D,
        parameter: Double
    ) -> Double {
        let radius = hypot(cosine.z, sine.z)
        let phase = atan2(cosine.z, sine.z)
        let sineValue = sin(parameter + phase)
        let denominatorSquared = 1.0 - radius * radius * sineValue * sineValue
        guard denominatorSquared > 0.0 else { return .nan }
        return radius * cos(parameter + phase) / sqrt(denominatorSquared)
    }

    private func trigonometricBounds(
        lower: Double,
        upper: Double,
        phase: Double,
        using execution: inout OriginalQueryExecution) throws -> Interval {
        let shiftedLower = lower + phase
        let shiftedUpper = upper + phase
        if shiftedUpper - shiftedLower >= 2.0 * Double.pi {
            return Interval(lower: -1.0, upper: 1.0)
        }
        var values: [Double] = []
        try OriginalParameterQueryStorage.reserve(2, in: &values, using: &execution)
        values.append(cos(shiftedLower)); values.append(cos(shiftedUpper))
        let firstCriticalIndex = try criticalIndex(ceil(shiftedLower / Double.pi))
        let lastCriticalIndex = try criticalIndex(floor(shiftedUpper / Double.pi))
        if firstCriticalIndex <= lastCriticalIndex {
            for index in firstCriticalIndex ... lastCriticalIndex {
                try execution.consumeWork(1)
                try OriginalParameterQueryStorage.append(index.isMultiple(of: 2) ? 1.0 : -1.0, to: &values, using: &execution)
            }
        }
        var minimum = Double.infinity, maximum = -Double.infinity
        for value in values {
            try execution.consumeWork(1)
            minimum = min(minimum, value); maximum = max(maximum, value)
        }
        return Interval(lower: minimum.nextDown, upper: maximum.nextUp)
    }
}
