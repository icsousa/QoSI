#!/usr/bin/env bash
# vnf_fw — ativa o controlo de acesso (corre dentro de mn.vnf_fw).
set -euo pipefail
. /tp3/vnfs/comum.sh

nft -f /tp3/vnfs/fw/regras.nft
echo "vnf_fw: lista branca ativa (policy drop)"
iniciar_exporter
