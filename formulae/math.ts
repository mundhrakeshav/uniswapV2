//V3 math

const q96 = 2 ** 96
function getBaseLog(x: number, y: number): number {
    return Math.log(x) / Math.log(y);
}

function price_to_tick(x: number): number {
    return Math.floor(getBaseLog(x, 1.0001))
    
}

function price_to_sqrt(x: number): BigInt{
    return BigInt(Math.sqrt(x) * q96)
}

const w = price_to_sqrt(5000)
console.log(w);
