#include <sstream>
#include <iostream>
#include <stdio.h>
#include <cstdlib> 
#include <cuda_runtime_api.h>
#include <malloc.h>
#include <curand.h>
#include <cublas_v2.h>
#include <gmp.h>
#include <gmpxx.h>
#include <cstdlib>
#include <time.h>
#include <sys/time.h>
#include "omp.h"
#include <bitset>
#include <math.h>
#include <boost/numeric/ublas/matrix.hpp>
#include <boost/numeric/ublas/operation.hpp>
#include <boost/numeric/ublas/io.hpp> 
#define uS_PER_SEC 1000000
#define uS_PER_mS 1000

typedef boost::numeric::ublas::matrix<double> matrix;

using std::cout;
using std::endl;

const int INT64L = 64;
const int DOUBLE_MANT = 53;

mpf_class *tmpC1, *tmpC2, *tmpC3, *tmpC4, *tmpC5;

int getSign(const mpf_class a) {
  if((a.get_mpf_t()->_mp_size) < 0) {return -1;}
  else {return 1;}
}

//Print matrix A(nr_rows_A, nr_cols_A) storage in column-major format                                                 
void print_matrix_long(const long long *A, int nr_rows_A, int nr_cols_A) {

  for(int i = 0; i < nr_rows_A; ++i){
    for(int j = 0; j < nr_cols_A; ++j){
      std::cout << A[j * nr_rows_A + i] << " ";
    }
    std::cout << std::endl;
  }
  std::cout << std::endl;
}

void print_matrix_double(const double *A, int nr_rows_A, int nr_cols_A) {

  for(int i = 0; i < nr_rows_A; ++i){
    for(int j = 0; j < nr_cols_A; ++j){
      std::cout << (long long) A[j * nr_rows_A + i] << " ";
    }
    std::cout << std::endl;
  }
  std::cout << std::endl;
}

//Extracts up to 64 bits of one 64-bit variable (extractForm) starting from position1 up to position2                                                      
long long getBitsFromOneLong(const long long extractFrom, const int position1, const int position2) {
  assert(position1 <= position2);
  assert(INT64L >= position2);
  unsigned long long mask;
  if(position2 - position1 == INT64L) {mask = -1;} else {
    mask = ((1LL << (position2 - position1)) - 1) << (INT64L - position2);
  }
  return ((mask & extractFrom) >> (INT64L - position2));
}

//Extracts up to 64 bits of two 64-bits variables (extractFromA & extractFromB) starting from position1 up to position2                                    
long long getBitsFromTwoLong(const long long extractFromA, const long long extractFromB, const int position1, const int position2) {
  assert(position2 <= position1);
  return (getBitsFromOneLong(extractFromA, position1, INT64L) << position2)|(getBitsFromOneLong(extractFromB, 0, position2));
}

 
// Generates an array of 64-bit variables from mpf_class where each 64-bit variable have a maximum number of bits maxBits  
// The returned array of 64-bit variables is padded as if the exponent of the mpf_class variable is maxExp
void toBit(const long long a) {
  std::bitset<64> tmp(a);
  std::cout << tmp << std::endl;
}


// TODO: Eventually decouple allocation from calculation
//
void generateLongsFromGMP(const mpf_class a, long long *&x, int &sizeOfArray, const int ownLimbSize, const int padExp) {
  int size = abs(a.get_mpf_t()->_mp_size); 
  // WARNING: _mp_exp is number of limbs, not actual exponent!
  // TODO: Test the fix below
  int realExp = a.get_mpf_t()->_mp_exp * INT64L;
  int padding = (padExp - realExp) / ownLimbSize;
  int padBitOffset = (padExp - realExp) % ownLimbSize;
  int sign  = getSign(a);

  // Assert that the padding will work and that the maximumBitSize is given appropraitely 
  assert(realExp <= padExp);
  assert(ownLimbSize <= INT64L);

  // Find size of needed 64-bit variable array with padding and allocate it in memory
  sizeOfArray = (INT64L * size + (padExp - realExp)) / ownLimbSize;
  
  if ((INT64L * size + (padExp - realExp)) % ownLimbSize != 0) sizeOfArray += 1; 
  x = (long long *)malloc(sizeOfArray * sizeof(long long));
  
  // Add padding
  // Note that GMP stores the most significant digits of a number in _mp_d[size - 1]
  // That's why we start iterating the array of limbs in reverse
  for (int i = 0; i < padding; i++) x[i] = 0; 
  
  long long tmp  = a.get_mpf_t()->_mp_d[size - 1];
  x[padding] = sign * getBitsFromOneLong(tmp, 0, ownLimbSize - padBitOffset);
  
  // Add all the elements in mpf_class to the result
  for (int i = padding + 1; i < sizeOfArray - 1; i++) {
    int leftGmpLimb  = size - 1 - (((i - padding) * ownLimbSize - padBitOffset) / INT64L);
    int leftBit      = ((i - padding) * ownLimbSize - padBitOffset) % INT64L;
    int rightGmpLimb = size - 1 - (((i - padding + 1) * ownLimbSize - padBitOffset) / INT64L);
    int rightBit     = ((i - padding + 1) * ownLimbSize - padBitOffset) % INT64L;
    // If true it means that all the bits are in the same limb. If flase it means that all the 
    // bits are in consecutive limbs.
    if (leftGmpLimb == rightGmpLimb) {
      long long tmp  = a.get_mpf_t()->_mp_d[leftGmpLimb];
      x[i] = sign * getBitsFromOneLong(tmp, leftBit, rightBit);
    } else {
      long long tmpA = a.get_mpf_t()->_mp_d[leftGmpLimb];
      long long tmpB = a.get_mpf_t()->_mp_d[rightGmpLimb];
      x[i] = sign * getBitsFromTwoLong(tmpA, tmpB, leftBit, rightBit);
    }
  }
  int leftBit = ((sizeOfArray - padding - 1) * ownLimbSize + padBitOffset) % INT64L;
  tmp = a.get_mpf_t()->_mp_d[0];
  x[sizeOfArray - 1] = sign * getBitsFromOneLong(tmp, leftBit, INT64L);

  // TODO: Multiply longs by overall sign
}




// THIS HAS NOT BEEN TESTED YET
// TODO: decouple memory allocation from calculation eventually
void generateLongMatrixFromGMPMatrix(const mpf_class *a, long long **&x,int &sizeOfArray, const int nr_rows, const int nr_cols, int &exp, const int ownLimbSize) {
  // Allocate memory for pointers that point to each element in matrix and to the array 
  // that gives the number of own limbs for each matrix element
  long long **tmpX;
  int *lengthOwnLimbs; 
  tmpX = (long long **) malloc( nr_rows * nr_cols * sizeof( long * ));
  lengthOwnLimbs = (int *) malloc( nr_rows * nr_cols * sizeof(int));
  
  // Find maximum exponent in matrix
  int maxExp = a[0].get_mpf_t()->_mp_exp;
  for(int i = 0; i < nr_rows; ++i)
    for(int j = 0; j < nr_cols; ++j) {
      int toCmp =  a[j * nr_rows + i].get_mpf_t()->_mp_exp;
      if (toCmp > maxExp) maxExp = toCmp;
    }
  exp = maxExp * INT64L;
  
  // Generate the array of 64-bit matrices
  long minLengthOwnLimbs = LLONG_MAX;
  for(int i = 0; i < nr_rows; ++i)
    for(int j = 0; j < nr_cols; ++j) {
      generateLongsFromGMP(a[j * nr_rows + i], tmpX[j * nr_rows + i], lengthOwnLimbs[j * nr_rows + i], ownLimbSize, maxExp); 
      if (minLengthOwnLimbs > lengthOwnLimbs[j * nr_rows + i]) minLengthOwnLimbs = lengthOwnLimbs[j * nr_rows + i];
    }
  
  // Allocate the memory for the set of matrices (make all elements have the same length) such that 
  // elements of the matrices are closer in memory 
  // This might need to be rethough
  sizeOfArray = minLengthOwnLimbs;
  x = (long long **)malloc(minLengthOwnLimbs * sizeof *x);
  for(int k = 0; k < sizeOfArray; k++)
    x[k] = (long long *) malloc(nr_rows * nr_cols * sizeof **x);
  
  for(int k = 0; k < sizeOfArray; k++)
    for(int i = 0; i < nr_rows; i++)
      for(int j = 0; j < nr_cols; j++) {
	x[k][j * nr_rows + i] = tmpX[j * nr_rows + i][k];
      }
  free(tmpX);
  free(lengthOwnLimbs);
}
 
// This can be WAAAAAAY more optimized 
// Right now I think it takes time d^2 N^2. 
// It should take time N^2

// TODO: Add initialization functions for mpf_t's
// TODO: Maybe do bitwise operations and carry's by hand?
// Now tested: Seems to work!
mpf_class addToGMP(const mpf_class a, const long long toAdd, const int bitToAdd) {
  mpf_t tmpDiv;
  mpf_init(tmpDiv);
  if(bitToAdd < 0) {
    mpf_mul_2exp(tmpDiv, a.get_mpf_t(), abs(bitToAdd));
  } else {
    mpf_div_2exp(tmpDiv, a.get_mpf_t(), bitToAdd);
  }
  mpf_t tmpAdd;
  mpf_init(tmpAdd);
  mpf_add_ui(tmpAdd, tmpDiv, toAdd);
  mpf_t tmpMul;
  mpf_init(tmpMul);
  if (bitToAdd < 0) {
    mpf_div_2exp(tmpMul, tmpAdd, abs(bitToAdd));
  } else {
    mpf_mul_2exp(tmpMul, tmpAdd, bitToAdd);
  }
  return(mpf_class (tmpMul));
}


// Set a = a + b * 2^bitOffset. 
void addToMpf(mpf_t a, const long long b, const int bitOffset) {
  // bitOffset = limbOffset * GMP_NUMB_BITS + bitShift
  int limbOffset = bitOffset / GMP_NUMB_BITS;
  int bitShift   = bitOffset % GMP_NUMB_BITS;
  // ensure bitShift is positive
  if (bitShift < 0) {
    limbOffset -= 1;
    bitShift += GMP_NUMB_BITS;
  }

  unsigned long long bAbs = abs(b);

  // Let 2^GMP_NUMB_BITS = N. We would like to add/subtract
  // 
  //   bAbs * 2^bitOffset = (bAbs * 2^bitShift) * N^limbOffset
  //
  // So we write
  // 
  //   bAbs * 2^bitShift = head * 2^GMP_NUMB_BITS + tail
  unsigned long long head = bAbs >> (GMP_NUMB_BITS - bitShift);
  unsigned long long tail = bAbs << bitShift;

  // We now set
  //
  // a = ((a * N^(-limbOffset - 1) + head) * N + tail) * N^limbOffset
  //

  // a *= N^(-limbOffset - 1)
  a->_mp_exp -= limbOffset + 1;

  // a += head
  if (b > 0) {
    mpf_add_ui(a, a, head);
  } else {
    mpf_sub_ui(a, a, head);
  }

  // a *= N
  a->_mp_exp += 1;

  // a += tail
  if (b > 0) {
    mpf_add_ui(a, a, tail);
  } else {
    mpf_sub_ui(a, a, tail);
  }

  // a *= N^limbOffset
  a->_mp_exp += limbOffset;
}

void addToGMPMatrix(mpf_class *a, const long long *toAdd, const int nr_rows, const int nr_cols, const int bitToAdd) {
  #pragma omp parallel for schedule(dynamic)  
  for(int i = 0; i < nr_rows; ++i) {
    for(int j = 0; j < nr_cols; ++j) {
      addToMpf(a[j * nr_rows +  i].get_mpf_t(), toAdd[j * nr_rows +  i], bitToAdd);
      //a[j * nr_rows +  i] = addToGMP( a[j * nr_rows +  i], toAdd[j * nr_rows +  i], bitToAdd);
    }
  }
}

void addToGMPMatrixSymm(mpf_class *a, const long long *toAdd, const int nr_rows, const int bitToAdd) {
  #pragma omp parallel for schedule(dynamic)  
  for(int i = 0; i < nr_rows; ++i) {
    for(int j = 0; j <= i; ++j) {
      addToMpf(a[j * nr_rows +  i].get_mpf_t(), toAdd[j * nr_rows +  i], bitToAdd);
      //a[j * nr_rows +  i] = addToGMP( a[j * nr_rows +  i], toAdd[j * nr_rows +  i], bitToAdd);
    }
  }
}

// NOT TESTED
void longToGMP(mpf_class &a, const long long *toAdd, const int size_toAdd, const int ownLimbSize, const int whereWeStart) {
  // Is the precision a global variable?... I assume so?
  a = mpf_class("0.0");
  for (int i = 0; i < size_toAdd; i++) {
    a = addToGMP(a, toAdd[i], whereWeStart - (i + 1) * ownLimbSize);
  }
}

// TESTED
void longToGMPMatrix(mpf_class *a, long long **toAdd, const int size_toAdd, const int nr_rows, const int nr_cols, const int ownLimbSize, const int whereWeStart) {
  for(int i = 0; i < nr_rows; ++i){
    for(int j = 0; j < nr_cols; ++j){
      a[j * nr_rows +  i] = mpf_class("0.0");
      for (int k = 0; k < size_toAdd; ++k) {
	a[j * nr_rows +  i]  = addToGMP(a[j * nr_rows +  i], toAdd[k][j * nr_rows +  i], whereWeStart - (k + 1) * ownLimbSize);
      }
    }
  }
} 

// TESTED                                                                                                                                                                                
void longToGMPMatrixDouble(mpf_class *a, double *toAdd, const int size_toAdd, const int nr_rows, const int nr_cols, const int ownLimbSize, const int whereWeStart) {
  for(int i = 0; i < nr_rows; ++i){
    for(int j = 0; j < nr_cols; ++j){
      a[j * nr_rows +  i] = mpf_class("0.0");
      for (int k = 0; k < size_toAdd; ++k) {
        a[j * nr_rows +  i]  = addToGMP(a[j * nr_rows +  i], (long long)toAdd[k * nr_rows * nr_cols + j * nr_rows +  i], whereWeStart - (k + 1) * ownLimbSize);
      }
    }
  }
}


// Now tested
void numberMultiplicationBasecase(mpf_class &c, const mpf_class a, const mpf_class b) {
  if(a.get_prec() != b.get_prec()) {
    std::cout << "numberMultiplication::Numbers have different precision and therefore we will use the lower precision when multiplying" << std::endl;
  }
  
  long long *aS;
  int size_aS; 
  long long *bS; 
  int size_bS;
  
  // Define the maximum no of bits we can store in a 64-bit variable 
  // and the exponent to which we should pad one (or none) of the no
  int ownLimbSize = DOUBLE_MANT/2;
  int maxExp = max(a.get_mpf_t()->_mp_exp, b.get_mpf_t()->_mp_exp) * INT64L;
  generateLongsFromGMP(a, aS, size_aS, ownLimbSize, maxExp);
  generateLongsFromGMP(b, bS, size_bS, ownLimbSize, maxExp);
  int size = min(size_aS, size_bS);
  
  // Allocate memory to save the result in another array of 64-bit variables
  long long *res = (long long *)malloc(size * sizeof(long long)); 
  for (int i = 0; i < size - 1; i++) {
    res[i] = 0;
    for (int j = 0; j < i + 1; j++) 
      res[i] += aS[j] * bS[i-j];
  }
  longToGMP(c, res, size - 1, ownLimbSize, 2 * maxExp - ownLimbSize);
  free(res);
}




