#if canImport(Foundation)
import Foundation
#else
import WASILibc
#endif
import CADCore
import CADGeometry

/// Whole original drafted-wall regularity under the existing native-sheet thresholds.
package struct OriginalDraftedSurfaceRegularity {
    private struct Cell { let box:SurfaceParameterBox; let depth:Int }
    package init() {}
    package func validate(_ surface:OriginalDraftedRuledSurface3D,tolerance:ModelingTolerance,
        using execution:inout OriginalQueryExecution) throws {
        try surface.validate(tolerance:tolerance,using:&execution)
        let depthLimit = min(18,execution.effectiveLimits.maximumSubdivisionDepth)
        try execution.retainStorage(bytes:(depthLimit+1)*MemoryLayout<Cell>.stride)
        var pending:[Cell] = [];pending.reserveCapacity(depthLimit+1)
        pending.append(.init(box:try .init(u:.init(lower:0,upper:1),v:.init(lower:0,upper:1)),depth:0))
        var visited = 0
        let angularTolerance = max(sin(min(tolerance.angle,Double.pi*0.5)),tolerance.relative,Double.ulpOfOne*256)
        while let cell = pending.popLast() {
            guard visited < 262_144 else { throw GeometryConversionError.resourceLimitExceeded("Original draft regularity exhausted the unchanged native-sheet cell allowance.") }
            visited += 1;try execution.visitGeometricCell(depth:cell.depth)
            let q = try surface.intervalTaylorJet(over:cell.box,throughOrder:1,tolerance:tolerance,
                maximumSpanCount:execution.effectiveLimits.maximumSpans,maximumSubdivisionDepth:execution.effectiveLimits.maximumSubdivisionDepth-cell.depth,
                remainingSourceDepth:execution.effectiveLimits.remainingSourceDepth,using:&execution)
            let u = try IntervalVector3DBounds(x:q.x.coefficient(1,0),y:q.y.coefficient(1,0),z:q.z.coefficient(1,0))
            let v = try IntervalVector3DBounds(x:q.x.coefficient(0,1),y:q.y.coefficient(0,1),z:q.z.coefficient(0,1))
            try execution.consumeWork(3)
            let n = IntervalVector3DBounds(x:u.y*v.z-u.z*v.y,y:u.z*v.x-u.x*v.z,z:u.x*v.y-u.y*v.x)
            let denominator = (u.lengthUpperBound*v.lengthUpperBound).nextUp
            let angularLower = denominator > 0 ? max(0,(n.lengthLowerBound/denominator).nextDown) : 0
            if u.lengthLowerBound > tolerance.distance, v.lengthLowerBound > tolerance.distance,
                angularLower > angularTolerance { continue }
            if u.lengthUpperBound <= tolerance.distance || v.lengthUpperBound <= tolerance.distance {
                throw KernelError(phase:.geometry,code:.singularGeometry,tolerance:tolerance,
                    message:"Original draft proves a collapsed wall tangent on its retained parameter domain.")
            }
            let alongU = cell.box.u.width >= cell.box.v.width
            let interval = alongU ? cell.box.u : cell.box.v
            let middle = interval.midpoint
            guard cell.depth < depthLimit,middle > interval.lower,middle < interval.upper else {
                throw GeometryConversionError.resourceLimitExceeded("Original draft regularity remains inconclusive at the unchanged native-sheet depth limit.")
            }
            let first = try ScalarInterval(lower:interval.lower,upper:middle)
            let second = try ScalarInterval(lower:middle,upper:interval.upper)
            let a = try SurfaceParameterBox(u:alongU ? first : cell.box.u,v:alongU ? cell.box.v : first)
            let b = try SurfaceParameterBox(u:alongU ? second : cell.box.u,v:alongU ? cell.box.v : second)
            pending.append(.init(box:b,depth:cell.depth+1));pending.append(.init(box:a,depth:cell.depth+1))
        }
    }
}
