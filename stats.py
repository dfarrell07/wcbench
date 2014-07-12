#!/usr/bin/env python
"""Compute basic stats about CBench data."""

import csv
import numpy
import pprint
import matplotlib.pyplot as pyplot
import argparse
import sys

description = "Compute stats about CBench data"
parser = argparse.ArgumentParser(description)
parser.add_argument("-a", "--all", action="store_true",
    help="compute all stats")
parser.add_argument("-A", "--all-graphs", action="store_true",
    help="compute all stats")
parser.add_argument("-f", "--flow", action="store_true",
    help="compute flows/sec stats")
parser.add_argument("-F", "--flow-graph", action="store_true",
    help="graph flows/sec data")

# Print help if no arguments are given
if len(sys.argv) == 1:
    parser.print_help()
    sys.exit(1)

# Parse the given args
args = parser.parse_args()

class Stats(object):

    """"""

    results_file = "results.csv"
    log_file = "cbench.log"
    precision = 3
    run_index = 0
    flow_index = 1

    def __init__(self):
        """Setup some flags and data structures, kick off build_cols call."""
        self.build_cols()
        self.results = {}
        self.some_graph_built = False
        self.some_stats_computed = False
        self.results["sample_size"] = len(self.run_col)

    def build_cols(self):
        """Parse results file into lists of values, one per column."""
        self.run_col= []
        self.flows_col = []
        with open(self.results_file, "rb") as results_fd:
            results_reader = csv.reader(results_fd)
            for row in results_reader:
                try:
                    self.run_col.append(float(row[self.run_index]))
                    self.flows_col.append(float(row[self.flow_index]))
                except ValueError:
                    # Skips header
                    continue

    def compute_flow_stats(self):
        """Calculate CBench flows/second stats."""
        flow_stats = {}
        flow_stats["min"] = int(round(numpy.amin(self.flows_col)))
        flow_stats["max"] = int(round(numpy.amax(self.flows_col)))
        flow_stats["mean"] = round(numpy.mean(self.flows_col),
                                                       self.precision)
        flow_stats["stddev"] = round(numpy.std(self.flows_col), self.precision)
        flow_stats["relstddev"] = round((numpy.std(self.flows_col) / numpy.mean(self.flows_col)) * 100, self.precision)
        self.results["flows"] = flow_stats
        self.some_stats_computed = True

    def build_flow_graph(self):
        """Plot flows/sec data."""
        #pyplot.subplot(2, 1, 1)
        # "go" means green O's. pyplot syntax is -"Explicit is better than implicit"
        pyplot.plot(self.run_col, self.flows_col, "go")
        pyplot.xlabel("Run Number")
        pyplot.ylabel("Flows per Second")
        self.some_graph_built = True

stats = Stats()

if args.all:
    stats.compute_flow_stats()

if args.all_graphs:
    stats.build_flow_graph()

if args.flow:
    stats.compute_flow_stats()

if args.flow_graph:
    stats.build_flow_graph()

if stats.some_stats_computed:
    # Report stat results
    pprint.pprint(stats.results)

if stats.some_graph_built:
    # Render plot
    pyplot.subplots_adjust(hspace=.3)
    pyplot.show()
