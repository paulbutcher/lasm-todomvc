/-
Copyright (c) 2026 Paul Butcher. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
-/
import ChatTools

namespace Tests.Todo

open _root_.Todo

/-- Setting a todo's completion twice leaves it as setting it once does. The model's `set_done` is
absolute for this reason: a call that is retried, or repeated in a later turn, must not undo the
one before it as a toggle would.

`id` names the todo and `b` the completion asked for, and `m` is any model. The claim is that
applying `.setCompleted id b` to the model it has already produced gives that same model back. -/
theorem setCompleted_idem (id : Nat) (b : Bool) (m : Model) :
    step (.setCompleted id b) (step (.setCompleted id b) m) = step (.setCompleted id b) m := by
  simp only [step, List.map_map]
  congr 2
  funext t
  simp only [Function.comp, setCompleted]
  split <;> simp_all

/-- Setting a todo's completion gives it that completion and leaves every other todo as it was.
The model is told the todo is done or active again, and would otherwise be wrong about the todo
it named or unaware of a change to one it did not.

`id`, `b` and `m` are as above. The first claim is that every todo with id `id` afterwards has
completion `b`; the second that every todo with another id afterwards was in `m` unchanged. -/
theorem setCompleted_sets (id : Nat) (b : Bool) (m : Model) :
    (∀ t ∈ (step (.setCompleted id b) m).todos, t.id = id → t.completed = b) ∧
    (∀ t ∈ (step (.setCompleted id b) m).todos, t.id ≠ id → t ∈ m.todos) := by
  constructor <;> intro t ht <;> simp only [step, List.mem_map] at ht <;>
    obtain ⟨u, hu, rfl⟩ := ht <;> simp only [setCompleted] <;> split <;> simp_all

/-- Retitling a todo with a title that is blank once trimmed deletes it, exactly as deleting it
does. That is what clearing a title in the list itself does, and `edit_todo` tells the model so.

`id` names the todo, `title` is the title given, which `h` says is blank once cleaned, and `m` is
any model. The claim is that the two messages produce the same model. -/
theorem setTitle_blank_deletes (id : Nat) (title : String) (m : Model) (h : clean title = "") :
    step (.setTitle id title) m = step (.delete id) m := by
  simp [step, h]

/-- A tool call that fails leaves the todo list as it was. The model is told the call failed, and
a change made anyway would be one it believes did not happen.

`m` is any model and `call` any call. `run` answers the model the call leaves and its outcome; the
claim is that whenever the outcome is `.error`, the model is `m`. -/
theorem run_error_unchanged (m : Model) (call : LLMClient.ToolCall) (e : String)
    (h : (ChatTools.run m call).2 = .error e) : (ChatTools.run m call).1 = m := by
  unfold ChatTools.run at *
  split at * <;> simp_all

end Tests.Todo
