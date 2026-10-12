#if canImport(Darwin)
import Darwin
#elseif canImport(WASILibc)
import WASILibc
#endif
import Synchronization
import CADCore
@testable import CADGeometry

/// Exercises the actual SSI constructor and the ordinary complete-empty CS authority.
@main struct ImplicitClosedPlaneEmptyAcceptance {
    struct Failure: Error { let line: Int }
    typealias Base = CADGeometry.OriginalExactScalarDomain
    typealias Value = CADGeometry.OriginalExactScalar
    typealias Source = ImplicitSourcePhase.OriginalImplicitCurveSnapshot
    typealias Receipt = ImplicitHostPlaneSourcePhase.OriginalImplicitHostPlaneSeparationReceipt
    typealias Interval = RetainedHostAdapters.ExactParameterInterval<Value>
    private let tolerance = ModelingTolerance.standard
    static func require(_ condition: Bool, line: Int = #line) throws {
        if !condition { throw Failure(line: line) }
    }
    static func ledger(work: Int = 8_388_608, bytes: Int = 268_435_456,
        valueDepth: Int = 32, coefficientDepth: Int = 32) throws -> ExactScalarLedger {
        .init(limits: try .init(work: work, storageBytes: bytes,
            valueDepth: valueDepth, coefficientDepth: coefficientDepth))
    }
    static func limits(sourceDepth: Int = 1, charts: Int = 4) throws -> OriginalDomainIdentityLimits {
        try .init(source: .init(remainingSourceDepth: sourceDepth), maximumTransportDepth: 0,
            maximumCharts: charts, maximumFamilies: 0, maximumIdentityProofs: 0)
    }
    static func equal(_ lhs: Value, _ rhs: Value, field: Base, using a: inout ExactScalarLedger) throws {
        try require(field.compare(lhs, rhs, using: &a) == .equal)
    }
  enum ConstructorFailure: Error { case missingExactGraph }
    private func closedPlanePcurve() throws -> (
        intersection: CertifiedImplicitIntersectionCurve,
        surface: BSplineSurface3D
    ) {
        let plane = BSplineSurface3D(
            uDegree: 1,
            vDegree: 1,
            uKnots: [0.0, 0.0, 1.0, 1.0],
            vKnots: [0.0, 0.0, 1.0, 1.0],
            controlPoints: [
                [
                    Point3D(x: -1.5, y: -1.5, z: 0.0),
                    Point3D(x: 1.5, y: -1.5, z: 0.0),
                ],
                [
                    Point3D(x: -1.5, y: 1.5, z: 0.0),
                    Point3D(x: 1.5, y: 1.5, z: 0.0),
                ],
            ],
            weights: [[1.0, 1.25], [0.8, 1.0]]
        )
        let sphere = try AnalyticSurfaceBSplineBuilder().surface(
            for: CanonicalAnalyticSurface(.analytic(.sphere(
                center: .origin,
                radius: 1.0
            ))),
            boundedBy: plane,
            periodicSeamOffset: Double.pi * 0.125,
            tolerance: tolerance
        )
        guard let exact = try ExactIsoparametricPlanarIntersectionGraph
            .certified(
                first: sphere,
                second: plane,
                tolerance: tolerance
            ) else { throw ConstructorFailure.missingExactGraph }
        let domains = [
            sphere.uDomain,
            sphere.vDomain,
            plane.uDomain,
            plane.vDomain,
        ]
        let cells = try exact.cells.map { source in
            let bounds = try zip(source.normalizedBounds, domains).map {
                normalized, domain in
                try ScalarInterval(
                    lower: actual(normalized.lower, in: domain),
                    upper: actual(normalized.upper, in: domain)
                )
            }
            return try CertifiedImplicitIntersectionGraphCell(
                parameterBox: SurfaceIntersectionParameterBox(
                    firstU: bounds[0],
                    firstV: bounds[1],
                    secondU: bounds[2],
                    secondV: bounds[3]
                ),
                freeParameter: source.freeParameter,
                direction: .forward,
                lowerAnchor: exact.actualParameterPair(
                    in: source,
                    at: 0.0,
                    first: sphere,
                    second: plane,
                    tolerance: tolerance
                ),
                midpointAnchor: exact.actualParameterPair(
                    in: source,
                    at: 0.5,
                    first: sphere,
                    second: plane,
                    tolerance: tolerance
                ),
                upperAnchor: exact.actualParameterPair(
                    in: source,
                    at: 1.0,
                    first: sphere,
                    second: plane,
                    tolerance: tolerance
                ),
                firstSurface: sphere,
                secondSurface: plane,
                tolerance: tolerance
            )
        }
        let intersection = try CertifiedImplicitIntersectionCurve(
            firstSurface: sphere,
            secondSurface: plane,
            cells: cells,
            isClosed: true,
            tolerance: tolerance
        )
        return (intersection, plane)
    }
    private func actual(
        _ normalized: Double,
        in domain: ParameterDomain
    ) -> Double {
        guard case let .closed(lower, upper) = domain else { return .nan }
        return lower + (upper - lower) * normalized
    }
    static func input() throws -> (Curve3D, Surface3D, CurveSurfaceIntersectionOptions) {
        let fixture = try Self().closedPlanePcurve()
        var options = CurveSurfaceIntersectionOptions()
        options.curveRange = try .init(lower: 0, upper: 1)
        options.surfaceURange = try .init(lower: -2, upper: 2)
        options.surfaceVRange = try .init(lower: -2, upper: 2)
        return (.implicit(fixture.intersection),
            .analytic(.plane(origin: .init(x: 0, y: 0, z: 2), normal: .unitZ)), options)
    }
    final class Counter: Sendable {
        struct State: Sendable { var work = 0; var bytes = 0 }
        private let state = Mutex(State())
        let maximumWork: Int
        let maximumBytes: Int
        let cancelAt: Int?
        let cancelStorageAt: Int?
        init(work: Int = 8_388_608, bytes: Int = 268_435_456,
            cancelAt: Int? = nil, cancelStorageAt: Int? = nil) {
            maximumWork = work; maximumBytes = bytes
            self.cancelAt = cancelAt; self.cancelStorageAt = cancelStorageAt
        }
        func consume(_ depth: Int) throws {
            let reached = try state.withLock { state in
                guard state.work < maximumWork else { throw ExactScalarFailure.resourceLimit(.work) }
                state.work += 1; return state.work
            }
            if reached == cancelAt { throw CancellationError() }
        }
        func retain(_ bytes: Int) throws {
            let reached = try state.withLock { state in
                let next = state.bytes.addingReportingOverflow(bytes)
                guard bytes >= 0, !next.overflow, next.partialValue <= maximumBytes else {
                    throw ExactScalarFailure.resourceLimit(.storage)
                }
                state.bytes = next.partialValue; return state.bytes
            }
            if reached == cancelStorageAt { withUnsafeCurrentTask { $0?.cancel() } }
        }
        var totals: State { state.withLock { $0 } }
    }
    static func logCount(_ label: StaticString, _ value: Int) {
        print(label, terminator: ": ")
        var divisor = 1
        while divisor <= value / 10 { divisor *= 10 }
        repeat { putchar(Int32(48 + value / divisor % 10)); divisor /= 10 } while divisor > 0
        putchar(10); fflush(nil)
    }
    static func admitted(_ curve: Curve3D, _ plane: Surface3D, _ options: CurveSurfaceIntersectionOptions,
        _ counter: Counter, sourceDepth: Int = 8, algebraicDepth: Int = 32,
        charts: Int = 262_144) throws -> CurveSurfaceIntersectionResult {
        try DefaultCurveSurfaceIntersector().intersectionResult(curve: curve, surface: plane,
            options: options, tolerance: .standard, maximumSpanCount: charts,
            maximumSubdivisionDepth: 8, remainingSourceDepth: sourceDepth,
            consumeWork: { try counter.consume($0) }, consumeStorage: { try counter.retain($0) },
            maximumAlgebraicDepth: algebraicDepth)
    }
    static func closed<S: Sendable>(_ selection: OriginalParameterSelection<S, Base>, axis: Int,
        lower: Double, upper: Double, using a: inout ExactScalarLedger) throws {
        try require(selection.axes[axis].intervalCount == 1)
        let interval = selection.axes[axis].intervals.first!
        guard case .finite(let lo) = interval.lower, case .finite(let hi) = interval.upper else {
            throw Failure(line: #line)
        }
        try require(!interval.isEmpty && interval.includesLower && interval.includesUpper)
        let f = selection.frame.scalarField
        try equal(lo, f.binary64(exactly: lower, using: &a), field: f, using: &a)
        try equal(hi, f.binary64(exactly: upper, using: &a), field: f, using: &a)
    }
    static func verify(_ result: CurveSurfaceIntersectionResult, options: CurveSurfaceIntersectionOptions) throws {
        guard let reading = result.originalImplicitHostPlaneExclusion else { throw Failure(line: #line) }
        let owner = reading.original, proof = owner.exclusion, f = proof.field
        var a = try ledger()
        try owner.admitProof(limits: limits(), using: &a)
        try require(reading.isEmpty && !reading.hasPositiveDimensionalSolutions && !reading.hasPositiveDimensionalImage)
        try require(owner.isEmpty && !owner.hasPositiveDimensionalSolutions && !owner.hasPositiveDimensionalImage)
        try require(result.points.isEmpty && result.overlaps.isEmpty && !result.hasPositiveDimensionalSolutions)
        let zero = try f.integer(0, using: &a), one = try f.integer(1, using: &a), two = try f.integer(2, using: &a)
        try equal(proof.support.lower, zero, field: f, using: &a)
        try equal(proof.support.upper, one, field: f, using: &a)
        try equal(proof.hostHeight, zero, field: f, using: &a)
        try equal(proof.planeHeight, two, field: f, using: &a)
        try equal(proof.signedGap, f.integer(-2, using: &a), field: f, using: &a)
        try require(f.sign(of: proof.signedGap, using: &a) == .negative)
        switch proof.proofScope { case .originalCommonRootPositionOnly: break }
        try require(proof.cellCount == 4 && proof.cells.count == 4)
        let snapshot = proof.source.original, original = snapshot.original
        try require(original.isClosed && original.cells.count == 4 && snapshot.cells.count == 4)
        try require(proof.source.sourceDepth == 1 && snapshot.first.sourceDepth == 0
            && snapshot.second.sourceDepth == 0 && proof.plane.source.sourceDepth == 0)
        try require(proof.host.owner === snapshot.second.owner)
        try require(original.cells[0].startAnchor.first.u == 0 && original.cells[3].endAnchor.first.u == 4)
        for (index, cell) in original.cells.enumerated() {
            try require(cell.freeParameter == .firstU && cell.direction == .forward)
            try require(cell.parameterBox.firstU.lower == Double(index)
                && cell.parameterBox.firstU.upper == Double(index + 1))
            for coordinate in [cell.parameterBox.firstV, cell.parameterBox.secondU, cell.parameterBox.secondV] {
                try require(coordinate.lower == 0 && coordinate.upper == 1)
            }
            for anchor in [cell.lowerAnchor, cell.midpointAnchor, cell.upperAnchor] {
                try require(anchor.first.v == 1)
            }
        }
        guard case .bSpline(let firstHost) = original.firstSurface,
            case .bSpline(let secondHost) = original.secondSurface else { throw Failure(line: #line) }
        try require(snapshot.first.original == firstHost && snapshot.second.original == secondHost)
        try require(proof.hostSupport.count == 2 && proof.hostWeights.count == 4
            && proof.hostHomogeneousZ.count == 4)
        for support in proof.hostSupport {
            try equal(support.lower, zero, field: f, using: &a)
            try equal(support.upper, one, field: f, using: &a)
        }
        let actualWeights = [1.0, 1.25, 0.8, 1.0]
        for index in 0..<4 {
            let row = index / 2, column = index % 2
            try require(secondHost.controlPoints[row][column].z == 0
                && secondHost.weights[row][column].bitPattern == actualWeights[index].bitPattern)
            try equal(proof.hostWeights[index], f.binary64(exactly: actualWeights[index], using: &a), field: f, using: &a)
            try require(f.sign(of: proof.hostWeights[index], using: &a) == .positive)
            try equal(proof.hostHomogeneousZ[index], zero, field: f, using: &a)
        }
        // Whole-support oracle: positive-weight rational second host has Z=0.
        // Every target parameter lies on Z=2; all original T/UV/incidents are excluded.
        try equal(proof.plane.origin[0], zero, field: f, using: &a)
        try equal(proof.plane.origin[1], zero, field: f, using: &a)
        try equal(proof.plane.origin[2], two, field: f, using: &a)
        for axis in 0..<3 { try equal(proof.plane.normal[axis], axis == 2 ? one : zero, field: f, using: &a) }
        try require(owner.support.frame.source.owner === proof.source.owner
            && owner.request.frame.source.owner === proof.source.owner && owner.effective.frame.source.owner === proof.source.owner)
        try require(owner.plane.source.owner === proof.plane.source.owner
            && owner.plane.law.source.owner === proof.plane.source.owner)
        for candidate in [owner.support.frame.scalarField, owner.request.frame.scalarField,
            owner.effective.frame.scalarField, owner.plane.support.frame.scalarField,
            owner.plane.request.frame.scalarField, owner.plane.effective.frame.scalarField] {
            _ = try f.importing(candidate.integer(0, using: &a), using: &a)
        }
        try closed(owner.support, axis: 0, lower: 0, upper: 1, using: &a)
        let range = try options.curveRange ?? ScalarInterval(lower: 0, upper: 1)
        try closed(owner.request, axis: 0, lower: range.lower, upper: range.upper, using: &a)
        let lower = max(0, range.lower), upper = min(1, range.upper)
        if lower > upper { try require(owner.effective.isEmpty) }
        else { try closed(owner.effective, axis: 0, lower: lower, upper: upper, using: &a) }
        for axis in 0..<2 {
            try require(owner.plane.support.axes[axis].intervalCount == 1)
            let whole = owner.plane.support.axes[axis].intervals.first!
            guard case .negativeInfinity = whole.lower, case .positiveInfinity = whole.upper else {
                throw Failure(line: #line)
            }
            try require(!whole.isEmpty && !whole.includesLower && !whole.includesUpper)
            if let range = axis == 0 ? options.surfaceURange : options.surfaceVRange {
                try closed(owner.plane.request, axis: axis, lower: range.lower, upper: range.upper, using: &a)
                try closed(owner.plane.effective, axis: axis, lower: range.lower, upper: range.upper, using: &a)
            } else {
                for selection in [owner.plane.request, owner.plane.effective] {
                    try require(selection.axes[axis].intervalCount == 1)
                    let whole = selection.axes[axis].intervals.first!
                    guard case .negativeInfinity = whole.lower, case .positiveInfinity = whole.upper else {
                        throw Failure(line: #line)
                    }
                }
            }
        }
        try require(result.originalAngularPlaneRelation == nil && result.originalRevolutionAxisRelation == nil
            && result.originalNativePoints == nil && result.originalNativeRelations == nil
            && result.originalPolynomialPoints == nil && result.originalAffinePoints == nil
            && result.originalCoonsPoints == nil && result.originalExactGeometricRelation == nil
            && result.originalIssuedGeometricRelation == nil && result.originalIssuedNumericalPoints == nil
            && result.originalContainedLiftPlaneFamily == nil && result.originalCertifiedApexPlaneExclusion == nil
            && result.originalImplicitCurveRelation == nil)
    }
    static func interval(_ lower: Double, _ upper: Double, includesLower: Bool = true,
        includesUpper: Bool = true, field f: Base, using a: inout ExactScalarLedger) throws -> Interval {
        try .checked(field: f, lower: .finite(f.binary64(exactly: lower, using: &a)),
            upper: .finite(f.binary64(exactly: upper, using: &a)), includesLower: includesLower,
            includesUpper: includesUpper, depth: .init(value: 0, coefficient: 0), using: &a)
    }
    static func resourceFailure(_ body: () throws -> Void) throws {
        do { try body(); throw Failure(line: #line) }
        catch let error as KernelError { try require(error.code == .resourceLimitExceeded) }
    }
    static func sourceFailure(_ expected: OriginalSourceIssuanceFailure,
        _ body: () throws -> Void) throws {
        do { try body(); throw Failure(line: #line) }
        catch let error as OriginalSourceIssuanceFailure {
            switch (expected, error) {
            case (.unsupportedRepresentation, .unsupportedRepresentation),
                (.unsupportedCoefficientField, .unsupportedCoefficientField),
                (.sourceDepthLimit, .sourceDepthLimit), (.chartLimit, .chartLimit),
                (.unresolvedAuthority, .unresolvedAuthority), (.scalar(.incompatibleDomain), .scalar(.incompatibleDomain)): return
            default: throw error
            }
        }
    }
    static func sourceControls(_ curve: Curve3D, _ plane: Surface3D) throws {
        var a = try ledger()
        let f = try Base(maximumValueDepth: 32, maximumCoefficientDepth: 32, using: &a)
        let l = try OriginalSourceIssuanceLimits(remainingSourceDepth: 1)
        let provider = ImplicitHostPlaneSourcePhase.OriginalImplicitHostExclusionSnapshotProvider(tolerance: .standard)
        try require(ImplicitHostPlaneSourcePhase.OriginalImplicitHostExclusionSnapshotProvider.supports(curve: curve, plane: plane))
        try require(!ImplicitSourcePhase.OriginalImplicitCurveSnapshotProvider.supports(curve))
        let source = try DefaultOriginalSourceBindingIssuer(provider: provider).bind(curve, limits: l, using: &a)
        func basis(_ targetPlane: Surface3D, using a: inout ExactScalarLedger) throws
            -> OriginalPlaneBasisReceipt<AngularSourcePhase.OriginalPlaneSnapshot, Base> {
            let target = try DefaultOriginalSourceBindingIssuer(provider:
                AngularSourcePhase.OriginalPlaneSnapshotProvider(tolerance: .standard)).bind(targetPlane, limits: l, using: &a)
            let one = try f.integer(1, using: &a)
            return try DefaultOriginalPlaneBasisIssuer<AngularSourcePhase.OriginalPlaneSnapshot, Base>()
                .issue(source: target, field: f, firstLength: one, normalLength: one, limits: l, using: &a)
        }
        let issuer = ImplicitHostPlaneSourcePhase.DefaultOriginalImplicitHostPlaneSeparationIssuer()
        let receipt = try issuer.issue(source: source, plane: basis(plane, using: &a), maximumCells: 4, limits: l, using: &a)
        try receipt.admitProof(maximumCells: 4, limits: l, using: &a)
        try sourceFailure(.chartLimit) {
            _ = try issuer.issue(source: source, plane: basis(plane, using: &a), maximumCells: 3, limits: l, using: &a)
        }
        try sourceFailure(.chartLimit) { try receipt.admitProof(maximumCells: 3, limits: l, using: &a) }
        let coincidentHeight = Surface3D.analytic(.plane(origin: .origin, normal: .unitZ))
        try sourceFailure(.unresolvedAuthority) {
            _ = try issuer.issue(source: source, plane: basis(coincidentHeight, using: &a), maximumCells: 4, limits: l, using: &a)
        }
        let oblique = Surface3D.analytic(.plane(origin: .init(x: 0, y: 0, z: 2), normal: .unitX))
        try sourceFailure(.unsupportedRepresentation) {
            _ = try issuer.issue(source: source, plane: basis(oblique, using: &a), maximumCells: 4, limits: l, using: &a)
        }
        for unsupported in [coincidentHeight, oblique,
            .analytic(.plane(origin: .init(x: 0, y: 0, z: 2), normal: .init(x: 0, y: 0, z: 2))),
            .bSpline(source.original.second.original)] {
            try require(!ImplicitHostPlaneSourcePhase.OriginalImplicitHostExclusionSnapshotProvider.supports(curve: curve, plane: unsupported))
            try require(OriginalImplicitHostPlanePublicProducer().resolve(curve: curve, surface: unsupported,
                options: .init(), tolerance: .standard) == nil)
        }
        let unrelated = Curve3D.circle(.init(center: .origin, normal: .unitZ, radius: 1))
        try sourceFailure(.unsupportedRepresentation) { _ = try provider.snapshot(unrelated, limits: l, using: &a) }
        try sourceFailure(.sourceDepthLimit) {
            _ = try provider.snapshot(curve, limits: .init(remainingSourceDepth: 0), using: &a)
        }
        print("PASS source whole-host position-only proof; chart4/3, nonseparation, unsupported selector and source depth")
    }
  enum ControlFailure: Error { case coefficientBitsChanged, derivativeLawChanged, outsideSupportAccepted, unexpectedOutsideFailure, unexpectedControlLayout, unexpectedNearDomainSuccess }
  static func taylorControls() throws {
    var cases = 0
    for constant in [OutwardScalarInterval(lower: 0, upper: 1), .exact(4)] {
      for gain in [1.0, -2.0, 0.0] {
        var scalar = try SurfaceAreaIntervalTaylorScalarJet(order: 3, axis: .u,
          tolerance: .standard, consumeWork: {})
        let coefficients = [constant, .exact(2), OutwardScalarInterval(lower: -3, upper: -1), .exact(0.5)]
        for k in 0...3 { try scalar.set(coefficients[k], k, 0) }
        var work = 0, storage = 0
        let result = try OriginalCurveTaylorComposition.scaledParameter(scalar,
          scale: .exact(gain), order: 3, consumeWork: { work += 1 },
          consumeStorage: { storage += $0 })
        let actualConstant = try result.coefficient(0, 0)
        guard actualConstant.lower.bitPattern == constant.lower.bitPattern,
          actualConstant.upper.bitPattern == constant.upper.bitPattern else {
          throw ControlFailure.coefficientBitsChanged
        }
        var power = OutwardScalarInterval.exact(1)
        for k in 0...3 {
          if k > 0 {
            let expected = coefficients[k] * power
            let actual = try result.coefficient(k, 0)
            guard actual.lower.bitPattern == expected.lower.bitPattern,
              actual.upper.bitPattern == expected.upper.bitPattern else {
              throw ControlFailure.derivativeLawChanged
            }
          }
          power = power * .exact(gain)
        }
        cases += 1
      }
    }
    try require(cases == 6)
  }
  static func outsideSupportControl(_ surface: BSplineSurface3D) throws {
    let prepared = try PreparedSurfaceDifferentialEncloser(surface: .bSpline(surface), tolerance: .standard)
    do {
      _ = try prepared.intervalJet(overClosedBox: SurfaceParameterBox(
        u: ScalarInterval(lower: -Double.leastNonzeroMagnitude, upper: 1),
        v: ScalarInterval(lower: 0, upper: 1)), tolerance: .standard,
        maximumSpanCount: 262_144, maximumSubdivisionDepth: 8,
        remainingSourceDepth: 16, consumeWork: {})
    } catch {
      guard let kernel = error as? KernelError, kernel.code == .invalidInput,
        kernel.message == "Original closed surface bounds extend beyond their retained support." else {
        throw ControlFailure.unexpectedOutsideFailure
      }
      try require(kernel.phase == .geometry)
      return
    }
    throw ControlFailure.outsideSupportAccepted
  }

  static func clonedCells(_ original: CertifiedImplicitIntersectionCurve,
      reversed: Bool = false, swapped: Bool = false, nearDomain: Bool = false)
      throws -> [CertifiedImplicitIntersectionGraphCell] {
    let ordered = reversed ? Array(original.cells.reversed()) : original.cells
    return try ordered.map { cell in
      let box = cell.parameterBox
      let firstV = nearDomain ? try ScalarInterval(lower: box.firstV.lower,
        upper: box.firstV.upper.nextDown) : box.firstV
      func anchor(_ value: SurfaceIntersectionParameterPair) throws -> SurfaceIntersectionParameterPair {
        let first = SurfaceParameter(u: value.first.u,
          v: nearDomain ? box.firstV.upper.nextDown : value.first.v)
        return try SurfaceIntersectionParameterPair(first: swapped ? value.second : first,
          second: swapped ? first : value.second)
      }
      return try CertifiedImplicitIntersectionGraphCell(
        parameterBox: SurfaceIntersectionParameterBox(
          firstU: swapped ? box.secondU : box.firstU,
          firstV: swapped ? box.secondV : firstV,
          secondU: swapped ? box.firstU : box.secondU,
          secondV: swapped ? firstV : box.secondV),
        freeParameter: swapped ? .secondU : cell.freeParameter,
        direction: reversed ? .reversed : cell.direction,
        lowerAnchor: anchor(cell.lowerAnchor), midpointAnchor: anchor(cell.midpointAnchor),
        upperAnchor: anchor(cell.upperAnchor),
        firstSurface: swapped ? original.secondSurface : original.firstSurface,
        secondSurface: swapped ? original.firstSurface : original.secondSurface,
        tolerance: .standard)
    }
  }
  static func controls(_ original: CertifiedImplicitIntersectionCurve) throws {
    guard original.cells.count == 4, original.isClosed,
      original.cells.allSatisfy({ $0.freeParameter == .firstU && $0.direction == .forward }),
      original.cells[0].startAnchor.first.u == 0,
      original.cells[3].endAnchor.first.u == 4 else { throw ControlFailure.unexpectedControlLayout }
    let reverseCells = try clonedCells(original, reversed: true)
    let reverse = try CertifiedImplicitIntersectionCurve(firstSurface: original.firstSurface,
      secondSurface: original.secondSurface, cells: reverseCells, isClosed: true, tolerance: .standard)
    guard reverse.cells.count == 4, reverse.isClosed,
      reverse.cells.allSatisfy({ $0.direction == .reversed }),
      reverse.cells[0].startAnchor.first.u == 4,
      reverse.cells[3].endAnchor.first.u == 0 else { throw ControlFailure.unexpectedControlLayout }

    let swappedCells = try clonedCells(original, swapped: true)
    let swapped = try CertifiedImplicitIntersectionCurve(firstSurface: original.secondSurface,
      secondSurface: original.firstSurface, cells: swappedCells, isClosed: true, tolerance: .standard)
    guard swapped.cells.count == 4, swapped.isClosed,
      swapped.cells.allSatisfy({ $0.freeParameter == .secondU && $0.direction == .forward }),
      swapped.cells[0].startAnchor.second.u == 0,
      swapped.cells[3].endAnchor.second.u == 4 else { throw ControlFailure.unexpectedControlLayout }

    var negativeStage = "graph-cell-construction"
    do {
      let nearCells = try clonedCells(original, nearDomain: true)
      negativeStage = "closed-curve-construction"
      _ = try CertifiedImplicitIntersectionCurve(firstSurface: original.firstSurface,
        secondSurface: original.secondSurface, cells: nearCells, isClosed: true, tolerance: .standard)
    } catch {
  
      guard let kernel = error as? KernelError else { throw error }
      try require(kernel.code == .intersectionFailure && negativeStage == "closed-curve-construction")
      try require(kernel.message == "Original graph endpoint requires its unique closed gauge root enclosure.")
      return
    }
    throw ControlFailure.unexpectedNearDomainSuccess
  }

    static func run() async throws {
        let (curve, plane, options) = try input()
#if hasFeature(Embedded)
        let group = getenv("CAD_PROOF_GROUP").map { String(cString: $0) } ?? "complete"
#else
        let group = CommandLine.arguments[1]
#endif
        func query(_ selected: CurveSurfaceIntersectionOptions) throws -> CurveSurfaceIntersectionResult {
            try DefaultCurveSurfaceIntersector().intersectionResult(curve: curve, surface: plane,
                options: selected, tolerance: .standard)
        }
        if group == "changed-controls" {
            if getenv("CAD_PROOF_REUSE_NATIVE_CONTROLS") != nil {
                print("REUSE exact frozen Native constructor v1 and Taylor/support v2 controls; no replay")
            } else {
                try taylorControls()
                guard case .implicit(let original) = curve,
                    case .bSpline(let second) = original.secondSurface else { throw Failure(line: #line) }
                try controls(original)
                try outsideSupportControl(second)
                print("PASS selected3 actual constructor direction/role/nearbox, Taylor bits/derivatives and strict support controls")
            }
        } else if group == "complete" {
            try verify(query(options), options: options)
            print("PASS complete actual closed4 ordinary rich CS: whole positive-weight Native host Z0 excludes planeZ2")
        } else if group == "dispatch" {
            try require(DefaultCurveSurfaceIntersector().intersections(curve: curve, surface: plane,
                options: options, tolerance: .standard).isEmpty)
            try verify(admitted(curve, plane, options, Counter()), options: options)
            let counter = Counter()
            let bare = try DefaultCurveSurfaceIntersector().intersections(curve: curve, surface: plane,
                options: options, tolerance: .standard, maximumSpanCount: 262_144,
                maximumSubdivisionDepth: 8, remainingSourceDepth: 8,
                consumeWork: { try counter.consume($0) }, consumeStorage: { try counter.retain($0) },
                maximumAlgebraicDepth: 32)
            try require(bare.isEmpty && counter.totals.work > 0 && counter.totals.bytes > 0)
            print("PASS all four ordinary bare/rich and standard/callback public entries preserve complete-empty authority")
        } else if group == "source" { try sourceControls(curve, plane)
        } else if group == "requests" {
            for control in 0..<8 {
                var selected = options
                if control == 0 { selected.curveRange = try .init(lower: 0.25, upper: 0.5) }
                if control == 1 { selected.curveRange = try .init(lower: 2, upper: 3) }
                if control == 2 { selected.curveRange = try .init(lower: 0, upper: 0) }
                if control == 3 { selected.curveRange = try .init(lower: 1, upper: 1) }
                if control == 4 { selected.surfaceURange = try .init(lower: 0, upper: 0) }
                if control == 5 { selected.surfaceVRange = try .init(lower: 7, upper: 7) }
                if control == 6 { selected.surfaceURange = nil; selected.surfaceVRange = nil }
                if control == 7 { selected.curveRange = nil }
                try verify(query(selected), options: selected)
            }
            let owner = try query(options).originalImplicitHostPlaneExclusion!.original
            var a = try ledger()
            let f = owner.exclusion.field, l = try limits()
            let uv = [try interval(-2, 2, field: f, using: &a)]
            for control in 0..<4 {
                let i: Interval
                if control == 0 { i = try interval(0, 1, includesLower: false, includesUpper: false, field: f, using: &a) }
                else if control == 1 { i = try interval(0, 0, includesLower: false, field: f, using: &a) }
                else if control == 2 { i = try .empty(depth: .init(value: 0, coefficient: 0), using: &a) }
                else { i = try interval(0.5, 0.5, field: f, using: &a) }
                let selected = try OriginalImplicitHostPlaneExclusion.resolve(exclusion: owner.exclusion,
                    curveIntervals: [i], planeIntervals: [uv, uv], limits: l, using: &a)
                try require(selected.isEmpty)
                try require(selected.effective.isEmpty == (control == 1 || control == 2))
                if control == 0 {
                    let effective = selected.effective.axes[0].intervals.first!
                    try require(!effective.includesLower && !effective.includesUpper)
                }
            }
            // Separate bindings of identical immutable source remain different owners.
            let foreign = try DefaultOriginalSourceBindingIssuer(provider:
                ImplicitHostPlaneSourcePhase.OriginalImplicitHostExclusionSnapshotProvider(tolerance: .standard))
                .bind(curve, limits: l.source, using: &a)
            let foreignFrame = try DefaultOriginalParameterTransporter<Source, Base>().frame(
                source: foreign, field: f, support: [[interval(0, 1, field: f, using: &a)]],
                semantics: [.authoredScalar], limits: l, using: &a)
            let foreignSelection = try foreignFrame.fullSelection(limits: l, using: &a)
            do {
                _ = try owner.support.intersection(foreignSelection, limits: l, using: &a)
                throw Failure(line: #line)
            } catch OriginalDomainIdentityFailure.foreignOwner { }
            print("PASS closed/open/empty/singleton/source-external requests and same-owner selections; foreign binding owner rejected")
        } else if group == "resources" {
            let baseline = Counter(), result = try admitted(curve, plane, options, baseline)
            try verify(result, options: options)
            let totals = baseline.totals
            try require(totals.work > 1 && totals.bytes > 0)
            logCount("QUERY_WORK", totals.work); logCount("QUERY_STORAGE", totals.bytes)
            let exact = Counter(work: totals.work, bytes: totals.bytes)
            try verify(admitted(curve, plane, options, exact), options: options)
            try require(exact.totals.work == totals.work && exact.totals.bytes == totals.bytes)
            try resourceFailure { _ = try admitted(curve, plane, options, Counter(work: totals.work - 1)) }
            try resourceFailure { _ = try admitted(curve, plane, options, Counter(bytes: totals.bytes - 1)) }
            try verify(admitted(curve, plane, options, Counter(), sourceDepth: 1), options: options)
            try verify(admitted(curve, plane, options, Counter(), charts: 4), options: options)
            try resourceFailure { _ = try admitted(curve, plane, options, Counter(), charts: 3) }
            var cells = options; cells.maximumSubdivisionCells = 4
            try verify(admitted(curve, plane, cells, Counter()), options: cells)
            cells.maximumSubdivisionCells = 3
            try resourceFailure { _ = try admitted(curve, plane, cells, Counter()) }
            try resourceFailure { _ = try admitted(curve, plane, options, Counter(), sourceDepth: 0) }
            let owner = result.originalImplicitHostPlaneExclusion!.original, depth = owner.proofDepth
            logCount("ATTAINED_VALUE_DEPTH", depth.value); logCount("ATTAINED_COEFFICIENT_DEPTH", depth.coefficient)
            let attained = max(depth.value, depth.coefficient)
            try verify(admitted(curve, plane, options, Counter(), algebraicDepth: attained), options: options)
            if attained > 0 { try resourceFailure { _ = try admitted(curve, plane, options, Counter(), algebraicDepth: attained - 1) } }
            var a = try ledger()
            try owner.admitProof(limits: limits(charts: 4), using: &a)
            do { try owner.admitProof(limits: limits(charts: 3), using: &a); throw Failure(line: #line) }
            catch OriginalSourceIssuanceFailure.chartLimit { }
            // An empty contact has no candidate pair. The exact supported count is zero.
            var count = options; count.maximumCandidateCount = 1
            try verify(admitted(curve, plane, count, Counter()), options: count)
            for tick in [1, totals.work / 2] {
                let counter = Counter(cancelAt: tick)
                do { _ = try admitted(curve, plane, options, counter); throw Failure(line: #line) }
                catch is CancellationError {}
                try require(counter.totals.work == tick)
            }
            print("PASS measured exact N/N-1 work/storage, attained scalar/source depth, chart4/3, no fabricated positive pair count and entry/mid cancellation")
        } else if group == "readmission" {
            let owner = try query(options).originalImplicitHostPlaneExclusion!.original
            var a = try ledger()
            try owner.admitProof(limits: limits(), using: &a)
            let work = a.work, bytes = a.storageBytes
            logCount("READMISSION_WORK", work); logCount("READMISSION_STORAGE", bytes)
            var exact = try ledger(work: work, bytes: bytes)
            try owner.admitProof(limits: limits(), using: &exact)
            try require(exact.work == work && exact.storageBytes == bytes)
            for control in 0..<2 where control == 0 || bytes > 0 {
                var limited = try ledger(work: control == 0 ? work - 1 : work, bytes: control == 1 ? bytes - 1 : bytes)
                do { try owner.admitProof(limits: limits(), using: &limited); throw Failure(line: #line) }
                catch let error as ExactScalarFailure { guard case .resourceLimit = error else { throw error } }
                catch let error as OriginalSourceIssuanceFailure { guard case .scalar(.resourceLimit) = error else { throw error } }
            }
            let depth = owner.proofDepth
            logCount("READMISSION_VALUE_DEPTH", depth.value)
            logCount("READMISSION_COEFFICIENT_DEPTH", depth.coefficient)
            var depthExact = try ledger(valueDepth: depth.value, coefficientDepth: depth.coefficient)
            try owner.admitProof(limits: limits(), using: &depthExact)
            try require(depthExact.valueDepth == depth.value && depthExact.coefficientDepth == depth.coefficient)
            if depth.coefficient > 0 {
                var depthLimited = try ledger(valueDepth: depth.value, coefficientDepth: depth.coefficient - 1)
                do { try owner.admitProof(limits: limits(), using: &depthLimited); throw Failure(line: #line) }
                catch let error as ExactScalarFailure {
                    guard case .resourceLimit(.coefficientDepth) = error else { throw error }
                } catch let error as OriginalSourceIssuanceFailure {
                    guard case .scalar(.resourceLimit(.coefficientDepth)) = error else { throw error }
                }
            }
            try sourceFailure(.sourceDepthLimit) { try owner.admitProof(limits: limits(sourceDepth: 0), using: &a) }
            print("PASS retained proof readmission exact N/N-1 work/storage/coefficient depth and sourceDepth1/0 without decomposition or solving")
        } else if group == "cancel-entry" {
            withUnsafeCurrentTask { $0?.cancel() }
            let counter = Counter()
            do { _ = try admitted(curve, plane, options, counter); throw Failure(line: #line) }
            catch is CancellationError {}
            try require(counter.totals.work == 0 && counter.totals.bytes == 0)
            print("PASS entry cancellation before any exact work or storage")
        } else if group == "cancel-final" {
            let baseline = Counter()
            _ = try admitted(curve, plane, options, baseline)
            let counter = Counter(cancelStorageAt: baseline.totals.bytes)
            do { _ = try admitted(curve, plane, options, counter); throw Failure(line: #line) }
            catch is CancellationError {}
            try require(counter.totals.bytes == baseline.totals.bytes)
            print("PASS cancellation at final empty publication storage checkpoint")
        } else if group == "cancel-reader" {
            let owner = try query(options).originalImplicitHostPlaneExclusion!.original
            var a = ExactScalarLedger(limits: try .init(work: 8_388_608, storageBytes: 268_435_456,
                valueDepth: 32, coefficientDepth: 32))
            a.cancel()
            do { try owner.admitProof(limits: limits(), using: &a); throw Failure(line: #line) }
            catch let error as ExactScalarFailure { guard case .cancelled = error else { throw error } }
            try require(a.work == 0 && a.storageBytes == 0)
            print("PASS subsequent independent proof-query cancellation without partial success")
        } else if group == "lifetime" {
            let retained: CurveSurfaceIntersectionResult
            do {
                var (localCurve, localPlane, localOptions) = try input()
                retained = try admitted(localCurve, localPlane, localOptions, Counter())
                guard case .implicit(let original) = localCurve,
                    case .bSpline(let native) = original.secondSurface else { throw Failure(line: #line) }
                var changed = native
                changed.controlPoints[0][0].z = 7
                changed.weights[0][0] = 3
                try require(native.controlPoints[0][0].z == 0 && native.weights[0][0] == 1)
                try require(changed.controlPoints[0][0].z == 7 && changed.weights[0][0] == 3)
                localCurve = .circle(.init(center: .origin, normal: .unitZ, radius: 7))
                localPlane = .analytic(.plane(origin: .origin, normal: .unitX))
                localOptions.curveRange = try .init(lower: 0, upper: 0)
                if case .circle(let changed) = localCurve { try require(changed.radius == 7) }
                try require(localPlane != plane)
            }
            let copied = retained
            try verify(copied, options: options)
            try await withThrowingTaskGroup(of: Void.self) { tasks in
                for _ in 0..<2 { tasks.addTask { try verify(retained, options: options) } }
                try await tasks.waitForAll()
            }
            print("PASS detached input/source lifetime, COW value independence and concurrent immutable readers")
        } else { throw Failure(line: #line) }
    }
    static func main() async {
        do { try await run() }
        catch {
            print("FAIL closed implicit complete-empty acceptance")
#if !hasFeature(Embedded)
            print(error)
#endif
            exit(1)
        }
    }
}