void matrixProduct(long long *C, const long long *A, const long long *B, const int nr_rowsA, const int nr_colsA, const int nr_colsB) {

  // #pragma omp parallel for schedule(dynamic)                                                                                                                                 
  for (int c = 0; c < nr_rowsA; c++) {
    for (int r = 0; r < nr_colsB; r++) {
      long long tmp = 0;
      for (int p = 0; p < nr_colsA; p++)
        tmp += A[p * nr_rowsA + c] * B[r * nr_colsA + p];
      C[r * nr_rowsA + c] = tmp;
    }
  }
}

void matrixProductDouble(long long *C, const double *A, const double *B, const int nr_rowsA, const int nr_colsA, const int nr_colsB) {

  // #pragma omp parallel for schedule(dynamic)                                                                                                          
  for (int c = 0; c < nr_rowsA; c++) {
    for (int r = 0; r < nr_colsB; r++) {
      long long tmp = 0;
      for (int p = 0; p < nr_colsA; p++)
        tmp += (long long)(A[p * nr_rowsA + c] * B[r * nr_colsA + p]);
      C[r * nr_rowsA + c] = tmp;
    }
  }
}

void matrixProductGMP(mpf_class *C, const mpf_class *A, const mpf_class *B, const int nr_rowsA, const int nr_colsA, const int nr_colsB) {

  // #pragma omp parallel for schedule(dynamic)                                                                     
                                                                                                                    
  for (int c = 0; c < nr_rowsA; c++) {
    for (int r = 0; r < nr_colsB; r++) {
      mpf_class tmp = mpf_class("0");
      for (int p = 0; p < nr_colsA; p++)
        tmp += A[p * nr_rowsA + c] * B[r * nr_colsA + p];
      C[r * nr_rowsA + c] = tmp;
    }
  }
}


void matrixMultiplicationBasecase(mpf_class *c, mpf_class *a, mpf_class *b, long long **&aS, long long **&bS, const int nr_rowsA, const int nr_colsA, const int nr_colsB) {
  
  int size_aS = 0;
  int size_bS = 0;
  int exp = 0; 
  
  int ownLimbSize = DOUBLE_MANT/2 - ceil(log2((double) nr_colsA));
  
  generateLongMatrixFromGMPMatrix(a, aS, size_aS, nr_rowsA, nr_colsA, exp, ownLimbSize);  
  generateLongMatrixFromGMPMatrix(b, bS, size_bS, nr_colsA, nr_colsB, exp, ownLimbSize);
    
  int size = min(size_aS, size_bS);
  
  for(int i = 0; i < nr_rowsA; ++i){
    for(int j = 0; j < nr_colsB; ++j){
      c[j * nr_rowsA +  i] = mpf_class("0.0");
    }
  }
  
  
  long long *tmp = (long long *)malloc(nr_rowsA * nr_colsB * sizeof(long long));
  for (int i = 0; i < size - 1; i++) {
    for (int j = 0; j < i + 1; j++) {
      matrixProduct(tmp, aS[j], bS[i-j], nr_rowsA, nr_colsA, nr_colsB);
      addToGMPMatrix(c, tmp, nr_rowsA, nr_colsB, 2 * exp - (i + 2) * ownLimbSize); 
      }
  }
}


void generateRandomGMPMatrix(mpf_class *&a, const int nr_rows, const int nr_cols) {
  gmp_randclass rr(gmp_randinit_default);
  rr.seed(time(NULL));
  for(int i = 0; i < nr_rows; i++){
    for(int j = 0; j < nr_cols; j++){
      a[j * nr_rows +  i] = rr.get_f(500);
    }
  }
}

void printGMPMatrix(mpf_class *a, const int nr_rows, const int nr_cols) {
  std::cout << "Printing GMP matrix..." << std::endl;
  for(int i = 0; i < nr_rows; ++i){
    for(int j = 0; j < nr_cols; ++j){
      std::cout << a[j * nr_rows +  i] << " ";
    }
    std::cout << std::endl;
  }
  std::cout << std::endl;
}

void printGMPMatrixDiff(mpf_class *a, mpf_class *b, const int nr_rows, const int nr_cols) {
  std::cout << "Printing GMP matrix difference..."<< std::endl;
  for(int i = 0; i < nr_rows; ++i){
    for(int j = 0; j < nr_cols; ++j){
      mpf_class tmp = (a[j * nr_rows +  i] - b[j * nr_rows +  i]);
      std::cout << tmp << " ";
    }
    std::cout << std::endl;
  }
  std::cout << std::endl;
}



// Fill the array A(nr_rows_A, nr_cols_A) with random numbers on GPU
void GPU_fill_rand(double *A, int nr_rows_A, int nr_cols_A) {
     // Create a pseudo-random number generator
     curandGenerator_t prng;
     curandCreateGenerator(&prng, CURAND_RNG_PSEUDO_DEFAULT);
 
     // Set the seed for the random number generator using the system clock
     curandSetPseudoRandomGeneratorSeed(prng, (unsigned long long) clock());
 
     // Fill the array with random numbers on the device
     curandGenerateUniformDouble(prng, A, nr_rows_A * nr_cols_A);
}

// Fill the array A(nr_rows_A, nr_cols_A) with random numbers on GPU                                                  
void GPU_fill_rand_vec(unsigned long long *A, int length) {
  // Create a pseudo-random number generator                                                                       
  curandGenerator_t prng;
  curandCreateGenerator(&prng, CURAND_RNG_PSEUDO_DEFAULT);

  // Set the seed for the random number generator using the system clock                                           
  curandSetPseudoRandomGeneratorSeed(prng, (unsigned long long) clock());

  // Fill the array with random numbers on the device                                                              
  curandGenerateLongLong(prng, A, length);
}




// Multiply the arrays A and B on GPU and save the result in C
// C(m,n) = A(m,k) * B(k,n)
// Also creates and destroys cuBLAS handle 
void gpu_blas_mmul(const double *A, const double *B, double *C, const int m, const int k, const int n) {
     int lda=m,ldb=k,ldc=m;
     const double alf = 1;
     const double bet = 0;
     const double *alpha = &alf;
     const double *beta = &bet;

     cublasHandle_t handle;
     cublasCreate(&handle);

      // Do the actual multiplication
     cublasDgemm(handle, CUBLAS_OP_N, CUBLAS_OP_N, m, n, k, alpha, A, lda, B, ldb, beta, C, ldc);
     
     cublasDestroy(handle);
}



 // Multiply the arrays A and B on GPU and save the result in C
 // C(m,n) = A(m,k) * B(k,n)
void gpu_blas_mmul(const cublasHandle_t handle, const double *A, const double *B, double *C, const int m, const int k, const int n) {
     int lda=m,ldb=k,ldc=m;
     const double alf = 1;
     const double bet = 0;
     const double *alpha = &alf;
     const double *beta = &bet;
 
      // Do the actual multiplication
     cublasDgemm(handle, CUBLAS_OP_N, CUBLAS_OP_N, m, n, k, alpha, A, lda, B, ldb, beta, C, ldc);
}


// Multiply the array A with its transpse. 
// B(n, n) =  A(n, k) A^T(k, n)
void gpu_blas_mulWithTransp(const cublasHandle_t handle, const double *A, double *B, const int n, const int k) {
  int lda = n;
  const double alf = 1; 
  const double bet = 0;
  const double *alpha = &alf;
  const double *beta = &bet;
  
     
  // Do the actual multiplication
  cublasDsyrk(handle, CUBLAS_FILL_MODE_LOWER, CUBLAS_OP_N, n, k, alpha, A, lda, beta, B, lda);
}


// Multiply the array A with its transpse. 
// B(n, n) =  A(n, k) A^T(k, n)
void gpu_blas_mulWithTranspAndSum(const cublasHandle_t handle, const double *A, const double *B, double *C, const int n, const int k) {
  int lda = n, ldb = k, ldc = k;
  const double alf = 1; 
  const double bet = 0;
  const double *alpha = &alf;
  const double *beta = &bet;

     
  // Do the actual multiplication
  cublasDsyr2k(handle, CUBLAS_FILL_MODE_LOWER, CUBLAS_OP_N, n, k, alpha, A, lda, B, ldb, beta, C, ldc);
}




void moveMatrixToBoost(const double *A, int nr_rows_A, int nr_cols_A, matrix &B) {
  for(int i = 0; i < nr_rows_A; ++i){
    for(int j = 0; j < nr_cols_A; ++j){
      B (i, j) = A[j * nr_rows_A + i];
    }
  }
  std::cout << std::endl;
}



void print_memory() {
 // show memory usage of GPU

     size_t free_byte ;
     size_t total_byte ;
     cudaError_t cuda_status = cudaMemGetInfo( &free_byte, &total_byte ) ;

     if ( cudaSuccess != cuda_status ){
            printf("Error: cudaMemGetInfo fails, %s \n", cudaGetErrorString(cuda_status) );
            exit(1);
      }



     double free_db = (double)free_byte ;
     double total_db = (double)total_byte ;

     double used_db = total_db - free_db ;

     printf("GPU memory usage: used = %f, free = %f MB, total = %f MB\n",
                 used_db/1024.0/1024.0, free_db/1024.0/1024.0, total_db/1024.0/1024.0);

}

// CUDA kernel. Each thread takes care of one element of c
__global__ void vecAdd(unsigned long long *a, unsigned long long *b, unsigned long long *c, int size)
{
  // Get our global thread ID
  int id = blockIdx.x*blockDim.x+threadIdx.x;
  
  // Make sure we do not go out of bounds
  if (id < size)
    c[id] = a[id] + b[id];
}


// CUDA kernel. Each thread takes care of one element of c                                                           
__global__ void vecAdd__wSign(double *a, long long *res, int size)
{
  // Get our global thread ID                                                                                       
  int id = blockIdx.x*blockDim.x+threadIdx.x;
  // Make sure we do not go out of bounds                                                                           
  if (id < size)
    res[id] += ((long long)a[id]);
}




// CUDA kernel. Each thread takes care of one element of c                                                          
__global__ void vecAdd_withRem(double *a, long long *res, long long *rem,  int size)
{
  // Get our global thread ID                                                                                       
  int id = blockIdx.x*blockDim.x+threadIdx.x;

  // Make sure we do not go out of bounds                                                                           
  if (id < size) {
    if (a[id] > 0 && res[id] > LLONG_MAX - a[id]) {
      /* handle overflow */
      rem[id] += 1;					       
      res[id] += (((long long)a[id]) - LLONG_MAX - 1);
    } else if (a[id] < 0 && res[id] < LLONG_MIN - a[id]) {
      /* handle underflow */
      rem[id] -= 1; 
      res[id] += (((long long)a[id]) - LLONG_MIN + 1);
    } else {
      /* handle regular cases */
      res[id] += a[id];
    }
  }
}

void matrixSquareIntoBlock(const double *A, double * B, const int nr_rows_A, const int nr_cols_A) {
  // #pragma omp parallel for schedule(dynamic)
#pragma omp parallel for schedule(dynamic)
  for (int c = 0; c < nr_rows_A; c++) {
    for (int r = 0; r <= c; r++) {
      double tmp = 0;
      for (int p = 0; p < nr_cols_A; p++)
        tmp += A[p * nr_rows_A + r] * A[p * nr_rows_A + c];
      B[r * nr_rows_A + c] = tmp;
      if (r != c)
        B[c * nr_rows_A + r] = tmp;
    }
  }
}


void matrixSquareIntoBlockGMP(const mpf_class *A, mpf_class * B, const int nr_rows_A, const int nr_cols_A) {
  // #pragma omp parallel for schedule(dynamic)
#pragma omp parallel for schedule(dynamic)
  for (int c = 0; c < nr_rows_A; c++) {
    for (int r = 0; r <= c; r++) {
      mpf_class tmp("0");
      for (int p = 0; p < nr_cols_A; p++)
        tmp += A[p * nr_rows_A + r] * A[p * nr_rows_A + c];
      B[r * nr_rows_A + c] = tmp;
      if (r != c)
        B[c * nr_rows_A + r] = tmp;
    }
  }
}

// Compute average difference for elements in matrix
double computeAverageDifference(const double *A, const double *B, const int nr_rows) {
  double sum = 0;
  for(int i = 0; i < nr_rows; ++i){
    for(int j = 0; j <= i; ++j){
      sum += abs(A[j * nr_rows + i] - B[j * nr_rows + i]);
    }
  }
  std::cout << "Average difference between the two is " << sum/(nr_rows * nr_rows) << std::endl;
  return(sum/(nr_rows * nr_rows));
}


void estimateSize(const mpf_class *a, int &sizeOfArray, int &maxExp, const int nr_rows, const int nr_cols, const int ownLimbSize) {
  assert(ownLimbSize <= INT64L);

  int minSize = 0;
  maxExp = a[0].get_mpf_t()->_mp_exp;
  for(int i = 0; i < nr_rows; ++i)
    for(int j = 0; j < nr_cols; ++j) {
      int toCmp =  a[j * nr_rows + i].get_mpf_t()->_mp_exp;
      if (toCmp >= maxExp) {
        maxExp = toCmp;
        minSize = abs(a[j * nr_rows + i].get_mpf_t()->_mp_size);
      }
    }

  maxExp *= INT64L;
  sizeOfArray = (INT64L * minSize) / ownLimbSize;
  if ((INT64L * minSize) % ownLimbSize != 0) sizeOfArray += 1;
}



