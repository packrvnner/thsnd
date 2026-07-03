# DUNE_QUERIES — public dashboard, ready to paste

Free Dune account → New Query → paste → save each → pin all to one dashboard named **"Thousand ($THSND) — live"**. These use raw `base.logs` so they work immediately, no decoding wait.

**First (optional but nice):** submit the four contracts at https://dune.com/contracts/new for decoding — then Dune generates clean `thousand_base.*` tables you can migrate to later.

Addresses / topics (verified against live chain):
- Vault `0x1141f662b0647c2776bb6a59b0eca3db481e6847`
- Token `0xf7aa829ed31fe30834e56348e9cd3fbb4687cfdb`
- `Locked`         `0x44cebfefa4561bee5b61d675ccfd8dc9969fff9cc15e7a4eccccd62af94f9c11`
- `Withdrawn`      `0x7084f5476618d8e60b11ef0d7d3f06914655adb8793e28ff7f018d4c76d505d5`
- `RewardNotified` `0xf9a5da3a173eca8cd77c02ece3ff1467b8aa461ed3822201817f2d72fbc54283`
- `RewardPaid`     `0xe2403640ba68fed3a2f88b7557551d1993f84b99bb10ff833f0cf8db0c5e0486`
- `Burned`         `0x23ff0e75edf108e3d0392d92e13e8c8a868ef19001bd49f9e94876dc46dff87f`

## Q1 — Vault TVL over time (area chart)

```sql
WITH flows AS (
  SELECT block_time,
         bytearray_to_uint256(bytearray_substring(data, 1, 32)) / 1e18 AS amt
  FROM base.logs
  WHERE contract_address = 0x1141f662b0647c2776bb6a59b0eca3db481e6847
    AND topic0 = 0x44cebfefa4561bee5b61d675ccfd8dc9969fff9cc15e7a4eccccd62af94f9c11
  UNION ALL
  SELECT block_time,
         -1 * bytearray_to_uint256(bytearray_substring(data, 1, 32)) / 1e18
  FROM base.logs
  WHERE contract_address = 0x1141f662b0647c2776bb6a59b0eca3db481e6847
    AND topic0 = 0x7084f5476618d8e60b11ef0d7d3f06914655adb8793e28ff7f018d4c76d505d5
)
SELECT block_time, SUM(amt) OVER (ORDER BY block_time) AS tvl_thsnd
FROM flows ORDER BY block_time;
```

## Q2 — Fee epochs: WETH distributed (bar chart + running total)

```sql
SELECT block_time, tx_hash,
       bytearray_to_uint256(bytearray_substring(data, 1, 32)) / 1e18 AS weth_pushed,
       SUM(bytearray_to_uint256(bytearray_substring(data, 1, 32)) / 1e18)
         OVER (ORDER BY block_time) AS weth_cumulative
FROM base.logs
WHERE contract_address = 0x1141f662b0647c2776bb6a59b0eca3db481e6847
  AND topic0 = 0xf9a5da3a173eca8cd77c02ece3ff1467b8aa461ed3822201817f2d72fbc54283
ORDER BY block_time;
```

## Q3 — Burns: cumulative THSND destroyed (area chart)

```sql
SELECT block_time, tx_hash,
       bytearray_to_uint256(bytearray_substring(data, 1, 32)) / 1e18 AS burned,
       SUM(bytearray_to_uint256(bytearray_substring(data, 1, 32)) / 1e18)
         OVER (ORDER BY block_time) AS burned_cumulative
FROM base.logs
WHERE contract_address = 0xf7aa829ed31fe30834e56348e9cd3fbb4687cfdb
  AND topic0 = 0x23ff0e75edf108e3d0392d92e13e8c8a868ef19001bd49f9e94876dc46dff87f
ORDER BY block_time;
```

## Q4 — Lockers: unique wallets + total vTHSND (counter tiles)

```sql
SELECT COUNT(DISTINCT topic1)                                            AS unique_lockers,
       SUM(bytearray_to_uint256(bytearray_substring(data, 33, 32)))/1e18 AS vthsnd_granted
FROM base.logs
WHERE contract_address = 0x1141f662b0647c2776bb6a59b0eca3db481e6847
  AND topic0 = 0x44cebfefa4561bee5b61d675ccfd8dc9969fff9cc15e7a4eccccd62af94f9c11;
```
*(vTHSND here is gross granted; net = subtract `Withdrawn` users' power — fine as a headline tile early on.)*

## Q5 — Claims: WETH actually paid to lockers

```sql
SELECT DATE_TRUNC('day', block_time) AS day,
       SUM(bytearray_to_uint256(bytearray_substring(data, 1, 32))) / 1e18 AS weth_claimed
FROM base.logs
WHERE contract_address = 0x1141f662b0647c2776bb6a59b0eca3db481e6847
  AND topic0 = 0xe2403640ba68fed3a2f88b7557551d1993f84b99bb10ff833f0cf8db0c5e0486
GROUP BY 1 ORDER BY 1;
```

Dashboard order: Q1 (hero), Q2, Q3, Q4 tiles, Q5. Link the dashboard from thsnd.xyz footer once live — "independent numbers" is the whole point, so it should not live on your domain.
