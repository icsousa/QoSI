#!/usr/bin/env bash
# TP3 QoSI — gera um cenário de tráfego sobre a topologia em execução.
#
# Uso:  sudo ./trafego/run_cenario.sh <mistura> [etiqueta] [duracao_s]
#
#   mistura   base       VoIP + ping, sem carga                    (E0)
#             misto      VoIP + vídeo + dados                      (E1/E2/E5)
#             ataque     misto + intruso (UDP 20 Mbit/s + scan)    (E4)
#             degradado  misto com netem no núcleo                 (E3)
#   etiqueta  estado da cadeia, só para nomear resultados (ex.: semqos, comqos, htb-w532)
#   duracao_s duração dos fluxos medidos (omissão: 60)
#
# Resultados em resultados/<mistura>_<etiqueta>_<data>/ + resumo.csv
set -euo pipefail

MIX=${1:?"mistura: base | misto | ataque | degradado"}
TAG=${2:-semqos}
DUR=${3:-60}

ROOT=$(cd "$(dirname "$0")/.." && pwd)
REL="resultados/${MIX}_${TAG}_$(date +%Y%m%d-%H%M%S)"
OUT="$ROOT/$REL"          # visto do anfitrião
OUT_CT="/tp3/$REL"        # visto dentro dos contentores
mkdir -p "$OUT"

SRV_VOIP=10.0.2.11; SRV_VIDEO=10.0.2.12; SRV_BULK=10.0.2.13

dx()  { docker exec "mn.$1" bash -c "$2"; }        # em primeiro plano
dxd() { docker exec -d "mn.$1" bash -c "$2"; }     # em segundo plano

case "$MIX" in base|misto|ataque|degradado) ;; *) echo "mistura inválida: $MIX"; exit 1;; esac
docker inspect mn.h_voip >/dev/null 2>&1 || { echo "A topologia não está a correr (sudo python3 topologia.py)"; exit 1; }

HAS_DITG=0
dx h_voip 'command -v ITGSend' >/dev/null 2>&1 && HAS_DITG=1

limpar() {
  for n in srv_voip srv_video srv_bulk h_voip h_video h_bulk h_intruso; do
    docker exec "mn.$n" pkill -f 'iperf3|ITGRecv|ITGSend' 2>/dev/null || true
  done
  if [ "$MIX" = degradado ]; then
    dx r1 'tc qdisc change dev r1-core root netem delay 10ms rate 100mbit limit 10000' || true
  fi
}
trap limpar EXIT

# ---------------------------------------------------------------- metadados
{
  echo "mistura=$MIX"; echo "etiqueta=$TAG"; echo "duracao_s=$DUR"
  echo "inicio=$(date -Iseconds)"; echo "ditg=$HAS_DITG"
  echo "--- vnf_tc tc-out (antes)"; dx vnf_tc 'tc -s qdisc show dev tc-out'
  echo "--- vnf_fw nftables (antes)"; dx vnf_fw 'nft list ruleset 2>/dev/null || true'
} > "$OUT/meta.txt"

# ---------------------------------------------------------------- degradação
if [ "$MIX" = degradado ]; then
  echo ">> netem no núcleo: perdas 1 %, atraso 50 ± 10 ms"
  dx r1 'tc qdisc change dev r1-core root netem delay 50ms 10ms distribution normal loss 1% rate 100mbit limit 10000'
fi

# ---------------------------------------------------------------- servidores
echo ">> a arrancar servidores"
if [ $HAS_DITG = 1 ]; then
  dxd srv_voip "ITGRecv -l $OUT_CT/voip_recv.log"
else
  dxd srv_voip "iperf3 -s -p 10000"
fi
dxd srv_video "iperf3 -s -p 5004"
dxd srv_bulk  "iperf3 -s -p 5201"
dxd srv_bulk  "iperf3 -s -p 5202"
sleep 2

PIDS=()
# ---------------------------------------------------------------- dados (arrancam primeiro para encher a fila)
if [ "$MIX" != base ]; then
  echo ">> dados: 4 fluxos TCP"
  docker exec mn.h_bulk iperf3 -c $SRV_BULK -p 5201 -P 4 -t $((DUR + 5)) -J > "$OUT/bulk.json" &
  PIDS+=($!)
  sleep 3
fi

# ---------------------------------------------------------------- VoIP
echo ">> VoIP (${DUR}s)"
if [ $HAS_DITG = 1 ]; then
  docker exec mn.h_voip ITGSend -a $SRV_VOIP -rp 10000 -t $((DUR * 1000)) \
      -l "$OUT_CT/voip_send.log" VoIP -x G.711.2 -h RTP > "$OUT/voip_send.txt" 2>&1 &
else
  docker exec mn.h_voip iperf3 -c $SRV_VOIP -p 10000 -u -b 64k -l 160 -t $DUR -J > "$OUT/voip.json" &
fi
PIDS+=($!)

# ping (ICMP, cai na classe best effort) para RTT
docker exec mn.h_voip ping -i 0.2 -c $((DUR * 5)) $SRV_VOIP > "$OUT/ping.txt" &
PIDS+=($!)

# ---------------------------------------------------------------- vídeo
if [ "$MIX" != base ]; then
  echo ">> vídeo: 4 Mbit/s UDP"
  docker exec mn.h_video iperf3 -c $SRV_VIDEO -p 5004 -u -b 4M -l 1316 -t $DUR -J > "$OUT/video.json" &
  PIDS+=($!)
fi

# ---------------------------------------------------------------- intruso
if [ "$MIX" = ataque ]; then
  echo ">> intruso: UDP 20 Mbit/s + varrimento de portas"
  docker exec mn.h_intruso iperf3 -c $SRV_BULK -p 5202 -u -b 20M -t $DUR -J > "$OUT/intruso.json" 2>&1 &
  PIDS+=($!)
  dx h_intruso "for p in \$(seq 20 30); do nc -z -w1 $SRV_VOIP \$p && echo \"\$p aberta\" || echo \"\$p fechada/filtrada\"; done" \
      > "$OUT/intruso_scan.txt" 2>&1 || true
fi

echo ">> à espera dos fluxos..."
for p in "${PIDS[@]}"; do wait "$p" || true; done

# ---------------------------------------------------------------- recolha
if [ $HAS_DITG = 1 ]; then
  sleep 2
  dx srv_voip 'pkill ITGRecv' || true
  sleep 1
  dx srv_voip "ITGDec $OUT_CT/voip_recv.log" > "$OUT/voip_itgdec.txt" 2>&1 || true
fi
{
  echo "--- vnf_tc tc-out (depois)"; dx vnf_tc 'tc -s qdisc show dev tc-out; tc -s class show dev tc-out'
  echo "--- vnf_fw nftables (depois)"; dx vnf_fw 'nft list ruleset 2>/dev/null || true'
  echo "fim=$(date -Iseconds)"
} >> "$OUT/meta.txt"

python3 "$ROOT/trafego/resumo.py" "$OUT"
echo ">> resultados em $REL"
