#!/usr/bin/env bash
# vnf_tc — repõe o estado sem QoS: só o tbf que emula a ligação de acesso.
# ACCESS_BW tem de coincidir com o --access-bw do topologia.py (omissão 10).
set -uo pipefail
ACCESS_BW=${ACCESS_BW:-10}

tc qdisc del dev tc-in ingress 2>/dev/null || true
tc qdisc replace dev tc-out root tbf rate ${ACCESS_BW}mbit burst 32kbit latency 100ms
rm -f /tmp/vnf_tc.conf
echo "vnf_tc: sem QoS (tbf ${ACCESS_BW} Mbit/s, FIFO)"
