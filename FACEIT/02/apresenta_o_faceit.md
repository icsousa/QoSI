---
marp: true
theme: default
class: text-center
---

# Análise e Redução do Volume de Tráfego do FACEIT (CS2)
**Unidade Curricular:** Qualidade de Serviço na Internet
**Grupo 6:** Ivo Sousa, João Afonso Sousa, João Carlos Neiva

---

## 🎯 1. Objetivos do Estudo

Analisar e otimizar a captura de tráfego gerado pela plataforma competitiva **FACEIT** (Counter-Strike 2).

**O que procurámos fazer:**
- **Capturar:** Obter tráfego real de uma partida (cerca de 30 minutos).
- **Classificar:** Identificar o que é jogo e o que é controlo/ruído.
- **Reduzir:** Testar técnicas (filtros, snaplen, sampling) para diminuir o tamanho dos ficheiros sem perder dados essenciais.
- **Agregar:** Transformar pacotes soltos em fluxos agregados.

> *Nota para o orador (1 min): Comece por introduzir o tema e o contexto prático de capturar uma sessão de 30m de CS2 com o Anti-Cheat ativo, e porque é que lidar com centenas de MBs de tráfego exige otimização.*

---

## 📊 2. O Perfil do Tráfego (A Captura Global)

**Captura Base:** ~326 mil pacotes | 206,9 MB | ~1800 segundos (30 min)

**Divisão Principal:**
- 🎮 **Plano de Jogo (79% dos bytes):** 
  - Um único fluxo UDP gigante de e para o servidor.
  - Débito constante (~133 pacotes/s).
  - Sem marcação de prioridade (QoS / DSCP 0 - *Best Effort*).
  - Extremamente regular (1 pacote a cada 15,6 ms).
- ⚙️ **Plano de Controlo (1,7% dos bytes):**
  - Tráfego DNS, TLS e QUIC para a infraestrutura do FACEIT.

> *Nota para o orador (1 min): Destaque a assimetria do tráfego. O jogo consome quase tudo, é muito regular, mas curiosamente a plataforma não usa marcações de QoS nos pacotes, sendo tratada como tráfego normal pela rede.*

---

## ✂️ 3. Reduzir o Volume: Técnicas e Resultados

Como diminuir os 206 MB iniciais?

- **Filtragem Simples:** Apanhar apenas o fluxo de jogo e controlo. 
  - *Redução de 21%* (O jogo já era 79% da captura).
- **Truncagem (Snaplen 96):** Cortar o conteúdo do pacote (payload) e guardar apenas os cabeçalhos.
  - *Redução de 87,5%* (Excelente para analisar a rede, perdendo apenas os dados do jogo em si).
- **Sampling (1 em 10):** Guardar apenas 10% dos pacotes.
  - *Redução de 92% a 98%* (Bom para estatísticas gerais, mau para analisar jitter ou atrasos).

> *Nota para o orador (1 min): Foque-se no "Snaplen 96" como a grande "estrela" da redução de pacotes, pois permite cortar quase 90% do tamanho do ficheiro e ainda permite estudar a QoS (atrasos, cabeçalhos, IPs).*

---

## 📦 4. Agregação em Fluxos

Em vez de olhar para pacotes individuais, usamos ferramentas como o **Argus** e o **tshark** para agrupar conversas.

- **Resultado:** Redução de volume superior a **99,9%**.
- O ficheiro de 206 MB passa a ter apenas **~65 a 90 KBs**.
- **Vantagens:** Mantém quem falou com quem, débitos médios e durações.
- **Desvantagens:** Perde-se a análise fina temporal (não dá para medir *jitter*).

> *Nota para o orador (1 min): Explique que a agregação é para quando só queremos o "registo telefónico" (quem ligou a quem e quanto tempo durou) em vez da gravação da chamada.*

---

## 🏆 5. Conclusões e Recomendação

**A Configuração Ideal para Capturas Futuras:**
Para monitorizar este serviço ao vivo de forma eficiente, a recomendação é usar um filtro misto com truncagem:

`Filtro (Portas UDP do Jogo + IPs de Controlo) + Snaplen 96`

- **Porquê?** Apanha tudo o que importa, corta o ruído da rede local, descarta os dados pesados do payload do jogo e ocupa apenas cerca de **26 MB** (em vez de 200 MB), permitindo análises completas de Qualidade de Serviço.

> *Nota para o orador (1 min): Termine com a recomendação prática. É a resposta direta à pergunta: "Como devo capturar isto da próxima vez?". Agradeça a atenção.*