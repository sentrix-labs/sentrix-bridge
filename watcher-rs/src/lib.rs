//! sentrix-bridge-watcher
//!
//! Read-only watcher for the sentrix-bridge Hyperlane v3 deployment.
//!
//! Loads `deployments/*.json`, walks every Mailbox + warp-route contract, and
//! reports on:
//!
//! * RPC liveness (Sentrix + Sepolia eth_blockNumber + eth_chainId)
//! * NoopIsm wiring (`unsafe_demo` flag overrides the warning)
//! * MultisigIsm validator-set + threshold (when an ISM exposes
//!   `validatorsAndThreshold`)
//! * Mailbox `localDomain` / `defaultIsm` / `defaultHook`
//! * wSRX 1:1 invariant — `WSRX.totalSupply()` and the collateral
//!   `balanceOf(WSRX_address)` on Sentrix should equal HypERC20
//!   `totalSupply()` on Sepolia
//! * Stuck `Dispatch` events on the origin Mailbox without a matching
//!   `ProcessId` on the destination Mailbox in the last N blocks
//!
//! No private keys, no signing — just `eth_call` and event scans.

pub mod checks;
pub mod config;
pub mod report;

pub use config::{Network, RuntimeConfig};
pub use report::{
    InvariantStatus, Report, RouteReport, RpcReport, StuckCheck, StuckMessage, WsrxInvariant,
};
