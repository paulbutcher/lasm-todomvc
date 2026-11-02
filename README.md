# lasm-todomvc

[TodoMVC](https://todomvc.com) in Lean (Lasm.UI), compiled ahead of time to WebAssembly by [Lasm](https://github.com/Millillion/lasm), starting from Lasm's [todomvc example](https://github.com/Millillion/lasm/tree/main/examples/ui/todomvc). It runs in Chrome, Edge, Firefox and Safari.

## Requirements

Node.js 24 or newer with npm. Lasm downloads Lean 4.35.0 and its build tools on the first build (a few hundred MB, cached for later builds).

## Run

```sh
npm install
npm run dev        # http://127.0.0.1:5173: rebuilds when a .lean file changes, then reloads the page
npm run build      # dist/: the static site
npm run preview    # the release build, served on http://127.0.0.1:5173
```

Files:

| File | What it is |
| --- | --- |
| `Main.lean` | The view, storage and routing, with `Lasm.UI` ([guide](https://github.com/Millillion/lasm/blob/main/docs/UI.md)). |
| `Todo.lean` | The model and update, with proofs that every reachable model is valid. |
| `index.html`, `public/style.css` | The page; `lasm build` adds the loader before `</head>`, and copies `public/` into `dist/`. |
| `lakefile.toml`, `lean-toolchain` | The Lake project, pinned to Lean 4.35.0. |
| `package.json` | npm scripts, and Lasm (`@lasm/cli`) as a dev dependency. |

Both modules import `Lasm.UI`, which ships with Lasm: `npx lasm editor` (also run by `npm run dev`) makes the Lean editor resolve it ([editor setup](https://github.com/Millillion/lasm/blob/main/docs/GETTING_STARTED.md#editor)).

## Deploy

`dist/` is a static site: upload it to any static host or CDN (GitHub Pages, Cloudflare Pages, Netlify, Vercel, S3 and CloudFront, nginx). Serve `.wasm` as `application/wasm`; the `.br` and `.gz` copies let the host send compressed files without compressing them itself. Files named `app.<hash>.*` never change and can be cached forever. See the [browser deployment guide](https://github.com/Millillion/lasm/blob/main/docs/deploy/browser.md).
