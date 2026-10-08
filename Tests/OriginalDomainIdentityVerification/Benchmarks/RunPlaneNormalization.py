import json
import statistics
import subprocess
import sys

before, after = sys.argv[1:]
results = {}
for case in ["rational", "sqrt2"]:
    samples = []
    for index in range(10):
        row = {}
        order = [("before", before), ("after", after)]
        if index % 2:
            order.reverse()
        for label, binary in order:
            output = subprocess.run([binary, case], capture_output=True, text=True, check=True, timeout=30)
            value = json.loads(output.stdout)
            if not value["exact"]:
                raise RuntimeError("Exact result check failed")
            row[label] = value
        row["ratio"] = row["after"]["microseconds"] / row["before"]["microseconds"]
        samples.append(row)
    old = [row["before"]["microseconds"] for row in samples]
    new = [row["after"]["microseconds"] for row in samples]
    ratios = sorted(row["ratio"] for row in samples)
    results[case] = {
        "before_median_us": statistics.median(old),
        "after_median_us": statistics.median(new),
        "before_range_us": [min(old), max(old)],
        "after_range_us": [min(new), max(new)],
        "paired_median_ratio": statistics.median(ratios),
        "paired_range_ratio": [min(ratios), max(ratios)],
        "before_work": samples[0]["before"]["work"],
        "after_work": samples[0]["after"]["work"],
        "before_generated_bytes": samples[0]["before"]["generated_bytes"],
        "after_generated_bytes": samples[0]["after"]["generated_bytes"],
        "samples": samples,
    }
    if case == "rational":
        if any(row["before"]["work"] != row["after"]["work"] or
               row["before"]["generated_bytes"] != row["after"]["generated_bytes"] for row in samples):
            raise RuntimeError("Rational resource cost changed")
    elif any(row["after"]["work"] >= row["before"]["work"] or
             row["after"]["generated_bytes"] >= row["before"]["generated_bytes"] for row in samples):
        raise RuntimeError("Algebraic resource cost did not improve")
print(json.dumps(results, indent=2))
