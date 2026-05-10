# syntax=docker/dockerfile:1.7
#
# code-server with Dance modal editing baked into the VS Code build.
#
# Stage 1 builds VS Code (with the dance overlay + workbench contribution)
# and code-server itself.  Stage 2 is the slim runtime image.
#
# Build:
#   docker build -t vscodium-dance-server:dev -f dance/Dockerfile .
# Run:
#   docker run --rm -p 8080:8080 -v "$HOME/.config/code-server:/home/coder/.config" \
#              -v "$PWD:/home/coder/project" vscodium-dance-server:dev

# =================================================================================================
# Stage 1: build
# =================================================================================================
FROM debian:bookworm AS builder

ENV DEBIAN_FRONTEND=noninteractive
ENV NODE_OPTIONS=--max-old-space-size=8192
ENV CI=1
# Skip electron / playwright downloads inside the vscode build (REH only).
ENV ELECTRON_SKIP_BINARY_DOWNLOAD=1
ENV PLAYWRIGHT_SKIP_BROWSER_DOWNLOAD=1

# Build tooling.  We pull node 22 from NodeSource because Debian's package
# is older than what code-server expects (.node-version pins a 22.x line).
RUN apt-get update && apt-get install -y --no-install-recommends \
      ca-certificates curl git build-essential pkg-config python3 \
      libkrb5-dev libsecret-1-dev libxkbfile-dev libx11-dev libnss3 quilt \
      jq rsync gnupg \
  && curl -fsSL https://deb.nodesource.com/setup_22.x | bash - \
  && apt-get install -y --no-install-recommends nodejs \
  && rm -rf /var/lib/apt/lists/*

ARG FORK_URL=https://github.com/WjcmeAFJb/code-server.git
ARG FORK_REF=dance-embed
# Pass --build-arg CACHE_BUST=$(git rev-parse HEAD) to force a fresh clone
# (otherwise docker happily reuses the cached layer even when the remote
# branch advanced).  The default literal value here means "use cache when
# possible"; serve.sh sets it to the head sha automatically.
ARG CACHE_BUST=stable
WORKDIR /src

# Clone the fork (rather than COPYing the local context) so the build
# survives the project's `.dockerignore` of **, and so re-running the
# Dockerfile against a remote machine works without sharing the workspace.
RUN echo "cache-bust: $CACHE_BUST" \
  && git clone --depth 1 --branch "$FORK_REF" "$FORK_URL" .

# Initialise the vscode submodule from the URL recorded in .gitmodules.
# --depth keeps the clone small.
RUN git submodule update --init --depth 1 lib/vscode

# Apply code-server's own quilt patches.  per docs/CONTRIBUTING.md these
# are applied from the repo root (the patch headers carry the
# `code-server/lib/vscode/...` prefix and quilt's default strip resolves
# them against $PWD).
RUN quilt push -a

# Apply the Dance overlay + register the workbench contribution.
RUN ./dance/install-into-vscode.sh

# Install lib/vscode/build deps first so the v8 header patcher can run.
# Without this, native modules (native-keymap, etc.) try to compile against
# unpatched Electron headers and fail with "EmbedderStateTag does not name a type".
# Mirrors what code-server's own .github/workflows/release.yaml does.
SHELL ["/bin/bash", "-eo", "pipefail", "-c"]
RUN cd lib/vscode/build && npm ci \
  && cd .. \
  && if [[ -f build/azure-pipelines/linux/setup-env.sh ]]; then . build/azure-pipelines/linux/setup-env.sh ; fi \
  && node build/npm/preinstall.ts

# Now install root + lib/vscode + test deps.  SKIP_SUBMODULE_DEPS is NOT set
# so the postinstall hook also handles lib/vscode.
RUN npm ci

# vsce's manifest validator hardcodes the allowed extensionKinds to
# {'ui','workspace'} even though vscode-web does support 'web'. We need 'web'
# so vscode-web's BrowserExtensionHostKindPicker routes dance to the
# LocalWebWorkerExtensionHost (postMessage IPC) instead of the slow
# RemoteExtensionHost (websocket RPC). Patch both copies of vsce.
RUN set -eux; \
    for f in $(find lib/vscode -path '*/node_modules/@vscode/vsce/out/package.js' 2>/dev/null); do \
      if grep -q "new Set(\\['ui', 'workspace'\\])" "$f"; then \
        echo "[dance] patching vsce extensionKind allow-list in $f"; \
        sed -i "s/new Set(\\['ui', 'workspace'\\])/new Set(['ui', 'workspace', 'web'])/g" "$f"; \
      fi; \
    done

# Build VS Code (REH-web flavour, the one code-server consumes).
RUN VERSION=0.0.0-dance npm run build:vscode

# Build code-server itself.
RUN VERSION=0.0.0-dance npm run build

# Pre-package release files so we can copy them into the runtime image.
RUN VERSION=0.0.0-dance KEEP_MODULES=1 npm run release

# =================================================================================================
# Stage 2: runtime
# =================================================================================================
FROM debian:bookworm-slim AS runtime

ENV DEBIAN_FRONTEND=noninteractive
ENV LANG=en_US.UTF-8

RUN apt-get update && apt-get install -y --no-install-recommends \
      ca-certificates curl git locales sudo openssh-client dumb-init \
      libnss3 libsecret-1-0 \
  && sed -i 's/# en_US.UTF-8/en_US.UTF-8/' /etc/locale.gen && locale-gen \
  && useradd --create-home --shell /bin/bash --uid 1000 coder \
  && echo 'coder ALL=(ALL) NOPASSWD:ALL' > /etc/sudoers.d/coder \
  && rm -rf /var/lib/apt/lists/*

# Pull node 22 (matches what code-server was built against).
RUN curl -fsSL https://deb.nodesource.com/setup_22.x | bash - \
  && apt-get update && apt-get install -y --no-install-recommends nodejs \
  && rm -rf /var/lib/apt/lists/*

# Drop the built artefacts in.
COPY --from=builder --chown=coder:coder /src/release /opt/code-server

# Convenience symlink.
RUN ln -s /opt/code-server/out/node/entry.js /usr/local/bin/code-server \
  && chmod +x /usr/local/bin/code-server

USER coder
WORKDIR /home/coder
EXPOSE 8080

# Default to listening on all interfaces with no auth (suitable for local
# `docker run -p 8080:8080`; pass --auth=password for shared use).
ENTRYPOINT ["/usr/bin/dumb-init", "--", "node", "/opt/code-server/out/node/entry.js"]
CMD ["--bind-addr", "0.0.0.0:8080", "--auth", "none", "/home/coder"]
