# Guia de Preparação e Roteiro de Apresentação
**Artigo:** *Understanding Orphan Flows* (TMA 2025)  
**Contexto Curricular:** Qualidade de Serviço e Segurança em Redes IP (QoSI)  
**Suporte Visual:** 9 Diapositivos (`pptfinal.pdf`)  
**Duração Recomendada:** 8 a 10 minutos (aprox. 3 minutos por orador)

---

## 1. Visão Geral e a Ideia Central do Paper

* **O Problema:** A monitorização moderna de redes depende quase cegamente de nomes de domínio (DNS) combinados com NetFlow. Se um computador acede a `google.com`, a firewall ou o monitor de rede inspeciona a query DNS e rotula o tráfego.
* **O Ponto Cego:** Há tráfego direto para IPs sem qualquer consulta DNS prévia — os chamados **Fluxos Órfãos** (*Orphan Flows*).
* **O Dilema:** Operadores de rede sentem a tentação de bloquear tráfego sem DNS ("Default Deny"). No entanto, o estudo demonstra que **mais de metade (53,5%) é tráfego legítimo** (atualizações Windows P2P, Microsoft Teams, NTP, VPNs) e que **quase 10% é malicioso ou suspeito** (malware que evita DNS de propósito). Bloquear tudo quebra a rede; ignorar tudo cria uma falha de segurança grave.

---

## 2. Proposta de Divisão do Trabalho (3 Pessoas)

A divisão tem uma narrativa lógica contínua: **Problema & Método** $\rightarrow$ **Dados & Resultados** $\rightarrow$ **QoS, Segurança & Conclusão**.

| Orador | Diapositivos | Papel / Tema Principal | Tempo Aprox. |
| :--- | :--- | :--- | :--- |
| **Pessoa 1** | **Slides 1 a 4** | **O Problema e o Pipeline Técnico:** Enquadramento, definição de fluxo órfão e como os autores trataram os dados. | ~3 min |
| **Pessoa 2** | **Slides 5 a 7** | **A Escala Real e os Resultados:** Os desafios de medição (perda de pacotes), os 26k IPs encontrados e a categorização. | ~3 min |
| **Pessoa 3** | **Slides 8 e 9** | **QoS, Dilemas Operacionais e Limitações:** Impacto em QoS, o erro do "Default Deny", limitações do estudo e conclusões. | ~3 min |

---

## 3. Roteiro Slide a Slide: O Que Dizer e Conceitos-Chave

---

### PESSOA 1: Enquadramento, Conceito e Metodologia (Slides 1 a 4)

#### Slide 1 — Título
* **O que dizer:**  
  > *"Olá a todos e ao professor. Hoje vamos apresentar o trabalho 'Understanding Orphan Flows: O ponto cego do DNS', publicado na conferência TMA 2025. O nosso foco é perceber o que acontece quando o tráfego de rede comunica diretamente por IP sem passar pela resolução de nomes e como isso impacta a monitorização, o QoS e a segurança."*
* **Dica de postura:** Fala com calma, estabelece contacto visual e passa logo ao Slide 2.

---

#### Slide 2 — O Problema: Quando o DNS deixa de explicar o tráfego
* **O que dizer:**  
  > *"Tradicionalmente, os administradores de rede utilizam o DNS para dar contexto semântico às comunicações. Quando um cliente faz um pedido web, nós vemos o nome do domínio e conseguimos categorizar esse tráfego. Contudo, existe uma zona cega: fluxos de rede outbound que comunicam diretamente com endereços IP de destino sem efetuar qualquer pedido DNS prévio. Para um operador de rede que dependa de filtros baseados em DNS, este tráfego é completamente invisível."*
* **Conceito técnico de bastidor:**  
  Por que só tráfego *outbound* (de saída)? Porque o tráfego *inbound* (alguém de fora a aceder a um servidor da universidade) nunca geraria um pedido no resolver DNS interno da rede. Apenas interessa o tráfego que sai dos clientes da organização.

---

#### Slide 3 — Definição: O que é um fluxo órfão?
* **O que dizer:**  
  > *"Definimos formalmente um 'fluxo órfão' como um fluxo de saída direcionado a um IP sem registo DNS associado nos resolvers da rede. Mas o que é que isto significa na prática? Significa que a aplicação local não perguntou 'quem é o domínio X?', simplesmente iniciou uma ligação direta 'às cegas' por IP. Não podemos assumir imediatamente que é um ataque. Um fluxo órfão pode ser um protocolo legítimo com IPs fixos (como NTP ou VoIP), ferramentas P2P como BitTorrent ou Windows Update, túneis VPN, ou, no pior cenário, malware a comunicar diretamente com servidores de comando e controlo (C2) para fugir a bloqueios de DNS."*

