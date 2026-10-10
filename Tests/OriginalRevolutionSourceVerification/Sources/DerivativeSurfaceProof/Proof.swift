import CADCore
@testable import CADGeometry
#if ORIGINAL_DERIVATIVE_SURFACE_ADAPTER_VERIFICATION
@testable import DerivativeSurfaceAdapters
import struct DerivativeSurfaceAdapters.OriginalPlaneDerivativeSurface3D
@testable import struct DerivativeSurfaceAdapters.OriginalCoonsRationalDifferentialAtlas
@testable import struct DerivativeSurfaceAdapters.OriginalBoundaryCorrectedRationalAtlas
#endif

@main
struct OriginalDerivativeSurfaceSourceProof {
    static func require(_ value: Bool, line: Int = #line) throws {
        guard value else { print("FAILED M4 derivative surface line \(line)"); throw ExactScalarFailure.invalidEvidence }
    }

    struct Admission: ~Copyable, ExactScalarAdmission {
        var ledger: ExactScalarLedger
        var storageCalls = 0
        let cancelAtStorage: Int?
        init(work: Int = 300_000_000, storage: Int = 1_073_741_824,
            cancelAtStorage: Int? = nil) throws {
            ledger = .init(limits: try .init(work: work, storageBytes: storage,
                valueDepth: 32, coefficientDepth: 32))
            self.cancelAtStorage = cancelAtStorage
        }
        mutating func checkpoint() throws(ExactScalarFailure) { try ledger.checkpoint() }
        mutating func consumeWork(_ units: Int) throws(ExactScalarFailure) { try ledger.consumeWork(units) }
        mutating func retainStorage(bytes: Int) throws(ExactScalarFailure) {
            try ledger.retainStorage(bytes: bytes)
            storageCalls += 1
            if storageCalls == cancelAtStorage { ledger.cancel() }
        }
        mutating func visitCell(axis: ExactScalarRootAxis, depth: Int) throws(ExactScalarFailure) {
            try ledger.visitCell(axis: axis, depth: depth)
        }
        mutating func admitDepth(value: Int, coefficient: Int) throws(ExactScalarFailure) {
            try ledger.admitDepth(value: value, coefficient: coefficient)
        }
    }

    static func shape<A: ExactScalarAdmission & ~Copyable>(weighted: Bool, projected: Bool,
        using a: inout A) throws -> OriginalPlaneDerivativeSurface3D {
        try ExactScalarNumericAccess.withAdmission(&a) { usage in
            let native = BSplineSurface3D(uDegree: 2, vDegree: 1,
                uKnots: [0,0,0,0.5,1,1,1], vKnots: [0,0,0.5,1,1], controlPoints: [
                    [.origin, .init(x:0.25,y:0,z:0), .init(x:0.75,y:0,z:0), .init(x:1,y:0,z:0)],
                    [.init(x:0,y:0.5,z:0), .init(x:0.25,y:0.5,z:0.125), .init(x:0.75,y:0.5,z:0.125), .init(x:1,y:0.5,z:0)],
                    [.init(x:0,y:1,z:0), .init(x:0.25,y:1,z:0.5), .init(x:0.75,y:1,z:0.5), .init(x:1,y:1,z:0)]],
                weights: [[1,1,1,1],[1,1,1,1],weighted ? [2,2,2,2]:[1,1,1,1]])
            let issuer = OriginalSurfaceBoundarySourceIssuer()
            func boundary(_ at: SurfaceParameterBoundary) throws -> OriginalCurveRootSpan3D {
                try issuer.boundary(of: .bSpline(native), at: at, maximumDepth: 0,
                    maximumSpanCount: 4, tolerance: .standard, usage: &usage)
            }
            let original = try OriginalCoonsSurface3D(vMinimumBoundary: boundary(.vLower),
                vMaximumBoundary: boundary(.vUpper), uMinimumBoundary: boundary(.uLower),
                uMaximumBoundary: boundary(.uUpper), tolerance: .standard, usage: &usage)
            let construction = try OriginalBoundaryCorrectedSurface3D(construction: native, boundaries: original,
                maximumSpanCount: 4, maximumSubdivisionDepth: 0, tolerance: .standard, usage: &usage)
            let constraints: [OriginalPlaneDerivativeConstraint] = projected ? [
                .init(surface: .plane(.init(origin: .origin, normal: .init(x:0,y:0,z:2))), order: .curvature)]:[]
            func connector(_ source: OriginalCurveRootSpan3D) throws -> OriginalCurveRootSpan3D {
                if !projected { return source }
                let curve = try OriginalPlaneDerivativeCurve3D(source: source, startConstraints: constraints,
                    endConstraints: constraints, tolerance: .standard, usage: &usage, remainingSourceDepth: 1)
                return try .init(source: .originalPlaneDerivative(curve), start: .authored(0), end: .authored(1),
                    maximumParameterWidth: ModelingTolerance.standard.relative, maximumSubdivisionDepth: 0,
                    tolerance: .standard, storageByteStride: MemoryLayout<UInt32>.stride, usage: &usage,
                    maximumSpanCount: 4, remainingSourceDepth: 1, maximumAlgebraicDepth: 0)
            }
            let final = try OriginalCoonsSurface3D(vMinimumBoundary: original.vMinimumBoundary,
                vMaximumBoundary: original.vMaximumBoundary, uMinimumBoundary: connector(original.uMinimumBoundary),
                uMaximumBoundary: connector(original.uMaximumBoundary), tolerance: .standard, usage: &usage)
            return try OriginalPlaneDerivativeSurface3D(construction: construction, boundaries: final,
                startConstraints: constraints, endConstraints: constraints, remainingSourceDepth: 2,
                tolerance: .standard, usage: &usage)
        }.value
    }

