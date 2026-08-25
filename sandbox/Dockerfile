FROM ubuntu:24.04

ENV DEBIAN_FRONTEND=noninteractive \
    LANG=C.UTF-8 \
    LC_ALL=C.UTF-8

RUN apt-get update \
  && apt-get install -y --no-install-recommends \
    sudo \
    ca-certificates \
    curl \
    git \
    locales \
    python3 \
  && rm -rf /var/lib/apt/lists/* \
  && useradd -m -s /bin/bash -G sudo waku \
  && echo 'waku ALL=(ALL) NOPASSWD:ALL' >/etc/sudoers.d/waku \
  && chmod 0440 /etc/sudoers.d/waku

COPY --chown=waku:waku . /home/waku/dotfiles

USER waku
WORKDIR /home/waku/dotfiles
ENV HOME=/home/waku \
    USER=waku \
    PATH="/home/waku/.local/bin:${PATH}"

CMD ["./sandbox/verify.sh"]
