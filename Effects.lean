/-
Copyright (c) 2026 Paul Butcher. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
-/
/-
The browser effects the app's updates ask for, as `Cmd.task`s. `store` is
`localStorage` unless a caller passes `sessionStorage`.
-/
import Lasm.UI.App
import Lasm.JS.Web.Dom
import Lasm.JS.Web.Html

namespace Effects

open Lasm.UI Lasm.JS.Web

def storageGet (key : String) (k : Option String → Msg) (store : IO Storage := localStorage) : Cmd Msg :=
  Cmd.task do return k (← (← store).getItem key)

def storageSet (key value : String) (store : IO Storage := localStorage) : Cmd Msg :=
  Cmd.ofEffect (.task fun _ => do (← store).setItem key value)

def storageRemove (key : String) (store : IO Storage := localStorage) : Cmd Msg :=
  Cmd.ofEffect (.task fun _ => do (← store).removeItem key)

/-- Focuses the element with id `id` once the next frame is on screen, so it may be one the
same update adds to the view. -/
def focus (id : String) : Cmd Msg :=
  Cmd.ofEffect (.task fun _ => do
    afterFrame
    if let some el ← (← document).getElementById id then
      ({ toElement := el } : HTMLElement).focus)

end Effects
