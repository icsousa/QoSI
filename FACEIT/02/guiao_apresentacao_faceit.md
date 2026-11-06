# Guião: Tráfego do FACEIT (CS2)

**Grupo 6 · Qualidade de Serviço na Internet · 6 a 7 minutos · 12 slides**

> Os tempos são acumulados. Os números a **negrito** são os que vale a pena dizer em voz alta.

---

## Slide 1 · Capa (0:00 – 0:20)

"Boa tarde. O nosso trabalho foi analisar o tráfego do FACEIT, a plataforma de partidas competitivas de CS2. Queríamos responder a três perguntas: o que é que o serviço manda pela rede, como o identificamos no meio do resto do tráfego, e quanto conseguimos reduzir o volume de uma captura sem perder o que interessa."

➡️ *"Começo pela forma como capturámos."*

## Slide 2 · Metodologia (0:20 – 0:50)

"Jogámos uma partida inteira, cerca de **30 minutos**, com o Wireshark a capturar tudo na própria máquina, por cabo, sem filtro e com o anti-cheat ligado. Ficámos com **326 mil pacotes** e cerca de **207 MB**.

A decisão importante foi fazer **uma única captura global** e tirar dela, offline, todos os outros cenários. Assim, quando comparamos reduções, estamos sempre a falar exatamente do mesmo tráfego."

➡️ *"E o que é que estava nessa captura?"*

## Slide 3 · Composição do tráfego (0:50 – 1:20)

"Um único destino domina: o servidor de jogo, com **79 % dos bytes**.

Em segundo lugar aparece um fluxo UDP para a porta 19336, que já existia na captura de ensaio fora do jogo, por isso tratámo-lo como ruído. O resto é TCP, QUIC e tráfego da rede local.

O controlo do FACEIT propriamente dito, o site, o chat e o anti-cheat, é **menos de 2 %**."

➡️ *"Vamos ver esse fluxo de jogo em detalhe."*

## Slide 4 · Plano de jogo (1:20 – 1:50)

"O jogo é **uma única conversa UDP** entre a nossa máquina e o servidor, na porta 27031. São **202 mil pacotes** e quase 160 MB em 25 minutos de partida.

O débito é baixo e praticamente constante, **menos de 1 Mbit/s**. O servidor envia um pouco mais do que recebe: 89 MB contra 71 MB."

➡️ *"Como a cadeira é de QoS, olhámos para este fluxo desse ponto de vista."*

## Slide 5 · QoS do fluxo de jogo (1:50 – 2:35)

"Três conclusões.

Primeiro, **não tem marcação DSCP**: os pacotes vão todos como best effort, sem prioridade nenhuma.

Segundo, é **extremamente regular**: um pacote a cada **15,6 ms**, cerca de 64 por segundo em cada sentido. O percentil 99 fica a menos de 2 ms da mediana. Os máximos de 1 segundo e meio segundo são interrupções isoladas.

Terceiro, o **RTT até ao servidor anda nos 56 ms**.

Ou seja, é um fluxo de débito baixo, mas muito sensível à latência e ao jitter: exatamente o tipo de tráfego que beneficiaria de prioridade."

➡️ *"Esse valor de RTT veio de algo que encontrámos na captura."*

## Slide 6 · Plano de controlo e traceroute (2:35 – 3:10)

"O controlo do FACEIT é pequeno, uns 4 mil pacotes, mas é ele que **identifica o serviço**: os nomes faceit.com aparecem no DNS e no SNI do TLS e do QUIC, todos para dois IPs.

Encontrámos ainda **80 pacotes ICMP** com o IP do servidor. Eram um **traceroute** feito pouco antes da partida, provavelmente pelo cliente do jogo. Daí tirámos o RTT por salto: menos de 1 ms no router de casa e cerca de **56 ms** até ao servidor."

➡️ *"Sabendo o que é o quê, a pergunta seguinte é como filtrar."*

## Slide 7 · Classificação e filtragem (3:10 – 3:45)

"Testámos vários filtros. Por IP ou por portas, **todos apanham 100 % do jogo**.

A **gama de portas 27000 a 27050** só traz 34 pacotes a mais, e tem uma grande vantagem: não precisa de saber o IP do servidor, que muda em cada partida.

Filtrar só por UDP não serve, porque **um terço** do que apanha não é jogo. E os nomes só se podem usar como filtro de visualização, porque o filtro de captura só vê cabeçalhos."

➡️ *"Agora a parte central: quanto conseguimos reduzir."*

