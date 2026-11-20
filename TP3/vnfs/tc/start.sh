#!/usr/bin/env bash
# vnf_tc — policiamento e agendamento (corre dentro de mn.vnf_tc).
#
# Uso: start.sh [htb|prio]       (omissão: htb)
#
#   Policiamento (tc-in, entrada): token bucket só na classe EF.
#   Agendamento (tc-out, saída):  limita a 9,5 Mbit/s, abaixo dos 10 Mbit/s do
#                                 acesso, para a fila se formar aqui.
#     htb : EF 1:10 prio 0 | AF41 1:20 prio 1 | BE 1:30 prio 2 + fq_codel
#     prio: PRIO de 3 bandas (estrita) dentro de um HTB a 9,5 Mbit/s (E5)
#
# Parâmetros (variáveis de ambiente, em Mbit/s salvo indicação):
#   TOTAL=9.5  EF_RATE=1  EF_BURST=10k  VIDEO_RATE=5  VIDEO_CEIL=9  BE_RATE=2  BE_CEIL=9.5
#   EF_CEIL=1.5: teto da classe HTB do EF. Fica acima do policiamento porque o
#   HTB conta o cabeçalho Ethernet e o police não; com o mesmo valor o EF era
#   limitado duas vezes.
set -euo pipefail
. /tp3/vnfs/comum.sh

MODO=${1:-htb}
TOTAL=${TOTAL:-9.5}
EF_RATE=${EF_RATE:-1};       EF_BURST=${EF_BURST:-10k}; EF_CEIL=${EF_CEIL:-1.5}
VIDEO_RATE=${VIDEO_RATE:-5}; VIDEO_CEIL=${VIDEO_CEIL:-9}
BE_RATE=${BE_RATE:-2};       BE_CEIL=${BE_CEIL:-$TOTAL}

OUT=tc-out; IN=tc-in
EF_MATCH="match ip dsfield 0xb8 0xfc"      # DSCP 46 << 2
AF41_MATCH="match ip dsfield 0x88 0xfc"    # DSCP 34 << 2

tc qdisc del dev $OUT root    2>/dev/null || true
tc qdisc del dev $IN  ingress 2>/dev/null || true

# ------------------------------------------------------------ policiamento EF
# Token bucket: o que exceder EF_RATE com rajada EF_BURST é descartado aqui,
# para o EF não poder usar a prioridade para esmagar as outras classes.
tc qdisc add dev $IN handle ffff: ingress
tc filter add dev $IN parent ffff: protocol ip prio 1 u32 $EF_MATCH \
   action police rate ${EF_RATE}mbit burst $EF_BURST conform-exceed drop/ok

# ------------------------------------------------------------ agendamento
case "$MODO" in
  htb)
    tc qdisc add dev $OUT root handle 1: htb default 30
    tc class add dev $OUT parent 1: classid 1:1 htb rate ${TOTAL}mbit ceil ${TOTAL}mbit
    tc class add dev $OUT parent 1:1 classid 1:10 htb rate ${EF_RATE}mbit    ceil ${EF_CEIL}mbit    prio 0
    tc class add dev $OUT parent 1:1 classid 1:20 htb rate ${VIDEO_RATE}mbit ceil ${VIDEO_CEIL}mbit prio 1
    tc class add dev $OUT parent 1:1 classid 1:30 htb rate ${BE_RATE}mbit    ceil ${BE_CEIL}mbit    prio 2
    tc qdisc add dev $OUT parent 1:10 handle 10: pfifo limit 50
    tc qdisc add dev $OUT parent 1:20 handle 20: pfifo limit 100
    tc qdisc add dev $OUT parent 1:30 handle 30: fq_codel
    tc filter add dev $OUT parent 1: protocol ip prio 1 u32 $EF_MATCH   flowid 1:10
    tc filter add dev $OUT parent 1: protocol ip prio 2 u32 $AF41_MATCH flowid 1:20
    ;;
  prio)
    # Uma só classe HTB (o limitador) com PRIO estrito por baixo.
    # priomap todo a 2: o que não for EF/AF41 vai para a banda 3 (BE).
    tc qdisc add dev $OUT root handle 1: htb default 1
    tc class add dev $OUT parent 1: classid 1:1 htb rate ${TOTAL}mbit ceil ${TOTAL}mbit
    tc qdisc add dev $OUT parent 1:1 handle 10: prio bands 3 priomap 2 2 2 2 2 2 2 2 2 2 2 2 2 2 2 2
    tc qdisc add dev $OUT parent 10:1 handle 11: pfifo limit 50
    tc qdisc add dev $OUT parent 10:2 handle 12: pfifo limit 100
    tc qdisc add dev $OUT parent 10:3 handle 13: fq_codel
    tc filter add dev $OUT parent 10: protocol ip prio 1 u32 $EF_MATCH   flowid 10:1
    tc filter add dev $OUT parent 10: protocol ip prio 2 u32 $AF41_MATCH flowid 10:2
    ;;
  *) echo "modo inválido: $MODO (htb|prio)"; exit 1 ;;
esac

cat > /tmp/vnf_tc.conf <<EOF
modo=$MODO total=$TOTAL ef_rate=$EF_RATE ef_burst=$EF_BURST video=$VIDEO_RATE/$VIDEO_CEIL be=$BE_RATE/$BE_CEIL
EOF
echo "vnf_tc: $(cat /tmp/vnf_tc.conf)"
iniciar_exporter
