# Dance integration for code-server

This directory adds [Dance](https://github.com/71/dance) modal editing to
code-server's VS Code build, mirroring what our companion fork
[`WjcmeAFJb/vscodium`](https://github.com/WjcmeAFJb/vscodium) does for the
desktop application.

## What's here

```
dance/
├── extension/                      pre-built built-in extension (esbuild bundle)
│   ├── package.json
│   ├── out/extension.js
│   ├── out/web-extension.js
│   ├── README.md, LICENSE, .vscodeignore
│   └── assets/
├── contrib/                        renderer-side workbench contribution
│   └── browser/dance.contribution.ts
├── register-contrib.patch          wires the contribution into workbench.common.main.ts
├── install-into-vscode.sh          overlays the above onto lib/vscode and applies the patch
├── Dockerfile                      multi-stage build for a self-contained server image
└── serve.sh                        build + run the container locally (podman or docker)
```

## How it slots into code-server's build

code-server's build flow is roughly:

```
git submodule update --init lib/vscode    # upstream microsoft/vscode at a pinned commit
quilt push -a                             # apply patches/*.diff to lib/vscode
npm ci                                    # install deps (root + lib/vscode + test)
npm run build:vscode                      # gulp vscode-reh-web-${arch}-min
npm run build                             # bundle code-server's own server code
npm run release                           # stage release under release/
```

We slot **`./dance/install-into-vscode.sh`** in between `quilt push -a` and
`npm ci`. It:

1. copies `extension/` → `lib/vscode/extensions/dance/`
2. copies `contrib/` → `lib/vscode/src/vs/workbench/contrib/dance/`
3. applies `register-contrib.patch` (one-line `import` in
   `workbench.common.main.ts`)

The Dockerfile encodes this exact flow so `serve.sh` produces a working
image without any host-side build dependencies.

## Local hosting

```bash
./dance/serve.sh            # build (~30 min on first run) then start on 127.0.0.1:8080
./dance/serve.sh --port 8088 --rebuild
```

The container exposes 8080. `serve.sh` mounts `$HOME/.config/code-server-dance`
for settings and `$HOME/.local/share/code-server-dance` for installed extensions
so they survive container recreation. Open http://127.0.0.1:8080 in a browser
once the container says it is listening.

## Why not just install Dance from the marketplace?

The bundled built-in extension alone is essentially the marketplace install
without the marketplace round-trip. The win comes from the renderer-side
workbench contribution at `contrib/browser/dance.contribution.ts`, which can
only exist if it is compiled into VS Code itself. It exposes
`_dance.{setMode, atomicEdit, regex.exec, pushSelections, popSelections, diag}`
and lifecycle-bound caches that the bundled extension uses to bypass the
extension-host RPC for hot operations (mode flips today; more on the way).