// All arrays need to already have allocated memory: 
// *a : array of mpf_class with size nr_rows * nr_cols
// *d_aS: array allocated in GPU with size sizeOfArray * nr_rows * nr_cols. Note that we flatten this 
//        array of matrices in order to speed up the access in the GPU.
//        Thus, to access the k-th limb from the (i, j) matrix entry one calls d_aS[k * nr_rows * nr_cols + j * nr_rows + i] 
// *tmpA: temporary array for doubles used for transfers that needs to be allocated nr_rows * nr_cols entries
// sizeOfArray: store number of own limbs that are saved for each entry
// nr_rows: number of matrix rows
// nr_cols: number of matrix columns 
// maxExp:  maximum power of 2 for the leading most limb among all the entries of the array *a 
void generateLongMatrixFromGMPMatrix_GPU(const mpf_class *a, double *d_aS, double *tmpA, 
					 int *sizeMatrix, int *realExpMatrix, int *signMatrix, int &sizeOfArray, 
					 const int nr_rows, const int nr_cols, int &maxExp, 
					 const int ownLimbSize) {
  assert(ownLimbSize <= INT64L);
  // timeval t1, t2, tA, tB;
  
  // double etAlloc = 0;
  // double etAlgebra = 0;
  // double etComputingSizes = 0;
  // double etAddingLongs = 0;
  // double etAddTrivial = 0;
  // double etAccs = 0;
  
  #pragma omp parallel for schedule(dynamic)
  for(int j = 0; j < nr_cols; ++j) {
    for(int i = 0; i < nr_rows; ++i) {
      sizeMatrix[j * nr_rows + i] = abs(a[j * nr_rows + i].get_mpf_t()->_mp_size);
      realExpMatrix[j * nr_rows + i] = a[j * nr_rows + i].get_mpf_t()->_mp_exp * INT64L;
      signMatrix[j * nr_rows + i] =  getSign(a[j * nr_rows + i]);
    }
  }

  for (int k = 0; k < sizeOfArray - 1; k++) {
    //gettimeofday(&t1, NULL);
    #pragma omp parallel for schedule(dynamic)
    for(int j = 0; j < nr_cols; ++j) {
      for(int i = 0; i < nr_rows; ++i) {
	//gettimeofday(&tA, NULL);
	int size = sizeMatrix[j * nr_rows + i];
	int realExp = realExpMatrix[j * nr_rows + i];
	int sign  = signMatrix[j * nr_rows + i];
	//gettimeofday(&tB, NULL);
	//etAccs += (((tB.tv_sec*uS_PER_SEC)+tB.tv_usec) - ((tA.tv_sec*uS_PER_SEC)+tA.tv_usec))/(float)uS_PER_mS;
	
	//gettimeofday(&tA, NULL);
	int padding = (maxExp - realExp) / ownLimbSize;
	int padBitOffset = (maxExp - realExp) % ownLimbSize;
	//gettimeofday(&tB, NULL);
	//etComputingSizes += (((tB.tv_sec*uS_PER_SEC)+tB.tv_usec) - ((tA.tv_sec*uS_PER_SEC)+tA.tv_usec))/(float)uS_PER_mSa;

	if(k > padding) {
	  //gettimeofday(&tA, NULL);
	  int leftGmpLimb  = size - 1 - (((k - padding) * ownLimbSize - padBitOffset) / INT64L);
	  int leftBit      = ((k - padding) * ownLimbSize - padBitOffset) % INT64L;
	  int rightGmpLimb = size - 1 - (((k - padding + 1) * ownLimbSize - padBitOffset) / INT64L);
	  int rightBit     = ((k - padding + 1) * ownLimbSize - padBitOffset) % INT64L;
	  //gettimeofday(&tB, NULL);
	  //etAddTrivial+= (((tB.tv_sec*uS_PER_SEC)+tB.tv_usec) - ((tA.tv_sec*uS_PER_SEC)+tA.tv_usec))/(float)uS_PER_mS;
	  //gettimeofday(&tA, NULL);
	  if (leftGmpLimb == rightGmpLimb) {
	    long long tmp  = a[j * nr_rows + i].get_mpf_t()->_mp_d[leftGmpLimb];
	    tmpA[j * nr_rows + i] = sign * getBitsFromOneLong(tmp, leftBit, rightBit);
	  } else {
	    long long tmp1 = a[j * nr_rows + i].get_mpf_t()->_mp_d[leftGmpLimb];
	    long long tmp2 = a[j * nr_rows + i].get_mpf_t()->_mp_d[rightGmpLimb];
	    tmpA[j * nr_rows + i] = sign * getBitsFromTwoLong(tmp1, tmp2, leftBit, rightBit);
	  }
	} else if (k < padding){
	  tmpA[j * nr_rows + i] = 0;
	} else {
	  long long tmp  = a[j * nr_rows + i].get_mpf_t()->_mp_d[size - 1];
	  tmpA[j * nr_rows + i] = sign * getBitsFromOneLong(tmp, 0, ownLimbSize - padBitOffset);
	}
	//gettimeofday(&tB, NULL);
	//etAddingLongs += (((tB.tv_sec*uS_PER_SEC)+tB.tv_usec) - ((tA.tv_sec*uS_PER_SEC)+tA.tv_usec))/(float)uS_PER_mS;
      } 
    }
    //gettimeofday(&t2, NULL);
    //etAlgebra +=  (((t2.tv_sec*uS_PER_SEC)+t2.tv_usec) - ((t1.tv_sec*uS_PER_SEC)+t1.tv_usec))/(float)uS_PER_mS;
    // Transfer matrix to memeory
    //gettimeofday(&t1, NULL);
    cudaMemcpy(&d_aS[k * nr_rows * nr_cols], tmpA, nr_rows * nr_cols * sizeof(double), cudaMemcpyHostToDevice);
    cudaThreadSynchronize();
    //gettimeofday(&t2, NULL);
    //etAlloc +=  (((t2.tv_sec*uS_PER_SEC)+t2.tv_usec) - ((t1.tv_sec*uS_PER_SEC)+t1.tv_usec))/(float)uS_PER_mS;
  }

  #pragma omp parallel for schedule(dynamic)
  for(int i = 0; i < nr_rows; ++i) {
    for(int j = 0; j < nr_cols; ++j) {
      int realExp = a[j * nr_rows + i].get_mpf_t()->_mp_exp * INT64L;
      int padding = (maxExp - realExp) / ownLimbSize;
      int padBitOffset = (maxExp - realExp) % ownLimbSize;
      int sign  = getSign(a[j * nr_rows + i]);
      int leftBit = ((sizeOfArray - padding - 1) * ownLimbSize + padBitOffset) % INT64L;
      int tmp = a[j * nr_rows + i].get_mpf_t()->_mp_d[0];
      tmpA[j * nr_rows + i] = sign * getBitsFromOneLong(tmp, leftBit, INT64L);
    }
  }
  cudaMemcpy(&d_aS[(sizeOfArray - 1) * nr_cols * nr_rows], tmpA, nr_rows * nr_cols * sizeof(double),cudaMemcpyHostToDevice);
  //printf("Actual allocation time to GPU = %fms\n", etAlloc);
  // printf("Algebra time in computing hands = %fms\n", etAlgebra);
  //printf("Calculating sizes = %fms\n", etComputingSizes);
  //printf("My function for obtaining the hands = %fms\n", etAddingLongs);
  //printf("Trivial stuff = %fms\n", etAddTrivial);
  //printf("Access time = %fms\n", etAccs);
}


// Estimates 
// maxFrac : 
// nr_rows :
// nr_cols :
int estimateMaxGPUAllocation(double maxFrac, int nr_rows, int nr_cols) {
  size_t free_byte ;
  size_t total_byte ;
  cudaError_t cuda_status = cudaMemGetInfo( &free_byte, &total_byte ) ;
  if ( cudaSuccess != cuda_status ){
    printf("Error: cudaMemGetInfo fails, %s \n", cudaGetErrorString(cuda_status) );
    exit(1);
  }
  double free_db = ((double)free_byte) * maxFrac;
  return (int) (8 * free_db/(nr_rows * nr_cols * INT64L));
}


void matrixMultiplicationArbOrder_cuBlas(const cublasHandle_t handle, mpf_class *c, mpf_class *a, mpf_class *b, 
					 double *d_aS, double *d_bS, double *tmpTransferLongToGMP, 
					 long long *tmp, int *sizeMatrix, int *realExpMatrix, int *signMatrix,  
					 double *d_prodRes, long long *d_res,  //long long *d_rem, 
					 const int nr_rowsA, const int nr_colsA, const int nr_colsB,
					 const int size_aS, const int size_bS, const int expA, const int expB, 
					 const int ownLimbSize, const int prec);


void matrixMultSymmArbOrder_cuBlas(const cublasHandle_t handle, mpf_class *c, mpf_class *a, 
				   double *d_aS, double *tmpTransferLongToGMP, 
				   long long *tmp, int *sizeMatrix, int *realExpMatrix, int *signMatrix,  
				   double *d_prodRes, long long *d_res, const int nr_rowsA, const int nr_colsA, 
				   const int size_aS, const int expA, const int ownLimbSize, const int prec);


void toom2(const cublasHandle_t handle, mpf_class *c, mpf_class *a, mpf_class *b, 
	   double *d_aS, double *d_bS, double *tmpTransferLongToGMP, 
	   long long *tmp, int *sizeMatrix, int *realExpMatrix, int *signMatrix, double *d_prodRes, 
	   long long *d_res, const int nr_rowsA, const int nr_colsA, const int nr_colsB, 
	   const int size_aS, const int size_bS, const int leadingExp, const int whatOrder); 


void toom3(const cublasHandle_t handle, mpf_class *c, mpf_class *a, mpf_class *b, 
	   double *d_aS, double *d_bS, double *tmpTransferLongToGMP, 
	   long long *tmp, int *sizeMatrix, int *realExpMatrix, int *signMatrix,  
	   double *d_prodRes, long long *d_res, 
	   const int nr_rowsA, const int nr_colsA, const int nr_colsB, const int whatOrder);



void toom2Symm(const cublasHandle_t handle, mpf_class *c, mpf_class *a, 
	       double *d_aS, double *tmpTransferLongToGMP, 
	       long long *tmp, int *sizeMatrix, int *realExpMatrix, int *signMatrix,  
	       double *d_prodRes, long long *d_res, const int nr_rowsA, const int nr_colsA, 
	       const int size_aS, const int prec); 


void toom3Symm(const cublasHandle_t handle, mpf_class *c, mpf_class *a, 
	       double *d_aS, double *tmpTransferLongToGMP, 
	       long long *tmp, int *sizeMatrix, int *realExpMatrix, int *signMatrix,  
	       double *d_prodRes, long long *d_res, const int nr_rowsA, const int nr_colsA, const int prec);


// Implements matrix multiplication c = a.b, and, according to whether or not the matrices fit 
// in GPU memory. If it does not fit we either apply the Karatsuba algorithm or the Toom-3 
// algorithm until all the matrices fit in GPU memory. 
void matrixMult_cuBlas(const cublasHandle_t handle, mpf_class *c, mpf_class *a, mpf_class *b, 
		       double *d_aS, double *d_bS, double *tmpTransferLongToGMP, 
		       long long *tmp, int *sizeMatrix, int *realExpMatrix, int *signMatrix,  
		       double *d_prodRes, long long *d_res, 
		       const int nr_rowsA, const int nr_colsA, const int nr_colsB, const int prec) {
  int maxNoMatrices = estimateMaxGPUAllocation(0.8, (nr_rowsA + nr_colsB), nr_colsA);
  int size_aS = 0; 
  int size_bS = 0;
  int expA = 0;
  int expB = 0;
    
  int ownLimbSize = DOUBLE_MANT/2 - ceil(log2((double) nr_colsA) / 2);
  estimateSize(a, size_aS, expA, nr_rowsA, nr_colsA, ownLimbSize);
  estimateSize(b, size_bS, expB, nr_colsA, nr_colsB, ownLimbSize);
  
  if (max(size_aS, size_bS) + 1 < maxNoMatrices) {
    // We need to allocate the matrix in memory here. This should be made more efficiently
    generateLongMatrixFromGMPMatrix_GPU(a, d_aS, tmpTransferLongToGMP, sizeMatrix, realExpMatrix, signMatrix, 
					size_aS, nr_rowsA, nr_colsA, expA, ownLimbSize);
    generateLongMatrixFromGMPMatrix_GPU(b, d_bS, tmpTransferLongToGMP, sizeMatrix, realExpMatrix, signMatrix,
					size_bS, nr_colsA, nr_colsB, expB, ownLimbSize);
    matrixMultiplicationArbOrder_cuBlas(handle, c, a, b, d_aS, d_bS, tmpTransferLongToGMP, 
					      tmp, sizeMatrix, realExpMatrix, signMatrix,  
					      d_prodRes, d_res, nr_rowsA, nr_colsA, nr_colsB, size_aS, size_bS, expA, expB, ownLimbSize, prec); 
  } else {
    toom2(handle, c, a, b, d_aS, d_bS, tmpTransferLongToGMP, 
	  tmp, sizeMatrix, realExpMatrix, signMatrix,  
	  d_prodRes, d_res, nr_rowsA, nr_colsA, nr_colsB, size_aS, size_bS, max(expA, expB), prec);
  }
}




void matrixMultSymm_cuBlas(const cublasHandle_t handle, mpf_class *c, mpf_class *a, 
			   double *d_aS, double *tmpTransferLongToGMP, 
			   long long *tmp, int *sizeMatrix, int *realExpMatrix, int *signMatrix,  
			   double *d_prodRes, long long *d_res, 
			   const int nr_rowsA, const int nr_colsA, const int prec) {
  int maxNoMatrices = estimateMaxGPUAllocation(0.8, nr_rowsA, nr_colsA);
  int size = 0; 
  int exp = 0;
 
  int ownLimbSize = DOUBLE_MANT/2 - ceil(log2((double) nr_colsA) / 2);
  
  estimateSize(a, size, exp, nr_rowsA, nr_colsA, ownLimbSize);

  if (size + 1 < maxNoMatrices) {    
    // We need to allocate the matrix in memory here. This should be made more efficiently
    generateLongMatrixFromGMPMatrix_GPU(a, d_aS, tmpTransferLongToGMP, sizeMatrix, realExpMatrix, signMatrix, 
					size, nr_rowsA, nr_colsA, exp, ownLimbSize);
    matrixMultSymmArbOrder_cuBlas(handle, c, a, d_aS, tmpTransferLongToGMP, 
				  tmp, sizeMatrix, realExpMatrix, signMatrix,  
				  d_prodRes, d_res, nr_rowsA, nr_colsA, size, exp, ownLimbSize, prec); 
  } else {
    toom2Symm(handle, c, a, d_aS, tmpTransferLongToGMP, 
	      tmp, sizeMatrix, realExpMatrix, signMatrix,  
	      d_prodRes, d_res, nr_rowsA, nr_colsA, size, prec);
  }
}

// Implements Karatsuba algorithm for matrix multiplication c = a.b
// We split each matrix element in two parts which are equal in length up to the size of one GMP limb. 
void toom2(const cublasHandle_t handle, mpf_class *c, mpf_class *a, mpf_class *b, 
	   double *d_aS, double *d_bS, double *tmpTransferLongToGMP, 
	   long long *tmp, int *sizeMatrix, int *realExpMatrix, int *signMatrix, double *d_prodRes, 
	   long long *d_res, const int nr_rowsA, const int nr_colsA, const int nr_colsB, 
	   const int size_aS, const int size_bS, const int leadingExp, const int whatOrder) {
  mpf_class *a1, *a2, *b1, *b2; 
  
  int sizeA1 = (size_aS / 2 + size_aS % 2), sizeA2 = size_aS / 2, sizeB1 = (size_bS / 2 + size_bS % 2), sizeB2 = size_bS / 2; 
 
  for(int i = 0; i < nr_colsA; ++i){
    for(int k = 0; k < nr_rowsA; ++k){
      if (sizeA1 + sizeA2 != abs(a[i *  nr_rowsA + k].get_mpf_t()->_mp_size))
	std::cout << "Error?" << std::endl;
      int sign =  a[i *  nr_rowsA + k].get_mpf_t()->_mp_size /
	abs(a[i *  nr_rowsA + k].get_mpf_t()->_mp_size);
      a1[i *  nr_rowsA + k].get_mpf_t()->_mp_size = sign * sizeA1;
      a2[i *  nr_rowsA + k].get_mpf_t()->_mp_size = sign * sizeA2;
      a1[i *  nr_rowsA + k].get_mpf_t()->_mp_exp = a[i *  nr_rowsA + k].get_mpf_t()->_mp_exp; 
      a2[i *  nr_rowsA + k].get_mpf_t()->_mp_exp = (a[i *  nr_rowsA + k].get_mpf_t()->_mp_exp) - sizeA1;
      a1[i *  nr_rowsA + k].get_mpf_t()->_mp_d = &(a[i *  nr_rowsA + k].get_mpf_t()->_mp_d[sizeA2]); 
      a2[i *  nr_rowsA + k].get_mpf_t()->_mp_d = &(a[i *  nr_rowsA + k].get_mpf_t()->_mp_d[0]);
    }
  }
  
  for(int i = 0; i < nr_colsB; ++i){
    for(int k = 0; k < nr_colsA; ++k){
      if (sizeB1 + sizeB2 != abs(b[i *  nr_rowsA + k].get_mpf_t()->_mp_size))
	std::cout << "Error?" << std::endl;
      int sign =  b[i *  nr_rowsA + k].get_mpf_t()->_mp_size /
	abs(b[i *  nr_rowsA + k].get_mpf_t()->_mp_size);
      b1[i *  nr_colsA + k].get_mpf_t()->_mp_size = sign * sizeB1; 
      b2[i *  nr_colsA + k].get_mpf_t()->_mp_size = sign * sizeB2;
      b1[i *  nr_colsA + k].get_mpf_t()->_mp_exp = b[i *  nr_rowsA + k].get_mpf_t()->_mp_exp; 
      b2[i *  nr_colsA + k].get_mpf_t()->_mp_exp = b[i *  nr_rowsA + k].get_mpf_t()->_mp_exp;
      b1[i *  nr_colsA + k].get_mpf_t()->_mp_d = &(b[i *  nr_rowsA + k].get_mpf_t()->_mp_d[sizeB2]); 
      b2[i *  nr_colsA + k].get_mpf_t()->_mp_d = &(b[i *  nr_rowsA + k].get_mpf_t()->_mp_d[0]); 
    }
  }
 
  matrixMult_cuBlas(handle, tmpC1, a1, b1, d_aS, d_bS, tmpTransferLongToGMP,
		    tmp, sizeMatrix, realExpMatrix, signMatrix, d_prodRes, d_res,
		    nr_rowsA, nr_colsA, nr_colsB, whatOrder);
  matrixMult_cuBlas(handle, tmpC2, a2, b2, d_aS, d_bS, tmpTransferLongToGMP,
		    tmp, sizeMatrix, realExpMatrix, signMatrix, d_prodRes, d_res,
		    nr_rowsA, nr_colsA, nr_colsB, whatOrder);
  for(int i = 0; i < nr_colsA; ++i){
    for(int k = 0; k < nr_rowsA; ++k){
      a1[i *  nr_rowsA + k] += a2[i *  nr_rowsA + k]; 
    }
  }
  for(int i = 0; i < nr_colsB; ++i){
    for(int k = 0; k < nr_colsA; ++k){
      b1[i *  nr_colsA + k] += b2[i *  nr_rowsA + k]; 
    }
  }

  matrixMult_cuBlas(handle, c, a1, b1, d_aS, d_bS, tmpTransferLongToGMP,
		    tmp, sizeMatrix, realExpMatrix, signMatrix, d_prodRes, d_res,
		    nr_rowsA, nr_colsA, nr_colsB, whatOrder);
  for (int i = 0; i < nr_colsB; ++i) {
    for (int j = 0; j < nr_rowsA; ++j) {
      c[i *  nr_rowsA + j] -= tmpC1[i *  nr_rowsA + j];
      c[i *  nr_rowsA + j] -= tmpC2[i *  nr_rowsA + j];
      c[i *  nr_rowsA + j].get_mpf_t()->_mp_exp -= sizeA2;
      tmpC2[i *  nr_rowsA + j].get_mpf_t()->_mp_exp -= 2 * sizeA2;
      c[i * nr_rowsA + j] += (tmpC1[i * nr_rowsA + j] + tmpC2[i * nr_rowsA + j]);
    }
  }  
}

