;; Tree-sitter Injection Queries for Luelte (.luelte) SFCs

;; Inject Lua Tree-sitter parser inside <script> blocks
((element
   (start_tag (tag_name) @_tag)
   (raw_text) @injection.content)
 (#eq? @_tag "script")
 (#set! injection.language "lua"))

;; Inject CSS Tree-sitter parser inside <style> blocks
((element
   (start_tag (tag_name) @_tag)
   (raw_text) @injection.content)
 (#eq? @_tag "style")
 (#set! injection.language "css"))

;; Inject Lua Tree-sitter parser inside attribute expression blocks
((attribute_value) @injection.content
 (#set! injection.language "lua"))
