# Project Summary: Luex Ecosystem (Luelte, Luact, Lue & Luex)

## 1. Concept and Vision
Luex is an Ahead-Of-Time (AOT) framework and compiler ecosystem for Neovim introducing Single File Component (SFC) architecture. It supports quad-paradigm component flavors: **Luelte** (Svelte-style `.luelte` files), **Luact** (React-style `.luact` files), **Lue** (Vue 3-style `.lue` files), and **Luex** (Pure Native Neovim Lua Table DSL `.luex` files), transpiling all four into pure, zero-overhead Lua modules with universal cross-framework interoperability.

## 2. Official Nomenclature
- **Luex**: Overarching ecosystem, core runtime framework (`luex.lua` / `require("luex")`), and Native Neovim Component flavor (`.luex` extension). Provides Svelte Runes (`$state`, `$derived`, `$effect`, `$props`), React Hooks (`useState`, `useEffect`, `useMemo`, `useRef`, `useCallback`), Vue Composition API (`ref`, `reactive`, `computed`, `watch`, `onMounted`), and Native Table DSL (`luex.component`, `luex.signal`, `luex.import`).
- **Luelte**: Svelte-flavor SFC engine (`.luelte` extension) using Svelte 5 Runes mental model.
- **Luact**: React-flavor SFC engine (`.luact` / `.lt` extension) using React Functional Components & Hooks mental model.
- **Lue**: Vue 3-flavor SFC engine (`.lue` extension) using Vue 3 Composition API `<script setup>` & `<template>` mental model.
- **Luexc**: AOT Compiler / Transpiler engine (`compiler.lua`). Transforms `.luelte`, `.luact`, `.lue`, and `.luex` files into pure Lua modules.
- **LuelteKit**: Meta-framework / Neovim plugin orchestrator (`lueltekit.nvim`). Handles hot-reload auto-compilation (`BufWritePost`) and `lazy.nvim` integration.
- **File Extensions**: `.luelte` (Svelte SFC flavor), `.luact` / `.lt` (React SFC flavor), `.lue` (Vue SFC flavor), `.luex` (Native Neovim Lua Table DSL flavor).

## 3. Strict Project Rules
1. **Isolated Environment Rule**:
   - This directory is a fully isolated Neovim environment using `./nvim` as `XDG_CONFIG_HOME` and `./nvim-data` as `XDG_DATA_HOME`.
   - To execute or test Neovim, **ALWAYS USE `nvim.ps1`** (e.g., `powershell -ExecutionPolicy Bypass -File .\nvim.ps1 ...`).
   - **NEVER** run plain `nvim` directly or touch the default system configuration (`~/.config/nvim` or `%LOCALAPPDATA%\nvim`).

2. **English Only Rule**:
   - All code, comments, documentation, UI texts, console output, log messages, and error messages MUST be written strictly in **English**. No Spanglish or Spanish allowed in `.luelte`, `.luact`, `.lue`, `.luex`, or anywhere in the codebase.

3. **Engine Local Hot-Update & Global Config Protection Rule**:
   - After making any change or update to the Luex core engine (`luex/core`), **ALWAYS** execute the project root installer (`powershell -ExecutionPolicy Bypass -File .\install.ps1`) to hot-update and sync the core into `./nvim/.luelte/core` within `./nvim-learning`.
   - The user's global Neovim configuration (`%LOCALAPPDATA%\nvim` or `~/.config/nvim`) **MAY BE INSPECTED READ-ONLY** as an authoritative reference guide for IDE features and setup. Modifying or writing to global Neovim configuration is **STRICTLY FORBIDDEN**.

4. **Mandatory Testing & Verification Rule**:
   - Whenever adding new features, refactoring logic, or modifying Luex core engine components, **ALWAYS** write comprehensive automated test specs in `luex/tests/`.
   - **ALWAYS** execute the full automated test suite (`powershell -ExecutionPolicy Bypass -File .\nvim.ps1 --headless -c "luafile luex/run_tests.lua" -c "qall!"`) after making any modifications in Luex to ensure 0 regressions before completing a task.

5. **No AI Co-Author Rule**:
   - Git commits MUST NEVER include AI as co-author (no `Co-authored-by: AI ...`, `Co-authored-by: Antigravity ...`, or similar commit message trailers).

