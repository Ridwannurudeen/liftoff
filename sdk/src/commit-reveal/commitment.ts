import {
  encodeAbiParameters,
  keccak256,
  stringToBytes,
  type Address,
  type Hex,
} from "viem";

export interface CommitmentInput {
  /** Real bid amount in quote-token base units (wei). Must equal what you'll pass to `reveal`. */
  amount: bigint;
  /** 32-byte salt the bidder keeps secret until reveal. Use `deriveSalt(...)` for convenience. */
  salt: Hex;
  /** The committing wallet — binds the commitment so observers can't replay another's hash. */
  bidder: Address;
}

/**
 * Compute the commitment a bidder must post on-chain. Matches the on-chain
 * `CommitRevealLaunch.commitmentFor` byte-for-byte:
 *
 *   keccak256(abi.encode(uint256 amount, bytes32 salt, address bidder))
 *
 * The bidder address is part of the hash, so an observer can't replay
 * another wallet's commitment.
 */
export function commitmentFor({ amount, salt, bidder }: CommitmentInput): Hex {
  return keccak256(
    encodeAbiParameters(
      [{ type: "uint256" }, { type: "bytes32" }, { type: "address" }],
      [amount, salt, bidder],
    ),
  );
}

/**
 * Convenience helper: turn a human-readable string into a deterministic
 * 32-byte salt via `keccak256(utf8(NFC(input)))`. The input is normalized to
 * Unicode NFC so visually-identical strings produced by different IMEs (or
 * pasted from different sources) hash the same. Useful for demos and tests;
 * for real bids generate random 32 bytes (e.g. `crypto.getRandomValues`) and
 * store the salt off-chain — losing it is equivalent to losing your bid.
 */
export function deriveSalt(input: string): Hex {
  return keccak256(stringToBytes(input.normalize("NFC")));
}
