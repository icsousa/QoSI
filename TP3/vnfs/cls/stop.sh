#!/usr/bin/env bash
# vnf_cls — volta ao simples encaminhamento (sem marcação).
set -uo pipefail

pkill -f "vnfs/cls/marcador.py" 2>/dev/null || true
nft delete table inet cls 2>/dev/null || true
echo "vnf_cls: sem marcação"
