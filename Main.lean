/-
Copyright (c) 2026 Paul Butcher. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
-/
/-
TodoMVC (https://todomvc.com) in Lean with Lasm.UI, beside a chat panel that can
read and change the list (Chat.lean). The state and update are in Todo.lean,
with proofs that every reachable model is valid; this file is the view, storage,
routing, and the request the chat sends. Build: lasm build Main.lean --target browser.
-/
import Json
import Lasm.UI
import Lasm.Web
import LLMClient.Fetch
import Todo
import Chat
open Lasm.UI Todo

/-! Storage: the todos as JSON in localStorage. -/

def toJson (todos : List Item) : String :=
  (Json.arr (todos.toArray.map fun t =>
    Json.mkObj [("id", Json.ofNat t.id), ("title", t.title), ("completed", t.completed)])).compress

def fromJson (s : String) : List Item :=
  match Json.parse s with
  | .ok (.arr items) => items.toList.filterMap fun j => do
      let id ← (j.getObjValAs? Nat "id").toOption
      let title ← (j.getObjValAs? String "title").toOption
      let completed ← (j.getObjValAs? Bool "completed").toOption
      return { id, title, completed }
  | _ => []

/-! Routing: `#/`, `#/active`, `#/completed`. -/

def filterOf (u : Url) : Filter :=
  match u.fragment with
  | some "/active" => .active
  | some "/completed" => .completed
  | _ => .all

/-! The view -/

def editId (id : Nat) : String := s!"edit-{id}"

def viewTodo (m : Model) (t : Item) : Html Msg :=
  let editing := match m.editing with | some (e, _) => e == t.id | none => false
  html! <li key={t.id} class={" ".intercalate ((if t.completed then ["completed"] else []) ++ (if editing then ["editing"] else []))}>
          <div class="view">
            <input class="toggle" type="checkbox" checked={t.completed} onCheck={fun _ => Msg.toggle t.id} />
            <label onDoubleClick={Msg.startEdit t.id}>{t.title}</label>
            <button class="destroy" onClick={Msg.delete t.id} />
          </div>
          {if editing then
            [html! <input class="edit" id={editId t.id} value={(m.editing.map (·.2)).getD ""}
                     onInput={Msg.updateEdit} onEnter={Msg.commitEdit} onBlur={Msg.commitEdit} onEscape={Msg.cancelEdit} />]
           else []}
        </li>

def visible (m : Model) : List Item :=
  match m.filter with
  | .all => m.todos
  | .active => m.todos.filter (!·.completed)
  | .completed => m.todos.filter (·.completed)

def filterLink (m : Model) (f : Filter) (href label : String) : Html Msg :=
  html! <li><a class={if m.filter == f then "selected" else ""} href={href}>{label}</a></li>

def view (m : Model) : Html Msg :=
  let active := (m.todos.filter (!·.completed)).length
  let completed := m.todos.length - active
  html! <section class="todoapp">
          <header class="header">
            <h1>todos</h1>
            <input class="new-todo" id="new-todo" placeholder="What needs to be done?" autofocus value={m.field}
              onInput={Msg.updateField} onEnter={Msg.add} />
          </header>
          {if m.todos.isEmpty then [] else
            [html! <main class="main">
                     <div class="toggle-all-container">
                       <input class="toggle-all" id="toggle-all" type="checkbox" checked={active == 0}
                         onCheck={Msg.toggleAll} />
                       <label class="toggle-all-label" for="toggle-all">Mark all as complete</label>
                     </div>
                     <ul class="todo-list">{(visible m).map (viewTodo m)}</ul>
                   </main>,
             html! <footer class="footer">
                     <span class="todo-count"><strong>{active}</strong> {if active == 1 then "item" else "items"} left</span>
                     <ul class="filters">
                       {filterLink m .all "#/" "All"}
                       {filterLink m .active "#/active" "Active"}
                       {filterLink m .completed "#/completed" "Completed"}
                     </ul>
                     {if completed == 0 then [] else
                       [html! <button class="clear-completed" onClick={Msg.clearCompleted}>Clear completed</button>]}
                   </footer>]}
        </section>

/-! The chat's request, the one effect it needs the browser for -/

def request : Chat.Request := fun c generation history =>
  Cmd.ofEffect (.io fun dispatch => Lasm.Web.background do
    let config := Chat.config c.vendor
    let provider := match c.vendor with
      | .anthropic => LLMClient.Claude.providerWith LLMClient.Fetch.transport c.key config
      | .openai => LLMClient.OpenAI.providerWith LLMClient.Fetch.transport c.key config
    let reply ← provider.sendRequest history ChatTools.tools
    dispatch (.replied generation reply))

/-! The app -/

structure AppModel where
  todo : Model
  chat : Chat.Model := {}

inductive AppMsg where
  | todo (msg : Msg)
  | chat (msg : Chat.Msg)

def updateTodo (msg : Msg) (m : Model) : Model × Cmd Msg :=
  let (m', cmd) := Todo.update toJson msg m
  match msg with
  | .startEdit id => (m', cmd ++ Cmd.focus (editId id))
  | _ => (m', cmd)

/-- The chat's tools change the list without a `Msg` of the app's own, so the list is saved here
whenever a chat message leaves it different. -/
def updateChat (msg : Chat.Msg) (m : AppModel) : AppModel × Cmd AppMsg :=
  let (todo, chat, cmd) := Chat.update request msg m.todo m.chat
  let save := if todo.todos == m.todo.todos then .none else Cmd.storageSet storageKey (toJson todo.todos)
  ({ todo, chat }, Cmd.batch [cmd.map .chat, save])

def appView (m : AppModel) : Html AppMsg :=
  div [class_ "app-shell"]
    ([div [class_ "app-pane"]
       [(view m.todo).map .todo,
        html! <footer class="info">
                <p>Double-click to edit a todo</p>
                <p>Written in Lean with <a href="https://github.com/Millillion/lasm/blob/main/docs/UI.md">Lasm.UI</a>; its update is proved to keep the model valid</p>
              </footer>]] ++
     (Chat.view m.chat).map (·.map .chat))

def app : App Unit AppModel AppMsg where
  init _ url := ({ todo := { filter := filterOf url } },
    Cmd.batch [Cmd.storageGet storageKey fun s => .todo (.loaded (fromJson (s.getD "[]"))),
      Cmd.focus "new-todo", Chat.init.map .chat])
  update
    | .todo msg, m => let (todo, cmd) := updateTodo msg m.todo; ({ m with todo }, cmd.map .todo)
    | .chat msg, m => updateChat msg m
  view := appView
  subscriptions m := (Chat.subscriptions m.chat).map .chat
  onUrlChange := some fun u => .todo (.setFilter (filterOf u))

def main : IO Unit := app.run
