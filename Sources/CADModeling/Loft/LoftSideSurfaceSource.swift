import CADCore
import CADGeometry

/// Keeps the source law distinct from optional exact construction specializations.
package enum LoftSideSurfaceSource {
    case native(BSplineSurface3D)
    case originalCoons(OriginalCoonsSurface3D)
    case originalBoundaryCorrected(OriginalBoundaryCorrectedSurface3D)
    indirect case originalPlaneDerivative(OriginalPlaneDerivativeSurface3D, ProceduralSurface3D, GeometryConversionGuarantee)

    package static func admittingOriginalPlaneDerivative(
        _ source: OriginalPlaneDerivativeSurface3D, usage: inout OriginalQueryExecution,
        certify: (Surface3D, inout OriginalQueryExecution) throws -> GeometryConversionGuarantee
    ) throws -> Self {
        try RationalAlgebraStorage.retain(1, of: OriginalPlaneDerivativeSurface3D.self, usage: &usage)
        try RationalAlgebraStorage.retain(1, of: (OriginalPlaneDerivativeSurface3D, ProceduralSurface3D, GeometryConversionGuarantee).self, usage: &usage)
        let procedural = ProceduralSurface3D.originalPlaneDerivative(source)
        let guarantee = try certify(.procedural(procedural), &usage)
        return .originalPlaneDerivative(source, procedural, guarantee)
    }

    package var surface: Surface3D {
        switch self {
        case .native(let source): .bSpline(source)
        case .originalCoons(let source): .procedural(.originalCoons(source))
        case .originalBoundaryCorrected(let source): .procedural(.originalBoundaryCorrected(source))
        case .originalPlaneDerivative(_, let retained, _): .procedural(retained)
        }
    }

    package func boundingBox(tolerance: ModelingTolerance, usage: inout OriginalQueryExecution) throws -> BoundingBox3D {
        switch self {
        case .native(let source):
            for row in source.controlPoints {
                let count = row.count.multipliedReportingOverflow(by: 3)
                guard !count.overflow else {
                    throw GeometryConversionError.resourceLimitExceeded("Original Loft bound source count overflows.")
                }
                try usage.consumeWork(count.partialValue)
            }
            return try .init(points: source.controlPoints.joined())
        case .originalBoundaryCorrected(let source):
            let full = try SurfaceParameterBox(u: .init(lower: 0, upper: 1), v: .init(lower: 0, upper: 1))
            let jet = try source.intervalTaylorJet(over: full, throughOrder: 0, tolerance: tolerance,
                    maximumSpanCount: source.maximumSpanCount, maximumSubdivisionDepth: source.maximumSubdivisionDepth,
                    remainingSourceDepth: 20, using: &usage)
            let x = try jet.x.coefficient(0, 0), y = try jet.y.coefficient(0, 0), z = try jet.z.coefficient(0, 0)
            return try .init(minimum: .init(x: x.lower, y: y.lower, z: z.lower),
                maximum: .init(x: x.upper, y: y.upper, z: z.upper))
        case .originalPlaneDerivative(let source, _, _):
            let full = try SurfaceParameterBox(u: .init(lower: 0, upper: 1), v: .init(lower: 0, upper: 1))
            let jet = try source.intervalTaylorJet(over: full, throughOrder: 0, tolerance: tolerance,
                    maximumSpanCount: source.maximumSpanCount, maximumSubdivisionDepth: source.maximumSubdivisionDepth,
                    remainingSourceDepth: source.remainingSourceDepth, using: &usage)
            let x = try jet.x.coefficient(0, 0), y = try jet.y.coefficient(0, 0), z = try jet.z.coefficient(0, 0)
            return try .init(minimum: .init(x: x.lower, y: y.lower, z: z.lower),
                maximum: .init(x: x.upper, y: y.upper, z: z.upper))
        case .originalCoons(let source):
            let full = try SurfaceParameterBox(u: ScalarInterval(lower: 0, upper: 1), v: ScalarInterval(lower: 0, upper: 1))
            let jet = try source.intervalTaylorJet(over: full, throughOrder: 0,
                tolerance: tolerance, using: &usage)
            let x = try jet.x.coefficient(0, 0)
            let y = try jet.y.coefficient(0, 0)
            let z = try jet.z.coefficient(0, 0)
            return try .init(minimum: .init(x: x.lower, y: y.lower, z: z.lower),
                maximum: .init(x: x.upper, y: y.upper, z: z.upper))
        }
    }

    package func exactNativeImage<B: ExactScalarAdmission & ~Copyable>(usage: inout B) throws -> BSplineSurface3D? {
        switch self {
        case .native(let source): source
        case .originalCoons(let source): try source.exactBilinearImage(usage: &usage)
        case .originalBoundaryCorrected, .originalPlaneDerivative: nil
        }
    }
}
