# Roadmap de comandos — análise do `faceit.pcapng`

Segue as fases por ordem. Cada fase indica o **objetivo do enunciado** que cobre e **o que anotar** para o relatório.
**(GUI)** = Wireshark; **(CLI)** = terminal (tshark, editcap, capinfos, tcpdump, Argus).
Todos os comandos CLI foram testados nesta captura (excepto onde indicado).

| Objetivo do enunciado | Fases |
|---|---|
| Gerar tráfego e capturar tráfego global | 1 |
| Estudar critérios de classificação/filtragem (captura e visualização) | 2, 3, 4 |
| Reduzir volume e quantificar a % (filtrar, snaplen, sampling) | 5, 7 |
| Agregação pacotes → fluxos | 6 |
| Relatório sucinto | 8, 9 |

---

## Fase 0 — Preparação

```bash
# valores desta captura (ajusta se repetires a captura)
export IN=faceit.pcapng
export CLIENT_IP=192.168.1.82
export GAME_IP=141.95.32.214      # servidor de jogo (conversa UDP dominante)
export GAME_PORT=27031
export CTRL1=193.41.200.101       # backend FACEIT (DNS/SNI)
export CTRL2=193.41.200.102
```

**Ferramentas**

- O Wireshark já inclui `tshark`, `editcap`, `capinfos`.
  - Windows: `C:\Program Files\Wireshark\` (usa PowerShell: `& "C:\Program Files\Wireshark\tshark.exe" ...`)
  - macOS: `/Applications/Wireshark.app/Contents/MacOS/`
- `tcpdump`: macOS, Linux ou WSL.
- Argus: `sudo apt install argus-server argus-client` (Linux/WSL).
- Zeek (alternativa ao Argus): `brew install zeek` ou pacotes oficiais.
- **Windows sem WSL:** troca `tcpdump -r in.pcap -w out.pcap "FILTRO_BPF"` por `tshark -r in.pcap -Y "FILTRO_DE_VISUALIZAÇÃO" -F pcap -w out.pcap`.

> Atenção: **filtro de captura (BPF)** e **filtro de visualização** têm sintaxes diferentes
> (`host 1.2.3.4` vs `ip.addr == 1.2.3.4`). O BPF só vê cabeçalhos; não vê nomes DNS/SNI.

---

## Fase 1 — Baseline: captura global (cenário A)

**(GUI)** *Statistics → Capture File Properties* (nº de pacotes, duração, bytes).

**(CLI)**

```bash
capinfos $IN                                   # visão geral
editcap -F pcap $IN A_global.pcap              # pcap simples (baseline justa)
capinfos -T -m -M -c -s -d A_global.pcap       # pacotes, tamanho do ficheiro, data size
```

**Anota:** nº de pacotes, duração, tamanho do ficheiro (pcapng e pcap), *data size*.

- Usa o **pcap** como baseline: só a conversão pcapng → pcap já poupa ~2,7 %.
- O *Data size* do `capinfos` **não muda com o snaplen** (mostra o tamanho original dos pacotes). Compara sempre o **tamanho do ficheiro**.
- Cada pacote tem 16 B de cabeçalho no pcap (mínimo de ~3,2 MB com 202 mil pacotes).

---

## Fase 2 — Caracterizar o tráfego global

**(GUI)**

1. *Statistics → Protocol Hierarchy* (print para o relatório).
2. *Statistics → Conversations*, separadores **IPv4 / TCP / UDP**, ordenado por *Packets* e por *Bytes*. A conversa UDP dominante é o servidor de jogo.
3. *Statistics → Endpoints → IPv4*.
4. *Statistics → I/O Graphs*: adiciona um gráfico com o filtro `ip.addr == 141.95.32.214` (intervalo de 1 s) e outro com `!(ip.addr == 141.95.32.214)`.

**(CLI)**

```bash
tshark -r A_global.pcap -q -z io,phs                         # hierarquia de protocolos
tshark -r A_global.pcap -q -z conv,udp | head -25            # conversas UDP
tshark -r A_global.pcap -q -z conv,tcp | head -25            # conversas TCP
tshark -r A_global.pcap -q -z endpoints,ip | head -15        # endpoints IPv4

