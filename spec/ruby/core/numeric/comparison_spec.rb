require File.expand_path('../../../spec_helper', __FILE__)
require File.expand_path('../fixtures/classes', __FILE__)

describe "Numeric#<=>" do
  before(:each) do
    @obj = NumericSub.new
  end

  it "returns 0 if self equals other" do
    (@obj <=> @obj).should == 0
  end
  
  it "returns nil if self does not equal other" do
    (@obj <=> NumericSub.new).should == nil
    (@obj <=> 10).should == nil
    (@obj <=> -3.5).should == nil
    (@obj <=> bignum_value).should == nil
  end
end