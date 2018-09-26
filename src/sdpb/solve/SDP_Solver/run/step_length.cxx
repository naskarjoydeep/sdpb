#include "../../SDP_Solver.hxx"

// min(gamma \alpha(M, dM), 1), where \alpha(M, dM) denotes the
// largest positive real number such that M + \alpha dM is positive
// semidefinite.
//
// \alpha(M, dM) is computed with a Cholesky decomposition M = L L^T.
// The eigenvalues of M + \alpha dM are equal to the eigenvalues of 1
// + \alpha L^{-1} dM L^{-T}.  The correct \alpha is then -1/lambda,
// where lambda is the smallest eigenvalue of L^{-1} dM L^{-T}.
//
// Inputs:
// - MCholesky = L, the Cholesky decomposition of M (M itself is not needed)
// - dM, a Block_Diagonal_Matrix with the same structure as M
// Workspace:
// - MInvDM (NB: overwritten when computing minEigenvalue)
// - eigenvalues, a Vector of eigenvalues for each block of M
// Output:
// - min(\gamma \alpha(M, dM), 1) (returned)

El::BigFloat step_length(const Block_Diagonal_Matrix &MCholesky,
                         const Block_Diagonal_Matrix &dM,
                         const El::BigFloat &gamma,
                         const std::string &timer_name,
                         Timers &timers)
{
  auto &step_length_timer(
        timers.add_and_start(timer_name));
  // MInvDM = L^{-1} dM L^{-T}, where M = L L^T
  Block_Diagonal_Matrix MInvDM(dM);
  lower_triangular_inverse_congruence(MCholesky, MInvDM);
  const El::BigFloat lambda(min_eigenvalue(MInvDM));
  step_length_timer.stop();
  if(lambda > -gamma)
    {
      return 1;
    }
  else
    {
      return -gamma / lambda;
    }
}
