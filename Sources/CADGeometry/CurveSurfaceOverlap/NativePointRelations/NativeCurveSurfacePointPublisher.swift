import CADCore
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

/// Complete original native point publication, before any legacy dispatch.
/// Publishes certified representatives from complete original zero-dimensional CS cells.
struct NativeCurveSurfacePointPublisher {
    private func value(_ polynomial: ExactBivariatePolynomial, curve: Bool,
        cell: OriginalRationalIntersectionCells.Cell, usage: inout OriginalQueryExecution)
        throws -> OriginalSingularFieldElement {
        let embedded = try ExactIntersectionPolynomial.embedding(polynomial, variableCount: 3,
            uCoordinate: curve ? 0 : 1, vCoordinate: curve ? 1 : 2, usage: &usage)
        return try OriginalIntersectionFieldEvaluation.evaluated(embedded, context: cell.context,
            coordinates: cell.coordinates, maximumDepth: usage.effectiveLimits.maximumValueDepth, usage: &usage)
    }

    func publish(cell: OriginalRationalIntersectionCells.Cell,
        partition: OriginalRationalIntersectionCells, cellIndex: Int,
        effectiveDomains: [OriginalRationalParameterDomain], curve: OriginalRationalCurvePolynomial,
        surfaceHomogeneous: [ExactBivariatePolynomial], surfaceNormalNumerators: [ExactBivariatePolynomial],
        options: CurveSurfaceIntersectionOptions, tolerance: ModelingTolerance,
        nativeDomains: (ScalarInterval, ScalarInterval, ScalarInterval),
        retainingParameters: inout [OriginalSingularFieldValueIsolation],
        retainingLocalizations: inout [NativeCurveSurfaceScalarLocalization?],
        usage: inout OriginalQueryExecution) throws -> CurveSurfaceIntersection {
        guard surfaceHomogeneous.count == 4, surfaceNormalNumerators.count == 3 else {
            throw rationalAlgebraFailure("Original CS publication requires complete homogeneous and normal laws.")
        }
        let depth = usage.effectiveLimits.maximumValueDepth
        let weight = try value(curve.homogeneous[3], curve: true, cell: cell, usage: &usage)
        try RationalAlgebraStorage.retain(6, of: OriginalSingularFieldValueIsolation.self, usage: &usage)
        var isolations: [OriginalSingularFieldValueIsolation] = []; isolations.reserveCapacity(6)
        for axis in 0..<3 {
            var seed = try OriginalNativeCurveSurfacePoints.sectionBounds(partition: partition, cellIndex: cellIndex, axis: axis)
            if let lower = effectiveDomains[axis].lower,
                try seed.lower.subtracting(lower, usage: &usage).isNegative { seed.lower = lower }
            if let upper = effectiveDomains[axis].upper,
                try seed.upper.subtracting(upper, usage: &usage).isPositive { seed.upper = upper }
            for previous in 0..<axis {
                // Exact equality reuses an already retained scalar enclosure;
                // a linear fiber must not discard its parent's original root proof.
                if try cell.coordinates[axis].subtracting(cell.coordinates[previous],
                    maximumDepth: depth, usage: &usage).sign(maximumDepth: depth, usage: &usage) == .zero {
                    if try seed.lower.subtracting(isolations[previous].lower, usage: &usage).isNegative {
                        seed.lower = isolations[previous].lower
                    }
                    if try seed.upper.subtracting(isolations[previous].upper, usage: &usage).isPositive {
                        seed.upper = isolations[previous].upper
                    }
                }
            }
            isolations.append(try .init(original: cell.coordinates[axis], lower: seed.lower, upper: seed.upper,
                inheritedDepth: cell.admissionDepth, maximumDepth: depth, usage: &usage))
        }
        let tBounds = try isolations[0].enclosure(usage: &usage)
        let parameterBox = SurfaceParameterBox(u: try .init(lower: tBounds.lower, upper: tBounds.upper),
            v: try .init(lower: 0, upper: 0))
        // On the original closed Bezier domain, its nonnegative basis sums to
        // one. These original positive weights therefore bound the denominator
        // at the exact root, even if outward parameter endpoints leave the domain.
        var minimumWeight = Double.infinity, maximumWeight = 0.0
        for weight in curve.source.weights {
            try usage.consumeWork(1)
            minimumWeight = min(minimumWeight, weight); maximumWeight = max(maximumWeight, weight)
        }
        let intervalWeight = OutwardScalarInterval(lower: minimumWeight, upper: maximumWeight)
        for axis in 0..<3 {
            let position = try value(curve.homogeneous[axis], curve: true, cell: cell, usage: &usage)
                .divided(by: weight, maximumDepth: depth, usage: &usage)
            guard let box = try curve.homogeneous[axis].enclosure(over: parameterBox, usage: &usage)
                .divided(by: intervalWeight), box.isFinite else {
                throw rationalAlgebraFailure("Original curve position seed has no finite positive-denominator enclosure.")
            }
            isolations.append(try .init(original: position,
                lower: .originalDouble(box.lower, usage: &usage),
                upper: .originalDouble(box.upper, usage: &usage),
                inheritedDepth: cell.admissionDepth, maximumDepth: depth, usage: &usage))
        }
        let kind = try classify(cell: cell, curve: curve, surfaceNormalNumerators: surfaceNormalNumerators, tolerance: tolerance, usage: &usage)
        try RationalAlgebraStorage.retain(3, of: NativeCurveSurfaceScalarLocalization?.self, usage: &usage)
        var localizations: [NativeCurveSurfaceScalarLocalization?] = []; localizations.reserveCapacity(3)
        for axis in 0..<3 {
            var localization: NativeCurveSurfaceScalarLocalization?
            if isolations[axis].lower != isolations[axis].upper {
                for prefix in 0...axis {
                    let section = try OriginalNativeCurveSurfacePoints.sectionCellIndex(partition: partition,
                        cellIndex: cellIndex, axis: prefix)
                    localization = try NativeCurveSurfaceScalarLocalization.prepare(original: cell.coordinates[axis],
                        sectionCoordinate: partition.cells[section].coordinates[prefix], isolation: isolations[axis],
                        inheritedCoefficientDepth: cell.coefficientAdmissionDepth, maximumDepth: depth,
                        maximumCoefficientDepth: partition.maximumCoefficientDepth, usage: &usage)
                    if let localization {
                        isolations[axis] = try isolations[axis].inheriting(depth: localization.parameterDepth,
                            maximumDepth: depth, usage: &usage)
                        break
                    }
                }
            }
            localizations.append(localization)
        }
        var width = ExactRationalCoefficient.one
        try RationalAlgebraStorage.retain(6, of: OutwardScalarInterval.self, usage: &usage)
        var bounds: [OutwardScalarInterval] = []; bounds.reserveCapacity(6)
        for iteration in 0..<options.maximumIterations {
            try usage.consumeWork(1)
            bounds.removeAll(keepingCapacity: true)
            for index in isolations.indices {
                if index < 3, let localization = localizations[index] {
                    var reusable: NativeCurveSurfaceScalarLocalization?
                    for previous in 0..<index {
                        if let proof = localizations[previous],
                            proof.primitiveCoordinate.context === localization.primitiveCoordinate.context { reusable = proof }
                    }
                    let refined = try localization.refined(maximumWidth: width, isolation: isolations[index],
                        reusing: reusable, maximumDepth: depth,
                        maximumCoefficientDepth: partition.maximumCoefficientDepth, usage: &usage)
                    localizations[index] = refined.proof; isolations[index] = refined.isolation
                } else {
                    isolations[index] = try isolations[index].refined(maximumWidth: width,
                        maximumDepth: depth, usage: &usage)
                }
                bounds.append(try isolations[index].enclosure(usage: &usage))
            }
            let parameters = (
                try parameterRepresentative(bounds[0], native: nativeDomains.0, requested: options.curveRange),
                try parameterRepresentative(bounds[1], native: nativeDomains.1, requested: options.surfaceURange),
                try parameterRepresentative(bounds[2], native: nativeDomains.2, requested: options.surfaceVRange))
            let point = Point3D(x: try representative(bounds[3]), y: try representative(bounds[4]), z: try representative(bounds[5]))
            let positionError = norm(bounds[3] - .exact(point.x), bounds[4] - .exact(point.y), bounds[5] - .exact(point.z))
            let curvePosition = try rationalPosition(curve.homogeneous, u: parameters.0, v: 0, usage: &usage)
            let surfacePosition = try rationalPosition(surfaceHomogeneous, u: parameters.1, v: parameters.2, usage: &usage)
            let residual = norm(curvePosition.0 - surfacePosition.0, curvePosition.1 - surfacePosition.1,
                curvePosition.2 - surfacePosition.2)
            let sourceError = norm(curvePosition.0 - .exact(point.x), curvePosition.1 - .exact(point.y), curvePosition.2 - .exact(point.z))
            let targetError = norm(surfacePosition.0 - .exact(point.x), surfacePosition.1 - .exact(point.y), surfacePosition.2 - .exact(point.z))
            if positionError <= tolerance.distance, residual <= tolerance.distance,
                sourceError <= tolerance.distance, targetError <= tolerance.distance,
                bounds[0].upper - bounds[0].lower <= tolerance.distance,
                bounds[1].upper - bounds[1].lower <= tolerance.distance,
                bounds[2].upper - bounds[2].lower <= tolerance.distance {
                for axis in 0..<3 {
                    try usage.consumeWork(1); retainingParameters.append(isolations[axis])
                    retainingLocalizations.append(localizations[axis])
                }
                return try .init(point: point, curveParameter: parameters.0, surfaceU: parameters.1,
                    surfaceV: parameters.2, kind: kind, residual: residual, iterations: iteration)
            }
            width = try width.divided(by: .natural(2, usage: &usage), usage: &usage)
        }
        throw failure(.resourceLimitExceeded, "Native exact-root publication exhausted refinement iterations.", tolerance)
    }

