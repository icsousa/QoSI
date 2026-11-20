#!/usr/bin/env bash
# vnf_mon — arranca o Prometheus e o Grafana (corre dentro de mn.vnf_mon).
#   Prometheus: http://<VM>:9090   Grafana: http://<VM>:3000 (dashboard "QoSI TP3")
set -euo pipefail
D=/tp3/vnfs/mon

command -v grafana-server >/dev/null && [ -x /opt/prometheus/prometheus ] || {
  echo "vnf_mon: falta a imagem qosi/mon (sudo docker build -t qosi/mon:latest -f docker/Dockerfile.mon docker/)"
  exit 1; }

pkill -f /opt/prometheus/prometheus 2>/dev/null || true
pkill -f grafana 2>/dev/null || true
sleep 1

nohup /opt/prometheus/prometheus \
    --config.file=$D/prometheus.yml \
    --storage.tsdb.path=/tmp/prometheus \
    --web.listen-address=0.0.0.0:9090 \
    >/tmp/prometheus.log 2>&1 &

# Acesso anónimo como administrador: é um laboratório isolado na VM.
export GF_PATHS_PROVISIONING=$D/grafana/provisioning
export GF_PATHS_DATA=/tmp/grafana
export GF_AUTH_ANONYMOUS_ENABLED=true
export GF_AUTH_ANONYMOUS_ORG_ROLE=Admin
export GF_AUTH_DISABLE_LOGIN_FORM=true
export GF_DASHBOARDS_DEFAULT_HOME_DASHBOARD_PATH=$D/grafana/dashboards/qosi.json
export GF_ANALYTICS_REPORTING_ENABLED=false
export GF_ANALYTICS_CHECK_FOR_UPDATES=false
nohup grafana-server --homepath /usr/share/grafana \
    >/tmp/grafana.log 2>&1 &

for i in $(seq 1 30); do
  curl -sf localhost:9090/-/ready >/dev/null && curl -sf localhost:3000/api/health >/dev/null && break
  sleep 1
done
curl -sf localhost:9090/-/ready >/dev/null || { echo "Prometheus não arrancou"; tail /tmp/prometheus.log; exit 1; }
curl -sf localhost:3000/api/health >/dev/null || { echo "Grafana não arrancou"; tail /tmp/grafana.log; exit 1; }
echo "vnf_mon: Prometheus :9090 e Grafana :3000 ativos"