---

#### Slide 4 — Método: Como os autores encontraram estes fluxos
* **O que dizer:**  
  > *"Para isolar estes fluxos sem falsos positivos, os autores desenharam um pipeline rigoroso de quatro passos:*  
  > *1. **Filtrar ruído:** eliminar tráfego interno, multicast, ICMP e a própria porta UDP 53 do DNS.*  
  > *2. **Agrupar (Merge):** o NetFlow é unidirecional por omissão. Foi necessário juntar os fluxos de ida e volta através do 5-tuple.*  
  > *3. **Inferir a direção:** em redes reais com perdas, não podemos confiar em timestamps para saber quem iniciou a ligação. Os autores usaram heurísticas de portas: portas efémeras (geralmente atribuídas dinamicamente ao cliente) versus portas bem conhecidas ou registadas (servidor).*  
  > *4. **Cruzar:** por fim, cruzaram os fluxos limpos com bases de dados de DNS passivo da universidade e com o dataset global ActiveDNS para validar quem realmente não tinha nome."*
* **Transição para a Pessoa 2:**  
  > *"Passo agora a palavra ao [Nome da Pessoa 2], que vos vai mostrar os desafios brutais de recolher estes dados à escala e o que os números revelaram."*

---

### PESSOA 2: Escala, Desafios de Medição e Resultados (Slides 5 a 7)

#### Slide 5 — Escala e Incerteza: Medir redes reais é mais difícil do que parece
* **O que dizer:**  
  > *"O estudo foi realizado numa grande universidade americana com mais de 50 mil utilizadores, ao longo de 7 meses. Falamos de mais de 3,3 mil milhões de registos NetFlow por dia.  
  > Ao medir redes de produção a esta escala, deparamo-nos com problemas reais: os autores identificaram uma perda média de 62,4% de pacotes nos sensores. Mas aqui está o detalhe metodológico crucial: como o NetFlow agrega múltiplos pacotes num único registo de fluxo, se pelo menos um pacote da ligação for capturado, o fluxo é registado. Através de simulações estatísticas, os autores provaram que capturaram 97,7% de todos os fluxos reais."*
* **Atenção à pergunta do professor:**  
  Se perguntarem *"Porque é que a perda de pacotes não arruinou o artigo?"*, a resposta é esta: o NetFlow faz agregação. Com uma média de 8,4 pacotes por fluxo, a probabilidade de perder *todos* os pacotes de uma ligação é de apenas 2,3%.

---

#### Slide 6 — Resultado: 26 385 IPs órfãos (10,6 Milhões de fluxos)
* **O que dizer:**  
  > *"Após todo o pipeline de limpeza e eliminação de scanners da internet, restaram mais de 10,6 milhões de fluxos órfãos, correspondentes a 26 385 IPs únicos de destino.  
  > Como vemos no gráfico, os resultados dividem-se em quatro grupos claros:  
  > • **53,5% Explicáveis:** tráfego benigno com razão técnica para não ter DNS;  
  > • **36,7% Indeterminados:** tráfego difícil de rotular apenas por metadados de fluxo;  
  > • **7,27% Maliciosos:** confirmados em listas de bloqueio e antivírus;  
  > • **2,53% Potencialmente maliciosos:** IPs não listados, mas ativamente contactados por amostras de malware."*

---

#### Slide 7 — Leitura do Resultado: O tráfego órfão não é sinónimo de ataque
* **O que dizer:**  
  > *"Este gráfico desconstrói um mito: tráfego sem DNS não é automaticamente crime cibernético.  
  > • Na fatia **Explicável**, o maior volume veio do Windows Update Delivery Optimization (porta 7680), que usa P2P entre computadores locais e na internet para distribuir patches sem sobrecarregar a largura de banda. Encontramos também Microsoft Teams e FaceTime (STUN/TURN) e servidores NTP.  
  > • Nos **7,27% Maliciosos**, os IPs estavam presentes no agregador de blocklists BLAG e no VirusTotal. Mais de 80% já eram conhecidos, o que prova que as listas de bloqueio funcionam.  
  > • Mas o achado mais inovador são os **2,53% Potencialmente Maliciosos**: foram identificados ficheiros de malware (como trojans Cerbu, backdoors do grupo DarkHotel e botnets Mirai) a tentar comunicar diretamente com estes IPs. Como estes IPs ainda não estavam em nenhuma lista pública, a monitorização de fluxos órfãos funciona como um sistema de alerta precoce."*
* **Transição para a Pessoa 3:**  
  > *"Agora o [Nome da Pessoa 3] vai explicar o que é que isto muda na prática da gestão de tráfego, no QoS e que lições operacionais devemos retirar."*

---

