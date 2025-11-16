# Test Fixtures for sirena

This directory contains reference test fixtures generated from the official
mermaid-js implementation. These serve as "golden" outputs for regression
testing and validation of sirena's SVG generation capabilities.

## Directory Structure

Each diagram type has its own subdirectory containing:
- `input.mmd` - The original Mermaid diagram source
- `expected.svg` - The reference SVG output from mermaid-js

```
spec/fixtures/
├── flowchart/
│   ├── input.mmd
│   └── expected.svg
├── sequence/
│   ├── input.mmd
│   └── expected.svg
├── class_diagram/
│   ├── input.mmd
│   └── expected.svg
├── state_diagram/
│   ├── input.mmd
│   └── expected.svg
├── er_diagram/
│   ├── input.mmd
│   └── expected.svg
└── user_journey/
    ├── input.mmd
    └── expected.svg
```

## Purpose

These fixtures serve multiple purposes:

1. **Regression Testing**: Ensure sirena output stays consistent across
   code changes
2. **Validation**: Compare sirena generated SVG against official mermaid-js
   output
3. **Documentation**: Provide concrete examples of expected behavior for each
   diagram type
4. **Development**: Aid in debugging and feature development

## Source

The `expected.svg` files are generated using the official **mermaid-js CLI**
(`@mermaid-js/mermaid-cli`) from the example files in `examples/`. These
represent the canonical output format that sirena aims to replicate or
approximate.

### Original Source Files

The input `.mmd` files are copied from:
- `examples/flowchart_example.mmd`
- `examples/sequence_example.mmd`
- `examples/class_diagram_example.mmd`
- `examples/state_diagram_example.mmd`
- `examples/er_diagram_example.mmd`
- `examples/user_journey_example.mmd`

### Generation Process

The `expected.svg` files in this directory are generated using the official
mermaid-js CLI tool. This ensures that our fixtures represent authentic
mermaid-js output for comparison and validation.

**Requirements:**

* Node.js and npm installed
* `@mermaid-js/mermaid-cli` package

**Installation:**

```bash
npm install -g @mermaid-js/mermaid-cli
```

**To regenerate all reference fixtures:**

```bash
bundle exec rake fixtures:generate_from_mermaidjs
```

This Rake task:

1. Reads each `.mmd` file from `examples/`
2. Runs `mmdc -i input.mmd -o expected.svg` for each diagram type
3. Saves the mermaid-js-generated SVG to `spec/fixtures/{type}/expected.svg`

## Usage in Tests

These fixtures can be used in RSpec tests to validate output:

```ruby
RSpec.describe Sirena::Engine do
  describe "flowchart rendering" do
    let(:input) { File.read("spec/fixtures/flowchart/input.mmd") }
    let(:expected_svg) { File.read("spec/fixtures/flowchart/expected.svg") }

    it "generates structurally similar SVG to mermaid-js" do
      actual_svg = Sirena::Engine.new.render(input)

      # Compare structure, not exact match due to implementation differences
      expect(actual_svg).to include("<svg")
      expect(actual_svg).to include("</svg>")
      # Add more assertions based on your validation needs
    end
  end
end
```

## Validation Approach

When comparing sirena output to these reference fixtures, consider:

1. **Structural Comparison**: Focus on SVG element structure rather than
   exact string matching
2. **Semantic Equivalence**: Ensure the visual meaning is preserved even if
   implementation details differ
3. **Coordinate Flexibility**: Allow for slight differences in positioning
   and dimensions
4. **Style Variations**: Account for possible CSS or style differences

## Maintaining Fixtures

### When to Update

Update fixtures when:
- mermaid-js output format changes significantly
- New diagram features are added to the examples
- Reference implementation is updated to a new major version
- Testing reveals discrepancies between sirena and mermaid-js output

### How to Update

To regenerate reference fixtures from mermaid-js:

1. Ensure mermaid-js CLI is installed:
   ```bash
   npm install -g @mermaid-js/mermaid-cli
   ```

2. Run the fixture generation task:
   ```bash
   bundle exec rake fixtures:generate_from_mermaidjs
   ```

3. Review the generated SVG files for correctness:
   ```bash
   ls -lh spec/fixtures/*/expected.svg
   ```

4. Run tests to ensure compatibility:
   ```bash
   bundle exec rspec spec/fixtures_spec.rb
   ```

5. Commit the updated fixtures if tests pass

**Note:** The fixtures are generated automatically by the Rake task using the
official mermaid-js implementation, ensuring consistency and accuracy.

## See Also

- `examples/README.md` - Example diagrams and generation scripts
- `spec/integration/` - Integration tests using these fixtures
- `ARCHITECTURE.md` - Overall sirena architecture