/*
 * Copyright (C) 2022 Muhammad Haseeb, and Fahad Saeed
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

#include <cuda.h>
#include <string>
#include <thrust/fill.h>
#include <thrust/gather.h>
#include <thrust/sort.h>
#include <thrust/scan.h>
#include <thrust/sequence.h>
#include <thrust/distance.h>
#include <thrust/binary_search.h>
#include <thrust/functional.h>
#include <thrust/execution_policy.h>

#include <iostream>
#include <thread>

#include "cuda/driver.hpp"

// for instrumentation
#include "hicops_instr.hpp"

#include "cuda/superstep1/kernel.hpp"
#include "cuda/superstep3/kernel.hpp"
#include "cuda/superstep4/kernel.hpp"

using namespace std;

// -------------------------------------------------------------------------------------------- //

// include the CUDA constant memory objects for A generation
// array to store PTM masses
extern __constant__ float_t modMass[ALPHABETS];

// amino acid masses
extern __constant__ float_t aaMass[ALPHABETS];

// static mod masses
extern __constant__ float_t statMass[ALPHABETS];

// log(factorial(n))
__constant__ double_t d_lgFact[hcp::utils::maxshp];


// -------------------------------------------------------------------------------------------- //

// host side global parameters
extern gParams params;

// -------------------------------------------------------------------------------------------- //

namespace hcp
{

namespace gpu
{

namespace cuda
{

// -------------------------------------------------------------------------------------------- //

namespace s1
{

extern __device__ int log2ceil(unsigned long long x);

}

// -------------------------------------------------------------------------------------------- //

namespace s3
{

//
// CUDA kernel declarations
//

// -------------------------------------------------------------------------------------------- //

__global__ void SpSpGEMM(spectype_t *dQ_moz, spectype_t *dQ_intensity, uint_t *dQ_idx, int *dQ_minlimits, int *dQ_maxlimits,
                        uint_t* d_bA, uint_t *d_iA, int iter, BYC *bycP, int maxchunk, double *d_survival, int *d_cpsms,
                        dhCell *d_topscore, int dF, int speclen, int maxmass, int scale, short min_shp, int ixx);

// database search kernel host wrapper
__host__ status_t SearchKernel(spmat_t *mat, Queries<spectype_t> *, int, int);

// compute min and max limits for the spectra
__host__ status_t MinMaxLimits(Queries<spectype_t> *, Index *, double dM);

template <typename T>
__global__ void vector_plus_constant(T *vect, T val, int size);

__global__ void resetdScores(double *survival, int *cpsms, dhCell *topscores);

extern __device__ void getMaxdhCell(dhCell &topscores, dhCell &out);

extern __device__ void getMinsurvival(double_t *survival, double_t *out);

template <typename T>
extern __device__ void blockSum(T val, T &sum);

template <typename T>
extern __device__ T * upper_bound(T *start, const int n, T target);

template <typename T>
extern __device__ T * lower_bound(T *start, const int n, T target);


// -------------------------------------------------------------------------------------------- //

dScores::dScores()
{
    auto driver = hcp::gpu::cuda::driver::get_instance();

    // allocate memory for the scores
    hcp::gpu::cuda::error_check(hcp::gpu::cuda::device_allocate_async(this->survival, HISTOGRAM_SIZE * QCHUNK, driver->stream[DATA_STREAM]));
    hcp::gpu::cuda::error_check(hcp::gpu::cuda::device_allocate_async(this->topscore, QCHUNK, driver->stream[DATA_STREAM]));
    hcp::gpu::cuda::error_check(hcp::gpu::cuda::device_allocate_async(this->cpsms, QCHUNK, driver->stream[DATA_STREAM]));

    hcp::gpu::cuda::s3::resetdScores<<<256, 256, KBYTES(1), driver->stream[DATA_STREAM]>>>(this->survival, this->cpsms, this->topscore);

    driver->stream_sync(DATA_STREAM);
}

// -------------------------------------------------------------------------------------------- //

dScores::~dScores()
{
    auto driver = hcp::gpu::cuda::driver::get_instance();

    // free all memory
    if (this->survival)
    {
        hcp::gpu::cuda::error_check(hcp::gpu::cuda::device_free_async(this->survival, driver->stream[DATA_STREAM]));
        this->survival = nullptr;
    }

    if (this->topscore)
    {
        hcp::gpu::cuda::error_check(hcp::gpu::cuda::device_free_async(this->topscore, driver->stream[DATA_STREAM]));
        this->topscore = nullptr;
    }

    if (this->cpsms)
    {
        hcp::gpu::cuda::error_check(hcp::gpu::cuda::device_free_async(this->cpsms, driver->stream[DATA_STREAM]));
        this->cpsms = nullptr;
    }

    driver->stream_sync(DATA_STREAM);
}

// -------------------------------------------------------------------------------------------- //

template <typename T>
dQueries<T>::dQueries()
{
    auto driver = hcp::gpu::cuda::driver::get_instance();

    hcp::gpu::cuda::error_check(hcp::gpu::cuda::device_allocate_async(this->idx, QCHUNK+1, driver->stream[DATA_STREAM]));
    //hcp::gpu::cuda::error_check(hcp::gpu::cuda::device_allocate_async(this->precurse, QCHUNK, driver->stream[DATA_STREAM]));
    hcp::gpu::cuda::error_check(hcp::gpu::cuda::device_allocate_async(this->minlimits, QCHUNK, driver->stream[DATA_STREAM]));
    hcp::gpu::cuda::error_check(hcp::gpu::cuda::device_allocate_async(this->maxlimits, QCHUNK, driver->stream[DATA_STREAM]));
    hcp::gpu::cuda::error_check(hcp::gpu::cuda::device_allocate_async(this->moz, QCHUNK * QALEN, driver->stream[DATA_STREAM]));
    hcp::gpu::cuda::error_check(hcp::gpu::cuda::device_allocate_async(this->intensity, QCHUNK * QALEN, driver->stream[DATA_STREAM]));

    numPeaks        = 0;
    numSpecs        = 0;
}

// -------------------------------------------------------------------------------------------- //

template <typename T>
void dQueries<T>::H2D(Queries<T> *rhs)
{
    auto driver = hcp::gpu::cuda::driver::get_instance();
    int chunksize = rhs->numSpecs;

    this->numSpecs = rhs->numSpecs;
    this->numPeaks = rhs->numPeaks;

    hcp::gpu::cuda::error_check(hcp::gpu::cuda::H2D(this->moz, rhs->moz, this->numPeaks, driver->stream[DATA_STREAM]));
    hcp::gpu::cuda::error_check(hcp::gpu::cuda::H2D(this->intensity, rhs->intensity, this->numPeaks, driver->stream[DATA_STREAM]));
    hcp::gpu::cuda::error_check(hcp::gpu::cuda::H2D(this->idx, rhs->idx, chunksize+1, driver->stream[DATA_STREAM]));
    //hcp::gpu::cuda::error_check(hcp::gpu::cuda::H2D(this->precurse, rhs.precurse, chunksize, driver->stream[DATA_STREAM]));

    // driver->stream_sync(DATA_STREAM);
}

// -------------------------------------------------------------------------------------------- //

template <typename T>
dQueries<T>::~dQueries()
{
    auto driver = hcp::gpu::cuda::driver::get_instance();

    numPeaks = 0;
    numSpecs = 0;

    /* Deallocate the memory */
    if (this->moz != nullptr)
    {
        hcp::gpu::cuda::error_check(hcp::gpu::cuda::device_free_async(this->moz, driver->stream[DATA_STREAM]));
        this->moz = nullptr;
    }
    if (this->intensity != nullptr)
    {
        hcp::gpu::cuda::error_check(hcp::gpu::cuda::device_free_async(this->intensity, driver->stream[DATA_STREAM]));
        this->intensity = nullptr;
    }
    if (this->minlimits != nullptr)
    {
        hcp::gpu::cuda::error_check(hcp::gpu::cuda::device_free_async(this->minlimits, driver->stream[DATA_STREAM]));
        this->minlimits = nullptr;
    }
    if (this->maxlimits != nullptr)
    {
        hcp::gpu::cuda::error_check(hcp::gpu::cuda::device_free_async(this->maxlimits, driver->stream[DATA_STREAM]));
        this->maxlimits = nullptr;
    }

    if (this->idx != nullptr)
    {
        hcp::gpu::cuda::error_check(hcp::gpu::cuda::device_free_async(this->idx, driver->stream[DATA_STREAM]));
        this->idx = nullptr;
    }

    driver->stream_sync(DATA_STREAM);
}

