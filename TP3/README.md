# TP3 QoSI — Mecanismos de QoS com VNFs

Topologia tipo ISP em Containernet com uma cadeia de VNFs em Docker:
`vnf_fw` (controlo de acesso) → `vnf_cls` (classificação DSCP) → `vnf_tc` (policiamento e agendamento), e `vnf_mon` (monitorização) na rede de gestão.

## Requisitos

- VM Ubuntu 22.04 Server, 4 GB RAM, 2+ vCPU, 25 GB de disco
  - **PC / Mac Intel:** imagem amd64 (VirtualBox)
  - **Mac Apple Silicon (M1–M5):** imagem **arm64** ("Ubuntu Server for ARM"), em VirtualBox 7.1+ ou UTM. A imagem amd64 não arranca.
- Docker e [Containernet](https://github.com/containernet/containernet), instalados pelo `instalar_vm.sh`

## Instalação (uma vez, dentro da VM)

```bash
git clone https://github.com/icsousa/QoSI.git && cd QoSI/TP3
./instalar_vm.sh          # Containernet em ~/containernet (venv) + imagens qosi/base e qosi/mon
```

Numa VM onde a instalação já foi feita, depois de um `git pull` basta reconstruir as imagens:

```bash
sudo docker build -t qosi/base:latest docker/
sudo docker build -t qosi/mon:latest -f docker/Dockerfile.mon docker/
sudo modprobe nfnetlink_queue      # só se ainda não estiver em /etc/modules-load.d
```

## Arranque

O Containernet está num venv e o Mininet precisa de root, por isso usa-se `sudo -E env PATH=$PATH`:

```bash
source ~/containernet/venv/bin/activate
sudo -E env PATH=$PATH python3 topologia.py --check   # cria, testa ping e sai
sudo -E env PATH=$PATH python3 topologia.py           # cria e abre a CLI do Mininet
```

Se uma execução for interrompida e deixar contentores ou interfaces para trás: `sudo -E env PATH=$PATH mn -c` e `sudo docker rm -f $(sudo docker ps -aq --filter name=mn.)`.

## Cadeia de VNFs (fase 2)

Noutro terminal, com a topologia a correr. Cada VNF tem `vnfs/<vnf>/start.sh` e `stop.sh`, que correm dentro do contentor; o `cadeia.sh` orquestra-as pela ordem da cadeia.

```bash
sudo ./vnfs/cadeia.sh up                  # fw -> cls -> tc + mon (com QoS)
sudo ./vnfs/cadeia.sh down                # volta a "sem QoS" (só encaminham)
sudo ./vnfs/cadeia.sh down fw             # tudo menos a firewall (E4 "sem firewall")
sudo ./vnfs/cadeia.sh estado              # regras, classes tc, sondas e alvos do Prometheus

sudo CLS_MODO=scapy ./vnfs/cadeia.sh up cls          # classificação com Scapy + NFQUEUE
sudo TC_MODO=prio ./vnfs/cadeia.sh up tc             # PRIO estrito em vez de HTB (E5)
sudo VIDEO_RATE=6 BE_RATE=1 ./vnfs/cadeia.sh up tc   # outros pesos HTB (E5)
```

| VNF | Ficheiros | O que faz |
| --- | --- | --- |
| `vnf_fw` | `vnfs/fw/regras.nft` | Lista branca com estado (nftables, `policy drop`): IP de origem + destino + porta por fluxo, ping só dos 3 clientes legítimos, respostas por conntrack. Um contador por regra (`voip`, `video`, `dados`, `ping`, `respostas`, `bloqueado`). |
| `vnf_cls` | `vnfs/cls/regras.nft`, `regras_scapy.nft`, `marcador.py` | Marca DSCP no sentido cliente → servidor. Modo `nft`: UDP 10000–10099 < 300 B → EF, UDP 5004 → AF41, resto → BE (apaga marcas do cliente). Modo `scapy`: a gama VoIP passa pela NFQUEUE e só é EF se tiver cabeçalho RTP v2 ou perfil de voz (pacotes < 300 B com intervalo médio de 10–60 ms). |
| `vnf_tc` | `vnfs/tc/start.sh` | Policiamento: token bucket de 1 Mbit/s (rajada 10 kB) só no EF, à entrada (`tc-in`). Agendamento à saída (`tc-out`), limitado a 9,5 Mbit/s: HTB com EF 1:10 (prio 0), AF41 1:20 (5 Mbit/s garantidos, teto 9), BE 1:30 (2 garantidos, teto 9,5, fq_codel). Alternativa PRIO de 3 bandas. |
| `vnf_mon` | `vnfs/mon/` | Prometheus (recolha a cada 1 s) e Grafana com o dashboard "QoSI TP3" já provisionado. As sondas são o `vnfs/exporter.py`, que corre em cada VNF e serve `/metrics` na rede de gestão: CPU do contentor, interfaces, contadores nftables, classes e qdiscs tc, policiamento e marcador Scapy. |

Grafana em `http://<VM>:3000` (sem login) e Prometheus em `http://<VM>:9090`. A partir do Mac/PC, com a VM em NAT e SSH na porta 2222:

```bash
ssh -p 2222 -L 3000:localhost:3000 -L 9090:localhost:9090 <utilizador>@localhost
# e abrir http://localhost:3000
```

### Testes isolados de cada VNF

```bash
sudo ./vnfs/testar.sh fw          # ou cls, cls-scapy, tc, mon, todas
```

Cada teste desliga a cadeia, ativa só a VNF em teste, gera tráfego controlado e verifica o resultado (24 verificações no total). O registo fica em `resultados/testes/`.

## Cenários de tráfego

```bash
sudo ./vnfs/cadeia.sh down
sudo ./trafego/run_cenario.sh base   semqos       # E0
sudo ./trafego/run_cenario.sh misto  semqos       # E1
sudo ./vnfs/cadeia.sh up
sudo ./trafego/run_cenario.sh misto  comqos       # E2
sudo ./trafego/run_cenario.sh degradado comqos    # E3
sudo ./trafego/run_cenario.sh ataque comqos       # E4 com firewall
sudo ./trafego/campanha.sh comqos 5               # todas as misturas, 5 repetições
```

Cada execução cria `resultados/<mistura>_<etiqueta>_<data>/` com os JSON do iperf3, o log do D-ITG, `ping.txt`, os ficheiros do intruso (`intruso_cli.txt`, `intruso_srv.txt`, `intruso_scan.txt`), `meta.txt` (estado das VNFs e do núcleo antes/depois) e `resumo.csv`. A `campanha.sh` junta tudo em `resultados/todos_<etiqueta>.csv` e calcula média, desvio-padrão e IC a 95 % em `resultados/agregado_<etiqueta>.csv` (`trafego/agregar.py`).

## Endereçamento

| Segmento | Rede | Nós |
| --- | --- | --- |
| LAN clientes | 10.0.1.0/24 | vnf_fw .1, h_voip .11, h_video .12, h_bulk .13, h_intruso .66 |
| fw → cls | 10.0.10.0/30 | fw-out .1, cls-in .2 |
| cls → tc | 10.0.11.0/30 | cls-out .1, tc-in .2 |
| tc → r1 (acesso, 10 Mbit/s) | 10.0.12.0/30 | tc-out .1, r1-in .2 |
| r1 → r2 (núcleo, 100 Mbit/s, 10 ms) | 10.0.20.0/30 | r1-core .1, r2-core .2 |
| LAN servidores | 10.0.2.0/24 | r2 .1, srv_voip .11, srv_video .12, srv_bulk .13 |
| Gestão | 10.0.100.0/24 | fw .2, cls .3, tc .4, mon .10 |

## Fluxos

| Fluxo | Porta | Ferramenta | Classe |
| --- | --- | --- | --- |
| VoIP | UDP 10000 (+ TCP 9000 sinalização D-ITG) | D-ITG G.711 (ou iperf3 64 kbit/s) | EF |
| Vídeo | UDP 5004 (+ TCP 5004 controlo) | iperf3 4 Mbit/s | AF41 |
| Dados | TCP 5201 | iperf3, 4 fluxos | BE |
| Intruso | UDP 5202, TCP 20–30 | iperf (v2) 20 Mbit/s + nmap | bloqueado |

## Notas

- Sem `cadeia.sh up`, as VNFs só encaminham: é o estado "sem QoS".
- A lista branca da `vnf_fw` filtra por IP de origem **e** porta. O `h_intruso` está na mesma LAN que os clientes legítimos, por isso só a porta não chega (com a porta 5201 passaria).
- O intruso usa o `iperf` versão 2: o `iperf3` abre primeiro uma ligação TCP de controlo que a firewall bloqueia, e nunca chegaria a enviar o UDP. O `nmap -sT` distingue porta `closed` (sem firewall) de `filtered` (descartada na `vnf_fw`).
- O D-ITG com `-h RTP` conta os 12 B do cabeçalho RTP no tamanho do pacote mas não escreve um cabeçalho RTP real (o payload começa pelo cabeçalho próprio do D-ITG). Por isso o modo `scapy` da `vnf_cls` também reconhece voz pelo perfil do fluxo.
- No modo `scapy`, cada pacote demora ≈ 0,43 ms no marcador (≈ 2 300 pacotes/s no máximo): serve para inspecionar a gama VoIP, não para marcar todo o tráfego.
- O teto da classe EF no HTB (1,5 Mbit/s) fica acima do policiamento (1 Mbit/s) porque o HTB conta o cabeçalho Ethernet e o `police` não; com o mesmo valor o EF era limitado duas vezes.
- O iproute2 5.15 do Ubuntu 22.04 não tem JSON para `tc class` e gera JSON inválido para `tc filter`; o exporter lê esses dois em texto.
- `ip_forward` e `rp_filter` são passados ao Docker na criação dos contentores (`sysctls`); dentro de um contentor não privilegiado `/proc/sys` é só de leitura. O `topologia.py` verifica-os no arranque.
- `tc-out` tem um `tbf` de 10 Mbit/s a emular a ligação; a `vnf_tc` substitui-o pelo HTB a 9,5 Mbit/s.
- O cenário `degradado` aplica o netem nos dois sentidos do núcleo (`r1-core` e `r2-core`) e repõe no fim os valores que lá estavam (os do `--core-delay`/`--core-bw`).
- Offloads (TSO/GSO/GRO) desligados nas interfaces de dados, incluindo as dos hosts, para o tc medir bem.
- O `topologia.py` repõe os IPs das ligações depois do `net.start()`, que põe o IP automático do Mininet (10.0.0.x/8) na primeira interface de cada nó.
