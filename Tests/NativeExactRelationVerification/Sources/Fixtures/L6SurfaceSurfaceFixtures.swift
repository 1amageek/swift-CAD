import CADCore
@testable import CADGeometry

public enum L6SurfaceSurfaceFixtures {
    typealias Base = ExactRationalScalarDomain
    typealias Cells = ExactRealCellDomain<Base>
    typealias Resolver = DefaultExactGeometricRelationResolver<Base, Cells, ExactRealTopology<Base>>

    static func limits(strata: Int = 20000) throws -> ExactGeometricRelationLimits {
        try .init(cells: NativeExactFixtures.cells(), topology: NativeExactFixtures.topology(),
            maximumStrata: strata, maximumProjectionSpans: 20000)
    }

    static func exact<R: NativeExactSurfaceSurfaceGeometricResolving, A: ExactScalarAdmission & ~Copyable>(
        _ resolver: R, _ first: BSplineSurface3D, _ second: BSplineSurface3D,
        firstBox: SurfaceParameterBox? = nil, secondBox: SurfaceParameterBox? = nil,
        strata: Int = 20000, using admission: inout A
    ) throws -> NativeExactGeometricRelation {
        try resolver.exactGeometricRelation(first: first, second: second,
            firstDomain: firstBox, secondDomain: secondBox, tolerance: .standard,
            maximumPolynomialDegree: 3, maximumExtensionLevel: 10,
            limits: limits(strata: strata), using: &admission)
    }

    static func rich<A: ExactScalarAdmission & ~Copyable>(
        _ first: BSplineSurface3D, _ second: BSplineSurface3D,
        firstBox: SurfaceParameterBox? = nil, secondBox: SurfaceParameterBox? = nil,
        options: SurfaceSurfaceIntersectionOptions = .init(), using admission: inout A
    ) throws -> SurfaceSurfaceIntersectionResult {
        try DefaultSurfaceSurfaceIntersector().intersectionResult(first: first, second: second,
            firstDomain: firstBox, secondDomain: secondBox, options: options, tolerance: .standard,
            maximumPolynomialDegree: 3, maximumExtensionLevel: 10,
            limits: limits(), using: &admission)
    }

    static func perpendicular() -> BSplineSurface3D {
        .init(uDegree: 1, vDegree: 1, uKnots: [0, 0, 1, 1], vKnots: [0, 0, 1, 1],
            controlPoints: [[.init(x: 0, y: 0.5, z: 0), .init(x: 1, y: 0.5, z: 0)],
                [.init(x: 0, y: 0.5, z: 1), .init(x: 1, y: 0.5, z: 1)]])
    }

    static func collapsed() -> BSplineSurface3D {
        .init(uDegree: 1, vDegree: 1, uKnots: [0, 0, 1, 1], vKnots: [0, 0, 1, 1],
            controlPoints: Array(repeating: Array(repeating: .init(x: 0.25, y: 0.5, z: 0), count: 2), count: 2))
    }

    static func folded() -> BSplineSurface3D {
        .init(uDegree: 2, vDegree: 1, uKnots: [-1, -1, -1, 1, 1, 1], vKnots: [-1, -1, 1, 1],
            controlPoints: [[.init(x: 1, y: -1, z: 0), .init(x: -1, y: -1, z: 0), .init(x: 1, y: -1, z: 0)],
                [.init(x: 1, y: 1, z: 0), .init(x: -1, y: 1, z: 0), .init(x: 1, y: 1, z: 0)]])
    }