// -------------------------------------------------------------------------------------------- //

__host__ status_t initialize()
{
    // static instance of the log(factorial(x)) array
    static auto h_lgfact = hcp::utils::lgfact<hcp::utils::maxshp>();

    // copy to CUDA constant arrays
    hcp::gpu::cuda::error_check(cudaMemcpyToSymbol(d_lgFact, &h_lgfact.val, sizeof(double_t) * hcp::utils::maxshp));

    return SLM_SUCCESS;

}

// -------------------------------------------------------------------------------------------- //

__global__ void reset_BYC(BYC *data, int N)
{
    int tid = blockIdx.x * blockDim.x + threadIdx.x;
    int stride = blockDim.x * gridDim.x;

    for (int i = tid; i < N; i += stride)
    {
        data[i].bc = 0;
        data[i].yc = 0;
        data[i].ibc = 0;
        data[i].iyc = 0;
    }
}

// -------------------------------------------------------------------------------------------- //

std::pair<BYC *, int>& getBYC(int chunksize)
{
    auto driver = hcp::gpu::cuda::driver::get_instance();

    static std::pair<BYC *, int> bycPair;
    static BYC *d_BYC = nullptr;
    static int maxchunk = 0;

    if (!d_BYC)
    {
        maxchunk = chunksize;

        if (!maxchunk)
            std::cout << "Error: getBYC: chunksize is zero" << std::endl;
        else
        {
            hcp::gpu::cuda::error_check(hcp::gpu::cuda::device_allocate_async<BYC>(d_BYC, maxchunk * SEARCHINSTANCES, driver->stream[DATA_STREAM]));

            const int nthreads = 1024;
            int nblocks = (maxchunk * SEARCHINSTANCES + nthreads-1) / nthreads;

            reset_BYC<<<nblocks, nthreads, KBYTES(1), driver->stream[DATA_STREAM]>>>(d_BYC, maxchunk * SEARCHINSTANCES);
        }
    }

    driver->stream_sync(DATA_STREAM);

    // update the pair
    bycPair = make_pair(d_BYC, maxchunk);

    // return the static pair
    return bycPair;
}

