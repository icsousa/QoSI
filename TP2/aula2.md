# CAIDA Ark - Discussão e Elaboração das Respostas Escritas

### 1. Comparação de Abordagens de Medição

Esta seção mostra diferentes formas de medir resultados em projetos de software. Vamos explicar cada abordagem, apontar seus pontos fortes e fracos, e mostrar quando usá-las. A escolha da abordagem certa pode ajudar a entender melhor o desempenho e os resultados dos projetos.

As abordagens ativas, como os testes feitos sob demanda pelo Speedtest ou as sondagens do CAIDA Ark, colocam tráfego artificial na rede para medir a capacidade máxima, a latência e mapear rotas. Essas métricas são muito boas para identificar gargalos de QoS na infraestrutura. Por outro lado, abordagens passivas ou contínuas em segundo plano, como as usadas pelo SamKnows, observam o tráfego real sem sobrecarregar a rede. Elas mostram uma visão muito mais fiel da QoE, pois refletem as condições reais que os usuários enfrentam no seu uso diário.   

No caso específico do CAIDA Ark e do MANIC, a medição é feita apenas de forma ativa, por meio do envio de pacotes coordenados. Embora seja muito boa para detectar tecnicamente congestionamentos entre domínios (QoS), essa abordagem precisa ser comparada com outras fontes para entender o impacto real na experiência do usuário (QoE). Isso acontece porque o estado e a topologia do protocolo BGP, sozinhos, não mostram de forma direta o desempenho das aplicações.   

### 2. Contribuição para Melhoria da Internet

Plataformas como o CAIDA Ark, o M-Lab e o RIPE Atlas são fundamentais para a transparência na Internet. Elas oferecem dados abertos que ajudam na gestão e melhoria global da rede. Durante a elaboração deste relatório, ficou claro que a partilha pública desses conjuntos de dados permite que pesquisadores e órgãos reguladores verifiquem a neutralidade da rede e resolvam disputas de peering entre ISPs.   

A identificação regular de congestionamento recorrente em ligações de trânsito faz com que os operadores precisem negociar reforços de capacidade com base em provas. Em estudos científicos, os dados longitudinais do CAIDA são usados há muito tempo para modelar o crescimento do ecossistema IPv6 e ajudar a reduzir vulnerabilidades estruturais em todo o mundo.   

### 3. Limitações e Viés

Todo método tem seus limites. Os dados podem não mostrar toda a situação, ou podem estar incompletos. Além disso, quem analisa pode trazer opiniões pessoais. Isso pode afetar os resultados. É importante ficar atento ao viés e buscar sempre diferentes pontos de vista.

A principal limitação arquitetónica do CAIDA Ark é o viés geográfico. Como depende do alojamento voluntário de monitores, há uma presença maior na América do Norte e na Europa. Regiões de África e Ásia ficam com pouca cobertura. Isso leva a uma visão parcial da topologia global e impede uma avaliação justa da QoS em países em desenvolvimento. Além disso, as medições ativas enfrentam a limitação técnica da filtragem e priorização de pacotes ICMP feita pelos routers de core. Isso gera falsos positivos na perda de pacotes e no cálculo do jitter.   

Como vimos na análise recente do nosso grupo ao artigo Understanding Orphan Flows nesta UC, quando os pacotes de monitorização não recebem resposta ou quando a infraestrutura interceta os fluxos por um dos lados, as métricas recolhidas ficam muito distorcidas. Para resolver isso, é essencial usar modelos estatísticos de compensação. Também é importante fazer parcerias com ISPs locais em áreas pouco representadas para instalar novos monitores de captação.

### 4. Melhorias no Monitoramento

Para superar as falhas de cobertura e a natureza limitada das sondagens ativas, a plataforma CAIDA Ark se beneficiaria de uma integração federada com infraestruturas mais distribuídas, como as sondas e âncoras do RIPE Atlas. Em vez de depender só dos seus próprios monitores, o CAIDA poderia usar uma rede mais ampla para aumentar sua capacidade de triangulação e detecção de congestionamentos interdomínio (MANIC).   

A implementação de mecanismos de monitoramento detalhado baseados em eBPF diretamente nos nós de recolha, usando ambientes Linux modernos, permitiria extrair métricas de rede muito mais detalhadas ao nível do kernel com um custo computacional mínimo. Esta atualização melhoraria o mapeamento de QoS. Também reduziria a dependência de injeção de tráfego artificial e capturaria variações de atraso com mais precisão no tempo.

### 5. Tendências Futuras

O futuro do monitoramento da Internet depende da descentralização com o uso de computação de edge, ecossistemas de IoT e Inteligência Artificial. Com a mudança global para o 5G e a preparação para o 6G, a tolerância para queda na QoE cai para poucos milissegundos. Nesse cenário, o modelo de sondagens periódicas com intervalos do CAIDA Ark precisa mudar para uma análise preditiva contínua.   

O próximo passo lógico para o CAIDA seria incluir modelos de Machine Learning nos monitores da borda da rede. Esses modelos poderiam examinar as variações de RTT e prever situações de congestionamento em links que conectam diferentes domínios, antes que cheguem ao limite crítico de saturação. Essa previsão faria com que os dados fossem enviados de forma antecipada, não depois do problema. Assim, as aplicações novas que precisam de baixa latência teriam uma boa experiência garantida.