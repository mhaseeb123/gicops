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

#pragma once

#include <iostream>
#include <cuda.h>

namespace hcp
{
namespace gpu
{
namespace cuda
{

#define error_check(ans)                   check((ans), __FILE__, __LINE__)
#define STREAMS_THREAD                     4

// ------------------------------------------------------------------------------------ //

// error checking function
template <typename T>
static inline void check(T result, const char *const file, const int line, bool is_fatal = true)
{
    if (result != cudaSuccess)
    {
        std::cerr << "CUDA error at " << file << ":" << line << std::endl;
        std::cerr << cudaGetErrorString(result) << std::endl;

        if (is_fatal)
            exit(result);
    }
}

// ------------------------------------------------------------------------------------ //

struct gpu_manager
{
    int ngpus = 0;

    gpu_manager()
    {
        error_check(cudaGetDeviceCount(&ngpus));
        std::cout << "MANAGER: Available Devices: " << ngpus << std::endl;
    }

    int gpu_id()
    {
        int gpu_id = 0;
        error_check(cudaGetDevice(&gpu_id));
        return gpu_id;
    }

    static gpu_manager& get_instance()
    {
        static gpu_manager instance;
        return instance;
    }
};

// ------------------------------------------------------------------------------------ //

// class driver
class driver
{
public:

    cudaStream_t stream[STREAMS_THREAD];
    cudaEvent_t d2h;
    cudaEvent_t h2d;
    cudaEvent_t kernel1;
    cudaEvent_t kernel2;

    // ------------------------------------------------------------------------------------ //
    
    driver()
    {
        auto manager = gpu_manager::get_instance();
        error_check(cudaSetDevice(manager.gpu_id()));
        std::cout << "DRIVER: Setting Device to: " << manager.gpu_id() << std::endl;

        for (int i = 0; i < STREAMS_THREAD; i++)
            error_check(cudaStreamCreateWithFlags(&stream[i], cudaStreamNonBlocking));
        
        error_check(cudaEventCreateWithFlags(&d2h, cudaEventBlockingSync));
        error_check(cudaEventCreateWithFlags(&kernel1, cudaEventBlockingSync));
        error_check(cudaEventCreateWithFlags(&kernel2, cudaEventBlockingSync));
    }

    // ------------------------------------------------------------------------------------ //
    ~driver()
    {
        for (int i = 0; i < STREAMS_THREAD; i++)
            error_check(cudaStreamDestroy(stream[i]));

        error_check(cudaEventDestroy(d2h));
        error_check(cudaEventDestroy(kernel1));
        error_check(cudaEventDestroy(kernel2));
    }

    // ------------------------------------------------------------------------------------ //

    void stream_sync(int i = 0)
    {
        error_check(cudaStreamSynchronize(stream[i]));
    }

    // ------------------------------------------------------------------------------------ //

    void all_streams_sync()
    {
        for (int i = 0; i < STREAMS_THREAD; i++)
            error_check(cudaStreamSynchronize(stream[i]));
    }

    // ------------------------------------------------------------------------------------ //

    void event_sync(cudaEvent_t &event)
    {
        error_check(cudaEventSynchronize(event));
    }

    // ------------------------------------------------------------------------------------ //

    bool event_query(cudaEvent_t &event)
    {
        auto status = cudaEventQuery(event);

        if (status == cudaSuccess)
            return true;
        else if (status == cudaErrorNotReady)
            return false;
        else
            error_check(status);

        return false;
    }

    // ------------------------------------------------------------------------------------ //

    auto& get_stream(int i = 0) const
    {
        return stream[i];
    }

    // ------------------------------------------------------------------------------------ //

    // We can have multiple concurrent resident kernels 
    // per device depending on device compute capability
    static driver* get_instance()
    {
        static driver instance;
        return &instance;
    }
};

// ------------------------------------------------------------------------------------ //

// CUDA driver functions
template <typename T>
auto H2D(T *&dst, T *&src, const size_t size, const cudaStream_t &stream)
{
    return cudaMemcpyAsync(dst, src, size * sizeof(T), cudaMemcpyHostToDevice, stream);
}

// ------------------------------------------------------------------------------------ //

template <typename T>
auto H2D_withEvent(T *&dst,  T *&src, const size_t size, const cudaStream_t &stream)
{
    auto drv = driver::get_instance();
    cudaMemcpyAsync(dst, src, size * sizeof(T), cudaMemcpyHostToDevice, stream);
    return cudaEventRecord(drv->h2d, stream);
}

// ------------------------------------------------------------------------------------ //

template <typename T>
auto D2H(T *&dst, T *&src, const size_t size, const cudaStream_t &stream)
{
    return cudaMemcpyAsync(dst, src, size * sizeof(T), cudaMemcpyDeviceToHost, stream);
}

// ------------------------------------------------------------------------------------ //

template <typename T>
auto D2H_withEvent(T *&dst, T *&src, const size_t size, const  cudaStream_t &stream)
{
    auto drv = driver::get_instance();
    cudaMemcpyAsync(dst, src, size * sizeof(T), cudaMemcpyDeviceToHost, stream);
    return cudaEventRecord(drv->d2h, stream);
}

// ------------------------------------------------------------------------------------ //

template <typename T>
auto D2D(T *&dst, T *&src, const size_t size, const cudaStream_t &stream)
{
    return cudaMemcpyAsync(dst, src, size * sizeof(T), cudaMemcpyDeviceToDevice, stream);
}

// ------------------------------------------------------------------------------------ //

template <typename T>
auto host_pinned_allocate(T *&ptr, size_t size)
{
    return cudaMallocHost(&ptr, size * sizeof(T));
}

// ------------------------------------------------------------------------------------ //

template <typename T>
auto device_allocate(T *&ptr, size_t size)
{
    return cudaMalloc(&ptr, size * sizeof(T));
}

// ------------------------------------------------------------------------------------ //

template <typename T>
auto device_allocate_async(T *&ptr, size_t size, const cudaStream_t &stream)
{
    return cudaMallocAsync(&ptr, size * sizeof(T), stream);
}

// ------------------------------------------------------------------------------------ //

template <typename T>
auto host_pinned_free(T *&ptr)
{
    return cudaFreeHost(ptr);
    ptr = nullptr;
}

// ------------------------------------------------------------------------------------ //

template <typename T>
auto device_free(T *&ptr)
{
    return cudaFree(ptr);
    ptr = nullptr;
}

// ------------------------------------------------------------------------------------ //

template <typename T>
auto device_free_async(T *&ptr, const cudaStream_t &stream)
{
    return cudaFreeAsync(ptr, stream);
}

}; //namespace cuda

}; // namespace gpu

}; // namespace hcp