    private func rationalPosition(_ homogeneous: [ExactBivariatePolynomial], u: Double, v: Double,
        usage: inout OriginalQueryExecution) throws -> (OutwardScalarInterval, OutwardScalarInterval, OutwardScalarInterval) {
        let a = try ExactRationalCoefficient.originalDouble(u, usage: &usage)
        let b = try ExactRationalCoefficient.originalDouble(v, usage: &usage)
        let weight = try homogeneous[3].evaluated(atU: a, v: b, usage: &usage)
        func axis(_ index: Int) throws -> OutwardScalarInterval {
            try homogeneous[index].evaluated(atU: a, v: b, usage: &usage)
                .divided(by: weight, usage: &usage).outwardInterval(usage: &usage)
        }
        return try (axis(0), axis(1), axis(2))
    }

    private func representative(_ interval: OutwardScalarInterval) throws -> Double {
        let middle = interval.lower * 0.5 + interval.upper * 0.5
        guard interval.isFinite, middle.isFinite, middle >= interval.lower, middle <= interval.upper else {
            throw rationalAlgebraFailure("Native root has no finite contained numerical representative.")
        }
        return middle
    }

    private func parameterRepresentative(_ interval: OutwardScalarInterval,
        native: ScalarInterval, requested: ScalarInterval?) throws -> Double {
        let lower = max(native.lower, requested?.lower ?? native.lower)
        let upper = min(native.upper, requested?.upper ?? native.upper)
        let candidate = max(lower, min(upper, try representative(interval)))
        guard lower <= upper, candidate >= interval.lower, candidate <= interval.upper else {
            throw rationalAlgebraFailure("Native parameter representative escaped its exact requested domain.")
        }
        return candidate
    }

