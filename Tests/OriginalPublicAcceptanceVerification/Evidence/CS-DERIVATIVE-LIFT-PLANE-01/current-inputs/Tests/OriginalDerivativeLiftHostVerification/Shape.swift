import CADCore
@testable import CADGeometry

struct DerivativeHostShape {
    nonisolated static func shape<A: ExactScalarAdmission & ~Copyable>(weighted: Bool, projected: Bool,
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

    nonisolated static func expected(_ v: Double, weighted: Bool, projected: Bool) -> Double {
        let g = v <= 0.5 ? v : (weighted ? (7*v-3)/(2*v):3*v-1)
        if !projected { return g }
        let h10 = v-6*v*v*v+8*v*v*v*v-3*v*v*v*v*v
        let h11 = -4*v*v*v+7*v*v*v*v-3*v*v*v*v*v
        let h21 = 0.5*v*v*v-v*v*v*v+0.5*v*v*v*v*v
        return g-h10-(weighted ? 1.5:3)*h11+(weighted ? 3:0)*h21
    }

}