## 4. File Architecture (Modular & Clean)
```
luex/                             # 📦 Public GitHub Repository & Luex Distribution Package
├── .gitignore                    # Git ignore rule (ignores nvim/ and nvim-data/ test sandbox)
├── install.ps1                   # Windows PowerShell installer script
├── install.sh                    # Linux/macOS Bash installer script
├── nvim.ps1                       # Windows isolated test Neovim launcher
├── nvim.sh                       # Linux/macOS isolated test Neovim launcher
├── run_tests.lua                 # Headless Neovim test suite runner script
├── run_installation_test.lua     # Standalone integration test script (wipes sandbox, deploys core & verifies)
├── core/                         # Core Luex Framework Engine
│   ├── init.lua                  # Framework bootstrap & lazy/mason orchestrator
│   ├── luex.lua                  # Core Luex framework entrypoint (require("luex"))
│   ├── luex_lsp.lua              # 100% Pure Lua Hybrid LSP Multiplexer & Extension Dispatch
│   ├── compiler.lua              # AOT Transpiler (Lueltec engine)
│   ├── runtime.lua               # UI Runtime Engine (Runes, Hooks & Composition API)
│   ├── builder.lua               # Batch compilation manager
│   ├── luex/                     # Namespace sub-modules
│   │   └── testing.lua           # BDD/TDD Testing Framework (require("luex.testing"))
│   └── syntax/                   # Neovim editor integration (ftdetect, syntax & treesitter queries)
│       ├── ftdetect/             # Filetype detection rules (.luelte, .luact, .lue, .luex)
│       ├── syntax/               # Vim syntax highlighting engines (luelte.vim, luact.vim, lue.vim, luex.vim)
│       └── queries/              # Tree-sitter Scheme Injections (luelte, luact, lue, luex)
└── tests/                        # 🧪 Automated Integration & Unit Test Specs
    ├── integration/              # 🔄 End-to-End Fresh Installation & Component Deployment Specs
    │   └── test_installation.lua
    ├── interop/                  # 🔗 Quad-Paradigm Interoperability Specs
    │   └── test_tri_directional_interop.lua
    ├── paradigms/                # 💎 SFC Paradigms, PropTypes, Directives & LSP Specs
    │   ├── test_sfc_paradigms.lua
    │   ├── test_luex_lsp.lua
    │   ├── test_paradigm_security_guard.lua
    │   └── test_all_flavors_hotreload.lua
    └── mocks/                    # 🎭 Mock SFC Component Files (.luelte, .luact, .lue, .luex)
        ├── app.luelte
        ├── languages.luelte
        └── components/

install.ps1                       # Windows fast installer script (deploys luex/core into ./nvim/.luelte/core)
install.sh                        # Linux/macOS fast installer script (deploys luex/core into ./nvim/.luelte/core)
nvim.ps1                          # Windows isolated test Neovim launcher

nvim/                             # 💻 User / Installed Neovim environment
├── init.lua                      # Minimal client bootstrap entrypoint
│
├── src/                          # 🛠️ Editable SFC source files (.luelte, .luact, .lue, .luex)
│   ├── app.luelte                # Global options and base configuration
│   ├── languages.luelte          # Language packs (<pack lang="..." />)
│   └── components/               # Visual SFC components
│       ├── counter.luelte        # Svelte 5 Runes ($state, $derived) component
│       ├── dashboard.luelte      # Hybrid Control Panel (<GitDashboard /> import)
│       ├── git_dashboard.luact   # React-style Git Dashboard (useState, useEffect)
│       ├── react_counter.luact   # React-style Counter (useState, useMemo)
│       ├── react_modal.luact     # React component embedding Svelte <HelloModal />
│       ├── vue_counter.lue       # Vue 3 Composition API Counter (ref, computed)
│       ├── hybrid_hub.lue        # Tri-Directional Component embedding Svelte & React
│       ├── native_hub.luex       # Quad-Directional Native Neovim Table DSL Component
│       └── hello_modal.luelte    # Startup Hello World modal
│
└── .luelte/                      # 📦 Installed Framework & Compiled AOT Output
    ├── core/                     # Installed Framework Engine (deployed by luex/install.ps1)
    └── dist/                     # Compiled Native Lua Output (Git-tracked)
        ├── manifest.lua          # Auto-assembled catalog for lazy.nvim
        ├── app.lua               # Compiled app configuration
        ├── languages.lua         # Compiled language packs
        └── components/           # Compiled component Lua modules
```

