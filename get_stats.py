#!/usr/bin/env python
# Calculates basic stats of results file

import csv
import numpy
import pprint

results_file = "results.csv"

flows_col = []
runtime_col = []
with open(results_file, "rb") as f:
    reader = csv.reader(f)
    for row in reader:
        try:
            flows_col.append(float(row[1]))
            # Subtract end_time from start_time to get CBench runtime
            runtime_col.append(float(row[3]) - float(row[2]))
            print float(row[4]) - float(row[3])
        except ValueError:
            # Skips header
            continue

results = {}
results["sample_size"] = len(flows_col)

# Calculate CBench flows/second stats
results["cbench_min"] = int(round(numpy.amin(flows_col)))
results["cbench_max"] = int(round(numpy.amax(flows_col)))
results["cbench_mean"] = int(round(numpy.mean(flows_col)))
results["cbench_standard_deviation"] = int(round(numpy.std(flows_col)))

# Calculate CBench runtime stats
results["runtime_min"] = int(round(numpy.amin(runtime_col)))
results["runtime_max"] = int(round(numpy.amax(runtime_col)))
results["runtime_mean"] = int(round(numpy.mean(runtime_col)))
results["runtime_standard_deviation"] = int(round(numpy.std(runtime_col)))
pprint.pprint(results)
