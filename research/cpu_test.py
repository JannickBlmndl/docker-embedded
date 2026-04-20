# /// script
# requires-python = ">=3.13"
# dependencies = [
#     "numpy>=2.4.0",
# ]
# ///
""" CPU primes workload

Finds prime numbers using Sieve of Eratosthenes, with upper limit n.
Output the number of found primes.

Usage:
uv run cpu_test.py -n [UPPER_LIMT]

"""

import os
import sys

import math
import numpy as np
import random

def rand_number():
    random_numbers = [random.random() for i in range(100000)]
    return sum(random_numbers)

# Prime numbers calculation
def sieve(n : int):
    if (n<0):
        print("Error: only use positive numbers")
        sys.exit()
    primes = np.ones(n + 1, dtype=bool)
    primes[0:2] = False

    for p in range(2, int(math.sqrt(n)) + 1):
        if primes[p]:
            primes[p*p:n+1:p] = False
            
    # print(np.nonzero(primes)[0].tolist()) # list of found primes
    # number of primes
    count = len(np.nonzero(primes)[0].tolist())
    return count

def main():
    # result = rand_number()
    if len(sys.argv) < 2:
        print("cpu test")
        print("=" * 50)
        print()
        print("Usage:")
        print("  python3 cpu_test.py -n N")
        print()
        sys.exit(1)

    if sys.argv[1] == '-n':
        if len(sys.argv) < 3:
            print("Error: '--n' flag requires a value")
            sys.exit(1)

        try:
            up_lim = int(sys.argv[2])
        except ValueError:
            print(f"Error: '{sys.argv[2]}' is not an int")
            sys.exit(1)

        result = sieve(up_lim)
        print(result)

if __name__=='__main__':
    main()
