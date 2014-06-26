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
start_time_index = 2
end_time_index = 3
start_steal_time_index = 10
end_steal_time_index = 11
used_ram_index = 13
one_min_load_index = 16
five_min_load_index = 17
fifteen_min_load_index = 18
start_iowait_index = 20
end_iowait_index = 21

run_col= []
flows_col = []
runtime_col = []
used_ram_col = []
iowait_col = []
steal_time_col = []
one_min_load_col = []
five_min_load_col = []
fifteen_min_load_col = []
# Start with -1 to account for header
null_flow_results = -1
with open(results_file, "rb") as f:
    reader = csv.reader(f)
    for row in reader:
        # cbench_script.sh is currently giving null for some CBench results, skip them
        # Also skips header row
        try:
            run_col.append(float(row[run_index]))
            flows_col.append(float(row[flow_index]))
            runtime_col.append(float(row[end_time_index]) - float(row[start_time_index]))
            used_ram_col.append(float(row[used_ram_index]))
            iowait_col.append(float(row[end_iowait_index]) - float(row[start_iowait_index]))
            steal_time_col.append(float(row[end_steal_time_index]) - float(row[start_steal_time_index]))
            one_min_load_col.append(float(row[one_min_load_index]))
            five_min_load_col.append(float(row[five_min_load_index]))
            fifteen_min_load_col.append(float(row[fifteen_min_load_index]))
        except ValueError:
            null_flow_results += 1
            continue

results = {}
results["sample_size"] = len(run_col)
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

# Build graph of stats
#pyplot.figure(1)

# Plot flows/sec
#pyplot.subplot(5, 1, 1)
pyplot.subplot(2, 1, 1)
# "go" means green O's. pyplot syntax is -"Explicit is better than implicit"
pyplot.plot(run_col, flows_col, "go")
pyplot.xlabel("Run Number")
pyplot.ylabel("Flows per Second")

# Plot used RAM
#pyplot.subplot(5, 1, 2)
pyplot.subplot(2, 1, 2)
pyplot.plot(run_col, used_ram_col, "go")
pyplot.xlabel("Run Number")
pyplot.ylabel("Used RAM")

# Currently not plotting load, as it's not very interesting

# Plot one minute load
#pyplot.subplot(5, 1, 3)
#pyplot.plot(run_col, one_min_load_col, "go")
#pyplot.xlabel("Run Number")
#pyplot.ylabel("One Minute Load")

# Plot five minute load
#pyplot.subplot(5, 1, 4)
#pyplot.plot(run_col, five_min_load_col, "go")
#pyplot.xlabel("Run Number")
#pyplot.ylabel("Five Minute Load")

# Plot fifteen minute load
#pyplot.subplot(5, 1, 5)
#pyplot.plot(run_col, fifteen_min_load_col, "go")
#pyplot.xlabel("Run Number")
#pyplot.ylabel("Fifteen Minute Load")

# Render plot
pyplot.subplots_adjust(hspace=.3)
pyplot.show()
