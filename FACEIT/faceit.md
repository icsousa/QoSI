# FACEIT

## Características e Exigências do Controlo de Fluxo

Ivo Costa Sousa - pg63976
João Afonso Almeida Sousa - pg62405
João Carlos Teixeira Neiva - pg63978

---

### 1. Perfil do Tráfego (Características)
O tráfego gerado pela plataforma FACEIT divide-se em duas componentes críticas que correm em paralelo: o tráfego do jogo (Game Engine) e o tráfego do Anti-Cheat (AC).

#### Tráfego de Jogo (Maioritariamente UDP):

- **Alta Frequência e Tickrate**: Historicamente conhecido pelos servidores de 128-tick (e arquiteturas de sub-tick no CS2), o cliente e o servidor trocam atualizações de estado com uma frequência altíssima.

- **Tamanho do Pacote (Payload)**: Os pacotes são minúsculos (frequentemente entre 60 a 200 bytes). O desafio de QoS não é o consumo de largura de banda (Bandwidth), mas sim a taxa de processamento de pacotes (Packets Per Second - PPS).

- **Assimetria**: O upload (ações do jogador: movimento, disparos) é menor e mais constante, enquanto o download (estado do mundo, posições dos outros 9 jogadores) é maior e mais variável.

#### Tráfego do FACEIT Anti-Cheat (TCP/UDP):

- **Heartbeats Contínuos**: O cliente AC ao nível do kernel comunica constantemente com os servidores da plataforma.

- **Carga de Encriptação**: Os dados do AC são fortemente encriptados para evitar engenharia reversa.

- **Tolerância Zero a Bloqueios**: Se os pacotes do AC sofrerem drop ou atraso severo devido a políticas de QoS agressivas na rede, a plataforma assume que o cliente está a bloquear o AC e expulsa o jogador da partida (timeout).


### 2. Exigências de QoS (Métricas Críticas)
No contexto competitivo, o modelo de esforço intermédio (Best-Effort) da internet tradicional é insuficiente. A rede tem de garantir as seguintes métricas:

#### Latência (Ping):

- **Exigência**: Estritamente abaixo de 40-50ms. Latências superiores causam desvantagem mecânica (o famoso peeker's advantage torna-se incontrolável).

- **Foco QoS**: Requer encaminhamento otimizado (routing). O FACEIT gere redes de Points of Presence (PoPs) próprios ou usa rotas BGP otimizadas para garantir que os pacotes tomam o caminho mais curto entre o ISP do utilizador e o servidor.

#### Jitter (Variação de Atraso):

- **Exigência**: Extremamente baixo (idealmente < 5ms).

- **Impacto**: Num jogo de high tickrate, o Jitter é mais destrutivo do que uma latência alta mas estável. Picos de Jitter causam rubberbanding (o jogador é "puxado" para trás) e dessincronização entre as hitboxes visuais e as do servidor, destruindo o hit registration (registo de tiros).

#### Perda de Pacotes (Packet Loss):

- **Exigência**: 0%.

- **Impacto**: Como o tráfego de jogo usa UDP (sem retransmissão nativa para não atrasar o estado atual), um pacote perdido com a informação de um "tiro perfeito" significa que a ação nunca aconteceu no servidor. Mecanismos de QoS (como buffers intermédios) não podem simplesmente descartar pacotes do jogo quando há congestionamento.


### 3. Desafios de Rede e Infraestrutura do FACEIT

- **Proteção DDoS vs. Latência**: Sendo uma plataforma de E-sports que move prémios monetários, os servidores do FACEIT sofrem ataques DDoS constantes. O grande desafio de QoS é aplicar mitigação de ataques (scrubbing de tráfego L3/L4) sem adicionar atraso ao tráfego legítimo de UDP. Passar o tráfego por firewalls de inspeção profunda (Deep Packet Inspection) adiciona demasiados milissegundos para um jogo competitivo.

- **Gestão de Buffers (Bufferbloat)**: O tráfego não responde bem a buffers profundos em routers de borda ou nos ISPs. Se os pacotes ficarem presos numa fila de espera (queue), a informação fica desatualizada no momento em que é entregue. É preferível usar mecanismos de Active Queue Management (AQM) que sinalizem rapidamente problemas ou priorizem o tráfego interativo de baixo volume.