# composição por classe (cada coluna = frames e bytes; as classes sobrepõem-se, não somar)
tshark -r A_global.pcap -q -z io,stat,0,\
"ip.addr==$GAME_IP","udp.port==19336","quic","tcp","mdns||ssdp||dns","ip.addr==$CTRL1||ip.addr==$CTRL2"

# débito do jogo por intervalos de 300 s (deve ser quase constante)
tshark -r A_global.pcap -q -z io,stat,300,"ip.addr==$GAME_IP"

# distribuição do tamanho dos pacotes do jogo
tshark -r A_global.pcap -q -z plen,tree,"ip.addr==$GAME_IP"
```

**Anota** (da conversa do jogo): início relativo, duração, pacotes e bytes em cada sentido, e daí:

- pacotes/s = pacotes / duração
- débito = bytes × 8 / duração
- tamanho médio = bytes / pacotes
- peso no global = pacotes (ou bytes) da conversa / total

**Atenção ao ruído:** `104.29.146.69:19336` (um novo fluxo por minuto) é independente do jogo e apareceu também no ensaio. Identifica o processo (Windows: Gestor de Recursos → Rede; ou `netstat -ano -p udp`).

---

## Fase 3 — Evidência de que o serviço é o FACEIT

**(GUI)** escreve na barra de filtros e tira print:

```
dns.qry.name contains "faceit"
tls.handshake.extensions_server_name contains "faceit"
```

(O SNI também aparece nos QUIC Initial, porque o Wireshark os decifra.)

**(CLI)**

```bash
# respostas DNS: quando e para que IPs
tshark -r A_global.pcap -Y 'dns.flags.response==1 && dns.qry.name contains "faceit"' \
  -T fields -e frame.time_relative -e dns.qry.name -e dns.a

# SNI (TLS e QUIC)
tshark -r A_global.pcap -Y 'tls.handshake.extensions_server_name contains "faceit"' \
  -T fields -e frame.time_relative -e ip.dst -e tls.handshake.extensions_server_name

