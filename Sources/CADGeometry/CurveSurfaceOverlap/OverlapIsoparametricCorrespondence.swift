import CADCore
import Foundation

/// A native-axis chart map retained by a whole-domain isoparametric proof.
struct OverlapIsoparametricCorrespondence: Sendable, Equatable {
    let variesU: Bool
    let fixedCoordinate: Double
    let reversedParameterSum: Double?
    let periodic: PeriodicAxis?

    struct PeriodicAxis: Sendable, Equatable {
        let period: Double
        let sourceRange: ScalarInterval
    }

    init(variesU: Bool, fixedCoordinate: Double, reversedParameterSum: Double?,
         periodic: PeriodicAxis? = nil) {
        self.variesU = variesU
        self.fixedCoordinate = fixedCoordinate
        self.reversedParameterSum = reversedParameterSum
        self.periodic = periodic
    }

    func parameter(at sourceParameter: Double) -> SurfaceParameter {
        let varying = reversedParameterSum.map { $0 - sourceParameter } ?? sourceParameter
        return variesU ? SurfaceParameter(u: varying, v: fixedCoordinate)
            : SurfaceParameter(u: fixedCoordinate, v: varying)
    }

    func boundarySourceParameters(uValues: [Double], vValues: [Double], surface: Surface3D,
                                  tolerance: ModelingTolerance) throws -> [Double] {
        guard periodic == nil else {
            throw boundaryFailure(.invalidInput, "Periodic boundary enumeration requires the invocation budget.", tolerance)
        }
        let domain = variesU ? surface.uDomain : surface.vDomain
        let resolver = SurfaceParameterRangeResolver()
        return try (variesU ? uValues : vValues).map { boundary in
            try Task.checkCancellation()
            guard let sum = reversedParameterSum else { return boundary }
            let parameter = sum - boundary
            let virtualSecond = parameter - sum
            let error = (sum - (parameter - virtualSecond)) + (-boundary - virtualSecond)
            // TwoSum expresses the exact inverse as parameter + error.
            // The real affine image of the rounded parameter is boundary + error.
            // Enclose that residual and use the existing chart authority; never
            // call the rounded parameter an exact root or widen the request.
            let enclosure = error == 0 ? OutwardScalarInterval.exact(boundary)
                : OutwardScalarInterval.exact(boundary) + .exact(error)
            let forward = self.parameter(at: parameter)
            let coordinate = variesU ? forward.u : forward.v
            let boundaryRange = try ScalarInterval(lower: boundary, upper: boundary)
            guard parameter.isFinite, error.isFinite, enclosure.isFinite,
                  resolver.resolvedParameter(enclosure.lower, domain: domain,
                    requestedRange: boundaryRange, tolerance: tolerance) != nil,
                  resolver.resolvedParameter(enclosure.upper, domain: domain,
                    requestedRange: boundaryRange, tolerance: tolerance) != nil,
                  resolver.resolvedParameter(coordinate, domain: domain,
                    requestedRange: boundaryRange, tolerance: tolerance) != nil else {
                throw KernelError(phase: .geometry, code: .intersectionFailure, tolerance: tolerance,
                    message: "An isoparametric inverse boundary exceeds the existing chart residual admission.")
            }
            return parameter
        }
    }

