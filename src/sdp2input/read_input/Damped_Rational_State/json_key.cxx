#include "../Damped_Rational_State.hxx"

void Damped_Rational_State::json_key(const std::string &key)
{
  if(parsing_constant)
    {
      throw std::runtime_error("Invalid input file.  Unexpected key '" + key
                               + "' inside '" + name + "."
                               + constant_state.name + "'.");
    }
  else if(parsing_base)
    {
      throw std::runtime_error("Invalid input file.  Unexpected key '" + key
                               + "' inside '" + name + "."
                               + base_state.name + "'.");
    }
  else if(parsing_polynomial)
    {
      throw std::runtime_error("Invalid input file.  Unexpected key '" + key
                               + "' inside '" + name + "."
                               + polynomial_state.name + "'.");
    }
  else if(key == constant_state.name)
    {
      parsing_constant = true;
    }
  else if(key == base_state.name)
    {
      parsing_base = true;
    }
  else if(key == polynomial_state.name)
    {
      parsing_polynomial = true;
    }
  else
    {
      throw std::runtime_error("Invalid input file.  Unexpected key '" + key
                               + "' inside '" + name + "'");
    }
}
