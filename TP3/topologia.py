#!/usr/bin/env python3
"""
TP3 QoSI — Topologia tipo ISP em Containernet.

  LAN clientes (s1) -> vnf_fw -> vnf_cls -> vnf_tc =[10 Mbit/s]=> r1 =[núcleo]=> r2 -> LAN servidores (s2)
                         \\_________\\_________\\____ rede de gestão (s3) ____ vnf_mon

Todos os nós são contentores Docker (imagem qosi/base). O repositório é montado
em /tp3 dentro de cada contentor, para partilhar scripts e resultados.

Uso:
  sudo python3 topologia.py                 # cria a topologia e abre a CLI
  sudo python3 topologia.py --check         # cria, testa conectividade e sai
  sudo python3 topologia.py --access-bw 10 --core-delay 10ms
"""
import argparse
import os
import sys

from mininet.net import Containernet
from mininet.node import OVSSwitch
from mininet.cli import CLI
from mininet.log import setLogLevel, info, error

REPO = os.path.dirname(os.path.abspath(__file__))
IMG = 'qosi/base:latest'

# --------------------------------------------------------------------------- #
# Plano de endereçamento (igual à tabela da proposta)
# --------------------------------------------------------------------------- #
CLIENTES = {            # nome: IP na LAN 10.0.1.0/24
    'h_voip':    '10.0.1.11',
    'h_video':   '10.0.1.12',
    'h_bulk':    '10.0.1.13',
    'h_intruso': '10.0.1.66',
}
SERVIDORES = {          # nome: IP na LAN 10.0.2.0/24
    'srv_voip':  '10.0.2.11',
    'srv_video': '10.0.2.12',
    'srv_bulk':  '10.0.2.13',
}
GESTAO = {              # nome: IP na rede de gestão 10.0.100.0/24
    'vnf_fw':  '10.0.100.2',
    'vnf_cls': '10.0.100.3',
    'vnf_tc':  '10.0.100.4',
    'vnf_mon': '10.0.100.10',
}

# Interfaces de dados (as que levam tráfego de utilizador): offloads desligados
DATA_INTFS = {
    'vnf_fw':  ['fw-lan', 'fw-out'],
    'vnf_cls': ['cls-in', 'cls-out'],
    'vnf_tc':  ['tc-in', 'tc-out'],
    'r1':      ['r1-in', 'r1-core'],
    'r2':      ['r2-core', 'r2-lan'],
}


def docker(net, name, forward=False):
    """Cria um nó Docker com NET_ADMIN (tc, nftables) e o repo montado em /tp3."""
    params = dict(
        dimage=IMG,
        volumes=[f'{REPO}:/tp3:rw'],
        cap_add=['NET_ADMIN', 'NET_RAW'],
    )
    if forward:
        params['sysctls'] = {'net.ipv4.ip_forward': 1}
    return net.addDocker(name, **params)


def build(net):
    info('*** Comutadores (OVS em modo standalone, sem controlador)\n')
    s1 = net.addSwitch('s1', cls=OVSSwitch, failMode='standalone')  # LAN clientes
    s2 = net.addSwitch('s2', cls=OVSSwitch, failMode='standalone')  # LAN servidores
    s3 = net.addSwitch('s3', cls=OVSSwitch, failMode='standalone')  # gestão

    info('*** Hosts\n')
    nodes = {}
    for name, ip in CLIENTES.items():
        nodes[name] = docker(net, name)
        net.addLink(nodes[name], s1, intfName1=f'{name}-eth0'[:15],
                    params1={'ip': f'{ip}/24'})
    for name, ip in SERVIDORES.items():
        nodes[name] = docker(net, name)
        net.addLink(nodes[name], s2, intfName1=f'{name}-eth0'[:15],
                    params1={'ip': f'{ip}/24'})

    info('*** VNFs e routers\n')
    for name in ('vnf_fw', 'vnf_cls', 'vnf_tc', 'r1', 'r2'):
        nodes[name] = docker(net, name, forward=True)
    nodes['vnf_mon'] = docker(net, 'vnf_mon')
    fw, cls, tc, r1, r2 = (nodes[n] for n in ('vnf_fw', 'vnf_cls', 'vnf_tc', 'r1', 'r2'))

    info('*** Ligações do caminho de dados\n')
    net.addLink(fw, s1, intfName1='fw-lan', params1={'ip': '10.0.1.1/24'})
    net.addLink(fw, cls, intfName1='fw-out', intfName2='cls-in',
                params1={'ip': '10.0.10.1/30'}, params2={'ip': '10.0.10.2/30'})
    net.addLink(cls, tc, intfName1='cls-out', intfName2='tc-in',
                params1={'ip': '10.0.11.1/30'}, params2={'ip': '10.0.11.2/30'})
    net.addLink(tc, r1, intfName1='tc-out', intfName2='r1-in',      # acesso
                params1={'ip': '10.0.12.1/30'}, params2={'ip': '10.0.12.2/30'})
    net.addLink(r1, r2, intfName1='r1-core', intfName2='r2-core',   # núcleo
                params1={'ip': '10.0.20.1/30'}, params2={'ip': '10.0.20.2/30'})
    net.addLink(r2, s2, intfName1='r2-lan', params1={'ip': '10.0.2.1/24'})

    info('*** Rede de gestão\n')
    for name, ip in GESTAO.items():
        short = name.replace('vnf_', '')
        net.addLink(nodes[name], s3, intfName1=f'{short}-mgmt',
                    params1={'ip': f'{ip}/24'})
    return nodes


