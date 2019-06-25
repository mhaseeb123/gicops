/*
 * This file is part of Load Balancing Algorithm for DSLIM
 *  Copyright (C) 2019  Muhammad Haseeb, Fahad Saeed
 *  Florida International University, Miami, FL
 *
 *  This program is free software: you can redistribute it and/or modify
 *  it under the terms of the GNU General Public License as published by
 *  the Free Software Foundation, either version 3 of the License, or
 *  (at your option) any later version.
 *
 *  This program is distributed in the hope that it will be useful,
 *  but WITHOUT ANY WARRANTY; without even the implied warranty of
 *  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 *  GNU General Public License for more details.
 *
 *  You should have received a copy of the GNU General Public License
 *  along with this program.  If not, see <https://www.gnu.org/licenses/>.
 *
 */

#include "dslim.h"
#include "hyperscore.h"

extern gParams params;


#ifdef FUTURE
extern pepEntry    *pepEntries; /* SLM Peptide Index */
extern PepSeqs          seqPep; /* Peptide sequences */
#ifdef VMODS
extern varEntry    *modEntries;
#endif /* VMODS */
#endif /* FUTURE */

/* Global Variables */
FLOAT *hyperscores = NULL;
UCHAR *sCArr = NULL;

/* FUNCTION: DSLIM_QuerySpectrum
 *
 * DESCRIPTION: Query the DSLIM for all query peaks
 *              and count the number of hits per chunk
 *
 * INPUT:
 * @QA     : Query Spectra Array
 * @len    : Number of spectra in the array
 * @Matches: Array to fill in the number of hits per chunk
 * @threads: Number of parallel threads to launch
 *
 * OUTPUT:
 * @status: Status of execution
 */
STATUS DSLIM_QuerySpectrum(ESpecSeqs &ss, UINT len, Index *index, UINT idxchunk)
{
    STATUS status = SLM_SUCCESS;
    UINT *QAPtr = NULL;
    FLOAT *iPtr = NULL;
    UINT maxz = params.maxz;
    UINT dF = params.dF;
    UINT threads = params.threads;
    UINT scale = params.scale;

    DOUBLE maxmass = params.max_mass;

    /* Process all the queries in the chunk */
    for (UINT queries = 0; queries < len; queries++)
    {
        /* Pointer to each query spectrum */
        QAPtr = ss.moz + (queries * QALEN);
        iPtr = ss.intensity + (queries * QALEN);

#ifdef _OPENMP
#pragma omp parallel for schedule(dynamic, 1) num_threads(threads)
#endif
        for (UINT ixx = 0; ixx < idxchunk; ixx++)
        {
            UINT speclen = (index[ixx].pepIndex.peplen - 1) * maxz * iSERIES;

            for (UINT chno = 0; chno < index[ixx].nChunks; chno++)
            {
                /* Query each chunk in parallel */
                UINT *bAPtr = index[ixx].ionIndex[chno].bA;
                UINT *iAPtr = index[ixx].ionIndex[chno].iA;
                UCHAR *bcPtr = index[ixx].ionIndex[chno].sc.bc;
                UCHAR *ycPtr = index[ixx].ionIndex[chno].sc.yc;
                FLOAT *ibcPtr = index[ixx].ionIndex[chno].sc.ibc;
                FLOAT *iycPtr = index[ixx].ionIndex[chno].sc.iyc;

                /* Query all fragments in each spectrum */
                for (UINT k = 0; k < QALEN; k++)
                {
                    /* Check for any zeros
                     * Zero = Trivial query */
                    if (QAPtr[k] < dF || QAPtr[k] > ((maxmass * scale) - 1 - dF))
                    {
                        continue;
                    }

                    /* Locate iAPtr start and end */
                    UINT start = bAPtr[QAPtr[k] - dF];
                    UINT end = bAPtr[QAPtr[k] + 1 + dF];

                    /* Loop through located iAions */
                    for (UINT ion = start; ion < end; ion++)
                    {
                        UINT raw = iAPtr[ion];

                        /* Calculate parent peptide ID */
                        UINT ppid = (raw / speclen);

                        /* Update corresponding scorecard entries */
                        if ((raw % speclen) < speclen / 2)
                        {
                            bcPtr[ppid] += 1;
                            ibcPtr[ppid] += iPtr[k];
                        }
                        else
                        {
                            ycPtr[ppid] += 1;
                            iycPtr[ppid] += iPtr[k];
                        }
                    }
                }

                index[ixx].ionIndex[chno].sc.especid = queries;

                INT idaa = -1;
                FLOAT maxhv = 0.0;

                for (UINT i = 0; i < ss.numSpecs; i++)
                {
                    if (bcPtr[i] + ycPtr[i] > params.min_shp)
                    {
                        FLOAT hyperscore = log(HYPERSCORE_Factorial(ULONGLONG(bcPtr[i])) *
                                HYPERSCORE_Factorial(ULONGLONG(ycPtr[i])) *
                                ibcPtr[i] *
                                iycPtr[i]);

                        if (hyperscore > maxhv)
                        {
                            idaa = i;
                            maxhv = hyperscore;
                        }
                    }

                    bcPtr[i] = 0;
                    ycPtr[i] = 0;
                    ibcPtr[i] = 0;
                    iycPtr[i] = 0;
                }

                /* FIXME: Printing the hyperscore in OpenMP mode - Use some other filename. How will we merge in multiple nodes? */
                status = HYPERSCORE_Calculate(queries, idaa, maxhv);
            }
        }
    }

    return status;
}

STATUS DSLIM_DeallocateSC(VOID)
{
    if (sCArr != NULL)
    {
        delete[] sCArr;
        sCArr = NULL;
    }

    return SLM_SUCCESS;
}