# dono do IP do servidor de jogo
whois $GAME_IP
```

**Anota:** nomes (`www`, `edge`, `chat`, `ac-client-ws`, `faceit-cdn.net`…), IPs (`193.41.200.101/102`), instantes, e o dono do `$GAME_IP`.

---

## Fase 4 — Critérios de classificação e filtros

| Critério | Filtro de captura (BPF) | Filtro de visualização |
|---|---|---|
| Protocolo | `udp` | `udp` |
| Servidor de jogo (IP) | `udp and host $GAME_IP` | `ip.addr == $GAME_IP && udp` |
| Gama de portas | `udp portrange 27000-27050` | `udp.port >= 27000 && udp.port <= 27050` |
| Controlo FACEIT (IP) | `host $CTRL1 or host $CTRL2` | `ip.addr == $CTRL1 \|\| ip.addr == $CTRL2` |
| Controlo FACEIT (nome) | *(BPF não vê nomes)* | `dns.qry.name contains "faceit"` / `tls.handshake.extensions_server_name contains "faceit"` |
| Jogo + controlo | `host $GAME_IP or host $CTRL1 or host $CTRL2` | `ip.addr == $GAME_IP \|\| ip.addr == $CTRL1 \|\| ip.addr == $CTRL2` |
| Dominância/volume | — | *Conversations* ordenado por bytes |

**Medir a eficácia de cada filtro** (compara com a conversa do jogo):

```bash
# quantos pacotes apanha o filtro por gama de portas e quantos são do servidor?
tcpdump -r A_global.pcap "udp portrange 27000-27050" -nn 2>/dev/null | wc -l          # apanhados
tcpdump -r A_global.pcap "udp portrange 27000-27050 and host $GAME_IP" -nn 2>/dev/null | wc -l   # do servidor
```

- **Cobertura** = pacotes do jogo apanhados / pacotes do jogo.
- **Precisão** = pacotes do jogo apanhados / pacotes apanhados.
- Resultado de referência: a gama `27000-27050` apanha 202 040 pacotes, dos quais 202 006 são do servidor (cobertura 100 %, precisão 99,98 %).
- O IP muda de partida para partida; a gama de portas e o critério de volume generalizam melhor.

---

## Fase 5 — Redução de volume (cenários B, C, D)

Tudo derivado do **mesmo** `A_global.pcap`, para a comparação ser exata.

**B — Filtrar**

```bash
tcpdump -r A_global.pcap -w B1_udp_host.pcap  "udp and host $GAME_IP"
tcpdump -r A_global.pcap -w B2_host.pcap      "host $GAME_IP"
tcpdump -r A_global.pcap -w B3_portrange.pcap "udp portrange 27000-27050"
tcpdump -r A_global.pcap -w B4_udp.pcap       "udp"
tcpdump -r A_global.pcap -w B5_game_ctrl.pcap "host $GAME_IP or host $CTRL1 or host $CTRL2"
```

**C — Não capturar o pacote inteiro (snaplen)**

```bash
for s in 128 96 64; do editcap -s $s B1_udp_host.pcap C_snaplen$s.pcap; done
editcap -s 96 B5_game_ctrl.pcap C_game_ctrl_snaplen96.pcap
```

Cabeçalhos Eth + IPv4 + UDP = 42 B, por isso `-s 96` guarda os cabeçalhos e mais 54 B de payload. O Wireshark mostra avisos de pacote truncado (esperado).

**D — Sampling 1 em 10** (por ordem de pacote)

```bash
tshark -r B1_udp_host.pcap -Y "frame.number % 10 == 0" -F pcap -w D1_sampling.pcap
tshark -r C_snaplen96.pcap -Y "frame.number % 10 == 0" -F pcap -w D2_snaplen_sampling.pcap
```

Erro de estimativa do sampling: extrapola × 10 e compara com o original.

```bash
capinfos -T -m -M -c -s -d B1_udp_host.pcap D1_sampling.pcap
```

**Medir tudo** (pacotes e tamanho do ficheiro de cada cenário):

```bash
capinfos -T -m -M -c -s *.pcap | grep -v '^File name'
```

---

## Fase 6 — Agregação pacotes → fluxos

**Argus** (usado no relatório)

```bash
argus -r A_global.pcap    -w E1_global.argus          # registos de estado (5 s)
argus -r B1_udp_host.pcap -w E3_B1.argus
racluster -r E1_global.argus -m proto saddr sport daddr dport -w E2_global_cluster.argus   # 1 registo por fluxo
racluster -r E3_B1.argus     -m proto saddr sport daddr dport -w E3_B1_cluster.argus
ra -r E2_global_cluster.argus -n -c , -s stime dur proto saddr sport daddr dport spkts dpkts sbytes dbytes > E2_global_flows.csv
ra -r E3_B1_cluster.argus     -n -c , -s stime dur proto saddr sport daddr dport spkts dpkts sbytes dbytes > E3_B1_flows.csv
ls -l E*.argus E*.csv
wc -l E2_global_flows.csv        # nº de fluxos = linhas - 1 (cabeçalho) - 1 (registo de gestão "man" do Argus)
```

- O Argus emite registos de estado de ~5 s; por isso `E1` é maior do que `E2` (um registo por fluxo).
- Confirma que os totais do fluxo de jogo batem com o pcap (soma de `sbytes` e `dbytes`).

**Zeek** (alternativa; não testado nesta captura)

```bash
zeek -C -r B1_udp_host.pcap          # gera conn.log (um registo por conexão)
ls -l conn.log
```

**Só com o Wireshark/tshark** (se não puderes instalar nada)

```bash
tshark -r B1_udp_host.pcap -q -z conv,udp > flows_B1.txt
tshark -r A_global.pcap    -q -z conv,udp > flows_global.txt
ls -l flows_*.txt
```

**Anota:** nº de fluxos (global vs filtrado), tamanho dos ficheiros de fluxos e % de redução face ao `A_global.pcap`.

---

## Fase 7 — Tabela final e percentagens

```
% otimização = (1 - tamanho_reduzido / tamanho_global) × 100        (em bytes e em pacotes)
```

O script do Anexo A faz as Fases 1 e 5-7 de uma vez e escreve `resultados/resultados.csv`:

```bash
./pipeline.sh faceit.pcapng
```

**Valores de referência** (para confirmares que o teu resultado coincide):

| Cenário | Pacotes | Ficheiro (B) | Redução bytes |
|---|---|---|---|
| A. Global | 326 122 | 206 864 624 | 0 % |
| B1. `udp and host` servidor | 202 006 | 162 905 309 | 21,25 % |
| B3. `udp portrange 27000-27050` | 202 040 | 162 951 481 | 21,23 % |
| B4. só `udp` | 300 571 | 193 613 964 | 6,41 % |
| B5. jogo + controlo | 206 055 | 166 312 206 | 19,60 % |
| C. B1 + snaplen 128 / 96 / 64 | 202 006 | 32 311 732 / 25 856 584 / 19 392 644 | 84,38 / 87,50 / 90,63 % |
| D1. B1 + sampling 1/10 | 20 200 | 16 376 628 | 92,08 % |
| D2. B1 + snaplen 96 + sampling 1/10 | 20 200 | 2 262 424 | 98,91 % |
| E1. Argus (registos 5 s) | – | 1 004 872 | 99,51 % |
| E2. Argus (1 reg./fluxo, CSV) | – | 64 839 | 99,97 % |

---

## Fase 8 — Validação ao vivo (opcional)

Para confirmar que o filtro e o snaplen funcionam **durante** a captura (e não só offline):

```bash
dumpcap -D                                         # lista as interfaces
dumpcap -i <n> -f "udp portrange 27000-27050 or host 193.41.200.101 or host 193.41.200.102" \
        -s 96 -w live.pcapng                       # filtro + snaplen na captura
