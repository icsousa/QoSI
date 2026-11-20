#!/usr/bin/env python3
"""
Agrega as repetições de uma campanha: média, desvio-padrão e intervalo de
confiança a 95 % (t de Student) por mistura, etiqueta e fluxo.

Uso: python3 trafego/agregar.py resultados/todos_comqos.csv [mais.csv ...]
     -> escreve resultados/agregado.csv (ou --saida <ficheiro>)

As pastas chamam-se <mistura>_<etiqueta>-r<N>_<data>; o "-r<N>" é removido
para juntar as repetições.
"""
import csv
import math
import re
import statistics
import sys
from collections import defaultdict
from pathlib import Path

METRICAS = ['debito_mbps', 'atraso_ms', 'jitter_ms', 'perdas_pct',
            'retransmissoes', 'rtt_medio_ms', 'rtt_max_ms']
# t de Student bilateral a 95 % para n-1 graus de liberdade (1..30)
T95 = [12.706, 4.303, 3.182, 2.776, 2.571, 2.447, 2.365, 2.306, 2.262, 2.228,
       2.201, 2.179, 2.160, 2.145, 2.131, 2.120, 2.110, 2.101, 2.093, 2.086,
       2.080, 2.074, 2.069, 2.064, 2.060, 2.056, 2.052, 2.048, 2.045, 2.042]


def chave(execucao):
    m = re.match(r'([^_]+)_(.+)_\d{8}-\d{6}$', execucao)
    if not m:
        return execucao, ''
    return m.group(1), re.sub(r'-r\d+$', '', m.group(2))


def main():
    args = sys.argv[1:]
    saida = None
    if args[:1] == ['--saida'] and len(args) > 1:
        saida, args = Path(args[1]), args[2:]
    if not args:
        sys.exit(__doc__)
    grupos = defaultdict(lambda: defaultdict(list))
    for f in args:
        for l in csv.DictReader(open(f)):
            mix, tag = chave(l['execucao'])
            for k in METRICAS:
                if l.get(k) not in (None, ''):
                    grupos[(mix, tag, l['fluxo'])][k].append(float(l[k]))

    linhas = []
    for (mix, tag, fluxo), mets in sorted(grupos.items()):
        for k, v in mets.items():
            n = len(v)
            media = statistics.fmean(v)
            dp = statistics.stdev(v) if n > 1 else 0.0
            ic = T95[min(n - 1, 30) - 1] * dp / math.sqrt(n) if n > 1 else 0.0
            linhas.append({'mistura': mix, 'etiqueta': tag, 'fluxo': fluxo, 'metrica': k,
                           'n': n, 'media': round(media, 4), 'desvio': round(dp, 4),
                           'ic95': round(ic, 4)})

    saida = saida or Path(args[0]).parent / 'agregado.csv'
    with open(saida, 'w', newline='') as f:
        w = csv.DictWriter(f, fieldnames=list(linhas[0]) if linhas else ['mistura'])
        w.writeheader()
        w.writerows(linhas)
    for l in linhas:
        print(f"  {l['mistura']:9s} {l['etiqueta']:10s} {l['fluxo']:8s} {l['metrica']:15s} "
              f"{l['media']:>10} ± {l['ic95']:<8} (n={l['n']})")
    print(f'>> {len(linhas)} linhas em {saida}')


if __name__ == '__main__':
    main()
