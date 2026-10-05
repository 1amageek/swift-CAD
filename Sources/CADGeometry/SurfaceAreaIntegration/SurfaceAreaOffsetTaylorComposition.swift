import CADCore

/// Composes genuine offsets from the same original higher-order source receipt.
struct SurfaceAreaOffsetTaylorComposition: Sendable {
    let distances: [Double]

    func intervalJet(from original: SurfaceAreaIntervalTaylorVectorJet,
                     consumeWork: () throws -> Void, consumeStorage: ((Int) throws -> Void)? = nil) throws -> SurfaceIntervalVectorJet {
        try intervalTaylorJet(from:original,translation:nil,consumeWork:consumeWork,consumeStorage:consumeStorage).intervalJet()
    }

    func intervalTaylorJet(from original: SurfaceAreaIntervalTaylorVectorJet,
        translation: SurfaceAreaOffsetTranslationAuthority?, requestedResultOrder: Int = 3,
        originalFirstNormal: SurfaceAreaIntervalTaylorVectorJet? = nil,
        consumeWork: () throws -> Void, consumeStorage: ((Int) throws -> Void)? = nil) throws
        -> SurfaceAreaIntervalTaylorVectorJet {
        let required = distances.count.addingReportingOverflow(requestedResultOrder)
        guard requestedResultOrder >= 3, !required.overflow, original.x.order == required.partialValue,
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
        if let normal = originalFirstNormal {
            guard !distances.isEmpty, translation == nil,
                  normal.x.order == original.x.order - 1,
                  normal.y.order == normal.x.order, normal.z.order == normal.x.order,
                  normal.x.tolerance == original.x.tolerance,
                  normal.y.tolerance == original.y.tolerance,
                  normal.z.tolerance == original.z.tolerance else {
                throw KernelError(phase: .geometry, code: .invalidInput, tolerance: original.x.tolerance,
                    message: "Original pole offset normal must bind the admitted first source order and tolerance.")
            }
        }
        var source = original
        var firstLayer = true
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
                    x:.constant(vector.x,order:order,axis:axis,tolerance:source.x.tolerance,consumeWork:consumeWork,consumeStorage:consumeStorage),
                    y:.constant(vector.y,order:order,axis:axis,tolerance:source.x.tolerance,consumeWork:consumeWork,consumeStorage:consumeStorage),
                    z:.constant(vector.z,order:order,axis:axis,tolerance:source.x.tolerance,consumeWork:consumeWork,consumeStorage:consumeStorage))
            }
            let normal: SurfaceAreaIntervalTaylorVectorJet
            if firstLayer, let admitted = originalFirstNormal {
                normal = admitted
            } else if let translation, let fixed = translation.constantNormal {
                normal = try constant(fixed)
            } else {
                let tangentU: SurfaceAreaIntervalTaylorVectorJet
                let tangentV: SurfaceAreaIntervalTaylorVectorJet
                if let translation, translation.direction == .u { tangentU = try constant(translation.translation) }
                else { tangentU = try source.differentiated(alongU:true,consumeWork:consumeWork,consumeStorage:consumeStorage) }
                if let translation, translation.direction == .v { tangentV = try constant(translation.translation) }
                else { tangentV = try source.differentiated(alongU:false,consumeWork:consumeWork,consumeStorage:consumeStorage) }
                normal = try tangentU.cross(tangentV,consumeWork:consumeWork,consumeStorage:consumeStorage).normalized(consumeWork:consumeWork,consumeStorage:consumeStorage)
            }
            source = try source.truncated(to:source.x.order-1,consumeWork:consumeWork,consumeStorage:consumeStorage)
                .adding(normal.scaled(by:.exact(distance),consumeWork:consumeWork,consumeStorage:consumeStorage),consumeWork:consumeWork,consumeStorage:consumeStorage)
            firstLayer = false
        }
        return source
    }
}