// -------------------------------------------------------------------------------------------- //

void freeBYC()
{
    auto driver = hcp::gpu::cuda::driver::get_instance();

    auto pBYC = getBYC();

    auto d_BYC = std::get<0>(pBYC);
    auto maxchunk = std::get<1>(pBYC);

    if (d_BYC)
        // free the d_Scores
        hcp::gpu::cuda::error_check(hcp::gpu::cuda::device_free_async(d_BYC, driver->stream[DATA_STREAM]));

    if (maxchunk)
        maxchunk = 0;

    driver->stream_sync(DATA_STREAM);

    // set to nullptr
    d_BYC = nullptr;
}

// -------------------------------------------------------------------------------------------- //

dScores *& getScorecard()
{
    auto driver = hcp::gpu::cuda::driver::get_instance();
    static dScores *d_Scores = nullptr;

    if (!d_Scores)
        d_Scores = new dScores();

    return d_Scores;
}

// -------------------------------------------------------------------------------------------- //

void freeScorecard()
{
    auto driver = hcp::gpu::cuda::driver::get_instance();

    auto&& d_Scores = getScorecard();

    if (d_Scores)
    {
        delete d_Scores;
        d_Scores = nullptr;
    }
}

// -------------------------------------------------------------------------------------------- //

__host__ dQueries<spectype_t> *& getdQueries()
{
    static thread_local dQueries<spectype_t> *dqueries = nullptr;

    if (!dqueries)
        dqueries = new dQueries<spectype_t>();

    return dqueries;
}

// -------------------------------------------------------------------------------------------- //

__host__ void freedQueries()
{
    auto &&dqueries = getdQueries();

    if (dqueries)
    {
        delete dqueries;
        dqueries = nullptr;
    }
}

// -------------------------------------------------------------------------------------------- //