// Implements Toom-3 algorithm for matrix multiplciation c = a.b
// We split each matrix element in three parts which are equal in length up to the size of one GMP limb.
void toom3(const cublasHandle_t handle, mpf_class *c, mpf_class *a, mpf_class *b, 
	   double *d_aS, double *d_bS, double *tmpTransferLongToGMP, 
	   long long *tmp, int *sizeMatrix, int *realExpMatrix, int *signMatrix,  
	   double *d_prodRes, long long *d_res, 
	   const int nr_rowsA, const int nr_colsA, const int nr_colsB, 
	   const int size_aS, const int size_bS, const int whatOrder) {
  mpf_class *a1, *a2, *a3, *b1, *b2, *b3;
  // We need to check that size_aS = size_bS are different by at most 1. Otherwise, this won't work. 
  assert(size_aS == size_bS || size_aS + 1 == size_bS || size_aS + 2 == size_bS);
  int sizeA1 = (size_aS / 3 + (size_aS % 3)), sizeA2 = (size_aS / 3), sizeA3 = size_aS / 3;
  int sizeB1 = size_aS - sizeA2 - sizeA3, sizeB2 = sizeA2, sizeB3 = sizeA3;
 
  for(int i = 0; i < nr_colsA; ++i){
    for(int k = 0; k < nr_rowsA; ++k){
      if (sizeA1 + sizeA2 + sizeA3 != abs(a[i *  nr_rowsA + k].get_mpf_t()->_mp_size))
	std::cout << "Error?" << std::endl;
      int sign =  a[i *  nr_rowsA + k].get_mpf_t()->_mp_size /
	abs(a[i *  nr_rowsA + k].get_mpf_t()->_mp_size);
      a1[i *  nr_rowsA + k].get_mpf_t()->_mp_size = sign * sizeA1;
      a2[i *  nr_rowsA + k].get_mpf_t()->_mp_size = sign * sizeA2;
      a3[i *  nr_rowsA + k].get_mpf_t()->_mp_size = sign * sizeA3;
      
      a1[i *  nr_rowsA + k].get_mpf_t()->_mp_exp = a[i *  nr_rowsA + k].get_mpf_t()->_mp_exp; 
      a2[i *  nr_rowsA + k].get_mpf_t()->_mp_exp = (a[i *  nr_rowsA + k].get_mpf_t()->_mp_exp) - sizeA1;
      a3[i *  nr_rowsA + k].get_mpf_t()->_mp_exp = (a[i *  nr_rowsA + k].get_mpf_t()->_mp_exp) - sizeA1 - sizeA2;
      
      
      a1[i *  nr_rowsA + k].get_mpf_t()->_mp_d = &(a[i *  nr_rowsA + k].get_mpf_t()->_mp_d[sizeA2 + sizeA3]); 
      a2[i *  nr_rowsA + k].get_mpf_t()->_mp_d = &(a[i *  nr_rowsA + k].get_mpf_t()->_mp_d[sizeA3]);
      a3[i *  nr_rowsA + k].get_mpf_t()->_mp_d = &(a[i *  nr_rowsA + k].get_mpf_t()->_mp_d[0]);
    }
  }

  for(int i = 0; i < nr_colsB; ++i){
    for(int k = 0; k < nr_colsA; ++k){
      if (sizeA1 + sizeA2 + sizeA3 != abs(a[i *  nr_rowsA + k].get_mpf_t()->_mp_size))
	std::cout << "Error?" << std::endl;
      int sign =  a[i *  nr_rowsA + k].get_mpf_t()->_mp_size /
	abs(a[i *  nr_rowsA + k].get_mpf_t()->_mp_size);
      b1[i *  nr_colsA + k].get_mpf_t()->_mp_size = sign * sizeB1;
      b2[i *  nr_colsA + k].get_mpf_t()->_mp_size = sign * sizeB2;
      b3[i *  nr_colsA + k].get_mpf_t()->_mp_size = sign * sizeB3;
      
      b1[i *  nr_colsA + k].get_mpf_t()->_mp_exp = (b[i *  nr_colsA + k].get_mpf_t()->_mp_exp); 
      b2[i *  nr_colsA + k].get_mpf_t()->_mp_exp = (b[i *  nr_colsA + k].get_mpf_t()->_mp_exp) - sizeB1;
      b3[i *  nr_colsA + k].get_mpf_t()->_mp_exp = (b[i *  nr_colsA + k].get_mpf_t()->_mp_exp) - sizeB1 - sizeB2;
      
      b1[i *  nr_colsA + k].get_mpf_t()->_mp_d = &(b[i *  nr_colsA + k].get_mpf_t()->_mp_d[sizeB2 + sizeB3]); 
      b2[i *  nr_colsA + k].get_mpf_t()->_mp_d = &(b[i *  nr_colsA + k].get_mpf_t()->_mp_d[sizeB3]);
      b3[i *  nr_colsA + k].get_mpf_t()->_mp_d = &(b[i *  nr_colsA + k].get_mpf_t()->_mp_d[0]);
    }
  }
  matrixMult_cuBlas(handle, tmpC1, a1, b1, d_aS, d_bS, tmpTransferLongToGMP,
		    tmp, sizeMatrix, realExpMatrix, signMatrix, d_prodRes, d_res,
		    nr_rowsA, nr_colsA, nr_colsB, whatOrder);
  matrixMult_cuBlas(handle, tmpC5, a3, b3, d_aS, d_bS, tmpTransferLongToGMP,
		    tmp, sizeMatrix, realExpMatrix, signMatrix, d_prodRes, d_res,
		    nr_rowsA, nr_colsA, nr_colsB, whatOrder);
  for(int i = 0; i < nr_colsA; ++i){
    for(int k = 0; k < nr_rowsA; ++k){
      a1[i *  nr_rowsA + k] += (a2[i *  nr_rowsA + k] + a3[i *  nr_rowsA + k]); 
    }
  }
  for(int i = 0; i < nr_colsB; ++i){
    for(int k = 0; k < nr_colsA; ++k){
      b1[i *  nr_rowsA + k] += (b2[i *  nr_rowsA + k] + b3[i *  nr_rowsA + k]); 
    }
  }
  matrixMult_cuBlas(handle, tmpC2, a1, b1, d_aS, d_bS, tmpTransferLongToGMP,
		    tmp, sizeMatrix, realExpMatrix, signMatrix, d_prodRes, d_res,
		    nr_rowsA, nr_colsA, nr_colsB, whatOrder);
  for(int i = 0; i < nr_colsA; ++i){
    for(int k = 0; k < nr_rowsA; ++k){
      a1[i *  nr_rowsA + k] -= (2 * a2[i *  nr_rowsA + k]); 
    }
  }
  for(int i = 0; i < nr_colsB; ++i){
    for(int k = 0; k < nr_colsA; ++k){
      b1[i *  nr_rowsA + k] -= (2 * b2[i *  nr_rowsA + k]); 
    }
  }
  matrixMult_cuBlas(handle, tmpC3, a1, b1, d_aS, d_bS, tmpTransferLongToGMP,
		    tmp, sizeMatrix, realExpMatrix, signMatrix, d_prodRes, d_res,
		    nr_rowsA, nr_colsA, nr_colsB, whatOrder);
  for(int i = 0; i < nr_colsA; ++i){
    for(int k = 0; k < nr_rowsA; ++k){
      a1[i *  nr_rowsA + k] += 3 * (a2[i *  nr_rowsA + k] + a3[i * nr_rowsA + k]); 
    }
  }
  for(int i = 0; i < nr_colsB; ++i){
    for(int k = 0; k < nr_colsA; ++k){
      b1[i *  nr_rowsA + k] += 3 * (b2[i *  nr_rowsA + k] + b3[i *  nr_rowsA + k]); 
    }
  }
  matrixMult_cuBlas(handle, tmpC4, a1, b1, d_aS, d_bS, tmpTransferLongToGMP,
		    tmp, sizeMatrix, realExpMatrix, signMatrix, d_prodRes, d_res,
		    nr_rowsA, nr_colsA, nr_colsB, whatOrder);
  
  for (int i = 0; i < nr_colsB; ++i) {
    for (int j = 0; j < nr_rowsA; ++j) {
      tmpC2[i * nr_rowsA + j] = (- tmpC1[i * nr_rowsA + j] / 2 + tmpC2[i * nr_rowsA + j] 
				 - tmpC3[i * nr_rowsA + j] /3 - tmpC4[i * nr_rowsA + j] / 6 
				 + 2 * tmpC5[i * nr_rowsA + j]); 
      tmpC3[i * nr_rowsA + j] = (-3/4 * tmpC1[i * nr_rowsA + j] + tmpC2[i * nr_rowsA + j] / 2 
				 + 2/3 * tmpC3[i * nr_rowsA + j] + 1/12 * tmpC4[i * nr_rowsA + j] 
				 - 2 * tmpC5[i * nr_rowsA + j]);
      tmpC4[i * nr_rowsA + j] = (- tmpC1[i * nr_rowsA + j] / 8 - tmpC2[i * nr_rowsA + j] / 2 
				 - tmpC3[i * nr_rowsA + j] / 4 + tmpC4[i * nr_rowsA + j] / 8 
				 - 2 * tmpC5[i * nr_rowsA + j]);
  
      tmpC2[i *  nr_rowsA + j].get_mpf_t()->_mp_exp -= sizeA2;
      tmpC3[i *  nr_rowsA + j].get_mpf_t()->_mp_exp -= 2 * sizeA2;
      tmpC4[i *  nr_rowsA + j].get_mpf_t()->_mp_exp -= 3 * sizeA2;
      tmpC5[i *  nr_rowsA + j].get_mpf_t()->_mp_exp -= 4 * sizeA2;
      
      c[i *  nr_rowsA + j] = (tmpC1[i *  nr_rowsA + j] + tmpC2[i *  nr_rowsA + j] 
			      + tmpC3[i *  nr_rowsA + j] + tmpC4[i *  nr_rowsA + j] 
			      + tmpC5[i *  nr_rowsA + j]);
    }
  }
}

// Implements Karatsuba algorithm for matrix multiplication c = a.a^T
//      
void toom2Symm(const cublasHandle_t handle, mpf_class *c, mpf_class *a, 
	       double *d_aS, double *tmpTransferLongToGMP, 
	       long long *tmp, int *sizeMatrix, int *realExpMatrix, int *signMatrix,  
	       double *d_prodRes, long long *d_res, const int nr_rowsA, const int nr_colsA, 
	       const int size_aS, const int prec) {
  mpf_class *a1, *a2;
  int sizeA1 = (size_aS / 2 + size_aS % 2), sizeA2 = size_aS / 2; 
 
  for(int i = 0; i < nr_colsA; ++i){
    for(int k = 0; k < nr_rowsA; ++k){
      if (sizeA1 + sizeA2 != abs(a[i *  nr_rowsA + k].get_mpf_t()->_mp_size))
	std::cout << "Error?" << std::endl;
      int sign =  a[i *  nr_rowsA + k].get_mpf_t()->_mp_size /
	abs(a[i *  nr_rowsA + k].get_mpf_t()->_mp_size);
      a1[i *  nr_rowsA + k].get_mpf_t()->_mp_size = sign * sizeA1;
      a2[i *  nr_rowsA + k].get_mpf_t()->_mp_size = sign * sizeA2;
      a1[i *  nr_rowsA + k].get_mpf_t()->_mp_exp = a[i *  nr_rowsA + k].get_mpf_t()->_mp_exp; 
      a2[i *  nr_rowsA + k].get_mpf_t()->_mp_exp = (a[i *  nr_rowsA + k].get_mpf_t()->_mp_exp) - sizeA1;
      a1[i *  nr_rowsA + k].get_mpf_t()->_mp_d = &(a[i *  nr_rowsA + k].get_mpf_t()->_mp_d[sizeA2]); 
      a2[i *  nr_rowsA + k].get_mpf_t()->_mp_d = &(a[i *  nr_rowsA + k].get_mpf_t()->_mp_d[0]);
    }
  }
  matrixMultSymm_cuBlas(handle, tmpC1, a1, d_aS, tmpTransferLongToGMP,
			tmp, sizeMatrix, realExpMatrix, signMatrix, d_prodRes, d_res,
			nr_rowsA, nr_colsA, prec);
  matrixMultSymm_cuBlas(handle, tmpC2, a2, d_aS, tmpTransferLongToGMP,
                        tmp, sizeMatrix, realExpMatrix, signMatrix, d_prodRes, d_res,
                        nr_rowsA, nr_colsA, prec);
  for(int i = 0; i < nr_colsA; ++i){
    for(int k = 0; k < nr_rowsA; ++k){
      a1[i *  nr_rowsA + k] += a2[i *  nr_rowsA + k]; 
    }
  }
  
  matrixMultSymm_cuBlas(handle, c, a1, d_aS,  tmpTransferLongToGMP,
			tmp, sizeMatrix, realExpMatrix, signMatrix, d_prodRes, d_res,
			nr_rowsA, nr_colsA, prec);
  for (int i = 0; i < nr_rowsA; ++i) {
    for (int j = 0; j < nr_rowsA; ++j) {
      c[i *  nr_rowsA + j] -= tmpC1[i *  nr_rowsA + j];
      c[i *  nr_rowsA + j] -= tmpC2[i *  nr_rowsA + j];
      c[i *  nr_rowsA + j].get_mpf_t()->_mp_exp -= sizeA2;
      tmpC2[i *  nr_rowsA + j].get_mpf_t()->_mp_exp -= 2 * sizeA2;
      c[i * nr_rowsA + j] += (tmpC1[i * nr_rowsA + j] + tmpC2[i * nr_rowsA + j]);
    }
  }  
}

