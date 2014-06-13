#!/usr/bin/env python
# Calculates basic stats of results file

import csv
import numpy
import pprint

results_file = "results.csv"

flows_col = []
runs_col = []
with open(results_file, "rb") as f:
    reader = csv.reader(f)
    for row in reader:
        try:
            flows_col.append(float(row[1]))
        except ValueError:
            # Skips header
            continue

results = {}
results["sample_size"] = len(flows_col)
results["min"] = int(round(numpy.amin(flows_col)))
results["max"] = int(round(numpy.amax(flows_col)))
results["mean"] = int(round(numpy.mean(flows_col)))
results["standard_deviation"] = int(round(numpy.std(flows_col)))
pprint.pprint(results)
