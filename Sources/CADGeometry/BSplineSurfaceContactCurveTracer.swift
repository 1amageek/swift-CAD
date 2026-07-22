import Foundation
import CADCore

struct BSplineSurfaceContactCurveTracer {
    struct Sample: Sendable {
        let normalizedParameters: [Double]
        let actualParameters: [Double]
        let firstPoint: Point3D
        let secondPoint: Point3D
        let point: Point3D
        let residual: Double
    }

    func component(
        from initialContact: BSplineSurfaceTangencyRefiner.Contact,
        first: BSplineSurface3D,
        second: BSplineSurface3D,
        domainLowerBounds: [Double],
        domainSpans: [Double],
        options: SurfaceSurfaceIntersectionOptions,
        tolerance: ModelingTolerance,
        remainingPointCount: inout Int
    ) throws -> [Sample] {
        guard initialContact.classification == .contactCurve,
              let tangent = initialContact.contactTangent else {
            throw KernelError(
                phase: .geometry,
                code: .invalidInput,
                tolerance: tolerance,
                message: "Contact curve tracing requires a rank-one tangency and its tangent."
            )
        }
        let initial = sample(initialContact)
        let forward = try march(
            from: initialContact,
            initialTangent: tangent,
            first: first,
            second: second,
            domainLowerBounds: domainLowerBounds,
            domainSpans: domainSpans,
            options: options,
            tolerance: tolerance,
            remainingPointCount: &remainingPointCount
        )
        if isClosed(forward, tolerance: tolerance) {
            return try refined(
                forward,
                first: first,
                second: second,
                domainLowerBounds: domainLowerBounds,
                domainSpans: domainSpans,
                options: options,
                tolerance: tolerance,
                remainingPointCount: &remainingPointCount
            )
        }
        let reverse = try march(
            from: initialContact,
            initialTangent: tangent.map { -$0 },
            first: first,
            second: second,
            domainLowerBounds: domainLowerBounds,
            domainSpans: domainSpans,
            options: options,
            tolerance: tolerance,
            remainingPointCount: &remainingPointCount
        )
        if isClosed(reverse, tolerance: tolerance) {
            return try refined(
                Array(reverse.reversed()),
                first: first,
                second: second,
                domainLowerBounds: domainLowerBounds,
                domainSpans: domainSpans,
                options: options,
                tolerance: tolerance,
                remainingPointCount: &remainingPointCount
            )
        }
        let combined = Array(reverse.dropFirst().reversed()) + forward
        guard combined.count >= 2,
              (combined.first?.point ?? initial.point) != (combined.last?.point ?? initial.point) else {
            throw KernelError(
                phase: .geometry,
                code: .singularGeometry,
                tolerance: tolerance,
                message: "Rank-one contact continuation did not produce a finite curve component."
            )
        }
        return try refined(
            combined,
            first: first,
            second: second,
            domainLowerBounds: domainLowerBounds,
            domainSpans: domainSpans,
            options: options,
            tolerance: tolerance,
            remainingPointCount: &remainingPointCount
        )
    }

