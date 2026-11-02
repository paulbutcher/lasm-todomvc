/-
Copyright (c) 2026 Paul Butcher. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
-/
/-
The chat panel: a conversation with a model that can read and change the todo list through the
tools in ChatTools.lean. A turn is driven one round trip at a time with lean-llmclient's step
functions, so the tools run inside `update` against the list as it is when the reply arrives.
-/
import LLMClient.Core
import Lasm.UI.Elements
import Lasm.UI.Subs
import ChatTools
import Markdown

namespace Chat

open Lasm.UI
open LLMClient (Turn Step Reply)

inductive Vendor where
  | anthropic
  | openai
  deriving DecidableEq, Repr, Inhabited

def Vendor.name : Vendor → String
  | .anthropic => "anthropic"
  | .openai => "openai"

def Vendor.ofName? : String → Option Vendor
  | "anthropic" => some .anthropic
  | "openai" => some .openai
  | _ => none

def Vendor.label : Vendor → String
  | .anthropic => "Anthropic"
  | .openai => "OpenAI"

structure Credentials where
  vendor : Vendor
  key : String

def toolGuidance : String :=
  "Use the tools to read and change the person's todos rather than answering from memory: the " ++
  "list changes underneath you, both from your own tool calls and from the person editing it " ++
  "directly, so call list_todos again rather than trusting what it said earlier. Ids are " ++
  "internal; refer to a todo by its title when you talk about it."

def systemPrompt : String :=
  "You are the assistant built into a todo list application, talking to the person whose list " ++
  "it is. " ++ toolGuidance ++ " Keep replies short. Format them as Markdown, and use a " ++
  "bulleted list when you are listing todos."

/-- Claude's current models think before they reply, which cannot be turned off and counts
against this budget, so it is well above what a short reply needs. -/
def maxOutputTokens : Nat := 4096

/-- Enough for listing, then changing, then listing again; a request needing more is reported as
such rather than run on indefinitely. -/
def maxIterations : Nat := 6

def config : Vendor → LLMClient.Config
  | .anthropic =>
    { LLMClient.Claude.defaultConfig with
      maxOutputTokens, systemPrompt := some systemPrompt
      extraHeaders := [("anthropic-dangerous-direct-browser-access", "true")] }
  | .openai => { LLMClient.OpenAI.defaultConfig with maxOutputTokens, systemPrompt := some systemPrompt }

/-- Written in place of the reply a failed turn never produced, once tools have run in it, so the
conversation can still be continued: the APIs require roles to alternate. -/
def unfinishedNote : String :=
  "(This turn stopped before I could reply. Any tools listed above did run.)"

/-! Storage: the key for the session only, the conversation alongside the todos. -/

def keyStorageKey : String := "todos-lasm-key"
def transcriptStorageKey : String := "todos-lasm-chat"

def encodeCredentials (c : Credentials) : String :=
  (Json.mkObj [("vendor", c.vendor.name), ("key", c.key)]).compress

def decodeCredentials (s : String) : Except String Credentials := do
  let j ← (Json.parse s).mapError toString
  let name ← j.getObjValAs? String "vendor"
  let some vendor := Vendor.ofName? name | throw s!"unknown provider {name}"
  return { vendor, key := ← j.getObjValAs? String "key" }

def encodeTranscript (history : Array LLMClient.Msg) : String :=
  (Json.arr (history.map LLMClient.Msg.toJson)).compress

def decodeTranscript (s : String) : Except String (Array LLMClient.Msg) := do
  let j ← (Json.parse s).mapError toString
  (← j.getArr?).mapM LLMClient.Msg.fromJson?

/-! The model -/

/-- A turn waiting on the model: the key it was started with, which it keeps to the end, and the
history it last sent. -/
structure InFlight where
  credentials : Credentials
  turn : Turn
  prompt : String

