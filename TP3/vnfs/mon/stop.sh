#!/usr/bin/env bash
# vnf_mon — pára o Prometheus e o Grafana.
set -uo pipefail
pkill -f /opt/prometheus/prometheus 2>/dev/null || true
pkill -f grafana 2>/dev/null || true
echo "vnf_mon: parado"
