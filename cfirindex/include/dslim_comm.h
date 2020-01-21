/*
 * Copyright (C) 2019 Muhammad Haseeb, Fahad Saeed
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

#ifndef INCLUDE_DSLIM_COMM_H_
#define INCLUDE_DSLIM_COMM_H_

#include "config.h"

#ifdef DISTMEM
/* Include headers */
#include <mpi.h>
#endif /* DISTMEM */

#include <semaphore.h>
#include <unistd.h>
#include "common.h"
#include "slm_dsts.h"
#include "slmerr.h"
#include "utils.h"
#include "msquery.h"
#include "config.h"
#include "lwqueue.h"

#define TXARRAYS                   2

/* Class for DSLIM MPI Communication */
class DSLIM_Comm
{
private:

    /* Number of data batches processed (either Tx or Rx'ed) */
    UINT    nBatches;

    /* RX buffer size in terms of
     * how many partRes it can contain */
    INT rxbuffsize;

    /* MPI Communication thread */
    THREAD commThd;

    /* Rx array */
    partRes *rxArr;

    /* Semaphore for Rx array */
    LOCK rxLock;

    /* currRxOffset */
    INT currRxOffset;

    /* 2 Tx arrays */
    partRes *txArr[TXARRAYS];

    /* 2 txArr locks */
    LOCK txLock[TXARRAYS];

    /* Current TxArray in use pointer */
    INT currTxPtr;

    /* Exit Signal */
    BOOL exitSignal;

#ifdef DISTMEM

    /* Handle for Rx request(S) */
    MPI_Request *RxRqsts;

    /* Handle for the Tx request */
    MPI_Request *TxRqst;

#endif /* DISTMEM */

    VOID Init_Locks();

    VOID InitTx();

    VOID InitRx();

    VOID Destroy_Locks();

    STATUS FlushRxBuffer();

    STATUS DestroyRxBuffers();

    STATUS InitComm_DataTypes();

    STATUS FreeComm_DataTypes();

public:

    /* Default constructor */
    DSLIM_Comm();

    /* Destructor */
    virtual ~DSLIM_Comm();

    partRes *getCurrTxArr();

    partRes *getCurrRxArr();

    STATUS Tx(INT batchnum);

    STATUS Rx(UINT specs, INT batchtag);

    STATUS ComputeResults();

    STATUS Waitfor_TxData();

    STATUS WaitFor_RxData();

    STATUS SignalExit(BOOL &signal);

    STATUS SignalTx();



};

#endif /* INCLUDE_DSLIM_COMM_H_ */
