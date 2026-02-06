use serde::{Deserialize, Serialize};
use std::collections::HashMap;

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(untagged)]
pub enum Step {
    Command(CommandStep),
    Wait(WaitStep),
    Group(GroupStep),
    Trigger(TriggerStep),
}

#[derive(Debug, Clone, Default, Serialize, Deserialize)]
pub struct CommandStep {
    #[serde(skip_serializing_if = "Option::is_none")]
    pub label: Option<String>,

    #[serde(skip_serializing_if = "Option::is_none")]
    pub command: Option<String>,

    #[serde(skip_serializing_if = "Option::is_none")]
    pub commands: Option<Vec<String>>,

    #[serde(skip_serializing_if = "Option::is_none")]
    pub env: Option<HashMap<String, String>>,

    #[serde(skip_serializing_if = "Option::is_none")]
    pub agents: Option<HashMap<String, String>>,

    #[serde(skip_serializing_if = "Option::is_none")]
    pub artifact_paths: Option<Vec<String>>,

    #[serde(skip_serializing_if = "Option::is_none")]
    pub plugins: Option<Vec<HashMap<String, serde_json::Value>>>,

    #[serde(skip_serializing_if = "Option::is_none")]
    pub key: Option<String>,

    #[serde(skip_serializing_if = "Option::is_none")]
    pub depends_on: Option<Vec<String>>,

    #[serde(skip_serializing_if = "Option::is_none")]
    pub timeout_in_minutes: Option<u32>,

    #[serde(skip_serializing_if = "Option::is_none")]
    pub retry: Option<RetryConfig>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct RetryConfig {
    #[serde(skip_serializing_if = "Option::is_none")]
    pub automatic: Option<Vec<AutomaticRetry>>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct AutomaticRetry {
    pub exit_status: String,
    pub limit: u32,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct WaitStep {
    pub wait: Option<String>,
}

impl Default for WaitStep {
    fn default() -> Self {
        Self { wait: Some("~".to_string()) }
    }
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct GroupStep {
    pub group: String,
    pub steps: Vec<Step>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct TriggerStep {
    pub trigger: String,

    #[serde(skip_serializing_if = "Option::is_none")]
    pub label: Option<String>,

    #[serde(skip_serializing_if = "Option::is_none")]
    pub build: Option<TriggerBuild>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct TriggerBuild {
    #[serde(skip_serializing_if = "Option::is_none")]
    pub message: Option<String>,

    #[serde(skip_serializing_if = "Option::is_none")]
    pub env: Option<HashMap<String, String>>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Pipeline {
    pub steps: Vec<Step>,
}

impl Pipeline {
    pub fn new() -> Self {
        Self { steps: Vec::new() }
    }

    pub fn add_step(&mut self, step: Step) {
        self.steps.push(step);
    }

    pub fn to_json(&self) -> Result<String, serde_json::Error> {
        serde_json::to_string_pretty(self)
    }
}

impl Default for Pipeline {
    fn default() -> Self {
        Self::new()
    }
}
