/*
 * Copyright (C) 2020 Muhammad Haseeb, and Fahad Saeed
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

#include "common.hpp"
#include <thread>
#include <unistd.h>
#include "config.hpp"
#include "slm_dsts.h"
#include "dslim.h"
#include "slmerr.h"
#include "utils.h"
#include "expeRT.h"

typedef struct _BorrowedData
{
    /* These pointers will be borrowed */
    expeRT *ePtr;
    hCell *heapArray;
    Index *index;
    int_t *sizeArray;
    int_t *fileArray;

    /* Dataset size */
    int_t cPSMsize;
    int_t nBatches;

    _BorrowedData()
    {
        ePtr = NULL;
        heapArray = NULL;
        index = NULL;
        sizeArray = NULL;
        fileArray = NULL;
        cPSMsize = 0;
        nBatches = 0;
    }

} BData;

#ifdef USE_MPI

class DSLIM_Score
{
private:

    /* Variables */
    int_t       threads;

    /* Dataset sizes */
    int_t       nSpectra;
    int_t       nBatches;
    int_t       myRXsize;

    /* These pointers will be borrowed */
    int_t      *sizeArray;
    int_t      *fileArray;
    expeRT   *ePtr;
    hCell    *heapArray;
    Index    *index;
    std::thread comm_thd;

    /* Data size that I expect to
     * receive from other processes */
    int_t      *rxSizes;
    int_t      *txSizes;

    /* key-values */
    int_t      *keys;

    fResult  *TxValues;
    fResult  *RxValues;

public:

    DSLIM_Score();
    DSLIM_Score(BData *bd);
    virtual  ~DSLIM_Score();

    status_t   CombineResults();

#ifdef USE_GPU
    status_t   GPUCombineResults();
#endif

    status_t   ScatterScores();

    status_t   TXSizes(MPI_Request *, int_t *);
    status_t   RXSizes(MPI_Request *, int_t *);

    status_t   TXResults(MPI_Request *, int_t*);
    status_t   RXResults(MPI_Request *, int_t*);

    status_t   DisplayResults();

    status_t   Wait4RX();

    status_t   InitDataTypes();
    status_t   FreeDataTypes();
};

#endif // USE_MPI