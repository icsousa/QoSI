#!/usr/bin/env bash
# TP3 QoSI — orquestração da cadeia de VNFs (corre na VM, com a topologia ativa).
#
# Uso:  sudo ./vnfs/cadeia.sh up     [vnf...]   ativa as VNFs   (omissão: fw cls tc mon)
#       sudo ./vnfs/cadeia.sh down   [vnf...]   volta a "sem QoS" (omissão: todas)
#       sudo ./vnfs/cadeia.sh estado
#
# Modos e parâmetros por variáveis de ambiente (passar com sudo -E ou antes do sudo):
#   CLS_MODO=nft|scapy      TC_MODO=htb|prio
#   TOTAL EF_RATE EF_BURST EF_CEIL VIDEO_RATE VIDEO_CEIL BE_RATE BE_CEIL   (ver vnfs/tc/start.sh)
#
# Exemplos:
#   sudo ./vnfs/cadeia.sh up                            # cadeia completa (E2)
#   sudo ./vnfs/cadeia.sh down fw                       # E4 "sem firewall"
#   sudo TC_MODO=prio ./vnfs/cadeia.sh up tc            # E5 com PRIO
#   sudo VIDEO_RATE=6 BE_RATE=1 ./vnfs/cadeia.sh up tc  # E5, outros pesos
set -euo pipefail

ACAO=${1:?"up | down | estado"}; shift || true
VNFS=("$@")
TODAS=(fw cls tc mon)
[ ${#VNFS[@]} -gt 0 ] || VNFS=("${TODAS[@]}")

docker inspect mn.vnf_fw >/dev/null 2>&1 || { echo "A topologia não está a correr (topologia.py)"; exit 1; }

ENV_TC=()
for v in TOTAL EF_RATE EF_BURST EF_CEIL VIDEO_RATE VIDEO_CEIL BE_RATE BE_CEIL ACCESS_BW; do
  [ -n "${!v:-}" ] && ENV_TC+=(-e "$v=${!v}")
done

run() {   # run <vnf> <script> [args...]
  local vnf=$1 s=$2; shift 2
  docker exec "${ENV_TC[@]}" "mn.vnf_$vnf" bash "/tp3/vnfs/$vnf/$s" "$@"
}

case "$ACAO" in
  up)
    for v in "${TODAS[@]}"; do          # ordem da cadeia, seja qual for a dos argumentos
      [[ " ${VNFS[*]} " == *" $v "* ]] || continue
      case $v in
        cls) run cls start.sh "${CLS_MODO:-nft}" ;;
        tc)  run tc  start.sh "${TC_MODO:-htb}" ;;
        *)   run "$v" start.sh ;;
      esac
    done ;;
  down)
    for v in mon tc cls fw; do
      [[ " ${VNFS[*]} " == *" $v "* ]] || continue
      run "$v" stop.sh
    done
    if [ ${#VNFS[@]} -eq ${#TODAS[@]} ]; then   # tudo em baixo: pára também as sondas
      for v in fw cls tc; do docker exec "mn.vnf_$v" bash -c '. /tp3/vnfs/comum.sh; parar_exporter'; done
    fi ;;
  estado)
    echo "=== vnf_fw";  docker exec mn.vnf_fw  nft list table inet fw  2>/dev/null || echo "(sem regras)"
    echo "=== vnf_cls"; docker exec mn.vnf_cls nft list table inet cls 2>/dev/null || echo "(sem marcação)"
    docker exec mn.vnf_cls pgrep -af marcador.py || true
    echo "=== vnf_tc";  docker exec mn.vnf_tc bash -c 'cat /tmp/vnf_tc.conf 2>/dev/null; tc -s qdisc show dev tc-out; tc -s class show dev tc-out; tc -s filter show dev tc-in ingress'
    echo "=== sondas"
    for v in fw cls tc; do
      printf '  vnf_%-4s ' "$v"; docker exec "mn.vnf_$v" pgrep -f vnfs/exporter.py >/dev/null && echo ativa || echo parada
    done
    echo "=== vnf_mon"
    docker exec mn.vnf_mon curl -sf localhost:9090/api/v1/targets 2>/dev/null \
      | python3 -c 'import json,sys; [print("  ",t["labels"]["instance"],t["health"]) for t in json.load(sys.stdin)["data"]["activeTargets"]]' \
      || echo "  (Prometheus parado)" ;;
  *) echo "ação inválida: $ACAO"; exit 1 ;;
esac