// the database search kernel
__host__ status_t search(Queries<spectype_t> *gWorkPtr, Index *index, uint_t idxchunks, int gpucurrSpecID, hCell *CandidatePSMS)
{
    status_t status = SLM_SUCCESS;

    auto dqueries = getdQueries();

    // transfer experimental data to device
    dqueries->H2D(gWorkPtr);

    // get instance of the driver
    static thread_local auto driver = hcp::gpu::cuda::driver::get_instance();

    dIndex *d_Index = nullptr;

    if (params.gpuindex)
        d_Index = hcp::gpu::cuda::s1::getdIndex(index);

    // sync all data streams
    driver->stream_sync(DATA_STREAM);

    // search for each database chunk (by length)
    for (int i = 0; i < idxchunks; i++)
    {
        // get the current index portion (by length)
        Index *curr_index = &index[i];
        dIndex *curr_dindex = nullptr;

        // get the current index chunk if required
        if (params.gpuindex)
            curr_dindex = &d_Index[i];

        // FIXME: make min-max limits for the spectra in the current chunk
        status = hcp::gpu::cuda::s3::MinMaxLimits(gWorkPtr, curr_index, params.dM);

        uint_t speclen = (curr_index->pepIndex.peplen - 1) * params.maxz * iSERIES;

        // construct for each intra-chunk (within each length)
        for (int chno = 0; chno < curr_index->nChunks && status == SLM_SUCCESS; chno++)
        {
            spmat_t *d_mat;

            // check if full index at GPU
            if (params.gpuindex)
                // get the spmat_t for the current chunk
                d_mat = &curr_dindex->ionIndex[chno];
            else
            {
                if (false) // FIXME: reconstruct the ionIndex?
                {
                    // build the AT columns. i.e. the iAPtr
                    status = hcp::gpu::cuda::s1::ConstructIndexChunk(curr_index, chno, true);
                    d_mat->iA = hcp::gpu::cuda::s1::getATcols();
                }
                else
                {
                    /* Check if this chunk is the last chunk */
                    uint_t nsize = ((chno == curr_index->nChunks - 1) && (curr_index->nChunks > 1))?
                       curr_index->lastchunksize : curr_index->chunksize;

                    uint_t *iAPtr = curr_index->ionIndex[chno].iA;
                    uint_t iAsize = nsize * speclen;

                    // copy the At columns to the device instead
                    d_mat->iA = hcp::gpu::cuda::s1::getATcols(iAsize);

                    hcp::gpu::cuda::error_check(hcp::gpu::cuda::H2D(d_mat->iA, iAPtr, iAsize, driver->stream[DATA_STREAM]));
                }

                // copy the At rows to device
                d_mat->bA = hcp::gpu::cuda::s1::getbA();
                uint_t bAsize = ((uint_t)(params.max_mass * params.scale)) + 1;

                hcp::gpu::cuda::error_check(hcp::gpu::cuda::H2D(d_mat->bA, curr_index->ionIndex[chno].bA, bAsize, driver->stream[DATA_STREAM]));

                // synch both streams
                driver->stream_sync(DATA_STREAM);
            }

            // search against the database
            status = hcp::gpu::cuda::s3::SearchKernel(d_mat, gWorkPtr, speclen, i);

            // if chunked index then free AT columns
            if (!params.gpuindex)
                // free the AT columns
                hcp::gpu::cuda::s1::freeATcols();
        }
    }

    if (params.nodes > 1)
    {
#if defined (USE_MPI)
        static bool once = [](){ std::cout << "WARNING: Experimental support for GPU+MPI only. Problems expected." << std::endl; return true;}();
        status = hcp::gpu::cuda::s4::getIResults(index, gWorkPtr, gpucurrSpecID, CandidatePSMS);
#else
        std::cerr << "ABORT: params.nodes > 1 without MPI. Build with -DUSE_MPI=ON" << std::endl;
        exit(-1);
#endif // USE_MPI
    }
    else
        // combine the results
        status = hcp::gpu::cuda::s4::processResults(index, gWorkPtr, gpucurrSpecID);

    hcp::gpu::cuda::s3::reset_dScores();

    return status;
}

// -------------------------------------------------------------------------------------------- //

