import CADCore

extension OriginalParameterGain {
    func validateOriginalSource(remainingSourceDepth: Int,
        consumeWork: (Int) throws -> Void) throws {
        guard remainingSourceDepth >= 0 else {
            throw GeometryConversionError.resourceLimitExceeded("Original gain validation exhausted source depth.")
        }
        try consumeWork(0); try CurrentTaskCancellationChecker().checkCancellation()
        switch self {
        case .binary, .ratio:
            try validate()
        case .product(let product):
            guard remainingSourceDepth > 0, !product.factors.isEmpty else {
                throw GeometryConversionError.resourceLimitExceeded("Original product validation requires remaining source depth.")
            }
            for factor in product.factors {
                try factor.validateOriginalSource(remainingSourceDepth: remainingSourceDepth - 1, consumeWork: consumeWork)
            }
            // The immutable exact coefficient cache was admitted by the only
            // constructor/decoder. No independent rational proof is replayed.
            let bounds = try interval()
            guard bounds.isFinite, bounds.excludesZero else {
                throw GeometryConversionError.invalidInput("Original product cache has no finite nonzero gain.")
            }
        case .difference(let difference):
            guard remainingSourceDepth > 0, difference.originalLower.isFinite,
                  difference.originalUpper.isFinite,
                  difference.periodicTranslation.originalSourcePeriod.isFinite,
                  difference.periodicTranslation.originalSourcePeriod > 0 else {
                throw GeometryConversionError.invalidInput("Original difference source fields are not admitted.")
            }
            try difference.periodicTranslation.parameterGain.validateOriginalSource(
                remainingSourceDepth: remainingSourceDepth - 1, consumeWork: consumeWork)
            let bounds = try interval()
            guard bounds.isFinite, bounds.excludesZero else {
                throw GeometryConversionError.invalidInput("Original difference cache has no finite nonzero gain.")
            }
        }
    }
}
