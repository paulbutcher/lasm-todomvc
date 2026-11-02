/-
Copyright (c) 2026 Paul Butcher. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
-/
import Chat

namespace Tests.Chat

open _root_.Chat

/-- `history` does not end on a tool result, which is what the APIs need of a history before a new
user turn is added to it. -/
def Closed (history : Array LLMClient.Msg) : Prop :=
  ∀ id output isError structured, history.back? ≠ some (.toolResult id output isError structured)

/-- Closing off a history leaves one that can be continued. lean-llmclient proves the same of
`closeOff` in its own tests, which a consumer cannot import, so it is proved again here.

`history` is any history and `text` the closing turn's text. The claim is that `closeOff` returns
a `Closed` history: it either appends an assistant turn or returns a history already `Closed`. -/
theorem closeOff_closed (history : Array LLMClient.Msg) (text : String) :
    Closed (LLMClient.closeOff history text) := by
  intro id output isError structured
  unfold LLMClient.closeOff
  split
  · simp
  · next hb => exact fun e => hb id output isError structured e

/-- A turn ended by `finish` leaves a conversation that can be continued. Every way a turn ends,
by a reply, by giving up or by failing after tools ran, goes through `finish`.

`m` is any model, `history` any history and `error` any error. The claim is that the history of
the model `finish` returns is `Closed`. -/
theorem finish_closed (m : Model) (history : Array LLMClient.Msg) (error : Option String) :
    Closed (finish m history error).1.history :=
  closeOff_closed history unfinishedNote

/-- Acting on a step keeps the conversation one that can be continued: it either leaves it alone,
while the turn is still going, or ends the turn through `finish`.

`request` is any way of sending, `f` the turn in flight, `m` a model whose history `h` says is
`Closed`, and `step` any step. The claim is that the model `settle` returns is `Closed` too. -/
theorem settle_closed (request : Request) (f : InFlight) (m : Model) (step : LLMClient.Step)
    (h : Closed m.history) : Closed (settle request f m step).1.history := by
  cases step with
  | send turn => exact h
  | done history text => exact finish_closed _ _ _
  | runTools pending => exact finish_closed _ _ _

/-- Acting on a reply, tools included, keeps the conversation one that can be continued.

`request`, `f`, `m` and `h` are as above, `todo` is the list the tools run against and `step` any
step. The claim is about the chat model `advance` returns, the second of its three results. -/
theorem advance_closed (request : Request) (f : InFlight) (todo : Todo.Model) (m : Model)
    (step : LLMClient.Step) (h : Closed m.history) :
    Closed (advance request f todo m step).2.1.history := by
  unfold advance
  split
  · exact settle_closed _ _ _ _ h
  · exact settle_closed _ _ _ _ h

/-- Whatever message arrives, the conversation the chat keeps, and stores, can still be continued.
A conversation left ending on tool results would have every later request refused by the API, with
nothing the person could do about it but start a new chat; that includes one read back from
storage after a turn failed part way.

`request` is any way of sending, `msg` any message, `todo` any list and `m` a model whose history
`h` says is `Closed`. The claim is that the chat model `update` returns has a `Closed` history. -/
theorem update_closed (request : Request) (msg : Msg) (todo : Todo.Model) (m : Model)
    (h : Closed m.history) : Closed (update request msg todo m).2.1.history := by
  cases msg with
  | keyLoaded stored =>
    rcases stored with _ | s
    · exact h
    · dsimp only [update]; cases decodeCredentials s <;> exact h
  | transcriptLoaded stored =>
    rcases stored with _ | s
    · exact h
    · dsimp only [update]; cases decodeTranscript s
      · exact h
      · exact closeOff_closed _ _
  | saveKey => dsimp only [update]; split <;> exact h
  | updateDraft s => dsimp only [update]; split <;> exact h
  | send byEnter =>
    dsimp only [update]
    rcases m.credentials with _ | c
    · exact h
    · dsimp only; split
      · exact h
      · split
        · exact h
        · exact finish_closed _ _ _
  | replied generation reply =>
    dsimp only [update]
    rcases m.inFlight with _ | f
    · exact h
    · dsimp only; split
      · exact h
      · rcases reply with e | reply
        · dsimp only; split
          · exact h
          · exact finish_closed _ _ _
        · exact advance_closed _ _ _ _ _ h
  | newChat => intro _ _ _ _ h'; simp [update] at h'
  | _ => exact h

/-- Every chat model reachable from the initial one keeps a conversation that can be continued.

`request` is any way of sending, and `msgs` any sequence of messages, each paired with the list as
it stood when it arrived; `update` is folded over them from the initial model. -/
theorem reachable_closed (request : Request) (msgs : List (Msg × Todo.Model)) :
    Closed (msgs.foldl (fun m (msg, todo) => (update request msg todo m).2.1) {}).history := by
  suffices ∀ m : Model, Closed m.history →
      Closed (msgs.foldl (fun m (msg, todo) => (update request msg todo m).2.1) m).history from
    this _ (by intro _ _ _ _ h; simp at h)
  induction msgs with
  | nil => intro m h; exact h
  | cons x xs ih => intro m h; exact ih _ (update_closed request x.1 x.2 m h)

end Tests.Chat
