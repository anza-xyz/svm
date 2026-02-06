pub mod buildkite;

use {
    anyhow::Result,
    buildkite::{CommandStep, Pipeline, Step, WaitStep},
    clap::Args,
    std::{fs, path::PathBuf},
};

#[derive(Args)]
pub struct CommandArgs {
    #[arg(long, short, default_value = "pipeline.json")]
    pub output_file: PathBuf,

    #[arg(long)]
    pub crate_name: Option<String>,
}

pub async fn run(args: CommandArgs) -> Result<()> {
    let pipeline = if let Some(crate_name) = args.crate_name {
        generate_crate_release_pipeline(&crate_name)?
    } else {
        generate_full_release_pipeline()?
    };

    let json = pipeline.to_json()?;
    fs::write(&args.output_file, json)?;

    println!("✓ Generated pipeline: {}", args.output_file.display());

    Ok(())
}

fn generate_crate_release_pipeline(crate_name: &str) -> Result<Pipeline> {
    let mut pipeline = Pipeline::new();

    pipeline.add_step(Step::Command(CommandStep {
        label: Some(format!(":rust: Validate release - {crate_name}")),
        command: Some(format!(
            "cargo xtask release validate --crate {crate_name} --ref $BUILDKITE_COMMIT --output metadata.json"
        )),
        artifact_paths: Some(vec!["metadata.json".to_string()]),
        ..Default::default()
    }));

    pipeline.add_step(Step::Command(CommandStep {
        label: Some(format!(":hammer: Build and test - {crate_name}")),
        command: Some(format!(
            "cargo build --release -p {crate_name} && cargo test -p {crate_name}"
        )),
        ..Default::default()
    }));

    pipeline.add_step(Step::Wait(WaitStep::default()));

    pipeline.add_step(Step::Command(CommandStep {
        label: Some(":github: Trigger GitHub Actions".to_string()),
        command: Some(
            "buildkite-agent artifact download metadata.json . && cargo xtask release trigger-github --metadata metadata.json"
                .to_string(),
        ),
        ..Default::default()
    }));

    Ok(pipeline)
}

fn generate_full_release_pipeline() -> Result<Pipeline> {
    let mut pipeline = Pipeline::new();

    pipeline.add_step(Step::Command(CommandStep {
        label: Some(":clipboard: Validate workspace".to_string()),
        command: Some("cargo xtask publish order --format tree".to_string()),
        ..Default::default()
    }));

    pipeline.add_step(Step::Command(CommandStep {
        label: Some(":mag: Check versions".to_string()),
        command: Some("echo 'Version validation will be implemented in release validate command'".to_string()),
        ..Default::default()
    }));

    pipeline.add_step(Step::Wait(WaitStep::default()));

    pipeline.add_step(Step::Command(CommandStep {
        label: Some(":rocket: Ready for release".to_string()),
        command: Some("echo 'Pipeline ready. Use trigger-github command to start release.'".to_string()),
        ..Default::default()
    }));

    Ok(pipeline)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_generate_crate_pipeline() {
        let pipeline = generate_crate_release_pipeline("solana-svm").unwrap();
        assert_eq!(pipeline.steps.len(), 4);
    }

    #[test]
    fn test_generate_full_pipeline() {
        let pipeline = generate_full_release_pipeline().unwrap();
        assert!(!pipeline.steps.is_empty());
    }

    #[test]
    fn test_pipeline_serialization() {
        let pipeline = generate_crate_release_pipeline("test-crate").unwrap();
        let json = pipeline.to_json().unwrap();
        assert!(json.contains("test-crate"));
        assert!(json.contains("steps"));
    }
}
