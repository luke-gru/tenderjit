# frozen_string_literal: true

require "helper"

class TenderJIT
  class BranchunlessTest < JITTest
    def compare a, b
      if a < b
        :cool
      else
        :other_cool
      end
    end

    def test_branchunless
      compile method(:compare), recv: self
      assert_equal 1, jit.compiled_methods
      assert_equal 0, jit.executed_methods
      assert_equal 0, jit.exits

      jit.enable!
      v = compare(1, 2)
      jit.disable!
      assert_equal :cool, v

      assert_equal 1, jit.compiled_methods
      assert_equal 1, jit.executed_methods
      assert_equal 0, jit.exits
    end

    #def test_branchunless_other_side
      #compile method(:compare), recv: self
      #assert_equal 1, jit.compiled_methods
      #assert_equal 0, jit.executed_methods
      #assert_equal 0, jit.exits

      #jit.enable!
      #v = compare(2, 1)
      #jit.disable!
      #assert_equal :other_cool, v

      #assert_equal 1, jit.compiled_methods
      #assert_equal 1, jit.executed_methods
      #assert_equal 0, jit.exits
    #end

    def compare_and_use a, b
      (a < b ? 5 : 6) + 5
    end

    def test_phi_function_for_stack
      skip "not working"
      compile method(:compare_and_use), recv: self
      assert_equal 1, jit.compiled_methods
      assert_equal 0, jit.executed_methods
      assert_equal 0, jit.exits

      jit.enable!
      v1 = compare_and_use(1, 2)
      v2 = compare_and_use(2, 1)
      jit.disable!
      assert_equal 10, v1
      assert_equal 11, v2

      assert_equal 1, jit.compiled_methods
      assert_equal 2, jit.executed_methods
      assert_equal 0, jit.exits
    end

    def check_truth x
      if x
        :true
      else
        :false
      end
    end

    #def test_nil_and_false_are_false
      #compile method(:check_truth), recv: self
      #assert_equal 1, jit.compiled_methods

      #jit.enable!
      #v1 = check_truth(false)
      #v2 = check_truth(nil)
      #v3 = check_truth(true)
      #v4 = check_truth(0)
      #jit.disable!

      #assert_equal :false, v1
      #assert_equal :false, v2

      #assert_equal :true, v3
      #assert_equal :true, v4

      #assert_equal 4, jit.executed_methods
    #end
  end
end
