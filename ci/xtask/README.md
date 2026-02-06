# XTask - SVM Build and Release Automation

Build and release automation tasks for the SVM (Solana Virtual Machine) workspace.

## Installation

From the SVM repository root:

```bash
cargo build --manifest-path ci/xtask/Cargo.toml
```

## Usage

### Publish Order

Compute the dependency-ordered list of crates for publishing to crates.io.

**JSON format** (for CI/scripting):
```bash
cargo xtask publish order --format json
```

Output example:
```json
[
  [
    {"name":"solana-svm-callback","path":"callback","dependencies":[]},
    {"name":"solana-svm-feature-set","path":"feature-set","dependencies":[]}
  ],
  [
    {"name":"solana-program-runtime","path":"program-runtime","dependencies":["..."]}
  ]
]
```

**Tree format** (for humans):
```bash
cargo xtask publish order --format tree
```

Output example:
```
📦 Total packages: 15
🌳 Total levels: 5

L1: (8 package(s))
  solana-svm-callback
  solana-svm-feature-set
  ...

L2: (1 package(s))
  solana-program-runtime
    L1: ["solana-svm-timings", "solana-svm-callback", ...]
```

### Generate Pipeline

Generate Buildkite pipeline JSON for release workflows.

**Full workspace pipeline**:
```bash
cargo xtask generate-pipeline --output-file pipeline.json
```

**Crate-specific release pipeline**:
```bash
cargo xtask generate-pipeline --crate-name solana-svm --output-file svm-pipeline.json
```

Output example:
```json
{
  "steps": [
    {
      "label": ":rust: Validate release - solana-svm",
      "command": "cargo xtask release validate --crate solana-svm --ref $BUILDKITE_COMMIT --output metadata.json",
      "artifact_paths": ["metadata.json"]
    },
    {
      "label": ":hammer: Build and test - solana-svm",
      "command": "cargo build --release -p solana-svm && cargo test -p solana-svm"
    },
    {
      "wait": "~"
    },
    {
      "label": ":github: Trigger GitHub Actions",
      "command": "buildkite-agent artifact download metadata.json . && cargo xtask release trigger-github --metadata metadata.json"
    }
  ]
}
```

## Features

- **Dependency Analysis**: Computes topological ordering of workspace crates
- **Circular Dependency Detection**: Validates no circular dependencies exist
- **Publish Filter**: Automatically excludes crates with `publish = false`
- **Multiple Output Formats**: JSON for automation, tree for visualization
- **Pipeline Generation**: Creates Buildkite pipeline JSON for release automation
- **Flexible Pipeline Templates**: Supports full workspace or crate-specific pipelines

## Testing

Run the test suite:

```bash
cargo test --manifest-path ci/xtask/Cargo.toml
```
