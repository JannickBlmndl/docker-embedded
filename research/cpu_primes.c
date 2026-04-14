/*  prime.c
    Author: J. Bloemendal
    Sieve of Eratosthenes function and clock tracking

    from https://www.geeksforgeeks.org/c/c-program-to-implement-sieve-of-eratosthenes/

    To compile:
        OS X built
            gcc cpu_primes.c -o runme
        Win64 i686 built
            gcc_win64 prime.c -o runme_win64.exe
            https://www.mingw-w64.org/

    Usage: ./runme -n [UPPER_LIMIT]
*/

// Defines
// #define DEBUG // to enable DEBUG mode
#define EN_PRNTS
// #define TRACK_TIME

#include <stdbool.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <math.h>
#include <time.h>

int SieveOfEratosthenes(signed int);

/**
 * @brief Finds prime numbers up to n using the Sieve of Eratosthenes algorithm.
 *
 * @param n The upper limit for finding prime numbers.
 * @return The total count of prime numbers found up to n.
 */
int SieveOfEratosthenes(signed int n)
{
  // Allocate memory for prime array and initialize all elements as true
  bool *prime = malloc((n + 1) * sizeof(bool));

  // Initialize all numbers as potentially prime (true).
  for (int i = 0; i <= n; i++)
    prime[i] = true;

  // 0 and 1 are not prime numbers
  prime[0] = prime[1] = false;

  // For each number from 2 to sqrt(n)
  for (int p = 2; p * p <= n; p++)
  {
    if (prime[p])
    {
      // Mark all multiples of p as non-prime
      for (int i = p * p; i <= n; i += p)
        prime[i] = false;
    }
  }

  // Count and print all prime numbers up to n
  int count = 0;

  // printf("Prime numbers up to %d:\n", n);
  for (int p = 2; p <= n; p++)
  {
    if (prime[p])
    {
      // printf("%d ", p);
      count++;
    }
  }
  // printf("\n");

  free(prime);
  return count;
}

int main(int argc, char *argv[])
{
  clock_t start_time, end_time;
  signed int n;

  // parse from cmd line argument
  if (argc >= 3 && strcmp(argv[1], "-n") == 0)
  {
    char *endptr;
    n = (int)strtol(argv[2], &endptr, 10);
    if (*endptr != '\0')
    {
      fprintf(stderr, "Error: '%s' is not an integer.\n", argv[2]);
      return 1;
    }
  }
  else
  {
    // No arguments — fall back to scanf
    printf("Enter the maximum number to find primes: ");
    if (scanf("%d", &n) != 1)
    {
      fprintf(stderr, "Invalid input. Please enter an integer.\n");
      return 1;
    }
  }

  if (n < 0)
  {
    printf("Input must be non-negative.\n");
    n = 0;
  }

  start_time = clock();
  // Call the Sieve function to find primes and get the count.
  int prime_count = SieveOfEratosthenes(n);
  end_time = clock();

  // Calculate the elapsed time in milliseconds.
  // clock ticks / CLOCKS_PER_SEC = runtime in (s)
  double runtime_ms = (double)(end_time - start_time) / CLOCKS_PER_SEC * 1000.0;

// Check if SieveOfEratosthenes returned an error code.
#ifdef EN_PRNTS
  if (prime_count != -1)
    printf("Total primes found: %d\n", prime_count);

  printf("Measured time: %.2fms\n", runtime_ms);
#endif

  return 0;
}