dumpcap -i <n> -b filesize:102400 -w ring.pcapng   # ring buffer: ficheiros de 100 MB
```

Em captura ao vivo ainda não sabes o IP do servidor, por isso usa a **gama de portas** (ou `udp`) e refina depois.

---

## Fase 9 — Material para o relatório

**Prints a guardar** (com estes nomes, ao lado do `.tex`):

- `fig_sni.png` — filtro `tls.handshake.extensions_server_name contains "faceit"`
- `fig_dns.png` — filtro `dns.qry.name contains "faceit"`
- `fig_udp.png` — *Conversations → UDP* ordenado por *Packets*
- (opcional) *Protocol Hierarchy* e *I/O Graph* da conversa do jogo

**Checklist de números:**

- [ ] Baseline: pacotes, duração, bytes
- [ ] Servidor: IP:porta, início, duração, pacotes/bytes por sentido, % do global
- [ ] Controlo FACEIT: nomes, IPs, pacotes, bytes
- [ ] Ruído: classes e pesos (QUIC, TCP, `:19336`, mDNS/SSDP/DNS)
- [ ] Filtros: pacotes apanhados, cobertura e precisão
- [ ] Snaplen 128/96/64 e sampling 1/10 (incl. erro de estimativa)
- [ ] Fluxos: nº de fluxos e tamanho dos ficheiros
- [ ] Tabela final com % de otimização (bytes e pacotes)

---

## Anexo A — `pipeline.sh` (testado)

Grava como `pipeline.sh`, dá permissões (`chmod +x pipeline.sh`) e corre `./pipeline.sh faceit.pcapng`.

```bash
#!/usr/bin/env bash
# pipeline.sh - gera todos os cenarios de reducao a partir da captura global
# Uso:  ./pipeline.sh faceit.pcapng
# Requer: editcap, capinfos, tshark (Wireshark) e tcpdump. Opcional: argus/ra/racluster, zeek.
set -euo pipefail

IN="$(realpath "${1:-faceit.pcapng}")"
GAME_IP="${GAME_IP:-141.95.32.214}"     # servidor de jogo (conversa UDP dominante)
GAME_PORT="${GAME_PORT:-27031}"
CTRL1="${CTRL1:-193.41.200.101}"        # backend FACEIT (DNS/SNI)
CTRL2="${CTRL2:-193.41.200.102}"
SNAP="${SNAP:-96}"                      # snaplen principal
N="${N:-10}"                            # sampling 1 em N
OUT="${OUT:-resultados}"

mkdir -p "$OUT"; cd "$OUT"

echo ">> A: baseline (pcap simples, para comparar tamanhos de forma justa)"
editcap -F pcap "$IN" A_global.pcap

