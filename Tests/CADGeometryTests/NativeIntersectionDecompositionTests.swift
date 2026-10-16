import CADCore
@testable import CADGeometry
import Testing

@Suite("Original native CS and SSI parameter decomposition")
struct NativeIntersectionDecompositionTests {
    private typealias Domain = OriginalRationalParameterDomain
    private struct Admission: ~Copyable, GeometryScalarTestAdmission {
        var proofScopes = ExactScalarProofScopes()
        var work = 0, storage = 0, cells = 0
        var maximumWork = 10_000_000, maximumStorage = 10_000_000
        mutating func consumeWork(_ count: Int) throws(ExactScalarFailure) {
            try checkpoint()
            try proofScopes.checkWork(count)
            do {
            guard count >= 0, count <= maximumWork - work else { throw exhausted("work") }
            work += count
        
            } catch let error as ExactScalarFailure { throw error }
            catch { throw .admissionRejected(error) }
            proofScopes.recordWork(count)
            try checkpoint()
        }
        mutating func retainStorage(bytes: Int) throws(ExactScalarFailure) {
            try checkpoint()
            let count = try geometryTestStorageWords(bytes)
            do {
            guard count >= 0, count <= maximumStorage - storage else { throw exhausted("storage") }
            storage += count
        
            } catch let error as ExactScalarFailure { throw error }
            catch { throw .admissionRejected(error) }
            try checkpoint()
        }
        
        
        private func exhausted(_ reason: String) -> KernelError {
            .init(phase: .geometry, code: .resourceLimitExceeded, tolerance: nil,
                message: "Native intersection exhausted \(reason): work=\(work), storage=\(storage), cells=\(cells).")
        }
            mutating func visitCell(axis: ExactScalarRootAxis, depth: Int) throws(ExactScalarFailure) {
            try admitDepth(value: axis == .value ? depth : 0, coefficient: axis == .coefficient ? depth : 0)
            let mapped = try proofScopes.mapped(value: axis == .value ? depth : 0, coefficient: axis == .coefficient ? depth : 0)
            do {
                switch (axis == .coefficient || proofScopes.exactDepthResource == .coefficientDepth) ? ExactScalarRootAxis.coefficient : .value {
                case .value:
                    let depth = mapped.value

            guard depth >= 0, depth <= 24, cells < 100_000 else { throw exhausted("cells/depth") }
            cells += 1
        
                case .coefficient:
                    let depth = mapped.coefficient

            throw rationalAlgebraFailure("A rational native chart cannot invent coefficient roots.")
        
                }
            } catch let error as ExactScalarFailure { throw error }
            catch { throw .admissionRejected(error) }
            try checkpoint()
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func exactRationalDomainsPreserveNonrepresentableCutsAndInfiniteEnds() throws {
        var usage = Admission()
        let third = try ExactRationalCoefficient.one.divided(by: .natural(3, usage: &usage), usage: &usage)
        let domain = try Domain(lower: third, upper: third, usage: &usage)
        let x = try ExactIntersectionPolynomial.coordinate(variableCount: 1, at: 0, usage: &usage)
        let cut = try x.subtracting(.constant(variableCount: 1, value: third, usage: &usage), usage: &usage)
        let point = try OriginalRationalIntersectionCells.prepare(equations: [cut], variableCount: 1,
            exactDomains: [domain], maximumDepth: 24, usage: &usage)
        #expect(point.solutionCells.count == 1)
        let index = try #require(point.solutionCells.first)
        #expect(try point.cells[index].coordinates[0].rationalValue(usage: &usage) == third)
        let rounded = try Domain(ScalarInterval(lower: 1.0 / 3.0, upper: 1.0 / 3.0), usage: &usage)
        #expect(try domain.intersecting(rounded, usage: &usage) == nil)
        let left = try Domain(lower: nil, upper: third, usage: &usage)
        let right = try Domain(lower: third, upper: nil, usage: &usage)
        #expect(try left.intersecting(right, usage: &usage) == domain)
        let halfLine = try OriginalRationalIntersectionCells.prepare(equations: [], variableCount: 1,
            exactDomains: [right], maximumDepth: 24, usage: &usage)
        #expect(halfLine.solutionCells.count == 2)
        #expect(halfLine.solutionCells.contains { halfLine.cells[$0].dimension == 1 })
        geometryTestExpectFailure({ geometryTestOriginalFailure($0) is KernelError }) { try Domain(lower: .one, upper: .zero, usage: &usage) }
    }

    @Test(.timeLimit(.minutes(1)), arguments: [false, true], [false, true])
    func nativeCurveContactsRetainOriginalWeightedOrRepeatedParameters(tangent: Bool, preferIsolated: Bool) throws {
        var usage = Admission()
        let surface = try law(plane(), usage: &usage)
        let curve = tangent
            ? BSplineCurve3D(degree: 2, knots: [0,0,0,1,1,1], controlPoints: [
                .init(x: 0, y: 0.5, z: 0.25), .init(x: 0.5, y: 0.5, z: -0.25), .init(x: 1, y: 0.5, z: 0.25)])
            : BSplineCurve3D(degree: 1, knots: [0,0,1,1], controlPoints: [
                .init(x: 0.5, y: 0.5, z: -1), .init(x: 0.5, y: 0.5, z: 1)], weights: [1,2])
        let source = try OriginalRationalCurvePolynomial(source: curve, spanIndex: curve.degree,
            tolerance: .standard, usage: &usage)
        let system = try OriginalRationalIntersectionSystem(curve: source, surface: surface, usage: &usage)
        let result = try OriginalRationalIntersectionDecomposition.prepare(system: system,
            normalizeDenominatorFactors: preferIsolated, preferIsolatedCells: preferIsolated, maximumDepth: 24, usage: &usage)
        let (strata, incidence, components) = try coverage(result)
        #expect(components.components.count == 1 && strata.partition.solutionCells.count == 1)
        let point = strata.partition.cells[try #require(strata.partition.solutionCells.first)]
        #expect(point.dimension == 0 && incidence.closures.count == 1)
        #expect(strata.strata.first?.originalJacobianRank == (tangent ? 2 : 3))
        let expected = try ExactRationalCoefficient.one.divided(by: .natural(tangent ? 2 : 3, usage: &usage), usage: &usage)
        #expect(try point.coordinates[0].rationalValue(usage: &usage) == expected)
        #expect(result.system.curveSource?.originalCurve == .bSpline(curve))
        try verifyOriginalSources(result, strata: strata, usage: &usage)
        // An exact singleton query keeps the algebraic contact; no Double cut is used.
        var request = result.nativeDomains
        request[0] = try Domain(lower: expected, upper: expected, usage: &usage)
        let singleton = try OriginalRationalIntersectionDecomposition.prepare(system: system,
            requestedDomains: request, maximumDepth: 24, usage: &usage)
        #expect(try coverage(singleton).0.partition.solutionCells.count == 1)
    }

    @Test(.timeLimit(.minutes(1)))
    func curvedNativeOverlapRetainsItsNonIsoparametricWholeInterval() throws {
        var usage = Admission()
        let source = BSplineSurface3D(uDegree: 2, vDegree: 2, uKnots: [0,0,0,1,1,1], vKnots: [0,0,0,1,1,1],
            controlPoints: [
                [.init(x: 0,y: 0,z: 0), .init(x: 0.5,y: 0,z: 0), .init(x: 1,y: 0,z: 1)],
                [.init(x: 0,y: 0.5,z: 0), .init(x: 0.5,y: 0.5,z: 0), .init(x: 1,y: 0.5,z: 1)],
                [.init(x: 0,y: 1,z: 1), .init(x: 0.5,y: 1,z: 1), .init(x: 1,y: 1,z: 2)]])
        let surface = try law(source, usage: &usage)
        let curve = BSplineCurve3D(degree: 2, knots: [0,0,0,1,1,1], controlPoints: [
            .init(x: 0,y: 0,z: 0), .init(x: 0.5,y: 0.5,z: 0), .init(x: 1,y: 1,z: 2)])
        let original = try OriginalRationalCurvePolynomial(source: curve, spanIndex: 2,
            tolerance: .standard, usage: &usage)
        let system = try OriginalRationalIntersectionSystem(curve: original, surface: surface, usage: &usage)
        let result = try OriginalRationalIntersectionDecomposition.prepare(system: system, maximumDepth: 24, usage: &usage)
        let (strata, _, components) = try coverage(result)
        #expect(components.components.count == 1)
        #expect(strata.partition.solutionCells.contains { strata.partition.cells[$0].dimension == 1 })
        for index in strata.partition.solutionCells {
            let cell = strata.partition.cells[index]
            #expect(try cell.coordinates[0].subtracting(cell.coordinates[1], maximumDepth: 24, usage: &usage)
                .sign(maximumDepth: 24, usage: &usage) == .zero)
            #expect(try cell.coordinates[0].subtracting(cell.coordinates[2], maximumDepth: 24, usage: &usage)
                .sign(maximumDepth: 24, usage: &usage) == .zero)
        }
        try verifyOriginalSources(result, strata: strata, usage: &usage)
    }

