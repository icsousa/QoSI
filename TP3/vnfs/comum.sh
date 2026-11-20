# Funções partilhadas pelos start.sh/stop.sh das VNFs (corre dentro do contentor).
# Uso: . /tp3/vnfs/comum.sh

EXPORTER_PORTA=9101

# IP desta VNF na rede de gestão (interface <nome>-mgmt)
ip_gestao() {
  ip -4 -o addr show | awk '$2 ~ /-mgmt$/ {split($4, a, "/"); print a[1]; exit}'
}

a_escutar() { ss -ltn "sport = :$EXPORTER_PORTA" | grep -q LISTEN; }

# Arranca o exporter de métricas na rede de gestão, se ainda não estiver à escuta
iniciar_exporter() {
  a_escutar && return 0
  parar_exporter
  local ip; ip=$(ip_gestao)
  [ -n "$ip" ] || { echo "sem interface de gestão"; return 1; }
  nohup python3 /tp3/vnfs/exporter.py --ip "$ip" --porta "$EXPORTER_PORTA" \
      >/tmp/exporter.log 2>&1 &
  for _ in $(seq 1 30); do a_escutar && break; sleep 0.1; done
  a_escutar || { echo "exporter não arrancou:"; cat /tmp/exporter.log; return 1; }
  echo "exporter em http://$ip:$EXPORTER_PORTA/metrics"
}

# Pára o exporter e espera que termine (evita corridas com um novo arranque)
parar_exporter() {
  pkill -f "python3 /tp3/vnfs/exporter.py" 2>/dev/null || true
  for _ in $(seq 1 30); do pgrep -f "python3 /tp3/vnfs/exporter.py" >/dev/null || return 0; sleep 0.1; done
}
