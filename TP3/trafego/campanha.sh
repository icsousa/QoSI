#!/usr/bin/env bash
# Corre todas as misturas N vezes com a mesma etiqueta (estado da cadeia).
# Uso: sudo ./trafego/campanha.sh <etiqueta> [repeticoes] [duracao_s]
#      ex.: sudo ./vnfs/cadeia.sh down && sudo ./trafego/campanha.sh semqos 5
#           sudo ./vnfs/cadeia.sh up   && sudo ./trafego/campanha.sh comqos 5
# Resultado: resultados/todos_<etiqueta>.csv e resultados/agregado_<etiqueta>.csv
set -euo pipefail
TAG=${1:?"etiqueta, ex.: semqos | comqos"}
REPS=${2:-5}
DUR=${3:-60}
DIR=$(cd "$(dirname "$0")" && pwd)
RES="$DIR/../resultados"

for i in $(seq 1 "$REPS"); do
  for mix in base misto ataque degradado; do
    echo "=== $mix ($TAG) repetição $i/$REPS"
    "$DIR/run_cenario.sh" "$mix" "${TAG}-r$i" "$DUR"
    sleep 5
  done
done
python3 "$DIR/resumo.py" --saida "$RES/todos_$TAG.csv" "$RES"/*_"$TAG"-r*
python3 "$DIR/agregar.py" --saida "$RES/agregado_$TAG.csv" "$RES/todos_$TAG.csv"