    static func expected(_ v: Double, weighted: Bool, projected: Bool) -> Double {
        let g = v <= 0.5 ? v : (weighted ? (7*v-3)/(2*v):3*v-1)
        if !projected { return g }
        let h10 = v-6*v*v*v+8*v*v*v*v-3*v*v*v*v*v
        let h11 = -4*v*v*v+7*v*v*v*v-3*v*v*v*v*v
        let h21 = 0.5*v*v*v-v*v*v*v+0.5*v*v*v*v*v
        return g-h10-(weighted ? 1.5:3)*h11+(weighted ? 3:0)*h21
    }

    static func correctedBase<A: ExactScalarAdmission & ~Copyable>(using a: inout A) throws -> OriginalBoundaryCorrectedSurface3D {
        try ExactScalarNumericAccess.withAdmission(&a) { usage in
            func span(_ points: [Point3D], degree: Int = 1) throws -> OriginalCurveRootSpan3D {
                let knots = Array(repeating: 0.0, count: degree+1)+Array(repeating: 1.0, count: degree+1)
                return try .init(source: .bSpline(.init(degree: degree, knots: knots, controlPoints: points)),
                    start: .authored(0), end: .authored(1), maximumParameterWidth: ModelingTolerance.standard.relative,
                    maximumSubdivisionDepth: 0, tolerance: .standard, storageByteStride: MemoryLayout<UInt32>.stride,
                    usage: &usage, maximumSpanCount: 1, remainingSourceDepth: 0, maximumAlgebraicDepth: 0)
            }
            let boundaries = try OriginalCoonsSurface3D(vMinimumBoundary: span([.origin,.init(x:0.5,y:0,z:0.25),.init(x:1,y:0,z:0)], degree: 2),
                vMaximumBoundary: span([.init(x:0,y:1,z:0),.init(x:1,y:1,z:0)]),
                uMinimumBoundary: span([.origin,.init(x:0,y:1,z:0)]),
                uMaximumBoundary: span([.init(x:1,y:0,z:0),.init(x:1,y:1,z:0)]), tolerance: .standard, usage: &usage)
            let native = BSplineSurface3D(uDegree: 1, vDegree: 1, uKnots: [0,0,1,1], vKnots: [0,0,1,1],
                controlPoints: [[.origin,.init(x:1,y:0,z:0)],[.init(x:0,y:1,z:0),.init(x:1,y:1,z:0)]])
            return try .init(construction: native, boundaries: boundaries, maximumSpanCount: 1,
                maximumSubdivisionDepth: 0, tolerance: .standard, usage: &usage)
        }.value
    }

