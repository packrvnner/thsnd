/**
 * DefiLlama adapter — Thousand ($THSND)
 *
 * Submission steps (free, ~24h after merge):
 *  1. Fork https://github.com/DefiLlama/DefiLlama-Adapters
 *  2. Create projects/thousand/index.js with this file's contents
 *  3. PR title: "Add Thousand (THSND) — Base". Fill their PR template:
 *     - twitter/site: https://thsnd.xyz · category: "Staking" (until the agent vault ships, then "Yield")
 *     - listing form: https://docs.llama.fi/list-your-project/submit-a-project
 *
 * Note: THSND locked in LatticeLock is the protocol's OWN token, so per
 * DefiLlama rules it must be reported as `staking`, not `tvl`. This is the
 * honest listing — it shows as a separate "Staking" line on the page.
 */
const { staking } = require("../helper/staking");

const VAULT = "0x1141F662b0647C2776Bb6A59B0ECA3Db481e6847"; // LatticeLock
const THSND = "0xF7aa829ed31fE30834E56348e9CD3fBb4687CFdb";

module.exports = {
  methodology:
    "Staking counts THSND locked in the LatticeLock vault (non-custodial 1wk–4yr locks earning pro-rata WETH protocol fees). The protocol currently has no external-asset deposits; when the agent vault (ERC-4626, USDC) ships, its NAV will be added under tvl.",
  start: 48117150, // deploy block, Base
  base: {
    tvl: async () => ({}), // no external-asset TVL yet — do not fake it
    staking: staking(VAULT, THSND),
  },
};
