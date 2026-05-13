# Chainlist PR Data — Ready to Submit

Repo: `github.com/ethereum-lists/chains`
Path: PRs add JSON files at `_data/chains/eip155-<chainId>.json`

## Mainnet — `_data/chains/eip155-7119.json`

```json
{
  "name": "Sentrix Chain",
  "chain": "Sentrix",
  "title": "Sentrix Chain Mainnet",
  "rpc": [
    "https://rpc.sentrixchain.com"
  ],
  "faucets": [],
  "nativeCurrency": {
    "name": "Sentrix",
    "symbol": "SRX",
    "decimals": 18
  },
  "infoURL": "https://sentrixchain.com",
  "shortName": "sentrix",
  "chainId": 7119,
  "networkId": 7119,
  "icon": "sentrix",
  "explorers": [
    {
      "name": "Sentrix Explorer",
      "url": "https://scan.sentrixchain.com",
      "icon": "sentrix",
      "standard": "EIP3091"
    }
  ]
}
```

## Testnet — `_data/chains/eip155-7120.json`

```json
{
  "name": "Sentrix Testnet",
  "chain": "Sentrix",
  "title": "Sentrix Chain Testnet",
  "rpc": [
    "https://testnet-rpc.sentrixchain.com"
  ],
  "faucets": [
    "https://faucet.sentrixchain.com"
  ],
  "nativeCurrency": {
    "name": "Sentrix",
    "symbol": "SRX",
    "decimals": 18
  },
  "infoURL": "https://sentrixchain.com",
  "shortName": "sentrix-test",
  "chainId": 7120,
  "networkId": 7120,
  "icon": "sentrix",
  "explorers": [
    {
      "name": "Sentrix Testnet Explorer",
      "url": "https://testnet-scan.sentrixchain.com",
      "icon": "sentrix",
      "standard": "EIP3091"
    }
  ],
  "parent": {
    "type": "L1",
    "chain": "eip155-7119"
  }
}
```

## Icon — `_data/icons/sentrix.json`

Submit a PR that also includes the chain icon. Chainlist needs an IPFS-pinned SVG/PNG of the brand mark.

```json
[
  {
    "url": "ipfs://<CID-after-upload>",
    "width": 512,
    "height": 512,
    "format": "png"
  }
]
```

Source: `github.com/sentrix-labs/brand-kit` has the logo as SVG. Convert to 512×512 PNG, upload to IPFS (Pinata / web3.storage / NFT.Storage), get CID, paste into the JSON above.

## Pre-submit checks

Verified 2026-05-12 against chain state:

```
$ curl -s -X POST https://rpc.sentrixchain.com -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","method":"eth_chainId","params":[],"id":1}' | jq -r .result
# 0x1bcf  (decimal 7119) ✓

$ curl -s -X POST https://testnet-rpc.sentrixchain.com -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","method":"eth_chainId","params":[],"id":1}' | jq -r .result
# 0x1bd0  (decimal 7120) ✓
```

EIP-3091 (block explorer URL scheme) confirmed compliant for `scan.sentrixchain.com` since 2026-04-30 per the chain operator's status notes.

## Submission steps

1. Fork `github.com/ethereum-lists/chains`
2. Add the two JSON files above + the icon metadata
3. Upload icon to IPFS, capture CID, paste into `_data/icons/sentrix.json`
4. Open PR titled `Add Sentrix Chain (7119) and Sentrix Testnet (7120)`
5. PR description: brief description of the chain, link to whitepaper / docs, mention EIP-3091 compliance
6. Wait for chainlist.org maintainer review (typically 1-7 days)

## Linked badges after merge

Once merged + indexed at `chainlist.org`, users can:
- Search "Sentrix" in chainlist
- One-click add to MetaMask via the chainlist UI
- Verify chain ID + RPC + explorer through standard tooling
- Get auto-displayed in many wallet "add network" pickers (Rabby, Frame, etc.)

## Estimated effort

- Icon prep + upload: 30 min
- Fork + create branch + add files: 15 min
- PR submission: 10 min
- Iterating on reviewer feedback: variable, usually 0-2 round trips

## Maintainability

Chainlist data is canonical. RPC URL changes should be PR'd back. If we add a 2nd public RPC endpoint, add it to the `rpc` array on a separate PR.
