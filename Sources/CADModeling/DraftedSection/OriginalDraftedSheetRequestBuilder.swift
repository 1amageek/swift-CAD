import CADCore
import CADGeometry
import CADIR
import CADTopology

/// Constructs original ruled-wall topology after whole original regularity admission.
package struct OriginalDraftedSheetRequestBuilder {
    package init() {}

    /// Retains the original cap plane translated along the exact normalized raw axis.
    package func capSupport(plane: Plane3D, axis: Vector3D, height: Double,
        tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution) throws -> Surface3D {
        try execution.consumeWork(1)
        guard axis.x.isFinite, axis.y.isFinite, axis.z.isFinite, height.isFinite,
              max(abs(axis.x), max(abs(axis.y), abs(axis.z))) > 0 else {
            throw GeometryConversionError.invalidInput("An original cap requires a finite height and nonzero raw axis.")
        }
        let reference: Vector3D
        if abs(axis.x) <= min(abs(axis.y), abs(axis.z)) { reference = .unitX }
        else if abs(axis.y) <= abs(axis.z) { reference = .unitY }
        else { reference = .unitZ }
        let frame = OriginalNormalizedAffineSource(family: .axis2, location: .zero,
            axis1: reference, axis2: nil, axis3: axis, scale: nil,
            lengthGain: .one, adjustments: [])
        let translation = try AffineTransform3D(basisX: .unitX, basisY: .unitY,
            basisZ: .unitZ, translation: .init(x: 0, y: 0, z: height))
        try execution.retainStorage(bytes: 3 * MemoryLayout<OriginalAffineOperation>.stride)
        let word = try OriginalAffineOperationWord(factors: [.normalizedInverse(frame),
            .forward(translation), .normalizedForward(frame)], tolerance: tolerance,
            maximumDepth: min(32, execution.effectiveLimits.maximumValueDepth), usage: &execution)
        return .procedural(.originalAffineWord(try OriginalAffineWordSurface3D(
            source: .plane(plane), operationWord: word, tolerance: tolerance,
            remainingSourceDepth: execution.effectiveLimits.remainingSourceDepth,
            maximumSubdivisionDepth: execution.effectiveLimits.maximumSubdivisionDepth,
            maximumAlgebraicDepth: execution.effectiveLimits.maximumValueDepth, usage: &execution)))
    }
    package func request(walls:[OriginalDraftedRuledSurface3D],featureID:FeatureID,
        tolerance:ModelingTolerance,using execution:inout OriginalQueryExecution,
        orientation:Orientation = .forward, loopWallCounts: [Int]? = nil) throws -> BRepSewingRequest {
        guard !walls.isEmpty else { throw GeometryConversionError.invalidInput("Original drafted sheet has no retained source walls.") }
        if let loopWallCounts {
            var total = 0
            for count in loopWallCounts {
                try execution.consumeWork(1)
                let next = total.addingReportingOverflow(count)
                guard count > 0, !next.overflow, next.partialValue <= walls.count else {
                    throw GeometryConversionError.invalidInput("Original sheet loop partition does not cover its retained walls.")
                }
                total = next.partialValue
            }
            guard total == walls.count else {
                throw GeometryConversionError.invalidInput("Original sheet loop partition omits retained walls.")
            }
        }
        try RationalAlgebraStorage.retain(walls.count, of: BRepSewingFacePatch.self, usage: &execution)
        var patches:[BRepSewingFacePatch] = [];patches.reserveCapacity(walls.count)
        for (index,wall) in walls.enumerated() {
            try execution.consumeWork(1)
            try OriginalDraftedSurfaceRegularity().validate(wall,tolerance:tolerance,using:&execution)
            let surface = Surface3D.procedural(.originalDrafted(wall))
            let prefix = "extrude:curve:patch:\(index)"
            try execution.retainStorage(bytes:4*(MemoryLayout<SurfaceParameterCurve>.stride+MemoryLayout<Point3D>.stride+MemoryLayout<BRepSewingEdge>.stride))
            let curves:[SurfaceParameterCurve] = [
                .constantV(v:0,uStart:0,uEnd:1),.constantU(u:1,vStart:0,vEnd:1),
                .constantV(v:1,uStart:1,uEnd:0),.constantU(u:0,vStart:1,vEnd:0)
            ]
            let roles = ["vMin","uMax","vMax","uMin"]
            func point(_ u:Double,_ v:Double) throws -> Point3D {
                let q = try wall.intervalTaylorJet(over:.init(u:.init(lower:u,upper:u),v:.init(lower:v,upper:v)),
                    throughOrder:0,tolerance:tolerance,maximumSpanCount:execution.effectiveLimits.maximumSpans,
                    maximumSubdivisionDepth:execution.effectiveLimits.maximumSubdivisionDepth,remainingSourceDepth:execution.effectiveLimits.remainingSourceDepth,
                    using:&execution)
                let x = try q.x.coefficient(0,0),y = try q.y.coefficient(0,0),z = try q.z.coefficient(0,0)
                let candidate = Point3D(x:x.midpoint,y:y.midpoint,z:z.midpoint)
                guard IntervalVector3DBounds(x:x - .exact(candidate.x),y:y - .exact(candidate.y),z:z - .exact(candidate.z)).lengthUpperBound <= tolerance.distance*0.25 else {
                    throw GeometryConversionError.toleranceRejected
                }
                return candidate
            }
            let points = try [point(0,0),point(1,0),point(1,1),point(0,1)]
            var edges:[BRepSewingEdge] = [];edges.reserveCapacity(4)
            for i in 0..<4 {
                try execution.consumeWork(1)
                let lift = Curve3D.surfaceLift(.init(surface:surface,parameterCurve:curves[i]))
                edges.append(try BRepSewingEdge(stableID:"\(prefix):edge:\(roles[i])",curve:lift,
                    startParameter:0,endParameter:1,startPoint:points[i],endPoint:points[(i+1)%4],
                    surfaceParameterCurve:curves[i],using:&execution))
            }
            try execution.retainStorage(bytes:MemoryLayout<BRepSewingLoop>.stride)
            let patch = try BRepSewingFacePatch(stableID:prefix,surface:surface,orientation:orientation,
                loops:[.init(stableID:"\(prefix):loop",role:.outer,edges:edges)],
                using:&execution)
            try patch.validate(tolerance:tolerance,maximumSpanCount:execution.effectiveLimits.maximumSpans,
                maximumSubdivisionDepth:execution.effectiveLimits.maximumSubdivisionDepth,remainingSourceDepth:min(16,execution.effectiveLimits.remainingSourceDepth),
                maximumAlgebraicDepth:execution.effectiveLimits.maximumValueDepth,
                using:&execution)
            patches.append(patch)
        }
        if let loopWallCounts {
            try RationalAlgebraStorage.retain(loopWallCounts.count, of: BRepSewingShell.self, usage: &execution)
            var shells: [BRepSewingShell] = []; shells.reserveCapacity(loopWallCounts.count)
            var first = 0
            for (index, count) in loopWallCounts.enumerated() {
                try execution.consumeWork(count)
                try RationalAlgebraStorage.retain(count, of: BRepSewingFacePatch.self, usage: &execution)
                let end = first + count
                shells.append(.init(stableID: "extrude:curve:shell:\(index)",
                    patches: Array(patches[first..<end])))
                first = end
            }
            return .init(featureID: featureID, bodyKind: .sheet, shells: shells)
        }
        try execution.retainStorage(bytes:MemoryLayout<BRepSewingShell>.stride)
        return .init(featureID:featureID,bodyKind:.sheet,
            shells:[.init(stableID:"extrude:curve:shell",patches:patches)])
    }
}
