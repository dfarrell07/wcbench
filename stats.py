#!/usr/bin/env python
"""Compute basic stats about CBench data."""

import csv
import numpy
import pprint
import matplotlib.pyplot as pyplot
import argparse
import sys


class Stats(object):

    """"""

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
        self.some_stats_computed = False
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
        self.some_stats_computed = True

    def build_flow_graph(self, total_graph_count, graph_num):
        """Plot flows/sec data."""
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
        self.some_stats_computed = True

    def build_ram_graph(self, total_graph_count, graph_num):
        """Plot used RAM data."""
        # Params are numrows, numcols, fignum
        pyplot.subplot(total_graph_count, 1, graph_num)
        # "go" means green O's
        pyplot.plot(self.run_col, self.used_ram_col, "go")
        pyplot.xlabel("Run Number")
        pyplot.ylabel("Used RAM")


stats = Stats()

# Map of graph names to the Stats.fns that build them
graph_map = {"flows": stats.build_flow_graph,
             "ram": stats.build_ram_graph}

parser = argparse.ArgumentParser(description="Compute stats about CBench data")
parser.add_argument("-a", "--all", action="store_true",
    help="compute all stats")
parser.add_argument("-A", "--all-graphs", action="store_true",
    help="graph all data")
parser.add_argument("-g", "--graphs", choices=graph_map.keys(),
    help="graph given data", nargs="+")
parser.add_argument("-f", "--flows", action="store_true",
    help="compute flows/sec stats")
parser.add_argument("-r", "--ram", action="store_true",
    help="compute used RAM stats")

# Print help if no arguments are given
if len(sys.argv) == 1:
    parser.print_help()
    sys.exit(1)

# Parse the given args
args = parser.parse_args()

if args.all_graphs:
    for graph_fn in graph_map.values():
        graph_fn()
else:
    for graph, graph_num in zip(args.graphs, range(len(args.graphs))):
        graph_map[graph](len(args.graphs), graph_num+1)

if args.flows or args.all:
    stats.compute_flow_stats()

if args.ram or args.all:
    stats.compute_ram_stats()

if stats.some_stats_computed:
    # Report stat results
    pprint.pprint(stats.results)

if args.graphs or args.all_graphs:
    # Render plot
    if len(args.graphs) <= 3:
        pyplot.subplots_adjust(hspace=.2)
    elif len(args.graphs) <= 6:
        pyplot.subplots_adjust(hspace=.4)
    elif len(args.graphs) <= 9:
        pyplot.subplots_adjust(hspace=.7)
    else:
        pyplot.subplots_adjust(hspace=.7)
        print "WARNING: That's a lot of graphs. Add a second column?"
    pyplot.show()