    @Test(.timeLimit(.minutes(1)))
    func oneSpatialContactRetainsBothOriginalSurfacePreimages() throws {
        var usage = Admission()
        let source = BSplineSurface3D(uDegree: 2, vDegree: 1, uKnots: [-1,-1,-1,1,1,1], vKnots: [0,0,1,1],
            controlPoints: [[.init(x: 1,y: 0,z: 0), .init(x: -1,y: 0,z: 0), .init(x: 1,y: 0,z: 0)],
                [.init(x: 1,y: 1,z: 0), .init(x: -1,y: 1,z: 0), .init(x: 1,y: 1,z: 0)]])
        let surface = try law(source, lowerU: -1, usage: &usage)
        let curve = BSplineCurve3D(degree: 1, knots: [0,0,1,1], controlPoints: [
            .init(x: 0.25,y: 0.5,z: -1), .init(x: 0.25,y: 0.5,z: 1)])
        let original = try OriginalRationalCurvePolynomial(source: curve, spanIndex: 1, tolerance: .standard, usage: &usage)
        let system = try OriginalRationalIntersectionSystem(curve: original, surface: surface, usage: &usage)
        let result = try OriginalRationalIntersectionDecomposition.prepare(system: system, maximumDepth: 24, usage: &usage)
        let (strata, _, components) = try coverage(result)
        #expect(components.components.count == 2 && strata.partition.solutionCells.count == 2)
        let half = try ExactRationalCoefficient.originalDouble(0.5, usage: &usage)
        var signs = Set<Int>()
        for index in strata.partition.solutionCells {
            let cell = strata.partition.cells[index]
            #expect(try cell.coordinates[0].rationalValue(usage: &usage) == half)
            let sign = try cell.coordinates[1].sign(maximumDepth: 24, usage: &usage)
            let value = try OriginalSingularFieldElement.constant(sign == .positive ? half : half.negated,
                in: cell.context, maximumDepth: 24, usage: &usage)
            #expect(try cell.coordinates[1].subtracting(value, maximumDepth: 24, usage: &usage)
                .sign(maximumDepth: 24, usage: &usage) == .zero)
            signs.insert(sign == .positive ? 1 : -1)
        }
        #expect(signs == [1, -1])
        try verifyOriginalSources(result, strata: strata, usage: &usage)
    }

