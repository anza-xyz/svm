use std::{path::PathBuf, process::Command};

fn get_workspace_root() -> PathBuf {
    let output = Command::new("git")
        .args(["rev-parse", "--show-toplevel"])
        .output()
        .expect("Failed to get git root");
    let root = String::from_utf8(output.stdout).expect("Invalid UTF-8");
    PathBuf::from(root.trim())
}

#[test]
fn test_publish_order_json_output() {
    let workspace_root = get_workspace_root();
    let output = Command::new("cargo")
        .current_dir(&workspace_root)
        .args([
            "run",
            "--quiet",
            "--manifest-path",
            "ci/xtask/Cargo.toml",
            "--",
            "publish",
            "order",
            "--format",
            "json",
        ])
        .output()
        .expect("Failed to execute xtask");

    assert!(output.status.success());

    let json_output = String::from_utf8(output.stdout).expect("Invalid UTF-8");
    let data: Vec<Vec<serde_json::Value>> =
        serde_json::from_str(&json_output).expect("Invalid JSON");

    assert!(!data.is_empty(), "Should have at least one level");

    let total_crates: usize = data.iter().map(|level| level.len()).sum();
    assert!(
        total_crates > 0,
        "Should have at least one crate to publish"
    );
}

#[test]
fn test_publish_order_tree_output() {
    let workspace_root = get_workspace_root();
    let output = Command::new("cargo")
        .current_dir(&workspace_root)
        .args([
            "run",
            "--quiet",
            "--manifest-path",
            "ci/xtask/Cargo.toml",
            "--",
            "publish",
            "order",
            "--format",
            "tree",
        ])
        .output()
        .expect("Failed to execute xtask");

    assert!(output.status.success());

    let tree_output = String::from_utf8(output.stdout).expect("Invalid UTF-8");

    assert!(tree_output.contains("Total packages:"));
    assert!(tree_output.contains("Total levels:"));
    assert!(tree_output.contains("L1:"));
}

#[test]
fn test_no_circular_dependencies() {
    let workspace_root = get_workspace_root();
    let output = Command::new("cargo")
        .current_dir(&workspace_root)
        .args([
            "run",
            "--quiet",
            "--manifest-path",
            "ci/xtask/Cargo.toml",
            "--",
            "publish",
            "order",
            "--format",
            "json",
        ])
        .output()
        .expect("Failed to execute xtask");

    assert!(
        output.status.success(),
        "Command should succeed if no circular dependencies"
    );
}
