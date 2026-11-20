#!/usr/bin/env bash
# TP3 QoSI — testa cada VNF isoladamente com tráfego controlado (fase 2).
#
# Uso:  sudo ./vnfs/testar.sh <fw|cls|cls-scapy|tc|mon|todas>
#
# Cada teste desativa a cadeia toda, ativa só a VNF em teste, gera tráfego
# conhecido e verifica o resultado. Saída também em resultados/testes/.
set -uo pipefail

ALVO=${1:?"fw | cls | cls-scapy | tc | mon | todas"}
ROOT=$(cd "$(dirname "$0")/.." && pwd)
CADEIA="$ROOT/vnfs/cadeia.sh"
mkdir -p "$ROOT/resultados/testes"

SRV_VOIP=10.0.2.11; SRV_VIDEO=10.0.2.12; SRV_BULK=10.0.2.13
OK=0; FALHAS=0

dx()  { docker exec "mn.$1" bash -c "$2"; }
dxd() { docker exec -d "mn.$1" bash -c "$2"; }
verifica() {   # verifica "<descrição>" <0=passou|outro=falhou>
  if [ "$2" -eq 0 ]; then echo "  [OK]     $1"; OK=$((OK+1))
  else echo "  [FALHOU] $1"; FALHAS=$((FALHAS+1)); fi
}
servidores() {
  for n in srv_voip srv_video srv_bulk; do docker exec "mn.$n" pkill -f 'iperf|ITGRecv' 2>/dev/null || true; done
  dxd srv_voip  "iperf3 -s -p 10000"
  dxd srv_voip  "ITGRecv >/dev/null 2>&1" 2>/dev/null || true
  dxd srv_video "iperf3 -s -p 5004"
  dxd srv_bulk  "iperf3 -s -p 5201"
  dxd srv_bulk  "iperf3 -s -p 6000"     # porta com servidor, mas fora da lista branca
  dxd srv_bulk  "iperf -s -u -p 5202 > /tmp/iperf2_5202.txt 2>&1"
  sleep 1
}
contador() {   # contador <vnf> <tabela> <nome> -> pacotes
  dx "vnf_$1" "nft -j list counter inet $2 $3" \
    | python3 -c 'import json,sys; print([o["counter"]["packets"] for o in json.load(sys.stdin)["nftables"] if "counter" in o][0])'
}
mbps_recebido() {   # débito no recetor, a partir do JSON do cliente iperf3
  python3 -c 'import json,sys
e=json.load(sys.stdin)["end"]
s=e.get("sum_received") or e["sum"]
print(round(s["bits_per_second"]*(1-s.get("lost_percent",0)/100)/1e6,2))'
}

# ------------------------------------------------------------------- fw
testar_fw() {
  echo "### vnf_fw — controlo de acesso"
  "$CADEIA" down >/dev/null; "$CADEIA" up fw || { verifica "vnf_fw arranca" 1; return; }; servidores
  local b0; b0=$(contador fw fw bloqueado)

  dx h_voip "ping -c 2 -W 1 $SRV_VOIP" >/dev/null;              verifica "h_voip ping srv_voip passa" $?
  dx h_intruso "ping -c 2 -W 1 $SRV_VOIP" >/dev/null;           verifica "h_intruso ping srv_voip é bloqueado" $((! $?))
  dx h_bulk "iperf3 -c $SRV_BULK -p 5201 -t 3" >/dev/null 2>&1; verifica "h_bulk TCP 5201 passa" $?
  dx h_bulk "nc -z -w2 $SRV_BULK 6000" >/dev/null 2>&1;         verifica "h_bulk TCP 6000 (porta fora da lista) é bloqueado" $((! $?))
  dx h_intruso "nc -z -w2 $SRV_BULK 5201" >/dev/null 2>&1;      verifica "h_intruso TCP 5201 (IP fora da lista) é bloqueado" $((! $?))
  dx h_video "iperf3 -c $SRV_VIDEO -p 5004 -u -b 1M -t 2" >/dev/null 2>&1; verifica "h_video UDP 5004 passa" $?

  dx h_intruso "iperf -c $SRV_BULK -u -p 5202 -b 20M -t 3" >/dev/null 2>&1
  local rec; rec=$(dx srv_bulk "grep -c 'sec' /tmp/iperf2_5202.txt" || true)
  verifica "UDP 20 Mbit/s do intruso não chega ao servidor" "$([ "${rec:-0}" -eq 0 ] && echo 0 || echo 1)"

  local scan; scan=$(dx h_intruso "nmap -Pn -sT -p 20-30 --max-retries 1 $SRV_VOIP" 2>/dev/null)
  echo "$scan" | grep -q "filtered" && ! echo "$scan" | grep -qE "^[0-9]+/tcp +(open|closed)"
  verifica "varrimento de portas: todas 'filtered'" $?

  local b1; b1=$(contador fw fw bloqueado)
  echo "  contador 'bloqueado': $b0 -> $b1 (+$((b1 - b0)) pacotes)"
  verifica "contador de bloqueados subiu" "$([ "$b1" -gt "$b0" ] && echo 0 || echo 1)"
}

