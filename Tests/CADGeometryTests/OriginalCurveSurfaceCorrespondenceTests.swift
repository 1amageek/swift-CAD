import CADCore
import CADGeometry
import Testing

@Suite("Original whole-use curve surface correspondence")
struct OriginalCurveSurfaceCorrespondenceTests {
    private let tolerance = ModelingTolerance.standard
    private var options: CurveSurfaceCorrespondenceValidationOptions {
        .init(maximumSubdivisionDepth: 32, maximumCellCount: 65_536,
              maximumDeviation: ModelingTolerance.standard.distance / 4)
    }
    private var plane: Surface3D { .plane(Plane3D(origin: .origin, normal: .unitZ)) }
    private var producer: any OriginalCurveSurfaceCorrespondenceCertifying {
        OriginalCurveSurfaceCorrespondenceCertifier()
    }
    private func line(_ y: Double = 0) -> Curve3D {
        .bSpline(BSplineCurve3D(degree: 1, knots: [0, 0, 1, 1],
            controlPoints: [.init(x: 0, y: y, z: 0), .init(x: 1, y: y, z: 0)], weights: [1, 1]))
    }
    private func chart(_ y: Double = 0) -> SurfaceParameterCurve {
        .bSpline(BSplineCurve2D(degree: 1, knots: [0, 0, 1, 1],
            controlPoints: [.init(x: 0, y: y), .init(x: 1, y: y)], weights: [1, 1]))
    }