def sh(node, cmd):
    out = node.cmd(cmd)
    if 'rror' in out or 'RTNETLINK' in out:
        error(f'[{node.name}] {cmd}\n  -> {out.strip()}\n')
    return out


def configure(nodes, access_bw, core_bw, core_delay):
    info('*** Rotas\n')
    for name in CLIENTES:
        sh(nodes[name], 'ip route replace default via 10.0.1.1')
    for name in SERVIDORES:
        sh(nodes[name], 'ip route replace default via 10.0.2.1')

    sh(nodes['vnf_fw'],  'ip route replace default via 10.0.10.2')
    sh(nodes['vnf_cls'], 'ip route replace default via 10.0.11.2')
    sh(nodes['vnf_cls'], 'ip route replace 10.0.1.0/24 via 10.0.10.1')
    sh(nodes['vnf_tc'],  'ip route replace default via 10.0.12.2')
    sh(nodes['vnf_tc'],  'ip route replace 10.0.1.0/24 via 10.0.11.1')
    sh(nodes['r1'], 'ip route replace 10.0.1.0/24 via 10.0.12.1')
    sh(nodes['r1'], 'ip route replace default via 10.0.20.2')
    sh(nodes['r2'], 'ip route replace default via 10.0.20.1')

    info('*** Encaminhamento IP (redundante com sysctls, por segurança)\n')
    for name in DATA_INTFS:
        nodes[name].cmd('sysctl -qw net.ipv4.ip_forward=1')
        # rp_filter desligado: as VNFs têm várias interfaces e rotas assimétricas são possíveis
        nodes[name].cmd('sysctl -qw net.ipv4.conf.all.rp_filter=0')

    info('*** Offloads desligados (tc preciso em veth)\n')
    for name, intfs in DATA_INTFS.items():
        for intf in intfs:
            nodes[name].cmd(f'ethtool -K {intf} tso off gso off gro off 2>/dev/null')

    info(f'*** Ligação de acesso: {access_bw} Mbit/s (tbf, FIFO)\n')
    # Nos dois sentidos. A vnf_tc substitui a raiz de tc-out na fase 2.
    for node, intf in ((nodes['vnf_tc'], 'tc-out'), (nodes['r1'], 'r1-in')):
        sh(node, f'tc qdisc replace dev {intf} root tbf rate {access_bw}mbit '
                 f'burst 32kbit latency 100ms')

    info(f'*** Núcleo: {core_bw} Mbit/s, {core_delay} por sentido (netem)\n')
    # O cenário "degradado" faz "tc qdisc change" nesta mesma raiz netem.
    for node, intf in ((nodes['r1'], 'r1-core'), (nodes['r2'], 'r2-core')):
        sh(node, f'tc qdisc replace dev {intf} root netem delay {core_delay} '
                 f'rate {core_bw}mbit limit 10000')


def check(nodes):
    """Ping de cada cliente para cada servidor. Na fase 1 todos devem passar."""
    info('*** Teste de conectividade (cliente -> servidor)\n')
    falhas = 0
    for c in CLIENTES:
        for s, ip in SERVIDORES.items():
            out = nodes[c].cmd(f'ping -c 2 -W 1 {ip}')
            ok = ' 0% packet loss' in out
            falhas += not ok
            info(f'  {c:10s} -> {s:10s} {"OK" if ok else "FALHOU"}\n')
    info('*** Teste da rede de gestão (vnf_mon -> VNFs)\n')
    for name, ip in GESTAO.items():
        if name == 'vnf_mon':
            continue
        ok = ' 0% packet loss' in nodes['vnf_mon'].cmd(f'ping -c 1 -W 1 {ip}')
        falhas += not ok
        info(f'  vnf_mon    -> {name:10s} {"OK" if ok else "FALHOU"}\n')
    info(f'*** {"Tudo OK" if not falhas else f"{falhas} testes falharam"}\n')
    return falhas


def main():
    ap = argparse.ArgumentParser(description='Topologia TP3 QoSI (Containernet)')
    ap.add_argument('--access-bw', type=float, default=10, help='Mbit/s da ligação de acesso')
    ap.add_argument('--core-bw', type=float, default=100, help='Mbit/s do núcleo')
    ap.add_argument('--core-delay', default='10ms', help='atraso do núcleo por sentido')
    ap.add_argument('--check', action='store_true', help='testa conectividade e sai')
    args = ap.parse_args()

    setLogLevel('info')
    net = Containernet(controller=None)
    rc = 0
    try:
        nodes = build(net)
        net.start()
        configure(nodes, args.access_bw, args.core_bw, args.core_delay)
        if args.check:
            rc = 1 if check(nodes) else 0
        else:
            info('*** Topologia pronta. Noutro terminal: sudo ./trafego/run_cenario.sh misto\n')
            CLI(net)
    finally:
        net.stop()
    sys.exit(rc)


if __name__ == '__main__':
    main()
