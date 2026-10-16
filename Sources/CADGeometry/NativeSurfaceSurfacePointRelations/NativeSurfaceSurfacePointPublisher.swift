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

/// Exact original tuple localization and numerical publication shared by genuine coverage.
struct NativeSurfaceSurfacePointPublisher {
    private static func value(_ polynomial: ExactBivariatePolynomial, first: Bool,
        cell: OriginalRationalIntersectionCells.Cell, usage: inout OriginalQueryExecution)
        throws -> OriginalSingularFieldElement {
        let embedded = try ExactIntersectionPolynomial.embedding(polynomial, variableCount: 4,
            uCoordinate: first ? 0 : 2, vCoordinate: first ? 1 : 3, usage: &usage)
        return try OriginalIntersectionFieldEvaluation.evaluated(embedded, context: cell.context,
            coordinates: cell.coordinates, maximumDepth: usage.effectiveLimits.maximumValueDepth, usage: &usage)
    }

    static func publish(cell: OriginalRationalIntersectionCells.Cell,
        partition: OriginalRationalIntersectionCells, cellIndex: Int,
        effectiveDomains: [OriginalRationalParameterDomain], first: OriginalRationalSurfacePolynomial, second: OriginalRationalSurfacePolynomial,
        options: SurfaceSurfaceIntersectionOptions, tolerance: ModelingTolerance,
        nativeDomains: [ScalarInterval], requestedDomains: [ScalarInterval],
        retainingParameters: inout [OriginalSingularFieldValueIsolation],
        retainingLocalizations: inout [NativeCurveSurfaceScalarLocalization?],
        usage: inout OriginalQueryExecution) throws -> SurfaceSurfaceIntersectionPoint {
        let depth = usage.effectiveLimits.maximumValueDepth
        let weight = try value(first.homogeneous[3], first: true, cell: cell, usage: &usage)
        try RationalAlgebraStorage.retain(7, of: OriginalSingularFieldValueIsolation.self, usage: &usage)
        var isolations: [OriginalSingularFieldValueIsolation] = []; isolations.reserveCapacity(7)
        for axis in 0..<4 {
            var seed = try OriginalNativeSurfaceSurfacePoints.sectionBounds(partition: partition, cellIndex: cellIndex, axis: axis)
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
        let uBounds = try isolations[0].enclosure(usage: &usage)
        let vBounds = try isolations[1].enclosure(usage: &usage)
        let parameterBox = SurfaceParameterBox(u: try .init(lower: uBounds.lower, upper: uBounds.upper),
            v: try .init(lower: vBounds.lower, upper: vBounds.upper))
        // On the original closed B-spline span, its nonnegative basis sums to
        // one. These original positive weights therefore bound the denominator
        // at the exact root, even if outward parameter endpoints leave the domain.
        var minimumWeight = Double.infinity, maximumWeight = 0.0
        for weight in first.source.weights.joined() {
            try usage.consumeWork(1)
            minimumWeight = min(minimumWeight, weight); maximumWeight = max(maximumWeight, weight)
        }
        let intervalWeight = OutwardScalarInterval(lower: minimumWeight, upper: maximumWeight)
        for axis in 0..<3 {
            let position = try value(first.homogeneous[axis], first: true, cell: cell, usage: &usage)
                .divided(by: weight, maximumDepth: depth, usage: &usage)
            guard let box = try first.homogeneous[axis].enclosure(over: parameterBox, usage: &usage)
                .divided(by: intervalWeight), box.isFinite else {
                throw rationalAlgebraFailure("Original surface position seed has no finite positive-denominator enclosure.")
            }
            isolations.append(try .init(original: position,
                lower: .originalDouble(box.lower, usage: &usage),
                upper: .originalDouble(box.upper, usage: &usage),
                inheritedDepth: cell.admissionDepth, maximumDepth: depth, usage: &usage))
        }
        try RationalAlgebraStorage.retain(4, of: NativeCurveSurfaceScalarLocalization?.self, usage: &usage)
        var localizations: [NativeCurveSurfaceScalarLocalization?] = []; localizations.reserveCapacity(4)
        for axis in 0..<4 {
            var localization: NativeCurveSurfaceScalarLocalization?
            if isolations[axis].lower != isolations[axis].upper {
                for prefix in 0...axis {
                    let section = try OriginalNativeSurfaceSurfacePoints.sectionCellIndex(partition: partition,
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
        try RationalAlgebraStorage.retain(7, of: OutwardScalarInterval.self, usage: &usage)
        var bounds: [OutwardScalarInterval] = []; bounds.reserveCapacity(7)
        for iteration in 0..<options.maximumIterations {
            try usage.consumeWork(1)
            bounds.removeAll(keepingCapacity: true)
            for index in isolations.indices {
                if index < 4, let localization = localizations[index] {
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
            try RationalAlgebraStorage.retain(4, of: Double.self, usage: &usage)
            var parameters: [Double] = []; parameters.reserveCapacity(4)
            for axis in 0..<4 {
                parameters.append(try parameterRepresentative(bounds[axis], native: nativeDomains[axis],
                    requested: requestedDomains[axis]))
            }
            let point = Point3D(x: try representative(bounds[4]), y: try representative(bounds[5]), z: try representative(bounds[6]))
            let positionError = norm(bounds[4] - .exact(point.x), bounds[5] - .exact(point.y), bounds[6] - .exact(point.z))
            let firstPosition = try rationalPosition(first.homogeneous, u: parameters[0], v: parameters[1], usage: &usage)
            let secondPosition = try rationalPosition(second.homogeneous, u: parameters[2], v: parameters[3], usage: &usage)
            let residual = norm(firstPosition.0 - secondPosition.0, firstPosition.1 - secondPosition.1,
                firstPosition.2 - secondPosition.2)
            let sourceError = norm(firstPosition.0 - .exact(point.x), firstPosition.1 - .exact(point.y), firstPosition.2 - .exact(point.z))
            let targetError = norm(secondPosition.0 - .exact(point.x), secondPosition.1 - .exact(point.y), secondPosition.2 - .exact(point.z))
            if positionError <= tolerance.distance, residual <= tolerance.distance,
                sourceError <= tolerance.distance, targetError <= tolerance.distance,
                bounds[0].upper - bounds[0].lower <= tolerance.distance,
                bounds[1].upper - bounds[1].lower <= tolerance.distance,
                bounds[2].upper - bounds[2].lower <= tolerance.distance,
                bounds[3].upper - bounds[3].lower <= tolerance.distance {
                for axis in 0..<4 {
                    try usage.consumeWork(1); retainingParameters.append(isolations[axis])
                    retainingLocalizations.append(localizations[axis])
                }
                return try .init(point: point,
                    firstSurfaceParameter: .init(u: parameters[0], v: parameters[1], point: point,
                        residual: sourceError, iterations: iteration),
                    secondSurfaceParameter: .init(u: parameters[2], v: parameters[3], point: point,
                        residual: targetError, iterations: iteration), residual: residual, tolerance: tolerance)
            }
            width = try width.divided(by: .natural(2, usage: &usage), usage: &usage)
        }
        throw failure(.resourceLimitExceeded, "Native exact-root publication exhausted refinement iterations.", tolerance)
    }

    private static func rationalPosition(_ homogeneous: [ExactBivariatePolynomial], u: Double, v: Double,
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

    private static func representative(_ interval: OutwardScalarInterval) throws -> Double {
        let middle = interval.lower * 0.5 + interval.upper * 0.5
        guard interval.isFinite, middle.isFinite, middle >= interval.lower, middle <= interval.upper else {
            throw rationalAlgebraFailure("Native root has no finite contained numerical representative.")
        }
        return middle
    }

    private static func parameterRepresentative(_ interval: OutwardScalarInterval,
        native: ScalarInterval, requested: ScalarInterval?) throws -> Double {
        let lower = max(native.lower, requested?.lower ?? native.lower)
        let upper = min(native.upper, requested?.upper ?? native.upper)
        let candidate = max(lower, min(upper, try representative(interval)))
        guard lower <= upper, candidate >= interval.lower, candidate <= interval.upper else {
            throw rationalAlgebraFailure("Native parameter representative escaped its exact requested domain.")
        }
        return candidate
    }

    private static func norm(_ x: OutwardScalarInterval, _ y: OutwardScalarInterval, _ z: OutwardScalarInterval) -> Double {
        let a = OutwardScalarInterval.exact(max(abs(x.lower), abs(x.upper)))
        let b = OutwardScalarInterval.exact(max(abs(y.lower), abs(y.upper)))
        let c = OutwardScalarInterval.exact(max(abs(z.lower), abs(z.upper)))
        let squared = a * a + b * b + c * c
        if !squared.isFinite || squared.upper < 0 { return .infinity }
        return sqrt(squared.upper).nextUp
    }

    private static func failure(_ code: KernelErrorCode, _ message: String, _ tolerance: ModelingTolerance) -> KernelError {
        .init(phase: .geometry, code: code, tolerance: tolerance, message: message)
    }
}
