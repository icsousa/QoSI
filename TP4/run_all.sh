#!/bin/bash
# Corre todas as simulacoes do TP4 e gera os ficheiros .gr, estatisticas e graficos.
# Uso (na VM com NS-2):   chmod +x run_all.sh && ./run_all.sh
set -e
BASE=$(cd "$(dirname "$0")" && pwd)
AWK=$(command -v gawk || command -v awk)
NS=$(command -v ns || true)
[ -z "$NS" ] && { echo "ns nao encontrado no PATH"; exit 1; }

# run <cenario> <script.tcl> [args]  -> results/<cenario>/
run() {
    local nome=$1 script=$2; shift 2
    local dir="$BASE/results/$nome"
    rm -rf "$dir"; mkdir -p "$dir"; cd "$dir"
    echo "== $nome: ns $script $*"
    "$NS" "$BASE/$script" "$@" > stats.txt 2>&1 || { echo "ERRO em $nome (ver $dir/stats.txt)"; cat stats.txt; exit 1; }
    local tr; tr=$(ls *.tr | head -1)
    grep "^d" "$tr" | $AWK -f "$BASE/loss.awk"                        || true
    grep "^r" "$tr" | $AWK -v s=3 -v d=4 -v outf=bw   -f "$BASE/bw_link.awk"   # link E1->C0
    grep "^r" "$tr" | $AWK -v s=5 -v d=4 -v outf=bwE2 -f "$BASE/bw_link.awk"   # link E2->C0
    # contagem de perdas por link (no origem -> no destino) para a A.1
    grep "^d" "$tr" | $AWK '{n[$3"->"$4]++} END{for(l in n) print l, n[l]}' | sort > drops_por_link.txt || true
    rm -f *.nam
    cd "$BASE"
}

run A_droptail qos0.tcl
run A_red      qos0_red.tcl
run B          qosB.tcl
# qos1 com impressao do tamanho maximo das filas (memoria) - Tarefa C.1
sed 's|^\$ns run|puts "limit_ E1C0 = [$q(E1C0) set limit_] pacotes"\nputs "limit_ C0E2 = [$q(C0E2) set limit_] pacotes"\n$ns run|' qos1.tcl > qos1_info.tcl
run C_diffserv qos1_info.tcl
run C4_ds      qosC4.tcl ds
run C4_rio     qosC4.tcl rio
run C4_be      qosC4.tcl be

# Graficos (PNG) + resumo numerico; se nao houver matplotlib usa-se xgraph
for d in results/*/; do python3 "$BASE/plot.py" "$d" || true; done
echo
echo "Feito. Resultados em results/<cenario>/ (summary.txt, stats.txt, *.png, *.gr)"
echo "Alternativa: cd results/A_droptail && xgraph loss*.gr  /  xgraph bw*.gr"
