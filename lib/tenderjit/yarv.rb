require "tenderjit/util"
require "tenderjit/linked_list"
require "tenderjit/ir/operands"
require "tenderjit/basic_block"
require "tenderjit/cfg"

class TenderJIT
  class YARV
    class Local < Util::ClassGen.pos(:name, :ops)
      def variable?; true; end
    end

    class Instruction < Util::ClassGen.pos(:op, :pc, :insn, :opnds, :stack_pos, :number)
      include LinkedList::Element

      NONE = IR::Operands::None.new

      attr_writer :number

      def phi?; false; end

      def put_label?
        op == :put_label
      end

      def label
        raise unless put_label?
        insn
      end

      def jump?
        op == :branchunless || op == :branchif || op == :jump
      end

      def has_jump_target?
        op == :branchunless || op == :branchif || op == :jump
      end

      def unconditional_jump?
        op == :jump
      end

      def return?
        op == :leave
      end

      def used_variables
        return unless op == :getlocal
        [opnds]
      end

      def set_variable
        return unless op == :setlocal
        opnds
      end

      def arg1
        if op == :getlocal
          opnds
        else
          NONE
        end
      end

      def arg2
        NONE
      end

      def out
        if op == :setlocal
          opnds
        else
          NONE
        end
      end

      def target_label
        out = opnds.first
        return out if out.label?
        raise "not a jump instruction"
      end

      def to_s
        if op == :getlocal || op == :setlocal
          "#{number} #{op}\t#{opnds.name}"
        else
          "#{number} #{op}\t#{opnds.map(&:to_s).join("\t")}"
        end
      end
    end

    class Label < Util::ClassGen.pos(:name)
      def label?; true; end

      def to_s
        "LABEL(#{name})"
      end
    end

    def self.dump_insns insns, ansi: true
      insns.map { |insn| insn.to_s }.join("\\l") + "\\l"
    end

    def self.vars set
      set.to_a.map(&:name).inspect
    end

    def initialize iseq, locals
      @insn_head = LinkedList::Head.new
      @instructions = @insn_head
      @label_map = {}
      @locals = locals.reverse
      @local_names = {}
    end

    def basic_blocks
      BasicBlock.build @insn_head, self, false
    end

    def cfg
      CFG.new basic_blocks, YARV
    end

    JUMP = RubyVM::MJIT::INSNS.values.find { |insn| insn.name == :jump }

    def insert_jump node, label
      jump = new_insn :jump, node.pc, JUMP, [label]
      node.insert jump
    end

    def peephole_optimize!
      @insn_head.each do |insn|
        # putobject
        # pop
        if insn.op == :putobject && insn._next.op == :pop
          insn._next.unlink
          insn.unlink
        end

        if insn.op == :jump && !insn.prev.head? && insn.prev.op == :jump
          insn.prev.unlink
        end
      end
    end

    def handle pc, insn, operands
      if label = @label_map[pc]
        put_label pc, label
      end
      send insn.name, pc, insn, operands
    end

    def getlocal_WC_0 pc, insn, ops
      getlocal pc, insn, [ops[0], 0]
    end

    def getlocal pc, insn, ops
      add_insn __method__, pc, insn, local_name(ops)
    end

    def opt_eq pc, insn, ops
      add_insn __method__, pc, insn, ops
    end

    def setlocal_WC_0 pc, insn, ops
      setlocal pc, insn, [ops[0], 0]
    end

    def setlocal pc, insn, ops
      add_insn __method__, pc, insn, local_name(ops)
    end

    def opt_plus pc, insn, ops
      add_insn __method__, pc, insn, ops
    end

    def opt_minus pc, insn, ops
      add_insn __method__, pc, insn, ops
    end

    def leave pc, insn, ops
      add_insn __method__, pc, insn, ops
    end

    def putobject pc, insn, ops
      add_insn __method__, pc, insn, ops
    end

    def putobject_INT2FIX_1_ pc, insn, ops
      putobject pc, insn, [1]
    end

    def putnil pc, insn, ops
      putobject pc, insn, [nil]
    end

    def pop pc, insn, ops
      add_insn __method__, pc, insn, ops
    end

    def opt_lt pc, insn, ops
      add_insn __method__, pc, insn, ops
    end

    def opt_gt pc, insn, ops
      add_insn __method__, pc, insn, ops
    end

    def newarray pc, insn, ops
      add_insn __method__, pc, insn, ops
    end

    def branchunless pc, insn, ops
      offset = ops.first

      # offset is PC + dest
      dest_pc = pc + offset + 2 # branchunless is 2 wide

      label = insert_label_at_pc pc, dest_pc

      add_insn __method__, pc, insn, [label]
    end

    def branchif pc, insn, ops
      offset = ops.first

      # offset is PC + dest
      dest_pc = pc + offset + 2 # branchunless is 2 wide

      label = insert_label_at_pc pc, dest_pc

      add_insn __method__, pc, insn, [label]
    end

    def put_label pc, label
      add_insn __method__, pc, label, [label]
    end

    def jump pc, insn, ops
      offset = ops.first

      # offset is PC + dest
      dest_pc = pc + offset + 2 # branchunless is 2 wide

      label = insert_label_at_pc pc, dest_pc

      add_insn __method__, pc, insn, [label]
    end

    private

    def insert_label_at_pc current_pc, dest_pc
      label = @label_map[dest_pc] ||= Label.new(dest_pc)

      if dest_pc < current_pc
        insn = @instructions

        while insn.pc > dest_pc
          insn = insn.prev
        end

        before = insn.prev

        put_label = Instruction.new :put_label, insn.pc, label, [label]
        put_label.append insn
        before.append put_label
      end

      label
    end

    def add_insn name, pc, insn, opnds
      insn = new_insn name, pc, insn, opnds
      @instructions = @instructions.append insn
    end

    def new_insn name, pc, insn, opnds
      Instruction.new name, pc, insn, opnds
    end

    def local_name ops
      unless @local_names[ops]
        idx, env = *ops
        if env == 0
          @local_names[ops] = Local.new(@locals[idx - 3], ops)
        else
          @local_names[ops] = Local.new(@local_names.size, ops)
        end
      end
      @local_names[ops]
    end
  end
end
