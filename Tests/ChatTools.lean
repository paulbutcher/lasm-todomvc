/-
Copyright (c) 2026 Paul Butcher. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
-/
import ChatTools

namespace Tests.ChatTools

open LLMClient Todo _root_.ChatTools

def call (name : String) (args : List (String × Json)) : ToolCall :=
  { id := "call", name, input := Json.mkObj args }

def runAll (m : Model) (calls : List ToolCall) : Model × List ToolOutcome :=
  calls.foldl (fun (m, outs) c => let (m', o) := run m c; (m', outs ++ [o])) (m, [])

def failed : ToolOutcome → Bool
  | .error _ => true
  | .ok _ => false

def listedTitles (o : ToolOutcome) : Option (List String) := do
  let .ok (_, some j) := o | none
  let todos ← (j.getObjVal? "todos" >>= Json.getArr?).toOption
  todos.toList.mapM fun t => (t.getObjVal? "title" >>= Json.getStr?).toOption

def titles (m : Model) : List String := m.todos.map (·.title)

def milk : Model := step (.addTitled "milk") {}

-- A list later in a reply sees what an earlier call in it did.
#guard (listedTitles ((runAll {} [call "add_todo" [("title", "  bread ")], call "list_todos" []]).2.getD 1 (.error ""))) == some ["bread"]

-- An id or a flag sent as the string it prints as is taken.
#guard (titles (run milk (call "set_done" [("id", "0"), ("done", "true")])).1 == ["milk"]) &&
  ((run milk (call "set_done" [("id", "0"), ("done", "true")])).1.todos.all (·.completed))

-- Anything else unreadable is refused rather than defaulted.
#guard failed (run milk (call "set_done" [("id", "zero"), ("done", true)])).2
#guard failed (run milk (call "set_done" [("id", 0), ("done", "yes")])).2
#guard failed (run milk (call "delete_todo" [])).2

-- An id with no todo is refused, rather than silently doing nothing.
#guard failed (run milk (call "delete_todo" [("id", 7)])).2
#guard failed (run milk (call "edit_todo" [("id", 7), ("title", "x")])).2

-- A blank title adds nothing, and deletes the todo it is given to.
#guard failed (run milk (call "add_todo" [("title", "   ")])).2
#guard titles (run milk (call "edit_todo" [("id", 0), ("title", " ")])).1 == []

-- The filter selects by completion.
#guard
  let (m, _) := runAll milk [call "add_todo" [("title", "eggs")], call "set_done" [("id", 0), ("done", true)]]
  listedTitles (run m (call "list_todos" [("filter", "active")])).2 == some ["eggs"] &&
  listedTitles (run m (call "list_todos" [("filter", "completed")])).2 == some ["milk"]

end Tests.ChatTools
