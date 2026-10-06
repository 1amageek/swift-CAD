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

extension SurfaceParameterCurve {
    package func validate(on surface: Surface3D, tolerance: ModelingTolerance,
        remainingSourceDepth: Int, maximumSubdivisionDepth: Int,
        consumeWork: @Sendable (Int) throws -> Void,
        consumeStorage: (@Sendable (Int) throws -> Void)? = nil,
        maximumAlgebraicDepth: Int? = nil) throws {
        try validateOriginalSource(on: surface, tolerance: tolerance, remainingSourceDepth: remainingSourceDepth,
            maximumSubdivisionDepth: maximumSubdivisionDepth, consumeWork: consumeWork, consumeStorage: consumeStorage,
                maximumAlgebraicDepth: maximumAlgebraicDepth)
    }

    func validateOriginalSource(on surface: Surface3D, tolerance: ModelingTolerance,
        remainingSourceDepth: Int, maximumSubdivisionDepth: Int,
        consumeWork: (Int) throws -> Void,
        consumeStorage: ((Int) throws -> Void)? = nil,
        maximumAlgebraicDepth: Int? = nil) throws {
        guard remainingSourceDepth >= 0, maximumSubdivisionDepth >= 0,
            maximumAlgebraicDepth.map({ (0...32).contains($0) }) ?? true else {
            throw GeometryConversionError.resourceLimitExceeded("Original pcurve validation exhausted caller depth.")
        }
        try consumeWork(0); try CurrentTaskCancellationChecker().checkCancellation(); try tolerance.validate()
        func source(_ curve: SurfaceParameterCurve, on support: Surface3D) throws {
            guard remainingSourceDepth > 0 else {
                throw GeometryConversionError.resourceLimitExceeded("Original pcurve descendant exhausted source depth.")
            }
            try curve.validateOriginalSource(on: support, tolerance: tolerance, remainingSourceDepth: remainingSourceDepth - 1,
                maximumSubdivisionDepth: maximumSubdivisionDepth, consumeWork: consumeWork, consumeStorage: consumeStorage,
                maximumAlgebraicDepth: maximumAlgebraicDepth)
        }
        func parameter(_ value: SurfaceParameter) throws {
            try consumeWork(0); try value.validate()
            guard try surface.uDomain.contains(value.u, tolerance: tolerance),
                  try surface.vDomain.contains(value.v, tolerance: tolerance) else {
                throw GeometryError.invalidDistance(0)
            }
        }
        switch self {
        case .affine, .constantU, .constantV, .harmonic, .sphericalGreatCircle:
            // These finite scalar laws have a fixed number of extrema and no
            // recursively prepared numerical producer or private proof ledger.
            try validate(on: surface, tolerance: tolerance)
        case .polyline(let values):
            guard values.count >= 2 else { throw GeometryError.invalidDistance(Double(values.count)) }
            var length = 0.0, previous: SurfaceParameter?
            for value in values {
                try parameter(value)
                if let previous {
                    let du = value.u - previous.u, dv = value.v - previous.v
                    length += hypot(du, dv)
                }
                previous = value
            }
            guard length > Double.ulpOfOne else { throw GeometryError.invalidDistance(length) }
        case .bSpline(let curve):
            try curve.validate(tolerance: tolerance, consumeWork: { try consumeWork(0) })
            for point in curve.controlPoints { try parameter(.init(u: point.x, v: point.y)) }
        case .originalAffineWord(let image):
            guard remainingSourceDepth > 0 else {
                throw GeometryConversionError.resourceLimitExceeded("Original word pcurve exhausted source depth.")
            }
            func comparisonWork(_ count: Int) throws {
                guard count >= 0 else {
                    throw GeometryConversionError.invalidInput("Original chart comparison requires nonnegative work.")
                }
                for _ in 0..<count { try CurrentTaskCancellationChecker().checkCancellation(); try consumeWork(0) }
            }
            try GeometryStructuralComparisonWork.charge(surface: surface, using: comparisonWork)
            try GeometryStructuralComparisonWork.charge(surface: image.source.surface, using: comparisonWork)
            try GeometryStructuralComparisonWork.charge(surface: image.target.source, using: comparisonWork)
            guard surface == .procedural(.originalAffineWord(image.target)),
                image.source.surface == image.target.source,
                image.startFraction.isFinite, image.endFraction.isFinite,
                image.startFraction >= 0, image.startFraction <= 1,
                image.endFraction >= 0, image.endFraction <= 1,
                image.startFraction != image.endFraction else {
                throw GeometryConversionError.invalidInput("Original word pcurve requires retained support and directed trim binding.")
            }
            try Surface3D.procedural(.originalAffineWord(image.target)).validateOriginalSource(
                tolerance: tolerance, remainingSourceDepth: remainingSourceDepth - 1,
                maximumSubdivisionDepth: maximumSubdivisionDepth, consumeWork: consumeWork, consumeStorage: consumeStorage,
                maximumAlgebraicDepth: maximumAlgebraicDepth)
            try source(image.source.parameterCurve, on: image.source.surface)
        case .originalImage(let image):
            guard surface == .parameterImage(image.targetImage), image.source.surface == image.targetImage.source,
                  image.startFraction.isFinite, image.endFraction.isFinite,
                  image.startFraction >= 0, image.startFraction <= 1,
                  image.endFraction >= 0, image.endFraction <= 1,
                  image.startFraction != image.endFraction, remainingSourceDepth > 0 else {
                throw GeometryConversionError.invalidInput("Original pcurve image source/target binding is invalid.")
            }
            try Surface3D.parameterImage(image.targetImage).validateOriginalSource(tolerance: tolerance,
                remainingSourceDepth: remainingSourceDepth - 1,
                maximumSubdivisionDepth: maximumSubdivisionDepth, consumeWork: consumeWork, consumeStorage: consumeStorage,
                maximumAlgebraicDepth: maximumAlgebraicDepth)
            try source(image.source.parameterCurve, on: image.source.surface)
        case .certifiedImplicit(let chart):
            try chart.intersection.validateCertificationContract(tolerance: tolerance)
            if maximumAlgebraicDepth != nil {
                try Curve3D.implicit(chart.intersection).validateOriginalSource(tolerance: tolerance,
                    remainingSourceDepth: remainingSourceDepth,
                    maximumSubdivisionDepth: maximumSubdivisionDepth,
                    consumeWork: consumeWork, consumeStorage: consumeStorage,
                    maximumAlgebraicDepth: maximumAlgebraicDepth)
            }
            // Only admitted immutable constructors/decoders can create this
            // chart; validation consumes its original hosting/trim witness.
            let expected = chart.role == .first ? chart.intersection.firstSurface : chart.intersection.secondSurface
            guard surface == expected else {
                // FIXME(INCOMPLETE_IMPLEMENTATION): A distinct exact-chart
                // representation needs its caller-admitted equivalence witness.
                throw GeometryConversionError.invalidInput("Original implicit pcurve needs its retained support binding.")
            }
            let upper = chart.intersection.isClosed ? 2.0 : 1.0
            guard chart.startFraction.isFinite, chart.endFraction.isFinite,
                  chart.startFraction >= 0, chart.startFraction <= upper,
                  chart.endFraction >= 0, chart.endFraction <= upper,
                  abs(chart.endFraction - chart.startFraction) > tolerance.relative,
                  abs(chart.endFraction - chart.startFraction) <= 1 + tolerance.relative else {
                throw GeometryConversionError.invalidInput("Original implicit directed trim is invalid.")
            }
        case .projectedAnalytic(let chart):
            guard remainingSourceDepth > 0 else {
                throw GeometryConversionError.resourceLimitExceeded("Original projected pcurve exhausted source depth.")
            }
            try chart.curve.validateOriginalSource(tolerance: tolerance, remainingSourceDepth: remainingSourceDepth - 1,
                maximumSubdivisionDepth: maximumSubdivisionDepth, consumeWork: consumeWork, consumeStorage: consumeStorage,
                maximumAlgebraicDepth: maximumAlgebraicDepth)
            try chart.surface.validateOriginalSource(tolerance: tolerance, remainingSourceDepth: remainingSourceDepth - 1,
                maximumSubdivisionDepth: maximumSubdivisionDepth, consumeWork: consumeWork, consumeStorage: consumeStorage,
                maximumAlgebraicDepth: maximumAlgebraicDepth)
            try chart.validate(on: surface, tolerance: tolerance)
        case .rigidImage(let image):
            try image.transform.validate(tolerance: tolerance)
            guard surface == image.targetSurface, image.startFraction.isFinite, image.endFraction.isFinite,
                  image.startFraction >= -tolerance.relative, image.startFraction <= 1 + tolerance.relative,
                  image.endFraction >= -tolerance.relative, image.endFraction <= 1 + tolerance.relative,
                  abs(image.endFraction - image.startFraction) > Double.leastNonzeroMagnitude,
                  remainingSourceDepth > 0 else {
                throw GeometryConversionError.invalidInput("Original rigid pcurve hosting/trim witness is invalid.")
            }
            // Transform/target equality was proven by the immutable source
            // constructor. Replaying a rounded tensor transform is unnecessary.
            try image.source.surface.validateOriginalSource(tolerance: tolerance, remainingSourceDepth: remainingSourceDepth - 1,
                maximumSubdivisionDepth: maximumSubdivisionDepth, consumeWork: consumeWork, consumeStorage: consumeStorage,
                maximumAlgebraicDepth: maximumAlgebraicDepth)
            try source(image.source.parameterCurve, on: image.source.surface)
        case .periodicTranslation(let base, let u, let v):
            try source(base, on: surface)
            guard u.isFinite, v.isFinite else { throw GeometryError.invalidDistance(0) }
            try withoutActuallyEscaping(consumeWork) { visit in
                var usage = OriginalGeometryValidationAdmission(consumeWork: visit, consumeStorage: consumeStorage)
                guard try OriginalSurfacePeriodShift.proves(on: surface, uShift: u, vShift: v,
                    remainingSourceDepth: remainingSourceDepth,
                    maximumSubdivisionDepth: maximumSubdivisionDepth,
                    tolerance: tolerance, usage: &usage) else {
                    throw GeometryConversionError.invalidInput("Original pcurve shift is not in the support period lattice.")
                }
            }
        case .originalBSplineContinuation(let chart):
            guard chart.certificationTolerance == tolerance, chart.startParameter.isFinite,
                  chart.endParameter.isFinite, chart.startParameter != chart.endParameter,
                  (chart.endParameter - chart.startParameter).isFinite else {
                throw GeometryConversionError.invalidInput("Original continuation endpoints or tolerance are invalid.")
            }
            guard remainingSourceDepth > 0 else {
                throw GeometryConversionError.resourceLimitExceeded("Original continuation exhausted source depth.")
            }
            try chart.original.validate(tolerance: tolerance, consumeWork: { try consumeWork(0) })
            let cover = try chart.originalParameterBounds(over: .init(lower: 0, upper: 1),
                tolerance: tolerance, maximumSpanCount: chart.original.controlPoints.count,
                maximumSubdivisionDepth: maximumSubdivisionDepth, remainingSourceDepth: remainingSourceDepth,
                consumeWork: { try consumeWork(0) }, consumeStorage: consumeStorage,
                maximumAlgebraicDepth: maximumAlgebraicDepth)
            for (value, domain) in [(cover.u, surface.uDomain), (cover.v, surface.vDomain)] {
                try consumeWork(0)
                guard value.lower.isFinite, value.upper.isFinite else {
                    throw GeometryConversionError.resourceLimitExceeded("Original continuation support bounds are nonfinite.")
                }
                if case .closed(let lower, let upper) = domain,
                   value.lower < lower || value.upper > upper {
                    throw GeometryConversionError.invalidInput("Original continuation leaves its closed support domain.")
                }
            }
        case .offsetSurfaceImage(let image):
            try image.validateOriginalRelation(on: surface, tolerance: tolerance,
                remainingSourceDepth: remainingSourceDepth,
                maximumSubdivisionDepth: maximumSubdivisionDepth,
                consumeWork: { try consumeWork(0) })
        case .certifiedAnalyticImplicit, .certifiedAnalyticPair:
            // FIXME(INCOMPLETE_IMPLEMENTATION): These callable manual BRep
            // validation branches still require original analytic
            // certificate proof loops to accept the composing ledger.
            // No private allowance or outer phase debit can authorize success.
            throw KernelError(phase: .geometry, code: .unsupportedCapability, tolerance: tolerance,
                message: "Original pcurve proof validation requires caller-admitted lower producers.")
        }
    }
}
