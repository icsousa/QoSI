# Understanding Orphan Flows

O artigo foca-se numa vulnerabilidade comum na monitorização e gestão de redes, introduzindo o conceito de "orphan flows" (fluxos órfãos). Estes são definidos como fluxos de rede de saída (outbound) que se conectam a endereços IP sem qualquer registo DNS associado.   

- **O Problema**: A grande maioria das ferramentas de monitorização e segurança de rede depende da resolução DNS para entender o tráfego. Quando um fluxo não tem DNS, cria-se um "ponto cego" na visibilidade da rede, permitindo que aplicações evasivas, redes VPN ou tráfego malicioso passem despercebidos aos operadores.   

- **Metodologia**: Os autores realizaram um estudo de larga escala numa rede universitária dos EUA durante sete meses, analisando mais de 3,3 mil milhões de fluxos diários através do protocolo NetFlow. Para mitigar desafios do mundo real, como perda e duplicação de dados, desenvolveram um pipeline rigoroso que funde fluxos unidirecionais em bidirecionais e filtra o tráfego esperado, cruzando depois os resultados com bases de dados DNS passivas e ativas para isolar os verdadeiros IPs órfãos.   

- **Descobertas Principais**: Foram identificados cerca de 26.000 IPs órfãos únicos, categorizados da seguinte forma:   
    - **53,47%** (Explicáveis): Tráfego legítimo que opera sem DNS, incluindo VPNs, comunicação Peer-to-Peer (BitTorrent), atualizações do Windows, Microsoft Teams e servidores de tempo (NTP).   
    - **7,27%** (Maliciosos): Tráfego associado a endereços IP confirmados em listas de bloqueio (blocklists) ou sinalizados por motores antivírus.   
    - **2,53%** (Potencialmente Maliciosos): IPs não listados em blocklists, mas com os quais ficheiros de malware conhecidos tentaram comunicar diretamente para evadir controlos DNS.   
    - **36,73%** (Indeterminados): IPs cujo comportamento não pôde ser categorizado devido à enorme complexidade e ruído inerente aos dados reais da rede.   

- **Persistência**: A grande maioria da infraestrutura de IP órfão (incluindo o tráfego malicioso) tem uma duração muito curta e efémera (transiente), mudando rapidamente de endereço, o que reforça a necessidade de inteligência contra ameaças em tempo real.   

## Estrutura para Apresentação e Discussão na Aula

Para dinamizar a apresentação e estimular o debate sobre QoSI (Quality of Service and Intelligence), pode estruturar a intervenção em torno dos seguintes pontos focais extraídos do artigo:

- **Impacto Direto na Aplicação de QoS**: O tráfego órfão inclui transferências maciças de dados não identificadas (como BitTorrent ou o Delivery Optimization de atualizações do Windows). Sem visibilidade sobre estes fluxos devido à ausência de domínio, os gestores de rede não conseguem aplicar políticas de Qualidade de Serviço de forma eficaz para priorizar tráfego crítico face a tráfego recreativo ou intensivo.   

- **A Ilusão da Segurança Baseada em DNS**: Muitos firewalls e sistemas de prevenção de intrusão corporativos assentam no bloqueio de domínios maliciosos. O estudo prova que várias famílias de malware ignoram o DNS e comunicam diretamente por IP (ex: botnets e trojans) precisamente para contornar essa segurança.   

- **O Dilema do "Default Deny"**: Se os fluxos órfãos escondem ameaças, porque não os bloquear a todos por defeito? O artigo destaca que o bloqueio cego é inviável porque perturbaria serviços vitais de rede que geram naturalmente tráfego sem DNS (como serviços de videochamada e sincronização de tempo). O desafio reside na distinção comportamental.   

- **Desafios Práticos de Monitorização em Larga Escala**: A análise de tráfego (TMA) enfrenta obstáculos físicos e lógicos. Discutir como os autores tiveram de lidar com perdas superiores a 60% em captura de pacotes, assimetria de routing e necessidade de adivinhar a direção cliente-servidor apenas baseando-se em portas efêmeras e conhecidas.