### PESSOA 3: QoS, Dilemas Operacionais e Próximos Passos (Slides 8 e 9)

#### Slide 8 — Implicação Operacional: Porque isto importa para QoS e segurança
* **O que dizer:**  
  > *"Ligar este artigo à Qualidade de Serviço (QoS) e à segurança revela três grandes dilemas para qualquer engenheiro de redes:  
  > 1. **Dificuldade na Classificação e Gestão de Recursos (QoS):** Mecanismos como Traffic Shaping e DiffServ precisam de saber que tipo de tráfego estão a priorizar. Se uma atualização massiva de Windows em P2P e uma chamada crítica de videoconferência ocorrem ambas por IP direto sem nomes DNS, como é que o shaper de tráfego sabe qual deve ter garantia de latência e qual deve sofrer limitação de débito?  
  > 2. **A Falácia do 'Default Deny':** A primeira reação de uma equipa de cibersegurança seria aplicar uma regra estrita: 'se não tem DNS, bloqueia-se na firewall'. O estudo prova que isso seria desastroso — derrubaria reuniões de Teams, sincronização de relógios de servidores e atualizações essenciais do sistema operativo.  
  > 3. **Defesa em Profundidade:** As firewalls de DNS (DNS sinkholing) são excelentes, mas deixam passar 10% de ameaças que comunicam diretamente por IP. A monitorização de fluxos órfãos não substitui o DNS; adiciona uma camada de segurança vital."*

---

#### Slide 9 — Limites e Próximo Passo
* **O que dizer:**  
  > *"Para concluir, temos de ser honestos quanto ao que o estudo consegue e ao que não consegue resolver:  
  > • **O que consegue:** Demonstra que é viável criar um pipeline escalável para detetar este tráfego em milhares de milhões de registos diários, sem precisar de inspecionar o payload confidencial dos utilizadores.  
  > • **O que não resolve:** Mais de um terço (36,7%) dos IPs ficou por explicar. Em redes reais não temos acesso ao disco de cada computador cliente para saber que software abriu a conexão. Além disso, muitos destes IPs são transientes: duram apenas uma semana e desaparecem.  
  > • **A grande mensagem final:** Os fluxos órfãos não devem ser bloqueados às cegas. Devem ser monitorizados de forma híbrida — correlacionando NetFlow, DNS passivo e Threat Intelligence atualizada.*  
  > *Muito obrigado pela vossa atenção. Estamos agora disponíveis para as vossas questões."*

---

## 4. Guia Rápido de Sobrevivência: Perguntas Típicas do Professor

1. **"Porque é que o estudo excluiu o tráfego Inbound (de entrada)?"**
   * *Resposta:* Porque o tráfego que entra tem como origem clientes externos na internet acedendo a serviços da rede local. Esses clientes externos nunca consultariam os servidores DNS internos da universidade. Rotulá-los como "órfãos" seria um falso positivo conceitual.

2. **"Como é que os autores souberam se o fluxo começou dentro ou fora da rede?"**
   * *Resposta:* Pelas portas TCP/UDP. O cliente usa uma porta efémera dinâmica (portas altas, acima de 32768) e o servidor escuta numa porta bem conhecida (ex: 80, 443, 123) ou registada. Se a porta efémera pertencia ao IP interno da universidade, o fluxo foi iniciado internamente.

3. **"Qual é a relação direta com QoS?"**
   * *Resposta:* Os algoritmos de escalonamento e policiamento de tráfego (como CBQ ou WFQ) dependem de classificação prévia de pacotes. Quando a classificação por domínio/DNS falha, o operador tem de recorrer a heurísticas de portas e padrões de tráfego para não estrangular serviços de tempo real nem deixar que tráfego P2P monopolize as ligações WAN.

4. **"O que são os 2,53% 'Potencialmente Maliciosos'?"**
   * *Resposta:* São IPs que não estavam em nenhuma lista de bloqueio pública (BLAG/antivírus), mas que foram encontrados em relatórios do VirusTotal associados a ficheiros de malware que executaram e tentaram ligar-se diretamente a eles. São candidatos a novas entradas de listas de bloqueio.
```

***

### Resumo das recomendações para a apresentação:
- **Pessoa 1:** Assume a liderança no início, garante que todos entendem o que é um fluxo órfão e explica a mecânica do pipeline (Slides 1 a 4).
- **Pessoa 2:** Apresenta a parte de dados e métricas puras, mostrando domínio sobre o gráfico e as percentagens (Slides 5 a 7).
- **Pessoa 3:** Traz a discussão para a cadeira de Redes / QoS e conclui com visão crítica sobre segurança e limitações (Slides 8 e 9).

Gostarias que criasse uma nova apresentação de slides em HTML / versão revista dos slides?