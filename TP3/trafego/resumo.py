#!/usr/bin/env python3
"""
Resume os resultados de uma execução de run_cenario.sh num resumo.csv.

Uso: python3 trafego/resumo.py resultados/<pasta>
     python3 trafego/resumo.py resultados/*                (várias pastas -> resultados/todos.csv)
     python3 trafego/resumo.py --saida resultados/todos_comqos.csv resultados/*_comqos-r*

Débito UDP = débito que chega ao recetor (enviado x (1 - perdas)); o
bits_per_second do cliente iperf3 3.9 é a taxa enviada.
"""
import csv
import json
import re
import sys
from pathlib import Path

CAMPOS = ['execucao', 'fluxo', 'debito_mbps', 'atraso_ms', 'jitter_ms',
          'perdas_pct', 'retransmissoes', 'rtt_medio_ms', 'rtt_max_ms']


def iperf(path):
    try:
        d = json.loads(path.read_text())
    except (OSError, ValueError):
        return None
    if 'error' in d:
        return {'erro': d['error']}
    end = d.get('end', {})
    if 'sum_received' in end and 'jitter_ms' not in end.get('sum', {}):   # TCP
        return {'debito_mbps': end['sum_received']['bits_per_second'] / 1e6,
                'retransmissoes': end.get('sum_sent', {}).get('retransmits')}
    s = end.get('sum_received') or end.get('sum', {})                     # UDP
    s = {**end.get('sum', {}), **s}
    perdas = s.get('lost_percent') or 0
    return {'debito_mbps': s.get('bits_per_second', 0) / 1e6 * (1 - perdas / 100),
            'jitter_ms': s.get('jitter_ms'),
            'perdas_pct': s.get('lost_percent')}


def iperf2_srv(path):
    """Relatório do servidor iperf2 UDP (intruso). Sem linhas = nada chegou."""
    try:
        txt = path.read_text()
    except OSError:
        return None
    m = re.findall(r'([\d.]+) ([KM])bits/sec\s+[\d.]+ ms\s+\d+/\s*\d+ \(([\d.e+-]+)%\)', txt)
    if not m:
        return {'debito_mbps': 0.0, 'perdas_pct': 100.0}
    v, u, perdas = m[-1]
    return {'debito_mbps': float(v) / (1000 if u == 'K' else 1), 'perdas_pct': float(perdas)}


def itgdec(path):
    """Último bloco do ITGDec (o total). Atrasos vêm em segundos."""
    try:
        txt = path.read_text()
    except OSError:
        return None

    def last(pat):
        m = re.findall(pat, txt)
        return float(m[-1]) if m else None
    atraso, jitter = last(r'Average delay\s*=\s*([\d.]+)'), last(r'Average jitter\s*=\s*([\d.]+)')
    kbps = last(r'Average bitrate\s*=\s*([\d.]+)')
    return {'atraso_ms': atraso * 1e3 if atraso is not None else None,
            'jitter_ms': jitter * 1e3 if jitter is not None else None,
            'debito_mbps': kbps / 1e3 if kbps is not None else None,
            'perdas_pct': last(r'Packets dropped\s*=\s*\d+\s*\(([\d.]+)\s*%\)')}


def ping(path):
    try:
        txt = path.read_text()
    except OSError:
        return None
    rtt = re.search(r'= ([\d.]+)/([\d.]+)/([\d.]+)/([\d.]+) ms', txt)
    loss = re.search(r'([\d.]+)% packet loss', txt)
    return {'rtt_medio_ms': float(rtt.group(2)) if rtt else None,
            'rtt_max_ms': float(rtt.group(3)) if rtt else None,
            'perdas_pct': float(loss.group(1)) if loss else None}


def resumir(d: Path):
    linhas = []
    fontes = [('voip', itgdec, 'voip_itgdec.txt'), ('voip', iperf, 'voip.json'),
              ('video', iperf, 'video.json'), ('dados', iperf, 'bulk.json'),
              ('intruso', iperf2_srv, 'intruso_srv.txt'), ('ping', ping, 'ping.txt')]
    vistos = set()
    for fluxo, fn, nome in fontes:
        if fluxo in vistos:
            continue
        r = fn(d / nome)
        if r is None:
            continue
        vistos.add(fluxo)
        if 'erro' in r:
            print(f'  {fluxo}: erro iperf3: {r["erro"]}')
            r = {}
        linhas.append({'execucao': d.name, 'fluxo': fluxo,
                       **{k: (round(v, 3) if isinstance(v, float) else v) for k, v in r.items()}})
    return linhas


def escrever(path, linhas):
    with open(path, 'w', newline='') as f:
        w = csv.DictWriter(f, fieldnames=CAMPOS)
        w.writeheader()
        w.writerows(linhas)


def main():
    args = sys.argv[1:]
    saida = None
    if args[:1] == ['--saida'] and len(args) > 1:
        saida, args = Path(args[1]), args[2:]
    pastas = [Path(p) for p in args if Path(p).is_dir()]
    if not pastas:
        sys.exit(__doc__)
    todas = []
    for d in pastas:
        linhas = resumir(d)
        escrever(d / 'resumo.csv', linhas)
        todas += linhas
        for l in linhas:
            print('  ' + '  '.join(f'{k}={v}' for k, v in l.items() if v is not None and k != 'execucao'))
    if len(pastas) > 1 or saida:
        saida = saida or pastas[0].parent / 'todos.csv'
        escrever(saida, todas)
        print(f'>> {len(todas)} linhas em {saida}')


if __name__ == '__main__':
    main()
