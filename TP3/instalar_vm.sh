#!/usr/bin/env bash
# TP3 QoSI — prepara uma VM Ubuntu 22.04 (amd64 ou arm64) para correr a topologia.
#
# Uso (como utilizador normal, não como root, a partir da pasta TP3):
#   ./instalar_vm.sh
#
# Instala o Containernet em ~/containernet (com venv, obrigatório desde o
# Ubuntu 22.04 por causa do setuptools) e constrói a imagem qosi/base.
set -euo pipefail

[ "$(id -u)" -ne 0 ] || { echo "Corre como utilizador normal (o script usa sudo quando precisa)."; exit 1; }
TP3=$(cd "$(dirname "$0")" && pwd)
CN="$HOME/containernet"

echo ">> arquitetura: $(dpkg --print-architecture)"

echo ">> dependências base"
sudo apt-get update
sudo apt-get install -y git ansible python3-venv

echo ">> Containernet (Docker, Open vSwitch, Mininet)"
[ -d "$CN" ] || git clone https://github.com/containernet/containernet.git "$CN"
sudo ansible-playbook -i "localhost," -c local "$CN/ansible/install.yml"

echo ">> venv do Containernet"
[ -d "$CN/venv" ] || python3 -m venv "$CN/venv"
"$CN/venv/bin/pip" install --upgrade pip
(cd "$CN" && "$CN/venv/bin/pip" install .)

echo ">> imagem Docker dos nós"
sudo docker build -t qosi/base:latest "$TP3/docker/"

cat <<EOF

Instalação concluída. Para testar:
  source $CN/venv/bin/activate
  cd $TP3
  sudo -E env PATH=\$PATH python3 topologia.py --check
EOF
