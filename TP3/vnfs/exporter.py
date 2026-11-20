#!/usr/bin/env python3
"""
Exporter Prometheus das VNFs (sonda virtual). Corre em cada VNF e serve
/metrics na rede de gestão; a vnf_mon recolhe-o com o Prometheus.

Métricas (todas com a etiqueta vnf=<hostname>):
  qosi_cpu_seconds_total                         CPU gasto pelo contentor (cgroup)
  qosi_intf_{rx,tx}_{bytes,packets,dropped}_total{intf}
  qosi_nft_{packets,bytes}_total{table,counter}  contadores com nome do nftables
  qosi_tc_{bytes,packets,drops,overlimits}_total{dev,kind,id}  classes e qdiscs
  qosi_tc_backlog_bytes{dev,kind,id}
  qosi_tc_police_{packets,drops}_total{dev}      token bucket da classe EF
  qosi_marcador_{pacotes_total,proc_seconds_total}{resultado}  (modo scapy)

Só usa a biblioteca padrão. Uso: exporter.py --ip 10.0.100.4 --porta 9101
"""
import argparse
import json
import os
import re
import socket
import socketserver
import subprocess
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

VNF = socket.gethostname()


def cmd_json(args):
    try:
        out = subprocess.run(args, capture_output=True, text=True, timeout=3).stdout
        return json.loads(out) if out.strip() else None
    except (OSError, ValueError, subprocess.TimeoutExpired):
        return None


def esc(v):
    return str(v).replace('\\', '\\\\').replace('"', '\\"')


class Metricas:
    def __init__(self):
        self.linhas, self.tipos = [], {}

    def add(self, nome, valor, tipo='counter', **etq):
        if valor is None:
            return
        self.tipos.setdefault(nome, tipo)
        etq = {'vnf': VNF, **etq}
        e = ','.join(f'{k}="{esc(v)}"' for k, v in etq.items())
        self.linhas.append(f'{nome}{{{e}}} {valor}')

    def texto(self):
        cab = [f'# TYPE {n} {t}' for n, t in self.tipos.items()]
        return '\n'.join(cab + self.linhas) + '\n'


def cpu(m):
    try:      # cgroup v2
        for l in open('/sys/fs/cgroup/cpu.stat'):
            if l.startswith('usage_usec'):
                m.add('qosi_cpu_seconds_total', int(l.split()[1]) / 1e6)
                return
    except OSError:
        pass
    try:      # cgroup v1
        m.add('qosi_cpu_seconds_total',
              int(open('/sys/fs/cgroup/cpuacct/cpuacct.usage').read()) / 1e9)
    except (OSError, ValueError):
        pass


def interfaces(m):
    base = '/sys/class/net'
    for intf in sorted(os.listdir(base)):
        if intf == 'lo' or intf.startswith('eth'):     # eth0 é a ponte do Docker
            continue
        for sentido in ('rx', 'tx'):
            for campo in ('bytes', 'packets', 'dropped'):
                try:
                    v = int(open(f'{base}/{intf}/statistics/{sentido}_{campo}').read())
                except (OSError, ValueError):
                    continue
                m.add(f'qosi_intf_{sentido}_{campo}_total', v, intf=intf)


def nft(m):
    d = cmd_json(['nft', '-j', 'list', 'counters'])
    for obj in (d or {}).get('nftables', []):
        c = obj.get('counter')
        if c:
            m.add('qosi_nft_packets_total', c['packets'], table=c['table'], counter=c['name'])
            m.add('qosi_nft_bytes_total', c['bytes'], table=c['table'], counter=c['name'])


def cmd_txt(args):
    try:
        return subprocess.run(args, capture_output=True, text=True, timeout=3).stdout
    except (OSError, subprocess.TimeoutExpired):
        return ''


def tamanho(v):
    """'3028b', '15Kb', '2Mb' -> bytes (formato do tc)."""
    m = re.match(r'(\d+)([KMG]?)b', v)
    return int(m.group(1)) * {'': 1, 'K': 1024, 'M': 1024**2, 'G': 1024**3}[m.group(2)] if m else None


