#!/usr/bin/env bash
# vnf_cls — ativa a classificação DSCP (corre dentro de mn.vnf_cls).
# Uso: start.sh [nft|scapy]      (omissão: nft)
set -euo pipefail
. /tp3/vnfs/comum.sh
MODO=${1:-nft}

pkill -f "vnfs/cls/marcador.py" 2>/dev/null || true
case "$MODO" in
  nft)
    nft -f /tp3/vnfs/cls/regras.nft
    ;;
  scapy)
    nft -f /tp3/vnfs/cls/regras_scapy.nft
    rm -f /tmp/marcador.json
    nohup python3 /tp3/vnfs/cls/marcador.py >/tmp/marcador.log 2>&1 &
    sleep 1
    pgrep -f "vnfs/cls/marcador.py" >/dev/null \
      || { echo "marcador.py não arrancou:"; cat /tmp/marcador.log; exit 1; }
    ;;
  *) echo "modo inválido: $MODO (nft|scapy)"; exit 1 ;;
esac
echo "vnf_cls: marcação DSCP ativa (modo $MODO)"
iniciar_exporter
