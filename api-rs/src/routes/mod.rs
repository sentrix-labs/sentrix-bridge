//! Route handlers. One module per endpoint to keep diffs small.
//!
//! `routes_endpoint` is the `/routes` handler — named with the `_endpoint`
//! suffix to avoid colliding with this `routes` module path.

pub mod fresh_user_flow;
pub mod health;
pub mod messages;
pub mod readiness;
pub mod routes_endpoint;
pub mod status;
pub mod unsafe_config;