    static func completeCover<A: ExactScalarAdmission & ~Copyable>(
        original: OriginalPlaneDerivativeSurface3D,
        provider: OriginalPlaneDerivativeSurfaceSnapshotProvider,
        limits: OriginalSourceIssuanceLimits, domainLimits: OriginalDomainIdentityLimits,
        using a: inout A) throws -> OriginalRetainedSurfaceDomainCover<OriginalPlaneDerivativeSurfaceSnapshot> {
        let source = try DefaultOriginalSourceBindingIssuer(provider: provider).bind(original, limits: limits, using: &a)
        try require(source.original.original == original)
        let family = try DefaultOriginalFiniteRetainedSurfaceChartPreparer<OriginalPlaneDerivativeSurfaceSnapshot>()
            .prepare(source: source, maximumCharts: 4, limits: limits, using: &a)
        try family.admitProof(limits: limits, using: &a)
        let issuer = DefaultOriginalRetainedSurfaceDomainIssuer<OriginalPlaneDerivativeSurfaceSnapshot>()
        let frame = try issuer.frame(family: family, limits: domainLimits, using: &a)
        let full = try frame.fullSelection(limits: domainLimits, using: &a)
        let cover = try issuer.issue(request: full, family: family, limits: domainLimits, using: &a)
        try require(cover.templateCount == 4 && cover.selectedMembers(limits: domainLimits, using: &a).count == 4)
        try require(cover.effective.equals(full, limits: domainLimits, using: &a))
        let half = try provider.field.binary64(exactly: 0.5, using: &a)
        let singleton = try frame.selection(intervals: [[.checked(field: provider.field, lower: .finite(half),
            upper: .finite(half), depth: .init(value: 0, coefficient: 0), using: &a)],
            [.checked(field: provider.field, lower: .finite(half), upper: .finite(half),
            depth: .init(value: 0, coefficient: 0), using: &a)]], limits: domainLimits, using: &a)
        try require(issuer.issue(request: singleton, family: family, limits: domainLimits, using: &a)
            .incident(at: [half,half], limits: domainLimits, using: &a).count == 4)
        let zero = try provider.field.integer(0, using: &a)
        let one = try provider.field.integer(1, using: &a)
        let third = try provider.field.dividing(one, provider.field.integer(3, using: &a), using: &a)
        let twoThirds = try provider.field.adding(third, third, using: &a)
        let strict = try frame.selection(intervals: [[.checked(field: provider.field,
            lower: .finite(third), upper: .finite(twoThirds), includesLower: false, includesUpper: false,
            depth: .init(value: 0, coefficient: 0), using: &a)],
            [.checked(field: provider.field, lower: .finite(zero), upper: .finite(one),
            depth: .init(value: 0, coefficient: 0), using: &a)]], limits: domainLimits, using: &a)
        let clipped = try issuer.issue(request: strict, family: family, limits: domainLimits, using: &a)
        try require(clipped.incident(at: [third,half], limits: domainLimits, using: &a).isEmpty)
        try require(clipped.incident(at: [twoThirds,half], limits: domainLimits, using: &a).isEmpty)
        try require(clipped.incident(at: [half,half], limits: domainLimits, using: &a).count == 4)
        let disconnected = try frame.selection(intervals: [[
            .checked(field: provider.field, lower: .finite(zero), upper: .finite(third),
                depth: .init(value: 0, coefficient: 0), using: &a),
            .checked(field: provider.field, lower: .finite(twoThirds), upper: .finite(one),
                depth: .init(value: 0, coefficient: 0), using: &a)],
            [.checked(field: provider.field, lower: .finite(half), upper: .finite(half),
                depth: .init(value: 0, coefficient: 0), using: &a)]], limits: domainLimits, using: &a)
        let separate = try issuer.issue(request: disconnected, family: family, limits: domainLimits, using: &a)
        try require(separate.incident(at: [half,half], limits: domainLimits, using: &a).isEmpty)
        try require(separate.incident(at: [third,half], limits: domainLimits, using: &a).count == 2)
        try require(separate.incident(at: [twoThirds,half], limits: domainLimits, using: &a).count == 2)
        let empty = try frame.selection(intervals: [[],[]], limits: domainLimits, using: &a)
        let excluded = try issuer.issue(request: empty, family: family, limits: domainLimits, using: &a)
        try require(excluded.selectedMembers(limits: domainLimits, using: &a).isEmpty
            && excluded.incident(at: [half,half], limits: domainLimits, using: &a).isEmpty)
        return cover
    }

