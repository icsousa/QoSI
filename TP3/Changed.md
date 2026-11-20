# Changed — o que foi feito e o que falta

Atualizado a 20/11/2026. Tudo o que está em "Feito" foi testado na VM (Ubuntu 22.04 arm64, Containernet):
- `topologia.py --check` passa sem falhas;
- `vnfs/testar.sh todas` passa as 24 verificações (registo em `resultados/testes/`);
- os cenários `misto`, `ataque` e `degradado` correm de ponta a ponta, com e sem QoS.

Os comandos estão no `README.md`.

---

## Antes de começar: atualizar a VM

Depois do `git pull` é preciso reconstruir as imagens Docker. A `qosi/base` ganhou o `iperf` e o `nmap`, e a `qosi/mon` (Prometheus + Grafana) é nova:

```bash
cd ~/QoSI/TP3 && git pull
sudo docker build -t qosi/base:latest docker/
sudo docker build -t qosi/mon:latest -f docker/Dockerfile.mon docker/
sudo modprobe nfnetlink_queue
echo nfnetlink_queue | sudo tee /etc/modules-load.d/qosi.conf
```

Numa VM nova basta o `./instalar_vm.sh`, que já faz tudo isto.

---

## Feito

### Fase 2: as VNFs (`vnfs/`)

| VNF | Ficheiros | O que faz | Testes |
| --- | --- | --- | --- |
| `vnf_fw` | `fw/regras.nft` | Lista branca com estado (nftables, `policy drop`): IP de origem + destino + porta por fluxo, ping só dos 3 clientes legítimos e respostas por conntrack. Um contador por regra. | 9/9 |
| `vnf_cls` | `cls/regras.nft`, `cls/regras_scapy.nft`, `cls/marcador.py` | Marcação DSCP (EF / AF41 / BE). Modo `nft`: por porta e tamanho. Modo `scapy`: a gama VoIP passa pela NFQUEUE e só é EF se tiver cabeçalho RTP ou perfil de voz (pacotes < 300 B com intervalo de 10 a 60 ms). | 4/4 + 5/5 |
| `vnf_tc` | `tc/start.sh` | Token bucket de 1 Mbit/s só no EF (entrada) e HTB a 9,5 Mbit/s à saída: EF prio 0, AF41 com 5 Mbit/s garantidos, BE com 2 Mbit/s garantidos e fq_codel. Modo PRIO para a E5. Os parâmetros mudam-se por variáveis de ambiente. | 3/3 |
| `vnf_mon` | `mon/`, `exporter.py` | Prometheus (recolha a cada 1 s) e Grafana com o dashboard "QoSI TP3" já pronto. O `exporter.py` corre em cada VNF e publica CPU, interfaces, contadores nftables, classes tc, policiamento e marcador Scapy. | 3/3 |

Também foram feitos:
- **`vnfs/cadeia.sh`:** liga e desliga a cadeia (`up`, `down`, `estado`), toda ou só algumas VNFs.
- **`vnfs/testar.sh`:** testa cada VNF isoladamente com tráfego controlado, como pede o enunciado.

### Correções à fase 1

| O quê | Ficheiro |
| --- | --- |
| O `net.start()` punha IPs 10.0.0.x/8 por cima dos nossos; agora são repostos | `topologia.py` |
| O "bracketed paste" do bash sujava o output dos comandos | `docker/Dockerfile` |
| O intruso usa o `iperf` v2. O `iperf3` era bloqueado na ligação de controlo e nunca chegava a atacar | `trafego/run_cenario.sh` |
| O varrimento de portas usa o `nmap`, que distingue `closed` (sem firewall) de `filtered` (com firewall) | `trafego/run_cenario.sh` |
| O débito UDP passa a ser o recebido. Antes o vídeo dava sempre 4 Mbit/s, mesmo com perdas | `trafego/resumo.py` |
| Portas TCP 9000 (D-ITG) e 10000 (iperf3) na lista branca | `vnfs/fw/regras.nft` |
| Offloads desligados também nos hosts | `topologia.py` |
| Média, desvio-padrão e IC a 95 % | `trafego/agregar.py` (novo) |
| Cada campanha escreve o seu `todos_<etiqueta>.csv` e já não apaga as anteriores | `trafego/campanha.sh` |
| O cenário `degradado` atua nos dois sentidos e repõe os valores originais do núcleo | `trafego/run_cenario.sh` |

### Coisas descobertas que convém pôr no relatório