RE_SENT = re.compile(r'Sent (\d+) bytes (\d+) pkt \(dropped (\d+), overlimits (\d+)')
RE_BACKLOG = re.compile(r'backlog (\S+) ')


def tc(m):
    # O iproute2 5.15 (Ubuntu 22.04) só tem JSON fiável para "qdisc"; as classes
    # e os filtros lêem-se da saída em texto.
    devs = [i for i in os.listdir('/sys/class/net') if i.endswith(('-out', '-in'))]
    for dev in devs:
        blocos = []
        for e in cmd_json(['tc', '-s', '-j', 'qdisc', 'show', 'dev', dev]) or []:
            if e.get('kind') not in ('ingress', 'noqueue'):
                blocos.append((f"qdisc:{e['kind']}", e.get('handle'), e.get('bytes'), e.get('packets'),
                               e.get('drops'), e.get('overlimits'), e.get('backlog')))
        for b in cmd_txt(['tc', '-s', 'class', 'show', 'dev', dev]).split('\n\n'):
            cab = b.split()
            sent = RE_SENT.search(b)
            if len(cab) < 3 or cab[0] != 'class' or not sent:
                continue
            bl = RE_BACKLOG.search(b)
            blocos.append((f'class:{cab[1]}', cab[2], *map(int, sent.groups()),
                           tamanho(bl.group(1)) if bl else None))
        for kind, id_, by, pk, dr, ov, bl in blocos:
            etq = dict(dev=dev, kind=kind, id=id_)
            m.add('qosi_tc_bytes_total', by, **etq)
            m.add('qosi_tc_packets_total', pk, **etq)
            m.add('qosi_tc_drops_total', dr, **etq)
            m.add('qosi_tc_overlimits_total', ov, **etq)
            m.add('qosi_tc_backlog_bytes', bl, 'gauge', **etq)
        # policiamento: "action ... police ..." seguido da linha "Sent ..."
        txt = cmd_txt(['tc', '-s', 'filter', 'show', 'dev', dev, 'ingress'])
        i = txt.find(' police ')
        sent = RE_SENT.search(txt, i) if i >= 0 else None
        if sent:
            m.add('qosi_tc_police_packets_total', int(sent.group(2)), dev=dev)
            m.add('qosi_tc_police_drops_total', int(sent.group(3)), dev=dev)


def marcador(m):
    try:
        d = json.load(open('/tmp/marcador.json'))
    except (OSError, ValueError):
        return
    for k, v in d.items():
        if k != 'proc_ns':
            m.add('qosi_marcador_pacotes_total', v, resultado=k)
    m.add('qosi_marcador_proc_seconds_total', d.get('proc_ns', 0) / 1e9)


def recolher():
    m = Metricas()
    for f in (cpu, interfaces, nft, tc, marcador):
        try:
            f(m)
        except Exception as e:          # uma sonda partida não deita abaixo as outras
            m.add('qosi_exporter_erro', 1, 'gauge', sonda=f.__name__, erro=type(e).__name__)
    return m.texto()


class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path != '/metrics':
            self.send_error(404)
            return
        corpo = recolher().encode()
        self.send_response(200)
        self.send_header('Content-Type', 'text/plain; version=0.0.4')
        self.send_header('Content-Length', str(len(corpo)))
        self.end_headers()
        self.wfile.write(corpo)

    def log_message(self, *a):
        pass


class Servidor(ThreadingHTTPServer):
    def server_bind(self):
        # O HTTPServer original chama socket.getfqdn(), que faz DNS inverso do
        # IP de gestão e fica vários segundos à espera dentro do contentor.
        socketserver.TCPServer.server_bind(self)
        self.server_name, self.server_port = self.server_address[:2]


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--ip', default='0.0.0.0')
    ap.add_argument('--porta', type=int, default=9101)
    a = ap.parse_args()
    Servidor((a.ip, a.porta), Handler).serve_forever()


if __name__ == '__main__':
    main()
