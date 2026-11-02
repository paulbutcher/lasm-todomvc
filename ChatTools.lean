/-
Copyright (c) 2026 Paul Butcher. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
-/
/-
The tools the chat offers the model, run as pure functions of the todo list. A tool that changes
the list does so with a `Todo.Msg`, which goes through `Todo.step` like any other, so the invariant
proofs cover what the model does as well as what the person does.
-/
import LLMClient.Core
import Todo

namespace ChatTools

open LLMClient Todo

private def stringParam (description : String) : Json :=
  Json.mkObj [("type", "string"), ("description", description)]

private def idParam : Json :=
  Json.mkObj [("type", "integer"), ("description", "The todo's id, as reported by list_todos.")]

private def schema (properties : List (String × Json)) (required : List String) : Json :=
  Json.mkObj
    [ ("type", "object"),
      ("properties", Json.mkObj properties),
      ("required", Json.arr (required.map Json.str).toArray) ]

def tools : Array Tool := #[
  { name := "list_todos"
    description :=
      "List the person's todos. Returns an object with a `todos` array of objects with `id`, " ++
      "`title` and `done`. Call this before any tool that takes an id, since ids come from here."
    schema := schema
      [ ("filter", Json.mkObj
          [ ("type", "string"),
            ("enum", Json.arr #["all", "active", "completed"]),
            ("description", "Which todos to return. Defaults to all.") ]) ]
      [] },
  { name := "add_todo"
    description := "Add a new todo. A title that is blank once trimmed adds nothing."
    schema := schema [("title", stringParam "The text of the new todo.")] ["title"] },
  { name := "edit_todo"
    description :=
      "Change the title of an existing todo. A title that is blank once trimmed deletes it, " ++
      "which is what the same edit in the list itself does."
    schema := schema [("id", idParam), ("title", stringParam "The replacement title.")]
      ["id", "title"] },
  { name := "delete_todo"
    description := "Delete a todo outright."
    schema := schema [("id", idParam)] ["id"] },
  /- Absolute rather than a toggle, so that a retried or repeated call cannot undo the one before. -/
  { name := "set_done"
    description := "Mark a todo done, or put it back to active."
    schema := schema
      [ ("id", idParam),
        ("done", Json.mkObj
          [("type", "boolean"), ("description", "True to complete it, false to reactivate it.")]) ]
      ["id", "done"] }]

private def stringArg (input : Json) (name : String) : Option String :=
  (input.getObjVal? name >>= Json.getStr?).toOption

/-- A model sometimes sends a number as the string it would print as, so a string that reads as
one is taken. Nothing else is: an id that cannot be read is reported rather than defaulted. -/
private def idArg (input : Json) (name : String) : Option Nat :=
  match input.getObjVal? name >>= Json.getNat? with
  | .ok id => some id
  | .error _ => (stringArg input name).bind String.toNat?

private def boolArg (input : Json) (name : String) : Option Bool :=
  match input.getObjVal? name >>= Json.getBool? with
  | .ok b => some b
  | .error _ =>
    match stringArg input name with
    | some "true" => some true
    | some "false" => some false
    | _ => none

private def need (name : String) : Option α → Except String α
  | some a => .ok a
  | none => .error s!"this call needs a `{name}` argument and did not have a usable one"

private def existing (m : Model) (id : Nat) : Except String Item :=
  match m.todos.find? (·.id == id) with
  | some t => .ok t
  | none => .error s!"there is no todo with id {id}; call list_todos for the current ids"

private def itemJson (t : Item) : Json :=
  Json.mkObj [("id", Json.ofNat t.id), ("title", t.title), ("done", t.completed)]

private def listed (m : Model) (input : Json) : Json :=
  let todos : List Item := match stringArg input "filter" with
    | some "active" => m.todos.filter (!·.completed)
    | some "completed" => m.todos.filter (·.completed)
    | _ => m.todos
  Json.mkObj [("todos", Json.arr (todos.map itemJson).toArray)]

/-- What a call comes to: the change it makes, if any, and what the model is told. Every refusal is
decided before a change is chosen, so a call reported as failed changed nothing. -/
def plan (m : Model) (call : ToolCall) : Except String (Option Todo.Msg × String × Option Json) := do
  let input := call.input
  match call.name with
  | "list_todos" =>
    let j := listed m input
    return (none, j.compress, some j)
  | "add_todo" =>
    let title := clean (← need "title" (stringArg input "title"))
    if title = "" then throw "that title is blank, so nothing was added"
    return (some (.addTitled title), s!"added \"{title}\" with id {m.nextId}", none)
  | "edit_todo" =>
    let id ← need "id" (idArg input "id")
    let raw ← need "title" (stringArg input "title")
    let _ ← existing m id
    let title := clean raw
    let text := if title = "" then s!"todo {id} had its title cleared, which deleted it"
      else s!"todo {id} is now \"{title}\""
    return (some (.setTitle id raw), text, none)
  | "delete_todo" =>
    let id ← need "id" (idArg input "id")
    let t ← existing m id
    return (some (.delete id), s!"deleted \"{t.title}\"", none)
  | "set_done" =>
    let id ← need "id" (idArg input "id")
    let done ← need "done" (boolArg input "done")
    let t ← existing m id
    let text := if done then s!"\"{t.title}\" is done" else s!"\"{t.title}\" is active again"
    return (some (.setCompleted id done), text, none)
  | name => throw s!"there is no tool called {name}"

/-- Runs `call` against `m`, giving the model it leaves and the outcome to report. -/
def run (m : Model) (call : ToolCall) : Model × ToolOutcome :=
  match plan m call with
  | .ok (msg, text, structured) => (msg.elim m (step · m), .ok (text, structured))
  | .error e => (m, .error e)

end ChatTools
