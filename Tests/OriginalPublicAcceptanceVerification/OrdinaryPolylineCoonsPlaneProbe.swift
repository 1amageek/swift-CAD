#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#elseif canImport(WASILibc)
import WASILibc
#endif
import CADCore
import Synchronization
@testable import CADGeometry
@testable import PolylineLiftAdapters
@testable import PublicLiftPlane
import PublicLiftPlanePort

@main struct OrdinaryPolylineCoonsPlaneProof {
    enum Mode: Sendable { case ordinary,selections,resources,cancelFinal,cancelEntry,positive,gp,scaledNormals }
    nonisolated static var mode:Mode {
        #if PUBLIC_PROOF_GP
        return .gp
        #elseif PUBLIC_PROOF_SELECTIONS
        return .selections
        #elseif PUBLIC_PROOF_RESOURCES
        return .resources
        #elseif PUBLIC_PROOF_CANCEL_FINAL
        return .cancelFinal
        #elseif PUBLIC_PROOF_CANCEL_ENTRY
        return .cancelEntry
        #elseif hasFeature(Embedded)
        return .ordinary
        #else
        if CommandLine.arguments.contains("scaled-normals") { return .scaledNormals }
        if CommandLine.arguments.contains("gp") { return .gp }
        if CommandLine.arguments.contains("positive") { return .positive }
        if CommandLine.arguments.contains("selections") { return .selections }
        if CommandLine.arguments.contains("resources") { return .resources }
        if CommandLine.arguments.contains("cancel-final") { return .cancelFinal }
        if CommandLine.arguments.contains("cancel-entry") { return .cancelEntry }
        return .ordinary
        #endif
    }
    final class Counter: Sendable {
        struct State: Sendable { var work = 0;var bytes = 0 }
        private let state = Mutex(State())
        let maximumWork:Int
        let maximumBytes:Int
        let cancelAt:Int?
        let cancelTask:Bool
        init(work:Int = Int.max,bytes:Int = Int.max,cancelAt:Int? = nil,cancelTask:Bool = false) {
            maximumWork=work;maximumBytes=bytes;self.cancelAt=cancelAt;self.cancelTask=cancelTask
        }
        func consume(_ depth:Int) throws {
            let reached = try state.withLock { state in
                guard state.work < maximumWork else { throw ExactScalarFailure.resourceLimit(.work) }
                state.work += 1;return state.work
            }
            if reached == cancelAt {
                if cancelTask { withUnsafeCurrentTask { $0?.cancel() } }
                else { throw CancellationError() }
            }
        }
        func retain(_ bytes:Int) throws {
            try state.withLock { state in
                let next = state.bytes.addingReportingOverflow(bytes)
                guard bytes >= 0,!next.overflow,next.partialValue <= maximumBytes else { throw ExactScalarFailure.resourceLimit(.storage) }
                state.bytes=next.partialValue
            }
        }
        var totals:State { state.withLock { $0 } }
    }
    nonisolated static func input(normal override:Vector3D? = nil) throws -> (Curve3D,Surface3D) {
        var a = try PolylineLiftProof.Admission(work:8_388_608)
        let host = try PolylineAtlasLiftProof.shape(multi:true,using:&a).0
        #if PUBLIC_PROOF_SUBNORMAL
        let normal = override ?? Vector3D(x:Double.leastNonzeroMagnitude,y:0,z:0)
        #else
        let normal = override ?? Vector3D.unitX
        #endif
        return (.surfaceLift(.init(surface:.procedural(.originalCoons(host)),
            parameterCurve:.polyline(PolylineLiftProof.points()))),
            .plane(.init(origin:.init(x:0.5,y:0,z:0),normal:normal)))
    }
    nonisolated static func check(_ points:[CurveSurfaceIntersection]) throws {
        try PolylineLiftProof.require(points.count == 2)
        try PolylineLiftProof.require(abs(points[0].curveParameter-(2.0.squareRoot()-1)) <= 1e-6)
        try PolylineLiftProof.require(points[1].curveParameter == 1)
        for point in points {
            try PolylineLiftProof.require(point.kind == .transverse)
            try PolylineLiftProof.require(abs(point.point.x-0.5) <= 1e-6 && abs(point.point.y-0.5) <= 1e-6 && abs(point.point.z) <= 1e-6)
            try PolylineLiftProof.require(abs(point.surfaceU) <= 1e-6 && abs(point.surfaceV+0.5) <= 1e-6)
        }
    }
    nonisolated static func run(_ selected:Mode? = nil,normal:Vector3D? = nil) async throws {
        let mode = selected ?? Self.mode
        func input() throws -> (Curve3D,Surface3D) { try Self.input(normal:normal) }
        let intersector = PublicLiftPlanePort.DefaultCurveSurfaceIntersector()
        if mode == .gp { try PreparedGraphPublicationRegression.run();return }
        if mode == .cancelEntry {
            let (curve,plane) = try input(),counter = Counter()
            withUnsafeCurrentTask { $0?.cancel() }
            do {
                _ = try intersector.intersectionResult(curve:curve,surface:plane,tolerance:.standard,
                    maximumSpanCount:262_144,maximumSubdivisionDepth:8,remainingSourceDepth:8,
                    consumeWork:{ try counter.consume($0) },consumeStorage:{ try counter.retain($0) },maximumAlgebraicDepth:32)
                throw ExactScalarFailure.invalidEvidence
            } catch is CancellationError {}
            try PolylineLiftProof.require(counter.totals.work == 0 && counter.totals.bytes == 0)
            print("PASS ordinary public entry Task cancellation before work/storage")
            return
        }
        if mode == .positive {
            let (curve,_) = try input()
            let plane = Surface3D.plane(.init(origin:.origin,normal:.unitZ))
            do { _ = try intersector.intersections(curve:curve,surface:plane,options:.init(),tolerance:.standard);throw ExactScalarFailure.invalidEvidence }
            catch let error as KernelError {
                #if !hasFeature(Embedded)
                print("POSITIVE bare diagnostic",error)
                #endif
                try PolylineLiftProof.require(error.code == .nonDiscreteIntersection)
            }
            let result = try intersector.intersectionResult(curve:curve,surface:plane,tolerance:.standard)
            try PolylineLiftProof.require(result.points.isEmpty && result.hasPositiveDimensionalSolutions)
            try PolylineLiftProof.require(result.originalIssuedGeometricRelation?.hasPositiveDimensionalImage == true)
            print("PASS ordinary public positive-dimensional lift/plane: bare refuses, rich retains complete image/fiber relation")
            return
        }
        if mode == .resources || mode == .cancelFinal {
            let (curve,plane) = try input()
            func query(_ counter:Counter,options:CurveSurfaceIntersectionOptions = .init()) throws -> PublicLiftPlanePort.CurveSurfaceIntersectionResult {
                try intersector.intersectionResult(curve:curve,surface:plane,options:options,tolerance:.standard,
                    maximumSpanCount:262_144,maximumSubdivisionDepth:8,remainingSourceDepth:8,
                    consumeWork:{ try counter.consume($0) },consumeStorage:{ try counter.retain($0) },maximumAlgebraicDepth:32)
            }
            let measured = Counter()
            let retained = try query(measured)
            let exact = measured.totals
            if mode == .cancelFinal {
                do { _ = try query(Counter(cancelAt:exact.work,cancelTask:true));throw ExactScalarFailure.invalidEvidence }
                catch is CancellationError {}
                #if hasFeature(Embedded)
                print("PASS ordinary public final callback cancellation")
                #else
                print("PASS ordinary public final work callback cancels current task and returns; publication propagates cancellation",exact.work)
                #endif
                return
            }
            try check(query(Counter(work:exact.work,bytes:exact.bytes)).points)
            for counter in [Counter(work:exact.work-1),Counter(bytes:exact.bytes-1),Counter(cancelAt:1),Counter(cancelAt:exact.work)] {
                do { _ = try query(counter);throw ExactScalarFailure.invalidEvidence }
                catch is CancellationError { try PolylineLiftProof.require(counter.cancelAt != nil) }
                catch let error as KernelError { try PolylineLiftProof.require(counter.cancelAt == nil && error.code == .resourceLimitExceeded) }
            }
            var options = CurveSurfaceIntersectionOptions();options.maximumCandidateCount = 11
            do { _ = try intersector.intersectionResult(curve:curve,surface:plane,options:options,tolerance:.standard);throw ExactScalarFailure.invalidEvidence }
            catch let error as KernelError { try PolylineLiftProof.require(error.code == .resourceLimitExceeded) }
            options = .init();options.maximumPolynomialDegree = 0
            do { _ = try intersector.intersectionResult(curve:curve,surface:plane,options:options,tolerance:.standard);throw ExactScalarFailure.invalidEvidence }
            catch let error as KernelError { try PolylineLiftProof.require(error.code == .resourceLimitExceeded) }
            for depth in [0,1] {
                let counter = Counter()
                do {
                    _ = try intersector.intersectionResult(curve:curve,surface:plane,tolerance:.standard,
                        maximumSpanCount:262_144,maximumSubdivisionDepth:8,remainingSourceDepth:depth,
                        consumeWork:{ try counter.consume($0) },consumeStorage:{ try counter.retain($0) },maximumAlgebraicDepth:32)
                    throw ExactScalarFailure.invalidEvidence
                } catch let error as KernelError { try PolylineLiftProof.require(error.code == .resourceLimitExceeded) }
            }
            let shallow = Counter()
            do {
                _ = try intersector.intersectionResult(curve:curve,surface:plane,tolerance:.standard,
                    maximumSpanCount:262_144,maximumSubdivisionDepth:8,remainingSourceDepth:8,
                    consumeWork:{ try shallow.consume($0) },consumeStorage:{ try shallow.retain($0) },maximumAlgebraicDepth:0)
                throw ExactScalarFailure.invalidEvidence
            } catch let error as KernelError { try PolylineLiftProof.require(error.code == .resourceLimitExceeded) }
            var emptyOptions = CurveSurfaceIntersectionOptions();emptyOptions.curveRange = try .init(lower:2,upper:3)
            let emptyCounter = Counter(),empty = try query(emptyCounter,options:emptyOptions)
            try PolylineLiftProof.require(empty.originalIssuedGeometricRelation?.isEmpty == true)
            do { _ = try query(Counter(cancelAt:emptyCounter.totals.work),options:emptyOptions);throw ExactScalarFailure.invalidEvidence }
            catch is CancellationError {}
            try check(retained.points)
            #if hasFeature(Embedded)
            print("PASS ordinary public exact/one-less work/storage; entry/last callback cancel; candidate/degree/source-depth ceilings; retained result")
            #else
            print("PASS ordinary public exact/one-less work",exact.work,"bytes",exact.bytes,"entry/last callback cancel, candidate/degree/source-depth ceilings, retained result after independent failed queries")
            #endif
            return
        }
        if mode == .scaledNormals {
            let (curve,_) = try input()
            for scale in [2.0,-2.0,Double.leastNonzeroMagnitude,Double.greatestFiniteMagnitude] {
                #if !hasFeature(Embedded)
                print("BEGIN saved-normal diagnostic",scale)
                #endif
                let scaled = Surface3D.plane(.init(origin:.init(x:0.5,y:0,z:0),normal:.init(x:scale,y:0,z:0)))
                let result = try intersector.intersectionResult(curve:curve,surface:scaled,tolerance:.standard)
                try PolylineLiftProof.require(result.points.count == 2 && result.originalIssuedGeometricRelation?.exactPoints.count == 12)
                #if !hasFeature(Embedded)
                print("END saved-normal diagnostic",scale)
                #endif
            }
            return
        }
        if mode == .selections {
            let (curve,plane) = try input()
            for (range,count) in [(try ScalarInterval(lower:1,upper:1),1),
                (try ScalarInterval(lower:0.6,upper:0.9),0),
                (try ScalarInterval(lower:2,upper:3),0)] {
                var options = CurveSurfaceIntersectionOptions();options.curveRange = range
                let result = try intersector.intersectionResult(curve:curve,surface:plane,options:options,tolerance:.standard)
                try PolylineLiftProof.require(result.points.count == count)
                guard let geometry = result.originalIssuedGeometricRelation,let mapping = result.originalIssuedNumericalPoints else {
                    throw ExactScalarFailure.invalidEvidence
                }
                try PolylineLiftProof.require(mapping.count == count && geometry.isEmpty == (count == 0))
                if count == 1 { try PolylineLiftProof.require(result.points[0].curveParameter == 1 && geometry.exactPoints.count == 4) }
            }
            var options = CurveSurfaceIntersectionOptions();options.surfaceURange = try .init(lower:1,upper:2)
            let empty = try intersector.intersectionResult(curve:curve,surface:plane,options:options,tolerance:.standard)
            try PolylineLiftProof.require(empty.originalIssuedGeometricRelation?.isEmpty == true && empty.points.isEmpty)
            print("PASS ordinary public selections: endpoint singleton, root-free interval, outside-support request, whole-plane UV exclusion")
            return
        }
        let bare:[CurveSurfaceIntersection]
        do { let (curve,plane) = try input();bare = try intersector.intersections(curve:curve,surface:plane,options:.init(),tolerance:.standard) }
        try check(bare)
        let retained:PublicLiftPlanePort.CurveSurfaceIntersectionResult
        do {
            let (curve,plane) = try input()
            retained = try intersector.intersectionResult(curve:curve,surface:plane,tolerance:.standard)
            guard case .surfaceLift(let lift) = curve,case .polyline(let original) = lift.parameterCurve else {
                throw ExactScalarFailure.invalidEvidence
            }
            var changed = original;changed[2].u = 0.75
            try PolylineLiftProof.require(original[2].u == 0.5 && changed[2].u == 0.75)
        }
        try check(retained.points)
        guard let geometry = retained.originalIssuedGeometricRelation,let mapping = retained.originalIssuedNumericalPoints else {
            throw ExactScalarFailure.invalidEvidence
        }
        try PolylineLiftProof.require(retained.representation == .numericalRepresentatives && !geometry.isEmpty && !geometry.hasPositiveDimensionalSolutions)
        try PolylineLiftProof.require(geometry.exactPoints.count == 12 && mapping.count == 2)
        try PolylineLiftProof.require(mapping.incidenceRanges[0].count == 8 && mapping.incidenceRanges[1].count == 4)
        try PolylineLiftProof.require(Set(mapping.incidenceOrdinals) == Set(0..<12))
        var a = try PolylineLiftProof.Admission(work:8_388_608)
        let f = mapping.coordinates.field,one = try f.integer(1,using:&a),two = try f.integer(2,using:&a)
        let half = try f.dividing(one,two,using:&a),zero = try f.integer(0,using:&a)
        for group in mapping.incidenceRanges.indices {
            for index in mapping.incidenceRanges[group] {
                let ordinal = mapping.incidenceOrdinals[index],t = mapping.coordinates.values[6*ordinal]
                if group == 0 {
                    try PolylineLiftProof.require(f.sign(of:t,using:&a) == .positive)
                    try PolylineLiftProof.require(f.sign(of:f.subtracting(f.adding(f.multiplying(t,t,using:&a),f.multiplying(two,t,using:&a),using:&a),one,using:&a),using:&a) == .zero)
                } else { try PolylineLiftProof.require(f.compare(t,one,using:&a) == .equal) }
                try PolylineLiftProof.require(f.compare(mapping.coordinates.values[6*ordinal+1],zero,using:&a) == .equal)
                try PolylineLiftProof.require(f.compare(mapping.coordinates.values[6*ordinal+2],f.negated(half,using:&a),using:&a) == .equal)
                guard let original = geometry.exactPoints[ordinal].originalFirstCoordinates else { throw ExactScalarFailure.invalidEvidence }
                let q = geometry.exactPoints[ordinal].local.witness.field,qhalf = try q.dividing(q.integer(1,using:&a),q.integer(2,using:&a),using:&a)
                try PolylineLiftProof.require(original.count == 3 && q.compare(original[1],qhalf,using:&a) == .equal && q.compare(original[2],qhalf,using:&a) == .equal)
            }
        }
        try await withThrowingTaskGroup(of:Void.self) { group in
            for _ in 0..<2 {
                group.addTask {
                    var reader = try PolylineLiftProof.Admission(work:8_388_608)
                    let f = mapping.coordinates.field,one = try f.integer(1,using:&reader)
                    let ordinal = mapping.incidenceOrdinals[mapping.incidenceRanges[1].lowerBound]
                    try PolylineLiftProof.require(f.compare(mapping.coordinates.values[6*ordinal],one,using:&reader) == .equal)
                }
            }
            try await group.waitForAll()
        }
        print("PASS ordinary bare/rich public input: two distinct T roots; exact 8/4 incidence groups; original lift UV and plane UV; detached input/COW lifetime; concurrent independent readers")
    }
    static func main() async {
        do {
            #if PUBLIC_PROOF_ALL_MODES
            try await Task { try await run(.ordinary,normal:.unitX) }.value
            for mode in [Mode.ordinary,.selections,.resources,.cancelEntry,.cancelFinal] {
                try await Task { try await run(mode) }.value
            }
            #elseif !hasFeature(Embedded)
            if CommandLine.arguments.contains("unit-regression") { try await run(.ordinary,normal:.unitX) }
            else { try await run() }
            #else
            try await run()
            #endif
        }
        catch {
            print("FAIL ordinary lift/plane")
            #if !hasFeature(Embedded)
            print(error)
            #endif
            exit(1)
        }
    }
}