__host__ status_t MinMaxLimits(Queries<spectype_t> *h_WorkPtr, Index *index, double dM)
{
    status_t status = SLM_SUCCESS;
    auto driver = hcp::gpu::cuda::driver::get_instance();

    auto d_WorkPtr = getdQueries();

    // extract all peptide masses in an array to simplify computations
    float_t *h_mzs; // = new float_t[index->lcltotCnt];
    hcp::gpu::cuda::host_pinned_allocate<float_t>(h_mzs, index->lcltotCnt);

    // simplify the peptide masses
    for (int i = 0; i < index->lcltotCnt; i++)
        h_mzs[i] = index->pepEntries[i].Mass;

    auto size = index->lcltotCnt;

    // initialize device vector with mzs
    float *d_mzs = nullptr;
    hcp::gpu::cuda::error_check(hcp::gpu::cuda::device_allocate_async(d_mzs, size, driver->stream[SEARCH_STREAM]));
    hcp::gpu::cuda::error_check(hcp::gpu::cuda::H2D(d_mzs, h_mzs, size, driver->stream[SEARCH_STREAM]));

    float *d_precurse = nullptr;
    hcp::gpu::cuda::error_check(hcp::gpu::cuda::device_allocate_async(d_precurse, h_WorkPtr->numSpecs, driver->stream[SEARCH_STREAM]));
    hcp::gpu::cuda::error_check(hcp::gpu::cuda::H2D(d_precurse, h_WorkPtr->precurse, h_WorkPtr->numSpecs, driver->stream[SEARCH_STREAM]));

    const int nthreads = 1024;
    int nblocks = h_WorkPtr->numSpecs / nthreads;
    nblocks += (h_WorkPtr->numSpecs % nthreads == 0)? 0 : 1;

    // add -dM to set for minlimit
    hcp::gpu::cuda::s3::vector_plus_constant<<<nblocks, nthreads, KBYTES(1), driver->get_stream(SEARCH_STREAM)>>>(d_precurse, (float)(-dM), h_WorkPtr->numSpecs);

    // binary search the start of each ion and store in minlimits
    thrust::lower_bound(thrust::device.on(driver->get_stream(SEARCH_STREAM)), d_mzs, d_mzs + size, d_precurse, d_precurse + h_WorkPtr->numSpecs, d_WorkPtr->minlimits);

    // add -dM to set for minlimit
    hcp::gpu::cuda::s3::vector_plus_constant<<<nblocks, nthreads, KBYTES(1), driver->get_stream(SEARCH_STREAM)>>>(d_precurse, (float)(2*dM), h_WorkPtr->numSpecs);

    // binary search the end of each spectrum and store in maxlimits
    thrust::upper_bound(thrust::device.on(driver->get_stream(SEARCH_STREAM)), d_mzs, d_mzs + size, d_precurse, d_precurse + h_WorkPtr->numSpecs, d_WorkPtr->maxlimits);

    // d_mzs is no longer needed - free
    hcp::gpu::cuda::error_check(hcp::gpu::cuda::device_free_async(d_mzs, driver->stream[SEARCH_STREAM]));
    hcp::gpu::cuda::error_check(hcp::gpu::cuda::device_free_async(d_precurse, driver->stream[SEARCH_STREAM]));

    // free the mzs array
    hcp::gpu::cuda::host_pinned_free(h_mzs);

    return status;
}

// -------------------------------------------------------------------------------------------- //

