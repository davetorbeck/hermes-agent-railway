FROM ghcr.io/astral-sh/uv:0.11.6-python3.13-trixie

# "latest" resolves the newest published GitHub release at build time.
# Override with any tag/branch/SHA via a Railway service variable to pin.
ARG HERMES_REF=latest
ARG HERMES_WEBUI_REF=v0.51.310

ENV PYTHONUNBUFFERED=1 \
    PLAYWRIGHT_BROWSERS_PATH=/opt/hermes/.playwright \
    HERMES_HOME=/data \
    PATH="/opt/hermes/.venv/bin:/data/.local/bin:${PATH}" \
    PYTHONPATH="/opt/hermes-railway:/opt/hermes:/opt/hermes-webui"

RUN apt-get update && \
    apt-get install -y --no-install-recommends \
      build-essential \
      ca-certificates \
      curl \
      docker-cli \
      ffmpeg \
      gcc \
      git \
      gosu \
      libffi-dev \
      nodejs \
      npm \
      openssh-client \
      procps \
      python3 \
      python3-dev \
      ripgrep \
      tini && \
    rm -rf /var/lib/apt/lists/*

RUN useradd --system --uid 10000 --create-home --home-dir /home/hermes --shell /bin/bash hermes

WORKDIR /opt/hermes

# Bust the build cache whenever a new Hermes release is published, so a rebuild
# automatically picks up the latest. Harmless when HERMES_REF is pinned.
ADD https://api.github.com/repos/NousResearch/hermes-agent/releases/latest /tmp/hermes-agent-release.json

RUN git init . && \
    git remote add origin https://github.com/NousResearch/hermes-agent.git && \
    REF="${HERMES_REF}"; \
    if [ "$REF" = "latest" ]; then \
      REF="$(sed -n 's/.*"tag_name": *"\([^"]*\)".*/\1/p' /tmp/hermes-agent-release.json | head -n1)"; \
    fi; \
    if [ -z "$REF" ]; then REF="v2026.7.20"; echo "WARN: could not resolve latest release; falling back to ${REF}"; fi; \
    echo "==> Installing hermes-agent @ ${REF}" && \
    (git fetch --depth 1 origin "${REF}" || git fetch --depth 1 origin "refs/tags/${REF}:refs/tags/${REF}") && \
    git checkout --detach FETCH_HEAD

ENV npm_config_install_links=false

RUN npm install --prefer-offline --no-audit && \
    npx playwright install --with-deps chromium --only-shell && \
    npm cache clean --force

RUN uv venv && \
    uv pip install --no-cache-dir -e ".[all,messaging]"

RUN chmod -R a+rX /opt/hermes

# Hermes WebUI: pure Python (stdlib + pyyaml) + vanilla JS, served from /opt/hermes-webui
WORKDIR /opt/hermes-webui

RUN git init . && \
    git remote add origin https://github.com/nesquena/hermes-webui.git && \
    (git fetch --depth 1 origin "refs/tags/${HERMES_WEBUI_REF}:refs/tags/${HERMES_WEBUI_REF}" || git fetch --depth 1 origin "${HERMES_WEBUI_REF}") && \
    git checkout --detach FETCH_HEAD && \
    uv pip install --python /opt/hermes/.venv/bin/python --no-cache-dir -r requirements.txt && \
    chmod -R a+rX /opt/hermes-webui

# Wrapper extras: small Starlette app that exposes /tui (in-browser xterm with
# OAuth shortcut buttons for `hermes auth add` device-code flows plus a free-
# form `/bin/bash` pane) and reverse-proxies everything else to hermes-webui on
# loopback (HERMES_WEBUI_HOST / HERMES_WEBUI_PORT; default 127.0.0.1:9120).
# starlette/uvicorn/httpx may already be transitive Hermes
# deps, but install explicitly to pin.
RUN uv pip install --python /opt/hermes/.venv/bin/python --no-cache-dir \
    ptyprocess httpx websockets starlette uvicorn

WORKDIR /opt/hermes-railway

COPY admin ./admin
COPY skills ./skills
COPY entrypoint.sh ./entrypoint.sh

# Owned by `hermes` so `git fetch`/`hermes update` from the Web TUI do not trip
# "detected dubious ownership" (repos owned by root, commands run as hermes).
RUN chmod +x /opt/hermes-railway/entrypoint.sh && \
    mkdir -p /data && \
    chown -R hermes:hermes \
      /opt/hermes \
      /opt/hermes-webui \
      /data \
      /opt/hermes-railway && \
    git config --system --add safe.directory /opt/hermes && \
    git config --system --add safe.directory /opt/hermes-webui

EXPOSE 8080

HEALTHCHECK --interval=30s --timeout=10s --start-period=90s --retries=3 \
    CMD curl -f "http://localhost:${PORT:-8080}/health" || exit 1

ENTRYPOINT ["/usr/bin/tini", "-g", "--", "/opt/hermes-railway/entrypoint.sh"]
