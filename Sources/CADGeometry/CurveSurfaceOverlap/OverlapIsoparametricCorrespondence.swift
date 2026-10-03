import CADCore

/// A native-axis chart map retained by a whole-domain isoparametric proof.
struct OverlapIsoparametricCorrespondence: Sendable, Equatable {
    let variesU: Bool
    let fixedCoordinate: Double
    let reversedParameterSum: Double?

    func parameter(at sourceParameter: Double) -> SurfaceParameter {
        let varying = reversedParameterSum.map { $0 - sourceParameter } ?? sourceParameter
        return variesU ? SurfaceParameter(u: varying, v: fixedCoordinate)
            : SurfaceParameter(u: fixedCoordinate, v: varying)
    }

    func boundarySourceParameters(uValues: [Double], vValues: [Double], surface: Surface3D,
                                  tolerance: ModelingTolerance) throws -> [Double] {
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
}
