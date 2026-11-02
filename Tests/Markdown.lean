/-
Copyright (c) 2026 Paul Butcher. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
-/
import Markdown

namespace Tests.Markdown

open _root_.Markdown

/-- The value an attribute's last setting gives it: `some (some v)` when it is set to `v`, `some
none` when it is removed, and `none` when nothing mentions it. -/
def lastSetting (settings : List (String × Option String)) (name : String) : Option (Option String) :=
  (settings.reverse.find? (·.1 == name)).map (·.2)

/-- Each attribute ends up with the value of its last setting, and one removed by its last setting
is absent. lean-html-model's payload laws let a later attribute override an earlier one and let a
boolean attribute turned off remove one set before, so an element built any other way would carry
an attribute the Markdown renderer meant to change or remove.

`settings` is any sequence of settings in the order the payload received them and `name` any
attribute name. `List.lookup name` answers the value `resolve` gives that attribute, or `none` when
it has none. `lastSetting` answers the last setting naming it, so `Option.join` of that is the value
it leaves: its value when it sets one, and `none` when it removes the attribute or nothing names
it. -/
theorem resolve_lookup (settings : List (String × Option String)) (name : String) :
    (resolve settings).lookup name = (lastSetting settings name).join := by
  induction settings with
  | nil => rfl
  | cons s rest ih =>
    obtain ⟨n, v⟩ := s
    simp only [lastSetting, List.reverse_cons, List.find?_append] at ih ⊢
    by_cases hr : rest.any (·.1 == n)
    · have hfind : (rest.reverse.find? (·.1 == n)).isSome := by
        simpa [List.find?_isSome] using hr
      simp only [resolve, hr, ite_true, ih]
      by_cases hn : n = name
      · subst hn
        obtain ⟨x, hx⟩ := Option.isSome_iff_exists.mp hfind
        simp [hx]
      · have : (rest.reverse.find? (·.1 == name)).or ([(n, v)].find? (·.1 == name)) =
            rest.reverse.find? (·.1 == name) := by
          have hb : (n == name) = false := by simp [hn]
          cases rest.reverse.find? (·.1 == name) <;> simp [List.find?, hb]
        rw [this]
    · have hnone : rest.reverse.find? (·.1 == n) = none := by
        rw [List.find?_eq_none]
        rintro ⟨a, b⟩ hx heq
        simp only [beq_iff_eq] at heq
        subst heq
        exact hr (List.any_eq_true.mpr ⟨(a, b), List.mem_reverse.mp hx, by simp⟩)
      by_cases hn : n = name
      · subst hn
        cases v <;> simp [resolve, hr, hnone, ih]
      · have : (rest.reverse.find? (·.1 == name)).or ([(n, v)].find? (·.1 == name)) =
            rest.reverse.find? (·.1 == name) := by
          have hb : (n == name) = false := by simp [hn]
          cases rest.reverse.find? (·.1 == name) <;> simp [List.find?, hb]
        rw [this, ← ih]
        have hb : (name == n) = false := by simp [Ne.symm hn]
        cases v <;> simp [resolve, hr, List.lookup, hb]

/-- `resolve` names no attribute that no setting names. `resolve_nodup` rests on it: a setting
dropped because a later one names the same attribute cannot reappear from elsewhere.

`settings` is any sequence of settings. The claim is that every name among the attributes
`resolve` produces is among the names of `settings`. -/
private theorem resolve_names_sub (settings : List (String × Option String)) :
    ∀ n ∈ (resolve settings).map (·.1), n ∈ settings.map (·.1) := by
  induction settings with
  | nil => simp [resolve]
  | cons s rest ih =>
    obtain ⟨m, v⟩ := s
    intro n hn
    simp only [resolve] at hn
    split at hn
    · exact List.mem_cons_of_mem _ (ih n hn)
    · split at hn
      · simp only [List.map_cons, List.mem_cons] at hn
        rcases hn with rfl | hn
        · simp
        · exact List.mem_cons_of_mem _ (ih n hn)
      · exact List.mem_cons_of_mem _ (ih n hn)

/-- No attribute appears twice on an element. The DOM keeps one value per attribute, so a repeated
name would leave the element's value to whichever the renderer applied last rather than to what
`resolve_lookup` establishes.

`settings` is any sequence of settings, and the claim is that the names of the attributes `resolve`
produces, in order, have no duplicates. -/
theorem resolve_nodup (settings : List (String × Option String)) :
    ((resolve settings).map (·.1)).Nodup := by
  induction settings with
  | nil => simp [resolve]
  | cons s rest ih =>
    obtain ⟨m, v⟩ := s
    simp only [resolve]
    split
    · exact ih
    · rename_i hr
      split
      · refine List.nodup_cons.mpr ⟨fun h => hr ?_, ih⟩
        obtain ⟨p, hp, he⟩ := List.mem_map.mp (resolve_names_sub rest m h)
        exact List.any_eq_true.mpr ⟨p, hp, by simp [he]⟩
      · exact ih

end Tests.Markdown
