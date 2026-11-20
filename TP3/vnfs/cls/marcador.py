#!/usr/bin/env python3
"""
vnf_cls (modo scapy) — inspeção de pacotes com Scapy + NetfilterQueue.

Recebe da NFQUEUE 0 os pacotes UDP 10000-10099 e só marca EF (DSCP 46) o que
for de facto voz; o resto da gama fica BE. Um pacote é voz se tiver < 300 B e:
  - trouxer um cabeçalho RTP válido (versão 2, payload type de áudio 0-34,
    RFC 3551), ou
  - pertencer a um fluxo com perfil de voz: nos últimos 10 pacotes, intervalo
    médio entre 10 e 60 ms (codecs com tramas de 10-60 ms) e todos < 300 B.

O segundo critério existe porque o D-ITG com "-h RTP" só conta os 12 B do
cabeçalho RTP no tamanho, mas não escreve um cabeçalho RTP real no payload.
Até haver 5 pacotes de um fluxo, os pacotes sem RTP ficam BE.

Escreve contadores em /tmp/marcador.json (lidos pelo exporter).
"""
import json
import signal
import sys
import time
from collections import deque

from netfilterqueue import NetfilterQueue
from scapy.layers.inet import IP, UDP

EF = 46
LIMITE = 300
JANELA, MIN_AMOSTRAS = 10, 5
IAT_MIN, IAT_MAX = 0.010, 0.060
ESTADO = '/tmp/marcador.json'

cont = {'rtp_ef': 0, 'perfil_ef': 0, 'nao_voz': 0, 'proc_ns': 0}
fluxos = {}
ultimo = 0.0


def e_rtp(payload: bytes) -> bool:
    return len(payload) >= 12 and payload[0] >> 6 == 2 and (payload[1] & 0x7F) <= 34


def perfil_voz(chave, agora, tamanho) -> bool:
    h = fluxos.get(chave)
    if h is None:
        if len(fluxos) > 1000:          # não deixar a tabela crescer sem limite
            fluxos.clear()
        h = fluxos[chave] = deque(maxlen=JANELA)
    h.append((agora, tamanho))
    if len(h) < MIN_AMOSTRAS:
        return False
    iat = (h[-1][0] - h[0][0]) / (len(h) - 1)
    return IAT_MIN <= iat <= IAT_MAX and max(t for _, t in h) < LIMITE


def tratar(pkt):
    global ultimo
    t0 = time.perf_counter_ns()
    agora = time.monotonic()
    ip = IP(pkt.get_payload())
    chave = 'nao_voz'
    if UDP in ip:
        u = ip[UDP]
        voz_perfil = perfil_voz((ip.src, ip.dst, u.sport, u.dport), agora, len(ip))
        if len(ip) < LIMITE and e_rtp(bytes(u.payload)):
            chave = 'rtp_ef'
        elif voz_perfil and len(ip) < LIMITE:
            chave = 'perfil_ef'
    dscp = EF if chave != 'nao_voz' else 0
    ip.tos = (dscp << 2) | (ip.tos & 0x03)
    del ip.chksum                      # o Scapy recalcula o checksum IP
    pkt.set_payload(bytes(ip))
    pkt.accept()
    cont[chave] += 1
    cont['proc_ns'] += time.perf_counter_ns() - t0
    if agora - ultimo > 1:
        ultimo = agora
        with open(ESTADO, 'w') as f:
            json.dump(cont, f)


def main():
    nfq = NetfilterQueue()
    nfq.bind(0, tratar)
    signal.signal(signal.SIGTERM, lambda *_: sys.exit(0))
    print('marcador: à escuta na NFQUEUE 0', flush=True)
    try:
        nfq.run()
    finally:
        nfq.unbind()


if __name__ == '__main__':
    main()