    func boundarySourceParameters(uValues: [Double], vValues: [Double], surface: Surface3D,
                                  tolerance: ModelingTolerance,
                                  budget: inout OverlapProofBudget) throws -> [Double] {
        guard let periodic else {
            return try boundarySourceParameters(uValues: uValues, vValues: vValues,
                surface: surface, tolerance: tolerance)
        }
        let domain = variesU ? surface.uDomain : surface.vDomain
        guard case .periodic(let period) = domain, period == periodic.period else {
            throw boundaryFailure(.invalidInput, "A periodic isocurve boundary requires its retained original period.", tolerance)
        }
        let source = periodic.sourceRange
        let image: OutwardScalarInterval
        if let sum = reversedParameterSum {
            image = .exact(sum) - OutwardScalarInterval(lower: source.lower, upper: source.upper)
        } else { image = OutwardScalarInterval(lower: source.lower, upper: source.upper) }
        var cuts: [Double] = []
        for boundary in (variesU ? uValues : vValues) {
            try budget.work(4)
            guard let quotient = (image - .exact(boundary)).divided(by: .exact(period)), quotient.isFinite else {
                throw boundaryFailure(.resourceLimitExceeded, "Periodic boundary cycle bounds are not finite.", tolerance)
            }
            let lower = ceil(quotient.lower), upper = floor(quotient.upper)
            if lower > upper { continue }
            let count = upper - lower + 1
            guard lower.isFinite, upper.isFinite, abs(lower) <= 9_007_199_254_740_991,
                  abs(upper) <= 9_007_199_254_740_991, count.isFinite,
                  count > 0, count <= Double(budget.options.maximumCandidateCount) else {
                throw boundaryFailure(.resourceLimitExceeded, "Periodic boundary copies exceed the finite candidate budget.", tolerance)
            }
            // Every possible incident copy is charged before evaluation or array growth.
            try budget.storage(Int(count))
            var cycle = lower
            while cycle <= upper {
                try budget.work(3)
                guard (cycle * 134_217_729).isFinite, (period * 134_217_729).isFinite else {
                    throw boundaryFailure(.resourceLimitExceeded, "Periodic boundary product has no exact finite expansion.", tolerance)
                }
                let shift = cycle * period
                let product = FloatingPointExpansion.product([cycle], [period])
                guard shift.isFinite, FloatingPointExpansion.sign(
                    FloatingPointExpansion.subtract(product, [shift])) == .zero else {
                    throw boundaryFailure(.resourceLimitExceeded, "Periodic boundary cycle translation is not exactly representable.", tolerance)
                }
                let copy = boundary + shift
                let virtualShift = copy - boundary
                let copyError = (boundary - (copy - virtualShift)) + (shift - virtualShift)
                let parameter: Double, inverseError: Double
                if let sum = reversedParameterSum {
                    parameter = sum - copy
                    let virtualSecond = parameter - sum
                    inverseError = (sum - (parameter - virtualSecond)) + (-copy - virtualSecond)
                } else { parameter = copy; inverseError = 0 }
                let correction = reversedParameterSum == nil ? OutwardScalarInterval.exact(copyError)
                    : .exact(inverseError) - .exact(copyError)
                let root = OutwardScalarInterval.exact(parameter) + correction
                guard copy.isFinite, copyError.isFinite, parameter.isFinite, inverseError.isFinite, root.isFinite else {
                    throw boundaryFailure(.resourceLimitExceeded, "Periodic boundary inversion exceeds finite arithmetic.", tolerance)
                }
                if root.upper >= source.lower, root.lower <= source.upper {
                    guard source.contains(parameter) else {
                        throw boundaryFailure(.intersectionFailure, "A periodic boundary root cannot be represented in its owned source interval.", tolerance)
                    }
                    let error = reversedParameterSum == nil ? -OutwardScalarInterval.exact(copyError)
                        : .exact(inverseError) - .exact(copyError)
                    let enclosure = OutwardScalarInterval.exact(boundary) + error
                    let forward = self.parameter(at: parameter)
                    let coordinate = variesU ? forward.u : forward.v
                    let requested = try ScalarInterval(lower: boundary, upper: boundary)
                    let resolver = SurfaceParameterRangeResolver()
                    guard enclosure.isFinite,
                          resolver.resolvedParameter(enclosure.lower, domain: domain, requestedRange: requested, tolerance: tolerance) != nil,
                          resolver.resolvedParameter(enclosure.upper, domain: domain, requestedRange: requested, tolerance: tolerance) != nil,
                          resolver.resolvedParameter(coordinate, domain: domain, requestedRange: requested, tolerance: tolerance) != nil else {
                        throw boundaryFailure(.intersectionFailure, "A periodic inverse boundary exceeds existing chart rounding admission.", tolerance)
                    }
                    cuts.append(parameter)
                }
                if cycle == upper { break }
                let next = cycle + 1
                guard next > cycle else {
                    throw boundaryFailure(.resourceLimitExceeded, "A periodic boundary cycle has no finite successor.", tolerance)
                }
                cycle = next
            }
        }
        return cuts
    }

    private func boundaryFailure(_ code: KernelErrorCode, _ message: String,
                                 _ tolerance: ModelingTolerance) -> KernelError {
        KernelError(phase: .geometry, code: code, tolerance: tolerance, message: message)
    }

}
