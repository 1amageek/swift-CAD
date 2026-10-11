import CADCore
@testable import CADGeometry
@testable import DerivativeLiftPlanePort
import enum DerivativeLiftPlanePort.GeometryExactScalarFailure
import struct CADGeometry.CurveSurfaceIntersectionResult
import protocol CADGeometry.CurveSurfaceIntersectionResolving
import CADCore

extension DefaultCurveSurfaceIntersector: CurveSurfaceIntersectionResolving {
    public func intersectionResult(
        curve: Curve3D,
        surface: Surface3D,
        options: CurveSurfaceIntersectionOptions = .init(),
        tolerance: ModelingTolerance
    ) throws -> CurveSurfaceIntersectionResult {
        return try GeometryExactScalarFailure.withPublication {
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
          if let lift = try OriginalRetainedLiftPlanePublicProducer().resolve(curve:curve,surface:surface,
              options:options,tolerance:tolerance,invocation:invocation,retainingRelations:true) { return lift }
          return try CurveSurfaceOverlapResolver().resolve(curve: curve, surface: surface,
              options: options, tolerance: tolerance, intersector: self, invocation: invocation)
        }
    }

}
