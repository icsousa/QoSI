#!/usr/bin/env bash
# TP3 QoSI — gera um cenário de tráfego sobre a topologia em execução.
#
# Uso:  sudo ./trafego/run_cenario.sh <mistura> [etiqueta] [duracao_s]
#
#   mistura   base       VoIP + ping, sem carga                    (E0)
#             misto      VoIP + vídeo + dados                      (E1/E2/E5)
#             ataque     misto + intruso (UDP 20 Mbit/s + scan)    (E4)
#             degradado  misto com netem no núcleo, nos dois sentidos (E3)
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

# Parâmetros atuais do netem do núcleo (os do --core-delay/--core-bw do topologia.py),
# para o cenário "degradado" os repor no fim em vez de assumir 10 ms / 100 Mbit/s.
netem_atual() {   # netem_atual <nó> <intf> -> "delay X rate Y"
  dx "$1" "tc qdisc show dev $2" | sed -n 's/.*delay \([^ ]*\).*rate \([^ ]*\).*/delay \1 rate \2/p' | head -1
}
NUCLEO=( "r1 r1-core" "r2 r2-core" )
declare -A NETEM_ORIG=()
for par in "${NUCLEO[@]}"; do set -- $par; NETEM_ORIG[$1]=$(netem_atual "$1" "$2"); done

limpar() {
  for n in srv_voip srv_video srv_bulk h_voip h_video h_bulk h_intruso; do
    docker exec "mn.$n" pkill -f 'iperf|ITGRecv|ITGSend' 2>/dev/null || true
  done
  if [ "$MIX" = degradado ]; then
    for par in "${NUCLEO[@]}"; do
      set -- $par
      dx "$1" "tc qdisc change dev $2 root netem ${NETEM_ORIG[$1]} limit 10000" || true
    done
  fi
}
trap limpar EXIT

# ---------------------------------------------------------------- metadados
{
  echo "mistura=$MIX"; echo "etiqueta=$TAG"; echo "duracao_s=$DUR"
  echo "inicio=$(date -Iseconds)"; echo "ditg=$HAS_DITG"
  echo "--- vnf_tc tc-out (antes)"; dx vnf_tc 'tc -s qdisc show dev tc-out'
  echo "--- vnf_fw nftables (antes)"; dx vnf_fw 'nft list ruleset 2>/dev/null || true'
  echo "--- vnf_cls nftables (antes)"; dx vnf_cls 'nft list ruleset 2>/dev/null || true'
  echo "--- vnf_tc config"; dx vnf_tc 'cat /tmp/vnf_tc.conf 2>/dev/null || echo sem QoS'
  echo "--- núcleo"; for par in "${NUCLEO[@]}"; do set -- $par; echo "$1: ${NETEM_ORIG[$1]}"; done
} > "$OUT/meta.txt"

# ---------------------------------------------------------------- degradação
if [ "$MIX" = degradado ]; then
  echo ">> netem no núcleo (dois sentidos): perdas 1 %, atraso 50 ± 10 ms"
  for par in "${NUCLEO[@]}"; do
    set -- $par
    rate=$(sed -n 's/.*rate \(.*\)/\1/p' <<< "${NETEM_ORIG[$1]}")
    dx "$1" "tc qdisc change dev $2 root netem delay 50ms 10ms distribution normal loss 1% rate ${rate:-100mbit} limit 10000"
  done
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
if [ "$MIX" = ataque ]; then   # iperf2: recetor do intruso (mede o que passa a firewall)
  dxd srv_bulk "iperf -s -u -p 5202 -i 1 > $OUT_CT/intruso_srv.txt 2>&1"
fi
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
  # iperf (v2) em UDP não tem ligação de controlo: envia mesmo com a firewall
  # a bloquear, que é o que se quer medir. O nmap distingue "closed" (sem
  # firewall, o servidor responde RST) de "filtered" (descartado na vnf_fw).
  echo ">> intruso: UDP 20 Mbit/s + varrimento de portas"
  docker exec mn.h_intruso iperf -c $SRV_BULK -u -p 5202 -b 20M -t $DUR > "$OUT/intruso_cli.txt" 2>&1 &
  PIDS+=($!)
  dx h_intruso "nmap -Pn -sT -p 20-30 --max-retries 1 $SRV_VOIP" > "$OUT/intruso_scan.txt" 2>&1 || true
fi

echo ">> à espera dos fluxos..."
for p in "${PIDS[@]}"; do wait "$p" || true; done
docker exec mn.srv_bulk pkill -INT -f 'iperf -s' 2>/dev/null || true   # fecha o relatório do iperf2

# ---------------------------------------------------------------- recolha
if [ $HAS_DITG = 1 ]; then
  sleep 2
  dx srv_voip 'pkill ITGRecv' || true
  sleep 1
  dx srv_voip "ITGDec $OUT_CT/voip_recv.log" > "$OUT/voip_itgdec.txt" 2>&1 || true
fi
{
  echo "--- vnf_tc tc-out (depois)"; dx vnf_tc 'tc -s qdisc show dev tc-out; tc -s class show dev tc-out'
  echo "--- vnf_tc policiamento (depois)"; dx vnf_tc 'tc -s filter show dev tc-in ingress 2>/dev/null'
  echo "--- vnf_fw nftables (depois)"; dx vnf_fw 'nft list ruleset 2>/dev/null || true'
  echo "--- vnf_cls nftables (depois)"; dx vnf_cls 'nft list ruleset 2>/dev/null || true'
  echo "fim=$(date -Iseconds)"
} >> "$OUT/meta.txt"

python3 "$ROOT/trafego/resumo.py" "$OUT"
echo ">> resultados em $REL"
