// AssemblyScript event handlers for SentrixDexPair template.
// One instance of this template runs per pair created by the factory.

import { Address, BigInt, BigDecimal, log } from "@graphprotocol/graph-ts";
import { Sync, Swap, Mint, Burn } from "../generated/templates/SentrixDexPair/SentrixDexPair";
import { Pair, Token, Swap as SwapEntity, Mint as MintEntity, Burn as BurnEntity } from "../generated/schema";

const ZERO_BI = BigInt.fromI32(0);
const ZERO_BD = BigDecimal.fromString("0");
const BI_18 = BigInt.fromI32(18);
const BD_TEN = BigDecimal.fromString("10");

/// Convert a raw token amount (uint256 in token-native units) to a
/// BigDecimal scaled to the token's decimals. e.g. 1e18 wei with decimals=18
/// returns 1.0.
function exponentToBigDecimal(decimals: BigInt): BigDecimal {
  let result = BigDecimal.fromString("1");
  let ten = BD_TEN;
  let i = BigInt.fromI32(0);
  while (i.lt(decimals)) {
    result = result.times(ten);
    i = i.plus(BigInt.fromI32(1));
  }
  return result;
}

function convertTokenAmount(raw: BigInt, decimals: BigInt): BigDecimal {
  if (decimals.equals(ZERO_BI)) {
    return raw.toBigDecimal();
  }
  return raw.toBigDecimal().div(exponentToBigDecimal(decimals));
}

// ─── Sync — reserves updated ─────────────────────────────────────────

export function handleSync(event: Sync): void {
  let pair = Pair.load(event.address.toHexString());
  if (pair == null) {
    log.warning("Sync on unknown pair {}", [event.address.toHexString()]);
    return;
  }

  let token0 = Token.load(pair.token0);
  let token1 = Token.load(pair.token1);
  if (token0 == null || token1 == null) {
    return;
  }

  pair.reserve0 = convertTokenAmount(event.params.reserve0, token0.decimals);
  pair.reserve1 = convertTokenAmount(event.params.reserve1, token1.decimals);
  pair.save();
}

// ─── Swap ────────────────────────────────────────────────────────────

export function handleSwap(event: Swap): void {
  let pair = Pair.load(event.address.toHexString());
  if (pair == null) {
    return;
  }
  let token0 = Token.load(pair.token0);
  let token1 = Token.load(pair.token1);
  if (token0 == null || token1 == null) {
    return;
  }

  let id = event.transaction.hash.toHexString() + "-" + event.logIndex.toString();
  let swap = new SwapEntity(id);
  swap.pair = pair.id;
  swap.sender = event.params.sender;
  swap.to = event.params.to;
  swap.amount0In = convertTokenAmount(event.params.amount0In, token0.decimals);
  swap.amount1In = convertTokenAmount(event.params.amount1In, token1.decimals);
  swap.amount0Out = convertTokenAmount(event.params.amount0Out, token0.decimals);
  swap.amount1Out = convertTokenAmount(event.params.amount1Out, token1.decimals);
  swap.timestamp = event.block.timestamp;
  swap.blockNumber = event.block.number;
  swap.transaction = event.transaction.hash;
  swap.logIndex = event.logIndex;
  swap.save();

  pair.txCount = pair.txCount.plus(BigInt.fromI32(1));
  pair.volumeToken0 = pair.volumeToken0.plus(swap.amount0In).plus(swap.amount0Out);
  pair.volumeToken1 = pair.volumeToken1.plus(swap.amount1In).plus(swap.amount1Out);
  pair.save();

  token0.tradeVolume = token0.tradeVolume.plus(swap.amount0In).plus(swap.amount0Out);
  token0.txCount = token0.txCount.plus(BigInt.fromI32(1));
  token0.save();

  token1.tradeVolume = token1.tradeVolume.plus(swap.amount1In).plus(swap.amount1Out);
  token1.txCount = token1.txCount.plus(BigInt.fromI32(1));
  token1.save();
}

// ─── Mint (LP added) ─────────────────────────────────────────────────

export function handleMint(event: Mint): void {
  let pair = Pair.load(event.address.toHexString());
  if (pair == null) {
    return;
  }
  let token0 = Token.load(pair.token0);
  let token1 = Token.load(pair.token1);
  if (token0 == null || token1 == null) {
    return;
  }

  let id = event.transaction.hash.toHexString() + "-" + event.logIndex.toString();
  let mint = new MintEntity(id);
  mint.pair = pair.id;
  mint.sender = event.params.sender;
  mint.to = event.params.sender; // V2 Mint event doesn't carry `to` separately; LP minted to sender path
  mint.amount0 = convertTokenAmount(event.params.amount0, token0.decimals);
  mint.amount1 = convertTokenAmount(event.params.amount1, token1.decimals);
  // V2 Mint event doesn't directly emit liquidity; could read pair.totalSupply diff.
  // For sketch, leave at 0 — production handler should compute from totalSupply delta.
  mint.liquidity = ZERO_BD;
  mint.timestamp = event.block.timestamp;
  mint.blockNumber = event.block.number;
  mint.transaction = event.transaction.hash;
  mint.logIndex = event.logIndex;
  mint.save();
}

// ─── Burn (LP removed) ───────────────────────────────────────────────

export function handleBurn(event: Burn): void {
  let pair = Pair.load(event.address.toHexString());
  if (pair == null) {
    return;
  }
  let token0 = Token.load(pair.token0);
  let token1 = Token.load(pair.token1);
  if (token0 == null || token1 == null) {
    return;
  }

  let id = event.transaction.hash.toHexString() + "-" + event.logIndex.toString();
  let burn = new BurnEntity(id);
  burn.pair = pair.id;
  burn.sender = event.params.sender;
  burn.to = event.params.to;
  burn.amount0 = convertTokenAmount(event.params.amount0, token0.decimals);
  burn.amount1 = convertTokenAmount(event.params.amount1, token1.decimals);
  burn.liquidity = ZERO_BD; // see comment in handleMint
  burn.timestamp = event.block.timestamp;
  burn.blockNumber = event.block.number;
  burn.transaction = event.transaction.hash;
  burn.logIndex = event.logIndex;
  burn.save();
}
