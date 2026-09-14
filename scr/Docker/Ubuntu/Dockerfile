FROM ubuntu:24.04

RUN apt-get update && apt-get install -y \
    curl \
    iputils-ping \
    ca-certificates \
    && rm -rf /var/lib/apt/lists/*

RUN useradd -m -s /bin/bash user1 && \
    echo "user1:hipassword" | chpasswd

RUN mkdir -p /home/user1/pro && \
    chown -R user1:user1 /home/user1 && \
    chmod 700 /home/user1 && \
    chmod 700 /home/user1/pro

USER user1
WORKDIR /home/user1

CMD ["/bin/bash"]
