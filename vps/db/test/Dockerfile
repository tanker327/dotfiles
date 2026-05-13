FROM ubuntu:24.04

ENV DEBIAN_FRONTEND=noninteractive \
    LANG=en_US.UTF-8 \
    LC_ALL=en_US.UTF-8

# Minimal prereqs. setup-postgres.sh installs the rest itself.
RUN apt-get update -qq && \
    apt-get install -y -qq --no-install-recommends \
        curl ca-certificates gnupg lsb-release sudo locales tzdata cron iproute2 procps && \
    locale-gen en_US.UTF-8 && \
    rm -rf /var/lib/apt/lists/*

WORKDIR /root
COPY . /root/dotfiles/

# Install the systemctl shim so the installer's service calls work in a
# non-systemd container.
RUN cp /root/dotfiles/vps/db/test/systemctl-shim.sh /usr/local/bin/systemctl && \
    chmod +x /usr/local/bin/systemctl

CMD ["bash"]
