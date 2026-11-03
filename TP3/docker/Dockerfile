# Imagem base para todos os nós da topologia (hosts, VNFs e routers).
# Construir com:  sudo docker build -t qosi/base:latest docker/
FROM ubuntu:22.04

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y --no-install-recommends \
        iproute2 iputils-ping net-tools ethtool tcpdump procps \
        nftables iptables \
        iperf3 netcat-openbsd curl \
        python3 python3-pip python3-scapy \
    && rm -rf /var/lib/apt/lists/*

# D-ITG (VoIP com atraso num sentido). Se falhar, os scripts usam iperf3.
RUN apt-get update \
    && (apt-get install -y --no-install-recommends d-itg \
        || echo "AVISO: d-itg indisponível; VoIP será gerado com iperf3") \
    && rm -rf /var/lib/apt/lists/*

# Usado pela VNF de classificação na fase 2 (Scapy + NFQUEUE)
RUN apt-get update && apt-get install -y --no-install-recommends \
        libnetfilter-queue-dev build-essential python3-dev \
    && pip3 install --no-cache-dir NetfilterQueue \
    && apt-get purge -y build-essential python3-dev \
    && apt-get autoremove -y && rm -rf /var/lib/apt/lists/*

WORKDIR /tp3
CMD ["/bin/bash"]
