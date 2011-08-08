require 'spec_helper'

describe GridRestTest do
  it "should respond to grid_rest_get" do
    GridRestTest.should respond_to :grid_rest_get 
  end

  it "should give 404 on nonexistent" do
    r = GridRestTest.grid_rest_get('nonexistent')
    r.code.should == 404
    r.type.should == 'HTTPNotFound'
  end
end

