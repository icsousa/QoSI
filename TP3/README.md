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
./instalar_vm.sh          # Containernet em ~/containernet (venv) + imagem qosi/base
```

## Arranque

O Containernet está num venv e o Mininet precisa de root, por isso usa-se `sudo -E env PATH=$PATH`:

```bash
source ~/containernet/venv/bin/activate
sudo -E env PATH=$PATH python3 topologia.py --check   # cria, testa ping e sai
sudo -E env PATH=$PATH python3 topologia.py           # cria e abre a CLI do Mininet
```

Se uma execução for interrompida e deixar contentores ou interfaces para trás: `sudo -E env PATH=$PATH mn -c` e `sudo docker rm -f $(sudo docker ps -aq --filter name=mn.)`.

Noutro terminal, com a topologia a correr:

```bash
sudo ./trafego/run_cenario.sh base   semqos       # E0
sudo ./trafego/run_cenario.sh misto  semqos       # E1
sudo ./trafego/run_cenario.sh ataque semqos       # E4 sem firewall
sudo ./trafego/campanha.sh semqos 5               # tudo, 5 repetições
```

Cada execução cria `resultados/<mistura>_<etiqueta>_<data>/` com os JSON do iperf3, o log do D-ITG, `ping.txt`, `meta.txt` (estado do tc e do nftables antes/depois) e `resumo.csv`.

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
| VoIP | UDP 10000 | D-ITG G.711 (ou iperf3 64 kbit/s) | EF |
| Vídeo | UDP 5004 (+ TCP 5004 controlo) | iperf3 4 Mbit/s | AF41 |
| Dados | TCP 5201 | iperf3, 4 fluxos | BE |
| Intruso | UDP 5202, TCP 20–30 | iperf3 20 Mbit/s + nc | bloqueado |

## Notas

- Na fase 1 as VNFs só encaminham: é o estado "sem QoS". A fase 2 acrescenta `vnfs/<nome>/start.sh` em cada contentor.
- Controlo de acesso (fase 2): a lista branca da `vnf_fw` filtra por IP de origem **e** porta. O `h_intruso` está na mesma LAN que os clientes legítimos, por isso só a porta não chega (com a porta 5201 passaria).
- `ip_forward` e `rp_filter` são passados ao Docker na criação dos contentores (`sysctls`); dentro de um contentor não privilegiado `/proc/sys` é só de leitura. O `topologia.py` verifica-os no arranque.
- `tc-out` tem um `tbf` de 10 Mbit/s a emular a ligação; a `vnf_tc` substitui-o pelo HTB a 9,5 Mbit/s.
- O cenário `degradado` altera o netem de `r1-core` e repõe-no no fim.
- Offloads (TSO/GSO/GRO) desligados nas interfaces de dados para o tc medir bem.