echo ">> B: filtros"
tcpdump -r A_global.pcap -w B1_udp_host.pcap    "udp and host $GAME_IP"                 2>/dev/null
tcpdump -r A_global.pcap -w B2_host.pcap        "host $GAME_IP"                         2>/dev/null
tcpdump -r A_global.pcap -w B3_portrange.pcap   "udp portrange 27000-27050"             2>/dev/null
tcpdump -r A_global.pcap -w B4_udp.pcap         "udp"                                   2>/dev/null
tcpdump -r A_global.pcap -w B5_game_ctrl.pcap   "host $GAME_IP or host $CTRL1 or host $CTRL2" 2>/dev/null

echo ">> C: snaplen (nao capturar o pacote inteiro)"
for s in 128 96 64; do editcap -s "$s" B1_udp_host.pcap "C_snaplen${s}.pcap"; done
editcap -s "$SNAP" B5_game_ctrl.pcap C_game_ctrl_snaplen${SNAP}.pcap

echo ">> D: sampling 1/$N (por ordem de pacote)"
tshark -r B1_udp_host.pcap -Y "frame.number % $N == 0" -F pcap -w D1_sampling.pcap 2>/dev/null
tshark -r "C_snaplen${SNAP}.pcap" -Y "frame.number % $N == 0" -F pcap -w D2_snaplen_sampling.pcap 2>/dev/null

if command -v argus >/dev/null 2>&1; then
  echo ">> E: agregacao em fluxos (Argus)"
  argus -r A_global.pcap     -w E1_global.argus
  argus -r B1_udp_host.pcap  -w E3_B1.argus
  racluster -r E1_global.argus -m proto saddr sport daddr dport -w E2_global_cluster.argus
  racluster -r E3_B1.argus     -m proto saddr sport daddr dport -w E3_B1_cluster.argus
  ra -r E2_global_cluster.argus -n -c , -s stime dur proto saddr sport daddr dport spkts dpkts sbytes dbytes > E2_global_flows.csv
  ra -r E3_B1_cluster.argus     -n -c , -s stime dur proto saddr sport daddr dport spkts dpkts sbytes dbytes > E3_B1_flows.csv
else
  echo ">> E: Argus nao encontrado - usa Zeek (zeek -C -r B1_udp_host.pcap) ou tshark -q -z conv,udp"
fi

echo ">> Tabela de resultados (reducao face a A_global.pcap)"
python3 - <<'EOF'
import os, subprocess, csv
def pkts(f):
    out = subprocess.run(["capinfos","-T","-m","-M","-c",f],capture_output=True,text=True).stdout
    return int([l for l in out.splitlines() if not l.startswith("File name")][0].split(",")[1])
files = ["A_global.pcap","B1_udp_host.pcap","B2_host.pcap","B3_portrange.pcap","B4_udp.pcap",
         "B5_game_ctrl.pcap","C_snaplen128.pcap","C_snaplen96.pcap","C_snaplen64.pcap",
         "C_game_ctrl_snaplen96.pcap","D1_sampling.pcap","D2_snaplen_sampling.pcap",
         "E1_global.argus","E2_global_cluster.argus","E2_global_flows.csv","E3_B1.argus","E3_B1_flows.csv"]
files = [f for f in files if os.path.exists(f)]
base_b = os.path.getsize("A_global.pcap"); base_p = pkts("A_global.pcap")
rows=[]
for f in files:
    b = os.path.getsize(f)
    if f.endswith(".pcap"):
        p = pkts(f); rp = f"{(1-p/base_p)*100:.2f}"
    else:
        p = ""; rp = ""
    rows.append([f,p,b,f"{(1-b/base_b)*100:.2f}",rp])
w = csv.writer(open("resultados.csv","w",newline=""))
w.writerow(["ficheiro","pacotes","bytes_ficheiro","reducao_bytes_%","reducao_pacotes_%"]); w.writerows(rows)
print(f"{'ficheiro':32s}{'pacotes':>9s}{'bytes':>13s}{'%bytes':>9s}{'%pkts':>8s}")
for r in rows: print(f"{r[0]:32s}{str(r[1]):>9s}{r[2]:>13d}{r[3]:>9s}{r[4]:>8s}")
EOF
echo ">> Escrito: $OUT/resultados.csv"
```
