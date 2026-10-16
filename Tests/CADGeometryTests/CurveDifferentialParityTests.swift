import CADCore
import Synchronization
@testable import CADGeometry
import Testing

@Suite("Original third-order differential authority parity")
struct CurveDifferentialParityTests {
    @Test(.timeLimit(.minutes(1))) func independentOriginalLawsAndReverse() throws {
        try CurveDifferentialParityChecks.independentOriginalLawsAndReverse()
    }
    @Test(.timeLimit(.minutes(1))) func sameAdmissionMeasuredResources() throws {
        try CurveDifferentialParityChecks.sameAdmissionMeasuredResources()
    }
    @Test(.timeLimit(.minutes(1))) func entryAndTerminalCancellation() throws {
        try CurveDifferentialParityChecks.entryAndTerminalCancellation()
    }
    @Test(.timeLimit(.minutes(1))) func ruledPublicConsumerContainsIndependentLaw() throws {
        try CurveDifferentialParityChecks.ruledPublicConsumerContainsIndependentLaw()
    }
    @Test(.timeLimit(.minutes(1))) func periodicCylinderPositiveWidthPathIsPreserved() throws {
        try CurveDifferentialParityChecks.periodicCylinderPositiveWidthPathIsPreserved()
    }
}

enum CurveDifferentialParityChecks {
    struct Failure: Error { let detail: String }
    static let tolerance = ModelingTolerance(distance: 1e-9, angle: 1e-10, relative: 1e-11)
    static func require(_ condition: Bool, _ detail: String) throws {
        guard condition else { throw Failure(detail: detail) }
    }
    static func execution(_ budget: OriginalQueryBudget) throws -> OriginalQueryExecution {
        .init(budget: budget, limits: try .init(maximumValueDepth: 32,
            maximumCoefficientDepth: 32, remainingSourceDepth: 16,
            maximumTransportDepth: 16, maximumSubdivisionDepth: 32))
    }
    static func range() throws -> ScalarInterval { try .init(lower: 0.17, upper: 0.83) }
    static func planeLift(reversed: Bool = false) -> Curve3D {
        .surfaceLift(.init(surface: .plane(.init(origin: .origin, normal: .unitZ, uDirection: .unitX)),
            parameterCurve: .affine(origin: .init(x: reversed ? 1 : 0, y: reversed ? 0.5 : 0),
                direction: .init(x: reversed ? -1 : 1, y: reversed ? -0.5 : 0.5),
                startParameter: 0, endParameter: 1)))
    }
    static func implicitLine(reversed: Bool = false) throws -> Curve3D {
        let first = BSplineSurface3D(uDegree: 1, vDegree: 1,
            uKnots: [0,0,1,1], vKnots: [0,0,1,1],
            controlPoints: [[.init(x: 0,y: 0,z: 0), .init(x: 1,y: 0,z: 0)],
                            [.init(x: 0,y: 1,z: 0), .init(x: 1,y: 1,z: 0)]], weights: [[1,1],[1,1]])
        let second = BSplineSurface3D(uDegree: 1, vDegree: 1,
            uKnots: [0,0,1,1], vKnots: [0,0,1,1],
            controlPoints: [[.init(x: 0.5,y: -1,z: -1), .init(x: 0.5,y: 2,z: -1)],
                            [.init(x: 0.5,y: -1,z: 1), .init(x: 0.5,y: 2,z: 1)]], weights: [[1,1],[1,1]])
        let unit = try ScalarInterval(lower: 0, upper: 1)
        let box = SurfaceIntersectionParameterBox(firstU: unit, firstV: unit, secondU: unit, secondV: unit)
        func anchor(_ t: Double) throws -> SurfaceIntersectionParameterPair {
            try .init(first: .init(u: 0.5,v: t), second: .init(u: (t + 1) / 3,v: 0.5))
        }
        let cell = try CertifiedImplicitIntersectionGraphCell(parameterBox: box, freeParameter: .firstV,
            direction: reversed ? .reversed : .forward,
            lowerAnchor: anchor(0), midpointAnchor: anchor(0.5), upperAnchor: anchor(1),
            firstSurface: first, secondSurface: second, tolerance: tolerance)
        return .implicit(try .init(firstSurface: first, secondSurface: second, cells: [cell],
            isClosed: false, tolerance: tolerance))
    }
    static func scalars(_ value: SurfaceIntervalJet) -> [OutwardScalarInterval] {
        [value.value, value.derivativeU, value.derivativeV,
         value.secondDerivativeUU, value.secondDerivativeUV, value.secondDerivativeVV,
         value.thirdDerivativeUUU, value.thirdDerivativeUUV, value.thirdDerivativeUVV, value.thirdDerivativeVVV]
    }
    static func identical(_ first: SurfaceIntervalVectorJet, _ second: SurfaceIntervalVectorJet) throws {
        for (a,b) in zip([first.x,first.y,first.z], [second.x,second.y,second.z]) {
            for (x,y) in zip(scalars(a),scalars(b)) {
                try require(x.lower.bitPattern == y.lower.bitPattern && x.upper.bitPattern == y.upper.bitPattern,
                    "Prepared and one-shot differential endpoints differ.")
            }
        }
    }
    static func contains(_ bound: OutwardScalarInterval, _ value: Double) throws {
        try require(bound.lower <= value && value <= bound.upper, "An independent derivative escaped its enclosure.")
    }
    static func lineLaw(_ jet: SurfaceIntervalVectorJet, origin: Point3D, tangent: Vector3D) throws {
        let interval = try range()
        for (scalar,start,slope) in [(jet.x,origin.x,tangent.x), (jet.y,origin.y,tangent.y), (jet.z,origin.z,tangent.z)] {
            for t in [interval.lower,interval.midpoint,interval.upper] { try contains(scalar.value,start + slope * t) }
            try contains(scalar.derivativeU,slope)
            for bound in scalars(scalar).dropFirst(2) { try contains(bound,0) }
        }
    }
    static func independentOriginalLawsAndReverse() throws {
        for reversed in [false,true] {
            let curves = [try implicitLine(reversed: reversed), planeLift(reversed: reversed)]
            for (index,curve) in curves.enumerated() {
                var admission = try execution(OriginalQueryBudget(workLimit: 8_388_608,storageByteLimit: 268_435_456))
                let jet = try DefaultCurveDifferentialEncloser().thirdOrderIntervalJet(of: curve,
                    over: range(), tolerance: tolerance, using: &admission)
                let prepared = try PreparedCurveDifferentialEncloser(curve: curve,tolerance: tolerance)
                    .thirdOrderIntervalJet(over: range(),tolerance: tolerance)
                try identical(jet,prepared)
                let sign = reversed ? -1.0 : 1.0
                if index == 0 {
                    try lineLaw(jet,origin: .init(x: 0.5,y: reversed ? 1 : 0,z: 0),tangent: .init(x: 0,y: sign,z: 0))
                } else {
                    try lineLaw(jet,origin: .init(x: reversed ? 1 : 0,y: reversed ? 0.5 : 0,z: 0),
                        tangent: .init(x: sign,y: sign * 0.5,z: 0))
                }
            }
        }
    }
    static func originalFailure(_ error: any Error) -> any Error {
        if let retained = error as? OriginalQueryFailure { return originalFailure(retained.originalError) }
        if case .admissionRejected(let retained)? = error as? ExactScalarFailure { return originalFailure(retained) }
        return error
    }
    static func refusal(_ expected: ExactResource?, _ operation: () throws -> Void) throws {
        do { try operation() }
        catch {
            guard let scalar = originalFailure(error) as? ExactScalarFailure else { throw error }
            switch (expected,scalar) {
            case (.some(let wanted),.resourceLimit(let actual)) where wanted == actual: return
            case (.none,.cancelled): return
            default: throw error
            }
        }
        throw Failure(detail: "A refused query published a jet.")
    }
    static func query(_ curve: Curve3D, budget: OriginalQueryBudget) throws -> SurfaceIntervalVectorJet {
        var admission = try execution(budget)
        try admission.consumeWork(7)
        try budget.chargeSource(storageBytes: 11)
        return try DefaultCurveDifferentialEncloser().thirdOrderIntervalJet(of: curve,
            over: range(),tolerance: tolerance,using: &admission)
    }
    static func sameAdmissionMeasuredResources() throws {
        for curve in [try implicitLine(),planeLift()] {
            let measured = try OriginalQueryBudget(workLimit: 8_388_608,storageByteLimit: 268_435_456)
            let expected = try query(curve,budget: measured)
            let cost = measured.snapshot
            try require(cost.work > 7 && cost.storageBytes > 11,"The original owner was not charged to its caller.")
            let exact = try OriginalQueryBudget(workLimit: cost.work,storageByteLimit: cost.storageBytes)
            try identical(try query(curve,budget: exact),expected)
            try require(exact.snapshot.work == cost.work && exact.snapshot.storageBytes == cost.storageBytes,
                "Exact cumulative resource use changed.")
            for resource in [ExactResource.work,.storage] {
                let limited = try OriginalQueryBudget(workLimit: resource == .work ? cost.work - 1 : cost.work,
                    storageByteLimit: resource == .storage ? cost.storageBytes - 1 : cost.storageBytes)
                try refusal(resource) { _ = try query(curve,budget: limited) }
                try require(limited.snapshot.work <= cost.work && limited.snapshot.storageBytes <= cost.storageBytes,
                    "A rejected allocation/debit crossed its limit.")
            }
            var again = try execution(exact)
            // A fresh reader admits its proof-frame storage before its first work debit.
            try refusal(.storage) {
                _ = try DefaultCurveDifferentialEncloser().thirdOrderIntervalJet(of: curve,over: range(),
                    tolerance: tolerance,using: &again)
            }
            try require(exact.snapshot.work == cost.work && exact.snapshot.storageBytes == cost.storageBytes,
                "A fresh execution reset the caller allowance.")
        }
    }
    final class Checkpoints: Sendable {
        private let state = Mutex(0)
        let stop: Int?
        init(stop: Int? = nil) { self.stop = stop }
        var count: Int { state.withLock { $0 } }
        func checkpoint() throws(ExactScalarFailure) {
            let ordinal = state.withLock { value in value += 1; return value }
            if ordinal == stop { throw .cancelled }
        }
    }
    static func entryAndTerminalCancellation() throws {
        for curve in [try implicitLine(),planeLift()] {
            let checkpoints = Checkpoints()
            let measured = try OriginalQueryBudget(checkpoint: { try checkpoints.checkpoint() })
            var admission = try execution(measured)
            _ = try DefaultCurveDifferentialEncloser().thirdOrderIntervalJet(of: curve,over: range(),
                tolerance: tolerance,using: &admission)
            let complete = measured.snapshot
            try require(checkpoints.count > 1,"No terminal checkpoint was observed.")
            for stop in [1,checkpoints.count] {
                let cancellation = Checkpoints(stop: stop)
                let budget = try OriginalQueryBudget(checkpoint: { try cancellation.checkpoint() })
                var read = try execution(budget)
                try refusal(nil) {
                    _ = try DefaultCurveDifferentialEncloser().thirdOrderIntervalJet(of: curve,over: range(),
                        tolerance: tolerance,using: &read)
                }
                try require(cancellation.count == stop,"The expected cancellation boundary was not reached.")
                try require(budget.snapshot.work == (stop == 1 ? 0 : complete.work)
                    && budget.snapshot.storageBytes == (stop == 1 ? 0 : complete.storageBytes),
                    "Cancellation did not preserve its original debit boundary.")
            }
        }
    }
    static func ruledPublicConsumerContainsIndependentLaw() throws {
        let ruled = Surface3D.procedural(.ruled(.init(startBoundary: try implicitLine(),endBoundary: planeLift())))
        let box = SurfaceParameterBox(u: try range(),v: try .init(lower: 0.2,upper: 0.7))
        let budget = try OriginalQueryBudget(workLimit: 8_388_608,storageByteLimit: 268_435_456)
        var admission = try execution(budget)
        let enclosure = try DefaultSurfaceDifferentialEncloser().enclosure(of: ruled,over: box,
            tolerance: tolerance,using: &admission)
        // S(u,v)=(.5+v*(u-.5), u*(1-.5*v), 0).
        for u in [box.u.lower,box.u.midpoint,box.u.upper] {
            for v in [box.v.lower,box.v.midpoint,box.v.upper] {
                try require(enclosure.position.contains(Point3D(x: 0.5+v*(u-0.5),y: u*(1-0.5*v),z: 0)),
                    "The public ruled enclosure lost its original position.")
                try require(enclosure.tangentU.contains(Vector3D(x: v,y: 1-0.5*v,z: 0))
                    && enclosure.tangentV.contains(Vector3D(x: u-0.5,y: -0.5*u,z: 0)),
                    "The public ruled enclosure lost its independent first derivatives.")
            }
        }
        try require(enclosure.secondDerivativeUU.contains(Vector3D.zero)
            && enclosure.secondDerivativeUV.contains(Vector3D(x: 1,y: -0.5,z: 0))
            && enclosure.secondDerivativeVV.contains(Vector3D.zero),"The ruled mixed derivative changed.")
        try require(budget.snapshot.work > 0 && budget.snapshot.storageBytes > 0,"The consumer escaped caller admission.")
    }
    static func periodicCylinderPositiveWidthPathIsPreserved() throws {
        let curve = Curve3D.surfaceLift(.init(surface: .analytic(.cylinder(origin: .origin,axis: .unitZ,radius: 1)),
            parameterCurve: .affine(origin: .init(x: 0,y: 0),direction: .init(x: 1,y: 0),
                startParameter: 0,endParameter: 4 * Double.pi)))
        let interval = try ScalarInterval(lower: 0.4,upper: 0.6)
        var admission = try execution(OriginalQueryBudget(workLimit: 8_388_608,storageByteLimit: 268_435_456))
        let jet = try DefaultCurveDifferentialEncloser().thirdOrderIntervalJet(of: curve,over: interval,
            tolerance: tolerance,using: &admission)
        for t in [interval.lower,0.5,interval.upper] {
            let sample = try curve.differentialGeometry(at: t,tolerance: tolerance)
            for (scalar,p,d1,d2) in [(jet.x,sample.position.x,sample.firstDerivative.x,sample.secondDerivative.x),
                (jet.y,sample.position.y,sample.firstDerivative.y,sample.secondDerivative.y),
                (jet.z,sample.position.z,sample.firstDerivative.z,sample.secondDerivative.z)] {
                try contains(scalar.value,p); try contains(scalar.derivativeU,d1); try contains(scalar.secondDerivativeUU,d2)
                try contains(scalar.thirdDerivativeUUU,-(4 * Double.pi)*(4 * Double.pi)*d1)
            }
        }
    }
}