# ------------------------------------------------------------------- cls
dscp_visto() {   # dscp_visto <host> "<comando de envio>" <filtro tcpdump> -> tos do último pacote visto na vnf_tc
  dx vnf_tc "timeout 6 tcpdump -i tc-in -n -v -c 10 '$3' 2>/dev/null" > /tmp/qosi_tcpdump.txt &
  local p=$!; sleep 1
  dx "$1" "$2" >/dev/null 2>&1
  wait $p
  grep -o 'tos 0x[0-9a-f]*' /tmp/qosi_tcpdump.txt | tail -1 | awk '{print $2}'
}
testar_cls() {
  local modo=${1:-nft}
  echo "### vnf_cls — classificação DSCP (modo $modo)"
  "$CADEIA" down >/dev/null; CLS_MODO=$modo "$CADEIA" up cls || { verifica "vnf_cls arranca" 1; return; }; servidores
  local t

  if [ "$modo" = nft ]; then
    t=$(dscp_visto h_voip "iperf3 -c $SRV_VOIP -p 10000 -u -b 64k -l 160 -t 2" 'udp dst port 10000')
    echo "  VoIP UDP 10000, 160 B  -> tos $t";   verifica "VoIP pequeno marcado EF (0xb8)" "$([ "$t" = 0xb8 ] && echo 0 || echo 1)"
    t=$(dscp_visto h_voip "iperf3 -c $SRV_VOIP -p 10000 -u -b 1M -l 1000 -t 2" 'udp dst port 10000 and greater 500')
    echo "  UDP 10000, 1000 B      -> tos $t";   verifica "pacote grande na porta VoIP fica BE (0x0)" "$([ "$t" = 0x0 ] && echo 0 || echo 1)"
  else
    t=$(dscp_visto h_voip "ITGSend -a $SRV_VOIP -rp 10000 -t 2000 VoIP -x G.711.2 -h RTP" 'udp dst port 10000')
    echo "  D-ITG G.711 (50 pps)   -> tos $t";   verifica "fluxo com perfil de voz marcado EF (0xb8)" "$([ "$t" = 0xb8 ] && echo 0 || echo 1)"
    t=$(dscp_visto h_voip "python3 -c \"from scapy.all import *; send(IP(dst='$SRV_VOIP')/UDP(sport=4000,dport=10050)/(bytes([0x80,0])+bytes(170)), count=3, inter=0.5, verbose=0)\"" 'udp dst port 10050')
    echo "  RTP v2 isolado (Scapy) -> tos $t";   verifica "pacote com cabeçalho RTP marcado EF (0xb8)" "$([ "$t" = 0xb8 ] && echo 0 || echo 1)"
    t=$(dscp_visto h_voip "iperf3 -c $SRV_VOIP -p 10000 -u -b 1M -l 160 -t 2" 'udp dst port 10000')
    echo "  UDP 10000 a 780 pps    -> tos $t";   verifica "UDP pequeno sem perfil de voz fica BE (0x0)" "$([ "$t" = 0x0 ] && echo 0 || echo 1)"
    dx vnf_cls "cat /tmp/marcador.json 2>/dev/null; echo"
  fi
  t=$(dscp_visto h_video "iperf3 -c $SRV_VIDEO -p 5004 -u -b 1M -l 1316 -t 2" 'udp dst port 5004')
  echo "  Vídeo UDP 5004         -> tos $t";   verifica "vídeo marcado AF41 (0x88)" "$([ "$t" = 0x88 ] && echo 0 || echo 1)"
  t=$(dscp_visto h_bulk "iperf3 -c $SRV_BULK -p 5201 -S 0xb8 -t 2" 'tcp dst port 5201 and greater 500')
  echo "  TCP 5201 com tos 0xb8  -> tos $t";   verifica "marca do cliente apagada no best effort (0x0)" "$([ "$t" = 0x0 ] && echo 0 || echo 1)"
  dx vnf_cls "nft list counters table inet cls" | grep -A1 'counter' | grep -v '^--'
}