__host__ status_t SearchKernel(spmat_t *mat, Queries<spectype_t> *gWorkPtr, int speclen, int ixx)
{
    status_t status = SLM_SUCCESS;

    auto d_WorkPtr = getdQueries();

    // number of spectra in the current batch
    int nspectra = gWorkPtr->numSpecs;

    auto d_iA = mat->iA;
    auto d_bA = mat->bA;

    // get driver object
    auto driver = hcp::gpu::cuda::driver::get_instance();

    const int itersize = SEARCHINSTANCES;

    int niters = nspectra / itersize;
    niters += (nspectra % itersize == 0)? 0 : 1;

    // get resPtr instance
    auto d_Scores = hcp::gpu::cuda::s3::getScorecard();

    // get BYC scorecard
    auto pBYC = hcp::gpu::cuda::s3::getBYC();

    auto d_BYC = std::get<0>(pBYC);
    auto maxchunk = std::get<1>(pBYC);

    // block size is 512 for open-search
    int blocksize = 512;

    // set block size to 320 for closed-search
    if (params.dM < 50)
        blocksize = 320;

    // calculate shmembytes needed
    int shmembytes = std::max((unsigned long)HISTOGRAM_SIZE, (sizeof(BYC) + sizeof(double)) * blocksize);

    // set the shared memory to 16KB
    cudaFuncSetAttribute(SpSpGEMM, cudaFuncAttributeMaxDynamicSharedMemorySize, KBYTES(16));

    for (int iter = 0 ; iter < niters ; iter++)
    {
        int nblocks = itersize;

        // if last iteration, adjust the number of blocks
        if (iter == niters - 1)
            nblocks = nspectra - iter * itersize;

        hcp::gpu::cuda::s3::SpSpGEMM<<<nblocks, blocksize, shmembytes, driver->stream[SEARCH_STREAM]>>>(d_WorkPtr->moz, d_WorkPtr->intensity, d_WorkPtr->idx, d_WorkPtr->minlimits, d_WorkPtr->maxlimits, d_bA, d_iA, iter * itersize, d_BYC, maxchunk, d_Scores->survival, d_Scores->cpsms, d_Scores->topscore, params.dF, speclen, params.max_mass, params.scale, params.min_shp, ixx);

        // synchronize the stream
        driver->stream_sync(SEARCH_STREAM);
    }

    MARK_END(SpSpGEMM);

    return status;
}

// -------------------------------------------------------------------------------------------- //

__host__ void reset_dScores()
{
    auto d_Scores = hcp::gpu::cuda::s3::getScorecard();

    // get driver object
    auto driver = hcp::gpu::cuda::driver::get_instance();

    // reset the scorecard
    hcp::gpu::cuda::s3::resetdScores<<<256, 256, KBYTES(1), driver->stream[SEARCH_STREAM]>>>(d_Scores->survival, d_Scores->cpsms, d_Scores->topscore);

    driver->stream_sync(SEARCH_STREAM);
}

// -------------------------------------------------------------------------------------------- //

__global__ void resetdScores(double *survival, int *cpsms, dhCell *topscore)
{
    int tid = threadIdx.x + blockIdx.x * blockDim.x;
    int stride = blockDim.x * gridDim.x;

    for (int ik = tid; ik < QCHUNK * HISTOGRAM_SIZE; ik+=stride)
        survival[ik] = 0;

    for (int ik = tid; ik < QCHUNK; ik+=stride)
    {
        cpsms[ik] = 0;
        topscore[ik].hyperscore = 0;
        topscore[ik].psid = 0;
        topscore[ik].idxoffset = 0;
        topscore[ik].sharedions = 0;
    }
}

// -------------------------------------------------------------------------------------------- //

