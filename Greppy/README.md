# Greppy

A very small clon of `grep` command with 0 dependencies.

## Usage

You can pipe text into `greppy` or redirect files to search for specific patterns (text).

```bash
# In this repo: Dev mode
cat "test.txt" | cargo run -- <pattern> [options]

# Once compiled with `cargo build --release`
cat "test.txt" | greppy <pattern> [options]
```

### Pattern

```md
Any "text" | "pattern" you'd like to look for from the piped text
```

### Options

```md
--i: For a case insensitive search
```

# Notes:

This is just a toy proyect, made to learn rust from 0. This is my first rust program btw.
