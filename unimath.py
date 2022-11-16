import math

# USDC on y reserve and ETH on x

min_tick = -887272
max_tick = 887272


q96 = 2**96
eth = 10**18


def price_to_tick(p):
    # p(i) = 1.0001^i
    return math.floor(math.log(p, 1.0001))


def price_to_sqrtp(p):
    # sqrt price and multiply by q96
    return int(math.sqrt(p) * q96)


def sqrtp_to_price(sqrtp):
    return (sqrtp / q96) ** 2


def tick_to_sqrtp(t):
    return int((1.0001 ** (t / 2)) * q96)


def liquidity0(amount, pa, pb):
    # if pa > pb:
    #     pa, pb = pb, pa
    return (amount * (pa * pb) / q96) / (pb - pa)


def liquidity1(amount, pa, pb):
    if pa > pb:
        pa, pb = pb, pa
    return amount * q96 / (pb - pa)


def calc_amount0(liq, price_next, price_current):
    # if pa > pb:
    #     pa, pb = pb, pa
    # Δx = (Δ(1/√p))L

    # If ETH is sold for USDC price will decrease, as price is represented in usdc/eth
    # ∴ price_next will be smaller in that case and calc_amount0 would return a +ve value i.e. ETH is sold.
    # If calc_amount is -ve, that would mean ETH is bought from the pool.
    # This function would return -ve value only if price_next is larger than price_current. 
    return int(liq * q96 * (price_current - price_next) / (price_current * price_next))


def calc_amount1(liq, price_next, price_current):
    # if pa > pb:
    #     pa, pb = pb, pa

    # Δ(√p) * L = Δy
    # If USDC is sold for ETH price will increase, as price is represented in usdc/eth
    # ∴ price_next will be greater in that case and calc_amount1 would return a +ve value i.e. USDC is sold.
    # If calc_amount is -ve, that would mean USDC is bought from the pool.
    # This function would return -ve value only if price_next is smaller than price_current. 
    
    return int(liq * (price_next - price_current) / q96)


# Liquidity provision
price_low = 4545
price_cur = 5000
price_upp = 5500

print(f"\n")
print(f"Price range: {price_low} usdc/eth to {price_upp} usdc/eth ; current price: {price_cur} usdc/eth\n")

sqrtp_low = price_to_sqrtp(price_low)
sqrtp_cur = price_to_sqrtp(price_cur)
sqrtp_upp = price_to_sqrtp(price_upp)

print(f"Price range sqrt: {sqrtp_low} to {sqrtp_upp}; current price: {sqrtp_cur}\n")


amount_eth = 1 * eth
amount_usdc = 5000 * eth

liq0 = liquidity0(amount_eth, sqrtp_cur, sqrtp_upp)
liq1 = liquidity1(amount_usdc, sqrtp_cur, sqrtp_low)
print(f"Liquidity0: {int(liq0)}, Liquidity1, {int(liq1)}\n")
liq = int(min(liq0, liq1))

print(f"Deposit: {amount_eth/eth} ETH, {amount_usdc/eth} USDC; liquidity: {liq}\n")

# Swap USDC for ETH
amount_in = 42 * eth
print(f"Selling {amount_in/eth} USDC\n")


price_diff = (amount_in * q96) // liq
price_next = sqrtp_cur + price_diff

print("New price:", (price_next / q96) ** 2, "\n")
print("New sqrtP:", int(price_next), "\n")
print("New tick:", price_to_tick(sqrtp_to_price(price_next)), "\n")

amount_in = calc_amount1(liq, price_next, sqrtp_cur)
amount_out = calc_amount0(liq, price_next, sqrtp_cur)

print("USDC in:", amount_in / eth, "\n")
print("ETH out:", amount_out / eth, "\n")

# Swap ETH for USDC
amount_in = 0.01337 * eth

print(f"\nSelling {amount_in/eth} ETH")

price_next = int((liq * q96 * sqrtp_cur) // (liq * q96 + amount_in * sqrtp_cur))

print("New price:", (price_next / q96) ** 2)
print("New sqrtP:", price_next)
print("New tick:", price_to_tick((price_next / q96) ** 2))

amount_in = calc_amount0(liq, price_next, sqrtp_cur)
amount_out = calc_amount1(liq, price_next, sqrtp_cur)

print("ETH in:", amount_in / eth)
print("USDC out:", amount_out / eth)

# Bitmap
tick = price_to_tick((price_next / q96) ** 2)
word_pos = tick >> 8 # or tick // 2**8
bit_pos = tick % 256
print(f"Word {word_pos}, bit {bit_pos}")
mask = 2**bit_pos # or 1 << bit_pos
print(bin(mask))