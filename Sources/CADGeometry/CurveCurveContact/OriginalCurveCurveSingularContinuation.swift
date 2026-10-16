import CADCore

/// Positive original continuation witness; no clipped-completeness inference.
struct OriginalCurveCurveSingularContinuation {
  func certificate(
    common: OriginalNativeCurveCurveCommonFactor,
    at roots: [ExactBivariateSystemRoot],
    over domain: SurfaceParameterBox,
    maximumDepth: Int,
    tolerance: ModelingTolerance,
    using execution: inout OriginalQueryExecution
  ) throws -> SurfaceParameterBox? {
    for root in roots {
      let resolution = try OriginalSingularResolution(
        original: common.factor,
        at: root, maximumDepth: maximumDepth, usage: &execution)
      for germ in resolution.germs {
        let chart = try OriginalSingularRegularChart(
          germ: germ, maximumDepth: maximumDepth, usage: &execution)
        let clipped = try OriginalSingularRegularChartClip(
          chart: chart, over: domain,
          maximumDepth: maximumDepth, usage: &execution)
        for span in clipped.spans {
          var lower = clipped.stations[span.lowerStation].endpoint
          var upper = clipped.stations[span.upperStation].endpoint
          let witness = span.originalFreeWitness
          while try
            !((try witness.subtracting(lower.upper, usage: &execution)).isPositive
            && (try upper.lower.subtracting(witness, usage: &execution)).isPositive)
          {
            if case .algebraic(let root) = lower {
              lower = .algebraic(
                try root.refinedOnce(maximumDepth: maximumDepth, usage: &execution))
            }
            if case .algebraic(let root) = upper {
              upper = .algebraic(
                try root.refinedOnce(maximumDepth: maximumDepth, usage: &execution))
            }
          }
          let two = try ExactRationalCoefficient.natural(2, usage: &execution)
          var left = try lower.upper.adding(witness, usage: &execution).divided(
            by: two, usage: &execution)
          var right = try upper.lower.adding(witness, usage: &execution).divided(
            by: two, usage: &execution)
          var depth = max(chart.sourceDepth, max(lower.depth, upper.depth))
          var coefficientWidth = try ExactRationalCoefficient.originalDouble(
            min(domain.u.width, domain.v.width), usage: &execution)
          while depth <= maximumDepth {
            try execution.visitCell(axis: .value, depth: depth)
            let leftLabel = try left.outwardInterval(usage: &execution).lower
            let rightLabel = try right.outwardInterval(usage: &execution).upper
            guard leftLabel < rightLabel else { break }
            let exactLeft = try ExactRationalCoefficient.originalDouble(
              leftLabel, usage: &execution)
            let exactRight = try ExactRationalCoefficient.originalDouble(
              rightLabel, usage: &execution)
            guard (try exactLeft.subtracting(lower.upper, usage: &execution)).isPositive,
              (try upper.lower.subtracting(exactRight, usage: &execution)).isPositive
            else { break }
            let interval = try ScalarInterval(lower: leftLabel, upper: rightLabel)
            let enclosure = try chart.enclosure(
              over: interval,
              maximumCoefficientWidth: coefficientWidth, maximumDepth: maximumDepth,
              usage: &execution)
            let box = enclosure.originalParameters
            guard enclosure.originalDerivatives.count == 4 else {
              throw GeometryConversionError.invalidInput(
                "Original clipped continuation lost its native parameter derivatives.")
            }
            let derivative = enclosure.originalDerivatives[1]
            let nonconstant =
              derivative.x.lower > 0 || derivative.x.upper < 0
              || derivative.y.lower > 0 || derivative.y.upper < 0
            if nonconstant {
              // Complete exact clipping proves the admitted graph
              // stays in the rectangle. Its outward query box may
              // overrun a coincident boundary by rounding only.
              return try SurfaceParameterBox(
                u: ScalarInterval(
                  lower: max(box.u.lower, domain.u.lower), upper: min(box.u.upper, domain.u.upper)),
                v: ScalarInterval(
                  lower: max(box.v.lower, domain.v.lower),
                  upper: min(box.v.upper, domain.v.upper)))
            }
            guard depth < maximumDepth else { break }
            depth += 1
            left = try left.adding(witness, usage: &execution).divided(by: two, usage: &execution)
            right = try right.adding(witness, usage: &execution).divided(by: two, usage: &execution)
            coefficientWidth = try coefficientWidth.divided(by: two, usage: &execution)
          }
        }
        for positive in [true, false] {
          var upper = positive ? chart.parameterDomain.upper : -chart.parameterDomain.lower
          var depth = chart.sourceDepth
          var coefficientWidth = try ExactRationalCoefficient.originalDouble(
            min(domain.u.width, domain.v.width), usage: &execution)
          let two = try ExactRationalCoefficient.natural(2, usage: &execution)
          while depth <= maximumDepth {
            try execution.visitCell(axis: .value, depth: depth)
            let lower = upper * 0.5
            guard lower > 0, lower < upper, upper.isFinite else { break }
            let interval = try ScalarInterval(
              lower: positive ? lower : -upper,
              upper: positive ? upper : -lower)
            let enclosure = try chart.enclosure(
              over: interval,
              maximumCoefficientWidth: coefficientWidth, maximumDepth: maximumDepth,
              usage: &execution)
            let box = enclosure.originalParameters
            guard enclosure.originalDerivatives.count == 4 else {
              throw GeometryConversionError.invalidInput(
                "Original singular chart lost its native parameter differential.")
            }
            let derivative = enclosure.originalDerivatives[1]
            let nonconstant =
              derivative.x.lower > 0 || derivative.x.upper < 0
              || derivative.y.lower > 0 || derivative.y.upper < 0
            if nonconstant, box.u.lower >= domain.u.lower, box.u.upper <= domain.u.upper,
              box.v.lower >= domain.v.lower, box.v.upper <= domain.v.upper
            {
              return box
            }
            if box.u.upper < domain.u.lower || box.u.lower > domain.u.upper
              || box.v.upper < domain.v.lower || box.v.lower > domain.v.upper
            {
              break
            }
            guard depth < maximumDepth else { break }
            depth += 1
            upper = lower
            coefficientWidth = try coefficientWidth.divided(by: two, usage: &execution)
          }
        }
      }
    }
    return nil
  }
}
