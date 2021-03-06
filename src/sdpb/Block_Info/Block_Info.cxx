#include "../Block_Info.hxx"

Block_Info::Block_Info(const boost::filesystem::path &sdp_directory,
                       const boost::filesystem::path &checkpoint_in,
                       const size_t &procs_per_node,
                       const size_t &proc_granularity,
                       const Verbosity &verbosity)
{
  read_block_info(sdp_directory);
  std::vector<Block_Cost> block_costs(
    read_block_costs(sdp_directory, checkpoint_in));
  allocate_blocks(block_costs, procs_per_node, proc_granularity, verbosity);
}

Block_Info::Block_Info(const boost::filesystem::path &sdp_directory,
                       const El::Matrix<int32_t> &block_timings,
                       const size_t &procs_per_node,
                       const size_t &proc_granularity,
                       const Verbosity &verbosity)
{
  read_block_info(sdp_directory);
  std::vector<Block_Cost> block_costs;
  for(int64_t block = 0; block < block_timings.Height(); ++block)
    {
      block_costs.emplace_back(block_timings(block, 0), block);
    }
  allocate_blocks(block_costs, procs_per_node, proc_granularity, verbosity);
}