    static func tangency(weighted: Bool = false) -> BSplineSurface3D {
        // The authored homogeneous Z law is (3u - 1)^2 + (3v - 2)^2.
        // Its only common point with Z = 0 has original UV (1/3, 2/3).
        let z = [[5.0, 2.0, 8.0], [-1.0, -4.0, 2.0], [2.0, -1.0, 5.0]]
        let weights = weighted ? [[1.0, 2.0, 1.0], [2.0, 1.0, 2.0], [1.0, 2.0, 1.0]]
            : Array(repeating: Array(repeating: 1.0, count: 3), count: 3)
        var points: [[Point3D]] = []
        for row in 0..<3 {
            var values: [Point3D] = []
            for column in 0..<3 {
                let weight = weights[row][column]
                values.append(.init(x: Double(column) * 0.5 / weight,
                    y: Double(row) * 0.5 / weight, z: z[row][column] / weight))
            }
            points.append(values)
        }
        return .init(uDegree: 2, vDegree: 2, uKnots: [0, 0, 0, 1, 1, 1], vKnots: [0, 0, 0, 1, 1, 1],
            controlPoints: points, weights: weights)
    }

    static func xyz(_ x: Double, _ y: Double, _ z: Double, in result: NativeExactGeometricRelation,
        using admission: inout ExactScalarLedger) throws -> ExactXYZ<Base> {
        let field = result.parameterRelation.coefficientField
        return try .init(field: field, x: field.binary64(exactly: x, using: &admission),
            y: field.binary64(exactly: y, using: &admission), z: field.binary64(exactly: z, using: &admission))
    }

    public static func verify() throws {
        try points()
        try dimensionsAndFibers()
        try selectedDomains()
        try failures()
        print("PASS L6 Native SSI public source binding, numerical points, image/fiber dimensions and atomic failures")
    }

    public static func verifyPoints() throws {
        try points()
    }

    public static func verifyImagesAndFibers() throws {
        try dimensionsAndFibers()
    }

    public static func verifySelectedDomains() throws {
        try selectedDomains()
    }

    public static func verifyFailures() throws {
        try failures()
    }

    static func points() throws {
        for weighted in [false, true] {
            var admission = try NativeExactFixtures.ledger()
            var second = tangency(weighted: weighted)
            let first = NativeExactFixtures.plane()
            let result = try rich(first, second, using: &admission)
            guard let authority = result.originalExactGeometricRelation,
                  result.intersections.count == 1, case .point(let point) = result.intersections[0] else {
                throw NativeExactFixtures.Failure.invalidEvidence
            }
            try NativeExactFixtures.require(!authority.hasPositiveDimensionalSolutions && !authority.hasPositiveDimensionalImage)
            let original = authority.parameterRelation.relation.original
            guard let reduction = original.squareReduction else { throw NativeExactFixtures.Failure.invalidEvidence }
            try NativeExactFixtures.require(reduction.factors.count == 2 && reduction.positiveWeights.count == 2)
            for weight in reduction.positiveWeights {
                try NativeExactFixtures.require(try authority.parameterRelation.coefficientField.sign(
                    of: weight, using: &admission) == .positive)
            }
            for law in original.predicate.source.polynomials {
                for term in law.terms {
                    try NativeExactFixtures.require(term.powers.reduce(0, +) <= 1)
                }
            }
            try NativeExactFixtures.require(authority.geometry.evidenceKind == .isolatedParameters)
            try NativeExactFixtures.require(authority.geometry.strata.allSatisfy {
                $0.imageDimension == 0 && $0.parameterDimension == 0 && $0.fiberDimension == 0
            })
            let sourcePoint = try first.point(u: point.firstSurfaceParameter.u,
                v: point.firstSurfaceParameter.v, tolerance: .standard)
            let targetPoint = try second.point(u: point.secondSurfaceParameter.u,
                v: point.secondSurfaceParameter.v, tolerance: .standard)
            try NativeExactFixtures.require((sourcePoint - targetPoint).length <= point.residual)
            try NativeExactFixtures.require((sourcePoint - point.point).length <= point.firstSurfaceParameter.residual)
            try NativeExactFixtures.require((targetPoint - point.point).length <= point.secondSurfaceParameter.residual)
            try NativeExactFixtures.require(abs(point.secondSurfaceParameter.u - 1.0 / 3.0) <= ModelingTolerance.standard.distance)
            try NativeExactFixtures.require(abs(point.secondSurfaceParameter.v - 2.0 / 3.0) <= ModelingTolerance.standard.distance)
            second.controlPoints.removeAll()
            if case .surfaceSurface(_, let retained, _, _) = authority.parameterRelation.source {
                try NativeExactFixtures.require(retained.controlPoints.count == 3)
            } else { throw NativeExactFixtures.Failure.invalidEvidence }
            let coordinate = weighted ? [(27, 121), (54, 121), (1, 3), (2, 3)] : [(1, 3), (2, 3), (1, 3), (2, 3)]
            try NativeExactFixtures.member(coordinate, authority.parameterRelation, expected: true, &admission)
            print("PASS L6 SSI weighted=\(weighted) exact point and retained source work=\(admission.work)")
        }
    }

