import CADCore

extension OriginalPlaneDerivativeSurface3D {
    package func intervalJet(over box: SurfaceParameterBox, tolerance: ModelingTolerance)
        throws -> SurfaceIntervalVectorJet {
        try intervalJet(over: box, tolerance: tolerance, maximumSpanCount: maximumSpanCount,
            maximumSubdivisionDepth: maximumSubdivisionDepth, remainingSourceDepth: remainingSourceDepth, consumeWork: {})
    }

    public func point(u: Double, v: Double, tolerance: ModelingTolerance) throws -> Point3D {
        try point(u: u, v: v, tolerance: tolerance, consumeWork: {})
    }
    package func point(u: Double, v: Double, tolerance: ModelingTolerance,
        consumeWork: () throws -> Void) throws -> Point3D {
        let q = try intervalTaylorJet(over: .init(u: .init(lower: u, upper: u), v: .init(lower: v, upper: v)),
            throughOrder: 0, tolerance: tolerance, maximumSpanCount: maximumSpanCount,
            maximumSubdivisionDepth: maximumSubdivisionDepth, remainingSourceDepth: remainingSourceDepth,
            consumeWork: consumeWork)
        return try numericalPosition(x: q.x.coefficient(0, 0), y: q.y.coefficient(0, 0),
            z: q.z.coefficient(0, 0), tolerance: tolerance)
    }
    public func parameterDerivatives(u: Double, v: Double, tolerance: ModelingTolerance)
        throws -> SurfaceParameterDerivatives {
        let q = try intervalTaylorJet(over:.init(u:.init(lower:u,upper:u),v:.init(lower:v,upper:v)),
            throughOrder:2,tolerance:tolerance,maximumSpanCount:maximumSpanCount,
            maximumSubdivisionDepth:maximumSubdivisionDepth,remainingSourceDepth:remainingSourceDepth,consumeWork:{})
        func vector(_ uOrder:Int,_ vOrder:Int,_ scale:Double) throws -> Vector3D {
            .init(x:try q.x.coefficient(uOrder,vOrder).midpoint*scale,
                y:try q.y.coefficient(uOrder,vOrder).midpoint*scale,
                z:try q.z.coefficient(uOrder,vOrder).midpoint*scale)
        }
        return try .init(position:numericalPosition(x:q.x.coefficient(0,0),y:q.y.coefficient(0,0),
            z:q.z.coefficient(0,0),tolerance:tolerance),tangentU:vector(1,0,1),tangentV:vector(0,1,1),
            secondDerivativeUU:vector(2,0,2),secondDerivativeUV:vector(1,1,1),secondDerivativeVV:vector(0,2,2))
    }
    public func parameterDerivativesThroughThirdOrder(u: Double, v: Double,
        tolerance: ModelingTolerance) throws -> SurfaceParameterThirdOrderDerivatives {
        let q = try intervalJet(over: .init(u: .init(lower: u, upper: u), v: .init(lower: v, upper: v)), tolerance: tolerance)
        func vector(_ field: (SurfaceIntervalJet) -> OutwardScalarInterval) -> Vector3D {
            .init(x: field(q.x).midpoint, y: field(q.y).midpoint, z: field(q.z).midpoint)
        }
        return try .init(position: numericalPosition(x: q.x.value, y: q.y.value, z: q.z.value, tolerance: tolerance),
            tangentU: vector { $0.derivativeU }, tangentV: vector { $0.derivativeV },
            secondDerivativeUU: vector { $0.secondDerivativeUU }, secondDerivativeUV: vector { $0.secondDerivativeUV },
            secondDerivativeVV: vector { $0.secondDerivativeVV }, thirdDerivativeUUU: vector { $0.thirdDerivativeUUU },
            thirdDerivativeUUV: vector { $0.thirdDerivativeUUV }, thirdDerivativeUVV: vector { $0.thirdDerivativeUVV },
            thirdDerivativeVVV: vector { $0.thirdDerivativeVVV })
    }
    private func numericalPosition(x: OutwardScalarInterval, y: OutwardScalarInterval,
        z: OutwardScalarInterval, tolerance: ModelingTolerance) throws -> Point3D {
        let point = Point3D(x: x.midpoint, y: y.midpoint, z: z.midpoint)
        let radius = IntervalVector3DBounds(x: x - .exact(point.x), y: y - .exact(point.y), z: z - .exact(point.z)).lengthUpperBound
        guard radius.isFinite, radius <= tolerance.distance else { throw GeometryConversionError.toleranceRejected }
        return point
    }