    @Test(.timeLimit(.minutes(1)), arguments: [0,1,2], [false, true])
    func nativeSurfaceProductsDistinguishCrossingCoincidenceAndNearAbsence(kind: Int, preferIsolated: Bool) throws {
        var usage = Admission()
        let first = try law(plane(), usage: &usage)
        let source = kind == 0
            ? BSplineSurface3D(uDegree: 1, vDegree: 1, uKnots: [0,0,1,1], vKnots: [0,0,1,1],
                controlPoints: [[.init(x: 0,y: 0.5,z: -1), .init(x: 1,y: 0.5,z: -1)],
                    [.init(x: 0,y: 0.5,z: 1), .init(x: 1,y: 0.5,z: 1)]])
            : plane(height: kind == 1 ? 0 : 5e-7)
        let second = try law(source, usage: &usage)
        let system = try OriginalRationalIntersectionSystem(first: first, second: second, usage: &usage)
        let result = try OriginalRationalIntersectionDecomposition.prepare(system: system,
            normalizeDenominatorFactors: preferIsolated, preferIsolatedCells: preferIsolated, maximumDepth: 24, usage: &usage)
        let (strata, _, components) = try coverage(result)
        #expect(components.components.count == (kind == 2 ? 0 : 1))
        if kind == 2 { #expect(strata.partition.solutionCells.isEmpty) }
        else { #expect(strata.partition.solutionCells.contains { strata.partition.cells[$0].dimension == (kind == 1 ? 2 : 1) }) }
        #expect(result.system.firstSurfaceSource.source == first.source)
        #expect(result.system.secondSurfaceSource?.source == second.source)
        try verifyOriginalSources(result, strata: strata, usage: &usage)
    }

    @Test(.timeLimit(.minutes(1)))
    func disjointNativeDomainsAndCallerFailuresPublishOnlyTheirActualProof() async throws {
        var usage = Admission()
        let surface = try law(plane(), usage: &usage)
        let curve = BSplineCurve3D(degree: 1, knots: [0,0,1,1], controlPoints: [
            .init(x: 0,y: 0,z: 0), .init(x: 1,y: 1,z: 0)])
        let original = try OriginalRationalCurvePolynomial(source: curve, spanIndex: 1, tolerance: .standard, usage: &usage)
        let system = try OriginalRationalIntersectionSystem(curve: original, surface: surface, usage: &usage)
        var request = try [Domain(lower: .one, upper: nil, usage: &usage), Domain(nil, usage: &usage), Domain(nil, usage: &usage)]
        request[0] = try Domain(lower: .natural(2, usage: &usage), upper: nil, usage: &usage)
        let result = try OriginalRationalIntersectionDecomposition.prepare(system: system, requestedDomains: request,
            maximumDepth: 24, usage: &usage)
        guard case .excludedNativeProduct(let axis) = result.coverage else {
            Issue.record("Disjoint original bounds require an exact domain exclusion."); return
        }
        #expect(axis == 0 && result.effectiveDomains == nil)
        var work = Admission(); work.maximumWork = 0
        geometryTestExpectFailure({ geometryTestOriginalFailure($0) is KernelError }) { try OriginalRationalIntersectionDecomposition.prepare(system: system, maximumDepth: 24, usage: &work) }
        var storage = Admission(); storage.maximumStorage = 0
        geometryTestExpectFailure({ geometryTestOriginalFailure($0) is KernelError }) { try OriginalRationalIntersectionDecomposition.prepare(system: system, maximumDepth: 24, usage: &storage) }
        geometryTestExpectFailure({ geometryTestOriginalFailure($0) is KernelError }) { try OriginalRationalIntersectionDecomposition.prepare(system: system,
            requestedDomains: [], maximumDepth: 24, usage: &usage) }
        let cancelled = await Task {
            withUnsafeCurrentTask { $0?.cancel() }
            var admission = Admission()
            do {
                _ = try OriginalRationalIntersectionDecomposition.prepare(system: system,
                    requestedDomains: request, maximumDepth: 24, usage: &admission)
                return false
            } catch let error where geometryTestIsCancelled(error) { return admission.work == 0 && admission.storage == 0 }
            catch { return false }
        }.value
        #expect(cancelled)
    }

    @Test(.timeLimit(.minutes(1)))
    func affineClosureRequiresItsSourceBindingAndBothProofsHaveTheSameClosedSet() throws {
        var usage = Admission()
        let bounded = try Domain(lower: .zero, upper: .one, usage: &usage)
        let partition = try OriginalRationalIntersectionCells.prepare(equations: [], variableCount: 2,
            exactDomains: [bounded, bounded], thomEncoding: true, maximumDepth: 24, usage: &usage)
        let interior = try #require(partition.solutionCells.first { partition.cells[$0].dimension == 2 })
        let affine = try OriginalIntersectionCellClosure.prepare(partition: partition, cellIndex: interior,
            maximumDepth: 24, usage: &usage)
        guard case .affineCell = affine.proof else { Issue.record("Affine region needs its exact segment proof."); return }
        let quantified = try OriginalIntersectionCellClosure.prepare(partition: partition, cellIndex: interior,
            allowAffineProofs: false, maximumDepth: 24, usage: &usage)
        for original in partition.cells.indices where partition.cells[original].coordinates.count == 2 {
            let condition = try OriginalIntersectionCellCondition(partition: partition, cellIndex: original, usage: &usage)
            var hasQuantifiedPiece = false
            for piece in quantified.includedCells {
                let cell = quantified.freePartition.cells[piece]
                if try condition.contains(context: cell.context, coordinates: cell.coordinates, maximumDepth: 24, usage: &usage) {
                    hasQuantifiedPiece = true; break
                }
            }
            #expect(affine.includedCells.contains(original) == hasQuantifiedPiece)
        }
        let source = try OriginalIntersectionCellCondition(partition: partition, cellIndex: interior, usage: &usage)
        let foreign = try OriginalRationalIntersectionCells.prepare(equations: [], variableCount: 1,
            exactDomains: [bounded], thomEncoding: true, maximumDepth: 24, usage: &usage)
        geometryTestExpectFailure({ geometryTestOriginalFailure($0) is KernelError }) {
            try OriginalAffineCellClosure.prepare(partition: foreign, source: source, maximumDepth: 24, usage: &usage)
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func preferredIsolatedExecutionRetainsMixedOriginalPointAndCurveComponents() throws {
        var usage = Admission()
        let source = BSplineSurface3D(uDegree: 1, vDegree: 2,
            uKnots: [0,0,1,1], vKnots: [0,0,0,1,1,1], controlPoints: [
                [.init(x: 0,y: 0,z: 0), .init(x: 1,y: 0,z: -1)],
                [.init(x: 0,y: -0.5,z: 0), .init(x: 1,y: -0.5,z: -0.5)],
                [.init(x: 0,y: 0,z: 0), .init(x: 1,y: 0,z: 0)]])
        let surface = try law(source, usage: &usage)
        let curve = BSplineCurve3D(degree: 1, knots: [0,0,1,1], controlPoints: [
            .init(x: 0,y: 0,z: 0), .init(x: 1,y: 0,z: 0)])
        let original = try OriginalRationalCurvePolynomial(source: curve, spanIndex: 1,
            tolerance: .standard, usage: &usage)
        let system = try OriginalRationalIntersectionSystem(curve: original, surface: surface, usage: &usage)
        let result = try OriginalRationalIntersectionDecomposition.prepare(system: system,
            normalizeDenominatorFactors: true, preferIsolatedCells: true, maximumDepth: 24, usage: &usage)
        let (strata, _, components) = try coverage(result)
        #expect(strata.equationIdeal?.classification == .positiveDimensional)
        #expect(components.components.count == 2)
        #expect(components.components.contains { component in
            component.cellIndexes.allSatisfy { strata.partition.cells[$0].dimension == 0 }
        })
        #expect(components.components.contains { component in
            component.cellIndexes.contains { strata.partition.cells[$0].dimension == 1 }
        })
        try verifyOriginalSources(result, strata: strata, usage: &usage)
    }

