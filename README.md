# lasm-todomvc

[TodoMVC](https://todomvc.com) in Lean (Lasm.UI), compiled ahead of time to WebAssembly by [Lasm](https://github.com/Millillion/lasm), starting from Lasm's [todomvc example](https://github.com/Millillion/lasm/tree/main/examples/ui/todomvc). Beside the list is a chat panel, in the style of [lean-todomvc-max](https://github.com/paulbutcher/lean-todomvc-max), where a model can read and change the list through tools. It runs in Chrome, Edge, Firefox and Safari.

## The chat panel

The panel asks for an Anthropic or OpenAI API key, which is kept in session storage and sent only to that provider, straight from the browser. The conversation is kept in local storage beside the todos. Requests go through [lean-llmclient](https://github.com/paulbutcher/lean-llmclient), and replies are rendered with [lean-markdown](https://github.com/paulbutcher/lean-markdown), sanitized, into Lasm.UI's virtual DOM. The tools run inside `update` as pure functions of the list, and change it with the same messages the list's own controls send, so the proof that every reachable model is valid covers what the model does too.

## Requirements

Node.js 24 or newer with npm. Lasm downloads Lean 4.35.0 and its build tools on the first build (a few hundred MB, cached for later builds).

## Run

```sh
npm install
npm run dev        # http://127.0.0.1:5173: rebuilds when a .lean file changes, then reloads the page
npm run build      # dist/: the static site
npm run preview    # the release build, served on http://127.0.0.1:5173
npm test           # the browser tests (Playwright, against a stand-in for the provider)
lake test          # the Lean theorems and examples in Tests/; compiling is passing
```

Files:

| File | What it is |
| --- | --- |
| `Main.lean` | The view, storage and routing, with `Lasm.UI` ([guide](https://github.com/Millillion/lasm/blob/main/docs/UI.md)), and the chat's request. |
| `Todo.lean` | The model and update, with proofs that every reachable model is valid. |
| `Chat.lean`, `ChatTools.lean` | The chat panel's model, update and view, and the tools it offers the model. |
| `Markdown.lean` | Markdown rendered into `Lasm.UI` `Html`. |
| `Tests/`, `e2e/` | Lean theorems and examples (`lake test`), and browser tests (`npm test`). |
| `index.html`, `public/` | The page and its stylesheets; `lasm build` adds the loader before `</head>`, and copies `public/` into `dist/`. |
| `lakefile.toml`, `lean-toolchain` | The Lake project, pinned to Lean 4.35.0. |
| `package.json` | npm scripts, and Lasm (`@lasm/cli`) as a dev dependency. |

The modules import `Lasm.UI`, which ships with Lasm: `npx lasm editor` (also run by `npm run dev`) makes the Lean editor resolve it ([editor setup](https://github.com/Millillion/lasm/blob/main/docs/GETTING_STARTED.md#editor)).

## Deploy

`dist/` is a static site: upload it to any static host or CDN (GitHub Pages, Cloudflare Pages, Netlify, Vercel, S3 and CloudFront, nginx). Serve `.wasm` as `application/wasm`; the `.br` and `.gz` copies let the host send compressed files without compressing them itself. Files named `app.<hash>.*` never change and can be cached forever. See the [browser deployment guide](https://github.com/Millillion/lasm/blob/main/docs/deploy/browser.md).
