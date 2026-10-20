# CAIDA Ark - Pesquisa e Preparação Sobre a Plataforma Atribuída

### Propósito

O objetivo principal da infraestrutura **CAIDA Ark** (Archipelago) é fazer medições ativas em escala global para mapear a topologia da Internet e monitorar o congestionamento em ligações entre domínios. Diferente de ferramentas como o Speedtest, quem usa o CAIDA Ark não são os consumidores comuns. Os usuários são pesquisadores acadêmicos, operadores de rede (ISPs), reguladores e analistas de cibersegurança que precisam entender a macrodinâmica e a integridade estrutural da Internet.   

### Métricas Chave Medidas

A plataforma assenta na execução coordenada de sondagens ativas (recorrendo a ferramentas como o scamper), recolhendo os seguintes indicadores:   

- **Caminhos de Roteamento (IP Paths/Topology)**: A sequência exata de saltos, como roteadores e Sistemas Autónomos, que um pacote atravessa desde a origem até o destino.

- **Round-Trip Time (RTT)**: O tempo de latência de ida e volta medido em milissegundos para cada salto individual ao longo da rota examinada. 

- **Perda de Pacotes (Packet Loss)**: A porcentagem de pacotes de teste, geralmente ICMP, UDP ou TCP, que são descartados ou não recebem resposta ao longo do trajeto.

### Relação com QoS e QoE

- **Mapeamento para QoS (Técnico)**: Os dados do CAIDA Ark se traduzem direto em medidas básicas de Qualidade de Serviço. O RTT mostra a latência de ponta a ponta e o jitter, pela variação do RTT ao longo do tempo. Já a topologia e a perda de pacotes ajudam a encontrar gargalos físicos ou saturação em links BGP nas bordas das redes.   

- **Mapeamento para QoE (Centrado no Utilizador)**: Embora o CAIDA Ark não meça a aplicação de forma direta, as suas métricas de QoS servem de base para a perceção do utilizador. Aumentos no RTT ou estrangulamentos encontrados em ligações entre domínios causam problemas de lag e dessincronização de hitreg em jogos competitivos, como CS2 ou Rainbow Six Siege. Também levam a tempos de carregamento de páginas web mais longos ou a buffering indesejado em serviços de streaming de vídeo.