#!/usr/bin/env python
"""Compute basic stats about CBench data."""

import csv
import numpy
import pprint
import matplotlib.pyplot as pyplot
import argparse
import sys


class Stats(object):

    """Compute stats and/or graph data."""

    results_file = "results.csv"
    log_file = "cbench.log"
    precision = 3
    run_index = 0
    flow_index = 1
    start_time_index = 2
    end_time_index = 3
    start_steal_time_index = 10
    end_steal_time_index = 11
    used_ram_index = 13
    one_load_index = 16
    five_load_index = 17
    fifteen_load_index = 18
    start_iowait_index = 20
    end_iowait_index = 21

    def __init__(self):
        """Setup some flags and data structures, kick off build_cols call."""
        self.build_cols()
        self.results = {}
        self.results["sample_size"] = len(self.run_col)

    def build_cols(self):
        """Parse results file into lists of values, one per column."""
        self.run_col= []
        self.flows_col = []
        self.runtime_col = []
        self.used_ram_col = []
        self.iowait_col = []
        self.steal_time_col = []
        self.one_load_col = []
        self.five_load_col = []
        self.fifteen_load_col = []

        with open(self.results_file, "rb") as results_fd:
            results_reader = csv.reader(results_fd)
            for row in results_reader:
                try:
                    self.run_col.append(float(row[self.run_index]))
                    self.flows_col.append(float(row[self.flow_index]))
                    self.runtime_col.append(float(row[self.end_time_index]) - \
                        float(row[self.start_time_index]))
                    self.used_ram_col.append(float(row[self.used_ram_index]))
                    self.iowait_col.append(float(row[self.end_iowait_index]) - \
                        float(row[self.start_iowait_index]))
                    self.steal_time_col.append(float(row[self.end_steal_time_index]) - \
                        float(row[self.start_steal_time_index]))
                    self.one_load_col.append(float(row[self.one_load_index]))
                    self.five_load_col.append(float(row[self.five_load_index]))
                    self.fifteen_load_col.append(float(row[self.fifteen_load_index]))
                except ValueError:
                    # Skips header
                    continue

    def compute_flow_stats(self):
        """Compute CBench flows/second stats."""
        flow_stats = {}
        flow_stats["min"] = int(round(numpy.amin(self.flows_col)))
        flow_stats["max"] = int(round(numpy.amax(self.flows_col)))
        flow_stats["mean"] = round(numpy.mean(self.flows_col),
                                                       self.precision)
        flow_stats["stddev"] = round(numpy.std(self.flows_col), self.precision)
        flow_stats["relstddev"] = round((numpy.std(self.flows_col) / \
            numpy.mean(self.flows_col)) * \
            100, self.precision)
        self.results["flows"] = flow_stats

    def build_flow_graph(self, total_graph_count, graph_num):
        """Plot flows/sec data.

        :param total_graph_count: Total number of graphs to render.
        :type total_graph_count: int
        :param graph_num: Number for this graph, <= total_graph_count.
        :type graph_num: int

        """
        pyplot.subplot(total_graph_count, 1, graph_num)
        # "go" means green O's
        pyplot.plot(self.run_col, self.flows_col, "go")
        pyplot.xlabel("Run Number")
        pyplot.ylabel("Flows per Second")

    def compute_ram_stats(self):
        """Compute used RAM stats."""
        ram_stats = {}
        ram_stats["min"] = int(numpy.amin(self.used_ram_col))
        ram_stats["max"] = int(numpy.amax(self.used_ram_col))
        ram_stats["mean"] = round(numpy.mean(self.used_ram_col), self.precision)
        ram_stats["stddev"] = round(numpy.std(self.used_ram_col), self.precision)
        self.results["ram"] = ram_stats

    def build_ram_graph(self, total_graph_count, graph_num):
        """Plot used RAM data.

        :param total_graph_count: Total number of graphs to render.
        :type total_graph_count: int
        :param graph_num: Number for this graph, <= total_graph_count.
        :type graph_num: int

        """
        # Params are numrows, numcols, fignum
        pyplot.subplot(total_graph_count, 1, graph_num)
        # "go" means green O's
        pyplot.plot(self.run_col, self.used_ram_col, "go")
        pyplot.xlabel("Run Number")
        pyplot.ylabel("Used RAM")

    def compute_runtime_stats(self):
        """Compute CBench runtime length stats."""
        runtime_stats = {}
        runtime_stats["min"] = int(numpy.amin(self.runtime_col))
        runtime_stats["max"] = int(numpy.amax(self.runtime_col))
        runtime_stats["mean"] = round(numpy.mean(self.runtime_col), self.precision)
        runtime_stats["stddev"] = round(numpy.std(self.runtime_col), self.precision)
        self.results["runtime"] = runtime_stats

    def build_runtime_graph(self, total_graph_count, graph_num):
        """Plot CBench runtime length data.

        :paruntime total_graph_count: Total number of graphs to render.
        :type total_graph_count: int
        :paruntime graph_num: Number for this graph, <= total_graph_count.
        :type graph_num: int

        """
        # Paruntimes are numrows, numcols, fignum
        pyplot.subplot(total_graph_count, 1, graph_num)
        # "go" means green O's
        pyplot.plot(self.run_col, self.runtime_col, "go")
        pyplot.xlabel("Run Number")
        pyplot.ylabel("CBench runtime (sec)")

# Build stats object
stats = Stats()

# Map of graph names to the Stats.fns that build them
graph_map = {"flows": stats.build_flow_graph,
             "runtime": stats.build_runtime_graph,
             "ram": stats.build_ram_graph}
stats_map = {"flows": stats.compute_flow_stats,
             "runtime": stats.compute_runtime_stats,
             "ram": stats.compute_ram_stats}

# Build argument parser
parser = argparse.ArgumentParser(description="Compute stats about CBench data")
parser.add_argument("-S", "--all-stats", action="store_true",
    help="compute all stats")
parser.add_argument("-s", "--stats", choices=stats_map.keys(),
    help="compute stats on specified data", nargs="+")
parser.add_argument("-G", "--all-graphs", action="store_true",
    help="graph all data")
parser.add_argument("-g", "--graphs", choices=graph_map.keys(),
    help="graph specified data", nargs="+")


# Print help if no arguments are given
if len(sys.argv) == 1:
    parser.print_help()
    sys.exit(1)

# Parse the given args
args = parser.parse_args()

# Build graphs
if args.all_graphs:
    graphs_to_build = graph_map.keys()
elif args.graphs:
    graphs_to_build = args.graphs
else:
    graphs_to_build = []
for graph, graph_num in zip(graphs_to_build, range(len(graphs_to_build))):
    graph_map[graph](len(graphs_to_build), graph_num+1)

# Compute stats
if args.all_stats:
    stats_to_compute = stats_map.keys()
elif args.stats:
    stats_to_compute = args.stats
else:
    stats_to_compute = []
for stat in stats_to_compute:
    stats_map[stat]()

# Render graphs
if args.graphs or args.all_graphs:
    # Attempt to adjust plot spacing, just a simple heuristic
    if len(graphs_to_build) <= 3:
        pyplot.subplots_adjust(hspace=.2)
    elif len(graphs_to_build) <= 6:
        pyplot.subplots_adjust(hspace=.4)
    elif len(graphs_to_build) <= 9:
        pyplot.subplots_adjust(hspace=.7)
    else:
        pyplot.subplots_adjust(hspace=.7)
        print "WARNING: That's a lot of graphs. Add a second column?"
    pyplot.show()

# Print stats
if args.stats or args.all_stats:
    pprint.pprint(stats.results)
