//! Verify the Report JSON shape stays stable. Downstream `api-rs` consumers
//! grep on these field names, so this guards against accidental rename.

use chrono::Utc;
use sentrix_bridge_watcher::report::{
    InvariantStatus, MailboxReport, MultisigInfo, Report, RouteReport, RpcReport, StuckCheck,
    StuckMessage, WsrxInvariant,
};

#[test]
fn report_serializes_with_expected_top_level_keys() {
    let report = Report {
        timestamp: Utc::now(),
        network: "testnet".into(),
        sentrix_rpc: RpcReport {
            url: "https://testnet-rpc.sentrixchain.com".into(),
            ok: true,
            block: Some(3_787_001),
            chain_id: Some(7120),
            error: None,
        },
        sepolia_rpc: RpcReport {
            url: "https://ethereum-sepolia-rpc.publicnode.com".into(),
            ok: true,
            block: Some(10_844_500),
            chain_id: Some(11155111),
            error: None,
        },
        mailboxes: vec![MailboxReport {
            label: "sentrix-testnet-mailbox".into(),
            address: "0x9741D99270aF14D4baca0e387B6ac0500b9a288F".into(),
            chain_id: 7120,
            local_domain: Some(7120),
            default_ism: Some("0x28834aa535f3130f0f60571ac7a813195ae56ec6".into()),
            default_hook: Some("0x6a192c8fea612ca3aa204035e51f6a624b0f1467".into()),
            local_domain_matches: Some(true),
            error: None,
        }],
        routes: vec![RouteReport {
            id: "warp-wsrx-sentrix-to-sepolia".into(),
            source_chain: 7120,
            destination_chain: 11155111,
            source_contract: "0xfb8190927034c447Fc29B1cfbF4f4F000969bb32".into(),
            destination_contract: "0xC4BDE56bCAadfDbD6fBad685b65628f05994e5a8".into(),
            ism_address: Some("0x28834aa535f3130f0f60571ac7a813195ae56ec6".into()),
            ism_type: "NoopIsm".into(),
            multisig: Some(MultisigInfo {
                validator_count: 0,
                threshold: 0,
                validators: vec![],
            }),
            unsafe_demo: false,
            unsafe_flags: vec!["NoopIsm-on-warp-route-unsafe".into()],
            error: None,
        }],
        wsrx_invariant: Some(WsrxInvariant {
            wsrx_total_supply_sentrix: "1000000000000000".into(),
            wsrx_locked_in_collateral: "1000000000000000".into(),
            hyperc20_total_supply_sepolia: "1000000000000000".into(),
            drift_wei: "0".into(),
            status: InvariantStatus::Ok,
            ok: true,
            error: None,
        }),
        stuck_messages: vec![StuckMessage {
            origin_chain: 7120,
            destination_chain: 11155111,
            message_id: "0xabc".into(),
            origin_tx: "0xdef".into(),
            origin_block: 3_787_000,
            age_blocks: 100,
        }],
        stuck: StuckCheck::Scanned {
            messages: vec![StuckMessage {
                origin_chain: 7120,
                destination_chain: 11155111,
                message_id: "0xabc".into(),
                origin_tx: "0xdef".into(),
                origin_block: 3_787_000,
                age_blocks: 100,
            }],
        },
        warnings: vec!["warp-wsrx-sentrix-to-sepolia: NoopIsm-on-warp-route-unsafe".into()],
    };

    let json = serde_json::to_value(&report).expect("serialize report");
    let obj = json.as_object().expect("report is object");
    for key in [
        "timestamp",
        "network",
        "sentrix_rpc",
        "sepolia_rpc",
        "mailboxes",
        "routes",
        "wsrx_invariant",
        "stuck_messages",
        "stuck",
        "warnings",
    ] {
        assert!(obj.contains_key(key), "missing top-level key: {key}");
    }
    // `stuck` is a tagged enum: { "kind": "scanned"|"skipped", ... }.
    let stuck = json["stuck"].as_object().unwrap();
    assert_eq!(stuck["kind"], "scanned");
    assert!(stuck.contains_key("messages"));

    let route = json["routes"][0].as_object().unwrap();
    for key in [
        "id",
        "source_chain",
        "destination_chain",
        "ism_address",
        "ism_type",
        "unsafe_demo",
        "unsafe_flags",
    ] {
        assert!(route.contains_key(key), "route missing key: {key}");
    }

    let inv = json["wsrx_invariant"].as_object().unwrap();
    for key in [
        "wsrx_locked_in_collateral",
        "hyperc20_total_supply_sepolia",
        "drift_wei",
        "ok",
        "status",
    ] {
        assert!(inv.contains_key(key), "invariant missing key: {key}");
    }
    assert_eq!(inv["status"], "ok");
}