// Implements Toom-3 algorithm for matrix multiplication c = a.a^T
void toom3Symm(const cublasHandle_t handle, mpf_class *c, mpf_class *a, 
	       double *d_aS, double *tmpTransferLongToGMP, 
	       long long *tmp, int *sizeMatrix, int *realExpMatrix, int *signMatrix,  
	       double *d_prodRes, long long *d_res, const int nr_rowsA, const int nr_colsA, 
	       const int size_aS, const int prec) {
  mpf_class *a1, *a2, *a3;
  int sizeA1 = (size_aS / 3 + (size_aS % 3)), sizeA2 = (size_aS / 3), sizeA3 = size_aS / 3; 
 
  for(int i = 0; i < nr_colsA; ++i){
    for(int k = 0; k < nr_rowsA; ++k){
      if (sizeA1 + sizeA2 + sizeA3 != abs(a[i *  nr_rowsA + k].get_mpf_t()->_mp_size))
	std::cout << "Error?" << std::endl;
      int sign =  a[i *  nr_rowsA + k].get_mpf_t()->_mp_size /
	abs(a[i *  nr_rowsA + k].get_mpf_t()->_mp_size);
      a1[i *  nr_rowsA + k].get_mpf_t()->_mp_size = sign * sizeA1;
      a2[i *  nr_rowsA + k].get_mpf_t()->_mp_size = sign * sizeA2;
      a3[i *  nr_rowsA + k].get_mpf_t()->_mp_size = sign * sizeA3;
      
      a1[i *  nr_rowsA + k].get_mpf_t()->_mp_exp = a[i *  nr_rowsA + k].get_mpf_t()->_mp_exp; 
      a2[i *  nr_rowsA + k].get_mpf_t()->_mp_exp = (a[i *  nr_rowsA + k].get_mpf_t()->_mp_exp) - sizeA1;
      a3[i *  nr_rowsA + k].get_mpf_t()->_mp_exp = (a[i *  nr_rowsA + k].get_mpf_t()->_mp_exp) - sizeA1 - sizeA2;
      
      
      a1[i *  nr_rowsA + k].get_mpf_t()->_mp_d = &(a[i *  nr_rowsA + k].get_mpf_t()->_mp_d[sizeA2 + sizeA3]); 
      a2[i *  nr_rowsA + k].get_mpf_t()->_mp_d = &(a[i *  nr_rowsA + k].get_mpf_t()->_mp_d[sizeA3]);
      a3[i *  nr_rowsA + k].get_mpf_t()->_mp_d = &(a[i *  nr_rowsA + k].get_mpf_t()->_mp_d[0]);
    }
  }
  
  matrixMultSymm_cuBlas(handle, tmpC1, a1, d_aS, tmpTransferLongToGMP,
			tmp, sizeMatrix, realExpMatrix, signMatrix, d_prodRes, d_res,
			nr_rowsA, nr_colsA, prec);
  matrixMultSymm_cuBlas(handle, tmpC5, a3, d_aS, tmpTransferLongToGMP,
                        tmp, sizeMatrix, realExpMatrix, signMatrix, d_prodRes, d_res,
                        nr_rowsA, nr_colsA, prec);
  
  for(int i = 0; i < nr_colsA; ++i){
    for(int k = 0; k < nr_rowsA; ++k){
      a1[i *  nr_rowsA + k] += (a2[i *  nr_rowsA + k] + a3[i *  nr_rowsA + k]); 
    }
  }
  matrixMultSymm_cuBlas(handle, tmpC2, a1, d_aS,  tmpTransferLongToGMP,
			tmp, sizeMatrix, realExpMatrix, signMatrix, d_prodRes, d_res,
			nr_rowsA, nr_colsA, prec);
 
  for(int i = 0; i < nr_colsA; ++i){
    for(int k = 0; k < nr_rowsA; ++k){
      a1[i *  nr_rowsA + k] -= (2 * a2[i *  nr_rowsA + k]); 
    }
  }
  matrixMultSymm_cuBlas(handle, tmpC3, a1, d_aS,  tmpTransferLongToGMP,
			tmp, sizeMatrix, realExpMatrix, signMatrix, d_prodRes, d_res,
			nr_rowsA, nr_colsA, prec);
  
  for(int i = 0; i < nr_colsA; ++i){
    for(int k = 0; k < nr_rowsA; ++k){
      a1[i *  nr_rowsA + k] += 3 * (a2[i *  nr_rowsA + k] + a3[i * nr_rowsA + k]); 
    }
  }
  matrixMultSymm_cuBlas(handle, tmpC4, a1, d_aS,  tmpTransferLongToGMP,
			tmp, sizeMatrix, realExpMatrix, signMatrix, d_prodRes, d_res,
			nr_rowsA, nr_colsA, prec);
  
  for (int i = 0; i < nr_rowsA; ++i) {
    for (int j = 0; j < nr_rowsA; ++j) {
      tmpC2[i * nr_rowsA + j] = (- tmpC1[i * nr_rowsA + j] / 2 + tmpC2[i * nr_rowsA + j] 
				 - tmpC3[i * nr_rowsA + j] /3 - tmpC4[i * nr_rowsA + j] / 6 
				 + 2 * tmpC5[i * nr_rowsA + j]); 
      tmpC3[i * nr_rowsA + j] = (-3/4 * tmpC1[i * nr_rowsA + j] + tmpC2[i * nr_rowsA + j] / 2 
				 + 2/3 * tmpC3[i * nr_rowsA + j] + 1/12 * tmpC4[i * nr_rowsA + j] 
				 - 2 * tmpC5[i * nr_rowsA + j]);
      tmpC4[i * nr_rowsA + j] = (- tmpC1[i * nr_rowsA + j] / 8 - tmpC2[i * nr_rowsA + j] / 2 
				 - tmpC3[i * nr_rowsA + j] / 4 + tmpC4[i * nr_rowsA + j] / 8 
				 - 2 * tmpC5[i * nr_rowsA + j]);
  
      tmpC2[i *  nr_rowsA + j].get_mpf_t()->_mp_exp -= sizeA2;
      tmpC3[i *  nr_rowsA + j].get_mpf_t()->_mp_exp -= 2 * sizeA2;
      tmpC4[i *  nr_rowsA + j].get_mpf_t()->_mp_exp -= 3 * sizeA2;
      tmpC5[i *  nr_rowsA + j].get_mpf_t()->_mp_exp -= 4 * sizeA2;
      
      c[i *  nr_rowsA + j] = (tmpC1[i *  nr_rowsA + j] + tmpC2[i *  nr_rowsA + j] 
			      + tmpC3[i *  nr_rowsA + j] + tmpC4[i *  nr_rowsA + j] 
			      + tmpC5[i *  nr_rowsA + j]);
    }
  }
}


// Returns matrix product c = a.a^T where each entry is of the type mpf_class
//
// All arrays need to already have allocated memory:
// handle : Handle for cuBlas computations that needs to be previously allocated.                                                                   
// *c : array of mpf_class with size nr_rowsA * nr_rowsA                  
// *a : array of mpf_class with size nr_rowsA * nr_colsA
// *d_aS: array allocated in GPU with size sizeOfArray * nr_rowsA * nr_colsA. Note that we flatten this               
//        array of matrices in order to speed up the access in the GPU.                                              
//        Thus, to access the k-th limb from the (i, j) matrix entry one calls d_aS[k * nr_rowsA * nr_colsA + j * nr_rowsA + i]
// *tmpTransferLongToGMP : temporary array of doubles used for transfers that needs nr_rowsA * nr_colsA entries                    
// *tmp: temporary array of 64-bit vars used for transfers. Needs to be allocated nr_rowsA * nr_rowsA entries
// *d_prodRes: temporary matrix allocated in GPU memory which handles individual multiplications of matrices
// *d_res : temporary matrix allocated in GPU memory in which we sum up all individual multiplications of matrices
// *d_rem : in case we encounter overflow in the matrix d_res we use the entries in the matrix d_rem to store the remainders. 
//          Note that this matrix is only used when using the function vecAdd__wRem. When using vecAdd__wSign we assume that 
//          overflow never occurs. This is the case if the number of own generated limbs is greater than 1024. This correpons 
//          to a GMP precision ~20,000. For current bootstrap applications such precision is not needed.
// nr_rows_A: number of rows for matrix A as well as for matrix C                                                                                
// nr_cols_A: number of columns for matrix A as well as number of rows for matrix B
// nr_cols_B: number of columns for matrix B as well as for matrix C                                                                            
// maxExp:  maximum power of 2 for the leading most limb among all the entries of the array *a 
void matrixMultSymmArbOrder_cuBlas(const cublasHandle_t handle, mpf_class *c, mpf_class *a, 
				   double *d_aS, double *tmpTransferLongToGMP, 
				   long long *tmp, int *sizeMatrix, int *realExpMatrix, int *signMatrix,  
				   double *d_prodRes, long long *d_res, const int nr_rowsA, const int nr_colsA, 
				   const int size, const int expA, const int ownLimbSize, const int prec) {
  timeval t1, t2;
  
  for(int i = 0; i < nr_rowsA; ++i){
    for(int j = 0; j < nr_rowsA; ++j){
      c[j * nr_rowsA +  i] = mpf_class("0.0");
      tmp[j * nr_rowsA +  i] = 0;
    }
  }

  // Number of threads in each thread block                                                                          
  int blockSize = 256; // Make sure this number is good? I don't know how
  // Number of thread blocks in grid                                                                                 
  int gridSize = (int)ceil((float)(nr_rowsA * nr_rowsA)/blockSize);
  
  double etMult = 0;
  double etAdd = 0;
  double etAlloc = 0;
  double etBackAlloc = 0;
  double etaddBack = 0;
  
  int sizeToCompute =  (prec + expA) / ownLimbSize;
  
  for (int i = 0; i < min(size, sizeToCompute); i++) {
    gettimeofday(&t1, NULL);
    cudaMemcpy(d_res, tmp, nr_rowsA * nr_rowsA * sizeof(long long), cudaMemcpyHostToDevice);
    gettimeofday(&t2, NULL);
    etAlloc += (((t2.tv_sec*uS_PER_SEC)+t2.tv_usec) - ((t1.tv_sec*uS_PER_SEC)+t1.tv_usec))/(float)uS_PER_mS;
    //cudaMemcpy(d_rem, tmp, nr_rowsA * nr_colsB * sizeof(long long), cudaMemcpyHostToDevice);
    for (int j = 0; j < i + 1; j++) {
      gettimeofday(&t1, NULL);
      if (i - j != j)
	gpu_blas_mulWithTranspAndSum(handle, &d_aS[j * nr_rowsA * nr_colsA], &d_aS[(i - j) * nr_rowsA * nr_colsA], d_prodRes, nr_rowsA, nr_colsA); 
      else
	gpu_blas_mulWithTransp(handle, &d_aS[j * nr_rowsA * nr_colsA], d_prodRes, nr_rowsA, nr_colsA); 
      cudaThreadSynchronize();
      gettimeofday(&t2, NULL);
      etMult += (((t2.tv_sec*uS_PER_SEC)+t2.tv_usec) - ((t1.tv_sec*uS_PER_SEC)+t1.tv_usec))/(float)uS_PER_mS;
      
      gettimeofday(&t1, NULL);
      vecAdd__wSign<<<gridSize, blockSize>>>(d_prodRes, d_res,  nr_rowsA * nr_rowsA);
      cudaThreadSynchronize();
      gettimeofday(&t2, NULL);
      etAdd += (((t2.tv_sec*uS_PER_SEC)+t2.tv_usec) - ((t1.tv_sec*uS_PER_SEC)+t1.tv_usec))/(float)uS_PER_mS;
      // This is safe with overflow until there are 1024 of our own limbs that need to be summed up
      // This case corresponds to a precision of ~20000 bits in GMP
    }
    gettimeofday(&t1, NULL);
    cudaMemcpy(tmp, d_res, nr_rowsA * nr_rowsA * sizeof(long long), cudaMemcpyDeviceToHost);
    gettimeofday(&t2, NULL);
    etBackAlloc += (((t2.tv_sec*uS_PER_SEC)+t2.tv_usec) - ((t1.tv_sec*uS_PER_SEC)+t1.tv_usec))/(float)uS_PER_mS;
    
    gettimeofday(&t1, NULL);
    addToGMPMatrixSymm(c, tmp, nr_rowsA, 2 * expA - (i + 2) * ownLimbSize);
    gettimeofday(&t2, NULL);
    etaddBack += (((t2.tv_sec*uS_PER_SEC)+t2.tv_usec) - ((t1.tv_sec*uS_PER_SEC)+t1.tv_usec))/(float)uS_PER_mS;
    
    #pragma omp parallel for schedule(dynamic)
    for(int l = 0; l < nr_rowsA; ++l){
      for(int k = 0; k < nr_rowsA; ++k){
	tmp[l *  nr_rowsA + k] = 0;
      }
    }
  }
  
   
  for (int i = size; i < min(2 * size - 1, sizeToCompute); i++) {
    gettimeofday(&t1, NULL);
    cudaMemcpy(d_res, tmp, nr_rowsA * nr_rowsA * sizeof(long long), cudaMemcpyHostToDevice);
    gettimeofday(&t2, NULL);
    etAlloc += (((t2.tv_sec*uS_PER_SEC)+t2.tv_usec) - ((t1.tv_sec*uS_PER_SEC)+t1.tv_usec))/(float)uS_PER_mS;
    //cudaMemcpy(d_rem, tmp, nr_rowsA * nr_colsB * sizeof(long long), cudaMemcpyHostToDevice);
    for (int j = i - size + 1; j < size; j++) {
      gettimeofday(&t1, NULL);
      if (i - j != j)
	gpu_blas_mulWithTranspAndSum(handle, &d_aS[j * nr_rowsA * nr_colsA], &d_aS[(i - j) * nr_rowsA * nr_colsA], d_prodRes, nr_rowsA, nr_colsA); 
      else
	gpu_blas_mulWithTransp(handle, &d_aS[j * nr_rowsA * nr_colsA], d_prodRes, nr_rowsA, nr_colsA); 
      cudaThreadSynchronize();
      gettimeofday(&t2, NULL);
      etMult += (((t2.tv_sec*uS_PER_SEC)+t2.tv_usec) - ((t1.tv_sec*uS_PER_SEC)+t1.tv_usec))/(float)uS_PER_mS;
      
      gettimeofday(&t1, NULL);
      vecAdd__wSign<<<gridSize, blockSize>>>(d_prodRes, d_res,  nr_rowsA * nr_rowsA);
      cudaThreadSynchronize();
      gettimeofday(&t2, NULL);
      etAdd += (((t2.tv_sec*uS_PER_SEC)+t2.tv_usec) - ((t1.tv_sec*uS_PER_SEC)+t1.tv_usec))/(float)uS_PER_mS;
      // This is safe with overflow until there are 1024 of our own limbs that need to be summed up
      // This case corresponds to a precision of ~20000 bits in GMP
    }
    gettimeofday(&t1, NULL);
    cudaMemcpy(tmp, d_res, nr_rowsA * nr_rowsA * sizeof(long long), cudaMemcpyDeviceToHost);
    gettimeofday(&t2, NULL);
    etBackAlloc += (((t2.tv_sec*uS_PER_SEC)+t2.tv_usec) - ((t1.tv_sec*uS_PER_SEC)+t1.tv_usec))/(float)uS_PER_mS;
    
    gettimeofday(&t1, NULL);
    addToGMPMatrixSymm(c, tmp, nr_rowsA, 2 * expA - (i + 2) * ownLimbSize);
    gettimeofday(&t2, NULL);
    etaddBack += (((t2.tv_sec*uS_PER_SEC)+t2.tv_usec) - ((t1.tv_sec*uS_PER_SEC)+t1.tv_usec))/(float)uS_PER_mS;
    #pragma omp parallel for schedule(dynamic)
    for(int l = 0; l < nr_rowsA; ++l){
      for(int k = 0; k < nr_rowsA; ++k){
	tmp[l *  nr_rowsA + k] = 0;
      }
    }
  }
 
  // printf("Transfer GPU = %fms\n", etTransfer);
  // printf("Multiplication GPU = %fms\n", etMult);
  // printf("Addition GPU = %fms\n", etAdd);
  // printf("Alloc of zero to GPU = %fms\n", etAlloc);
  // printf("Transfer from GPU to host = %fms\n", etBackAlloc);
  // printf("Addition on CPU = %fms\n", etaddBack);
}


