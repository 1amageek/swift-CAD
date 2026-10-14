import CADCore

extension DefaultSurfaceSurfaceIntersector {
    public func intersectionResult(first: Surface3D, second: Surface3D,
        options: SurfaceSurfaceIntersectionOptions = .init(), tolerance: ModelingTolerance) throws -> SurfaceSurfaceIntersectionResult {
        return try GeometryExactScalarFailure.withPublication {
          if let coincidentCone = try OriginalCoincidentConePublicProducer().resolve(first: first, second: second,
              options: options, tolerance: tolerance, includeRelations: true) { return coincidentCone }
          if let commonApexCone = try OriginalCommonApexConePublicProducer().resolve(first: first, second: second,
              options: options, tolerance: tolerance, includeRelations: true) { return commonApexCone }
          if let apexSphereCone = try OriginalApexSphereConeSurfacePublicProducer().resolve(first: first, second: second,
              options: options, tolerance: tolerance, includeRelations: true) { return apexSphereCone }
          if let fullConeCone = try OriginalFullConeConeSurfacePublicProducer().resolve(first: first, second: second,
              options: options, tolerance: tolerance, includeRelations: true) { return fullConeCone }
          if let boundedSphereCone = try OriginalBoundedSphereConeSurfacePublicProducer().resolve(first: first, second: second,
              options: options, tolerance: tolerance, includeRelations: true) { return boundedSphereCone }
          if let fullSphereCone = try OriginalFullSphereConeSurfacePublicProducer().resolve(first: first, second: second,
              options: options, tolerance: tolerance, includeRelations: true) { return fullSphereCone }
          if let coaxial = try OriginalCoaxialSurfacePublicProducer().resolve(first: first, second: second,
              options: options, tolerance: tolerance, includeRelations: true) { return coaxial }
          if let issued = try OriginalRetainedRollingPlanePublicProducer().resolve(first: first, second: second,
              options: options, tolerance: tolerance, includeRelations: true) { return issued }
          if let issued = try OriginalRetainedCoonsPlanePublicProducer().resolve(first: first, second: second,
              options: options, tolerance: tolerance, includeRelations: true) { return issued }
          if let exact = try NativeExactPublicSurfaceSurfaceProducer().resolve(first: first, second: second,
              options: options, tolerance: tolerance, includeRelations: true) { return exact }
          if let native = try NativeSurfaceSurfacePointProducer().resolve(first: first, second: second,
              options: options, tolerance: tolerance, includeRelations: true) { return native }
          if let native = try NativeMultiChartSurfaceSurfaceRelationProducer().resolve(first: first, second: second,
              options: options, tolerance: tolerance, includeRelations: true) { return native }
          let intersections = try intersections(first: first, second: second, options: options, tolerance: tolerance)
          try CurrentTaskCancellationChecker().checkCancellation()
          return .init(intersections: intersections)
        }
    }