    package func intervalJet(over box: SurfaceParameterBox, tolerance: ModelingTolerance,
        maximumSpanCount: Int, maximumSubdivisionDepth: Int, remainingSourceDepth: Int,
        consumeWork: () throws -> Void, consumeStorage: ((Int) throws -> Void)? = nil)
        throws -> SurfaceIntervalVectorJet {
        try intervalTaylorJet(over: box, throughOrder: 3, tolerance: tolerance,
            maximumSpanCount: maximumSpanCount, maximumSubdivisionDepth: maximumSubdivisionDepth,
            remainingSourceDepth: remainingSourceDepth, consumeWork: consumeWork, consumeStorage: consumeStorage).intervalJet()
    }

    package func preparedFirstOrder(over box: SurfaceParameterBox,
        maximumSpanCount: Int, maximumSubdivisionDepth: Int, remainingSourceDepth: Int,
        tolerance: ModelingTolerance, consumeWork: () throws -> Void,
        consumeStorage: ((Int) throws -> Void)? = nil) throws -> OriginalSurfaceFirstOrderEnclosure {
        try .init(intervalTaylorJet(over: box, throughOrder: 1, tolerance: tolerance,
            maximumSpanCount: maximumSpanCount, maximumSubdivisionDepth: maximumSubdivisionDepth,
            remainingSourceDepth: remainingSourceDepth, consumeWork: consumeWork, consumeStorage: consumeStorage))
    }

    package func preparedFirstOrder<B: RationalAlgebraAdmitting>(over box: SurfaceParameterBox,
        maximumSpanCount: Int, maximumSubdivisionDepth: Int, remainingSourceDepth: Int,
        tolerance: ModelingTolerance, storageByteStride: Int, usage: inout B)
        throws -> OriginalSurfaceFirstOrderEnclosure {
        guard storageByteStride > 0 else {
            throw GeometryConversionError.invalidInput("Original plane derivative query storage stride must be positive.")
        }
        func bytes(_ count: Int) throws {
            let rounded = count.addingReportingOverflow(storageByteStride - 1)
            guard count >= 0, !rounded.overflow else {
                throw GeometryConversionError.resourceLimitExceeded("Original plane derivative query storage conversion overflows.")
            }
            try usage.retainExactStorage(rounded.partialValue / storageByteStride)
        }
        return try withoutActuallyEscaping(bytes) { storage in
            try preparedFirstOrder(over: box, maximumSpanCount: maximumSpanCount,
                maximumSubdivisionDepth: maximumSubdivisionDepth, remainingSourceDepth: remainingSourceDepth,
                tolerance: tolerance, consumeWork: { try usage.consumeExactWork(1) }, consumeStorage: storage)
        }
    }

    func taylorJet(u: Double, v: Double, throughOrder order: Int,
        tolerance: ModelingTolerance) throws -> SurfaceTaylorVectorJet {
        guard (0...16).contains(order) else {
            throw GeometryConversionError.invalidInput("Original plane derivative numeric facade retains Taylor order zero through sixteen.")
        }
        let original = try intervalTaylorJet(over: .init(u: .init(lower: u, upper: u), v: .init(lower: v, upper: v)),
            throughOrder: order, tolerance: tolerance, maximumSpanCount: maximumSpanCount,
            maximumSubdivisionDepth: maximumSubdivisionDepth, remainingSourceDepth: remainingSourceDepth, consumeWork: {})
        func candidate(_ q: SurfaceAreaIntervalTaylorScalarJet) throws -> SurfaceTaylorScalarJet {
            var result = try SurfaceTaylorScalarJet(order: order)
            for total in 0...order { for a in 0...total {
                try CurrentTaskCancellationChecker().checkCancellation()
                try result.setCoefficient(q.coefficient(a, total-a).midpoint, uOrder: a, vOrder: total-a)
            } }; return result
        }
        return try .init(x: candidate(original.x), y: candidate(original.y), z: candidate(original.z))
    }
}
