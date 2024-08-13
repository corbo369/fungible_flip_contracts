const { ethers } = require('ethers');

async function simulateCoinFlips(iterations) {
    let headsCount = 0;
    let tailsCount = 0;

    for (let i = 0; i < iterations; i++) {
        const randomBytes = ethers.randomBytes(32);
        const randomNumber = ethers.toBigInt(randomBytes);

        if (randomNumber % 2n === 0n) {
            headsCount++;
        } else {
            tailsCount++;
        }
    }

    console.log(`Total Flips: ${iterations}`);
    console.log(`Heads: ${headsCount}`);
    console.log(`Tails: ${tailsCount}`);
}

const iterations = 10000;
simulateCoinFlips(iterations);