    public func intersectionResult(first: Surface3D, second: Surface3D,
        options: SurfaceSurfaceIntersectionOptions = .init(), tolerance: ModelingTolerance,
        maximumSpanCount: Int, maximumSubdivisionDepth: Int, remainingSourceDepth: Int,
        consumeWork: @escaping @Sendable () throws -> Void,
        consumeStorage: (@Sendable (Int) throws -> Void)? = nil,
        maximumAlgebraicDepth: Int? = nil) throws -> SurfaceSurfaceIntersectionResult {
        return try GeometryExactScalarFailure.withPublication {
          try options.validate(tolerance: tolerance)
          let admission = try SurfaceSurfaceQueryAdmission(maximumSpanCount: maximumSpanCount,
              maximumSubdivisionDepth: maximumSubdivisionDepth, remainingSourceDepth: remainingSourceDepth,
              consumeWork: consumeWork, consumeStorage: consumeStorage, maximumAlgebraicDepth: maximumAlgebraicDepth)
          if let coincidentCone = try OriginalCoincidentConePublicProducer().resolve(first: first, second: second,
              options: options, tolerance: tolerance, includeRelations: true, admission: admission) { return coincidentCone }
          if let commonApexCone = try OriginalCommonApexConePublicProducer().resolve(first: first, second: second,
              options: options, tolerance: tolerance, includeRelations: true, admission: admission) { return commonApexCone }
          if let apexSphereCone = try OriginalApexSphereConeSurfacePublicProducer().resolve(first: first, second: second,
              options: options, tolerance: tolerance, includeRelations: true, admission: admission) { return apexSphereCone }
          if let fullConeCone = try OriginalFullConeConeSurfacePublicProducer().resolve(first: first, second: second,
              options: options, tolerance: tolerance, includeRelations: true, admission: admission) { return fullConeCone }
          if let boundedSphereCone = try OriginalBoundedSphereConeSurfacePublicProducer().resolve(first: first, second: second,
              options: options, tolerance: tolerance, includeRelations: true, admission: admission) { return boundedSphereCone }
          if let fullSphereCone = try OriginalFullSphereConeSurfacePublicProducer().resolve(first: first, second: second,
              options: options, tolerance: tolerance, includeRelations: true, admission: admission) { return fullSphereCone }
          if let coaxial = try OriginalCoaxialSurfacePublicProducer().resolve(first: first, second: second,
              options: options, tolerance: tolerance, includeRelations: true, admission: admission) { return coaxial }
          if let issued = try OriginalRetainedRollingPlanePublicProducer().resolve(first: first, second: second,
              options: options, tolerance: tolerance, includeRelations: true, admission: admission) { return issued }
          if let issued = try OriginalRetainedCoonsPlanePublicProducer().resolve(first: first, second: second,
              options: options, tolerance: tolerance, includeRelations: true, admission: admission) { return issued }
          if let exact = try NativeExactPublicSurfaceSurfaceProducer().resolve(first: first, second: second,
              options: options, tolerance: tolerance, includeRelations: true, admission: admission) { return exact }
          if let native = try NativeSurfaceSurfacePointProducer().resolve(first: first, second: second,
              options: options, tolerance: tolerance, includeRelations: true, admission: admission) { return native }
          if let native = try NativeMultiChartSurfaceSurfaceRelationProducer().resolve(first: first, second: second,
              options: options, tolerance: tolerance, includeRelations: true, admission: admission) { return native }
          let intersections = try intersections(first: first, second: second, options: options, tolerance: tolerance,
              maximumSpanCount: maximumSpanCount, maximumSubdivisionDepth: maximumSubdivisionDepth,
              remainingSourceDepth: remainingSourceDepth, consumeWork: consumeWork, consumeStorage: consumeStorage,
              maximumAlgebraicDepth: maximumAlgebraicDepth)
          try admission.reserve(count: 1, stride: MemoryLayout<SurfaceSurfaceIntersectionResult>.stride)
          try CurrentTaskCancellationChecker().checkCancellation()
          return .init(intersections: intersections)
        }
    }