    private func norm(_ x: OutwardScalarInterval, _ y: OutwardScalarInterval, _ z: OutwardScalarInterval) -> Double {
        let a = OutwardScalarInterval.exact(max(abs(x.lower), abs(x.upper)))
        let b = OutwardScalarInterval.exact(max(abs(y.lower), abs(y.upper)))
        let c = OutwardScalarInterval.exact(max(abs(z.lower), abs(z.upper)))
        let squared = a * a + b * b + c * c
        if !squared.isFinite || squared.upper < 0 { return .infinity }
        return sqrt(squared.upper).nextUp
    }

    private func classify(cell: OriginalRationalIntersectionCells.Cell,
        curve: OriginalRationalCurvePolynomial, surfaceNormalNumerators: [ExactBivariatePolynomial],
        tolerance: ModelingTolerance, usage: inout OriginalQueryExecution)
        throws -> CurveSurfaceIntersectionKind {
        let depth = usage.effectiveLimits.maximumValueDepth
        let zero = try OriginalSingularFieldElement.constant(.zero, in: cell.context, maximumDepth: depth, usage: &usage)
        let derivativeWeight = try curve.homogeneous[3].differentiated(alongU: true, usage: &usage)
        var tangentSquared = zero, normalSquared = zero, dot = zero
        for axis in 0..<3 {
            let tangentLaw = try curve.homogeneous[axis].differentiated(alongU: true, usage: &usage)
                .multiplied(by: curve.homogeneous[3], usage: &usage)
                .subtracting(curve.homogeneous[axis].multiplied(by: derivativeWeight, usage: &usage), usage: &usage)
            let tangent = try value(tangentLaw, curve: true, cell: cell, usage: &usage)
            let normal = try value(surfaceNormalNumerators[axis], curve: false, cell: cell, usage: &usage)
            tangentSquared = try tangentSquared.adding(tangent.multiplied(by: tangent, maximumDepth: depth, usage: &usage), maximumDepth: depth, usage: &usage)
            normalSquared = try normalSquared.adding(normal.multiplied(by: normal, maximumDepth: depth, usage: &usage), maximumDepth: depth, usage: &usage)
            dot = try dot.adding(tangent.multiplied(by: normal, maximumDepth: depth, usage: &usage), maximumDepth: depth, usage: &usage)
        }
        if try tangentSquared.sign(maximumDepth: depth, usage: &usage) == .zero { return .mixed }
        if try normalSquared.sign(maximumDepth: depth, usage: &usage) == .zero { return .mixed }
        let angle = try ExactRationalCoefficient.originalDouble(tolerance.angle, usage: &usage)
        let threshold = try OriginalSingularFieldElement.constant(angle.multiplied(by: angle, usage: &usage),
            in: cell.context, maximumDepth: depth, usage: &usage)
        let difference = try dot.multiplied(by: dot, maximumDepth: depth, usage: &usage)
            .subtracting(tangentSquared.multiplied(by: normalSquared, maximumDepth: depth, usage: &usage)
                .multiplied(by: threshold, maximumDepth: depth, usage: &usage), maximumDepth: depth, usage: &usage)
        return try difference.sign(maximumDepth: depth, usage: &usage) == .positive ? .transverse : .tangent
    }

    private func failure(_ code: KernelErrorCode, _ message: String, _ tolerance: ModelingTolerance) -> KernelError {
        .init(phase: .geometry, code: code, tolerance: tolerance, message: message)
    }
}