    static func dimensionsAndFibers() throws {
        for mode in 0..<4 {
            var admission = try NativeExactFixtures.ledger()
            let first = mode == 3 ? collapsed() : NativeExactFixtures.plane()
            let second = mode == 0 ? perpendicular() : NativeExactFixtures.plane(z: mode == 2 ? 1 : 0)
            let publication = try rich(first, second, using: &admission)
            guard let result = publication.originalExactGeometricRelation else { throw NativeExactFixtures.Failure.invalidEvidence }
            try NativeExactFixtures.require(publication.intersections.isEmpty)
            if mode == 2 {
                try NativeExactFixtures.require(result.geometry.isEmpty && !result.hasPositiveDimensionalSolutions)
            } else {
                let image = mode == 0 ? 1 : mode == 1 ? 2 : 0
                let parameters = mode == 3 ? 2 : image
                try NativeExactFixtures.require(result.hasPositiveDimensionalSolutions)
                try NativeExactFixtures.require(result.hasPositiveDimensionalImage == (image > 0))
                try NativeExactFixtures.require(result.geometry.strata.contains {
                    $0.imageDimension == image && $0.parameterDimension == parameters && $0.fiberDimension == parameters - image
                })
                let point = try xyz(mode == 3 ? 0.25 : 0.5, 0.5, 0, in: result, using: &admission)
                let resolver = Resolver(cells: Cells.self, topology: .init(cells: Cells.self))
                try NativeExactFixtures.require(try resolver.contains(point, in: result.geometry,
                    limits: limits(), using: &admission))
                let fiber = try resolver.fiber(at: .xyz(point), in: result.geometry, limits: limits(), using: &admission)
                try NativeExactFixtures.require(!fiber.isEmpty)
                if mode == 3 { try NativeExactFixtures.require(fiber.selection.cells.contains { $0.dimension == 2 }) }
                var discreteAdmission = try NativeExactFixtures.ledger()
                do {
                    _ = try DefaultSurfaceSurfaceIntersector().intersections(first: first, second: second,
                        options: .init(), tolerance: .standard, maximumPolynomialDegree: 3,
                        maximumExtensionLevel: 10, limits: limits(), using: &discreteAdmission)
                    throw NativeExactFixtures.Failure.invalidEvidence
                } catch is KernelError { }
            }
            print("PASS L6 SSI image/fiber case \(mode) work=\(admission.work)")
        }
        // The original fold preserves both UV branches at the same XYZ station.
        var admission = try NativeExactFixtures.ledger()
        let result = try exact(DefaultSurfaceSurfaceIntersector(), folded(), NativeExactFixtures.plane(), using: &admission)
        let parameterRelation = result.parameterRelation.relation
        let originalLawCount = parameterRelation.selection.partition.source.polynomials.count
        let retainedGraph = parameterRelation.components.incidence.closures.contains { closure in
            closure.proof == .polynomialGraph
                && closure.region.partition.source.polynomials.count == originalLawCount
                && closure.region.signInvariants.contains { $0.sourceLawIndex != nil }
        }
        try NativeExactFixtures.require(retainedGraph)
        let point = try xyz(0.25, 0.5, 0, in: result, using: &admission)
        let fiber = try Resolver(cells: Cells.self, topology: .init(cells: Cells.self)).fiber(
            at: .xyz(point), in: result.geometry, limits: limits(), using: &admission)
        try NativeExactFixtures.require(fiber.components.count == 2)
        try NativeExactFixtures.member([(-1, 2), (1, 2), (1, 4), (1, 2)], result.parameterRelation, expected: true, &admission)
        try NativeExactFixtures.member([(1, 2), (1, 2), (1, 4), (1, 2)], result.parameterRelation, expected: true, &admission)
        print("PASS L6 SSI distinct folded UV fibers work=\(admission.work)")
    }

