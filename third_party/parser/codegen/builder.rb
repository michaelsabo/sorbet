#!/usr/bin/env ruby

require 'optparse'

RE_BODY = /struct builder \{(.*?)\}/m
RE_FUNC = /foreign_ptr\(\*(\w+)\)\((.*?)\);/

CHECK_COOKIES = false
TYPE_CONVERSION = {
  "foreign_ptr" => "NodeId",
  "const token*" => "*const TokenPtr",
  "const node_list*" => "*mut NodeListPtr",
  "bool" => "bool",
  "size_t" => "size_t",
  "self_ptr" => "*mut Builder",
}

class Argument
  attr_reader :type
  attr_reader :name

  def initialize(type, name)
    @type = type
    @name = name
  end

  def as_arg
    "#{name}: #{type}"
  end

  def as_safe_arg
    if type == "*mut Builder"
      return "&mut self"
    end

    t = case type
        when "NodeId"
          "Option<Rc<Node>>"
        when "*mut NodeListPtr"
          "Vec<Rc<Node>>"
        when "*const TokenPtr"
          "Option<Token>"
        when "size_t"
          "usize"
        else
          type
        end

    "#{name}: #{t}"
  end

  def as_param
    name
  end

  def convert
    case type
    when "*mut Builder"
      "let #{name} = &mut *#{name}"
    when "NodeId"
      "let #{name} = node_from_c(builder, #{name})"
    when "*mut NodeListPtr"
      "let #{name} = node_list_from_c(builder, #{name})"
    when "*const TokenPtr"
      "let #{name} = token_from_c(#{name})"
    when "size_t"
      "let #{name} = #{name} as usize"
    end
  end
end

class Interface
  attr_reader :name
  attr_reader :args

  def initialize(name, args)
    @name = name
    @args = args
  end

  def arg_block
    args.map {|a| a.as_arg }.join(", ")
  end

  def signature
    "pub #{name}: unsafe extern \"C\" fn(#{arg_block}) -> NodeId"
  end

  def signature_safe
    _args = args.map {|a| a.as_safe_arg }.join(", ")
    "fn #{name}(#{_args}) -> Rc<Node>"
  end

  def definition
    "unsafe extern \"C\" fn #{name}(#{arg_block}) -> NodeId"
  end

  def callsite
    _args = args[1..-1].map {|a| a.as_param }.join(", ")
    "(*#{args.first.name}).#{name}(#{_args})"
  end

  def cookie_check
    "assert_eq!((*#{args.first.name}).cookie, 12345678)"
  end
end

def get_definitions(filename)
  cpp = File.read(filename)
  builder = RE_BODY.match(cpp)

  abort("failed to match 'struct builder' body in #{filename}") unless builder
  defs = builder[1].split("\n").map { |d| d.strip }.reject { |d| d.empty? }

  defs.map do |d|
    match = RE_FUNC.match(d)
    abort("bad definition: '#{d}'") unless match
    method, args = match[1], match[2]

    args = args.split(",").map { |a| a.strip }
    args = args.map do |arg|
      arg = arg.split(' ')
      argname = arg.pop
      ctype = arg.join(' ')
      rstype = TYPE_CONVERSION[ctype]
      abort("unknown C type: #{ctype}") unless rstype

      Argument.new(rstype, argname)
    end

    Interface.new(method, args)
  end
end

def generate_rs(apis, out)
  out.puts "// This file is autogenerated by builder.rb"
  out.puts "// DO NOT MODIFY"
  out.puts "#[repr(C)]"
  out.puts "struct BuilderInterface {"

  apis.each do |api|
    out.puts "\t#{api.signature},"
  end

  out.puts "}"
  out.puts "\n\n"

  apis.each do |api|
    out.puts "#{api.definition} {"
    api.args.each do |arg|
      cv = arg.convert
      out.puts "\t#{cv};" if cv
    end
    out.puts "\t#{api.cookie_check};" if CHECK_COOKIES
    out.puts "\t#{api.callsite}.to_raw(builder)"
    out.puts "}"
  end

  out.puts "\n\n"

  out.puts "static CALLBACKS: BuilderInterface = BuilderInterface {"
  apis.each do |api|
    out.puts "\t#{api.name}: #{api.name},"
  end
  out.puts "};"
end

BUILDER_H = File.join(File.dirname(__FILE__), '..', 'include', 'ruby_parser', 'builder.hh')
OptionParser.new do |opts|
  opts.banner = "Usage: ruby builder.rb [--rs=FILE]"

  opts.on("--rs [FILE]") do |file|
    file = file ? File.open(file, "w") : $stdout
    abort("failed to open '#{file}'") unless file

    apis = get_definitions(BUILDER_H)
    generate_rs(apis, file)
  end
end.parse!
