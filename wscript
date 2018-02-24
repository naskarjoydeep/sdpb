import os

def options(opt):
    opt.load(['compiler_cxx','gnu_dirs','boost','tinyxml2','gmpxx','openmp','cxx17',
              'cblas'])

def configure(conf):
    conf.load(['compiler_cxx','gnu_dirs','boost','tinyxml2','gmpxx','openmp','cxx17',
               'cblas'])
    conf.check_boost(lib='serialization system filesystem timer program_options chrono')

def build(bld):
    default_flags=['-Wall', '-Wextra', '-g', '-O3', '-D___MPACK_BUILD_WITH_GMP___']
    # default_flags=['-g', '-Wall', '-Wextra', '-ansi', '-D___MPACK_BUILD_WITH_GMP___']
    use_packages=['BOOST','tinyxml2','gmpxx','openmp','cxx17','cblas']
    
    mpack_sources=['src/mpack/Rpotrf.cpp',
                   'src/mpack/Rgemm.cpp',
                   'src/mpack/Rorgql.cpp',
                   'src/mpack/Rgetf2.cpp',
                   'src/mpack/Rsterf.cpp',
                   'src/mpack/RgemmParallel.cpp',
                   'src/mpack/Rlarft.cpp',
                   'src/mpack/Rorgtr.cpp',
                   'src/mpack/Rlartg.cpp',
                   'src/mpack/Rorgqr.cpp',
                   'src/mpack/Rlapy2.cpp',
                   'src/mpack/Rpotf2.cpp',
                   'src/mpack/Rgetrf.cpp',
                   'src/mpack/iMlaenv.cpp',
                   'src/mpack/Rsytd2.cpp',
                   'src/mpack/Rger.cpp',
                   'src/mpack/Rlamch.cpp',
                   'src/mpack/Rtrsv.cpp',
                   'src/mpack/Rlae2.cpp',
                   'src/mpack/Rorg2r.cpp',
                   'src/mpack/Rswap.cpp',
                   'src/mpack/Rtrsm.cpp',
                   'src/mpack/Rrot.cpp',
                   'src/mpack/Rgemv.cpp',
                   'src/mpack/iRamax.cpp',
                   'src/mpack/Rlarf.cpp',
                   'src/mpack/Rsyr2k.cpp',
                   'src/mpack/Rsteqr.cpp',
                   'src/mpack/Rlatrd.cpp',
                   'src/mpack/Rlaev2.cpp',
                   'src/mpack/Mxerbla.cpp',
                   'src/mpack/Rnrm2.cpp',
                   'src/mpack/Rscal.cpp',
                   'src/mpack/Rsyrk.cpp',
                   'src/mpack/Rsyr2.cpp',
                   'src/mpack/Rcopy.cpp',
                   'src/mpack/Rrotg.cpp',
                   'src/mpack/Rlasr.cpp',
                   'src/mpack/Rtrmv.cpp',
                   'src/mpack/Rlansy.cpp',
                   'src/mpack/Rpotf2Stabilized.cpp',
                   'src/mpack/Rtrmm.cpp',
                   'src/mpack/Raxpy.cpp',
                   'src/mpack/Rlaswp.cpp',
                   'src/mpack/Rsytrd.cpp',
                   'src/mpack/Rlaset.cpp',
                   'src/mpack/Rlarfb.cpp',
                   'src/mpack/Rsymv.cpp',
                   'src/mpack/Rsyev.cpp',
                   'src/mpack/Rorg2l.cpp',
                   'src/mpack/Rlascl.cpp',
                   'src/mpack/Rlasrt.cpp',
                   'src/mpack/RpotrfStabilized.cpp',
                   'src/mpack/Rdot.cpp',
                   'src/mpack/Mlsame.cpp',
                   'src/mpack/Rgetrs.cpp',
                   'src/mpack/Rlanst.cpp',
                   'src/mpack/Rlassq.cpp',
                   'src/mpack/Rlarfg.cpp']

    bld.stlib(source=mpack_sources,
              target='mpack',
              name='mpack_st',
              includes=['src/mpack'],
              cxxflags=default_flags,
              install_path=bld.env.LIBDIR,
              use=use_packages
              )

    mpmat_sources=['src/mpmat/mpmat_conversion.cpp',
                   'src/mpmat/mpmat_karatsuba.cpp',
                   'src/mpmat/mpmat_operations.cpp',
                   'src/mpmat/mpmat_tests.cpp']

    bld.stlib(source=mpmat_sources,
              target='mpmat',
              name='mpmat_st',
              includes=['src/mpmat'],
              cxxflags=default_flags,
              install_path=bld.env.LIBDIR,
              use=use_packages
              )

    
    # Main executable
    sdpb_sources=['src/SDPSolver.cpp',
                  'src/BlockDiagonalMatrix.cpp',
                  'src/SDPSolverIO.cpp',
                  'src/SDP.cpp',
                  'src/parse.cpp',
                  'src/main.cpp',
                  'src/Matrix.cpp']

    bld.program(source=sdpb_sources,
                target='sdpb',
                includes=['src/mpack'],
                cxxflags=default_flags,
                rpath=[bld.env.LIBDIR],
                use=use_packages + ['mpack_st','mpmat_st'],
                )