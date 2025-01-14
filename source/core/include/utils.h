/*
 * Copyright (C) 2019  Muhammad Haseeb, Fahad Saeed
 * Florida International University, Miami, FL
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program.  If not, see <https://www.gnu.org/licenses/>.
 *
 */

#pragma once

#include <omp.h>
#include <parallel/algorithm>
#include <bits/stdc++.h>
#include <functional>
#include <cstdlib>
#include "common.hpp"
#include "slm_dsts.h"
#include "keyval.h"

#define BITSET(x, bit)                      ((x) |  ((ull_t)((ull_t)1 << (bit)))
#define BITCLR(x, bit)                      ((x) & ~((ull_t)((ull_t)1 << (bit)))
#define ISBITSET(x,bit)                     ((x) &  ((ull_t)((ull_t)1 << (bit))))


/*
 * FUNCTION: UTILS_Sort
 *
 * DESCRIPTION: Sort an array
 *
 * INPUT:
 * @data      : Array to sort
 * @size      : Size of array
 * @descending: Sort in descending order?
 *
 * OUTPUT: none
 */
template <class Num>
void   UTILS_Sort(Num *data, uint_t size, bool descending = false)
{
    if (descending == false)
        std::sort(data, data + size);
    else
        std::sort(data, data+size, std::greater<Num>());
}

/*
 * FUNCTION: UTILS_ParallelSort
 *
 * DESCRIPTION: Parallel Sort an array
 *
 * INPUT:
 * @data      : Array to sort
 * @size      : Size of array
 * @descending: Sort in descending order?
 *
 * OUTPUT: none
 */
template <class Num>
void   UTILS_ParallelSort(Num *data, uint_t size, bool descending = false)
{
    if (descending == false)
        __gnu_parallel::sort(data, data + size);
    else
        __gnu_parallel::sort(data, data+size, std::greater<Num>());
}

/*
 * FUNCTION: UTILS_GetNumProcs
 *
 * DESCRIPTION: Get the number of processors
 *              from the environment variable
 *
 * INPUT: none
 *
 * OUTPUT:
 * @procs: Number of processors
 */
uint_t   UTILS_GetNumProcs();

/*
 * FUNCTION: UTILS_Factorial
 *
 * DESCRIPTION: Calculate the factorial of a number
 *
 * INPUT:
 * @n : input value for which to calculate factorial
 *
 * OUTPUT:
 * @factorial : the factorial of the input number n
 */
ull_t factorial(ull_t);


namespace hcp
{
namespace utils
{
// max shared b- or y-ions
const int maxshp = MAX_SHDPEAKS + 1;

//
// computes log(factorial(x)) at compile time
//
template<int N>
struct lgfact {
    constexpr lgfact() : val() {
        
        val[0] = val[1] = log10(1);

        for (auto i = 2; i < N; i++) {
            val[i] = log10(i) + val[i-1]; 
        }
    }

    // needs to be const so it does not affect the val
    auto operator[](int x) const { return val[x]; }

    // array to store results
    double val[N];
};

// max shared b- or y-ions
const int maxcombs = 64;

//
// computes nCr at compile time
//
template<int N>
struct Comb {
    constexpr Comb() : val() {

        //run this at start of main to fill Comb with the proper values
        val[0][0] = 1;
        val[1][0] = 1;
        val[1][1] = 1;
        for (int i = 1; i < N; i++)
        {
            val[i][0] = 1;
            for (int j = 1; j <= (i + 1) / 2; j++)
            {
                val[i][j] = val[i - 1][j - 1] + val[i - 1][j];
            }
            for (int j = i / 2; j < i; j++)
            {
                val[i][j] = val[i][i - j];
            }
            val[i][i] = 1;
        }
    }

    // needs to be const so it does not affect the val
    ull_t ( & operator []( int x ) )[N]
    {
        return val[x];
    }

    // array to store results
    ull_t val[N][N];
};

} // namespace utils
} // namespace hcp

/*
 * FUNCTION: UTILS_Shuffle
 *
 * DESCRIPTION: Shuffles an array

 *
 * INPUT:
 * @arr : Array to shuffle
 * @N   : Size of array
 *
 * OUTPUT:
 * @status: Status of execution
 */
status_t UTILS_Shuffle(uint_t *, uint_t );

/*
 * FUNCTION: UTILS_ShuffleI
 *
 * DESCRIPTION: Shuffles an array using specific seed
 *
 * INPUT:
 * @arr : Array to shuffle
 * @N   : Size of array
 * @seed: The seed to use
 *
 * OUTPUT:
 * @status: Status of execution
 */
status_t UTILS_ShuffleI(uint_t *, uint_t, ull_t);

/*
 * FUNCTION: UTILS_GenerateSpectrum
 *
 * DESCRIPTION: Generates theoretical spectrum of a peptide
 *
 * INPUT:
 * @seq     : Peptide sequence
 * @len     : Length of peptide
 * @Spectrum: Pointer to the theoretical spectrum
 *
 * OUTPUT:
 * @mass: Precursor mass of peptide
 */
float_t  UTILS_GenerateSpectrum(char_t *, uint_t, uint_t *);

/*
 * FUNCTION: UTILS_CalculatePepMass
 *
 * DESCRIPTION: Calculate precursor mass of a peptide
 *
 * INPUT:
 * @seq: Peptide sequence
 * @len: Length of peptide
 *
 * OUTPUT:
 * @mass: Precursor mass of peptide
 */
float_t UTILS_CalculatePepMass(AA *, uint_t);

/*
 * FUNCTION: UTILS_InitializeModInfo
 *
 * DESCRIPTION: Initialize the gModInfo structure
 *
 * INPUT:
 * @modconditions: The initialization information
 *
 * OUTPUT:
 * @status: Status of execution
 */
status_t UTILS_InitializeModInfo(string_t);

/*
 * FUNCTION: UTILS_InitializeModInfo
 *
 * DESCRIPTION: Initialize the gModInfo structure
 *
 * INPUT:
 * @vMods: gModInfo information
 *
 * OUTPUT:
 * @status: Status of execution
 */
status_t UTILS_InitializeModInfo(SLM_vMods *);

status_t UTILS_SetParams(gParams *params);

/*
 * FUNCTION: UTILS_CalculateModMass
 *
 * DESCRIPTION: Calculate precursor mass of a mod
 *
 * INPUT:
 * @seq     : Modified Peptide sequence
 * @len     : Length of Modified Peptide
 * @vmodInfo: Information about the modifications
 *
 * OUTPUT:
 * @mass: Precursor mass of modified peptide
 */
float_t UTILS_CalculateModMass(AA *, uint_t, uint_t);

/*
 * FUNCTION: UTILS_GenerateModSpectrum
 *
 * DESCRIPTION: Generates theoretical spectrum for a mod
 *
 * INPUT:
 * @seq     : Modified peptide sequence
 * @len     : Length of modified peptide
 * @Spectrum: Pointer to the theoretical spectrum
 * @modInfo : Modified peptide information
 *
 * OUTPUT:
 * @mass: Precursor mass of modified peptide
 */
float_t UTILS_GenerateModSpectrum(char_t *, uint_t, uint_t *, modAA);
