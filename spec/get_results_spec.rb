require 'spec_helper'

describe GridRestTest do
  it "should respond to grid_rest_get" do
    GridRestTest.should respond_to :grid_rest_get 
  end

  it "should give valid response" do
    r = GridRestTest.grid_rest_get('search.json', :q => 'grid_rest')
    r.should be_valid
    r.should be_kind_of Hash
  end
end