- **D-ITG:** com `-h RTP`, só conta os 12 B do cabeçalho RTP no tamanho do pacote e não escreve um RTP verdadeiro. Por isso o modo `scapy` também reconhece a voz pelo perfil do fluxo.
- **Custo do Scapy:** ≈ 0,43 ms por pacote, ou seja, ≈ 2 300 pacotes/s no máximo. Justifica deixar a marcação em massa no nftables (está na proposta).
- **Teto da classe EF:** no HTB é 1,5 Mbit/s, acima do policiamento (1 Mbit/s). O HTB conta o cabeçalho Ethernet e o `police` não; com o mesmo valor, o EF era limitado duas vezes.
- **Sem firewall, o VoIP e o vídeo continuam protegidos pelo HTB.** Quem perde é o BE (de 5,7 para 4,7 Mbit/s), porque o tráfego do intruso cai na classe BE.

### Primeiros resultados (20 s, uma repetição, só indicativos)

| Cenário | VoIP atraso | VoIP jitter | Vídeo perdas | Ping RTT |
| --- | --- | --- | --- | --- |
| misto, sem QoS | 97,4 ms | 5,5 ms | 0,32 % | 107 ms |
| misto, com QoS (HTB) | 10,3 ms | 0,10 ms | 0 % | 22 ms |
| misto, com QoS (PRIO) | 10,9 ms | 0,64 ms | 0 % | 22 ms |
| ataque, com QoS | 10,2 ms | 0,09 ms | 0 % | 22 ms |
| ataque, sem firewall | 10,2 ms | 0,11 ms | 0 % | 22 ms |
| degradado, com QoS | 61,7 ms | 6,8 ms | 0,93 % | 117 ms |

---

## O que falta fazer

### Já (atrasado ou obrigatório)

- [ ] **`CONTRIBUICOES.md`:** quem fez o quê. O enunciado pede-o e só nós sabemos o que cada um fez.
- [ ] **Cada membro faz commits com o próprio nome.** Também conta como registo de contribuição.

### Relatório de progresso (entrega a 03/12, 3 a 5 páginas)

O enunciado pede excertos de código, resultados iniciais de testes e capturas de ecrã da configuração.
- [ ] **Excertos de código:** `vnfs/fw/regras.nft`, `vnfs/cls/regras.nft` e o bloco HTB do `vnfs/tc/start.sh`.
- [ ] **Resultados iniciais:** o registo dos testes (`resultados/testes/`) e a tabela acima, refeita com campanhas a sério (ver abaixo).
- [ ] **Capturas de ecrã:** dashboard do Grafana com tráfego a passar, `cadeia.sh estado`, e a saída do `testar.sh todas`.

### Fase 3: integração, testes e otimização

- [ ] **Campanhas completas** (5 repetições × 60 s; cada uma demora cerca de 25 min):
  ```bash
  sudo ./vnfs/cadeia.sh down        && sudo ./trafego/campanha.sh semqos 5
  sudo ./vnfs/cadeia.sh up          && sudo ./trafego/campanha.sh comqos 5
  sudo ./vnfs/cadeia.sh down fw     && sudo ./trafego/campanha.sh semfw 5     # E4 sem firewall
  ```
- [ ] **E5 (agendadores e pesos):** `TC_MODO=prio`, e várias combinações de `VIDEO_RATE` e `BE_RATE`. Documentar as contrapartidas, por exemplo "o policiamento reduz o débito mas melhora a equidade".
- [ ] **Custo da cadeia** (prometido na proposta, ainda por medir):
  - atraso acrescentado por cada VNF (ping a cada salto, com e sem regras);
  - CPU por contentor, que já está no Grafana (`qosi_cpu_seconds_total`).
- [ ] **Comparar os modos `nft` e `scapy` da classificação** em débito e latência (prometido na proposta).
- [ ] **Na análise da E3, referir que o `netem` com jitter (50 ± 10 ms) reordena pacotes** e prejudica o TCP.

### Fase 4: entrega final (17/12)

- [ ] Gráficos (por exemplo, latência em função da carga) a partir dos `agregado_*.csv`.
- [ ] Relatório de 10 a 15 páginas: introdução, metodologia, resultados, discussão, conclusão e referências IEEE.
- [ ] Vídeo de demonstração de 5 a 10 minutos (YouTube/Vimeo, com o link no relatório).

### Opcional (bónus)

- [ ] Classificação por aprendizagem automática (árvore de decisão sobre o tamanho e o intervalo entre pacotes). O `marcador.py` já calcula estas duas características por fluxo, por isso é um bom ponto de partida.
- [ ] Encaminhamento da cadeia por regras OpenFlow no Open vSwitch, em vez de rotas estáticas.

### Notas

- A proposta tem 4 páginas e o enunciado pedia 2 a 3. Já foi entregue, fica assim.
- Os resultados de teste em `resultados/` são criados como root. Para os apagar ou processar fora dos scripts, usar `sudo`.
