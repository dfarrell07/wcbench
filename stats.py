#!/usr/bin/env python
# Calculates basic stats of results file

import csv
import numpy
import pprint
import matplotlib.pyplot as pyplot

results_file = "results.csv"
precision = 3
run_index = 0
flow_index = 1

run_col= []
flows_col = []
# Start with -1 to account for header
null_flow_results = -1
with open(results_file, "rb") as f:
    reader = csv.reader(f)
    for row in reader:
        try:
            run_col.append(float(row[run_index]))
            flows_col.append(float(row[flow_index]))
        except ValueError:
            # Skips header
            continue

results = {}
results["sample_size"] = len(run_col)

# Calculate CBench flows/second stats
results["cbench_min"] = int(round(numpy.amin(flows_col)))
results["cbench_max"] = int(round(numpy.amax(flows_col)))
results["cbench_mean"] = round(numpy.mean(flows_col), precision)
results["cbench_standard_deviation"] = round(numpy.std(flows_col), precision)
results["cbench_relative_std_dev"] = round((numpy.std(flows_col) / numpy.mean(flows_col)) * 100, precision)

pprint.pprint(results)

# Plot flows/sec
pyplot.subplot(2, 1, 1)
# "go" means green O's. pyplot syntax is -"Explicit is better than implicit"
pyplot.plot(run_col, flows_col, "go")
pyplot.xlabel("Run Number")
pyplot.ylabel("Flows per Second")

# Render plot
pyplot.subplots_adjust(hspace=.3)
pyplot.show()