    private func march(
        from initialContact: BSplineSurfaceTangencyRefiner.Contact,
        initialTangent: [Double],
        first: BSplineSurface3D,
        second: BSplineSurface3D,
        domainLowerBounds: [Double],
        domainSpans: [Double],
        options: SurfaceSurfaceIntersectionOptions,
        tolerance: ModelingTolerance,
        remainingPointCount: inout Int
    ) throws -> [Sample] {
        var current = sample(initialContact)
        var tangent = initialTangent
        var result = [current]
        let baseStep = max(
            1.0 / pow(2.0, Double(options.maximumSubdivisionDepth + 2)),
            1.0 / 256.0
        )
        while true {
            guard result.count < 16_384,
                  remainingPointCount > 0 else {
                throw resourceLimit(
                    tolerance: tolerance,
                    message: "B-spline contact continuation exceeded its point limit."
                )
            }
            var step = baseStep
            var nextContact: BSplineSurfaceTangencyRefiner.Contact?
            var reachesBoundary = false
            for _ in 0..<8 {
                let boundaryStep = scaleToUnitBoundary(
                    from: current.normalizedParameters,
                    direction: tangent,
                    requestedStep: step
                )
                guard boundaryStep > 1.0e-13 else { break }
                reachesBoundary = boundaryStep < step
                let predictor = zip(current.normalizedParameters, tangent).map {
                    $0.0 + $0.1 * boundaryStep
                }
                nextContact = try BSplineSurfaceTangencyRefiner().refinedContact(
                    near: predictor,
                    first: first,
                    second: second,
                    domainLowerBounds: domainLowerBounds,
                    domainSpans: domainSpans,
                    maximumIterations: options.maximumIterations,
                    tolerance: tolerance,
                    gaugeOrigin: predictor,
                    gaugeTangent: tangent
                )
                if nextContact != nil { break }
                step *= 0.5
            }
            guard let candidate = nextContact else {
                if isOnUnitBoundary(current.normalizedParameters) { break }
                throw KernelError(
                    phase: .geometry,
                    code: .intersectionFailure,
                    tolerance: tolerance,
                    message: "B-spline contact continuation correction failed before reaching a boundary."
                )
            }
            let next = try contactCurveSample(candidate, tolerance: tolerance)
            if (next.point - current.point).length <= tolerance.distance * 0.1 {
                if reachesBoundary || isOnUnitBoundary(next.normalizedParameters) { break }
                throw KernelError(
                    phase: .geometry,
                    code: .intersectionFailure,
                    residual: (next.point - current.point).length,
                    tolerance: tolerance,
                    message: "B-spline contact continuation stagnated before reaching a boundary."
                )
            }
            remainingPointCount -= 1
            result.append(next)
            if result.count > 12,
               (next.point - result[0].point).length <= tolerance.distance * 2.0 {
                result[result.count - 1] = result[0]
                break
            }
            if reachesBoundary || isOnUnitBoundary(next.normalizedParameters) { break }
            guard var nextTangent = candidate.contactTangent else {
                throw KernelError(
                    phase: .geometry,
                    code: .singularGeometry,
                    tolerance: tolerance,
                    message: "B-spline contact continuation lost its rank-one tangent."
                )
            }
            if dot(nextTangent, tangent) < 0.0 {
                nextTangent = nextTangent.map { -$0 }
            }
            tangent = nextTangent
            current = next
        }
        return result
    }

    private func refined(
        _ samples: [Sample],
        first: BSplineSurface3D,
        second: BSplineSurface3D,
        domainLowerBounds: [Double],
        domainSpans: [Double],
        options: SurfaceSurfaceIntersectionOptions,
        tolerance: ModelingTolerance,
        remainingPointCount: inout Int
    ) throws -> [Sample] {
        guard samples.count >= 2 else { return samples }
        var result = [samples[0]]
        for index in 1..<samples.count {
            try refineSegment(
                lower: samples[index - 1],
                upper: samples[index],
                depth: 0,
                first: first,
                second: second,
                domainLowerBounds: domainLowerBounds,
                domainSpans: domainSpans,
                options: options,
                tolerance: tolerance,
                remainingPointCount: &remainingPointCount,
                result: &result
            )
        }
        return result
    }

    private func refineSegment(
        lower: Sample,
        upper: Sample,
        depth: Int,
        first: BSplineSurface3D,
        second: BSplineSurface3D,
        domainLowerBounds: [Double],
        domainSpans: [Double],
        options: SurfaceSurfaceIntersectionOptions,
        tolerance: ModelingTolerance,
        remainingPointCount: inout Int,
        result: inout [Sample]
    ) throws {
        let predictor = zip(lower.normalizedParameters, upper.normalizedParameters).map {
            ($0.0 + $0.1) * 0.5
        }
        let direction = zip(upper.normalizedParameters, lower.normalizedParameters).map {
            $0.0 - $0.1
        }
        guard let tangent = normalized(direction),
              let contact = try BSplineSurfaceTangencyRefiner().refinedContact(
                near: predictor,
                first: first,
                second: second,
                domainLowerBounds: domainLowerBounds,
                domainSpans: domainSpans,
                maximumIterations: options.maximumIterations,
                tolerance: tolerance,
                gaugeOrigin: predictor,
                gaugeTangent: tangent
              ) else {
            throw KernelError(
                phase: .geometry,
                code: .intersectionFailure,
                tolerance: tolerance,
                message: "B-spline contact midpoint correction failed."
            )
        }
        let middle = try contactCurveSample(contact, tolerance: tolerance)
        let linearMidpoint = interpolated(lower.point, upper.point, fraction: 0.5)
        let parameterMidpoint = zip(lower.actualParameters, upper.actualParameters).map {
            ($0.0 + $0.1) * 0.5
        }
        let firstParameterPoint = try first.point(
            u: parameterMidpoint[0],
            v: parameterMidpoint[1],
            tolerance: tolerance
        )
        let secondParameterPoint = try second.point(
            u: parameterMidpoint[2],
            v: parameterMidpoint[3],
            tolerance: tolerance
        )
        let residual = max(
            (linearMidpoint - middle.point).length,
            (linearMidpoint - firstParameterPoint).length,
            (linearMidpoint - secondParameterPoint).length
        )
        if residual <= tolerance.distance * 0.5 {
            result.append(upper)
            return
        }
        guard depth < options.maximumSubdivisionDepth + 10,
              remainingPointCount > 0 else {
            throw resourceLimit(
                tolerance: tolerance,
                message: "B-spline contact residual refinement exceeded its limit."
            )
        }
        remainingPointCount -= 1
        try refineSegment(
            lower: lower,
            upper: middle,
            depth: depth + 1,
            first: first,
            second: second,
            domainLowerBounds: domainLowerBounds,
            domainSpans: domainSpans,
            options: options,
            tolerance: tolerance,
            remainingPointCount: &remainingPointCount,
            result: &result
        )
        try refineSegment(
            lower: middle,
            upper: upper,
            depth: depth + 1,
            first: first,
            second: second,
            domainLowerBounds: domainLowerBounds,
            domainSpans: domainSpans,
            options: options,
            tolerance: tolerance,
            remainingPointCount: &remainingPointCount,
            result: &result
        )
    }

