require "set"
require "tenderjit/error"

class TenderJIT
  class RegisterAllocator
    class Spill < Error; end
    class DoubleFree < Error; end
    class OutsideLiveRange < Error; end

    attr_reader :scratch_regs

    class BorrowedRegister
      def initialize reg
        @reg = reg
      end

      def unwrap; @reg; end

      def borrowed?; true; end
    end

    class OwnedRegister
      def initialize reg
        @reg = reg
      end

      def unwrap; @reg; end

      def borrowed?; false; end
    end

    def initialize param_regs, scratch_regs
      @parameter_registers = param_regs.map { |x| OwnedRegister.new(x) }
      @scratch_regs        = Set.new(scratch_regs.map { OwnedRegister.new(_1) })
      @freelist            = @scratch_regs.to_a
      @borrow_list         = []
    end

    def ensure virt, from, to
      if virt.physical_register
        virt.physical_register
      else
        if virt.param?
          virt.physical_register = @parameter_registers[virt.name]
        else
          alloc virt, from, to
        end
      end
    end

    def lend_until phys, i
      @borrow_list << [phys, i]
      false
    end

    def free r, phys
      @active.delete r

      return true if phys.borrowed?

      if @freelist.include?(phys)
        msg = "Physical register #{phys.unwrap.to_i} freed twice"
        raise DoubleFree, msg
      end

      if @scratch_regs.include? phys
        @freelist.push phys
      end

      true
    end

    def allocate ir
      i = 0

      active = Set.new

      ir.each_instruction do |insn|
        # vr == "virtual register"
        # pr == "physical register"

        vr1 = insn.arg1
        vr2 = insn.arg2
        vr3 = insn.out

        # ensure we have physical registers for the arguments.
        # `ensure` may not return a physical register in the case where
        # the virtual register is actually a label or a literal value
        begin
          active.delete vr1
          active.delete vr2
          active.delete vr3

          active.each do |vr|
            if vr.free(self, i)
              active.delete(vr)
            end
          end

          pr1 = vr1.ensure(self, i)
          pr2 = vr2.ensure(self, i)

          # Free the physical registers if they're not used after this
          if vr1 == vr2
            active << vr1 unless vr1.free(self, i)
          else
            active << vr2 unless vr2.free(self, i)
            active << vr1 unless vr1.free(self, i)
          end

          # Allocate a physical register for the output virtual register
          pr3 = vr3.ensure(self, i)

          # Free the output register if it's not used after this
          active << vr3 unless vr3.free(self, i)
        rescue TenderJIT::Error
          puts
          puts ir.dump_usage i
          raise
        end

        i += 1
      end
    end

    private

    def alloc r, from, to
      phys = nil
      if !@borrow_list.empty?
        reg = @borrow_list.find_all { |_, next_use|
          next_use > to
        }.sort_by { |reg, next_use| next_use - to }.first
        @borrow_list.delete reg
        phys = BorrowedRegister.new(reg.first.unwrap)
      end

      phys ||= @freelist.pop

      if phys
        r.physical_register = phys
      else
        raise Spill, "Spill!"
      end
    end
  end
end