// Returns matrix product c = a.a^T where each entry is of the type mpf_class
//
// All arrays need to already have allocated memory:
// handle : Handle for cuBlas computations that needs to be previously allocated.                                                                   
// *c : array of mpf_class with size nr_rowsA * nr_rowsA                  
// *a : array of mpf_class with size nr_rowsA * nr_colsA
// *d_aS: array allocated in GPU with size sizeOfArray * nr_rowsA * nr_colsA. Note that we flatten this               
//        array of matrices in order to speed up the access in the GPU.                                              
//        Thus, to access the k-th limb from the (i, j) matrix entry one calls d_aS[k * nr_rowsA * nr_colsA + j * nr_rowsA + i]
// *tmpTransferLongToGMP : temporary array of doubles used for transfers that needs nr_rowsA * nr_colsA entries                    
// *tmp: temporary array of 64-bit vars used for transfers. Needs to be allocated nr_rowsA * nr_rowsA entries
// *d_prodRes: temporary matrix allocated in GPU memory which handles individual multiplications of matrices
// *d_res : temporary matrix allocated in GPU memory in which we sum up all individual multiplications of matrices
// *d_rem : in case we encounter overflow in the matrix d_res we use the entries in the matrix d_rem to store the remainders. 
//          Note that this matrix is only used when using the function vecAdd__wRem. When using vecAdd__wSign we assume that 
//          overflow never occurs. This is the case if the number of own generated limbs is greater than 1024. This correpons 
//          to a GMP precision ~20,000. For current bootstrap applications such precision is not needed.
// nr_rows_A: number of rows for matrix A as well as for matrix C                                                                                
// nr_cols_A: number of columns for matrix A as well as number of rows for matrix B
// nr_cols_B: number of columns for matrix B as well as for matrix C                                                                            
// maxExp:  maximum power of 2 for the leading most limb among all the entries of the array *a 
void matrixMultSymmBasecase_cuBlas(const cublasHandle_t handle, mpf_class *c, mpf_class *a, 
				   double *d_aS, double *tmpTransferLongToGMP, 
				   long long *tmp, int *sizeMatrix, int *realExpMatrix, int *signMatrix,  
				   double *d_prodRes, long long *d_res, const int nr_rowsA, const int nr_colsA) {
  
  int size_aS = 0; 
  int expA = 0;
  timeval t1, t2;
  
  int ownLimbSize = DOUBLE_MANT/2 - ceil(log2((double) nr_colsA) / 2);
  gettimeofday(&t1, NULL);
  estimateSize(a, size_aS, expA, nr_rowsA, nr_colsA, ownLimbSize);
  
  generateLongMatrixFromGMPMatrix_GPU(a, d_aS, tmpTransferLongToGMP, sizeMatrix, realExpMatrix, signMatrix, 
				      size_aS, nr_rowsA, nr_colsA, expA, ownLimbSize);
  gettimeofday(&t2, NULL);
  double etTransfer = (((t2.tv_sec*uS_PER_SEC)+t2.tv_usec) - ((t1.tv_sec*uS_PER_SEC)+t1.tv_usec))/(float)uS_PER_mS;
  
  std::cout << size_aS << " " << expA << std::endl;

  for(int i = 0; i < nr_rowsA; ++i){
    for(int j = 0; j < nr_rowsA; ++j){
      c[j * nr_rowsA +  i] = mpf_class("0.0");
      tmp[j * nr_rowsA +  i] = 0;
    }
  }

  // Number of threads in each thread block                                                                          
  int blockSize = 256; // Make sure this number is good? I don't know how
  // Number of thread blocks in grid                                                                                 
  int gridSize = (int)ceil((float)(nr_rowsA * nr_rowsA)/blockSize);
  
  double etMult = 0;
  double etAdd = 0;
  double etAlloc = 0;
  double etBackAlloc = 0;
  double etaddBack = 0;
  
  for (int i = 0; i < size_aS; i++) {
    gettimeofday(&t1, NULL);
    cudaMemcpy(d_res, tmp, nr_rowsA * nr_rowsA * sizeof(long long), cudaMemcpyHostToDevice);
    gettimeofday(&t2, NULL);
    etAlloc += (((t2.tv_sec*uS_PER_SEC)+t2.tv_usec) - ((t1.tv_sec*uS_PER_SEC)+t1.tv_usec))/(float)uS_PER_mS;
    //cudaMemcpy(d_rem, tmp, nr_rowsA * nr_colsB * sizeof(long long), cudaMemcpyHostToDevice);
    for (int j = 0; j < i + 1; j++) {
      gettimeofday(&t1, NULL);
      if (i - j != j)
	gpu_blas_mulWithTranspAndSum(handle, &d_aS[j * nr_rowsA * nr_colsA], &d_aS[(i - j) * nr_rowsA * nr_colsA], d_prodRes, nr_rowsA, nr_colsA); 
      else
	gpu_blas_mulWithTransp(handle, &d_aS[j * nr_rowsA * nr_colsA], d_prodRes, nr_rowsA, nr_colsA); 
      cudaThreadSynchronize();
      gettimeofday(&t2, NULL);
      etMult += (((t2.tv_sec*uS_PER_SEC)+t2.tv_usec) - ((t1.tv_sec*uS_PER_SEC)+t1.tv_usec))/(float)uS_PER_mS;
      
      gettimeofday(&t1, NULL);
      vecAdd__wSign<<<gridSize, blockSize>>>(d_prodRes, d_res,  nr_rowsA * nr_rowsA);
      cudaThreadSynchronize();
      gettimeofday(&t2, NULL);
      etAdd += (((t2.tv_sec*uS_PER_SEC)+t2.tv_usec) - ((t1.tv_sec*uS_PER_SEC)+t1.tv_usec))/(float)uS_PER_mS;
      // This is safe with overflow until there are 1024 of our own limbs that need to be summed up
      // This case corresponds to a precision of ~20000 bits in GMP
    }
    gettimeofday(&t1, NULL);
    cudaMemcpy(tmp, d_res, nr_rowsA * nr_rowsA * sizeof(long long), cudaMemcpyDeviceToHost);
    gettimeofday(&t2, NULL);
    etBackAlloc += (((t2.tv_sec*uS_PER_SEC)+t2.tv_usec) - ((t1.tv_sec*uS_PER_SEC)+t1.tv_usec))/(float)uS_PER_mS;
    
    gettimeofday(&t1, NULL);
    addToGMPMatrixSymm(c, tmp, nr_rowsA, 2 * expA - (i + 2) * ownLimbSize);
    gettimeofday(&t2, NULL);
    etaddBack += (((t2.tv_sec*uS_PER_SEC)+t2.tv_usec) - ((t1.tv_sec*uS_PER_SEC)+t1.tv_usec))/(float)uS_PER_mS;
    
    #pragma omp parallel for schedule(dynamic)
    for(int l = 0; l < nr_rowsA; ++l){
      for(int k = 0; k < nr_rowsA; ++k){
	tmp[l *  nr_rowsA + k] = 0;
      }
    }
  }
  
  printf("Transfer GPU = %fms\n", etTransfer);
  printf("Multiplication GPU = %fms\n", etMult);
  printf("Addition GPU = %fms\n", etAdd);
  printf("Alloc of zero to GPU = %fms\n", etAlloc);
  printf("Transfer from GPU to host = %fms\n", etBackAlloc);
  printf("Addition on CPU = %fms\n", etaddBack);
}




// Returns matrix product c = a.b where each entry is of the type mpf_class
//
// All arrays need to already have allocated memory:                                                                  
// *c : array of mpf_class with size nr_rowsA * nr_colsB                   
// *a : array of mpf_class with size nr_rowsA * nr_colsA
// *b : array of mpf_class with size nr_colsA * nr_colsB
// *d_aS: array allocated in GPU with size sizeOfArray * nr_rowsA * nr_colsA. Note that we flatten this               
//        array of matrices in order to speed up the access in the GPU.                                              
//        Thus, to access the k-th limb from the (i, j) matrix entry one calls d_aS[k * nr_rowsA * nr_colsA + j * nr_rowsA + i]
// *d_bS: array allocated in GPU with size sizeOfArray * nr_colsA * nr_colsB. Note that we flatten this                                         
//        array of matrices in order to speed up the access in the GPU.                                                                          
//        Thus, to access the k-th limb from the (i, j) matrix entry one calls d_bS[k * nr_colsA * nr_colsB + j * nr_colsA + i] 
// *tmpTransferLongToGMP : temporary array of doubles used for transfers that needs max(nr_rowsA * nr_colsA, nr_colsA * nr_colsB) entries        
// *tmp: temporary array of 64-bit vars used for transfers. Needs to be allocated nr_rowsA * nr_colsB entries
// *d_prodRes: temporary matrix allocated in GPU memory which handles individual multiplications of matrices
// *d_res : temporary matrix allocated in GPU memory in which we sum up all individual multiplications of matrices
// *d_rem : in case we encounter overflow in the matrix d_res we use the entries in the matrix d_rem to store the remainders. 
//          Note that this matrix is only used when using the function vecAdd__wRem. When using vecAdd__wSign we assume that 
//          overflow never occurs. This is the case if the number of own generated limbs is greater than 1024. This correpons 
//          to a GMP precision ~20,000. For current bootstrap applications such precision is not needed.
// nr_rows_A: number of rows for matrix A as well as for matrix C                                                                                
// nr_cols_A: number of columns for matrix A as well as number of rows for matrix B
// nr_cols_B: number of columns for matrix B as well as for matrix C                                                                             
// maxExp:  maximum power of 2 for the leading most limb among all the entries of the array *a 
void matrixMultiplicationArbOrder_cuBlas(const cublasHandle_t handle, mpf_class *c, mpf_class *a, mpf_class *b, 
					 double *d_aS, double *d_bS, double *tmpTransferLongToGMP, 
					 long long *tmp, int *sizeMatrix, int *realExpMatrix, int *signMatrix,  
					 double *d_prodRes, long long *d_res,  //long long *d_rem, 
					 const int nr_rowsA, const int nr_colsA, const int nr_colsB,
					 const int size_aS, const int size_bS, const int expA, const int expB, const int ownLimbSize, const int prec) {
  
  timeval t1, t2;
  
  int size = min(size_aS, size_bS);
  std::cout << size_aS << " " << size_bS << " " << expA << " " << expB << std::endl;

  for(int i = 0; i < nr_rowsA; ++i){
    for(int j = 0; j < nr_colsB; ++j){
      c[j * nr_rowsA +  i] = mpf_class("0.0");
      tmp[j * nr_rowsA +  i] = 0;
    }
  }

  // Number of threads in each thread block                                                                          
  int blockSize = 256; // Make sure this number is good? I don't know how
  // Number of thread blocks in grid                                                                                 
  int gridSize = (int)ceil((float)(nr_rowsA * nr_colsB)/blockSize);
  
  double etMult = 0;
  double etAdd = 0;
  double etAlloc = 0;
  double etBackAlloc = 0;
  double etaddBack = 0;
  int maxExp = max(expA, expB);

  int sizeToCompute =  (prec + maxExp) / ownLimbSize;
  
  for (int i = 0; i < min(size, sizeToCompute); i++) {
    gettimeofday(&t1, NULL);
    cudaMemcpy(d_res, tmp, nr_rowsA * nr_colsB * sizeof(long long), cudaMemcpyHostToDevice);
    gettimeofday(&t2, NULL);
    etAlloc += (((t2.tv_sec*uS_PER_SEC)+t2.tv_usec) - ((t1.tv_sec*uS_PER_SEC)+t1.tv_usec))/(float)uS_PER_mS;
    //cudaMemcpy(d_rem, tmp, nr_rowsA * nr_colsB * sizeof(long long), cudaMemcpyHostToDevice);
    for (int j = 0; j < i + 1; j++) {
      gettimeofday(&t1, NULL);
      gpu_blas_mmul(handle, &d_aS[j * nr_rowsA * nr_colsA], &d_bS[(i - j) * nr_colsA * nr_colsB], d_prodRes, nr_rowsA, nr_colsA, nr_colsB);
      cudaThreadSynchronize();
      gettimeofday(&t2, NULL);
      etMult += (((t2.tv_sec*uS_PER_SEC)+t2.tv_usec) - ((t1.tv_sec*uS_PER_SEC)+t1.tv_usec))/(float)uS_PER_mS;
      
      gettimeofday(&t1, NULL);
      vecAdd__wSign<<<gridSize, blockSize>>>(d_prodRes, d_res,  nr_rowsA * nr_colsB);
      cudaThreadSynchronize();
      gettimeofday(&t2, NULL);
      etAdd += (((t2.tv_sec*uS_PER_SEC)+t2.tv_usec) - ((t1.tv_sec*uS_PER_SEC)+t1.tv_usec))/(float)uS_PER_mS;
      // This is safe with overflow until there are 1024 of our own limbs that need to be summed up
      // This case corresponds to a precision of ~20000 bits in GMP
    }
    gettimeofday(&t1, NULL);
    cudaMemcpy(tmp, d_res, nr_rowsA * nr_colsB * sizeof(long long), cudaMemcpyDeviceToHost);
    gettimeofday(&t2, NULL);
    etBackAlloc += (((t2.tv_sec*uS_PER_SEC)+t2.tv_usec) - ((t1.tv_sec*uS_PER_SEC)+t1.tv_usec))/(float)uS_PER_mS;
    
    gettimeofday(&t1, NULL);
    addToGMPMatrix(c, tmp, nr_rowsA, nr_colsB, expA + expB - (i + 2) * ownLimbSize);
    gettimeofday(&t2, NULL);
    etaddBack += (((t2.tv_sec*uS_PER_SEC)+t2.tv_usec) - ((t1.tv_sec*uS_PER_SEC)+t1.tv_usec))/(float)uS_PER_mS;
    //cudaMemcpy(tmp, d_rem, nr_rowsA * nr_colsB * sizeof(long long),cudaMemcpyDeviceToHost);
    //addToGMPMatrix(c, tmp, nr_rowsA, nr_colsB, 2 * exp - (i + 2) * ownLimbSize + (INT64L - 1));
    #pragma omp parallel for schedule(dynamic)
    for(int k = 0; k < nr_rowsA; ++k){
      for(int l = 0; l < nr_colsB; ++l){
	tmp[l *  nr_rowsA + k] = 0;
      }
    }
  }

   
  for (int i = size; i < min(2 * size - 1, sizeToCompute); i++) {
    gettimeofday(&t1, NULL);
    cudaMemcpy(d_res, tmp, nr_rowsA * nr_colsB * sizeof(long long), cudaMemcpyHostToDevice);
    gettimeofday(&t2, NULL);
    etAlloc += (((t2.tv_sec*uS_PER_SEC)+t2.tv_usec) - ((t1.tv_sec*uS_PER_SEC)+t1.tv_usec))/(float)uS_PER_mS;
    //cudaMemcpy(d_rem, tmp, nr_rowsA * nr_colsB * sizeof(long long), cudaMemcpyHostToDevice);
    for (int j = i - size + 1; j < size; j++) {
      gettimeofday(&t1, NULL);
      gpu_blas_mmul(handle, &d_aS[j * nr_rowsA * nr_colsA], &d_bS[(i - j) * nr_colsA * nr_colsB], d_prodRes, nr_rowsA, nr_colsA, nr_colsB);
      cudaThreadSynchronize();
      gettimeofday(&t2, NULL);
      etMult += (((t2.tv_sec*uS_PER_SEC)+t2.tv_usec) - ((t1.tv_sec*uS_PER_SEC)+t1.tv_usec))/(float)uS_PER_mS;
      
      gettimeofday(&t1, NULL);
      vecAdd__wSign<<<gridSize, blockSize>>>(d_prodRes, d_res,  nr_rowsA * nr_colsB);
      cudaThreadSynchronize();
      gettimeofday(&t2, NULL);
      etAdd += (((t2.tv_sec*uS_PER_SEC)+t2.tv_usec) - ((t1.tv_sec*uS_PER_SEC)+t1.tv_usec))/(float)uS_PER_mS;
      // This is safe with overflow until there are 1024 of our own limbs that need to be summed up
      // This case corresponds to a precision of ~20000 bits in GMP
    }
    gettimeofday(&t1, NULL);
    cudaMemcpy(tmp, d_res, nr_rowsA * nr_colsB * sizeof(long long), cudaMemcpyDeviceToHost);
    gettimeofday(&t2, NULL);
    etBackAlloc += (((t2.tv_sec*uS_PER_SEC)+t2.tv_usec) - ((t1.tv_sec*uS_PER_SEC)+t1.tv_usec))/(float)uS_PER_mS;
    
    gettimeofday(&t1, NULL);
    addToGMPMatrix(c, tmp, nr_rowsA, nr_colsB, expA + expB - (i + 2) * ownLimbSize);
    gettimeofday(&t2, NULL);
    etaddBack += (((t2.tv_sec*uS_PER_SEC)+t2.tv_usec) - ((t1.tv_sec*uS_PER_SEC)+t1.tv_usec))/(float)uS_PER_mS;
    #pragma omp parallel for schedule(dynamic)
    for(int k = 0; k < nr_rowsA; ++k){
      for(int l = 0; l < nr_colsB; ++l){
	tmp[l *  nr_rowsA + k] = 0;
      }
    }
  }
  // printf("Transfer GPU = %fms\n", etTransfer);
  // printf("Multiplication GPU = %fms\n", etMult);
  // printf("Addition GPU = %fms\n", etAdd);
  // printf("Alloc of zero to GPU = %fms\n", etAlloc);
  // printf("Transfer from GPU to host = %fms\n", etBackAlloc);
  // printf("Addition on CPU = %fms\n", etaddBack);
}