    private func contactCurveSample(
        _ contact: BSplineSurfaceTangencyRefiner.Contact,
        tolerance: ModelingTolerance
    ) throws -> Sample {
        guard contact.classification == .contactCurve,
              contact.contactTangent != nil else {
            let code: KernelErrorCode = contact.classification == .branching
                ? .nonDiscreteIntersection
                : .singularGeometry
            throw KernelError(
                phase: .geometry,
                code: code,
                residual: contact.normalResidual,
                tolerance: tolerance,
                message: "B-spline contact continuation reached a non-regular tangency."
            )
        }
        return sample(contact)
    }

    private func sample(_ contact: BSplineSurfaceTangencyRefiner.Contact) -> Sample {
        Sample(
            normalizedParameters: contact.normalizedParameters,
            actualParameters: contact.actualParameters,
            firstPoint: contact.firstPoint,
            secondPoint: contact.secondPoint,
            point: interpolated(contact.firstPoint, contact.secondPoint, fraction: 0.5),
            residual: (contact.firstPoint - contact.secondPoint).length
        )
    }

    private func isClosed(_ samples: [Sample], tolerance: ModelingTolerance) -> Bool {
        guard samples.count > 12,
              let first = samples.first,
              let last = samples.last else { return false }
        return (first.point - last.point).length <= tolerance.distance * 2.0
    }

    private func scaleToUnitBoundary(
        from parameters: [Double],
        direction: [Double],
        requestedStep: Double
    ) -> Double {
        var result = requestedStep
        for index in parameters.indices {
            if direction[index] > 0.0 {
                result = min(result, (1.0 - parameters[index]) / direction[index])
            } else if direction[index] < 0.0 {
                result = min(result, -parameters[index] / direction[index])
            }
        }
        return max(result, 0.0)
    }

    private func isOnUnitBoundary(_ values: [Double]) -> Bool {
        values.contains { $0 <= 1.0e-10 || $0 >= 1.0 - 1.0e-10 }
    }

    private func dot(_ first: [Double], _ second: [Double]) -> Double {
        zip(first, second).reduce(0.0) { $0 + $1.0 * $1.1 }
    }

    private func normalized(_ values: [Double]) -> [Double]? {
        let length = sqrt(dot(values, values))
        guard length.isFinite, length > 1.0e-12 else { return nil }
        return values.map { $0 / length }
    }

    private func interpolated(_ first: Point3D, _ second: Point3D, fraction: Double) -> Point3D {
        Point3D(
            x: first.x + (second.x - first.x) * fraction,
            y: first.y + (second.y - first.y) * fraction,
            z: first.z + (second.z - first.z) * fraction
        )
    }

    private func resourceLimit(tolerance: ModelingTolerance, message: String) -> KernelError {
        KernelError(
            phase: .geometry,
            code: .resourceLimitExceeded,
            tolerance: tolerance,
            message: message
        )
    }
}
