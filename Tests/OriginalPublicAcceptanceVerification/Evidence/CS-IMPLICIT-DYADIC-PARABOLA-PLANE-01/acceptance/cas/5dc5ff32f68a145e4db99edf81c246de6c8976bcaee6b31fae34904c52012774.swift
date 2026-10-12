import CADCore

extension DefaultCurveSurfaceIntersector: CurveSurfaceIntersectionResolving {
    public func intersectionResult(
        curve: Curve3D,
        surface: Surface3D,
        options: CurveSurfaceIntersectionOptions = .init(),
        tolerance: ModelingTolerance
    ) throws -> CurveSurfaceIntersectionResult {
        return try GeometryExactScalarFailure.withPublication {
          if let excluded = try OriginalCertifiedApexPlanePublicProducer().resolve(curve:curve,surface:surface,
              options:options,tolerance:tolerance) { return excluded }
          if let implicit = try OriginalImplicitCurvePublicProducer().resolve(curve:curve,surface:surface,
              options:options,tolerance:tolerance,retainingRelations:true) { return implicit }
          if let angular = try OriginalAngularPlanePublicProducer().resolve(curve:curve,surface:surface,
              options:options,tolerance:tolerance) { return angular }
          if let axis = try OriginalRevolutionAxisLinePublicProducer().resolve(curve:curve,surface:surface,
              options:options,tolerance:tolerance,retainingRelations:true) { return axis }
          if let drafted = try OriginalDraftedZeroLinePublicProducer().resolve(curve:curve,surface:surface,
              options:options,tolerance:tolerance,retainingRelations:true) { return drafted }
          if let lift = try OriginalRetainedLiftPlanePublicProducer().resolve(curve:curve,surface:surface,
              options:options,tolerance:tolerance,retainingRelations:true) { return lift }
          return try CurveSurfaceOverlapResolver().resolve(curve: curve, surface: surface, options: options,
                                                  tolerance: tolerance, intersector: self)
        }
    }

    public func intersectionResult(curve: Curve3D, surface: Surface3D,
        options: CurveSurfaceIntersectionOptions = .init(), tolerance: ModelingTolerance,
        maximumSpanCount: Int, maximumSubdivisionDepth: Int, remainingSourceDepth: Int,
        consumeWork: @escaping @Sendable (Int) throws -> Void,
        consumeStorage: (@Sendable (Int) throws -> Void)? = nil,
        maximumAlgebraicDepth: Int? = nil) throws -> CurveSurfaceIntersectionResult {
        return try GeometryExactScalarFailure.withPublication {
          let invocation = try CurveSurfaceQueryInvocation(
              maximumSubdivisionDepth: min(options.maximumSubdivisionDepth, maximumSubdivisionDepth),
              maximumSpanCount: maximumSpanCount, remainingSourceDepth: remainingSourceDepth,
              consumeWork: consumeWork, consumeStorage: consumeStorage,
              maximumAlgebraicDepth: maximumAlgebraicDepth)
          if let excluded = try OriginalCertifiedApexPlanePublicProducer().resolve(curve:curve,surface:surface,
              options:options,tolerance:tolerance,invocation:invocation) { return excluded }
          if let implicit = try OriginalImplicitCurvePublicProducer().resolve(curve:curve,surface:surface,
              options:options,tolerance:tolerance,invocation:invocation,retainingRelations:true) { return implicit }
          if let angular = try OriginalAngularPlanePublicProducer().resolve(curve:curve,surface:surface,
              options:options,tolerance:tolerance,invocation:invocation) { return angular }
          if let axis = try OriginalRevolutionAxisLinePublicProducer().resolve(curve:curve,surface:surface,
              options:options,tolerance:tolerance,invocation:invocation,retainingRelations:true) { return axis }
          if let drafted = try OriginalDraftedZeroLinePublicProducer().resolve(curve:curve,surface:surface,
              options:options,tolerance:tolerance,invocation:invocation,retainingRelations:true) { return drafted }
          if let lift = try OriginalRetainedLiftPlanePublicProducer().resolve(curve:curve,surface:surface,
              options:options,tolerance:tolerance,invocation:invocation,retainingRelations:true) { return lift }
          return try CurveSurfaceOverlapResolver().resolve(curve: curve, surface: surface,
              options: options, tolerance: tolerance, intersector: self, invocation: invocation)
        }
    }

}
