import CADCore

/// Composes genuine offsets from the same original higher-order source receipt.
struct SurfaceAreaOffsetTaylorComposition: Sendable {
    let distances: [Double]

    func intervalJet(from original: SurfaceAreaIntervalTaylorVectorJet,
                     consumeWork: () throws -> Void) throws -> SurfaceIntervalVectorJet {
        try intervalTaylorJet(from:original,translation:nil,consumeWork:consumeWork).intervalJet()
    }

    func intervalTaylorJet(from original: SurfaceAreaIntervalTaylorVectorJet,
        translation: SurfaceAreaOffsetTranslationAuthority?, consumeWork: () throws -> Void) throws
        -> SurfaceAreaIntervalTaylorVectorJet {
        let required = distances.count.addingReportingOverflow(3)
        guard !required.overflow, original.x.order == required.partialValue,
              original.y.order == original.x.order, original.z.order == original.x.order else {
            throw KernelError(phase:.geometry,code:.invalidInput,tolerance:original.x.tolerance,
                message:"Offset composition requires every actual extra original source order.")
        }
        if let translation {
            guard original.x.axis == translation.varyingAxis,
                  original.y.axis == translation.varyingAxis,
                  original.z.axis == translation.varyingAxis else {
                throw KernelError(phase:.geometry,code:.invalidInput,tolerance:original.x.tolerance,
                    message:"Translated offset composition requires its original unary rail authority.")
            }
        }
        var source = original
        // Distances follow the original source chain from innermost to outermost.
        for distance in distances {
            try Task.checkCancellation()
            guard distance.isFinite, distance != 0 else {
                throw KernelError(phase:.geometry,code:.invalidInput,tolerance:original.x.tolerance,
                    message:"Higher offset composition requires a finite genuine offset distance.")
            }
            func constant(_ vector: IntervalVector3DBounds) throws -> SurfaceAreaIntervalTaylorVectorJet {
                let order = source.x.order-1, axis = source.x.axis
                return try SurfaceAreaIntervalTaylorVectorJet(
                    x:.constant(vector.x,order:order,axis:axis,tolerance:source.x.tolerance,consumeWork:consumeWork),
                    y:.constant(vector.y,order:order,axis:axis,tolerance:source.x.tolerance,consumeWork:consumeWork),
                    z:.constant(vector.z,order:order,axis:axis,tolerance:source.x.tolerance,consumeWork:consumeWork))
            }
            let normal: SurfaceAreaIntervalTaylorVectorJet
            if let translation, let fixed = translation.constantNormal {
                normal = try constant(fixed)
            } else {
                let tangentU: SurfaceAreaIntervalTaylorVectorJet
                let tangentV: SurfaceAreaIntervalTaylorVectorJet
                if let translation, translation.direction == .u { tangentU = try constant(translation.translation) }
                else { tangentU = try source.differentiated(alongU:true,consumeWork:consumeWork) }
                if let translation, translation.direction == .v { tangentV = try constant(translation.translation) }
                else { tangentV = try source.differentiated(alongU:false,consumeWork:consumeWork) }
                normal = try tangentU.cross(tangentV,consumeWork:consumeWork).normalized(consumeWork:consumeWork)
            }
            source = try source.truncated(to:source.x.order-1,consumeWork:consumeWork)
                .adding(normal.scaled(by:.exact(distance),consumeWork:consumeWork),consumeWork:consumeWork)
        }
        return source
    }
}
