// AssemblyScript event handler for SentrixDexFactory.
// Compiled to WebAssembly by graph-cli when the subgraph is deployed.
//
// AssemblyScript is a strict subset of TypeScript. Differences vs regular TS:
//   - No closures (anonymous functions captured in variables OK, but no real closures)
//   - No exceptions (use return values + log.warning)
//   - Strict types — all variables must have explicit types or trivially inferable
//   - BigInt / BigDecimal must use @graphprotocol/graph-ts helpers
//   - Address.fromString returns Address, not string

import { Address, BigInt, BigDecimal, log } from "@graphprotocol/graph-ts";
import { PairCreated } from "../generated/SentrixDexFactory/SentrixDexFactory";
import { Pair, Token, SentrixDexFactory } from "../generated/schema";
import { SentrixDexPair as PairTemplate } from "../generated/templates";
import { ERC20 } from "../generated/SentrixDexFactory/ERC20";

// Singleton factory entity id — addresses-as-lowercase-hex per Graph convention.
// SentrixV2Factory mainnet (chain 7119), from sentrix-dex/deployments/7119.json.
const FACTORY_ID = "0xc5344f0dde0b9916217449ad9222e446475ad936";

const ZERO_BI = BigInt.fromI32(0);
const ZERO_BD = BigDecimal.fromString("0");

export function handlePairCreated(event: PairCreated): void {
  // 1. Load or initialize the factory singleton
  let factory = SentrixDexFactory.load(FACTORY_ID);
  if (factory == null) {
    factory = new SentrixDexFactory(FACTORY_ID);
    factory.pairCount = 0;
    factory.totalVolumeSRX = ZERO_BD;
    factory.totalLiquiditySRX = ZERO_BD;
    factory.txCount = ZERO_BI;
  }
  factory.pairCount = factory.pairCount + 1;
  factory.save();

  // 2. Create the Pair entity
  let pair = new Pair(event.params.pair.toHexString());
  pair.token0 = ensureToken(event.params.token0);
  pair.token1 = ensureToken(event.params.token1);
  pair.reserve0 = ZERO_BD;
  pair.reserve1 = ZERO_BD;
  pair.totalSupply = ZERO_BD;
  pair.volumeToken0 = ZERO_BD;
  pair.volumeToken1 = ZERO_BD;
  pair.txCount = ZERO_BI;
  pair.createdAtTimestamp = event.block.timestamp;
  pair.createdAtBlock = event.block.number;
  pair.save();

  // 3. Spawn a Pair template — graph-node now indexes Swap/Mint/Burn/Sync
  // events on this new pair address.
  PairTemplate.create(event.params.pair);

  log.info("PairCreated: {} ({} / {})", [
    event.params.pair.toHexString(),
    event.params.token0.toHexString(),
    event.params.token1.toHexString(),
  ]);
}

// ─── Token bookkeeping ──────────────────────────────────────────────

function ensureToken(address: Address): string {
  let id = address.toHexString();
  let token = Token.load(id);
  if (token != null) {
    return id;
  }

  token = new Token(id);
  // Snapshot ERC20 metadata at pair-creation time.
  // graph-ts handles "view function failed" via the .reverted flag on the
  // returned Result struct; if any call reverts we set sane fallbacks.
  let erc20 = ERC20.bind(address);

  let nameResult = erc20.try_name();
  token.name = nameResult.reverted ? "unknown" : nameResult.value;

  let symbolResult = erc20.try_symbol();
  token.symbol = symbolResult.reverted ? "???" : symbolResult.value;

  let decimalsResult = erc20.try_decimals();
  token.decimals = decimalsResult.reverted
    ? BigInt.fromI32(18) // EVM default — matches what most ERC20s use
    : BigInt.fromI32(decimalsResult.value);

  let supplyResult = erc20.try_totalSupply();
  token.totalSupply = supplyResult.reverted ? ZERO_BI : supplyResult.value;

  token.totalLiquidity = ZERO_BD;
  token.tradeVolume = ZERO_BD;
  token.txCount = ZERO_BI;
  token.save();

  return id;
}