// Returns matrix product c = a.b where each entry is of the type mpf_class
//
// All arrays need to already have allocated memory:                                                                  
// *c : array of mpf_class with size nr_rowsA * nr_colsB                   
// *a : array of mpf_class with size nr_rowsA * nr_colsA
// *b : array of mpf_class with size nr_colsA * nr_colsB
// *d_aS: array allocated in GPU with size sizeOfArray * nr_rowsA * nr_colsA. Note that we flatten this               
//        array of matrices in order to speed up the access in the GPU.                                              
//        Thus, to access the k-th limb from the (i, j) matrix entry one calls d_aS[k * nr_rowsA * nr_colsA + j * nr_rowsA + i]
// *d_bS: array allocated in GPU with size sizeOfArray * nr_colsA * nr_colsB. Note that we flatten this                                         
//        array of matrices in order to speed up the access in the GPU.                                                                          
//        Thus, to access the k-th limb from the (i, j) matrix entry one calls d_bS[k * nr_colsA * nr_colsB + j * nr_colsA + i] 
// *tmpTransferLongToGMP : temporary array of doubles used for transfers that needs max(nr_rowsA * nr_colsA, nr_colsA * nr_colsB) entries        
// *tmp: temporary array of 64-bit vars used for transfers. Needs to be allocated nr_rowsA * nr_colsB entries
// *d_prodRes: temporary matrix allocated in GPU memory which handles individual multiplications of matrices
// *d_res : temporary matrix allocated in GPU memory in which we sum up all individual multiplications of matrices
// *d_rem : in case we encounter overflow in the matrix d_res we use the entries in the matrix d_rem to store the remainders. 
//          Note that this matrix is only used when using the function vecAdd__wRem. When using vecAdd__wSign we assume that 
//          overflow never occurs. This is the case if the number of own generated limbs is greater than 1024. This correpons 
//          to a GMP precision ~20,000. For current bootstrap applications such precision is not needed.
// nr_rows_A: number of rows for matrix A as well as for matrix C                                                                                
// nr_cols_A: number of columns for matrix A as well as number of rows for matrix B
// nr_cols_B: number of columns for matrix B as well as for matrix C                                                                             
// maxExp:  maximum power of 2 for the leading most limb among all the entries of the array *a 
void matrixMultiplicationBasecase_cuBlas(const cublasHandle_t handle, mpf_class *c, mpf_class *a, mpf_class *b, 
					 double *d_aS, double *d_bS, double *tmpTransferLongToGMP, 
					 long long *tmp, int *sizeMatrix, int *realExpMatrix, int *signMatrix,  
					 double *d_prodRes, long long *d_res,  //long long *d_rem, 
					 const int nr_rowsA, const int nr_colsA, const int nr_colsB) {
  
  int size_aS = 0; 
  int size_bS = 0;
  int expA = 0;
  int expB = 0;
  timeval t1, t2;
  
  int ownLimbSize = DOUBLE_MANT/2 - ceil(log2((double) nr_colsA) / 2);
  gettimeofday(&t1, NULL);
  estimateSize(a, size_aS, expA, nr_rowsA, nr_colsA, ownLimbSize);
  estimateSize(b, size_bS, expB, nr_colsA, nr_colsB, ownLimbSize);
  
  generateLongMatrixFromGMPMatrix_GPU(a, d_aS, tmpTransferLongToGMP, sizeMatrix, realExpMatrix, signMatrix, 
				      size_aS, nr_rowsA, nr_colsA, expA, ownLimbSize);
  generateLongMatrixFromGMPMatrix_GPU(b, d_bS, tmpTransferLongToGMP, sizeMatrix, realExpMatrix, signMatrix,
				      size_bS, nr_colsA, nr_colsB, expB, ownLimbSize);
  gettimeofday(&t2, NULL);
  double etTransfer = (((t2.tv_sec*uS_PER_SEC)+t2.tv_usec) - ((t1.tv_sec*uS_PER_SEC)+t1.tv_usec))/(float)uS_PER_mS;
  
  int size = min(size_aS, size_bS);
  std::cout << size_aS << " " << size_bS << " " << expA << " " << expB << std::endl;

  for(int i = 0; i < nr_rowsA; ++i){
    for(int j = 0; j < nr_colsB; ++j){
      c[j * nr_rowsA +  i] = mpf_class("0.0");
      tmp[j * nr_rowsA +  i] = 0;
    }
  }

  // Number of threads in each thread block                                                                          
  int blockSize = 256; // Make sure this number is good? I don't know how
  // Number of thread blocks in grid                                                                                 
  int gridSize = (int)ceil((float)(nr_rowsA * nr_colsB)/blockSize);
  
  double etMult = 0;
  double etAdd = 0;
  double etAlloc = 0;
  double etBackAlloc = 0;
  double etaddBack = 0;
  for (int i = 0; i < size; i++) {
    gettimeofday(&t1, NULL);
    cudaMemcpy(d_res, tmp, nr_rowsA * nr_colsB * sizeof(long long), cudaMemcpyHostToDevice);
    gettimeofday(&t2, NULL);
    etAlloc += (((t2.tv_sec*uS_PER_SEC)+t2.tv_usec) - ((t1.tv_sec*uS_PER_SEC)+t1.tv_usec))/(float)uS_PER_mS;
    //cudaMemcpy(d_rem, tmp, nr_rowsA * nr_colsB * sizeof(long long), cudaMemcpyHostToDevice);
    for (int j = 0; j < i + 1; j++) {
      gettimeofday(&t1, NULL);
      gpu_blas_mmul(handle, &d_aS[j * nr_rowsA * nr_colsA], &d_bS[(i - j) * nr_colsA * nr_colsB], d_prodRes, nr_rowsA, nr_colsA, nr_colsB);
      cudaThreadSynchronize();
      gettimeofday(&t2, NULL);
      etMult += (((t2.tv_sec*uS_PER_SEC)+t2.tv_usec) - ((t1.tv_sec*uS_PER_SEC)+t1.tv_usec))/(float)uS_PER_mS;
      
      gettimeofday(&t1, NULL);
      vecAdd__wSign<<<gridSize, blockSize>>>(d_prodRes, d_res,  nr_rowsA * nr_colsB);
      cudaThreadSynchronize();
      gettimeofday(&t2, NULL);
      etAdd += (((t2.tv_sec*uS_PER_SEC)+t2.tv_usec) - ((t1.tv_sec*uS_PER_SEC)+t1.tv_usec))/(float)uS_PER_mS;
      // This is safe with overflow until there are 1024 of our own limbs that need to be summed up
      // This case corresponds to a precision of ~20000 bits in GMP
    }
    gettimeofday(&t1, NULL);
    cudaMemcpy(tmp, d_res, nr_rowsA * nr_colsB * sizeof(long long), cudaMemcpyDeviceToHost);
    gettimeofday(&t2, NULL);
    etBackAlloc += (((t2.tv_sec*uS_PER_SEC)+t2.tv_usec) - ((t1.tv_sec*uS_PER_SEC)+t1.tv_usec))/(float)uS_PER_mS;
    
    gettimeofday(&t1, NULL);
    addToGMPMatrix(c, tmp, nr_rowsA, nr_colsB, expA + expB - (i + 2) * ownLimbSize);
    gettimeofday(&t2, NULL);
    etaddBack += (((t2.tv_sec*uS_PER_SEC)+t2.tv_usec) - ((t1.tv_sec*uS_PER_SEC)+t1.tv_usec))/(float)uS_PER_mS;
    //cudaMemcpy(tmp, d_rem, nr_rowsA * nr_colsB * sizeof(long long),cudaMemcpyDeviceToHost);
    //addToGMPMatrix(c, tmp, nr_rowsA, nr_colsB, 2 * exp - (i + 2) * ownLimbSize + (INT64L - 1));
    #pragma omp parallel for schedule(dynamic)
    for(int k = 0; k < nr_rowsA; ++k){
      for(int l = 0; l < nr_colsB; ++l){
	tmp[l *  nr_rowsA + k] = 0;
      }
    }
  }
  printf("Transfer GPU = %fms\n", etTransfer);
  printf("Multiplication GPU = %fms\n", etMult);
  printf("Addition GPU = %fms\n", etAdd);
  printf("Alloc of zero to GPU = %fms\n", etAlloc);
  printf("Transfer from GPU to host = %fms\n", etBackAlloc);
  printf("Addition on CPU = %fms\n", etaddBack);
}



void testAddToMpf() {
  mpf_set_default_prec(300);
  mpf_class x("3.14159265358");
  long long a = 12345;
  long long b = -4321899;
  cout.precision(300);
  cout << x << endl;
  addToMpf(x.get_mpf_t(), a, 62);
  cout << x << endl;
  addToMpf(x.get_mpf_t(), b, -4);
  cout << x << endl;
}
 
void allocateAndGenerateRandomMatrix(mpf_class *&randA, int nr_rowsA, int nr_colsA) {
  randA = new mpf_class[nr_rowsA * nr_colsA];
  generateRandomGMPMatrix(randA, nr_rowsA, nr_colsA);
}

void testGenerateLongsFromGMP() {
  std::cout << "*****************************" << std::endl;
  std::cout << "*** TESTING GENERATING LONGS FROM AN MPF_CLASS ***" << std::endl;
  mpf_class f("-3.23124");
  mpf_class fCopy = f;
  long long *mLimbs;
  int noOfmLimbs = 0;
  generateLongsFromGMP(f, mLimbs, noOfmLimbs, 7, 10);    
  free(mLimbs);
  std::cout << "*****************************" << std::endl;
}

void testLongToGMP() {
  std::cout << "*****************************" << std::endl;
  std::cout << "*** TESTING GENERATING MPF_CLASS FROM LONGS ***" << std::endl;
  mpf_class f("-3.23124");
  mp_exp_t exp;
  mpf_class getResBack;

  long long *mLimbs;
  int noOfmLimbs = 0;
  generateLongsFromGMP(f, mLimbs, noOfmLimbs, 7, 10);

  longToGMP(getResBack, mLimbs, noOfmLimbs, 7, 10);                                                                         
  std::cout << getResBack.get_str(exp, 2) << std::endl;                                                                      
  std::cout << getResBack - f << std::endl;                                                                                
  free(mLimbs);                          
  std::cout << "*****************************" << std::endl;                                                                
}

void testAddToGMP() {
  std::cout << "*****************************" << std::endl;
  std::cout << "*** TESTING ADDITION BETWEEN MPF_CLASS AND INT64 ***" << std::endl;
  mpf_class f("-3.23124");
  mp_exp_t exp;
  std::cout << "Binary..." << f.get_str(exp, 2) << std::endl;                                                          
                
  long long toAdd = 11232145214524552;                                                                                     
                            
  mpf_class result = addToGMP(f, toAdd, -5);                                                                                
                            
  std::cout << "Binary added..." << result.get_str(exp, 2) << std::endl;                                                    
                            
  std::bitset<64> tr(toAdd);                                                                                                
  std::cout << "what to add ..." << tr << std::endl;                                                                        
             
  std::cout << "Binary added..." << result.get_str(exp, 10) << std::endl;   
  std::cout << "*****************************" << std::endl;
}

void testNumberMultiplicationBasecase() {
  std::cout << "*****************************" << std::endl;
  std::cout << "*** TESTING NUMBER MULTIPLICATION BETWEEN TWO MPF_CLASS VARS ***" << std::endl;
  mpf_class a1("0.23124");                                                                                             
  mpf_class a2("0.251253124");                                                                                              
                            
  mpf_class a3;                                                                   

  numberMultiplicationBasecase(a3, a2, a1);                                                                                 
                            
  std::cout << "This needs to be 0: " << a3 - (a1 * a2) << std::endl;            
  std::cout << "*****************************" << std::endl;
}

void testGenerateLongMatrixFromGMPMatrix(mpf_class *&randA, long long **&GMPtoLong, 
					 const int nr_rowsA, const int nr_colsA) {
  std::cout << "*****************************" << std::endl;
  std::cout << "*** TESTING GENERATING LONG MATRIX FROM MPF_CLASS MATRIX ***" << std::endl;
  
  allocateAndGenerateRandomMatrix(randA, nr_rowsA, nr_colsA);
  
  int maxExpo;
  int noOfLimbs;
  generateLongMatrixFromGMPMatrix(randA, GMPtoLong, noOfLimbs, nr_rowsA, nr_colsA, maxExpo, 7);
  std::cout << "Generated. Number of limbs: " << noOfLimbs 
	    << "  Maximum exponent: " << maxExpo << std::endl;
  std::cout << "*****************************" << std::endl;
}