structure Model where
  credentials : Option Credentials := none
  /-- The key form. -/
  vendor : Vendor := .anthropic
  keyField : String := ""
  /-- The conversation as of the last turn to finish. -/
  history : Array LLMClient.Msg := #[]
  inFlight : Option InFlight := none
  /-- Counts turns started and abandoned, so that a reply to an abandoned one is recognised. -/
  generation : Nat := 0
  draft : String := ""
  /-- Set when Enter sends the draft. The browser then inserts the newline it was going to, and
  what the input event carrying it reports must not become the new draft. -/
  swallowNewline : Bool := false
  error : Option String := none
  /-- The panel's width in pixels, once the divider has been dragged. -/
  width : Option Float := none
  dragging : Bool := false

inductive Msg where
  | keyLoaded (stored : Option String)
  | transcriptLoaded (stored : Option String)
  | chooseVendor (v : Vendor)
  | updateKey (s : String)
  | saveKey
  | forgetKey
  | updateDraft (s : String)
  /-- `byEnter` is set when Enter sent it rather than the button. -/
  | send (byEnter : Bool)
  | replied (generation : Nat) (reply : Except String Reply)
  | newChat
  | startDrag
  | drag (x viewport : Float)
  | stopDrag

def Model.busy (m : Model) : Bool := m.inFlight.isSome

/-- What is shown: the conversation, and a turn in flight as far as it has got. -/
def Model.shown (m : Model) : Array LLMClient.Msg :=
  match m.inFlight with
  | some f => f.turn.history
  | none => m.history

/-- `request credentials generation history` asks the model to continue `history`, and answers
with `.replied generation`. It is the one effect that needs the browser, so the app supplies it. -/
abbrev Request := Credentials → Nat → Array LLMClient.Msg → Cmd Msg

def saveTranscript (history : Array LLMClient.Msg) : Cmd Msg :=
  Cmd.storageSet transcriptStorageKey (encodeTranscript history)

/-- Ends the turn with `history` as the conversation, closed off so that it can be continued. -/
def finish (m : Model) (history : Array LLMClient.Msg) (error : Option String) : Model × Cmd Msg :=
  let history := LLMClient.closeOff history unfinishedNote
  ({ m with history, inFlight := none, error }, saveTranscript history)

/-- Acts on `step` for a turn started with `f`'s key and prompt. -/
def settle (request : Request) (f : InFlight) (m : Model) : Step → Model × Cmd Msg
  | .send turn => ({ m with inFlight := some { f with turn } }, request f.credentials m.generation turn.history)
  | .done history _ => finish m history none
  /- `answerWith` resumes with `.send` or `.done`, so this is not reached from `advance`, but
  nothing here proves it. Dropping the turn keeps the conversation one that can be continued. -/
  | .runTools _ => finish m m.history (some "the model's tool calls could not be answered")

/-- Acts on `step`, running any tools it asks for against `todo`. -/
def advance (request : Request) (f : InFlight) (todo : Todo.Model) (m : Model) (step : Step) :
    Todo.Model × Model × Cmd Msg :=
  match step with
  | .runTools pending =>
    let (todo, step) := pending.answerWith ChatTools.run todo
    let (m, cmd) := settle request f m step
    (todo, m, cmd)
  | step =>
    let (m, cmd) := settle request f m step
    (todo, m, cmd)

def clean (s : String) : String := s.trimAscii.toString

/-- The width the divider is dragged to, kept within what leaves both panes usable. -/
def clampWidth (x viewport : Float) : Float :=
  let w := viewport - x
  max 288 (min w (viewport - 320))