## 5. Technical Decisions
- **Tri-Paradigm Ecosystem Architecture**:
  - **Luex**: Core ecosystem runtime (`require("luex")`).
  - **Luelte**: Svelte-flavor `.luelte` components using Svelte 5 Runes (`$state`, `$derived`, `$effect`, `$props`).
  - **Luact**: React-flavor `.luact` components using React Hooks (`useState`, `useEffect`, `useMemo`, `useRef`, `useCallback`).
  - **Lue**: Vue-flavor `.lue` components using Vue 3 Composition API (`ref`, `reactive`, `computed`, `watch`, `onMounted`).
- **Transpiler Paradigm Guard Security (`compiler.lua`)**:
  - Enforces strict paradigm boundaries at compile-time across all SFC extensions.
  - Calling React Hooks (`useState()`) directly in `.luelte` or `.lue` logic, or calling Svelte Runes (`$state()`) directly in `.luact` or `.lue` logic triggers an instant compile-time error (`[Luex Security Guard] Paradigm Violation`).
  - *Universal Interoperability Preserved*: Rendering imported cross-framework components (`<ReactComponent />` or `<VueComponent />`) inside `.luelte` remains 100% valid and supported.
- **Hot-Swappable Component Triggers & Keymaps (`init.lua`)**:
  - Hotkey and command changes in SFC `<script keys="..." cmd="...">` blocks are dynamically hot-swapped on save (`BufWritePost`).
  - Automatically unbinds old keymaps (`vim.keymap.del`) and old user commands, binding new triggers seamlessly without restarting Neovim.
- **React Functional Component Scope Un-wrapping & Keymap Guard (`compiler.lua` & `runtime.lua`)**:
  - Unwraps outer `function ReactComponent(props)` blocks during `.luact` compilation so state handlers (`increment`, `decrement`) remain in local closure scope for `on:key:i` and `on:key:d` keymap bindings.
  - Added action validation guard in `runtime.lua` so `nil` or unhandled keymap actions never hijack buffer keypresses.
- **100% Pure Lua Hybrid LSP (`luex_lsp.lua`)**:
  - Zero external JavaScript, Node.js, or build dependencies.
  - **Extension-Based Fast Flavor Dispatch**: Instantly branches parsing rules by extension (`.luelte` $\to$ Svelte Runes, `.luact` $\to$ React Hooks, `.lue` $\to$ Vue Composition, `.luex` $\to$ Native Table DSL).
  - **Live Mason Registry Sync**: Queries `mason-registry` dynamically to show package availability, installation status, and deprecation warnings (`Mason LSP [Installed | ⚠️ DEPRECATED]`).
- **Tree-sitter Scheme Injections (`queries/`)**:
  - Uses native `.scm` injection queries (`queries/{luelte,luact,lue,luex}/injections.scm`) to embed standard `lua` Tree-sitter parsers inside `<script>` blocks and attribute expressions, and `css` parsers inside `<style>` blocks.
- **Declarative SFC Language Packs & Mason Cleanup (`<pack ... />`)**:
  - Components declare language tooling using `<pack lang="..." lsp="..." formatter="..." linter="..." />`.
  - **`:LueltePackSync`**: Automatically detects and uninstalls orphaned Mason packages when `<pack>` directives are removed from SFC source files.
- **Default Package Manager & Caret Autocompletion**:
  - `lazy.nvim` and `mason.nvim` are bootstrapped automatically.
  - `nvim-cmp` is preconfigured with `<Ctrl-Space>` mapping to trigger caret IntelliSense instantly.
- **LuaJIT Super-Optimizations**:
  - *Zero GC Table Reuse*: `lines`, `highlights`, `keymaps` tables are reused on re-renders for zero GC pressure.
  - *Direct Array Indexing*: Replaces `table.insert` C-calls with native array index assignments (`lines[l_cnt] = ...`).
  - *Compile-Time Constant Folding*: Static text line lengths and highlight ranges are calculated at compile time.

