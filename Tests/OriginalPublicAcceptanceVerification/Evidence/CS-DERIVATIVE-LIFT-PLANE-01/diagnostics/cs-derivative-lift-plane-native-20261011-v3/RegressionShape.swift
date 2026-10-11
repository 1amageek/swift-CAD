import CADCore
@testable import CADGeometry
struct PolylineAtlasLiftProof {
    typealias Admission = DerivativeLiftPlaneAcceptance.Admission
    nonisolated static func shape(multi: Bool,using a: inout Admission) throws -> (OriginalCoonsSurface3D,OriginalBoundaryCorrectedSurface3D) {
        try ExactScalarNumericAccess.withAdmission(&a) { usage in
            let t=multi ? [0.0,0.5,1.0]:[0.0,1.0],knots=multi ? [0.0,0,0.5,1,1]:[0.0,0,1,1]
            let native=BSplineSurface3D(uDegree:1,vDegree:1,uKnots:knots,vKnots:knots,
                controlPoints:t.map { v in t.map { u in .init(x:u,y:v,z:0) } })
            let issuer=OriginalSurfaceBoundarySourceIssuer()
            func boundary(_ b: SurfaceParameterBoundary) throws -> OriginalCurveRootSpan3D {
                try issuer.boundary(of:.bSpline(native),at:b,maximumDepth:0,maximumSpanCount:4,tolerance:.standard,usage:&usage)
            }
            let lower: OriginalCurveRootSpan3D
            if multi { lower=try boundary(.vLower) }
            else {
                lower=try .init(source:.bSpline(.init(degree:2,knots:[0,0,0,1,1,1],
                    controlPoints:[.origin,.init(x:0.5,y:0,z:0.25),.init(x:1,y:0,z:0)])),start:.authored(0),end:.authored(1),
                    maximumParameterWidth:ModelingTolerance.standard.relative,maximumSubdivisionDepth:0,tolerance:.standard,
                    storageByteStride:MemoryLayout<UInt32>.stride,usage:&usage,maximumSpanCount:1,remainingSourceDepth:0,maximumAlgebraicDepth:0)
            }
            let coons=try OriginalCoonsSurface3D(vMinimumBoundary:lower,vMaximumBoundary:boundary(.vUpper),
                uMinimumBoundary:boundary(.uLower),uMaximumBoundary:boundary(.uUpper),tolerance:.standard,usage:&usage)
            let correction=try OriginalBoundaryCorrectedSurface3D(construction:native,boundaries:coons,
                maximumSpanCount:4,maximumSubdivisionDepth:0,tolerance:.standard,usage:&usage)
            return (coons,correction)
        }.value
    }
}
struct PolylineLiftProof {
    nonisolated static func points(periodic: Bool=false) -> [SurfaceParameter] {
        let h=periodic ? 3.0:0.5
        return [.init(u:0,v:0),.init(u:0,v:0),.init(u:h,v:h),.init(u:2*h,v:h),.init(u:h,v:h)]
    }
}