def update (request : Request) (msg : Msg) (todo : Todo.Model) (m : Model) :
    Todo.Model × Model × Cmd Msg :=
  let only (r : Model × Cmd Msg) := (todo, r.1, r.2)
  match msg with
  | .keyLoaded none => only (m, .none)
  | .keyLoaded (some s) =>
    match decodeCredentials s with
    | .ok c => only ({ m with credentials := some c, vendor := c.vendor }, .none)
    | .error e => only ({ m with error := some s!"The saved key could not be read ({e})." },
        Cmd.storageRemove keyStorageKey (storage := .session))
  | .transcriptLoaded none => only (m, .none)
  | .transcriptLoaded (some s) =>
    match decodeTranscript s with
    | .ok history => only ({ m with history := LLMClient.closeOff history unfinishedNote }, .none)
    | .error e => only ({ m with error := some s!"The saved conversation could not be read ({e}), so this is a new one." },
        .none)
  | .chooseVendor v => only ({ m with vendor := v }, .none)
  | .updateKey s => only ({ m with keyField := s }, .none)
  | .saveKey =>
    let key := clean m.keyField
    if key = "" then only (m, .none)
    else
      let c := { vendor := m.vendor, key }
      only ({ m with credentials := some c, keyField := "", error := none },
        Cmd.batch [Cmd.storageSet keyStorageKey (encodeCredentials c) (storage := .session),
          Cmd.focus "chat-prompt"])
  | .forgetKey =>
    only ({ m with credentials := none }, Cmd.storageRemove keyStorageKey (storage := .session))
  | .updateDraft s =>
    if m.swallowNewline then only ({ m with swallowNewline := false }, .none)
    else only ({ m with draft := s }, .none)
  | .send byEnter =>
    let prompt := clean m.draft
    match m.credentials with
    | some credentials =>
      if prompt = "" || m.busy then only (m, .none)
      else
        let m := { m with draft := "", error := none, generation := m.generation + 1,
                          swallowNewline := byEnter }
        let history := m.history.push (.user prompt)
        match Turn.start history maxIterations with
        | .send turn => only ({ m with inFlight := some { credentials, turn, prompt } },
            request credentials m.generation turn.history)
        | step => only (finish m (match step with | .done h _ => h | _ => m.history) none)
    | none => only (m, .none)
  | .replied generation reply =>
    match m.inFlight with
    | some f =>
      if generation ≠ m.generation then only (m, .none)
      else match reply with
        | .ok reply => advance request f todo m (f.turn.receive reply)
        | .error e =>
          -- Before any tool has run, nothing happened that is worth keeping, so the prompt goes
          -- back to the field to be tried again.
          if f.turn.history.size = m.history.size + 1 then
            only ({ m with inFlight := none, error := some e,
                           draft := if m.draft = "" then f.prompt else m.draft }, .none)
          else only (finish m f.turn.history (some e))
    | none => only (m, .none)
  | .newChat =>
    only ({ m with history := #[], inFlight := none, generation := m.generation + 1, error := none },
      Cmd.storageRemove transcriptStorageKey)
  | .startDrag => only ({ m with dragging := true }, .none)
  | .drag x viewport => only ({ m with width := some (clampWidth x viewport) }, .none)
  | .stopDrag => only ({ m with dragging := false }, .none)

def init : Cmd Msg :=
  Cmd.batch [Cmd.storageGet keyStorageKey .keyLoaded (storage := .session),
    Cmd.storageGet transcriptStorageKey .transcriptLoaded]

def subscriptions (m : Model) : Subs Msg :=
  if m.dragging then
    Subs.batch [
      Subs.onDocument "pointermove"
        (Decoder.map2 Msg.drag Decoder.clientX (Decoder.float ["view", "innerWidth"])),
      Subs.onDocument "pointerup" (.succeed .stopDrag)]
  else .none

/-! The view -/

def toolList (names : Array String) (runningLast : Bool) : List (Html Msg) :=
  if names.isEmpty then []
  else
    [ul [class_ "chat-tools"] (names.toList.zipIdx.map fun (name, i) =>
      li [class_ (if runningLast && i + 1 == names.size then "chat-tool running" else "chat-tool")]
        [span [class_ "chat-tool-name"] [text name]])]

def bubble (cls : String) (children : List (Html Msg)) : Html Msg :=
  div [class_ s!"chat-bubble {cls}"] children

/-- A tool result is for the model, not the person: what was asked for is shown instead, on the
assistant turn that asked. -/
def messageView : LLMClient.Msg → List (Html Msg)
  | .user text => [div [class_ "chat-message from-user"] [bubble "" [Lasm.UI.text text]]]
  | .assistant content =>
    let said := LLMClient.Block.joinText content
    let asked := toolList ((LLMClient.Block.toolCalls content).map (·.name)) false
    let spoken := if said.isEmpty then [] else [bubble "" (Markdown.render said)]
    if asked.isEmpty && spoken.isEmpty then []
    else [div [class_ "chat-message from-assistant"] (asked ++ spoken)]
  | .toolResult .. => []

def statusView (m : Model) : List (Html Msg) :=
  match m.error with
  | some e => [div [class_ "chat-message from-assistant"] [bubble "chat-error" [text s!"That went wrong: {e}"]]]
  | none =>
    if m.busy then
      [div [class_ "chat-message from-assistant"] [bubble "chat-thinking" [span [] [text "Thinking"]]]]
    else []

def conversationView (m : Model) : Html Msg :=
  let shown := m.shown
  let body :=
    if shown.isEmpty && !m.busy && m.error.isNone then
      [div [class_ "chat-empty"] [p [] [text "Ask me to add, change, or find something in your list."]]]
    else shown.toList.flatMap messageView ++ statusView m
  div [id_ "chat-conversation", class_ "chat-conversation"] body

/-- Enter sends and Shift+Enter starts a new line; Enter while composing text in an input method
belongs to the input method. -/
def onSend : Attr Msg :=
  on "keydown" ((Decoder.map2 (·, ·) Decoder.key
      (Decoder.map2 (·, ·) Decoder.shiftKey (Decoder.bool ["isComposing"]))).filterMap fun
    | ("Enter", false, false) => some (.send true)
    | _ => none)

def keyForm (m : Model) : List (Html Msg) :=
  let choice (v : Vendor) :=
    label [class_ "chat-vendor"]
      [input [type_ "radio", attr "name" "vendor", Lasm.UI.checked (m.vendor == v),
        onCheck fun _ => .chooseVendor v], text v.label]
  [div [class_ "chat-key"]
    [p [] [text "To chat about your list, enter an API key. It is kept only for this browser session, and sent only to the provider you choose."],
     div [class_ "chat-vendors"] [choice .anthropic, choice .openai],
     div [class_ "chat-form"]
       [input [id_ "chat-key", class_ "chat-prompt", type_ "password", autofocus true,
          placeholder s!"{m.vendor.label} API key", value m.keyField, onInput .updateKey, onEnter .saveKey],
        button [class_ "chat-send", onClick .saveKey] [text "Save"]],
     match m.error with
     | some e => p [class_ "chat-key-error"] [text e]
     | none => empty]]

def promptForm (m : Model) : List (Html Msg) :=
  [conversationView m,
   div [class_ "chat-form"]
     [textarea [id_ "chat-prompt", class_ "chat-prompt", attr "rows" "2",
        placeholder "Ask about your todos", value m.draft, onInput .updateDraft, onSend] [],
      button [class_ "chat-send", disabled m.busy, onClick (.send false)] [text "Send"]]]

def view (m : Model) : List (Html Msg) :=
  let header :=
    div [class_ "chat-header"]
      [h2 [] [text "Assistant"],
       div [class_ "chat-actions"]
         (if m.credentials.isSome then
           [button [class_ "chat-reset", onClick .newChat] [text "New chat"],
            button [class_ "chat-reset", onClick .forgetKey] [text "Change key"]]
          else [])]
  let panel :=
    aside ([id_ "chat-panel", class_ "chat-panel"] ++
        (m.width.map fun w => style "flex-basis" s!"{w}px").toList)
      (header :: if m.credentials.isSome then promptForm m else keyForm m)
  [div [class_ (if m.dragging then "app-divider dragging" else "app-divider"),
     preventDefaultOn "pointerdown" (.succeed .startDrag)] [],
   panel]

end Chat
