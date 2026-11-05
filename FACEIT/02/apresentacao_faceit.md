# Apresentação: Tráfego do FACEIT (CS2)

**Grupo 6 · Qualidade de Serviço na Internet · cerca de 5 minutos**

---

## 1. Abertura (0:00 – 0:30)

"O nosso trabalho foi analisar o tráfego do FACEIT, a plataforma de partidas competitivas de CS2. A pergunta era simples: o que é que este serviço manda pela rede, como o identificamos no meio do resto do tráfego, e quanto conseguimos reduzir o volume de uma captura sem perder o que interessa."

## 2. Como fizemos (0:30 – 1:00)

"Jogámos uma partida inteira, cerca de 30 minutos, com o Wireshark a capturar tudo na própria máquina, sem filtros e com o anti-cheat ligado. Ficámos com uns 326 mil pacotes e cerca de 200 MB. Essa captura serviu de referência, e todos os outros cenários foram tirados dela, para compararmos sempre o mesmo tráfego."

## 3. O que encontrámos: dois planos (1:00 – 2:00)

"O tráfego do FACEIT divide-se em duas partes.

O **plano de jogo** é basicamente um único fluxo UDP entre o PC e o servidor do jogo. Sozinho, representa **79 % dos bytes** de toda a captura.

O **plano de controlo** é o site, o chat, o anti-cheat: DNS, HTTPS e QUIC para os servidores do FACEIT. Isto é muito pouco, menos de **2 % dos bytes**. É por aqui que confirmamos que é mesmo o FACEIT, porque os nomes faceit.com aparecem no DNS e no TLS.

O resto é ruído: Steam, tráfego da rede local e um fluxo UDP que já aparecia mesmo sem jogar."

## 4. QoS do fluxo de jogo (2:00 – 2:45)

"Como a cadeira é de QoS, olhámos para o fluxo de jogo desse ponto de vista. Três coisas:

- **Não tem marcação DSCP**: todos os pacotes vão como best effort, sem prioridade nenhuma.
- **É muito regular**: sai um pacote a cada **15,6 ms**, cerca de 64 por segundo em cada sentido, com pouca variação.
- O **RTT até ao servidor anda nos 56 ms**, que medimos a partir de um traceroute que o próprio cliente fez antes da partida.

Ou seja, é um fluxo de débito baixo, menos de 1 Mbit/s, mas muito sensível à latência e ao jitter."

## 5. Como filtrar (2:45 – 3:30)

"Para apanhar o jogo testámos vários filtros. Filtrar pelo IP do servidor ou pela **gama de portas 27000 a 27050** apanha 100 % do jogo e praticamente nada mais. Já filtrar só por UDP não serve: um terço do que apanha não é jogo.

O problema do IP é que muda de partida para partida. Por isso, para capturar ao vivo, o melhor é **juntar a gama de portas com os IPs de controlo do FACEIT**."

## 6. Redução de volume, a parte principal (3:30 – 4:30)

"Depois medimos quanto cada técnica poupa face à captura completa:

- **Filtrar** só o jogo poupa apenas **21 %**. Parece pouco, mas faz sentido: o jogo já era quase tudo.
- **Truncar os pacotes**, guardando só os primeiros 96 bytes, sobe para **87,5 %**. Mantém os cabeçalhos e os tempos, e perde o payload.
- **Sampling** de 1 em cada 10 pacotes, junto com a truncagem, chega a **99 %**.
- **Agregar em fluxos** com o Argus ou o tshark chega aos **99,9 %**: 200 MB passam a uns 65 kB.

Mas nenhuma técnica é grátis. O sampling estraga a medição do jitter, e os fluxos só guardam totais, perdendo a temporização dos pacotes."

## 7. Conclusão (4:30 – 5:00)

"Em resumo: o FACEIT é um fluxo UDP dominante, regular e sem QoS, mais um plano de controlo pequeno. A técnica de redução escolhe-se pelo que se quer medir: para medir jitter e tempos, filtro com truncagem; para volumes, sampling; para guardar registos durante muito tempo, fluxos.

A configuração que recomendamos é o filtro de portas com os IPs de controlo e snaplen de 96, que poupa **87 %** e mantém tudo o que precisamos para analisar a QoS. Obrigado."

---

## Se fizerem perguntas

- **"Porque é que a filtragem poupa tão pouco?"**
  Porque o jogo já representava 79 % dos bytes. O ruído são muitos pacotes, mas pequenos.
- **"Isto vale para outras partidas?"**
  Não necessariamente. Analisámos uma única partida, e o IP e a porta do servidor mudam. A gama de portas é uma suposição razoável, não uma garantia.
- **"Diferença entre Argus e tshark?"**
  O Argus agrega por 5-tuplo e apanha todos os protocolos. O tshark só faz UDP e TCP e conta cada ligação em separado, por isso dá mais conversas TCP.

---

*Lido a um ritmo normal, dá entre 4 e 5 minutos. Se o tempo apertar, a secção 5 é a mais fácil de encurtar.*
