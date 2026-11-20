# island_editor

Flutter block editor used by the Solar Network clients (Solian, SolWatt).

Forked from [AppFlowy Editor](https://github.com/AppFlowy-IO/appflowy-editor)
6.2.0 and vendored in `socommon` so the editor can be patched in lockstep with
the clients that embed it. Code is dual-licensed AGPL-3.0 / MPL-2.0 (see
`LICENSE`); the fork keeps the same terms.

Import `package:island_editor/island_editor.dart`, and asset lookups pass
`package: 'island_editor'`. Public symbols are branded under the `Island*`
prefix (`IslandEditor`, `IslandRichText`, `IslandEditorLocalizations`,
`IslandClipboard`, etc.).

## Local changes over upstream

- **`MarkdownFallbackParserV2`** — the decoder stops at the first parser that
  returns nodes and silently dropped everything else, so a post containing a
  fenced code block, an HTML wrapper or an indented block loaded as an empty
  document and lost that text on the next save. The fallback keeps the content
  as paragraphs so it survives the round-trip.
- **`IslandKeyboardService.composingTextRange`** — exposes the range the
  platform IME owns. Hosts that rewrite text in place (Solar's inline-syntax
  normalization) need it: rewriting text under an active composition makes the
  next IME delta land at the wrong offset, which dropped the rest of a dictated
  utterance.
- Clipboard menus are wired by the host (`contextMenuBuilder` for desktop
  right-click, `MobileFloatingToolbar` + `toolbarBuilder` for mobile) — upstream
  renders nothing on either platform when they are omitted.

## Documentation

See the [upstream repository](https://src.solsynth.dev/SoSYS/Socommon/src/commit/f135d75c228ff7bfc597faea254f7f8696201a42/packages/island_editor)
for `documentation/` and `demo/`. This vendored copy contains runtime source,
assets and licenses; examples and upstream test projects are omitted.
The OHOS platform declaration is retained for the shared OH-Flutter runtime.
