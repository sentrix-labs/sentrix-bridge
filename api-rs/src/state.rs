//! Shared application state — runtime config + parsed deployments + uptime
//! origin. Cheap to clone via `Arc`; axum hands every handler a reference.

use crate::config::RuntimeConfig;
use crate::deployments::Deployments;
use std::time::Instant;

#[derive(Debug)]
pub struct AppState {
    pub config: RuntimeConfig,
    pub deployments: Deployments,
    pub started_at: Instant,
}

impl AppState {
    pub fn new(config: RuntimeConfig, deployments: Deployments) -> Self {
        Self {
            config,
            deployments,
            started_at: Instant::now(),
        }
    }

    pub fn uptime_seconds(&self) -> u64 {
        self.started_at.elapsed().as_secs()
    }
}
