#include "../Block_Diagonal_Matrix.hxx"

// Compute L (lower triangular) such that A = L L^T
void cholesky_decomposition(const Block_Diagonal_Matrix &A,
                            Block_Diagonal_Matrix &L)
{
  for(size_t b = 0; b < A.blocks.size(); b++)
    {
      cholesky_decomposition(A.blocks[b], L.blocks[b]);

      L.blocks_elemental[b] = A.blocks_elemental[b];
      Cholesky(El::UpperOrLowerNS::LOWER, L.blocks_elemental[b]);
    }
}