#!/usr/bin/env python
# Calculates basic stats of results file

import csv
import numpy
import pprint

results_file = "results.csv"
precision = 3
flow_index = 1
start_time_index = 2
end_time_index = 3
start_steal_time_index = 10
end_steal_time_index = 11
used_ram_index = 13
start_iowait_index = 20
end_iowait_index = 21

flows_col = []
runtime_col = []
used_ram_col = []
iowait_col= []
steal_time_col= []
null_flow_results = 0
with open(results_file, "rb") as f:
    reader = csv.reader(f)
    for row in reader:
        # cbench_script.sh is currently giving null for some CBench results, skip them
        try:
            flows_col.append(float(row[flow_index]))
        except ValueError:
            if row[flow_index] == "":
                null_flow_results += 1
            continue
        # Subtract end_time from start_time to get CBench runtime
        runtime_col.append(float(row[end_time_index]) - float(row[start_time_index]))
        used_ram_col.append(float(row[used_ram_index]))
        iowait_col.append(float(row[end_iowait_index]) - float(row[start_iowait_index]))
        steal_time_col.append(float(row[end_steal_time_index]) - float(row[start_steal_time_index]))

results = {}
results["sample_size"] = len(flows_col)
results["null_flow_results"] = null_flow_results

# Calculate CBench flows/second stats
results["cbench_min"] = int(round(numpy.amin(flows_col)))
results["cbench_max"] = int(round(numpy.amax(flows_col)))
results["cbench_mean"] = round(numpy.mean(flows_col), precision)
results["cbench_standard_deviation"] = round(numpy.std(flows_col), precision)
results["cbench_relative_std_dev"] = round((numpy.std(flows_col) / numpy.mean(flows_col)) * 100, precision)

# Calculate CBench runtime stats
results["runtime_min"] = int(numpy.amin(runtime_col))
results["runtime_max"] = int(numpy.amax(runtime_col))
results["runtime_mean"] = round(numpy.mean(runtime_col), precision)
results["runtime_standard_deviation"] = round(numpy.std(runtime_col), precision)

# Calculate used RAM stats
results["used_ram_min"] = int(numpy.amin(used_ram_col))
results["used_ram_max"] = int(numpy.amax(used_ram_col))
results["used_ram_mean"] = round(numpy.mean(used_ram_col), precision)
results["used_ram_standard_deviation"] = round(numpy.std(used_ram_col), precision)

# Calculate iowait stats
results["iowait_min"] = int(numpy.amin(iowait_col))
results["iowait_max"] = int(numpy.amax(iowait_col))
results["iowait_mean"] = round(numpy.mean(iowait_col), precision)
results["iowait_standard_deviation"] = round(numpy.std(iowait_col), precision)

# Calculate steal_time stats
results["steal_time_min"] = int(numpy.amin(steal_time_col))
results["steal_time_max"] = int(numpy.amax(steal_time_col))
results["steal_time_mean"] = round(numpy.mean(steal_time_col), precision)
results["steal_time_standard_deviation"] = round(numpy.std(steal_time_col), precision)

pprint.pprint(results)
