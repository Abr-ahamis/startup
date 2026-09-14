FROM debian:latest

# 1. Update system and install sudo + network testing utilities (curl, iputils-ping)
RUN apt-get update && apt-get install -y \
    sudo \
    curl \
    iputils-ping \
    && rm -rf /var/lib/apt/lists/*

# 2. Create 'user1' with password 'hipassword' and grant sudo rights
RUN useradd -m -s /bin/bash user1 && \
    echo "user1:hipassword" | chpasswd && \
    usermod -aG sudo user1

# 3. Create the 'pro' folder inside the user's home directory
RUN mkdir -p /home/user1/pro

# 4. Strict Permissions: Full control for user1, zero access for anyone else (700)
RUN chown -R user1:user1 /home/user1 && \
    chmod 700 /home/user1 && \
    chmod 700 /home/user1/pro

# 5. Automatically land in user1's folder as user1
USER user1
WORKDIR /home/user1
   