    @Test(.timeLimit(.minutes(1)))
    func preferredIsolatedExecutionUsesActualClosedDomainDimension() throws {
        var usage = Admission()
        let surface = try law(plane(), usage: &usage)
        let curve = BSplineCurve3D(degree: 1, knots: [0,0,1,1], controlPoints: [
            .init(x: 0,y: 0,z: 0), .init(x: 1,y: 1,z: 0)])
        let original = try OriginalRationalCurvePolynomial(source: curve, spanIndex: 1,
            tolerance: .standard, usage: &usage)
        let system = try OriginalRationalIntersectionSystem(curve: original, surface: surface, usage: &usage)
        let zero = try Domain(lower: .zero, upper: .zero, usage: &usage)
        let full = try Domain(lower: .zero, upper: .one, usage: &usage)
        let result = try OriginalRationalIntersectionDecomposition.prepare(system: system,
            requestedDomains: [zero, full, full], normalizeDenominatorFactors: true,
            preferIsolatedCells: true, maximumDepth: 24, usage: &usage)
        let (strata, _, components) = try coverage(result)
        #expect(strata.equationIdeal?.classification == .positiveDimensional)
        #expect(components.components.count == 1 && strata.partition.solutionCells.count == 1)
        #expect(strata.strata.allSatisfy { $0.isolatedRankSigns != nil && $0.originalJacobianRank == 2 })
        #expect(strata.partition.solutionCells.allSatisfy { strata.partition.cells[$0].dimension == 0 })
        try verifyOriginalSources(result, strata: strata, usage: &usage)
    }

