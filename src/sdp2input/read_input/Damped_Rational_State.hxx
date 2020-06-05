#pragma once

#include "../../Vector_State.hxx"
#include "../../Number_State.hxx"
#include "../Damped_Rational.hxx"

#include <libxml2/libxml/parser.h>
#include <vector>
#include <string>
#include <stdexcept>

using namespace std::string_literals;
struct Damped_Rational_State
{
  std::string name;
  bool inside = false;
  // TODO: Fix duplication
  // XML
  bool finished_constant = false, finished_base = false;
  // JSON
  bool parsing_constant = false, parsing_base = false,
       parsing_polynomial = false;
  Damped_Rational value;
  Number_State<Boost_Float> constant_state, base_state;
  Vector_State<Number_State<Boost_Float>> polynomial_state;

  Damped_Rational_State(const std::vector<std::string> &names,
                        const size_t &offset)
      : name(names.at(offset)), constant_state("Number"s),
        base_state("Number"s), polynomial_state({"Function"s, "Number"s})
  {}
  Damped_Rational_State(const std::initializer_list<std::string> &names)
      : Damped_Rational_State(names, 0)
  {}

  bool xml_on_start_element(const std::string &element_name);
  bool xml_on_end_element(const std::string &element_name);
  bool xml_on_characters(const xmlChar *characters, int length);

  void json_key(const std::string &key);
  void json_string(const std::string &s);
  void json_start_array();
  void json_end_array();
  void json_start_object();
  void json_end_object();
};
