# encoding: utf-8

require 'spec_helper'

describe Foil::Path do

  it 'has a length' do
    Foil::Path.new("/foo").length.should == 2
    Foil::Path.new("/foo/bar").length.should == 3
    Foil::Path.new("/foo/bar/baz").length.should == 4
  end

  it 'ignores slash at end' do
    Foil::Path.new("/foo/bar/").should == Foil::Path.new("/foo/bar")
    Foil::Path.new("/foo/bar//").should == Foil::Path.new("/foo/bar")
  end

  it 'implements #to_s' do
    Foil::Path.new("/foo/bar").to_s.should == '/foo/bar'
    Foil::Path.new("/foo/bar/").to_s.should == '/foo/bar'
  end

  it 'implements #first' do
    Foil::Path.new("/foo/bar").first.should == ''
    Foil::Path.new("foo/bar").first.should == 'foo'
  end

  it 'can be absolute or relative' do
    Foil::Path.new("/foo/bar").root?.should == true
    Foil::Path.new("/foo/bar").first.should == ''
    Foil::Path.new("foo/bar").root?.should == false
  end

  it 'can descend into the next component' do
    path = Foil::Path.new("foo/bar")
    path.descend.should == Foil::Path.new('bar')
    path.descend.descend.should == nil
  end

  it 'can be relative to a parent' do
    path = Foil::Path.new("foo/bar")
    path.descend.parent == Foil::Path.new('foo/bar')
    path.descend.absolute == Foil::Path.new('foo/bar')
  end

  it 'can copy itself' do
    path = Foil::Path.new("/foo/bar")
    other = Foil::Path.new(path)
    other.should == path
  end

  it 'implements #each' do
    components = []
    path = Foil::Path.new("foo/bar")
    path.each { |component| components << component }
    components.should == ['foo', 'bar']
  end

  it 'may be joined with another path' do
    path = Foil::Path.new("/foo/bar")
    path.join(Foil::Path.new("baz")) == Foil::Path.new("/foo/bar/baz")
    path.join('baz') == Foil::Path.new("/foo/bar/baz")
  end

  it 'may be joined with another relative path' do
    a = Foil::Path.new("/foo")
    b = a.join("bar/baz")
    c = b.descend
    c.absolute == Foil::Path.new('/foo/bar/baz')
  end

end