void testLongToGMPMatrix(const int nr_rowsA, const int nr_colsA) {
  std::cout << "*****************************" << std::endl;
  std::cout << "*** TESTING GENERATING MPF_CLASS MATRIX FROM LONG MATRIX ***" << std::endl;
  mpf_class *randA;
  long long ** GMPtoLong;
  testGenerateLongMatrixFromGMPMatrix(randA, GMPtoLong, nr_rowsA, nr_colsA);
  mpf_class *randACopy = new mpf_class[nr_rowsA * nr_colsA];

  int maxExpo = 0;
  int noOfLimbs = 0;
  longToGMPMatrix(randACopy, GMPtoLong, noOfLimbs, nr_rowsA, nr_colsA, 7, maxExpo);
  
  std::cout << "Matrix difference should be close to zero:" << std::endl;
  printGMPMatrixDiff(randACopy, randA, nr_rowsA, nr_colsA);
  free(randA); 
  free(GMPtoLong);
  free(randACopy);
  std::cout << "*****************************" << std::endl;
}

void testMatrixMultNoGPU(const int nr_rowsA, const int nr_colsA, const int nr_colsB) {
  std::cout << "*****************************" << std::endl;
  std::cout << "*** TESTING GMP MATRIX MULTIPLICATION NO GPU ***" << std::endl;
  mpf_class *randA, *randB;

  allocateAndGenerateRandomMatrix(randA, nr_rowsA, nr_colsA);
  allocateAndGenerateRandomMatrix(randB, nr_colsA, nr_colsB);
  
  mpf_class *randC = new mpf_class[nr_rowsA * nr_colsB];
  mpf_class *randCNaive = new mpf_class[nr_rowsA * nr_colsB];
  
  long long ** GMPtoLongA;
  long long ** GMPtoLongB;
  matrixMultiplicationBasecase(randC, randA, randB, GMPtoLongA, GMPtoLongB, nr_rowsA, nr_colsA, nr_colsB);    
  matrixProductGMP(randCNaive, randA, randB, nr_rowsA, nr_colsA, nr_colsB);
  std::cout << "Matrix difference should be close to zero:" << std::endl;
  printGMPMatrixDiff(randC, randCNaive, nr_rowsA, nr_colsB);
  free(randA);
  free(randB);
  free(randC);
  free(randCNaive);
  free(GMPtoLongA);
  free(GMPtoLongB);
  std::cout << "*****************************" << std::endl;
}

void testVectorAddOnGPU(const int len) {
  std::cout << "*****************************" << std::endl;
  std::cout << "*** TESTING VECTOR ADDITION ON GPU ***" << std::endl;
  unsigned long long *d_a;
  unsigned long long *d_b;
  unsigned long long *d_c;
  
  cudaMalloc(&d_a, len * sizeof(long long));                                                   
  cudaMalloc(&d_b, len * sizeof(long long));                                                   
  cudaMalloc(&d_c, len * sizeof(long long)); 
  
  GPU_fill_rand_vec(d_a, len);                                                                 
  GPU_fill_rand_vec(d_b, len);

  // Number of threads in each thread block                                                                        
  int blockSize = 1024;                                                                                          
  // Number of thread blocks in grid                                                                               
  int gridSize = (int)ceil((float)(len)/blockSize);                                            

  vecAdd<<<gridSize, blockSize>>>(d_a, d_b, d_c, len);                                         
  cudaFree(d_a);
  cudaFree(d_b);
  cudaFree(d_c);
  std::cout << "*****************************" << std::endl;
}


void testMatrixMult_cuBlas(const int nr_rowsA, const int nr_colsA, const int nr_colsB) {
  std::cout << "*****************************" << std::endl;
  std::cout << "*** TESTING GMP MATRIX MULTIPLICATION ON GPU ***" << std::endl;
  timeval t1, t2;
  int nr_rowsB = nr_colsA, nr_rowsC = nr_rowsA, nr_colsC = nr_colsB;
  cublasHandle_t handle;
  cublasCreate(&handle);
  mpf_class *randA, *randB;

  allocateAndGenerateRandomMatrix(randA, nr_rowsA, nr_colsA);
  allocateAndGenerateRandomMatrix(randB, nr_colsA, nr_colsB);
  
  mpf_class *randC = new mpf_class[nr_rowsA * nr_colsB];
  mpf_class *randCNaive = new mpf_class[nr_rowsA * nr_colsB];
  
  int ownLimbSize = DOUBLE_MANT/2 - ceil(log2((double) nr_colsA) / 2);
  int size_aS = 0;
  int size_bS = 0;
  int expA = 0;
  int expB = 0;

  estimateSize(randA, size_aS, expA, nr_rowsA, nr_colsA, ownLimbSize);
  estimateSize(randB, size_bS, expB, nr_colsA, nr_colsB, ownLimbSize);
  
  double *d_aS;
  cudaMalloc(&d_aS, size_aS * nr_rowsA * nr_colsA * sizeof(double));
  double *d_bS;                                                                                                    
  cudaMalloc(&d_bS, size_bS * nr_rowsB * nr_colsB * sizeof(double));                                         
  double *d_prodRes;                                                                                               
  cudaMalloc(&d_prodRes, nr_rowsC * nr_colsC * sizeof(double));                                                  
  long  long *d_res;                                                                                               
  cudaMalloc(&d_res, nr_rowsC * nr_colsC * sizeof(long long));                                                   
                                                                                                                      
  print_memory();                                                                                                  
  // Allocate the memory for temporary arrays                                                                      
  double * tmpTransferLongToGMP = (double *)malloc(max(nr_rowsA * nr_colsA, nr_rowsB * nr_colsB) * sizeof(double));                                                                                                                 
  int * sizeMatrix = (int *)malloc(max(nr_rowsA * nr_colsA, nr_rowsB * nr_colsB) * sizeof(int));               
  int * realExpMatrix = (int *)malloc(max(nr_rowsA * nr_colsA, nr_rowsB * nr_colsB) * sizeof(int));            
  int * signMatrix = (int *)malloc(max(nr_rowsA * nr_colsA, nr_rowsB * nr_colsB) * sizeof(int));               
  long long *tmp = (long long *)malloc(nr_rowsC * nr_colsC * sizeof(long long));                                 
  
  gettimeofday(&t1, NULL);                                                                                         
  matrixMultiplicationBasecase_cuBlas(handle, randC, randA, randB,                                              
				      d_aS, d_bS, tmpTransferLongToGMP, tmp, sizeMatrix, realExpMatrix, signMatrix,         
				      d_prodRes, d_res,  nr_rowsA, nr_colsA, nr_colsB);                         
  gettimeofday(&t2, NULL);                                                                                         
  double etGPU = (((t2.tv_sec*uS_PER_SEC)+t2.tv_usec) - ((t1.tv_sec*uS_PER_SEC)+t1.tv_usec))/(float)uS_PER_mS;     
 
  gettimeofday(&t1, NULL);                                                                                        
  matrixProductGMP(randCNaive, randA, randB, nr_rowsA, nr_colsA, nr_colsB);
  gettimeofday(&t2, NULL);
  double etCPU = (((t2.tv_sec*uS_PER_SEC)+t2.tv_usec) - ((t1.tv_sec*uS_PER_SEC)+t1.tv_usec))/(float)uS_PER_mS;
  
  std::cout << "Matrix difference should be close to zero:" << std::endl;
  printGMPMatrixDiff(randC, randCNaive, 10, 10);                                        
  
  std::cout << "Timing: " << std::endl;                                                                             
  
  printf("GPU optimized GMP = %fms\n", etGPU);                                                                     
  printf("CPU naive GMP = %fms\n", etCPU);                                                                         
  print_memory();

  cublasDestroy(handle);
  free(randA);
  free(randB);
  free(randC);
  free(randCNaive);
  free(tmpTransferLongToGMP);
  free(tmp);
  free(sizeMatrix);
  free(realExpMatrix);
  free(signMatrix);

  cudaFree(d_aS);
  cudaFree(d_bS);
  cudaFree(d_prodRes);
  cudaFree(d_res);
  std::cout << "*****************************" << std::endl;
}

void testMatrixMultSymm_cuBlas(const int nr_rowsA, const int nr_colsA) {
  std::cout << "*****************************" << std::endl;
  std::cout << "*** TESTING GMP SYMMETRIC MATRIX MULTIPLICATION ON GPU ***" << std::endl;
  timeval t1, t2;
  int nr_rowsC = nr_rowsA, nr_colsC = nr_rowsA;
  cublasHandle_t handle;
  cublasCreate(&handle);
  
  mpf_class *randA;
  allocateAndGenerateRandomMatrix(randA, nr_rowsA, nr_colsA);
    
  mpf_class *randC = new mpf_class[nr_rowsA * nr_rowsA];
  mpf_class *randCNaive = new mpf_class[nr_rowsA * nr_rowsA];
  
  int ownLimbSize = DOUBLE_MANT/2 - ceil(log2((double) nr_colsA) / 2);
  int size_aS = 0;
  int expA = 0;
  estimateSize(randA, size_aS, expA, nr_rowsA, nr_colsA, ownLimbSize);
  
  double *d_aS;
  cudaMalloc(&d_aS, size_aS * nr_rowsA * nr_colsA * sizeof(double));
  double *d_prodRes;                                                                                               
  cudaMalloc(&d_prodRes, nr_rowsC * nr_colsC * sizeof(double));                                                  
  long  long *d_res;                                                                                               
  cudaMalloc(&d_res, nr_rowsC * nr_colsC * sizeof(long long));                                                   
                                                                                                                   
 
  print_memory();
                                                                                                  
  // Allocate the memory for temporary arrays                                                                      
  double * tmpTransferLongToGMP = (double *)malloc(nr_rowsA * nr_colsA * sizeof(double));                            
                                                                                    
  int * sizeMatrix = (int *)malloc(nr_rowsA * nr_colsA * sizeof(int));               
  int * realExpMatrix = (int *)malloc(nr_rowsA * nr_colsA * sizeof(int));            
  int * signMatrix = (int *)malloc(nr_rowsA * nr_colsA * sizeof(int));               
  long long *tmp = (long long *)malloc(nr_rowsC * nr_colsC * sizeof(long long));                                 
  
  gettimeofday(&t1, NULL);                                                                                         
  matrixMultSymmBasecase_cuBlas(handle, randC, randA,                                              
				d_aS, tmpTransferLongToGMP, tmp, sizeMatrix, realExpMatrix, signMatrix,        
				d_prodRes, d_res, nr_rowsA, nr_colsA);                         
  gettimeofday(&t2, NULL);                                                                                         
  double etGPU = (((t2.tv_sec*uS_PER_SEC)+t2.tv_usec) - ((t1.tv_sec*uS_PER_SEC)+t1.tv_usec))/(float)uS_PER_mS;     
 
  gettimeofday(&t1, NULL);                                                                                        
  matrixSquareIntoBlockGMP(randA, randCNaive, nr_rowsA, nr_colsA); 
  gettimeofday(&t2, NULL);
  double etCPU = (((t2.tv_sec*uS_PER_SEC)+t2.tv_usec) - ((t1.tv_sec*uS_PER_SEC)+t1.tv_usec))/(float)uS_PER_mS;
 
  std::cout << "Matrix difference should be close to zero:" << std::endl;
  printGMPMatrixDiff(randC, randCNaive, 10, 10);                                        
  
  std::cout << "Timing: " << std::endl;                                                                            
  printf("GPU optimized GMP = %fms\n", etGPU);                                                                     
  printf("CPU naive GMP = %fms\n", etCPU);                                                                         
  print_memory();
  
  cublasDestroy(handle);
  
  free(randA);
  free(randC);
  free(randCNaive);
  free(tmpTransferLongToGMP);
  free(tmp);
  free(sizeMatrix);
  free(realExpMatrix);
  free(signMatrix);

  cudaFree(d_aS);
  cudaFree(d_prodRes);
  cudaFree(d_res);
  std::cout << "*****************************" << std::endl;
}

void testCholeskyOnCPU () {
  std::cout << "*****************************" << std::endl;
  std::cout << "*** TESTING CHOLESKY DECOMPOSITION NO GPU ***" << std::endl;
  std::cout << "*****************************" << std::endl;
}

void testCholeskyOnGPU() {
  std::cout << "*****************************" << std::endl;
  std::cout << "*** TESTING CHOLESKY DECOMPOSITION ON GPU ***" << std::endl;
  std::cout << "*****************************" << std::endl;
}

void testToom2() {
  std::cout << "*****************************" << std::endl;
  std::cout << "*** TESTING TOOM2 ***" << std::endl;
  std::cout << "*****************************" << std::endl;
}

void testToom2Symm() {
  std::cout << "*****************************" << std::endl;
  std::cout << "*** TESTING TOOM2SYMM ***" << std::endl;
  std::cout << "*****************************" << std::endl;
}

void testToom3() {
  std::cout << "*****************************" << std::endl;
  std::cout << "*** TESTING TOOM3 ***" << std::endl;
  std::cout << "*****************************" << std::endl;
}

void testToom3Symm() {
  std::cout << "*****************************" << std::endl;
  std::cout << "*** TESTING TOOM3SYMM ***" << std::endl;
  std::cout << "*****************************" << std::endl;
}

void testMatrixMultiplicationWithToom2() {
  std::cout << "*****************************" << std::endl;
  std::cout << "*** TESTING TOOM2 MATRIX MULTIPLICATION ***" << std::endl;
  std::cout << "*****************************" << std::endl;
}

void testMatrixMultiplicationSymmWithToom2() {
  std::cout << "*****************************" << std::endl;
  std::cout << "*** TESTING TOOM2 WITH SYMM MATRIX MULTIPLICATION ***" << std::endl;
  std::cout << "*****************************" << std::endl;
}

void testMatrixMultiplicationWithToom3() {
  std::cout << "*****************************" << std::endl;
  std::cout << "*** TESTING TOOM3 MATRIX MULTIPLICATION ***" << std::endl;
  std::cout << "*****************************" << std::endl;
}

void testMatrixMultiplicationSymmWithToom3() {
  std::cout << "*****************************" << std::endl;
  std::cout << "*** TESTING TOOM3 SYMM MATRIX MULTIPLICATION ***" << std::endl;
  std::cout << "*****************************" << std::endl;
}


void lucaGiantTest(int argc, char *argv[]) {
    print_memory();
    int val1, val2; 

     if (argc >= 2)
     {
	std::istringstream iss1( argv[1] );
	std::istringstream iss2( argv[2] );
        if (iss1 >> val1)
        {
            // Conversion successful
        }
	if (iss2 >> val2)
	  {
            // Conversion successful                                     
	  }
     }
     mpf_set_default_prec(300);
     int nr_rowsA, nr_colsA, nr_colsB;
     nr_rowsA = nr_colsB = val1;
     nr_colsA = val2;
     
     testGenerateLongsFromGMP();
     testLongToGMP();
     testAddToGMP();
     testNumberMultiplicationBasecase();
     testLongToGMPMatrix(nr_rowsA, nr_colsA);
     testMatrixMultNoGPU(nr_rowsA, nr_colsA, nr_colsB);
     testVectorAddOnGPU(nr_rowsA * nr_colsA);
     testMatrixMult_cuBlas(nr_rowsA, nr_colsA, nr_colsB);
     testMatrixMultSymm_cuBlas(nr_rowsA, nr_colsA);
 }


void choleskyTest() {

}

int main(int argc, char *argv[]) {
  lucaGiantTest(argc, argv);
  //testAddToMpf();
}
