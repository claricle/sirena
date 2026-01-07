# Sirena Examples

This directory contains example diagrams for all supported diagram types.

## Structure

Each diagram type has its own directory with:
- `*.mmd` - Mermaid source files
- `*.yml` - Metadata for each example
- `generated/` - Auto-generated SVG files (git-ignored)

## Usage

```bash
# Generate all SVGs
rake examples:generate

# Create a new example
rake examples:create[flowchart,my-example]

# Validate all examples
rake examples:validate

# List all examples
rake examples:list

# Build everything (generate + docs + copy)
rake examples:build
```

## Adding Examples

1. Create example files:
   ```bash
   rake examples:create[type,name]
   ```

2. Edit the `.mmd` and `.yml` files

3. Generate SVG:
   ```bash
   rake examples:generate
   ```

4. Build documentation:
   ```bash
   rake examples:build
   ```

## Example Metadata

Each `.yml` file should contain:

```yaml
title: "Example Title"
description: "What this example demonstrates"
complexity: basic  # basic, intermediate, advanced
keywords:
  - keyword1
  - keyword2
use_cases:
  - "Use case description"
theme: default  # default, dark, light, high-contrast
```