    static func main() throws {
        var a = ExactScalarLedger(limits: try .init(work: 300_000_000, storageBytes: 1_073_741_824,
            valueDepth: 32, coefficientDepth: 32))
        let f = try OriginalExactScalarDomain(maximumValueDepth: 32, maximumCoefficientDepth: 32, using: &a)
        let limits = try OriginalSourceIssuanceLimits(remainingSourceDepth: 2)
        let provider = OriginalPlaneDerivativeSurfaceSnapshotProvider(field: f, tolerance: .standard)
        let domainLimits = try OriginalDomainIdentityLimits(source: limits, maximumTransportDepth: 16,
            maximumCharts: 8, maximumFamilies: 1, maximumIdentityProofs: 16)
        let transport = DefaultOriginalParameterTransporter<OriginalPlaneDerivativeSurfaceSnapshot,OriginalExactScalarDomain>()
        var retained: OriginalRetainedSurfaceDomainCover<OriginalPlaneDerivativeSurfaceSnapshot>?
        var budgetOriginal: OriginalPlaneDerivativeSurface3D?
        for weighted in [false,true] { for projected in [false,true] {
            print("CASE derivative surface weighted=\(weighted) projected=\(projected)")
            let original = try shape(weighted: weighted, projected: projected, using: &a)


            let cover = try completeCover(original: original, provider: provider, limits: limits,
                domainLimits: domainLimits, using: &a)
            try require(cover.family.laws.count == 4)
            retained = cover
            if !weighted && !projected { budgetOriginal = original }
            var copiedNative = original.construction.construction
            copiedNative.controlPoints[0][0] = .init(x: 9, y: 9, z: 9)
            try require(cover.source.original.original.construction.construction.controlPoints[0][0] == .origin)
            for u in [0.0,0.25,0.5,0.75,1.0] { for v in [0.0,0.25,0.5,0.75,1.0] {
                let parameters = [try f.binary64(exactly: u, using: &a), try f.binary64(exactly: v, using: &a)]
                let z = u*(1-u)*expected(v, weighted: weighted, projected: projected)
                var incidents = 0
                for occurrence in try cover.incident(at: parameters, limits: domainLimits, using: &a) {
                    let local = try transport.forward(parameters, through: transport.inverse(occurrence.transport,
                        limits: domainLimits, using: &a), limits: domainLimits, using: &a)
                    try require(f.compare(local[0], parameters[0], using: &a) == .equal
                        && f.compare(local[1], parameters[1], using: &a) == .equal)
                    incidents += 1
                    let law = occurrence.law
                    let r = law.polynomials
                    let denominator = try r.evaluated(law.denominator, at: local, using: &a).value
                    let exactZ = try f.dividing(r.evaluated(law.homogeneous[2], at: local, using: &a).value,
                        denominator, using: &a)
                    try require(f.compare(exactZ, f.binary64(exactly: z, using: &a), using: &a) == .equal)
                }
                try require(incidents == (v == 0.5 ? 2:1)*(u == 0.5 ? 2:1))
                let actual = try original.point(u: u, v: v, tolerance: .standard)
                try require(abs(actual.z-z)<1e-9 && abs(actual.x-u)<1e-9)
            } }
            let derivatives = try original.parameterDerivatives(u: 0.5, v: 0.25, tolerance: .standard)
            let expectedV = projected ? (weighted ? 1.36328125:1.796875)*0.25:0.25
            try require(abs(derivatives.tangentV.z-expectedV)<1e-9)
            do { _ = try original.parameterDerivatives(u: 0.5, v: 0.5, tolerance: .standard); throw ExactScalarFailure.invalidEvidence }
            catch let failure as KernelError { try require(failure.code == .singularGeometry) }
            do { _ = try provider.snapshot(original, limits: .init(remainingSourceDepth: 1), using: &a); throw ExactScalarFailure.invalidEvidence }
            catch OriginalSourceIssuanceFailure.sourceDepthLimit {}
            var noStorage = ExactScalarLedger(limits: try .init(work: 300_000_000, storageBytes: 0, valueDepth: 32, coefficientDepth: 32))
            do { _ = try provider.snapshot(original, limits: limits, using: &noStorage); throw ExactScalarFailure.invalidEvidence }
            catch OriginalSourceIssuanceFailure.scalar(.resourceLimit(.storage)) {}
            let changed = ModelingTolerance(distance: 2*ModelingTolerance.standard.distance,
                angle: ModelingTolerance.standard.angle, relative: ModelingTolerance.standard.relative)
            do { _ = try OriginalPlaneDerivativeSurfaceSnapshotProvider(field: f, tolerance: changed)
                .snapshot(original, limits: limits, using: &a); throw ExactScalarFailure.invalidEvidence }
            catch OriginalSourceIssuanceFailure.sourceRejected {}
            let atlas = try ExactScalarNumericAccess.withAdmission(&a) { usage in
                try OriginalCoonsRationalDifferentialAtlas.prepared(.bSpline(original.construction.construction),
                    maximumSpanCount: 4, tolerance: .standard, usage: &usage)
            }.value
            guard let atlas else { throw ExactScalarFailure.invalidEvidence }
            try require(atlas.cells.count == 4)
            for cell in atlas.cells { try require(cell.originalConstructionHomogeneous == cell.homogeneous) }
            let nativeFields = try ExactScalarNumericAccess.withAdmission(&a) { usage in
                try atlas.fields(over: .init(u: .init(lower:0.25,upper:0.25),v: .init(lower:0.25,upper:0.25)), usage: &usage)
            }.value
            try require(nativeFields.count == 1 && nativeFields[0].normal[2].lower > 0)
            let coons = try ExactScalarNumericAccess.withAdmission(&a) { usage in
                try OriginalCoonsRationalDifferentialAtlas.prepared(original.construction.boundaries, usage: &usage)
            }.value
            guard let coons else { throw ExactScalarFailure.invalidEvidence }
            for cell in coons.cells { try require(cell.originalConstructionHomogeneous == cell.homogeneous) }
            let coonsFields = try ExactScalarNumericAccess.withAdmission(&a) { usage in
                try coons.fields(over: .init(u: .init(lower:0.25,upper:0.25),v: .init(lower:0.25,upper:0.25)), usage: &usage)
            }.value
            try require(coonsFields.count == 1 && coonsFields[0].normal[2].lower > 0)
        } }
        guard let retained else { throw ExactScalarFailure.invalidEvidence }
        let half = try f.dividing(f.integer(1, using: &a), f.integer(2, using: &a), using: &a)
        try require(retained.incident(at: [half,half], limits: domainLimits, using: &a).count == 4)
        guard let original = budgetOriginal else { throw ExactScalarFailure.invalidEvidence }
        var measured = try Admission()
        _ = try provider.snapshot(original, limits: limits, using: &measured)
        let work = measured.ledger.work, bytes = measured.ledger.storageBytes
        print("BUDGET measured work=\(work) bytes=\(bytes) callbacks=\(measured.storageCalls)")
        var exact = try Admission(work: work, storage: bytes)
        _ = try provider.snapshot(original, limits: limits, using: &exact)
        print("BUDGET exact work=\(exact.ledger.work) bytes=\(exact.ledger.storageBytes) callbacks=\(exact.storageCalls)")
        var shortWork = try Admission(work: work-1, storage: bytes)
        do { _ = try provider.snapshot(original, limits: limits, using: &shortWork); throw ExactScalarFailure.invalidEvidence }
        catch OriginalSourceIssuanceFailure.scalar(.resourceLimit(.work)) {}
        catch OriginalSourceIssuanceFailure.polynomial(.scalar(.resourceLimit(.work))) {}
        var shortStorage = try Admission(work: work, storage: bytes-1)
        do { _ = try provider.snapshot(original, limits: limits, using: &shortStorage); throw ExactScalarFailure.invalidEvidence }
        catch OriginalSourceIssuanceFailure.scalar(.resourceLimit(.storage)) {}
        catch OriginalSourceIssuanceFailure.polynomial(.scalar(.resourceLimit(.storage))) {}
        var entry = try Admission()
        entry.ledger.cancel()
        do { _ = try provider.snapshot(original, limits: limits, using: &entry); throw ExactScalarFailure.invalidEvidence }
        catch OriginalSourceIssuanceFailure.scalar(.cancelled) {}
        var terminal = try Admission(cancelAtStorage: measured.storageCalls)
        do { _ = try provider.snapshot(original, limits: limits, using: &terminal); throw ExactScalarFailure.invalidEvidence }
        catch OriginalSourceIssuanceFailure.scalar(.cancelled) {}
        print("PASS derivative source exact work/storage ceilings, entry/final callback cancel, COW and post-scope lifetime")
        let corrected = try correctedBase(using: &a)
        let atlas = try ExactScalarNumericAccess.withAdmission(&a) { usage in
            try OriginalBoundaryCorrectedRationalAtlas.prepared(corrected, usage: &usage)
        }.value
        guard let atlas else { throw ExactScalarFailure.invalidEvidence }
        try require(atlas.cells.count == 1)
        let z = try ExactScalarNumericAccess.withAdmission(&a) { usage in
            let half = try ExactRationalCoefficient.one.divided(by: .natural(2, usage: &usage), usage: &usage)
            let cell = atlas.cells[0]
            return (try cell.originalConstructionHomogeneous[2].evaluated(atU: half, v: .zero, usage: &usage),
                try cell.homogeneous[2].evaluated(atU: half, v: .zero, usage: &usage))
        }.value
        try require(z.0.isZero && !z.1.isZero)
        let correctionFields = try ExactScalarNumericAccess.withAdmission(&a) { usage in
            try atlas.fields(over: .init(u: .init(lower:0.25,upper:0.25),v: .init(lower:0.25,upper:0.25)), usage: &usage)
        }.value
        try require(correctionFields.count == 1 && correctionFields[0].normal[2].lower > 0)
        try require(abs(corrected.point(u:0.5,v:0,tolerance:.standard).z-0.125)<1e-9)
        var noStorage = ExactScalarLedger(limits: try .init(work: 300_000_000, storageBytes: 0, valueDepth: 32, coefficientDepth: 32))
        do { _ = try OriginalBoundaryCorrectionSnapshotProvider(field:f,tolerance:.standard)
            .snapshot(corrected,limits:.init(remainingSourceDepth:1),using:&noStorage); throw ExactScalarFailure.invalidEvidence }
        catch OriginalSourceIssuanceFailure.scalar(.resourceLimit(.storage)) {}
        _ = try ExactScalarNumericAccess.withAdmission(&a) { usage in
            let discontinuous = BSplineSurface3D(uDegree:1,vDegree:1,uKnots:[0,0,0.5,0.5,1,1],vKnots:[0,0,1,1],
                controlPoints:[
                    [.origin,.init(x:0.5,y:0,z:0),.init(x:0.5,y:0,z:1),.init(x:1,y:0,z:1)],
                    [.init(x:0,y:1,z:0),.init(x:0.5,y:1,z:0),.init(x:0.5,y:1,z:1),.init(x:1,y:1,z:1)]])
            do { _ = try OriginalBoundaryCorrectedSurface3D(construction:discontinuous,boundaries:corrected.boundaries,
                maximumSpanCount:4,maximumSubdivisionDepth:0,tolerance:.standard,usage:&usage)
                throw ExactScalarFailure.invalidEvidence
            } catch GeometryError.invalidDistance(let multiplicity) { try require(multiplicity == 2) }
        }
        let slot = MemoryLayout<OriginalCoonsRationalDifferentialAtlas.Cell>.stride
        var exactSlot = ExactScalarLedger(limits: try .init(work:100,storageBytes:slot,valueDepth:0,coefficientDepth:0))
        _ = try ExactScalarNumericAccess.withAdmission(&exactSlot) { usage in
            try RationalAlgebraStorage.retain(1,of:OriginalCoonsRationalDifferentialAtlas.Cell.self,usage:&usage)
        }
        var smallSlot = ExactScalarLedger(limits: try .init(work:100,storageBytes:slot-1,valueDepth:0,coefficientDepth:0))
        do { _ = try ExactScalarNumericAccess.withAdmission(&smallSlot) { usage in
            try RationalAlgebraStorage.retain(1,of:OriginalCoonsRationalDifferentialAtlas.Cell.self,usage:&usage)
        }; throw ExactScalarFailure.invalidEvidence }
        catch ExactScalarFailure.resourceLimit(.storage) {}
        print("PASS M4 actual derivative surface, complete retained source-to-DI cover and UV/lifetime, weighted original D1/D2, public position/derivatives and explicit source/storage failure")
    }
}
