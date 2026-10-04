import CADCore
import Foundation
import Testing

@testable import CADGeometry

@Suite("Certified Implicit Intersection Curve")
struct CertifiedImplicitIntersectionCurveTests {
  private let tolerance = ModelingTolerance.standard

  @Test func lowerOrderEvaluationRetainsNonlinearImplicitDerivatives() throws {
    let first = Surface3D.bSpline(horizontalSurface())
    let second = Surface3D.bSpline(BSplineSurface3D(uDegree: 3, vDegree: 1,
      uKnots: [0, 0, 0, 0, 1, 1, 1, 1], vKnots: [0, 0, 1, 1],
      controlPoints: [-0.5, 0.5].map { z in
        [Point3D(x: 0, y: 0, z: z), Point3D(x: 0, y: 1.0 / 3, z: z),
         Point3D(x: 0, y: 2.0 / 3, z: z), Point3D(x: 1, y: 1, z: z)]
      }, weights: [[1, 1, 1, 1], [1, 1, 1, 1]]))
    func anchor(_ t: Double) throws -> SurfaceIntersectionParameterPair {
      try .init(first: .init(u: t * t * t, v: t), second: .init(u: t, v: 0.5))
    }
    let cell = try CertifiedImplicitIntersectionGraphCell(
      parameterBox: .init(firstU: ScalarInterval(lower: 0, upper: 1),
        firstV: ScalarInterval(lower: 0.4, upper: 0.6),
        secondU: ScalarInterval(lower: 0.35, upper: 0.65), secondV: ScalarInterval(lower: 0, upper: 1)),
      freeParameter: .firstV, direction: .forward,
      lowerAnchor: anchor(0.4), midpointAnchor: anchor(0.5), upperAnchor: anchor(0.6),
      firstSurface: first, secondSurface: second, tolerance: tolerance)
    let implicit = try CertifiedImplicitIntersectionCurve(firstSurface: first, secondSurface: second,
      cells: [cell], isClosed: false, tolerance: tolerance)
    for fraction in [0.0, 0.17, 0.63, 1.0] {
      let t = 0.4 + 0.2 * fraction
      let lower = try Curve3D.implicit(implicit).differentialGeometry(at: fraction, tolerance: tolerance)
      let full = try implicit.differential(atNormalizedFraction: fraction, tolerance: tolerance)
      #expect((lower.position - Point3D(x: t * t * t, y: t, z: 0)).length <= tolerance.distance)
      #expect((lower.firstDerivative - Vector3D(x: 0.6 * t * t, y: 0.2, z: 0)).length <= tolerance.relative)
      #expect((lower.secondDerivative - Vector3D(x: 0.24 * t, y: 0, z: 0)).length <= tolerance.relative)
      #expect((lower.firstDerivative - full.firstDerivative).length <= tolerance.relative)
      #expect((lower.secondDerivative - full.secondDerivative).length <= tolerance.relative)
      #expect(abs(full.thirdDerivative.x - 0.048) <= tolerance.relative)
    }
  }

  @Test(.timeLimit(.minutes(1)))
  func dyadicPlaneParabolaCertificateHasIndependentNativeRootAuthority() throws {
    let curve = try dyadicPlaneParabolaCurve()
    for fraction in [0.0, 0.25, 0.5, 0.75, 1.0] {
      let t = 0.25 + 0.5 * fraction
      let pair = try curve.parameterPair(atNormalizedFraction: fraction, tolerance: tolerance)
      #expect(abs(pair.first.u - t*t) <= tolerance.relative)
      #expect(abs(pair.first.v - t) <= tolerance.relative)
      #expect(abs(pair.second.u - t) <= tolerance.relative)
      #expect(abs(pair.second.v - 0.5) <= tolerance.relative)
      let differential = try curve.differential(atNormalizedFraction: fraction, tolerance: tolerance)
      #expect((differential.position-Point3D(x:t*t/32,y:t/64,z:0)).length <= tolerance.distance)
      #expect((differential.firstDerivative-Vector3D(x:t/32,y:1.0/128,z:0)).length <= tolerance.relative)
      #expect((differential.secondDerivative-Vector3D(x:1.0/64,y:0,z:0)).length <= tolerance.relative)
      #expect(differential.thirdDerivative.length <= tolerance.relative)
    }
  }

