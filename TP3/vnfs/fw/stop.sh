#!/usr/bin/env bash
# vnf_fw — volta ao simples encaminhamento (sem firewall).
set -uo pipefail
. /tp3/vnfs/comum.sh

# O exporter fica a correr (CPU e interfaces continuam a ser medidos);
# quem o pára é o "cadeia.sh down".
nft delete table inet fw 2>/dev/null || true
echo "vnf_fw: sem regras (encaminha tudo)"
