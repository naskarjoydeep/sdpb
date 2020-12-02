#include "../../../../SDP.hxx"
#include "../../../../Block_Diagonal_Matrix.hxx"
#include "../../../../../Timers.hxx"

// Compute the quantities needed to solve the Schur complement
// equation
//
// {{S, -B}, {B^T, 0}} . {dx, dy} = {r, s}
//
// (where S = SchurComplement, B = FreeVarMatrix), using the method
// described in the manual:
//
// - Compute S using BilinearPairingsXInv and BilinearPairingsY.
//
// - Compute the Cholesky decomposition S' = L' L'^T.
//
// - Form B' = (B U) and compute
//
//   - SchurOffDiagonal = L'^{-1} B
//   - L'^{-1} U
//   - Q = (L'^{-1} B')^T (L'^{-1} B') - {{0, 0}, {0, 1}}
//
// - Compute the LU decomposition of Q.
//
// This data is sufficient to efficiently solve the above equation for
// a given r,s.
//
// Inputs:
// - BilinearPairingsXInv, BilinearPairingsY (these are members of
//   SDPSolver, but we include them as arguments to emphasize that
//   they must be computed first)
// Workspace (members of SDPSolver which are modified by this method
// and not used later):
// - SchurComplement
// Outputs (members of SDPSolver which are modified by this method and
// used later):
// - SchurComplementCholesky
// - SchurOffDiagonal
//

void compute_schur_complement(
  const Block_Info &block_info,
  const Block_Diagonal_Matrix &bilinear_pairings_X_inv,
  const Block_Diagonal_Matrix &bilinear_pairings_Y,
  Block_Diagonal_Matrix &schur_complement, Timers &timers);

void initialize_Q_group(const SDP &sdp, const Block_Info &block_info,
                        const Block_Diagonal_Matrix &schur_complement,
                        Block_Matrix &schur_off_diagonal,
                        Block_Diagonal_Matrix &schur_complement_cholesky,
                        El::DistMatrix<El::BigFloat> &Q_group, Timers &timers);

void synchronize_Q(El::DistMatrix<El::BigFloat> &Q,
                   const El::DistMatrix<El::BigFloat> &Q_group,
                   Timers &timers);

void initialize_schur_complement_solver(
  const Block_Info &block_info, const SDP &sdp,
  const Block_Diagonal_Matrix &bilinear_pairings_X_inv,
  const Block_Diagonal_Matrix &bilinear_pairings_Y, const El::Grid &group_grid,
  Block_Diagonal_Matrix &schur_complement_cholesky,
  Block_Matrix &schur_off_diagonal, El::DistMatrix<El::BigFloat> &Q,
  Timers &timers)
{
  auto &initialize_timer(
    timers.add_and_start("run.step.initializeSchurComplementSolver"));
  // The Schur complement matrix S: a Block_Diagonal_Matrix with one
  // block for each 0 <= j < J.  SchurComplement.blocks[j] has dimension
  // (d_j+1)*m_j*(m_j+1)/2
  //
  Block_Diagonal_Matrix schur_complement(
    block_info.schur_block_sizes, block_info.block_indices,
    block_info.schur_block_sizes.size(), group_grid);

  compute_schur_complement(block_info, bilinear_pairings_X_inv,
                           bilinear_pairings_Y, schur_complement, timers);

  auto &Q_computation_timer(
    timers.add_and_start("run.step.initializeSchurComplementSolver.Q"));

  {
    // FIXME: Change initialize_Q_group to initialize_Q and
    // synchronize inside.
    El::DistMatrix<El::BigFloat> Q_group(Q.Height(), Q.Width(), group_grid);
    initialize_Q_group(sdp, block_info, schur_complement, schur_off_diagonal,
                       schur_complement_cholesky, Q_group, timers);
    synchronize_Q(Q, Q_group, timers);
  }
  Q_computation_timer.stop();

  auto &Cholesky_timer(
    timers.add_and_start("run.step.initializeSchurComplementSolver."
                         "Cholesky"));

  {
    /// There is a bug in El::HermitianEig when there is more than
    /// one level of recursion when computing eigenvalues.  One fix
    /// is to increase the cutoff so that there is no more than one
    /// level of recursion.

    /// An alternate workaround is to compute both eigenvalues and
    /// eigenvectors, but that seems to be significantly slower.
    El::HermitianEigCtrl<El::BigFloat> hermitian_eig_ctrl;
    hermitian_eig_ctrl.tridiagEigCtrl.dcCtrl.cutoff = Q.Height() / 2 + 1;

    /// The default number of iterations is 40.  That is sometimes
    /// not enough, so we bump it up significantly.
    hermitian_eig_ctrl.tridiagEigCtrl.dcCtrl.secularCtrl.maxIterations = 400;

    El::DistMatrix<El::BigFloat, El::VR, El::STAR> eigenvalues(Q.Grid());
    El::HermitianEig(El::UpperOrLowerNS::LOWER, Q, eigenvalues,
                     hermitian_eig_ctrl);

    El::BigFloat max(0), min(std::numeric_limits<double>::max());

    for(int64_t row(0); row!=eigenvalues.Height(); ++row)
      {
        max=std::max(max,El::Abs(eigenvalues.Get(row,0)));
        min=std::min(min,El::Abs(eigenvalues.Get(row,0)));
      }
    if(El::mpi::Rank()==0)
      {
        std::cout << "Q Condition: "
                  << (max / min) << " "
                  << max << " "
                  << min << "\n";
      }
    // exit(0);
  }

  
  Cholesky(El::UpperOrLowerNS::UPPER, Q);
  Cholesky_timer.stop();
  initialize_timer.stop();
}