# Resumo das Alterações a Aplicar no Relatório

Este documento lista todas as correções e melhorias que devem ser integradas no relatório original para cumprir os requisitos da avaliação e corrigir imprecisões técnicas.

## 1. Correções Críticas (Erros a Corrigir)

*   **Abstract - Troca de Percentagens:** 
    *   *Antes:* "...Argus e tshark (99,96 % e 99,97 %)..."
    *   *Depois:* "...tshark e o Argus (99,96 % e 99,97 %, respetivamente)..." (Corrigido para corresponder à Tabela 5, onde Argus CSV é 99,97%).
*   **Abstract e Conclusões - Percentagem do Plano de Controlo:**
    *   *Antes:* "...cerca de 1% do volume..."
    *   *Depois:* "...1,7 % do volume..." (Alinhado com a Tabela 1, que indica 1,7% dos bytes).
*   **Secção 6.1 / 6.2 - Falsa premissa sobre Snaplen 96 e SNI:**
    *   *O que alterar:* Remover a afirmação de que o *snaplen* de 96 B mantém o DNS/SNI dos pedidos de controlo.
    *   *O que escrever:* Explicar que com pacotes truncados a 96 B, subtraindo os 42 B de cabeçalhos básicos, sobram apenas 54 B. Isto significa que **perde-se a visibilidade do SNI** (o *ClientHello* do TLS fica cortado e o QUIC precisa de pacote inteiro para decifra). A identificação do controlo passa a ser feita **exclusivamente pelo IP**.

## 2. Melhoria da Análise (A discrepância dos 80 pacotes)

*   **Secção 2.1 - Explicar o Traceroute ICMP:**
    *   *Adicionar:* Explicar de onde vêm os 80 pacotes fora da conversa UDP. Mencionar que se trata de um *traceroute* ICMP (*Echo requests* com TTL crescente e *Time-to-live exceeded* a retornar) gerado pouco antes do fluxo UDP iniciar.
    *   *Filtros:* Explicar que o filtro `ip.addr==` do Wireshark apanha as mensagens de erro porque analisa IPs embebidos no *payload* ICMP, enquanto o BPF `host` só lê os cabeçalhos exteriores.
    *   *Ação:* Inserir o *screenshot* do Wireshark que comprova este *traceroute*.
*    **Texto Sugerido, melhorar A foto para esta merda é a ICMP_sec2,1.png** 
    * A primeira linha conta todos os pacotes com o IP do servidor (202 086), incluindo 80 que não pertencem à conversa UDP principal (202 006 pacotes). Estes 80 pacotes extra correspondem a um traceroute ICMP gerado pela máquina cliente (provavelmente pelo próprio jogo) instantes antes do início do fluxo UDP (a ~293,05 s). Consistem em cerca de 54 pedidos Echo (ping) request (com o payload icmp-trace-packet) e 26 respostas Time-to-live exceeded enviadas pelos routers intermédios.
    Esta descoberta explica também a discrepância de pacotes observada na Tabela 3: o filtro BPF de captura (host 141.95.32.214) apanha 202 060 pacotes porque avalia apenas os cabeçalhos exteriores, enquanto o filtro de visualização do Wireshark (ip.addr==141.95.32.214) apanha 202 086 pacotes, pois consegue inspecionar o IP original que vai embebido dentro das 26 mensagens de erro ICMP devolvidas pelos routers."
## 3. Qualidade de Serviço (QoS) e Rigor Científico

*   **Secção 2.3 - Definir Jitter:**
    *   *Ação:* Associar explicitamente a palavra **jitter** ao "desvio-padrão do tempo entre pacotes" (que já tinhas calculado como 7,58 ms e 4,02 ms).
*   **Secção 2.3 - RTT Estimado (Extra):**
    *   *Ação:* Mencionar brevemente que as respostas ICMP do primeiro salto do *traceroute* permitem estimar um RTT de cerca de 0,5 ms.
*   **Secção 5.2 - Justificar diferença TCP (Argus vs tshark):**
    *   *Antes:* A diferença "não foi investigada".
    *   *Depois:* A diferença de fluxos TCP (149 vs 165) justifica-se por "critérios distintos de delimitação das conversas por parte das ferramentas (ex: avaliação de *timeouts* ou encerramento de ligação)".
*   **Secção 6.3 - Limitações da Captura:**
    *   *Ação:* Acrescentar que a gama de portas validada (`27000-27050`) diz respeito a apenas uma partida e pode não generalizar para todos os servidores da plataforma (devido a balanceamento de carga).

## 4. Estrutura e Apresentação (Tornar o relatório "sucinto")

*   **Secções 2.4 e 2.5:**
    *   *Ação:* Fundir a subsecção de "Ruído" na subsecção do "Plano de Controlo" para poupar espaço e tornar o texto mais fluido.
*   **Figuras 1, 2 e 3:**
    *   *Ação:* Reduzir o tamanho das Figuras 2 e 3 (ou colocá-las lado a lado) e manter a Figura 1 maior e mais legível.
*   **Secção 6.1 (Síntese) e Abstract:**
    *   *Ação:* Rever a redação para garantir que não há cópias exatas ("chapas") de parágrafos entre o Abstract e a Síntese, resumindo os pontos de forma mais concisa nas conclusões.