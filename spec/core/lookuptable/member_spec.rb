require File.dirname(__FILE__) + '/../../spec_helper'
require File.dirname(__FILE__) + '/shared/has_key'

describe "Rubinius::LookupTable#member?" do
  it_behaves_like :lookuptable_has_key, :member?
end