## 6. Execution Flow & Tooling
- **Engine Deployment / Installation**:
  - Fast Root Launcher (Demo Client `.\nvim`):
    - Windows:
      ```powershell
      powershell -ExecutionPolicy Bypass -File .\install.ps1
      ```
    - Linux/macOS:
      ```bash
      chmod +x ./install.sh && ./install.sh
      ```
  - Custom Neovim Directory Installation:
    - Windows:
      ```powershell
      powershell -ExecutionPolicy Bypass -File .\luex\install.ps1 -TargetDir "C:\path\to\nvim"
      ```
    - Linux/macOS:
      ```bash
      ./luex/install.sh /path/to/nvim
      ```
- **CLI / Headless Batch Compilation**:
  ```powershell
  powershell -ExecutionPolicy Bypass -File .\nvim.ps1 --headless -c "lua require('builder')" -c "qall!"
  ```
- **Hot Reload**: Automatic `BufWritePost *.luelte,*.luact,*.lue,*.luex` autocmd transpiles saved files instantly.
- **Automated Test Runner**:
  ```powershell
  powershell -ExecutionPolicy Bypass -File .\nvim.ps1 --headless -c "luafile luex/run_tests.lua" -c "qall!"
  ```
- **End-to-End Installation Integration Test**:
  ```powershell
  powershell -ExecutionPolicy Bypass -File .\luex\nvim.ps1 --headless -c "luafile luex/run_installation_test.lua" -c "qall!"
  ```

## 7. Development Status & Milestone Progress
- [x] Isolated environment rule documented (`nvim.ps1`).
- [x] English-only strict codebase rule enforced.
- [x] Directive analyzer in `compiler.lua` for `<pack lang="..." lsp="..." formatter="..." linter="..." />` and automatic generation of `.luelte/dist/manifest.lua`.
- [x] Default package manager integration (`lazy.nvim`) bootstrapped in Luex core engine (`init.lua`).
- [x] `.luelte` language pack auto-installation registration for LSPs, formatters, and linters.
- [x] Template control flow support (`{#if condition}`, `{:else}`, `{/if}` and `{#each list as item, index}`).
- [x] Event binding support (`on:select`, `on:key`).
- [x] Dynamic percentage and fixed window dimension resolver in `runtime.lua`.
- [x] Modular AOT batch build manager `builder.lua`.
- [x] `BufWritePost *.luelte,*.luact,*.lue,*.luex` hot-reload autocmd in `.luelte/core/init.lua`.
- [x] Neovim filetype detection and syntax highlighting rules in `.luelte/core/syntax` for all quad-paradigm SFC extensions (`.luelte`, `.luact`, `.lue`, `.luex`).
- [x] Component import and nesting composition engine in `compiler.lua` (`<import ... />` tag & `<ChildComponent />` tag).
- [x] Standard JS/TS/Lua component import syntax (`import ComponentName from "components.path"`).
- [x] Core testing framework (`.luelte/core/luex/testing.lua` / `require("luex.testing")`) with `describe`, `it`, `expect`, and `render_component`.
- [x] Svelte 5 Runes reactive state engine (`$state`, `$derived`, `$effect`, `$props`).
- [x] React-style SFC support (`.luact` / `.lt` extension) with React Hooks (`useState`, `useEffect`, `useMemo`, `useRef`, `useCallback`).
- [x] Vue 3-style SFC support (`.lue` extension) with Vue Composition API (`ref`, `reactive`, `computed`, `watch`, `onMounted`, `onUnmounted`).
- [x] Tri-Directional Universal Interoperability (`.luelte` $\leftrightarrow$ `.luact` $\leftrightarrow$ `.lue`).
- [x] Automated test suite verifying 3-way component compilation and cross-framework nesting (`test_tri_directional_interop.lua` & `test_sfc_paradigms.lua`).
- [x] 100% Pure Lua Hybrid Language Server (`luex_lsp.lua`) with Extension-Based Fast Flavor Dispatch.
- [x] Tree-sitter Scheme Injections (`queries/`) embedding `lua` and `css` parsers.
- [x] Dynamic Mason Registry synchronization and `:LueltePackSync` orphaned package cleanup.
- [x] Caret IntelliSense autocompletion (`<Ctrl-Space>`) via `nvim-cmp`.
- [x] Full Vim syntax & Tree-sitter auto-start for all 4 SFC flavors (`.luelte`, `.luact`, `.lue`, `.luex`).
- [x] LuaJIT super-optimizations (zero-allocation table reuse, direct array indexing, constant folding).
- [x] Proof of Concept fully verified and functional.