  @Test(.timeLimit(.minutes(1)), arguments:[false,true])
  func originalTwoCellClosedJetsAndRootRestrictionPreserveGlobalFractionPowers(_ backwards: Bool) throws {
    let curve = try dyadicPlaneParabolaCurve(direction:backwards ? .reversed : .forward,split:true)
    let prepared = try ImplicitCurveIntervalJetEncloser(intersection:curve,tolerance:tolerance)
    var remaining = SurfaceSurfaceIntersectionOptions().maximumSubdivisionCells
    for index in curve.cells.indices {
      let parent = try continuedRootParameterJet(prepared,of:curve,over:ScalarInterval(lower:0,upper:1),
        cellIndex:index,remainingWork:&remaining)
      for local in [0.0,0.25,0.5,0.75,1] {
        let point = try ScalarInterval(lower:local,upper:local)
        let result = try continuedRootParameterJet(prepared,of:curve,over:point,cellIndex:index,
          restricting:parent.state,remainingWork:&remaining)
        let global = (Double(index)+local)/2
        let t = backwards ? 0.75-0.5*global : 0.25+0.5*global
        let h = backwards ? -0.5 : 0.5
        let expected: [[Double]] = [[t*t,2*t*h,2*h*h,0],[t,h,0,0],[t,h,0,0],[0.5,0,0,0]]
        for (coordinate,values) in zip(result.jet.coordinates,expected) {
          for (field,value) in zip([coordinate.value,coordinate.firstDerivative,
            coordinate.secondDerivative,coordinate.thirdDerivative],values) { #expect(field.contains(value)) }
          #expect(coordinate.value.width <= Double.ulpOfOne*64)
        }
      }
      do {
        _ = try prepared.prepareParameterEnclosure(restricting:parent.state,cellIndex:1-index,
          overClosedInterval:ScalarInterval(lower:0.5,upper:0.5),tolerance:tolerance)
        Issue.record("An original root state changed its owning graph cell.")
      } catch let error as KernelError { #expect(error.code == .invalidInput) }
    }
    #expect(remaining < SurfaceSurfaceIntersectionOptions().maximumSubdivisionCells-4)
  }

  @Test(.timeLimit(.minutes(1)))
  func rationalSingleCellConstructorRetainsIndependentNonpolynomialRootAuthority() throws {
    let curve = try rationalPlaneParabolaCurve()
    guard case .bSpline(let rational) = curve.secondSurface else {
      Issue.record("The original second support must retain its rational control net.")
      return
    }
    #expect(rational.weights == [[4,2,1],[4,2,1]])
    for fraction in [0.0,0.25,0.5,0.75,1] {
      let t = 3.0/8+fraction/4
      let s = 2*t/(1+t)
      let pair = try curve.parameterPair(atNormalizedFraction:fraction,tolerance:tolerance)
      #expect(abs(pair.first.u-t*t) <= tolerance.relative)
      #expect(abs(pair.first.v-t) <= tolerance.relative)
      #expect(abs(pair.second.u-s) <= tolerance.relative)
      #expect(abs(pair.second.v-0.5) <= tolerance.relative)
      let jet = try curve.secondSurface.taylorJet(u:s,v:0.5,throughOrder:3,tolerance:tolerance)
      #expect(abs(jet.value.y-s/(2-s)/64) <= tolerance.relative)
      // Nonzero third native Y derivative proves these unequal weights do
      // not merely degree-elevate the earlier polynomial parameter chart.
      let third = jet.derivative(uOrder:3,vOrder:0).y
      #expect(abs(third-12/(64*pow(2-s,4))) <= tolerance.relative)
      #expect(third > 0)
    }
  }

  @Test(.timeLimit(.minutes(1)), arguments:[false,true])
  func rationalClosedAndRangeJetsRetainBothOriginalRolesThroughThirdOrder(_ backwards: Bool) throws {
    let curve = try rationalPlaneParabolaCurve(direction:backwards ? .reversed : .forward)
    let prepared = try ImplicitCurveIntervalJetEncloser(intersection:curve,tolerance:tolerance)
    var remainingWork = SurfaceSurfaceIntersectionOptions().maximumSubdivisionCells
    let points = try [0.0,0.25,0.5,0.75,1].map { try ScalarInterval(lower:$0,upper:$0) }
    let ranges = [try ScalarInterval(lower:0.25,upper:0.75),
                  try ScalarInterval(lower:0.5,upper:0.5+Double(sign:.plus,exponent:-20,significand:1))]
    for interval in points+ranges {
      let actual = try continuedParameterJet(prepared,of:curve,over:interval,remainingWork:&remainingWork)
      for fraction in [interval.lower,interval.midpoint,interval.upper] {
        let t = backwards ? 5.0/8-fraction/4 : 3.0/8+fraction/4
        let h = backwards ? -0.25 : 0.25
        let denominator = 1+t
        let expected: [[Double]] = [[t*t,2*t*h,2*h*h,0],[t,h,0,0],
          [2*t/denominator,2*h/pow(denominator,2),-4*h*h/pow(denominator,3),12*h*h*h/pow(denominator,4)],
          [0.5,0,0,0]]
        for (index,pair) in zip(actual.coordinates,expected).enumerated() {
          let (coordinate,values) = pair
          for (field,value) in zip([coordinate.value,coordinate.firstDerivative,
            coordinate.secondDerivative,coordinate.thirdDerivative],values) {
            #expect(field.contains(value))
            if interval.width == 0 { #expect(field.width <= tolerance.relative) }
          }
          if interval.width == 0 {
            #expect(coordinate.value.width <= Double.ulpOfOne*64)
          }
        }
      }
      let lower = backwards ? 5.0/8-interval.upper/4 : 3.0/8+interval.lower/4
      let upper = backwards ? 5.0/8-interval.lower/4 : 3.0/8+interval.upper/4
      #expect(actual[.firstU].value.width <= upper*upper-lower*lower+tolerance.relative)
      #expect(actual[.secondU].value.width <= 2*upper/(1+upper)-2*lower/(1+lower)+tolerance.relative)
    }
  }

  @Test(.timeLimit(.minutes(1)))
  func rationalContinuationPreservesOneCallerWorkAndForeignOwnerContract() throws {
    let curve = try rationalPlaneParabolaCurve()
    let prepared = try ImplicitCurveIntervalJetEncloser(intersection:curve,tolerance:tolerance)
    let interval = try ScalarInterval(lower:0.25,upper:0.75)
    var remaining = SurfaceSurfaceIntersectionOptions().maximumSubdivisionCells
    _ = try continuedParameterJet(prepared,of:curve,over:interval,remainingWork:&remaining)
    let used = SurfaceSurfaceIntersectionOptions().maximumSubdivisionCells-remaining
    #expect(used > 1)
    var exactBudget = used
    _ = try continuedParameterJet(prepared,of:curve,over:interval,remainingWork:&exactBudget)
    #expect(exactBudget == 0)
    do {
      _ = try continuedParameterJet(prepared,of:curve,over:interval,remainingWork:&exactBudget)
      Issue.record("Rational continuation cannot reset exhausted caller work.")
    } catch let error as KernelError { #expect(error.code == .resourceLimitExceeded) }
    let state = try prepared.prepareParameterEnclosure(of:curve,cellIndex:0,
      overClosedInterval:interval,tolerance:tolerance)
    let other = try ImplicitCurveIntervalJetEncloser(intersection:dyadicPlaneParabolaCurve(),tolerance:tolerance)
    do {
      _ = try other.advanceParameterEnclosure(state,tolerance:tolerance)
      Issue.record("A rational root state cannot transfer its source authority.")
    } catch let error as KernelError { #expect(error.code == .invalidInput) }
  }

  @Test(.timeLimit(.minutes(1)), arguments:[false,true])
  func originalWholeRootCoverRestrictsClosedRationalChildrenWithMeasuredWork(_ backwards: Bool) throws {
    let curve = try rationalPlaneParabolaCurve(direction:backwards ? .reversed : .forward)
    let prepared = try ImplicitCurveIntervalJetEncloser(intersection:curve,tolerance:tolerance)
    var remaining = SurfaceSurfaceIntersectionOptions().maximumSubdivisionCells
    let parent = try continuedRootParameterJet(prepared,of:curve,
      over:ScalarInterval(lower:0,upper:1),remainingWork:&remaining)
    var directWork = 0, restrictedWork = 0
    for fraction in [0.25,0.5,0.75] {
      let interval = try ScalarInterval(lower:fraction,upper:fraction)
      let beforeDirect = remaining
      let direct = try continuedRootParameterJet(prepared,of:curve,over:interval,remainingWork:&remaining)
      directWork += beforeDirect-remaining
      let beforeRestricted = remaining
      let restricted = try continuedRootParameterJet(prepared,of:curve,over:interval,
        restricting:parent.state,remainingWork:&remaining)
      restrictedWork += beforeRestricted-remaining
      let t = backwards ? 5.0/8-fraction/4 : 3.0/8+fraction/4
      let h = backwards ? -0.25 : 0.25, d = 1+t
      let expected: [[Double]] = [[t*t,2*t*h,2*h*h,0],[t,h,0,0],
        [2*t/d,2*h/pow(d,2),-4*h*h/pow(d,3),12*h*h*h/pow(d,4)],[0.5,0,0,0]]
      for jet in [direct.jet,restricted.jet] {
        for (coordinate,values) in zip(jet.coordinates,expected) {
          for (field,value) in zip([coordinate.value,coordinate.firstDerivative,
            coordinate.secondDerivative,coordinate.thirdDerivative],values) {
            #expect(field.contains(value))
          }
          #expect(coordinate.value.width <= Double.ulpOfOne*64)
        }
      }
    }
    // This is an actual lower prepare/advance count, not a timing prediction.
    #expect(restrictedWork < directWork)
    #expect(restrictedWork > 3)
  }

  @Test(.timeLimit(.minutes(1)))
  func originalRootRestrictionPreservesSourceDomainToleranceAndCallerFailures() throws {
    let curve = try rationalPlaneParabolaCurve()
    let prepared = try ImplicitCurveIntervalJetEncloser(intersection:curve,tolerance:tolerance)
    var remaining = SurfaceSurfaceIntersectionOptions().maximumSubdivisionCells
    let range = try ScalarInterval(lower:0.25,upper:0.75)
    let parent = try continuedRootParameterJet(prepared,of:curve,over:range,remainingWork:&remaining)
    let point = try ScalarInterval(lower:0.5,upper:0.5)
    let foreign = try ImplicitCurveIntervalJetEncloser(intersection:dyadicPlaneParabolaCurve(),tolerance:tolerance)
    let different = ModelingTolerance(distance:tolerance.distance*2,angle:tolerance.angle,relative:tolerance.relative)
    let otherPreparation = try ImplicitCurveIntervalJetEncloser(intersection:curve,tolerance:different)
    for mismatch in 0..<4 {
      do {
        let owner = mismatch == 0 ? foreign : mismatch == 1 ? otherPreparation : prepared
        _ = try owner.prepareParameterEnclosure(restricting:parent.state,
          overClosedInterval:mismatch == 2 ? ScalarInterval(lower:0,upper:0.5) : point,
          tolerance:mismatch == 3 ? different : tolerance)
        Issue.record("A restricted root state accepted foreign source, preparation, domain or tolerance authority.")
      } catch let error as KernelError { #expect(error.code == .invalidInput) }
    }
    // An uncontracted original range also covers every certified root. This
    // entry must never reinterpret an endpoint subset as a whole range box.
    guard remaining > 0 else {
      throw KernelError(phase:.geometry,code:.resourceLimitExceeded,tolerance:tolerance,
        message:"Original range preparation exhausted the shared caller work.")
    }
    remaining -= 1
    let initial = try prepared.prepareParameterEnclosure(of:curve,cellIndex:0,
      overClosedInterval:range,tolerance:tolerance)
    let fromInitial = try continuedRootParameterJet(prepared,of:curve,over:point,
      restricting:initial,remainingWork:&remaining)
    #expect(fromInitial.jet[.firstU].value.contains(0.25))
    #expect(fromInitial.jet[.secondU].value.contains(2.0/3))
    var preparationOnly = 1
    do {
      _ = try continuedRootParameterJet(prepared,of:curve,over:point,
        restricting:parent.state,remainingWork:&preparationOnly)
      Issue.record("Restricted root contraction bypassed the exhausted shared caller work.")
    } catch let error as KernelError { #expect(error.code == .resourceLimitExceeded) }
  }

  @Test(.timeLimit(.minutes(1)))
  func originalRootRestrictionCancellationRetainsItsCheckedBoundary() async throws {
    let curve = try rationalPlaneParabolaCurve()
    let prepared = try ImplicitCurveIntervalJetEncloser(intersection:curve,tolerance:tolerance)
    var remaining = SurfaceSurfaceIntersectionOptions().maximumSubdivisionCells
    let parent = try continuedRootParameterJet(prepared,of:curve,
      over:ScalarInterval(lower:0,upper:1),remainingWork:&remaining)
    let task = Task {
      while !Task.isCancelled { await Task.yield() }
      return try prepared.prepareParameterEnclosure(restricting:parent.state,
        overClosedInterval:ScalarInterval(lower:0.5,upper:0.5),tolerance:tolerance)
    }
    task.cancel()
    do { _ = try await task.value; Issue.record("Original restricted preparation hid cancellation.") }
    catch let error as KernelError { #expect(error.code == .cancelled) }
  }

  @Test(.timeLimit(.minutes(1)))
  func rationalContinuationCancellationRemainsExplicit() async throws {
    let curve = try rationalPlaneParabolaCurve()
    let prepared = try ImplicitCurveIntervalJetEncloser(intersection:curve,tolerance:tolerance)
    let task = Task {
      while !Task.isCancelled { await Task.yield() }
      return try prepared.prepareParameterEnclosure(of:curve,cellIndex:0,
        overClosedInterval:ScalarInterval(lower:0,upper:1),tolerance:tolerance)
    }
    task.cancel()
    do { _ = try await task.value; Issue.record("Rational continuation cannot hide cancellation.") }
    catch let error as KernelError { #expect(error.code == .cancelled) }
  }

  private func rationalPlaneParabolaCurve(direction: CertifiedImplicitIntersectionDirection = .forward)
    throws -> CertifiedImplicitIntersectionCurve {
    let first = BSplineSurface3D(uDegree:1,vDegree:1,
      uKnots:[-0.5,-0.5,1.5,1.5],vKnots:[0,0,1,1],
      controlPoints:[0.0,1.0/64].map { y in
        [Point3D(x:-1.0/64,y:y,z:0),Point3D(x:3.0/64,y:y,z:0)] })
    // W=(2-s)^2, X=s^2/32, Y=s(2-s)/64 in homogeneous coordinates.
    // The original chart S2=(s^2/(2-s)^2/32,s/(2-s)/64,(2r-1)/64)
    // has genuinely rational native derivatives and unequal positive weights.
    let second = BSplineSurface3D(uDegree:2,vDegree:1,
      uKnots:[0,0,0,1,1,1],vKnots:[0,0,1,1],
      controlPoints:[-1.0/64,1.0/64].map { z in
        [Point3D(x:0,y:0,z:z),Point3D(x:0,y:1.0/128,z:z),Point3D(x:1.0/32,y:1.0/64,z:z)] },
      weights:[[4,2,1],[4,2,1]])
    func anchor(_ t: Double) throws -> SurfaceIntersectionParameterPair {
      try SurfaceIntersectionParameterPair(first:SurfaceParameter(u:t*t,v:t),
        second:SurfaceParameter(u:2*t/(1+t),v:0.5))
    }
    let cell = try CertifiedImplicitIntersectionGraphCell(parameterBox:SurfaceIntersectionParameterBox(
      firstU:ScalarInterval(lower:-1.0/8,upper:1.0/2),firstV:ScalarInterval(lower:3.0/8,upper:5.0/8),
      secondU:ScalarInterval(lower:1.0/2,upper:13.0/16),secondV:ScalarInterval(lower:0,upper:1)),
      freeParameter:.firstV,direction:direction,lowerAnchor:anchor(3.0/8),
      midpointAnchor:anchor(1.0/2),upperAnchor:anchor(5.0/8),
      firstSurface:first,secondSurface:second,tolerance:tolerance)
    return try CertifiedImplicitIntersectionCurve(firstSurface:first,secondSurface:second,
      cells:[cell],isClosed:false,tolerance:tolerance)
  }

  @Test(.timeLimit(.minutes(1)))
  func subnormalNativeSurfacePointRetainsOutwardValueAndDerivativeContainment() throws {
    let patch = RationalBezierSurfacePatch3D(
      controlPoints: [[Point3D(x: 0, y: 0, z: 0), Point3D(x: 1, y: 0, z: 0)],
        [Point3D(x: 0, y: 1, z: 0), Point3D(x: 1, y: 1, z: 0)]],
      weights: [[1, 1], [1, 1]], uLower: 0, uUpper: 1, vLower: 0, vUpper: 1)
    let encloser = RationalBezierSurfaceJetEncloser()
    let prepared = try encloser.prepare(patch, tolerance: tolerance)
    for u in [Double.leastNonzeroMagnitude, Double.leastNormalMagnitude / 8] {
      let jet = try encloser.pointEnclosure(of: prepared, u: u, v: 0.5, tolerance: tolerance)
      let expected: [[Double]] = [[u, 1, 0, 0, 0, 0, 0, 0, 0, 0],
        [0.5, 0, 1, 0, 0, 0, 0, 0, 0, 0], [0, 0, 0, 0, 0, 0, 0, 0, 0, 0]]
      for (coordinate, values) in zip([jet.x, jet.y, jet.z], expected) {
        for (field, value) in zip([coordinate.value, coordinate.derivativeU, coordinate.derivativeV,
          coordinate.secondDerivativeUU, coordinate.secondDerivativeUV, coordinate.secondDerivativeVV,
          coordinate.thirdDerivativeUUU, coordinate.thirdDerivativeUUV, coordinate.thirdDerivativeUVV,
          coordinate.thirdDerivativeVVV], values) {
          #expect(field.isFinite && field.contains(value))
        }
      }
    }
  }

  @Test(.timeLimit(.minutes(1)))
  func dyadicPlaneParabolaClosedPointJetsContainNativeValuesAndThreeDerivatives() throws {
    let curve = try dyadicPlaneParabolaCurve()
    let prepared = try ImplicitCurveIntervalJetEncloser(intersection:curve,tolerance:tolerance)
    var remainingWork = SurfaceSurfaceIntersectionOptions().maximumSubdivisionCells
    for fraction in [0.0,0.5,1.0] {
      let t = 0.25+0.5*fraction
      let actual = try continuedParameterJet(prepared,of:curve,
        over:ScalarInterval(lower:fraction,upper:fraction),remainingWork:&remainingWork)
      let expected: [[Double]] = [[t*t,t,0.5,0],[t,0.5,0,0],[t,0.5,0,0],[0.5,0,0,0]]
      for (coordinate,values) in zip(actual.coordinates,expected) {
        for (field,value) in zip([coordinate.value,coordinate.firstDerivative,
                                  coordinate.secondDerivative,coordinate.thirdDerivative],values) {
          #expect(field.contains(value))
          #expect(field.width <= tolerance.relative)
        }
      }
    }
  }

  @Test(.timeLimit(.minutes(1)), arguments: [false, true])
  func originalClosedEndpointsRetainExactNativeFreeCoordinates(_ backwards: Bool) throws {
    let curve = try dyadicPlaneParabolaCurve(direction: backwards ? .reversed : .forward)
    let prepared = try ImplicitCurveIntervalJetEncloser(intersection: curve, tolerance: tolerance)
    var remaining = SurfaceSurfaceIntersectionOptions().maximumSubdivisionCells
    for fraction in [0.0, 1.0] {
      let t = backwards ? 0.75 - 0.5 * fraction : 0.25 + 0.5 * fraction
      let jet = try continuedParameterJet(prepared, of: curve,
        over: ScalarInterval(lower: fraction, upper: fraction), remainingWork: &remaining)
      #expect(jet.coordinates[1].value.lower == t && jet.coordinates[1].value.upper == t)
      for (coordinate, value) in zip(jet.coordinates, [t * t, t, t, 0.5]) {
        #expect(coordinate.value.contains(value))
        #expect(coordinate.value.width <= Double.ulpOfOne * 64)
      }
    }
  }

  @Test(.timeLimit(.minutes(1)), arguments: [false, true])
  func dyadicPartialEndpointJetsMeetConnectionRoundingAndNativeDerivatives(_ backwards: Bool) throws {
    let curve = try dyadicPlaneParabolaCurve(direction: backwards ? .reversed : .forward)
    let prepared = try ImplicitCurveIntervalJetEncloser(intersection: curve, tolerance: tolerance)
    var remainingWork = SurfaceSurfaceIntersectionOptions().maximumSubdivisionCells
    for fraction in [0.25, 0.75] {
      let t = backwards ? 0.75 - 0.5*fraction : 0.25 + 0.5*fraction
      let sign = backwards ? -1.0 : 1.0
      let actual = try continuedParameterJet(prepared, of: curve,
        over: ScalarInterval(lower: fraction, upper: fraction), remainingWork: &remainingWork)
      let expected: [[Double]] = [[t*t, sign*t, 0.5, 0], [t, sign*0.5, 0, 0],
        [t, sign*0.5, 0, 0], [0.5, 0, 0, 0]]
      for (coordinate, values) in zip(actual.coordinates, expected) {
        let rounding = Double.ulpOfOne * max(1, abs(values[0])) * 64
        #expect(coordinate.value.width <= rounding)
        for (field, value) in zip([coordinate.value, coordinate.firstDerivative,
          coordinate.secondDerivative, coordinate.thirdDerivative], values) {
          #expect(field.contains(value))
          #expect(field.width <= tolerance.relative)
        }
      }
    }
  }

  @Test(.timeLimit(.minutes(1)))
  func dyadicPlaneParabolaIntervalJetsLocalizeOriginalRootAndDerivativeRanges() throws {
    let curve = try dyadicPlaneParabolaCurve()
    let prepared = try ImplicitCurveIntervalJetEncloser(intersection:curve,tolerance:tolerance)
    var remainingWork = SurfaceSurfaceIntersectionOptions().maximumSubdivisionCells
    for width in [0.25,Double(sign:.plus,exponent:-20,significand:1)] {
      let interval = try ScalarInterval(lower:0.375,upper:0.375+width)
      let lower = 0.25+0.5*interval.lower,upper = 0.25+0.5*interval.upper
      let actual = try continuedParameterJet(prepared,of:curve,over:interval,remainingWork:&remainingWork)
      let u = actual[.firstU],v = actual[.firstV]
      #expect(u.value.contains(lower*lower) && u.value.contains(upper*upper))
      #expect(u.value.width <= upper*upper-lower*lower+tolerance.relative)
      #expect(u.firstDerivative.contains(lower) && u.firstDerivative.contains(upper))
      #expect(u.firstDerivative.width <= upper-lower+tolerance.relative)
      #expect(u.secondDerivative.contains(0.5) && u.secondDerivative.width <= tolerance.relative)
      #expect(u.thirdDerivative.contains(0) && u.thirdDerivative.width <= tolerance.relative)
      #expect(v.value.contains(lower) && v.value.contains(upper))
      #expect(v.value.width <= upper-lower+tolerance.relative)
      for fraction in [interval.lower,interval.midpoint,interval.upper] {
        let t = 0.25+0.5*fraction
        #expect(u.value.contains(t*t) && u.firstDerivative.contains(t))
        #expect(actual[.secondU].value.contains(t))
        #expect(actual[.secondV].value.contains(0.5))
      }
    }
  }

  @Test(.timeLimit(.minutes(1)))
  func reversedClosedImplicitJetsApplyNativeDirectionAndPowersOnce() throws {
    let curve = try dyadicPlaneParabolaCurve(direction: .reversed)
    let prepared = try ImplicitCurveIntervalJetEncloser(intersection: curve, tolerance: tolerance)
    var remainingWork = SurfaceSurfaceIntersectionOptions().maximumSubdivisionCells
    for fraction in [0.0, 0.5, 1.0] {
      let t = 0.75 - 0.5 * fraction
      let actual = try continuedParameterJet(prepared, of: curve,
        over: ScalarInterval(lower: fraction, upper: fraction), remainingWork: &remainingWork)
      let expected: [[Double]] = [[t*t, -t, 0.5, 0], [t, -0.5, 0, 0],
        [t, -0.5, 0, 0], [0.5, 0, 0, 0]]
      for (coordinate, values) in zip(actual.coordinates, expected) {
        for (field, value) in zip([coordinate.value, coordinate.firstDerivative,
          coordinate.secondDerivative, coordinate.thirdDerivative], values) {
          #expect(field.contains(value))
          #expect(field.width <= tolerance.relative)
        }
      }
    }
  }

  @Test(.timeLimit(.minutes(1)))
  func reversedMonotoneEndpointPhasesRetainWholeOriginalRangeJets() throws {
    let curve = try dyadicPlaneParabolaCurve(direction: .reversed)
    let prepared = try ImplicitCurveIntervalJetEncloser(intersection: curve, tolerance: tolerance)
    var remainingWork = SurfaceSurfaceIntersectionOptions().maximumSubdivisionCells
    let actual = try continuedParameterJet(prepared, of: curve,
      over: ScalarInterval(lower: 0.375, upper: 0.625), remainingWork: &remainingWork)
    let lower = 0.4375, upper = 0.5625
    let u = actual[.firstU]
    #expect(u.value.contains(lower * lower) && u.value.contains(upper * upper))
    #expect(u.value.width <= upper * upper - lower * lower + tolerance.relative)
    #expect(u.firstDerivative.contains(-upper) && u.firstDerivative.contains(-lower))
    #expect(u.firstDerivative.width <= upper - lower + tolerance.relative)
    #expect(u.secondDerivative.contains(0.5) && u.secondDerivative.width <= tolerance.relative)
    #expect(u.thirdDerivative.contains(0) && u.thirdDerivative.width <= tolerance.relative)
    #expect(actual[.firstV].value.contains(lower) && actual[.firstV].value.contains(upper))
    #expect(actual[.secondU].value.contains(lower) && actual[.secondU].value.contains(upper))
    #expect(actual[.secondV].value.contains(0.5))
    #expect(actual[.firstV].firstDerivative.contains(-0.5))
    #expect(actual[.secondU].firstDerivative.contains(-0.5))
  }

  @Test(.timeLimit(.minutes(1)))
  func closedImplicitContinuationKeepsForeignStateAndInputFailuresTyped() throws {
    let curve = try dyadicPlaneParabolaCurve()
    let prepared = try ImplicitCurveIntervalJetEncloser(intersection:curve,tolerance:tolerance)
    let point = try ScalarInterval(lower:0.5,upper:0.5)
    let state = try prepared.prepareParameterEnclosure(of:curve,cellIndex:0,
      overClosedInterval:point,tolerance:tolerance)
    let otherPreparationTolerance = ModelingTolerance(distance:tolerance.distance*2,
      angle:tolerance.angle,relative:tolerance.relative)
    let otherPreparation = try ImplicitCurveIntervalJetEncloser(intersection:curve,
      tolerance:otherPreparationTolerance)
    do {
      _ = try otherPreparation.advanceParameterEnclosure(state,tolerance:tolerance)
      Issue.record("A continuation cannot borrow another preparation tolerance for the same source.")
    } catch let error as KernelError { #expect(error.code == .invalidInput) }
    let line = try certifiedLineCurve()
    let foreign = try ImplicitCurveIntervalJetEncloser(intersection:line,tolerance:tolerance)
    do {
      _ = try foreign.advanceParameterEnclosure(state,tolerance:tolerance)
      Issue.record("A localization state cannot transfer its original root authority.")
    } catch let error as KernelError { #expect(error.code == .invalidInput) }
    for (index,interval) in [(1,point),(0,try ScalarInterval(lower:-0.1,upper:0.1))] {
      do {
        _ = try prepared.prepareParameterEnclosure(of:curve,cellIndex:index,
          overClosedInterval:interval,tolerance:tolerance)
        Issue.record("Closed localization cannot clamp a foreign cell or invalid original fraction.")
      } catch let error as KernelError { #expect(error.code == .invalidInput) }
    }
    do {
      _ = try prepared.advanceParameterEnclosure(state,
        tolerance:ModelingTolerance(distance:tolerance.distance*2,angle:tolerance.angle,relative:tolerance.relative))
      Issue.record("A root-state continuation must retain the original preparation tolerance.")
    } catch let error as KernelError { #expect(error.code == .invalidInput) }
    do {
      _ = try prepared.prepareParameterEnclosure(of: curve, cellIndex: 0,
        overClosedInterval: point,
        tolerance: ModelingTolerance(distance: tolerance.distance*2, angle: tolerance.angle, relative: tolerance.relative))
      Issue.record("A root-state preparation must retain its prepared source tolerance.")
    } catch let error as KernelError { #expect(error.code == .invalidInput) }
  }

  @Test(.timeLimit(.minutes(1)))
  func closedImplicitContinuationConsumesOneCallerBudgetAcrossRequests() throws {
    let curve = try dyadicPlaneParabolaCurve()
    let prepared = try ImplicitCurveIntervalJetEncloser(intersection:curve,tolerance:tolerance)
    let range = try ScalarInterval(lower:0.375,upper:0.625)
    var remainingWork = SurfaceSurfaceIntersectionOptions().maximumSubdivisionCells
    _ = try continuedParameterJet(prepared,of:curve,over:range,remainingWork:&remainingWork)
    let consumed = SurfaceSurfaceIntersectionOptions().maximumSubdivisionCells-remainingWork
    #expect(consumed > 1)
    var exactlyOneRequest = consumed
    _ = try continuedParameterJet(prepared,of:curve,over:range,remainingWork:&exactlyOneRequest)
    #expect(exactlyOneRequest == 0)
    do {
      _ = try continuedParameterJet(prepared,of:curve,over:range,remainingWork:&exactlyOneRequest)
      Issue.record("Another range and endpoint continuation cannot reset a caller-owned work budget.")
    } catch let error as KernelError { #expect(error.code == .resourceLimitExceeded) }
    var preparationOnly = 1
    do {
      _ = try continuedParameterJet(prepared,of:curve,over:ScalarInterval(lower:0.5,upper:0.5),remainingWork:&preparationOnly)
      Issue.record("Root contraction must consume work after preparation.")
    } catch let error as KernelError { #expect(error.code == .resourceLimitExceeded) }
  }

  @Test(.timeLimit(.minutes(1)))
  func closedImplicitContinuationCancellationIsExplicit() async throws {
    let curve = try dyadicPlaneParabolaCurve()
    let prepared = try ImplicitCurveIntervalJetEncloser(intersection:curve,tolerance:tolerance)
    let state = try prepared.prepareParameterEnclosure(of:curve,cellIndex:0,
      overClosedInterval:ScalarInterval(lower:0.5,upper:0.5),tolerance:tolerance)
    let task = Task {
      while !Task.isCancelled { await Task.yield() }
      return try prepared.advanceParameterEnclosure(state,tolerance:tolerance)
    }
    task.cancel()
    do { _ = try await task.value; Issue.record("A cancelled continuation cannot publish a root jet.") }
    catch let error as KernelError { #expect(error.code == .cancelled) }
  }

  private func continuedParameterJet(_ prepared: ImplicitCurveIntervalJetEncloser,
    of curve: CertifiedImplicitIntersectionCurve,over interval: ScalarInterval,
    remainingWork: inout Int) throws -> CertifiedImplicitParameterIntervalJet {
    try continuedRootParameterJet(prepared,of:curve,over:interval,remainingWork:&remainingWork).jet
  }

  private func continuedRootParameterJet(_ prepared: ImplicitCurveIntervalJetEncloser,
    of curve: CertifiedImplicitIntersectionCurve, over interval: ScalarInterval, cellIndex: Int = 0,
    restricting parent: ImplicitCurveIntervalJetEncloser.ParameterEnclosureState? = nil,
    remainingWork: inout Int) throws -> (jet: CertifiedImplicitParameterIntervalJet,
      state: ImplicitCurveIntervalJetEncloser.ParameterEnclosureState) {
    func consume(_ remaining: inout Int) throws {
      guard remaining > 0 else {
        throw KernelError(phase:.geometry,code:.resourceLimitExceeded,tolerance:tolerance,
          message:"The test caller exhausted its existing aggregate work budget.")
      }
      remaining -= 1
    }
    try consume(&remainingWork)
    var state: ImplicitCurveIntervalJetEncloser.ParameterEnclosureState
    if let parent {
      state = try prepared.prepareParameterEnclosure(restricting:parent,cellIndex:cellIndex,
        overClosedInterval:interval,tolerance:tolerance)
    } else {
      state = try prepared.prepareParameterEnclosure(of:curve,cellIndex:cellIndex,
        overClosedInterval:interval,tolerance:tolerance)
    }
    while true {
      try consume(&remainingWork)
      switch try prepared.advanceParameterEnclosure(state,tolerance:tolerance) {
      case .enclosed(let jet): return (jet,state)
      case .contracted(let next): state = next
      case .subdivisionRequired:
        throw KernelError(phase:.geometry,code:.singularSystem,tolerance:tolerance,
          message:"The independent regular fixture unexpectedly required caller subdivision.")
      }
    }
  }

  private func dyadicPlaneParabolaCurve(
    direction: CertifiedImplicitIntersectionDirection = .forward, split: Bool = false
  ) throws -> CertifiedImplicitIntersectionCurve {
    // Exact original controls: S1(u,v)=(u/32,v/64,0),
    // S2(s,r)=(s^2/32,s/64,(2r-1)/64). No fitted chart or sampled certificate.
    let first = BSplineSurface3D(uDegree:1,vDegree:1,
      uKnots:[-0.5,-0.5,1.5,1.5],vKnots:[0,0,1,1],
      controlPoints:[0.0,1.0/64].map { y in
        [Point3D(x:-1.0/64,y:y,z:0),Point3D(x:3.0/64,y:y,z:0)]
      })
    let second = BSplineSurface3D(uDegree:2,vDegree:1,
      uKnots:[0,0,0,1,1,1],vKnots:[0,0,1,1],
      controlPoints:[-1.0/64,1.0/64].map { z in
        [Point3D(x:0,y:0,z:z),Point3D(x:0,y:1.0/128,z:z),Point3D(x:1.0/32,y:1.0/64,z:z)]
      })
    func anchor(_ t: Double) throws -> SurfaceIntersectionParameterPair {
      try SurfaceIntersectionParameterPair(first:SurfaceParameter(u:t*t,v:t),
        second:SurfaceParameter(u:t,v:0.5))
    }
    let ranges: [(Double,Double)] = split ? [(0.25,0.5),(0.5,0.75)] : [(0.25,0.75)]
    let ordered = direction == .forward ? ranges : Array(ranges.reversed())
    let cells = try ordered.map { lower,upper in
      try CertifiedImplicitIntersectionGraphCell(parameterBox:SurfaceIntersectionParameterBox(
        firstU:ScalarInterval(lower:-0.25,upper:0.875),firstV:ScalarInterval(lower:lower,upper:upper),
        secondU:ScalarInterval(lower:0.2,upper:0.8),secondV:ScalarInterval(lower:0,upper:1)),
        freeParameter:.firstV,direction:direction,
        lowerAnchor:anchor(lower),midpointAnchor:anchor((lower+upper)/2),upperAnchor:anchor(upper),
        firstSurface:first,secondSurface:second,tolerance:tolerance)
    }
    return try CertifiedImplicitIntersectionCurve(firstSurface:first,secondSurface:second,
      cells:cells,isClosed:false,tolerance:tolerance)
  }

  @Test func implicitLiftBoundsRespectRequestedSubinterval() throws {
    let intersection = try certifiedLineCurve()
    for role in [SurfaceIntersectionSurfaceRole.first, .second] {
      for (start, end) in [(0.2, 0.8), (0.8, 0.2)] {
        let pcurve = try CertifiedImplicitSurfaceParameterCurve(
          intersection: intersection, role: role,
          startFraction: start, endFraction: end, tolerance: tolerance)
        let lift = SurfaceLiftCurve3D(
          surface: role == .first ? intersection.firstSurface : intersection.secondSurface,
          parameterCurve: .certifiedImplicit(pcurve))
        let jet = try DefaultCurveDifferentialEncloser().thirdOrderIntervalJet(
          of: .surfaceLift(lift), over: ScalarInterval(lower: 0.25, upper: 0.75), tolerance: tolerance)
        #expect(jet.y.derivativeU.lower <= end - start && jet.y.derivativeU.upper >= end - start)
        #expect(jet.y.derivativeU.width < 1e-6)
        #expect(jet.x.derivativeU.absoluteUpperBound < 1e-6)
        #expect(jet.z.thirdDerivativeUUU.absoluteUpperBound < 1e-6)
        for width in [0.01, tolerance.relative * 0.5] {
          let interval = try ScalarInterval(lower: 0.25, upper: 0.25 + width)
          let box = try lift.boundingBox(over: interval, tolerance: tolerance)
          #expect(box.maximum.y - box.minimum.y <= abs(end - start) * width + tolerance.distance * 16)
          for fraction in [interval.lower, interval.midpoint, interval.upper] {
            let point = try lift.point(atNormalizedFraction: fraction, tolerance: tolerance)
            #expect(point.x >= box.minimum.x && point.x <= box.maximum.x)
            #expect(point.y >= box.minimum.y && point.y <= box.maximum.y)
            #expect(point.z >= box.minimum.z && point.z <= box.maximum.z)
          }
        }
      }
    }
  }

  @Test func tinyImplicitIntervalsRetainLocalPositionBounds() throws {
    let curve = try certifiedLineCurve()
    for encloser in [ImplicitCurveIntervalJetEncloser(),
                     try ImplicitCurveIntervalJetEncloser(intersection: curve, tolerance: tolerance)] {
      for lower in [0.0, 0.5, 1.0 - tolerance.relative * 0.5] {
        let interval = try ScalarInterval(lower: lower, upper: min(1, lower + tolerance.relative * 0.5))
        let jet = try encloser.parameterIntervalJet(of: curve, over: interval, tolerance: tolerance)
        let free = jet[.firstV]
        #expect(free.value.contains(interval.lower))
        #expect(free.value.contains(interval.upper))
        #expect(free.value.width < tolerance.relative * 32)
        #expect(free.firstDerivative.contains(1))
        #expect(free.secondDerivative.contains(0))
        #expect(free.thirdDerivative.contains(0))
      }
    }
  }

  @Test func implicitPcurveLiftRetainsTrimmedAndReversedDerivativeBounds() throws {
    let intersection = try certifiedLineCurve()
    for role in [SurfaceIntersectionSurfaceRole.first, .second] {
      for (start, end) in [(0.2, 0.8), (0.8, 0.2)] {
        let pcurve = try CertifiedImplicitSurfaceParameterCurve(
          intersection: intersection, role: role,
          startFraction: start, endFraction: end, tolerance: tolerance)
        let lift = SurfaceLiftCurve3D(
          surface: role == .first ? intersection.firstSurface : intersection.secondSurface,
          parameterCurve: .certifiedImplicit(pcurve))
        let interval = try ScalarInterval(lower: 0.25, upper: 0.75)
        let bounder = SurfaceLiftDifferentialBounder()
        let first = try #require(try bounder.firstDerivativeMagnitude(
          lift: lift, interval: interval, tolerance: tolerance))
        let second = try #require(try bounder.secondDerivativeMagnitude(
          lift: lift, interval: interval, tolerance: tolerance))
        let third = try #require(try bounder.thirdDerivativeMagnitude(
          lift: lift, interval: interval, tolerance: tolerance))
        #expect(first.isFinite && first >= 0.6 && first < 0.61)
        #expect(second.isFinite && second >= 0 && second < 1e-6)
        #expect(third.isFinite && third >= 0 && third < 1e-6)
        let bounds = try #require(try bounder.parameterBounds(.certifiedImplicit(pcurve), tolerance: tolerance))
        for fraction in [0.25, 0.5, 0.75] {
          let uv = try pcurve.parameter(atNormalizedFraction: fraction, tolerance: tolerance)
          #expect(bounds.u.contains(uv.u) && bounds.v.contains(uv.v))
          let actual = try lift.differentialGeometry(atNormalizedFraction: fraction, tolerance: tolerance)
          #expect(actual.firstDerivative.length <= first)
          #expect(actual.secondDerivative.length <= second)
        }
      }
    }
  }

  @Test func planarSupportConnectsMultipleCellsAndRoundTrips() throws {
    let first = Surface3D.bSpline(horizontalSurface())
    let second = Surface3D.plane(Plane3D(
      origin: Point3D(x: 0.5, y: 0, z: 0), normal: .unitX))
    func anchor(_ y: Double) throws -> SurfaceIntersectionParameterPair {
      let p = try second.parameterProjection(
        of: Point3D(x: 0.5, y: y, z: 0), tolerance: tolerance)
      return try SurfaceIntersectionParameterPair(
        first: SurfaceParameter(u: 0.5, v: y),
        second: SurfaceParameter(u: p.u, v: p.v))
    }
    func cell(_ lower: Double, _ upper: Double) throws -> CertifiedImplicitIntersectionGraphCell {
      try CertifiedImplicitIntersectionGraphCell(
        parameterBox: SurfaceIntersectionParameterBox(
          firstU: ScalarInterval(lower: 0, upper: 1),
          firstV: ScalarInterval(lower: lower, upper: upper),
          secondU: ScalarInterval(lower: -2, upper: 2),
          secondV: ScalarInterval(lower: -2, upper: 2)),
        freeParameter: .firstV, direction: .forward,
        lowerAnchor: anchor(lower), midpointAnchor: anchor((lower + upper) / 2),
        upperAnchor: anchor(upper), firstSurface: first, secondSurface: second,
        tolerance: tolerance)
    }
    let lower = try cell(0, 0.5)
    let upper = try cell(0.5, 1)
    let curve = try CertifiedImplicitIntersectionCurve(
      firstSurface: first, secondSurface: second, cells: [lower, upper],
      isClosed: false, tolerance: tolerance)
    let prepared = try ImplicitCurveIntervalJetEncloser(intersection: curve, tolerance: tolerance)
    do {
      _ = try prepared.prepareParameterEnclosure(of: curve, cellIndex: 0,
        overClosedInterval: ScalarInterval(lower: 0, upper: 0.25), tolerance: tolerance)
      Issue.record("A valid multi-cell analytic chart cannot enter the single polynomial-cell localizer.")
    } catch let error as KernelError { #expect(error.code == .unsupportedCapability) }
    let decoded = try JSONDecoder().decode(
      CertifiedImplicitIntersectionCurve.self, from: JSONEncoder().encode(curve))
    #expect(decoded == curve)
    for fraction in [0.0, 0.25, 0.5, 0.75, 1.0] {
      let point = try decoded.point(atNormalizedFraction: fraction, tolerance: tolerance)
      #expect(point.isApproximatelyEqual(to: Point3D(x: 0.5, y: fraction, z: 0),
        tolerance: tolerance.distance))
    }
    let disconnected = try cell(0.6, 1)
    do {
      _ = try CertifiedImplicitIntersectionCurve(
        firstSurface: first, secondSurface: second, cells: [lower, disconnected],
        isClosed: false, tolerance: tolerance)
      Issue.record("Disconnected planar-support graph cells must be rejected.")
    } catch let error as KernelError {
      #expect(error.code == .intersectionFailure)
    }
  }

  @Test(.timeLimit(.minutes(1)))
  func evaluatesTheUniqueRootOfARevalidatedKrawczykGraph() throws {
    let first = horizontalSurface()
    let second = verticalSurface()
    let cell = try graphCell(first: first, second: second)
    let curve = try CertifiedImplicitIntersectionCurve(
      firstSurface: first,
      secondSurface: second,
      cells: [cell],
      isClosed: false,
      tolerance: tolerance
    )
    #expect(curve.maximumResidualUpperBound == tolerance.distance)

    for fraction in [0.0, 0.25, 0.5, 0.75, 1.0] {
      let point = try curve.point(
        atNormalizedFraction: fraction,
        tolerance: tolerance
      )
      let parameters = try curve.parameterPair(
        atNormalizedFraction: fraction,
        tolerance: tolerance
      )
      #expect(abs(point.x - 0.5) <= tolerance.distance)
      #expect(abs(point.y - fraction) <= tolerance.distance)
      #expect(abs(point.z) <= tolerance.distance)
      #expect(abs(parameters.first.u - 0.5) <= tolerance.distance)
      #expect(abs(parameters.first.v - fraction) <= tolerance.distance)
      #expect(abs(parameters.second.u - ((fraction + 1.0) / 3.0)) <= tolerance.distance)
      #expect(abs(parameters.second.v - 0.5) <= tolerance.distance)
    }
  }

  @Test(.timeLimit(.minutes(1)))
  func rejectsACellWhoseClaimedFreeParameterDoesNotReproduceTheProof() throws {
    let first = horizontalSurface()
    let second = verticalSurface()
    let box = try parameterBox()
    let anchors = try anchorParameters()

    #expect(throws: KernelError.self) {
      _ = try CertifiedImplicitIntersectionGraphCell(
        parameterBox: box,
        freeParameter: .firstU,
        direction: .forward,
        lowerAnchor: anchors.lower,
        midpointAnchor: anchors.midpoint,
        upperAnchor: anchors.upper,
        firstSurface: first,
        secondSurface: second,
        tolerance: tolerance
      )
    }
  }

  @Test(.timeLimit(.minutes(1)))
  func proceduralSurfaceCellReconstructsARepresentationIndependentGraphProof() throws {
    let first = Surface3D.procedural(
      .offset(
        OffsetSurface3D(
          source: .bSpline(horizontalSurface()),
          distance: 0.25
        )))
    let second = Surface3D.procedural(
      .offset(
        OffsetSurface3D(
          source: .bSpline(verticalSurface()),
          distance: 0.1
        )))
    let anchors = try proceduralAnchorParameters()
    let cell = try CertifiedImplicitIntersectionGraphCell(
      parameterBox: parameterBox(),
      freeParameter: .firstV,
      direction: .forward,
      lowerAnchor: anchors.lower,
      midpointAnchor: anchors.midpoint,
      upperAnchor: anchors.upper,
      firstSurface: first,
      secondSurface: second,
      tolerance: tolerance
    )
    let curve = try CertifiedImplicitIntersectionCurve(
      firstSurface: first,
      secondSurface: second,
      cells: [cell],
      isClosed: false,
      tolerance: tolerance
    )

    for fraction in [0.0, 0.25, 0.5, 0.75, 1.0] {
      let point = try curve.point(
        atNormalizedFraction: fraction,
        tolerance: tolerance
      )
      #expect(abs(point.x - 0.6) <= tolerance.distance)
      #expect(abs(point.y - fraction) <= tolerance.distance)
      #expect(abs(point.z - 0.25) <= tolerance.distance)
    }

    let derivativeBounds = try cell.parameterDerivativeBounds(
      firstSurface: first,
      secondSurface: second,
      tolerance: tolerance
    )
    #expect(derivativeBounds.count == 4)
    #expect(derivativeBounds[0].contains(0.0))
    #expect(derivativeBounds[1].contains(1.0))
    #expect(derivativeBounds[2].contains(1.0 / 3.0))
    #expect(derivativeBounds[3].contains(0.0))

    let firstPcurve = CertifiedImplicitSurfaceParameterCurve(
      validatedIntersection: curve,
      role: .first
    )
    let secondPcurve = CertifiedImplicitSurfaceParameterCurve(
      validatedIntersection: curve,
      role: .second
    )
    try firstPcurve.validate(on: first, tolerance: tolerance)
    try secondPcurve.validate(on: second, tolerance: tolerance)

    let bounds = try curve.boundingBox(
      fromNormalizedFraction: 0.0,
      toNormalizedFraction: 1.0,
      tolerance: tolerance
    )
    #expect(
      bounds.contains(
        Point3D(x: 0.6, y: 0.5, z: 0.25),
        tolerance: tolerance.distance
      ))

    let encoded = try JSONEncoder().encode(curve)
    let decoded = try JSONDecoder().decode(
      CertifiedImplicitIntersectionCurve.self,
      from: encoded
    )
    #expect(decoded == curve)
    try decoded.validate(tolerance: tolerance)
  }

  @Test(.timeLimit(.minutes(1)))
  func proceduralSurfaceCellRejectsAnIncorrectGraphCoordinate() throws {
    let first = Surface3D.procedural(
      .offset(
        OffsetSurface3D(
          source: .bSpline(horizontalSurface()),
          distance: 0.25
        )))
    let second = Surface3D.procedural(
      .offset(
        OffsetSurface3D(
          source: .bSpline(verticalSurface()),
          distance: 0.1
        )))
    let anchors = try proceduralAnchorParameters()

    #expect(throws: KernelError.self) {
      _ = try CertifiedImplicitIntersectionGraphCell(
        parameterBox: parameterBox(),
        freeParameter: .firstU,
        direction: .forward,
        lowerAnchor: anchors.lower,
        midpointAnchor: anchors.midpoint,
        upperAnchor: anchors.upper,
        firstSurface: first,
        secondSurface: second,
        tolerance: tolerance
      )
    }
  }

  @Test(.timeLimit(.minutes(1)))
  func strictRoundTripReconstructsAndRevalidatesTheCertificate() throws {
    let first = horizontalSurface()
    let second = verticalSurface()
    let curve = try CertifiedImplicitIntersectionCurve(
      firstSurface: first,
      secondSurface: second,
      cells: [try graphCell(first: first, second: second)],
      isClosed: false,
      tolerance: tolerance
    )

    let encoded = try JSONEncoder().encode(curve)
    let decoded = try JSONDecoder().decode(
      CertifiedImplicitIntersectionCurve.self,
      from: encoded
    )

    #expect(decoded == curve)
    try decoded.validate(tolerance: tolerance)
  }

  @Test(.timeLimit(.minutes(1)))
  func certificateCannotBeReusedAtAStricterTolerance() throws {
    let first = horizontalSurface()
    let second = verticalSurface()
    let curve = try CertifiedImplicitIntersectionCurve(
      firstSurface: first,
      secondSurface: second,
      cells: [try graphCell(first: first, second: second)],
      isClosed: false,
      tolerance: tolerance
    )
    let stricterTolerance = ModelingTolerance(
      distance: tolerance.distance * 0.5,
      angle: tolerance.angle * 0.5,
      relative: tolerance.relative * 0.5
    )

    #expect(throws: KernelError.self) {
      try curve.validate(tolerance: stricterTolerance)
    }
    let admitted = try ValidatedCurve3D(.implicit(curve), tolerance: tolerance)
    for parameter in [0.0, 0.5, 1.0] {
      #expect(try admitted.point(at: parameter) == curve.point(
        atNormalizedFraction: parameter, tolerance: tolerance))
    }
    #expect(throws: KernelError.self) {
      try ValidatedCurve3D(.implicit(curve), tolerance: stricterTolerance)
    }
    #expect(throws: KernelError.self) {
      try PreparedCurveDifferentialEncloser(curve: .implicit(curve), tolerance: stricterTolerance)
    }
  }

  @Test(.timeLimit(.minutes(1)))
  func intersectsThirdBSplineWithCertifiedParametricCompleteness() throws {
    let first = horizontalSurface()
    let second = verticalSurface()
    let curve = try CertifiedImplicitIntersectionCurve(
      firstSurface: first,
      secondSurface: second,
      cells: [try graphCell(first: first, second: second)],
      isClosed: false,
      tolerance: tolerance
    )
    let target = BSplineSurface3D(
      uDegree: 1,
      vDegree: 1,
      uKnots: [0.0, 0.0, 1.0, 1.0],
      vKnots: [0.0, 0.0, 1.0, 1.0],
      controlPoints: [
        [
          Point3D(x: 0.0, y: 0.25, z: -1.0),
          Point3D(x: 1.0, y: 0.25, z: -1.0),
        ],
        [
          Point3D(x: 0.0, y: 0.25, z: 1.0),
          Point3D(x: 1.0, y: 0.25, z: 1.0),
        ],
      ],
      weights: [[1.0, 1.0], [1.0, 1.0]]
    )

    let intersections = try DefaultCurveSurfaceIntersector().intersections(
      curve: .implicit(curve),
      surface: .bSpline(target),
      options: CurveSurfaceIntersectionOptions(),
      tolerance: tolerance
    )

    let intersection = try #require(intersections.first)
    #expect(intersections.count == 1)
    #expect(intersection.kind == .transverse)
    #expect(abs(intersection.curveParameter - 0.25) <= tolerance.relative)
    #expect(
      intersection.point.isApproximatelyEqual(
        to: Point3D(x: 0.5, y: 0.25, z: 0.0),
        tolerance: tolerance.distance
      ))
    #expect(intersection.residual <= tolerance.distance)
  }

  @Test(.timeLimit(.minutes(1)))
  func singularThirdBSplineContactFailsExplicitly() throws {
    let first = horizontalSurface()
    let second = verticalSurface()
    let curve = try CertifiedImplicitIntersectionCurve(
      firstSurface: first,
      secondSurface: second,
      cells: [try graphCell(first: first, second: second)],
      isClosed: false,
      tolerance: tolerance
    )
    let options = CurveSurfaceIntersectionOptions(
      maximumSubdivisionDepth: 0
    )

    do {
      _ = try DefaultCurveSurfaceIntersector().intersections(
        curve: .implicit(curve),
        surface: .bSpline(tangentParaboloid()),
        options: options,
        tolerance: tolerance
      )
      Issue.record("A singular uncertified contact must fail explicitly.")
    } catch let error as KernelError {
      #expect(error.code == .resourceLimitExceeded)
    }
  }

  @Test(.timeLimit(.minutes(1)))
  func intersectsExactPlaneThroughCertifiedRationalPatch() throws {
    let curve = try certifiedLineCurve()
    let target = Surface3D.plane(
      Plane3D(
        origin: Point3D(x: 0.0, y: 0.25, z: 0.0),
        normal: .unitY
      ))

    let intersections = try DefaultCurveSurfaceIntersector().intersections(
      curve: .implicit(curve),
      surface: target,
      options: CurveSurfaceIntersectionOptions(),
      tolerance: tolerance
    )

    let intersection = try #require(intersections.first)
    #expect(intersections.count == 1)
    #expect(intersection.kind == .transverse)
    #expect(abs(intersection.curveParameter - 0.25) <= tolerance.relative)
    #expect(
      intersection.point.isApproximatelyEqual(
        to: Point3D(x: 0.5, y: 0.25, z: 0.0),
        tolerance: tolerance.distance
      ))
    #expect(intersection.residual <= tolerance.distance)
  }