__global__ void SpSpGEMM(spectype_t *dQ_moz, spectype_t *dQ_intensity, uint_t *dQ_idx, int *dQ_minlimits,
                         int *dQ_maxlimits, uint_t* d_bA, uint_t *d_iA, int iter, BYC *bycP,
                         int maxchunk, double *d_survival, int *d_cpsms, dhCell *d_topscore, int dF,
                         int speclen, int maxmass, int scale, short min_shp, int ixx)
{
    BYC *bycPtr = &bycP[blockIdx.x * maxchunk];

    // get spectrum data
    int qnum = iter + blockIdx.x;

    auto *survival = &d_survival[qnum * HISTOGRAM_SIZE];
    auto *cpsms = d_cpsms + qnum;

    auto *QAPtr = dQ_moz + dQ_idx[qnum];
    auto *iPtr = dQ_intensity + dQ_idx[qnum];
    int qspeclen = dQ_idx[qnum + 1] - dQ_idx[qnum];
    int halfspeclen = speclen / 2;

    int minlimit = dQ_minlimits[qnum];
    int maxlimit = dQ_maxlimits[qnum] - 1; // maxlimit = upper_bound - 1

    // if maxlimit < minlimit then no point, just return
    if (maxlimit < minlimit)
        return;

    // shared memory
    extern __shared__ int shmem[];


    // keys = ppid, vals = BYC for reduction
    int *keys    = &shmem[0];
    BYC *vals    = (BYC*)&keys[blockDim.x];

    // setup shared memory here
    __syncthreads();


    // iterate over all ions
    for (int k = 0; k < qspeclen; k++)
    {
        uint_t intn = iPtr[k];
        auto qion = QAPtr[k];

        // ion +-dF
        for (auto bin = qion - dF; bin < qion + 1 + dF; bin++)
        {
            if (qion <= dF || qion >= ((maxmass * scale) - 1 - dF))
                continue;

            auto data = d_iA + d_bA[bin];

            int n = d_bA[bin + 1] - d_bA[bin];

            /* If no ions in the bin */
            if (n < 1)
                continue;

            int off1 = lower_bound(data, n, (uint_t)(minlimit * speclen)) - data;
            int off2 = upper_bound(data, n, (uint_t)(((maxlimit + 1) * speclen) - 1)) - data;

            int stt = d_bA[bin] + off1;
            int ends = d_bA[bin] + off2;

            int nions = ends - stt + 1;
            int ioniters = nions / blockDim.x;
            ioniters += (nions % blockDim.x) ? 1 : 0;

            int itnum = 0;

            //
            // fragment ion search loop
            //
            for (int ion = stt + threadIdx.x; itnum < ioniters; ion+= blockDim.x, itnum++)
            {
                int myKey = 0;
                BYC *myVal = nullptr;

                if (ion <= ends)
                {
                    uint_t raw = d_iA[ion];

                    /* Calculate the residue (raw % speclen) and isY */
                    short isY = (((raw % speclen)) / halfspeclen);

                    // key = parent peptide ID
                    myKey = (raw / speclen);

                    // write to keys
                    keys[threadIdx.x] = myKey;

                    /* Get the map element */
                    myVal = &vals[threadIdx.x];
                    myVal->bc = (1 - isY);
                    myVal->ibc = intn * (1 - isY);
                    myVal->yc = isY;
                    myVal->iyc = intn * isY;
                }

                __syncthreads();

                //
                // reduce the BYC elements to avoid
                // race conditions and locking
                //

                // number of active threads
                int activethds = min(blockDim.x, ends - ion + threadIdx.x + 1);

                short iters = hcp::gpu::cuda::s1::log2ceil(activethds);

                // is this thread a part of a localized group (and not group leader)
                bool isGroup = false;

                // threadIdx.x is always the leader
                if (threadIdx.x > 0)
                    isGroup = (myKey == keys[threadIdx.x - 1]) || (threadIdx.x >= activethds);

                // the reduction loop by all threads
                for (int ij = 0; ij < iters; ij++)
                {
                    int offset = 1 << ij;

                    int newKey = 0;
                    BYC newVal;

                    // exchange values
                    if (threadIdx.x < (activethds - offset))
                    {
                        int idx = threadIdx.x + offset;
                        newKey = keys[idx];

                        // if the keys match, get the new value
                        if (newKey == myKey)
                        {
                            newVal.bc = vals[idx].bc;
                            newVal.ibc = vals[idx].ibc;
                            newVal.yc = vals[idx].yc;
                            newVal.iyc = vals[idx].iyc;
                        }
                    }

                    __syncthreads();

                    // write the sum to the shm
                    if (threadIdx.x < (activethds - offset))
                    {
                        if (newKey == myKey)
                        {
                            myVal->bc += newVal.bc;
                            myVal->ibc += newVal.ibc;
                            myVal->yc += newVal.yc;
                            myVal->iyc += newVal.iyc;
                        }
                    }

                    // sync threads
                    __syncthreads();
                }

                // only write to global memory if no group or the leader
                if (!isGroup)
                {
                    BYC *glob = &bycPtr[myKey];
                    glob->bc += myVal->bc;
                    glob->ibc += myVal->ibc;
                    glob->yc += myVal->yc;
                    glob->iyc += myVal->iyc;
                }
            }

            // synchronize
            __syncthreads();
        }
    }

    // reuse the shared memory
    int *histogram = &shmem[0];

    // initialize
    for (int ij = threadIdx.x; ij < HISTOGRAM_SIZE; ij+=blockDim.x)
        histogram[ij] = 0;

    // wait for shmem to be initialized
    __syncthreads();

    // thread local variable to store topscores
    dhCell topscores;

    topscores.hyperscore = 0;
    topscores.psid = 0;
    topscores.idxoffset = 0;
    topscores.sharedions = 0;

    // thread local variable to store ncpsms
    int cpss = 0;

    /* Look for candidate PSMs */
    for (int_t it = minlimit + threadIdx.x; it <= maxlimit; it+= blockDim.x)
    {
        ushort_t bcc = bycPtr[it].bc;
        ushort_t ycc = bycPtr[it].yc;
        ushort_t shpk = bcc + ycc;

        // filter by the min shared peaks
        if (shpk >= min_shp)
        {
            // get the precomputed log(factorial(x))

            double_t hyperscore = d_lgFact[bcc] + d_lgFact[ycc] + log10f(1 + bycPtr[it].ibc) + log10f(1 + bycPtr[it].iyc) - 4;

            // hyperscore < 0 means either b- or y- ions were not matched
            if (hyperscore > 0)
            {
                if (hyperscore >= MAX_HYPERSCORE)
                    hyperscore = MAX_HYPERSCORE - 1;

                // increment local candidate psms by +1
                cpss +=1;

                // Update the histogram
                atomicAdd(&histogram[(int)(hyperscore * 10 + 0.5)], 1);

                if (hyperscore > topscores.hyperscore)
                {
                    topscores.hyperscore = hyperscore;
                    topscores.psid       = it;
                    topscores.idxoffset  = ixx;
                    topscores.sharedions = shpk;
                }
            }
        }
    }

    __syncthreads();

    dhCell l_topscore;

    // get max dhcell
    hcp::gpu::cuda::s3::getMaxdhCell(topscores, l_topscore);

    __syncthreads();

    // write the max dhcell to global memory
    if (!threadIdx.x && (l_topscore.hyperscore > d_topscore[qnum].hyperscore))
    {
        d_topscore[qnum].hyperscore = l_topscore.hyperscore;
        d_topscore[qnum].psid       = l_topscore.psid;
        d_topscore[qnum].idxoffset  = l_topscore.idxoffset;
        d_topscore[qnum].sharedions = l_topscore.sharedions;
    }

    // local candidate psms
    int l_cpsms = 0;

    // sum the local cpsms to get the count
    hcp::gpu::cuda::s3::blockSum(cpss, l_cpsms);

    // add to the global memory sum
    if (!threadIdx.x)
        *cpsms = *cpsms + l_cpsms;

    // need this to avoid race conditions
    __syncthreads();

    // copy histogram to the global memory
    for (int ii = threadIdx.x; ii < HISTOGRAM_SIZE; ii+=blockDim.x)
        survival[ii] += histogram[ii];

    // need this to avoid race conditions
    __syncthreads();

    // reset the bycPtr
    for (int f = minlimit + threadIdx.x; f <= maxlimit; f += blockDim.x)
    {
        bycPtr[f].bc = 0;
        bycPtr[f].yc = 0;
        bycPtr[f].ibc = 0;
        bycPtr[f].iyc = 0;
    }

    return;
}

// -------------------------------------------------------------------------------------------- //

template <typename T>
__global__ void vector_plus_constant(T *vect, T val, int size)
{
    for (int i = blockIdx.x * blockDim.x + threadIdx.x; i < size; i += blockDim.x * gridDim.x)
        vect[i] += val;
}

// -------------------------------------------------------------------------------------------- //

status_t deinitialize()
{
    // free the memory if allocated
    hcp::gpu::cuda::s1::freedIndex();
    hcp::gpu::cuda::s1::freeATcols();
    hcp::gpu::cuda::s1::freeFragIon();
    hcp::gpu::cuda::s1::freebA();

    freedQueries();

    hcp::gpu::cuda::s4::freed_eValues();

    // sync all streams
    hcp::gpu::cuda::driver::get_instance()->all_streams_sync();

    return SLM_SUCCESS;
}

// -------------------------------------------------------------------------------------------- //

} // namespace s3

} // namespace cuda

} // namespace gpu

} // namespace hcp