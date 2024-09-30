# frozen_string_literal: true
#
class TenderJIT
  begin
    C = RubyVM::RJIT.const_get(:C)
  rescue NameError
    $stderr.puts "make sure to give RUBYOPTS='--rjit', otherwise tenderjit won't work!"
    exit! 1
  ensure
    # turn off rjit
    C.rjit_cancel_all("because") if defined?(TenderJIT::C)
  end
  DEBUG = ENV['TENDERJIT_DEBUG'] ? ENV['TENDERJIT_DEBUG'].to_i != 0 : false
end

require "tenderjit/fiddle_hacks"
require "tenderjit/c_funcs"
require "tenderjit/ir"
require "tenderjit/compiler"
require "fiddle/import"
require "hacks"
require "hatstone"
require "etc"
require "ruby_vm/rjit/c_type"
require "ruby_vm/rjit/c_pointer"
require "ruby_vm/rjit/compiler"

class TenderJIT
  INSNS = RubyVM::RJIT.const_get(:INSNS)

  extend Fiddle::Importer

  Stats = struct [
    "uint64_t compiled_methods",
    "uint64_t executed_methods",
    "uint64_t recompiles",
    "uint64_t exits",
    "uint64_t entry_sp",
  ]

  STATS = Stats.malloc(Fiddle::RUBY_FREE)

  def self.disasm buf
    hs = case Util::PLATFORM
         when :arm64
           Hatstone.new(Hatstone::ARCH_ARM64, Hatstone::MODE_ARM)
         when :x86_64
           Hatstone.new(Hatstone::ARCH_X86, Hatstone::MODE_64)
         else
           raise "unknown platform"
         end

    # Now disassemble the instructions with Hatstone
    hs.disasm(buf[0, buf.pos], buf.to_i).each do |insn|
      puts "%#05x %s %s" % [insn.address, insn.mnemonic, insn.op_str]
    end
  end

  def initialize
    @stats = STATS
    @stats.compiled_methods = 0
    @stats.executed_methods = 0
    @stats.recompiles       = 0
    @stats.exits            = 0
    @compiled_iseq_addrs    = []
  end

  # Entry point for compiling a method from RJIT hooks
  def compile method, cfp = C.rb_control_frame_t.new
    iseq = RubyVM::InstructionSequence.of(method)
    return if iseq.nil? # c method

    iseq_internal = Compiler.method_to_iseq_t(method)
    if iseq_internal.nil?
      raise ArgumentError, "expected non-nil"
    end
    compiler = TenderJIT::Compiler.new iseq_internal
    jit_addr = compiler.compile cfp

    @compiled_iseq_addrs << compiler.iseq.to_i
    iseq_internal.body.jit_entry = jit_addr
  end

  # Compile a method.  For example:
  def compile_method method, recv:
    iseq_internal = Compiler.method_to_iseq_t(method)
    cfp = C.rb_control_frame_t.new
    cfp.self = Fiddle.dlwrap(recv)
    compile iseq_internal, cfp
  ensure
    Fiddle.free cfp.to_i
  end

  def uncompile_iseqs
    @compiled_iseq_addrs.each do |addr|
      C.rb_iseq_t.new(addr).body.jit_entry = 0
      C.rb_iseq_t.new(addr).body.variable.coverage = 0
    end
  end

  def uncompile method
    Compiler.uncompile method
  end

  def compiled_methods
    @stats.compiled_methods
  end

  def executed_methods
    @stats.executed_methods
  end

  def exits
    @stats.exits
  end

  def enable!
    RubyVM::RJIT.enable
  end

  def disable!
    #RubyVM::RJIT.pause
  end
end