  @Test(.timeLimit(.minutes(1)))
  func legacyPlaneRemapsExplicitParameterRanges() throws {
    let curve = try certifiedLineCurve()
    let target = Surface3D.plane(
      Plane3D(
        origin: Point3D(x: 0.0, y: 0.25, z: 0.0),
        normal: .unitY
      ))
    let options = CurveSurfaceIntersectionOptions(
      surfaceURange: try ScalarInterval(lower: -0.6, upper: -0.4),
      surfaceVRange: try ScalarInterval(lower: -0.1, upper: 0.1)
    )

    let intersections = try DefaultCurveSurfaceIntersector().intersections(
      curve: .implicit(curve),
      surface: target,
      options: options,
      tolerance: tolerance
    )

    let intersection = try #require(intersections.first)
    #expect(intersections.count == 1)
    #expect(abs(intersection.surfaceU + 0.5) <= tolerance.relative)
    #expect(abs(intersection.surfaceV) <= tolerance.relative)
    #expect(intersection.residual <= tolerance.distance)
  }

  @Test(.timeLimit(.minutes(1)))
  func analyticCylinderRemapsIntoShiftedPeriodicRange() throws {
    let curve = try certifiedLineCurve()
    let target = Surface3D.cylinder(
      Cylinder3D(
        origin: .origin,
        axis: .unitZ,
        radius: 1.0
      ))
    let expectedAngle = Double.pi / 3.0
    let shiftedAngle = expectedAngle + 2.0 * Double.pi
    let options = CurveSurfaceIntersectionOptions(
      surfaceURange: try ScalarInterval(
        lower: shiftedAngle - 0.1,
        upper: shiftedAngle + 0.1
      ),
      surfaceVRange: try ScalarInterval(lower: -0.1, upper: 0.1)
    )

    let intersections = try DefaultCurveSurfaceIntersector().intersections(
      curve: .implicit(curve),
      surface: target,
      options: options,
      tolerance: tolerance
    )

    let intersection = try #require(intersections.first)
    #expect(intersections.count == 1)
    #expect(intersection.kind == .transverse)
    #expect(abs(intersection.surfaceU - shiftedAngle) <= tolerance.angle)
    #expect(abs(intersection.surfaceV) <= tolerance.distance)
    #expect(
      abs(intersection.curveParameter - sqrt(0.75))
        <= tolerance.relative)
    #expect(intersection.residual <= tolerance.distance)
  }

  @Test(.timeLimit(.minutes(1)))
  func exactImplicitSourceSurfaceReportsContinuousCoincidence() throws {
    let curve = try certifiedLineCurve()

    do {
      _ = try DefaultCurveSurfaceIntersector().intersections(
        curve: .implicit(curve),
        surface: curve.firstSurface,
        options: CurveSurfaceIntersectionOptions(),
        tolerance: tolerance
      )
      Issue.record("An exact source surface must report coincidence.")
    } catch let error as KernelError {
      #expect(error.code == .nonDiscreteIntersection)
    }
  }

  @Test(.timeLimit(.minutes(1)))
  func singularAnalyticContactFailsExplicitly() throws {
    let curve = try certifiedLineCurve()
    let target = Surface3D.analytic(
      .sphere(
        center: Point3D(x: 0.6, y: 0.5, z: 0.0),
        radius: 0.1
      ))
    let options = CurveSurfaceIntersectionOptions(
      surfaceURange: try ScalarInterval(
        lower: Double.pi * 0.5 - 0.1,
        upper: Double.pi * 0.5 + 0.1
      ),
      surfaceVRange: try ScalarInterval(lower: -0.1, upper: 0.1),
      maximumSubdivisionDepth: 0,
      maximumPeriodicSeamAttempts: 1
    )

    do {
      _ = try DefaultCurveSurfaceIntersector().intersections(
        curve: .implicit(curve),
        surface: target,
        options: options,
        tolerance: tolerance
      )
      Issue.record("A singular analytic contact must fail explicitly.")
    } catch let error as KernelError {
      #expect(error.code == .resourceLimitExceeded)
    }
  }

  @Test
  func rejectsInvalidPeriodicSeamAttemptBudget() throws {
    let curve = try certifiedLineCurve()
    let target = Surface3D.cylinder(
      Cylinder3D(
        origin: .origin,
        axis: .unitZ,
        radius: 1.0
      ))

    do {
      _ = try DefaultCurveSurfaceIntersector().intersections(
        curve: .implicit(curve),
        surface: target,
        options: CurveSurfaceIntersectionOptions(
          maximumPeriodicSeamAttempts: 0
        ),
        tolerance: tolerance
      )
      Issue.record("An invalid seam-attempt budget must be rejected.")
    } catch let error as KernelError {
      #expect(error.code == .resourceLimitExceeded)
    }
  }

  private func certifiedLineCurve()
    throws -> CertifiedImplicitIntersectionCurve
  {
    let first = horizontalSurface()
    let second = verticalSurface()
    return try CertifiedImplicitIntersectionCurve(
      firstSurface: first,
      secondSurface: second,
      cells: [try graphCell(first: first, second: second)],
      isClosed: false,
      tolerance: tolerance
    )
  }

  private func tangentParaboloid() -> BSplineSurface3D {
    let uX = [0.5625, 0.3125, 1.0625]
    let vX = [1.0, -1.0, 1.0]
    let uY = [0.0, 0.5, 1.0]
    let vZ = [-1.0, 0.0, 1.0]
    let controlPoints = uX.indices.map { uIndex in
      vX.indices.map { vIndex in
        Point3D(
          x: uX[uIndex] + vX[vIndex],
          y: uY[uIndex],
          z: vZ[vIndex]
        )
      }
    }
    return BSplineSurface3D(
      uDegree: 2,
      vDegree: 2,
      uKnots: [0.0, 0.0, 0.0, 1.0, 1.0, 1.0],
      vKnots: [0.0, 0.0, 0.0, 1.0, 1.0, 1.0],
      controlPoints: controlPoints,
      weights: Array(
        repeating: Array(repeating: 1.0, count: 3),
        count: 3
      )
    )
  }

  private func graphCell(
    first: BSplineSurface3D,
    second: BSplineSurface3D
  ) throws -> CertifiedImplicitIntersectionGraphCell {
    let anchors = try anchorParameters()
    return try CertifiedImplicitIntersectionGraphCell(
      parameterBox: parameterBox(),
      freeParameter: .firstV,
      direction: .forward,
      lowerAnchor: anchors.lower,
      midpointAnchor: anchors.midpoint,
      upperAnchor: anchors.upper,
      firstSurface: first,
      secondSurface: second,
      tolerance: tolerance
    )
  }

  private func parameterBox() throws -> SurfaceIntersectionParameterBox {
    SurfaceIntersectionParameterBox(
      firstU: try ScalarInterval(lower: 0.0, upper: 1.0),
      firstV: try ScalarInterval(lower: 0.0, upper: 1.0),
      secondU: try ScalarInterval(lower: 0.0, upper: 1.0),
      secondV: try ScalarInterval(lower: 0.0, upper: 1.0)
    )
  }

  private func anchorParameters() throws -> (
    lower: SurfaceIntersectionParameterPair,
    midpoint: SurfaceIntersectionParameterPair,
    upper: SurfaceIntersectionParameterPair
  ) {
    (
      try SurfaceIntersectionParameterPair(
        first: SurfaceParameter(u: 0.5, v: 0.0),
        second: SurfaceParameter(u: 1.0 / 3.0, v: 0.5)
      ),
      try SurfaceIntersectionParameterPair(
        first: SurfaceParameter(u: 0.5, v: 0.5),
        second: SurfaceParameter(u: 0.5, v: 0.5)
      ),
      try SurfaceIntersectionParameterPair(
        first: SurfaceParameter(u: 0.5, v: 1.0),
        second: SurfaceParameter(u: 2.0 / 3.0, v: 0.5)
      )
    )
  }

  private func proceduralAnchorParameters() throws -> (
    lower: SurfaceIntersectionParameterPair,
    midpoint: SurfaceIntersectionParameterPair,
    upper: SurfaceIntersectionParameterPair
  ) {
    (
      try SurfaceIntersectionParameterPair(
        first: SurfaceParameter(u: 0.6, v: 0.0),
        second: SurfaceParameter(u: 1.0 / 3.0, v: 0.625)
      ),
      try SurfaceIntersectionParameterPair(
        first: SurfaceParameter(u: 0.6, v: 0.5),
        second: SurfaceParameter(u: 0.5, v: 0.625)
      ),
      try SurfaceIntersectionParameterPair(
        first: SurfaceParameter(u: 0.6, v: 1.0),
        second: SurfaceParameter(u: 2.0 / 3.0, v: 0.625)
      )
    )
  }

  private func horizontalSurface() -> BSplineSurface3D {
    BSplineSurface3D(
      uDegree: 1,
      vDegree: 1,
      uKnots: [0.0, 0.0, 1.0, 1.0],
      vKnots: [0.0, 0.0, 1.0, 1.0],
      controlPoints: [
        [
          Point3D(x: 0.0, y: 0.0, z: 0.0),
          Point3D(x: 1.0, y: 0.0, z: 0.0),
        ],
        [
          Point3D(x: 0.0, y: 1.0, z: 0.0),
          Point3D(x: 1.0, y: 1.0, z: 0.0),
        ],
      ],
      weights: [[1.0, 1.0], [1.0, 1.0]]
    )
  }

  private func verticalSurface() -> BSplineSurface3D {
    BSplineSurface3D(
      uDegree: 1,
      vDegree: 1,
      uKnots: [0.0, 0.0, 1.0, 1.0],
      vKnots: [0.0, 0.0, 1.0, 1.0],
      controlPoints: [
        [
          Point3D(x: 0.5, y: -1.0, z: -1.0),
          Point3D(x: 0.5, y: 2.0, z: -1.0),
        ],
        [
          Point3D(x: 0.5, y: -1.0, z: 1.0),
          Point3D(x: 0.5, y: 2.0, z: 1.0),
        ],
      ],
      weights: [[1.0, 1.0], [1.0, 1.0]]
    )
  }
}