# ------------------------------------------------------------------- tc
testar_tc() {
  echo "### vnf_tc — policiamento e agendamento (HTB)"
  "$CADEIA" down >/dev/null; "$CADEIA" up tc || { verifica "vnf_tc arranca" 1; return; }; servidores
  local r

  # Sem classificador, as marcas vêm da origem (iperf3 -S) para isolar a vnf_tc
  r=$(dx h_bulk "iperf3 -c $SRV_BULK -p 5201 -t 8 -J" | python3 -c 'import json,sys; print(round(json.load(sys.stdin)["end"]["sum_received"]["bits_per_second"]/1e6,2))')
  echo "  TCP sozinho (BE): $r Mbit/s"
  verifica "BE sozinho usa a capacidade do limitador (8,5-9,6 Mbit/s)" "$(python3 -c "print(0 if 8.5<=$r<=9.6 else 1)")"

  r=$(dx h_voip "iperf3 -c $SRV_VOIP -p 10000 -u -b 3M -l 160 -S 0xb8 -t 5 -J" | mbps_recebido)
  echo "  EF a 3 Mbit/s: chegam $r Mbit/s"
  verifica "policiamento EF limita a ~1 Mbit/s (0,8-1,2)" "$(python3 -c "print(0 if 0.8<=$r<=1.2 else 1)")"

  # Vídeo AF41 a 4 Mbit/s com BE a saturar: o vídeo tem 5 Mbit/s garantidos
  dx h_bulk "iperf3 -c $SRV_BULK -p 5201 -P 4 -t 12" >/dev/null 2>&1 &
  local p=$!; sleep 2
  r=$(dx h_video "iperf3 -c $SRV_VIDEO -p 5004 -u -b 4M -l 1316 -S 0x88 -t 8 -J" | mbps_recebido)
  wait $p
  echo "  AF41 4 Mbit/s com BE saturado: chegam $r Mbit/s"
  verifica "vídeo mantém ~4 Mbit/s com congestionamento (>= 3,9)" "$(python3 -c "print(0 if $r>=3.9 else 1)")"

  dx vnf_tc "tc -s class show dev tc-out | grep -A2 'htb 1:[123]0'; tc -s filter show dev tc-in ingress | grep -E 'Sent|police|drop'"
}

# ------------------------------------------------------------------- mon
testar_mon() {
  echo "### vnf_mon — Prometheus + Grafana"
  "$CADEIA" down >/dev/null
  for v in fw cls tc; do dx "vnf_$v" ". /tp3/vnfs/comum.sh; iniciar_exporter" >/dev/null; done
  "$CADEIA" up mon || { verifica "vnf_mon arranca" 1; return; }
  local up=0
  for _ in $(seq 1 15); do     # o Prometheus marca os alvos como "unknown" até à 1.ª recolha
    sleep 1
    up=$(dx vnf_mon "curl -sf localhost:9090/api/v1/targets" | python3 -c 'import json,sys; print(sum(t["health"]=="up" for t in json.load(sys.stdin)["data"]["activeTargets"]))')
    [ "$up" = 3 ] && break
  done
  echo "  alvos 'up' no Prometheus: $up/3"; verifica "Prometheus recolhe as 3 sondas" "$([ "$up" = 3 ] && echo 0 || echo 1)"
  local n
  n=$(dx vnf_mon "curl -sf 'localhost:9090/api/v1/query?query=qosi_cpu_seconds_total'" | python3 -c 'import json,sys; print(len(json.load(sys.stdin)["data"]["result"]))')
  verifica "métrica de CPU disponível para as 3 VNFs ($n)" "$([ "$n" = 3 ] && echo 0 || echo 1)"
  dx vnf_mon "curl -sf localhost:3000/api/search?query=QoSI" | grep -q qosi-vnfs
  verifica "Grafana com o dashboard 'QoSI TP3' provisionado" $?
}

# ------------------------------------------------------------------- main
LOG="$ROOT/resultados/testes/${ALVO}_$(date +%Y%m%d-%H%M%S).txt"
{
  case "$ALVO" in
    fw) testar_fw ;;
    cls) testar_cls nft ;;
    cls-scapy) testar_cls scapy ;;
    tc) testar_tc ;;
    mon) testar_mon ;;
    todas) testar_fw; testar_cls nft; testar_cls scapy; testar_tc; testar_mon ;;
    *) echo "alvo inválido: $ALVO"; exit 1 ;;
  esac
  for n in srv_voip srv_video srv_bulk; do docker exec "mn.$n" pkill -f 'iperf|ITGRecv' 2>/dev/null || true; done
  "$CADEIA" down >/dev/null
  echo "=== $OK passaram, $FALHAS falharam"
} 2>&1 | tee "$LOG"
echo "(registo em ${LOG#$ROOT/})"
