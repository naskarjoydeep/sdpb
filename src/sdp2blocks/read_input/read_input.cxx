#include "Input_Parser.hxx"

#include <boost/filesystem.hpp>

namespace
{
  void start_element_callback(void *user_data, const xmlChar *name,
                              const xmlChar **)
  {
    Input_Parser *input_parser = static_cast<Input_Parser *>(user_data);
    input_parser->on_start_element(reinterpret_cast<const char *>(name));
  }

  void end_element_callback(void *user_data, const xmlChar *name)
  {
    Input_Parser *input_parser = static_cast<Input_Parser *>(user_data);
    input_parser->on_end_element(reinterpret_cast<const char *>(name));
  }

  void
  characters_callback(void *user_data, const xmlChar *characters, int length)
  {
    Input_Parser *input_parser = static_cast<Input_Parser *>(user_data);
    input_parser->on_characters(characters, length);
  }

  void warning_callback(void *, const char *msg, ...)
  {
    va_list args;
    va_start(args, msg);
    vprintf(msg, args);
    va_end(args);
  }

  void error_callback(void *, const char *msg, ...)
  {
    va_list args;
    va_start(args, msg);
    vprintf(msg, args);
    va_end(args);
    throw std::runtime_error("Invalid Input file");
  }
}

void read_input(const boost::filesystem::path &input_file,
                std::vector<El::BigFloat> &objectives,
                std::vector<El::BigFloat> &normalization,
                std::vector<Positive_Matrix_With_Prefactor> &matrices)
{
  LIBXML_TEST_VERSION;

  Input_Parser input_parser;

  xmlSAXHandler xml_handlers;
  // This feels unclean.
  memset(&xml_handlers, 0, sizeof(xml_handlers));
  xml_handlers.startElement = start_element_callback;
  xml_handlers.endElement = end_element_callback;
  xml_handlers.characters = characters_callback;
  xml_handlers.warning = warning_callback;
  xml_handlers.error = error_callback;

  if(xmlSAXUserParseFile(&xml_handlers, &input_parser, input_file.c_str()) < 0)
    {
      throw std::runtime_error("Unable to parse input file: "
                               + input_file.string());
    }

  std::swap(objectives, input_parser.objective_state.value);
  std::swap(normalization, input_parser.normalization_state.value);
  std::swap(matrices,
            input_parser.positive_matrices_with_prefactor_state.value);
}