    static func selectedDomains() throws {
        let surface = tangency()
        for mode in 0..<3 {
            var admission = try NativeExactFixtures.ledger()
            let box = SurfaceParameterBox(u: try .init(lower: mode == 0 ? 2 : mode == 1 ? 0.5 : 0,
                upper: mode == 0 ? 3 : 1), v: try .init(lower: 0, upper: 1))
            let result = try exact(DefaultSurfaceSurfaceIntersector(), NativeExactFixtures.plane(), surface,
                secondBox: box, using: &admission)
            try NativeExactFixtures.require(result.geometry.isEmpty == (mode < 2))
            print("PASS L6 SSI selected exact domain case \(mode) work=\(admission.work)")
        }
        var admission = try NativeExactFixtures.ledger()
        let point = SurfaceParameterBox(u: try .init(lower: 0.5, upper: 0.5), v: try .init(lower: 0.5, upper: 0.5))
        print("VERIFY L6 SSI numerical singleton domain 0.5")
        let selected = try rich(NativeExactFixtures.plane(), NativeExactFixtures.plane(),
            firstBox: point, secondBox: point, using: &admission)
        try NativeExactFixtures.require(selected.intersections.count == 1)
        guard case .point(let numerical) = selected.intersections[0] else { throw NativeExactFixtures.Failure.invalidEvidence }
        try NativeExactFixtures.require(numerical.point == .init(x: 0.5, y: 0.5, z: 0))
        print("PASS L6 SSI numerical singleton domain 0.5 work=\(admission.work)")
        // Preserve the authored singleton instead of underflowing its midpoint to zero.
        var subnormalAdmission = try NativeExactFixtures.ledger()
        let tiny = Double.leastNonzeroMagnitude
        let subnormalBox = SurfaceParameterBox(u: try .init(lower: tiny, upper: tiny),
            v: try .init(lower: 0.5, upper: 0.5))
        print("VERIFY L6 SSI numerical singleton domain leastNonzeroMagnitude")
        let subnormal = try rich(NativeExactFixtures.plane(), NativeExactFixtures.plane(),
            firstBox: subnormalBox, secondBox: subnormalBox, using: &subnormalAdmission)
        guard subnormal.intersections.count == 1, case .point(let tinyPoint) = subnormal.intersections[0] else {
            throw NativeExactFixtures.Failure.invalidEvidence
        }
        try NativeExactFixtures.require(tinyPoint.firstSurfaceParameter.u == tiny
            && tinyPoint.secondSurfaceParameter.u == tiny)
        print("PASS L6 SSI numerical singleton domain leastNonzeroMagnitude work=\(subnormalAdmission.work)")
        print("PASS L6 SSI closed/singleton/empty selected domain")
    }

