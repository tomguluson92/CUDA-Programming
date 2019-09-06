#include "error.cuh"
#include <stdio.h>
#ifdef USE_DP
    typedef double real;
#else
    typedef float real;
#endif
real reduce(real *x, int N, int K);

int main(int argc, char **argv)
{
    int K = atoi(argv[1]);
    int N = 100000000;
    int M = sizeof(real) * N;
    real *h_x = (real *)malloc(M);
    for (int n = 0; n < N; ++n) { h_x[n] = 1.0; }
    real *x;
    CHECK(cudaMalloc(&x, M))
    CHECK(cudaMemcpy(x, h_x, M, cudaMemcpyHostToDevice))

    real sum = reduce(x, N, K);
    printf("sum = %g.\n", sum);

    free(h_x);
    CHECK(cudaFree(x))
    return 0;
}

void __global__ reduce_1
(real *g_x, real *g_y, int N, int number_of_rounds)
{
    int tid = threadIdx.x;
    int bid = blockIdx.x;

    real y = 0.0;
    int offset = tid + bid * blockDim.x * number_of_rounds;
    for (int round = 0; round < number_of_rounds; ++round)
    {
        int n = round * blockDim.x + offset;
        if (n < N) { y += g_x[n]; }
    }

    #define FULL_MASK 0xffffffff
    for (int offset = warpSize >> 1; offset > 0; offset >>= 1)
    y += __shfl_down_sync(FULL_MASK, y, offset);

    int lane_id = tid % warpSize;
    if (lane_id == 0) { atomicAdd(g_y, y); }
}

real reduce(real *x, int N, int K)
{
    int block_size = 128;
    int grid_size = (N - 1) / (block_size * K) + 1;

    real *h_sum = (real *)malloc(sizeof(real));
    h_sum[0] = 0.0;
    real *sum;
    CHECK(cudaMalloc(&sum, sizeof(real)))
    CHECK(cudaMemcpy(sum, h_sum, sizeof(real), 
        cudaMemcpyHostToDevice))

    reduce_1<<<grid_size, block_size>>>(x, sum, N, K);

    CHECK(cudaMemcpy(h_sum, sum, sizeof(real), 
        cudaMemcpyDeviceToHost))
    real result = h_sum[0];

    free(h_sum);
    CHECK(cudaFree(sum))
    return result;
}

