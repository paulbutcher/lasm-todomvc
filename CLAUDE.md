# CLAUDE.md

Guidance for Claude Code, and any other coding agent, working in this repo. Contributors are welcome to work another way, but agents run against this file by default.

## Verifying Lean changes

- `import Lasm.*` resolves only under Lasm's own Lean, which `npx lasm editor` (also run by `npm run dev` and `npm run build`) links as this directory's elan override; `lake`, `lean` and lean-lsp-mcp all need it. If it says the toolchain "is already installed", the link dangles: `elan toolchain uninstall` it and rerun.
- After editing a `.lean` file, verify it with `mcp__lean-lsp__lean_diagnostic_messages` (or other lean-lsp-mcp tools, e.g. `lean_goal`/`lean_multi_attempt` for interactive proof/termination work), and with `mcp__lean-lsp__lean_build` if a change adds or removes an `import`. Ignore the editor's `<ide_diagnostics>` hook output.
- All Lean code must compile without warnings, but neither Lake nor `lasm build` fails on one, so build with `lake build --wfail Todo Main Tests` (`Tests` is `lake test`, where compiling is passing). Plain `lake build` fails regardless: its default target, the native `app` executable, cannot link, since Lasm.UI's runtime exists only in the Wasm build.
- UnicodeBasic compiles C, which the override's toolchain has no headers for, so run that `lake` from the toolchain `npm run build` uses: the `~/.cache/lasm/derived/*` directory with an `include/`, put first on `PATH`. Before considering a task complete, run that, `npm run build` and `npm test` as the final ground truth.

## Commenting

- Only add a comment which says something the source does not already say. This includes file and function headers: omit them unless they earn their place.
- Do comment where it is not clear *why* the code does what it does.
- Don't explain Lean language features or quirks. Readers of this project know Lean.
- Don't refer to previous implementations or rejected designs unless that is essential to understand the code, and never to plans, milestones, or ticket numbers. A comment should still be true years from now, when nobody cares how it came about.
- Never use an emdash. Wherever you might use one, use a comma or a semicolon instead.
- Every file starts with:

      Copyright (c) 2026 Paul Butcher. All rights reserved.
      Released under Apache 2.0 license as described in the file LICENSE.

## Length

Applies to comments, documentation, and replies.

- Each addition is justifiable alone; the cost is cumulative. Before adding, ask what this file reads like after twenty more additions as justifiable as this one.
- Prefer tightening an existing line to adding a new one.
- State the rule. Give the reason only where it would otherwise look arbitrary or be misapplied.
- A section is at most five bullets of one or two lines. More than that is more than one rule, and they are not all worth keeping.
- Check the text as written, not the intention it was written with: inside the cap, and no sentence restating an earlier one.

## Markdown

- Write each paragraph as a single line. Never hard-wrap prose; leave wrapping to the renderer. Applies to every markdown file, and to issue, PR, and comment text.

## Changelog

- Where the project keeps a CHANGELOG, one short sentence per release, as the existing entries are. Several unrelated changes become several bullets, not a longer sentence.

## Process

- If asked a question, JUST answer it. Don't take a question as an instruction or a recommendation; take it literally, answer it, and stop.
- Make no source control changes unless explicitly asked: no commits, pushes, pulls, or pull requests.
- Never install OS packages; ask first. This does not apply to Lean packages, which are declared in the lakefile and the manifest.
- Instructions written for another agent should assume a fresh checkout of the library in question, not the copies under `.lake`.

## Libraries

- If a change would be easier to make in a dependency than here, stop and ask whether to make it there instead.
- If new functionality would be useful to another application, in an existing library or a new one, stop and ask where it should live.
- A change to a public signature, a default, or a supported format is a change to every consumer. Say so when proposing one.

## Test layout

Applies to published libraries. An application keeps its tests in the same package and names them in `testDriver`; if that is this project, skip this section.

- Nothing needed only for development, such as tests, test-only dependencies, or benchmarks, may appear in the dependency graph a downstream consumer resolves.
- Tests live in a subproject called `test` with its own lakefile, which requires the root package by path. The root lakefile carries a `@[test_driver]` script that runs the subproject's tests as a child process:

      @[test_driver]
      script tests do
        let child ← IO.Process.spawn
          { cmd := "lake", args := #["test"], cwd := __dir__ / "test" }
        child.wait

## What to test

- Write tests alongside new code, as long as they comply with the rules below. `update` and `view` are pure, so state claims about them in Lean; use Playwright 1.64.1 (the Chromium `.devcontainer/setup.sh` installs) only for what needs a browser.
- Don't write tests which wholly or largely restate literals from the source with no computation in between. Ask first: could this fail from a real behaviour regression, or only by retyping the expected value wrong?
- Don't test the functionality of dependencies unless asked to, or unless there is evidence of a bug. Assume dependencies do what they claim to do.
- Don't check HTML structure. Tests like that are too fragile; abstract away from the precise markup so they survive the UI evolving, which rules out comparing `Lasm.UI.render` output with a literal.
- A test of wire behaviour must not depend on how the network happens to split a write. Loopback coalesces sends, so a response written in pieces is usually read in one go, and such a test passes whether or not the code can resume from a partial read. Force the case by size, past the reader's own buffer.

## Proofs and properties

- Prefer the strongest form a claim admits: a proven theorem over a property (Lean's Plausible library) over an example and an expected result. Reach for a weaker form only when the stronger one is out of reach.
- Write a theorem rather than a property when the claim is about a pure total function and either the case analysis is finite (encodings, mappings between representations) or a counterexample would corrupt output rather than merely look wrong (an invariant a file format or a wire format depends on).
- Time-box the attempt. If a proof will not close in a few tries, fall back to a property and record the obstacle in a comment, so the next person knows it was weighed and why it failed.
- Never leave `sorry` or an admitted goal. The `plausible` tactic emits a warning, so it cannot be used here either; write the property out instead.
- When changing a module that carries properties, re-ask whether each is now provable. A property is a fallback, not a resting place.
- Theorems not needed by the production code belong in test code. They need no entry in a runner: compiling is passing.

## Documenting theorems

Applies to every theorem, `private` ones included, and overrides Commenting above for them; definitions still follow it.

- Give each one a doc comment of two paragraphs, separated by a blank line.
- The first says in plain English what the theorem establishes and why that is worth establishing. It stands alone: never "the same as above".
- The second reads the proposition back term by term, saying what each predicate answers `true` to and what each argument does, and so why that statement is the property the first paragraph names.
- Where an argument could make the proposition vacuously true, a depth bound for instance, say why it does not.
- Where the reading rests on something nothing in the codebase proves, say that rather than asserting it.

## Lean code

- Never use a partial function unless it is absolutely essential.
- Never use a function which might panic, typically marked by a trailing exclamation mark, unless it is absolutely essential.
- An `Option` whose `none` can mean "misconfigured" must not default into a value meaning "nothing was asked for". Collapsing them makes a broken server answer wrongly and silently.

## Logging

Applies where this project emits logs or spans. If it does not, skip this section.

- Write the logging with the code, not when something breaks. What was not recorded cannot be recovered.
- Log at a decision the response cannot express: an empty list and a bare 403 say nothing about which cause produced them.
- Record the value that decided the branch. "refused" is worth little; "refused, scopes held: none" ends the investigation.
- A span carries the route, not the query, so what was asked for is recorded only if it is logged.
- Don't log ordinary success where a span already records the request.

## UI code

Applies where this project serves a UI. If it does not, skip this section.

- The UI is Lasm.UI: every interaction is a `Msg` handled by `update`, and effects go through `Cmd`. Never use JavaScript unless it is essential.