    @Test(.timeLimit(.minutes(2)))
    func stricterRequestedDistanceRejectsTheLiteralWholeIntervalOffset() throws {
        // C(f)=(f,0,0), S(P(f))=(f,distance/2,0) for every f, not only samples.
        let discrepancy = tolerance.distance / 2
        #expect(discrepancy > options.maximumDeviation!)
        #expect(throws: KernelError.self) {
            do {
                _ = try producer.certify(curve: line(), from: 0, to: 1, surface: plane,
                    parameterCurve: chart(discrepancy), options: options, tolerance: tolerance)
            } catch let error as KernelError {
                #expect(error.code == .topologyFailure)
                #expect((error.residual ?? 0) > options.maximumDeviation!)
                throw error
            }
        }
    }

    @Test(.timeLimit(.minutes(2)), arguments: [0.0, ModelingTolerance.standard.distance / 8])
    func exactAndWithinRequestProduceSourceBoundWholeReceipts(offset: Double) throws {
        let curve = line(), pcurve = chart(offset)
        let result = try producer.certify(curve: curve, from: 0, to: 1, surface: plane,
            parameterCurve: pcurve, options: options, tolerance: tolerance)
        #expect(result.achievedUpperBound >= offset)
        #expect(result.achievedUpperBound <= options.maximumDeviation!)
        #expect(result.inspectedCells > 0 && result.consumedCellCount >= result.inspectedCells)
        #expect(result.sourceScalarCount > 0)
        try result.validateBinding(curve: curve, from: 0, to: 1, surface: plane,
            parameterCurve: pcurve, options: options, tolerance: tolerance)
        #expect(throws: KernelError.self) {
            try result.validateBinding(curve: line(tolerance.distance), from: 0, to: 1, surface: plane,
                parameterCurve: pcurve, options: options, tolerance: tolerance)
        }
        #expect(throws: KernelError.self) {
            try result.validateBinding(curve: curve, from: 1, to: 0, surface: plane,
                parameterCurve: pcurve, options: options, tolerance: tolerance)
        }
        #expect(throws: KernelError.self) {
            try result.validateBinding(curve: curve, from: 0, to: 1,
                surface: .plane(Plane3D(origin: .init(x: 0, y: 0, z: tolerance.distance), normal: .unitZ)),
                parameterCurve: pcurve, options: options, tolerance: tolerance)
        }
        #expect(throws: KernelError.self) {
            try result.validateBinding(curve: curve, from: 0, to: 1, surface: plane,
                parameterCurve: pcurve,
                options: .init(maximumSubdivisionDepth: 32, maximumCellCount: 65_536,
                    maximumDeviation: tolerance.distance / 3), tolerance: tolerance)
        }
    }

    @Test(.timeLimit(.minutes(2)))
    func interiorOriginalBernsteinDifferenceCannotHideBehindEndpointAndCenterAgreement() throws {
        let height = 0.004
        let controls = [0.0, height, -4 * height / 3, height, 0.0]
        // This literal degree-four law is zero at endpoints and essentially zero at 1/2.
        // At 1/4 its Bernstein value is height*3/16 > the unchanged request.
        let witness = height * 3 / 16
        #expect(witness > 100 * options.maximumDeviation!)
        let curve = Curve3D.bSpline(BSplineCurve3D(degree: 4,
            knots: [0, 0, 0, 0, 0, 1, 1, 1, 1, 1],
            controlPoints: (0..<5).map { .init(x: Double($0) / 4, y: 0, z: controls[$0]) }))
        #expect(throws: KernelError.self) {
            do {
                _ = try producer.certify(curve: curve, from: 0, to: 1, surface: plane,
                    parameterCurve: chart(), options: options, tolerance: tolerance)
            } catch let error as KernelError {
                #expect(error.code == .topologyFailure)
                throw error
            }
        }
    }

    @Test(.timeLimit(.minutes(2)))
    func originalRationalCoefficientsAndReversedPartialTrimAreCertified() throws {
        // A nonuniform positive-weight line has t-to-position t-dependent speed.
        // Original pcurve uses exactly the same rational law and the directed native domain.
        let curve = Curve3D.bSpline(BSplineCurve3D(degree: 1, knots: [2, 2, 4, 4],
            controlPoints: [.origin, .init(x: 1, y: 0, z: 0)], weights: [1, 2]))
        let parameter = SurfaceParameterCurve.bSpline(BSplineCurve2D(degree: 1, knots: [2, 2, 4, 4],
            controlPoints: [.init(x: 0, y: 0), .init(x: 1, y: 0)], weights: [1, 2]))
        let receipt = try producer.certify(curve: curve, from: 2, to: 4, surface: plane,
            parameterCurve: parameter, options: options, tolerance: tolerance)
        #expect(receipt.achievedUpperBound <= options.maximumDeviation!)
        // For unit-weight native line, reversed partial trim maps x=3/4-f/2.
        let original = Curve3D.bSpline(BSplineCurve3D(degree: 1, knots: [2, 2, 4, 4],
            controlPoints: [.origin, .init(x: 1, y: 0, z: 0)]))
        let reverse = SurfaceParameterCurve.constantV(v: 0, uStart: 0.75, uEnd: 0.25)
        let result = try producer.certify(curve: original, from: 3.5, to: 2.5, surface: plane,
            parameterCurve: reverse, options: options, tolerance: tolerance)
        #expect(result.achievedUpperBound <= options.maximumDeviation!)
    }

    @Test(.timeLimit(.minutes(2)))
    func allOriginalClosedOwningSidesAtC0JoinRemainCovered() throws {
        let curve = Curve3D.bSpline(BSplineCurve3D(degree: 1, knots: [0, 0, 0.5, 1, 1],
            controlPoints: [.origin, .init(x: 0.5, y: 0.2, z: 0), .init(x: 1, y: 0, z: 0)]))
        let parameter = SurfaceParameterCurve.bSpline(BSplineCurve2D(degree: 1,
            knots: [0, 0, 0.5, 1, 1], controlPoints: [.init(x: 0, y: 0), .init(x: 0.5, y: 0.2), .init(x: 1, y: 0)]))
        let result = try producer.certify(curve: curve, from: 0, to: 1, surface: plane,
            parameterCurve: parameter, options: options, tolerance: tolerance)
        #expect(result.achievedUpperBound <= options.maximumDeviation!)
        #expect(result.inspectedCells >= 1)
        // The second original span owns this independent nonzero residual; the join itself is exact.
        let wrongRight = Curve3D.bSpline(BSplineCurve3D(degree: 1, knots: [0, 0, 0.5, 1, 1],
            controlPoints: [.origin, .init(x: 0.5, y: 0.2, z: 0),
                .init(x: 1, y: 0, z: tolerance.distance)]))
        #expect(throws: KernelError.self) {
            do {
                _ = try producer.certify(curve: wrongRight, from: 0, to: 1, surface: plane,
                    parameterCurve: parameter, options: options, tolerance: tolerance)
            } catch let error as KernelError { #expect(error.code == .topologyFailure); throw error }
        }
    }

    @Test(.timeLimit(.minutes(2)))
    func originalCubicLinearSupportUsesItsFullNativeCoefficientLaw() throws {
        // x=u, y=v, z=3u(1-u): Bernstein controls [0,1,1,0].
        let row: [Point3D] = [.init(x: 0, y: 0, z: 0), .init(x: 1.0/3, y: 0, z: 1),
            .init(x: 2.0/3, y: 0, z: 1), .init(x: 1, y: 0, z: 0)]
        let surface = Surface3D.bSpline(BSplineSurface3D(uDegree: 3, vDegree: 1,
            uKnots: [0, 0, 0, 0, 1, 1, 1, 1], vKnots: [0, 0, 1, 1],
            controlPoints: [row, row.map { .init(x: $0.x, y: 1, z: $0.z) }]))
        let curve = Curve3D.bSpline(BSplineCurve3D(degree: 3, knots: [0, 0, 0, 0, 1, 1, 1, 1], controlPoints: row))
        let receipt = try producer.certify(curve: curve, from: 0, to: 1, surface: surface,
            parameterCurve: .constantV(v: 0, uStart: 0, uEnd: 1), options: options, tolerance: tolerance)
        #expect(receipt.achievedUpperBound <= options.maximumDeviation!)
        #expect(throws: KernelError.self) {
            do {
                _ = try producer.certify(curve: curve, from: 0, to: 1, surface: surface,
                    parameterCurve: .constantV(v: 0, uStart: -Double.ulpOfOne, uEnd: 1),
                    options: options, tolerance: tolerance)
            } catch let error as KernelError { #expect(error.code == .invalidInput); throw error }
        }
    }

    @Test(.timeLimit(.minutes(2)))
    func invalidDomainsAndNativeFamiliesRefuseWithoutClippingOrRoundedExtraction() throws {
        #expect(throws: KernelError.self) {
            do {
                _ = try producer.certify(curve: line(), from: -Double.ulpOfOne, to: 1, surface: plane,
                    parameterCurve: chart(), options: options, tolerance: tolerance)
            } catch let error as KernelError { #expect(error.code == .invalidInput); throw error }
        }
        let nonFold = Curve3D.bSpline(BSplineCurve3D(degree: 2, knots: [0, 0, 0, 0.5, 1, 1, 1],
            controlPoints: [.origin, .init(x: 0.3, y: 0, z: 0), .init(x: 0.6, y: 0, z: 0), .init(x: 1, y: 0, z: 0)]))
        #expect(throws: KernelError.self) {
            do {
                _ = try producer.certify(curve: nonFold, from: 0, to: 1, surface: plane,
                    parameterCurve: chart(), options: options, tolerance: tolerance)
            } catch let error as KernelError { #expect(error.code == .unsupportedCapability); throw error }
        }
        #expect(throws: KernelError.self) {
            do {
                _ = try producer.certify(curve: .line(Line3D(origin: .origin, direction: .unitX)), from: 0, to: 1,
                    surface: plane, parameterCurve: chart(), options: options, tolerance: tolerance)
            } catch let error as KernelError { #expect(error.code == .unsupportedCapability); throw error }
        }
    }

    @Test(.timeLimit(.minutes(2)))
    func callerScalarAndAggregateCellCeilingsRefuseWithDistinctUnits() throws {
        #expect(throws: KernelError.self) {
            do {
                _ = try producer.certify(curve: line(), from: 0, to: 1, surface: plane,
                    parameterCurve: chart(), options: .init(maximumSubdivisionDepth: 32, maximumCellCount: 1),
                    tolerance: tolerance)
            } catch let error as KernelError {
                #expect(error.code == .resourceLimitExceeded)
                #expect(error.message.contains("scalar admission")); throw error
            }
        }
        let good = try producer.certify(curve: line(), from: 0, to: 1, surface: plane,
            parameterCurve: chart(), options: options, tolerance: tolerance)
        let exactCeiling = max(good.sourceScalarCount, good.consumedCellCount)
        let boundary = try producer.certify(curve: line(), from: 0, to: 1, surface: plane,
            parameterCurve: chart(), options: .init(maximumSubdivisionDepth: 32, maximumCellCount: exactCeiling,
                maximumDeviation: options.maximumDeviation), tolerance: tolerance)
        #expect(boundary.consumedCellCount == good.consumedCellCount && boundary.sourceScalarCount == good.sourceScalarCount)
        try boundary.validateBinding(curve: line(), from: 0, to: 1, surface: plane,
            parameterCurve: chart(),
            options: .init(maximumSubdivisionDepth: 32, maximumCellCount: exactCeiling,
                maximumDeviation: options.maximumDeviation), tolerance: tolerance)
        #expect(throws: KernelError.self) {
            do {
                _ = try producer.certify(curve: line(), from: 0, to: 1, surface: plane,
                    parameterCurve: chart(), options: .init(maximumSubdivisionDepth: 32, maximumCellCount: exactCeiling - 1,
                        maximumDeviation: options.maximumDeviation), tolerance: tolerance)
            } catch let error as KernelError { #expect(error.code == .resourceLimitExceeded); throw error }
        }
    }

    @Test(.timeLimit(.minutes(2)))
    func nativeCellTraversalHasAnExactAggregateRefusalBoundary() throws {
        // Independent different-degree original tensors both author the exact law x=.001f.
        // They deliberately do not meet the same-basis coefficient residual shortcut.
        let curve = Curve3D.bSpline(BSplineCurve3D(degree: 1, knots: [0, 0, 1, 1],
            controlPoints: [.origin, .init(x: 0.001, y: 0, z: 0)]))
        let parameter = SurfaceParameterCurve.bSpline(BSplineCurve2D(degree: 2,
            knots: [0, 0, 0, 1, 1, 1],
            controlPoints: [.init(x: 0, y: 0), .init(x: 0.0005, y: 0), .init(x: 0.001, y: 0)]))
        let good = try producer.certify(curve: curve, from: 0, to: 1, surface: plane,
            parameterCurve: parameter, options: options, tolerance: tolerance)
        #expect(good.consumedCellCount > good.sourceScalarCount)
        #expect(throws: KernelError.self) {
            do {
                _ = try producer.certify(curve: curve, from: 0, to: 1, surface: plane,
                    parameterCurve: parameter,
                    options: .init(maximumSubdivisionDepth: 1, maximumCellCount: 65_536,
                        maximumDeviation: options.maximumDeviation), tolerance: tolerance)
            } catch let error as KernelError { #expect(error.code == .resourceLimitExceeded); throw error }
        }
        let tight = CurveSurfaceCorrespondenceValidationOptions(maximumSubdivisionDepth: 32,
            maximumCellCount: good.consumedCellCount, maximumDeviation: options.maximumDeviation)
        let boundary = try producer.certify(curve: curve, from: 0, to: 1, surface: plane,
            parameterCurve: parameter, options: tight, tolerance: tolerance)
        #expect(boundary.consumedCellCount == good.consumedCellCount)
        #expect(throws: KernelError.self) {
            do {
                _ = try producer.certify(curve: curve, from: 0, to: 1, surface: plane,
                    parameterCurve: parameter,
                    options: .init(maximumSubdivisionDepth: 32, maximumCellCount: good.consumedCellCount - 1,
                        maximumDeviation: options.maximumDeviation), tolerance: tolerance)
            } catch let error as KernelError {
                #expect(error.code == .resourceLimitExceeded)
                #expect(error.message.contains("preparation and traversal")); throw error
            }
        }
    }

    @Test(.timeLimit(.minutes(2)))
    func cancellationPropagatesWithoutPublishingEvidence() async throws {
        let task = Task {
            while !Task.isCancelled { await Task.yield() }
            return try producer.certify(curve: line(), from: 0, to: 1, surface: plane,
                parameterCurve: chart(), options: options, tolerance: tolerance)
        }
        task.cancel()
        do { _ = try await task.value; Issue.record("Canceled original proof published a receipt.") }
        catch is CancellationError { }
    }
    private func originalProductTensor() -> Surface3D {
        // Independently authored native tensor S(u,v)=(u,v,u*v).
        let first = (0...3).map { Point3D(x: Double($0) / 3, y: 0, z: 0) }
        let second = (0...3).map { Point3D(x: Double($0) / 3, y: 1, z: Double($0) / 3) }
        return .bSpline(BSplineSurface3D(uDegree: 3, vDegree: 1,
            uKnots: [0,0,0,0,1,1,1,1], vKnots: [0,0,1,1], controlPoints: [first,second]))
    }

    @Test(.timeLimit(.minutes(2)))
    func originalTensorCompositionRetainsInteriorPolynomialCorrelation() throws {
        // v=f(1-f); the independent spatial Bernstein law is (f,f-f²,f²-f³).
        let curve = Curve3D.bSpline(BSplineCurve3D(degree: 3,
            knots: [0,0,0,0,1,1,1,1], controlPoints: [
                .origin, .init(x: 1.0/3, y: 1.0/3, z: 0),
                .init(x: 2.0/3, y: 1.0/3, z: 1.0/3), .init(x: 1, y: 0, z: 0)]))
        let chart = SurfaceParameterCurve.bSpline(BSplineCurve2D(degree: 2,
            knots: [0,0,0,1,1,1], controlPoints: [.init(x:0,y:0),.init(x:0.5,y:0.5),.init(x:1,y:0)]))
        let receipt = try producer.certify(curve: curve, from: 0, to: 1, surface: originalProductTensor(),
            parameterCurve: chart, options: options, tolerance: tolerance)
        #expect(receipt.achievedUpperBound <= tolerance.distance)
        #expect(receipt.inspectedCells > 0)
        try receipt.validateBinding(curve: curve, from: 0, to: 1, surface: originalProductTensor(),
            parameterCurve: chart, options: options, tolerance: tolerance)
        guard case let .bSpline(source) = curve else { Issue.record("Literal spatial owner changed."); return }
        var altered = source; altered.controlPoints[1].z += 0.0001
        #expect(throws: KernelError.self) {
            do {
                _ = try producer.certify(curve: .bSpline(altered), from: 0, to: 1,
                    surface: originalProductTensor(), parameterCurve: chart, options: options, tolerance: tolerance)
            } catch let error as KernelError { #expect(error.code == .topologyFailure); throw error }
        }
    }

    @Test(.timeLimit(.minutes(2)))
    func originalRationalInteriorTensorAndReversedTrimRetainTheirWeights() throws {
        let curve = Curve3D.bSpline(BSplineCurve3D(degree: 1, knots: [0,0,1,1],
            controlPoints: [.init(x:0,y:0.25,z:0),.init(x:1,y:0.25,z:0.25)], weights: [1,2]))
        for reverse in [false,true] {
            let points = reverse ? [Point2D(x:1,y:0.25),Point2D(x:0,y:0.25)]
                : [Point2D(x:0,y:0.25),Point2D(x:1,y:0.25)]
            let chart = SurfaceParameterCurve.bSpline(BSplineCurve2D(degree: 1,
                knots: [0,0,1,1], controlPoints: points, weights: reverse ? [2,1] : [1,2]))
            let receipt = try producer.certify(curve: curve, from: reverse ? 1 : 0, to: reverse ? 0 : 1,
                surface: originalProductTensor(), parameterCurve: chart, options: options, tolerance: tolerance)
            #expect(receipt.achievedUpperBound <= tolerance.distance)
        }
    }

    @Test(.timeLimit(.minutes(2)))
    func originalNativeC0CompositionCoversBothClosedJoinSides() throws {
        // v=u on the first half, v=1-u on the second; z=u*v.
        let curve = Curve3D.bSpline(BSplineCurve3D(degree: 3,
            knots: [0,0,0,0,0.5,0.5,0.5,1,1,1,1], controlPoints: [
                .origin, .init(x:1.0/6,y:1.0/6,z:0), .init(x:1.0/3,y:1.0/3,z:1.0/12),
                .init(x:0.5,y:0.5,z:0.25), .init(x:2.0/3,y:1.0/3,z:0.25),
                .init(x:5.0/6,y:1.0/6,z:1.0/6), .init(x:1,y:0,z:0)]))
        let chart = SurfaceParameterCurve.bSpline(BSplineCurve2D(degree: 2,
            knots: [0,0,0,0.5,0.5,1,1,1], controlPoints: [
                .init(x:0,y:0),.init(x:0.25,y:0.25),.init(x:0.5,y:0.5),
                .init(x:0.75,y:0.25),.init(x:1,y:0)]))
        let receipt = try producer.certify(curve: curve, from: 0, to: 1, surface: originalProductTensor(),
            parameterCurve: chart, options: options, tolerance: tolerance)
        #expect(receipt.achievedUpperBound <= tolerance.distance)
        #expect(receipt.inspectedCells >= 2)
        #expect(throws: KernelError.self) {
            do {
                _ = try producer.certify(curve: curve, from: 0, to: 1, surface: originalProductTensor(),
                    parameterCurve: chart,
                    options: .init(maximumSubdivisionDepth:32,maximumCellCount:128,maximumDeviation:tolerance.distance),
                    tolerance: tolerance)
            } catch let error as KernelError { #expect(error.code == .resourceLimitExceeded); throw error }
        }
    }

}