    static func failures() throws {
        var componentAdmission = try NativeExactFixtures.ledger()
        let first = folded(), second = NativeExactFixtures.plane()
        let secondBox = SurfaceParameterBox(u: try .init(lower: 0.25, upper: 1),
            v: try .init(lower: 0, upper: 1))
        let receipt = try exact(DefaultSurfaceSurfaceIntersector(), first, second,
            secondBox: secondBox, using: &componentAdmission)
        try NativeExactFixtures.require(receipt.parameterRelation.relation.components.count == 2)
        for closure in receipt.parameterRelation.relation.components.incidence.closures {
            for proof in closure.region.signInvariants where proof.projectionInvariant != nil {
                try NativeExactFixtures.require(proof.incomingLaw == nil && proof.quotient == nil && proof.remainder == nil)
            }
        }
        do {
            _ = try NativeExactSurfaceSurfacePublisher.publish(receipt,
                options: .init(maximumSeedCount: 1), using: &componentAdmission)
            throw NativeExactFixtures.Failure.invalidEvidence
        } catch NativeExactGeometricRelationFailure.publication(let cause) {
            guard let error = cause as? KernelError, error.code == .resourceLimitExceeded else { throw cause }
        }
        let complete = try NativeExactSurfaceSurfacePublisher.publish(receipt,
            options: .init(maximumSeedCount: 2), using: &componentAdmission)
        guard let retained = complete.originalExactGeometricRelation,
              case .surfaceSurface(let retainedFirst, let retainedSecond, let firstBox, let retainedSecondBox) = retained.parameterRelation.source else {
            throw NativeExactFixtures.Failure.invalidEvidence
        }
        try NativeExactFixtures.require(retained.parameterRelation.relation.components.count == 2
            && retainedFirst == first && retainedSecond == second && firstBox == nil && retainedSecondBox == secondBox
            && retained.hasPositiveDimensionalSolutions && retained.hasPositiveDimensionalImage)
        try NativeExactFixtures.member([(-1, 2), (1, 2), (1, 4), (1, 2)], retained.parameterRelation,
            expected: true, &componentAdmission)
        try NativeExactFixtures.member([(1, 2), (1, 2), (1, 4), (1, 2)], retained.parameterRelation,
            expected: true, &componentAdmission)
        print("PASS L6 SSI connected source component publication cap work=\(componentAdmission.work)")
        for mode in 0..<4 {
            var admission = try NativeExactFixtures.ledger(work: mode == 0 ? 0 : 80_000_000,
                bytes: mode == 1 ? 0 : 1_073_741_824)
            if mode == 2 { admission.cancel() }
            do {
                _ = try exact(DefaultSurfaceSurfaceIntersector(), NativeExactFixtures.plane(), perpendicular(),
                    strata: mode == 3 ? 0 : 20000, using: &admission)
                throw NativeExactFixtures.Failure.invalidEvidence
            } catch is NativeExactGeometricRelationFailure { }
        }
        var admission = try NativeExactFixtures.ledger()
        do {
            _ = try rich(NativeExactFixtures.plane(), tangency(),
                options: .init(maximumIterations: 1), using: &admission)
            throw NativeExactFixtures.Failure.invalidEvidence
        } catch is KernelError { }
        // Reject cancellation introduced by the terminal result reservation for points and empty coverage.
        for empty in [false, true] {
            var preparation = try NativeExactFixtures.ledger()
            let receipt = try exact(DefaultSurfaceSurfaceIntersector(), NativeExactFixtures.plane(),
                empty ? NativeExactFixtures.plane(z: 1) : tangency(), using: &preparation)
            var measured = try FinalPublicationAdmission()
            _ = try NativeExactSurfaceSurfacePublisher.publish(receipt, options: .init(), using: &measured)
            var cancelled = try FinalPublicationAdmission(cancellingCall: measured.storageCalls)
            do {
                _ = try NativeExactSurfaceSurfacePublisher.publish(receipt, options: .init(), using: &cancelled)
                throw NativeExactFixtures.Failure.invalidEvidence
            } catch NativeExactGeometricRelationFailure.publication(let cause) {
                guard case ExactScalarFailure.cancelled = cause else { throw cause }
            }
            try NativeExactFixtures.require(cancelled.storageCalls == measured.storageCalls)
        }
    }
}
