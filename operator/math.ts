// Math utilities for bigint operations

export class Mathb {
    static abs(value: bigint): bigint {
        return value < 0 ? -value : value;
    }

    static min(a: bigint, b: bigint): bigint {
        return a < b ? a : b;
    }

    static max(a: bigint, b: bigint): bigint {
        return a > b ? a : b;
    }

    static sqrt(value: bigint): bigint {
        if (value < 0) throw new Error("Cannot compute square root of negative number");
        if (value === BigInt(0)) return BigInt(0);
        if (value === BigInt(1)) return BigInt(1);

        let x = value;
        let y = (x + BigInt(1)) / BigInt(2);
        while (y < x) {
            x = y;
            y = (x + value / x) / BigInt(2);
        }
        return x;
    }
}