    private func coverage(_ result: OriginalRationalIntersectionDecomposition) throws -> (
        OriginalRationalIntersectionStrata, OriginalRationalIntersectionIncidence, OriginalRationalParameterComponents) {
        guard case .parameterCells(let strata, let incidence, let components) = result.coverage else {
            throw rationalAlgebraFailure("Expected complete real coverage inside the original native product.")
        }
        return (strata, incidence, components)
    }

    private func verifyOriginalSources(_ result: OriginalRationalIntersectionDecomposition,
        strata: OriginalRationalIntersectionStrata, usage: inout Admission) throws {
        #expect(strata.equationIdeal?.originalEquations == (result.guardedEquations?.normalizedEquations ?? result.system.equations))
        #expect(strata.partition.nonzeroPolynomials == result.system.denominatorGuards)
        for index in strata.partition.solutionCells {
            let cell = strata.partition.cells[index]
            // Evaluate original minors independently of the ideal-normal-form
            // partition witnesses used by the production rank classifier.
            var originalRank = 0
            for minor in strata.jacobian.minors {
                let value = try OriginalIntersectionFieldEvaluation.evaluated(minor.polynomial,
                    context: cell.context, coordinates: cell.coordinates, maximumDepth: 24, usage: &usage)
                if try value.sign(maximumDepth: 24, usage: &usage) != .zero {
                    originalRank = max(originalRank, minor.order)
                }
            }
            #expect(strata.strata.first(where: { $0.cellIndex == index })?.originalJacobianRank == originalRank)
            for equation in result.system.equations {
                #expect(try OriginalIntersectionFieldEvaluation.evaluated(equation, context: cell.context,
                    coordinates: cell.coordinates, maximumDepth: 24, usage: &usage).sign(maximumDepth: 24, usage: &usage) == .zero)
            }
            for denominator in result.system.denominatorGuards {
                #expect(try OriginalIntersectionFieldEvaluation.evaluated(denominator, context: cell.context,
                    coordinates: cell.coordinates, maximumDepth: 24, usage: &usage).sign(maximumDepth: 24, usage: &usage) != .zero)
            }
        }
    }

    private func plane(height: Double = 0) -> BSplineSurface3D {
        BSplineSurface3D(uDegree: 1, vDegree: 1, uKnots: [0,0,1,1], vKnots: [0,0,1,1],
            controlPoints: [[.init(x: 0,y: 0,z: height), .init(x: 1,y: 0,z: height)],
                [.init(x: 0,y: 1,z: height), .init(x: 1,y: 1,z: height)]])
    }

    private func law(_ source: BSplineSurface3D, lowerU: Double = 0,
        usage: inout Admission) throws -> OriginalRationalSurfacePolynomial {
        let domain = SurfaceParameterBox(u: try .init(lower: lowerU, upper: 1), v: try .init(lower: 0, upper: 1))
        let prepared = try PreparedBSplineSurfaceDifferentialEncloser(surface: source, tolerance: .standard,
            using: &usage)
        let spans = try prepared.originalNativeSpans(over: domain, tolerance: .standard, maximumSpanCount: 1,
            using: &usage)
        let native = try #require(spans.first)
        return try OriginalRationalSurfacePolynomial(source: source, native: native, domain: domain,
            view: .init(x: 0,y: 0,z: 1), tolerance: .standard, usage: &usage)
    }
}
