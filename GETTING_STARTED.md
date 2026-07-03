# Getting Started — for humans, not terminals

You don't need to know Solidity for any of this. Every step is copy-paste into the Terminal app on your Mac (Cmd+Space, type "Terminal"). Do them in order. Steps 1–5 are free and risk-free; nothing touches real money until step 6.

**Already verified for you:** the contracts compile clean and all 16 tests pass (I ran the full suite). Steps 1–2 just reproduce that on your machine.

---

## 1. Install the tools (5 min, once)

```bash
curl -L https://foundry.paradigm.xyz | bash
```

Close Terminal, open it again (this loads the new tools), then:

```bash
foundryup
```

## 2. Check the project works on your machine

```bash
cd ~/Claude/Projects/\$MUY/contracts
forge install foundry-rs/forge-std
forge test
```

You should see `16 tests passed, 0 failed`. If you do, everything works.

## 3. Create your deployer wallet

This creates a brand-new wallet just for deploying. It will ask you to paste a private key — generate a fresh one first:

```bash
cast wallet new
```

Copy the "Private key" it prints (starts with `0x`), then:

```bash
cast wallet import deployer --interactive
```

Paste the private key when asked, choose a password you'll remember. **Then delete the private key from your clipboard/screen.** Write down the "Address" from `cast wallet new` — that's your deployer address.

## 4. Get free test money

Go to https://docs.base.org/tools/network-faucets, pick a faucet (the Coinbase one is easiest), paste your deployer address, and request Base **Sepolia** ETH. It's fake money for the test network. Takes a minute.

## 5. Deploy to the test network 🚀

Create your settings file:

```bash
cd ~/Claude/Projects/\$MUY/contracts
cat > .env <<'EOF'
BASE_SEPOLIA_RPC=https://sepolia.base.org
TREASURY=YOUR_DEPLOYER_ADDRESS_HERE
REWARD_TOKEN=0x4200000000000000000000000000000000000006
EOF
```

Edit `.env` and replace `YOUR_DEPLOYER_ADDRESS_HERE` with the address from step 3 (on testnet it's fine for treasury = your own address; on mainnet it must be a multisig). Then:

```bash
source .env
forge script script/Deploy.s.sol --rpc-url $BASE_SEPOLIA_RPC --account deployer --broadcast
```

It asks for your password, then prints four addresses under `[ M U Y ] deployment matrix`. **Your token now exists on Base Sepolia.** Paste any address into https://sepolia.basescan.org to see it live.

## 6. What stands between you and mainnet

The commands for mainnet are nearly identical (see `docs/DEPLOYMENT.md` §3). The reason not to run them today:

1. **Audits** — two external firms, 3–6 weeks, typically $30k–$150k+ total. This is the real cost of launching a "premium" protocol. Skipping it with these exact mechanics (a burn engine holding funds, a staking contract holding user principal) is how projects die.
2. **A Safe multisig** — 15 minutes at https://app.safe.global, needs 2–3 trusted co-signers. Genesis supply goes here, never to your laptop wallet.
3. **Legal review** — the fee-share staking especially. Talk to crypto counsel before any public sale or marketing.
4. **Real ETH** — deployment gas on Base is only a few dollars; liquidity seeding is the real capital (whatever MUY/WETH depth you want at launch).

## Also in the repo now

- `contracts/src/MuyVesting.sol` — team-token vesting (cliff + linear, no clawback, no admin). Deploy one per team member with `script/DeployVesting.s.sol`, then send the allocation to it. Publishing these addresses is what makes "no rug" credible.
- `keeper/burn-keeper.mjs` — the bot that triggers the burn engine. Needs Node.js (`npm install viem`) and a small dedicated wallet. Only relevant once Strata is live.

**Suggested order from today:** steps 1–5 (this afternoon) → play with the testnet deployment → Safe multisig → book audits → legal → mainnet.