    public func intersectionResult(first: Surface3D, over firstBox: SurfaceParameterBox,
        second: Surface3D, over secondBox: SurfaceParameterBox,
        options: SurfaceSurfaceIntersectionOptions = .init(), tolerance: ModelingTolerance,
        maximumSpanCount: Int, maximumSubdivisionDepth: Int, remainingSourceDepth: Int,
        consumeWork: @escaping @Sendable () throws -> Void,
        consumeStorage: (@Sendable (Int) throws -> Void)? = nil,
        maximumAlgebraicDepth: Int? = nil) throws -> SurfaceSurfaceIntersectionResult {
        return try GeometryExactScalarFailure.withPublication {
          try options.validate(tolerance: tolerance)
          let admission = try SurfaceSurfaceQueryAdmission(maximumSpanCount: maximumSpanCount,
              maximumSubdivisionDepth: maximumSubdivisionDepth, remainingSourceDepth: remainingSourceDepth,
              consumeWork: consumeWork, consumeStorage: consumeStorage, maximumAlgebraicDepth: maximumAlgebraicDepth)
          if let coincidentCone = try OriginalCoincidentConePublicProducer().resolve(first: first, second: second,
              firstBox: firstBox, secondBox: secondBox,
              options: options, tolerance: tolerance, includeRelations: true, admission: admission) { return coincidentCone }
          if let commonApexCone = try OriginalCommonApexConePublicProducer().resolve(first: first, second: second,
              firstBox: firstBox, secondBox: secondBox,
              options: options, tolerance: tolerance, includeRelations: true, admission: admission) { return commonApexCone }
          if let apexSphereCone = try OriginalApexSphereConeSurfacePublicProducer().resolve(first: first, second: second,
              firstBox: firstBox, secondBox: secondBox,
              options: options, tolerance: tolerance, includeRelations: true, admission: admission) { return apexSphereCone }
          if let fullConeCone = try OriginalFullConeConeSurfacePublicProducer().resolve(first: first, second: second,
              firstBox: firstBox, secondBox: secondBox,
              options: options, tolerance: tolerance, includeRelations: true, admission: admission) { return fullConeCone }
          if let boundedSphereCone = try OriginalBoundedSphereConeSurfacePublicProducer().resolve(first: first, second: second,
              firstBox: firstBox, secondBox: secondBox,
              options: options, tolerance: tolerance, includeRelations: true, admission: admission) { return boundedSphereCone }
          if let fullSphereCone = try OriginalFullSphereConeSurfacePublicProducer().resolve(first: first, second: second,
              firstBox: firstBox, secondBox: secondBox,
              options: options, tolerance: tolerance, includeRelations: true, admission: admission) { return fullSphereCone }
          if let coaxial = try OriginalCoaxialSurfacePublicProducer().resolve(first: first, second: second,
              firstBox: firstBox, secondBox: secondBox,
              options: options, tolerance: tolerance, includeRelations: true, admission: admission) { return coaxial }
          if let issued = try OriginalRetainedRollingPlanePublicProducer().resolve(first: first, second: second,
              firstBox: firstBox, secondBox: secondBox, options: options,
              tolerance: tolerance, includeRelations: true, admission: admission) { return issued }
          if let issued = try OriginalRetainedCoonsPlanePublicProducer().resolve(first: first, second: second,
              firstBox: firstBox, secondBox: secondBox, options: options,
              tolerance: tolerance, includeRelations: true, admission: admission) { return issued }
          if let exact = try NativeExactPublicSurfaceSurfaceProducer().resolve(first: first, second: second,
              firstBox: firstBox, secondBox: secondBox, options: options,
              tolerance: tolerance, includeRelations: true, admission: admission) { return exact }
          if let native = try NativeSurfaceSurfacePointProducer().resolve(first: first, second: second,
              firstBox: firstBox, secondBox: secondBox, options: options,
              tolerance: tolerance, includeRelations: true, admission: admission) { return native }
          if let native = try NativeMultiChartSurfaceSurfaceRelationProducer().resolve(first: first, second: second,
              firstBox: firstBox, secondBox: secondBox, options: options,
              tolerance: tolerance, includeRelations: true, admission: admission) { return native }
          let intersections = try intersections(first: first, over: firstBox, second: second, over: secondBox,
              options: options, tolerance: tolerance, maximumSpanCount: maximumSpanCount,
              maximumSubdivisionDepth: maximumSubdivisionDepth, remainingSourceDepth: remainingSourceDepth,
              consumeWork: consumeWork, consumeStorage: consumeStorage, maximumAlgebraicDepth: maximumAlgebraicDepth)
          try admission.reserve(count: 1, stride: MemoryLayout<SurfaceSurfaceIntersectionResult>.stride)
          try CurrentTaskCancellationChecker().checkCancellation()
          return .init(intersections: intersections)
        }
    }
}
