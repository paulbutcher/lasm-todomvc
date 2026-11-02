/-
Copyright (c) 2026 Paul Butcher. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
-/
/-
Markdown rendered as Lasm.UI `Html`: lean-markdown builds a sanitized lean-html-model tree, which
is erased of its typing and folded into the virtual DOM.
-/
import GFMarkdown
import Lasm.UI.Html

namespace Markdown

open Lasm.UI

variable {Msg : Type}

/-- An element's payload. A boolean attribute turned off must remove one set earlier, so attributes
are kept in the order they were set, `none` meaning absent, and resolved when the element is built. -/
structure Props where
  key : Option String := none
  attrs : List (String × Option String) := []
  styles : List (String × String) := []

instance : HtmlModel.HtmlPayload Props where
  empty := {}
  attr name value p := { p with attrs := p.attrs ++ [(name, some value)] }
  flag name on p := { p with attrs := p.attrs ++ [(name, if on then some "" else none)] }
  style name value p := { p with styles := p.styles ++ [(name, value)] }
  key k p := { p with key := some k }
  append p q := { key := q.key <|> p.key, attrs := p.attrs ++ q.attrs, styles := p.styles ++ q.styles }

/-- Each attribute's last setting, dropping those whose last setting removes them. -/
def resolve : List (String × Option String) → List (String × String)
  | [] => []
  | (name, value) :: rest =>
    if rest.any (·.1 == name) then resolve rest
    else match value with
      | some v => (name, v) :: resolve rest
      | none => resolve rest

def ns : HtmlModel.Namespace → Ns
  | .html => .html
  | .svg => .svg
  | .mathml => .mathml

def element (n : HtmlModel.Namespace) (tag : String) (p : Props) (children : List (Html Msg)) :
    Html Msg :=
  let attrs := (resolve p.attrs).map (fun (k, v) => Attr.attr k v) ++
    p.styles.map fun (k, v) => Attr.style k v
  .elem (ns n) tag p.key attrs children

mutual
/-- `.verbatim` is markup to emit unescaped, which a virtual DOM cannot express. `htmlNodesSafe`
documents that it produces none, but nothing proves it, so it is dropped rather than shown as text. -/
def ofTree : HtmlModel.Web.Tree Props → List (Html Msg)
  | .text s => [.text s]
  | .verbatim .. => []
  | .elem e _ p children =>
    [element (HtmlModel.Web.vocab.sig.ns e) (HtmlModel.Web.vocab.sig.name e) p (ofTrees children)]
  | .unchecked n tag _ p children => [element n tag p (ofTrees children)]
def ofTrees : List (HtmlModel.Web.Tree Props) → List (Html Msg)
  | [] => []
  | t :: ts => ofTree t ++ ofTrees ts
end

/-- `source` as GitHub Flavored Markdown, with anything unsafe in untrusted input removed. -/
def render (source : String) : List (Html Msg) :=
  ofTrees ((GFMarkdown.htmlNodesSafe (GFMarkdown.parseDocument source)).map HtmlModel.Node.erase)

end Markdown