## Slide 8 · Redução de volume (3:45 – 4:35)

"Filtrar só o jogo reduz apenas **21 %** dos bytes. Parece pouco, mas faz sentido: o jogo já era 79 % da captura. O ruído são muitos pacotes, mas pequenos.

A técnica com maior impacto individual é a **truncagem**. Guardando só os primeiros 96 bytes de cada pacote, que chegam para os cabeçalhos, passamos para **87,5 %**.

Juntando **sampling** de 1 em cada 10 pacotes chegamos a **99 %**, e a **agregação em fluxos** ultrapassa os **99,9 %**: 207 MB passam a cerca de 65 kB."

➡️ *"Mas reduzir tem um preço."*

## Slide 9 · Impacto nas métricas de QoS (4:35 – 5:15)

"Nenhuma redução é grátis.

Com **filtro e snaplen** guardamos todos os pacotes, os tempos e o cabeçalho IP, por isso ainda conseguimos calcular o jitter.

O **sampling** mantém os volumes, com erro abaixo de 0,6 %, mas os intervalos entre pacotes amostrados deixam de ser reais.

Os **fluxos** guardam totais exatos e a duração, mas perdem completamente a temporização.

Resumindo: para tempos e jitter, filtro com snaplen; para estatísticas de volume, sampling; para guardar registos durante muito tempo, fluxos."

➡️ *"Sobre os fluxos, comparámos duas ferramentas."*

## Slide 10 · Argus vs tshark (5:15 – 5:50)

"As duas chegam a tamanhos semelhantes, mais de **99,9 %** de redução, mas registam coisas diferentes.

O **Argus** apanha todos os protocolos e agrupa pelo 5-tuplo. O **tshark** só faz UDP e TCP e conta cada ligação em separado. Por isso o tshark tem 16 conversas TCP a mais: são ligações repetidas a um Chromecast da rede local, com o mesmo 5-tuplo.

O resultado mais impressionante: a partida inteira cabe num registo de **229 bytes**, com os totais exatos."

➡️ *"Para terminar, a nossa recomendação."*

## Slide 11 · Conclusões (5:50 – 6:30)

"O FACEIT é um **fluxo UDP dominante, regular e sem marcação de QoS**, mais um plano de controlo pequeno.

Para capturar este serviço recomendamos o **filtro de portas mais os dois IPs de controlo, com snaplen 96**. Aplicado à nossa captura, poupa **87 %** e mantém tudo o que precisamos para analisar QoS. O custo é deixar de ver o SNI, por isso o controlo passa a ser identificado pelos IPs.

As limitações: analisámos **uma só partida**, a gama de portas pode variar entre servidores, e esta configuração ainda não foi testada ao vivo."

## Slide 12 · Perguntas (6:30 – 6:40)

"Obrigado. Ficamos disponíveis para perguntas."

---

## Perguntas prováveis

**"Porque é que a filtragem poupa tão pouco?"**
Porque o jogo já representava 79 % dos bytes. O ruído são muitos pacotes, mas pequenos: o fluxo da porta 19336 é 26 % dos pacotes e só 9 % dos bytes.

**"Isto vale para outras partidas?"**
Não necessariamente. O IP e a porta do servidor mudam entre partidas, e a gama 27000–27050 é uma suposição razoável, não uma garantia. Por isso juntámos os IPs de controlo ao filtro.

**"Porque usaram snaplen 96 e não 64?"**
Os cabeçalhos Ethernet, IP e UDP ocupam 42 B. Com 96 B sobram 54 B de payload, que chegam para as queries DNS inteiras. Com 64 poupa-se mais (90,6 %), mas perde-se essa informação.

**"Como mediram o jitter?"**
Pelo desvio-padrão do tempo entre pacotes consecutivos de cada sentido, medido no próprio PC: 7,58 ms do servidor para o cliente e 4,02 ms no sentido inverso.

**"De onde vem o traceroute?"**
Não confirmámos. São 51 sondas ICMP com TTL de 1 a 17, feitas pouco antes de o jogo começar, por isso o mais provável é ser o cliente do jogo.

**"Diferença entre Argus e tshark?"**
O Argus agrega por 5-tuplo e regista todos os protocolos. O tshark agrega por ligação, só UDP e TCP, e arredonda os bytes.

---

*Se o tempo apertar: encurta o slide 6 (dizer só "o RTT veio de um traceroute") e o slide 10 (saltar a explicação do Chromecast). Poupas cerca de 40 segundos.*
